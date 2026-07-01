//
//  WebExtensionStorageCleanupPlanner.swift
//  Sumi
//
//  Pure decisions for WebExtension storage cleanup. ExtensionManager remains the
//  owner of WebKit controller calls and filesystem mutation.
//

import Foundation

struct WebExtensionStorageCleanupPlanner {
    enum CleanupMode {
        case pruneDirectoryIfPossible
        case preserveDirectoryForImmediateRuntimeLoad
    }

    struct StorageSnapshot: Equatable {
        let directoryExists: Bool
        let entryNames: [String]
        let hasRegisteredContentScriptsStore: Bool
        let hasLocalStorageStore: Bool
        let hasSyncStorageStore: Bool

        static let stateFileName = "State.plist"
        static let trackedOptionalStoreNames = [
            "RegisteredContentScripts.db",
            "LocalStorage.db",
            "SyncStorage.db",
        ]

        var hasOnlyPrunableEntries: Bool {
            entryNames.allSatisfy {
                WebExtensionStorageCleanupPlanner.isPrunableEntryName($0)
            }
        }

        var hasStoredDataCandidate: Bool {
            entryNames.contains {
                WebExtensionStorageCleanupPlanner.isPrunableEntryName($0) == false
            }
        }

        var missingTrackedOptionalStoreNames: [String] {
            Self.trackedOptionalStoreNames.filter { entryNames.contains($0) == false }
        }

        var isMissingTrackedOptionalStoresOnly: Bool {
            directoryExists && missingTrackedOptionalStoreNames.isEmpty == false
        }
    }

    struct StoreCapabilitySnapshot: Equatable {
        let usesWebKitCompatibilityPrelude: Bool
        let mayTouchDynamicContentScriptStore: Bool
        let mayTouchSyncStorageStore: Bool
        let declaredPermissions: [String]
        let unsupportedAPIs: [String]
    }

    struct ErrorDiagnostic: Equatable {
        let domain: String
        let code: Int
        let localizedDescription: String
        let localizedFailureReason: String
        let debugDescription: String
        let userInfoDescription: String

        private var normalizedPayload: String {
            [
                localizedDescription,
                localizedFailureReason,
                debugDescription,
                userInfoDescription,
            ]
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
            .lowercased()
        }

        var referencesOptionalStore: Bool {
            StorageSnapshot.trackedOptionalStoreNames.contains { storeName in
                normalizedPayload.contains(storeName.lowercased())
            }
        }

        var mentionsMissingFile: Bool {
            normalizedPayload.contains("no such file or directory")
                || normalizedPayload.contains("cannot open file")
                || normalizedPayload.contains("open(")
        }

        var isGenericSQLiteStoreCreationFailure: Bool {
            normalizedPayload.contains("failed to create sqlite store")
        }

        var isWebKitExtensionStorageComputationFailure: Bool {
            domain == "WKWebExtensionDataRecordErrorDomain"
                && code == 3
                && (
                    normalizedPayload.contains("unable to calculate extension storage")
                        || normalizedPayload.contains("unable to delete extension storage")
                )
        }

        var logSummary: String {
            "domain=\(domain) code=\(code) desc=\(localizedDescription) reason=\(localizedFailureReason) debug=\(debugDescription) userInfo=\(userInfoDescription)"
        }
    }

    struct ErrorClassification: Equatable {
        let benignOptionalStoreDiagnostics: [ErrorDiagnostic]
        let actionableDiagnostics: [ErrorDiagnostic]
    }

    static let shared = WebExtensionStorageCleanupPlanner()

    static func isPrunableEntryName(_ entryName: String) -> Bool {
        entryName == StorageSnapshot.stateFileName
    }

    func hasStoredDataCandidate(in snapshot: StorageSnapshot) -> Bool {
        snapshot.hasStoredDataCandidate
    }

    func isPrunableStorageEntry(_ url: URL) -> Bool {
        Self.isPrunableEntryName(url.lastPathComponent)
    }

    func storeCapabilitySnapshot(
        for manifest: [String: Any],
        unsupportedAPIs: Set<String>
    ) -> StoreCapabilitySnapshot {
        let permissions = Set((manifest["permissions"] as? [String] ?? []).map {
            $0.lowercased()
        })

        return StoreCapabilitySnapshot(
            usesWebKitCompatibilityPrelude: false,
            mayTouchDynamicContentScriptStore: permissions.contains("scripting"),
            mayTouchSyncStorageStore: permissions.contains("storage"),
            declaredPermissions: permissions.sorted(),
            unsupportedAPIs: unsupportedAPIs.sorted()
        )
    }

    func classifyCleanupErrors(
        _ errors: [Error],
        extensionId: String,
        preCleanupSnapshot: StorageSnapshot,
        postCleanupSnapshot: StorageSnapshot
    ) -> ErrorClassification {
        let diagnostics = errors.map(makeErrorDiagnostic)
        let hasNonOptionalFailureSignals = diagnostics.contains { diagnostic in
            diagnostic.referencesOptionalStore == false
                && diagnostic.isGenericSQLiteStoreCreationFailure == false
                && diagnostic.isWebKitExtensionStorageComputationFailure == false
        }

        let benignOptionalStoreDiagnostics = diagnostics.filter { diagnostic in
            isBenignMissingOptionalStoreError(
                diagnostic,
                extensionId: extensionId,
                preCleanupSnapshot: preCleanupSnapshot,
                postCleanupSnapshot: postCleanupSnapshot,
                hasNonOptionalFailureSignals: hasNonOptionalFailureSignals
            )
        }
        let actionableDiagnostics = diagnostics.filter { diagnostic in
            benignOptionalStoreDiagnostics.contains(diagnostic) == false
        }

        return ErrorClassification(
            benignOptionalStoreDiagnostics: benignOptionalStoreDiagnostics,
            actionableDiagnostics: actionableDiagnostics
        )
    }

    func makeErrorDiagnostic(_ error: Error) -> ErrorDiagnostic {
        let nsError = error as NSError
        return ErrorDiagnostic(
            domain: nsError.domain,
            code: nsError.code,
            localizedDescription: nsError.localizedDescription,
            localizedFailureReason: nsError.localizedFailureReason ?? "",
            debugDescription: String(describing: error),
            userInfoDescription: nsError.userInfo.description
        )
    }

    func isBenignMissingOptionalStoreError(
        _ diagnostic: ErrorDiagnostic,
        extensionId: String,
        preCleanupSnapshot: StorageSnapshot,
        postCleanupSnapshot: StorageSnapshot,
        hasNonOptionalFailureSignals: Bool
    ) -> Bool {
        let extensionMatches = diagnostic.logSummary.lowercased().contains(extensionId.lowercased())
        let snapshotShowsOnlyOptionalStoreGap =
            preCleanupSnapshot.isMissingTrackedOptionalStoresOnly
            || postCleanupSnapshot.isMissingTrackedOptionalStoresOnly
        if diagnostic.referencesOptionalStore && diagnostic.mentionsMissingFile {
            return true
        }

        if diagnostic.isGenericSQLiteStoreCreationFailure,
           snapshotShowsOnlyOptionalStoreGap,
           hasNonOptionalFailureSignals == false,
           extensionMatches || diagnostic.referencesOptionalStore {
            return true
        }

        if diagnostic.isWebKitExtensionStorageComputationFailure,
           snapshotShowsOnlyOptionalStoreGap,
           hasNonOptionalFailureSignals == false {
            return true
        }

        return false
    }
}

@available(macOS 15.5, *)
extension ExtensionManager {
    typealias WebExtensionStorageCleanupMode = WebExtensionStorageCleanupPlanner.CleanupMode
    typealias WebExtensionStorageSnapshot = WebExtensionStorageCleanupPlanner.StorageSnapshot
    typealias WebExtensionStoreCapabilitySnapshot = WebExtensionStorageCleanupPlanner.StoreCapabilitySnapshot
}
