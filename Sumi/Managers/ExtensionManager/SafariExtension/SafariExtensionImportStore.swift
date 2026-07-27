//
//  SafariExtensionImportStore.swift
//  Sumi
//
//  Tracks discovered Safari Web Extension candidates and user imports.
//  Does not auto-enable or load WebKit runtime state.
//

import Foundation
import OSLog

protocol SafariExtensionImportStoring: AnyObject {
    func refreshDiscoveredCandidates(_ candidates: [DiscoveredSafariExtensionCandidate])
    func removeImportedRecord(forInstalledExtensionId installedExtensionId: String)
    func markImported(
        candidate: DiscoveredSafariExtensionCandidate,
        installedExtensionId: String
    )
}

struct SafariExtensionImportCandidateRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { extensionBundleIdentifier }

    let extensionBundleIdentifier: String
    let appexPath: String
    let displayName: String
    let containingAppName: String
    let lastDiscoveredAt: Date
}

struct SafariExtensionImportedRecord: Codable, Equatable, Sendable {
    let extensionBundleIdentifier: String
    let appexPath: String
    let installedExtensionId: String
    let importedAt: Date
}

/// Minimal registry for scanner output vs explicit user imports.
final class SafariExtensionImportStore: @unchecked Sendable {
    /// Non-durable fallback for low-level diagnostics and isolated tests.
    static let transient = SafariExtensionImportStore()

    private static let log = Logger.sumi(category: "Extensions")
    private static let documentKey = "safari-extension.import-registry"

    private struct State: Codable {
        var discovered: [SafariExtensionImportCandidateRecord] = []
        var imported: [SafariExtensionImportedRecord] = []
    }

    private let database: SumiDatabase?
    private let memoryLock = NSLock()
    private var memoryState = State()

    init(database: SumiDatabase) {
        self.database = database
    }

    private init() {
        database = nil
    }

    func refreshDiscoveredCandidates(_ candidates: [DiscoveredSafariExtensionCandidate]) {
        let now = Date()
        let records = candidates.filter { $0.bundleKind == .webExtension }.map {
            SafariExtensionImportCandidateRecord(
                extensionBundleIdentifier: $0.extensionBundleIdentifier,
                appexPath: $0.appexURL.path,
                displayName: $0.displayName,
                containingAppName: $0.containingAppName,
                lastDiscoveredAt: now
            )
        }
        updateState { $0.discovered = records }
    }

    func discoveredCandidates() -> [SafariExtensionImportCandidateRecord] {
        loadDiscovered().sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func importedRecords() -> [SafariExtensionImportedRecord] {
        loadImported().sorted {
            $0.importedAt > $1.importedAt
        }
    }

    func isImported(extensionBundleIdentifier: String) -> Bool {
        loadImported().contains { $0.extensionBundleIdentifier == extensionBundleIdentifier }
    }

    func importedExtensionId(forExtensionBundleIdentifier identifier: String) -> String? {
        loadImported().first { $0.extensionBundleIdentifier == identifier }?.installedExtensionId
    }

    func importableCandidates(
        excludingInstalledBundlePaths installedBundlePaths: Set<String> = []
    ) -> [SafariExtensionImportCandidateRecord] {
        discoveredCandidates().filter { candidate in
            installedBundlePaths.contains(candidate.appexPath) == false
        }
    }

    func removeImportedRecord(forInstalledExtensionId installedExtensionId: String) {
        updateState {
            $0.imported.removeAll {
                $0.installedExtensionId == installedExtensionId
            }
        }
    }

    func removeImportedRecord(extensionBundleIdentifier: String) {
        updateState {
            $0.imported.removeAll {
                $0.extensionBundleIdentifier == extensionBundleIdentifier
            }
        }
    }

    func markImported(
        candidate: DiscoveredSafariExtensionCandidate,
        installedExtensionId: String
    ) {
        updateState {
            $0.imported.removeAll {
                $0.extensionBundleIdentifier
                    == candidate.extensionBundleIdentifier
            }
            $0.imported.append(
                SafariExtensionImportedRecord(
                    extensionBundleIdentifier:
                        candidate.extensionBundleIdentifier,
                    appexPath: candidate.appexURL.path,
                    installedExtensionId: installedExtensionId,
                    importedAt: Date()
                )
            )
        }
    }

    func markImported(
        extensionBundleIdentifier: String,
        appexPath: String,
        installedExtensionId: String
    ) {
        updateState {
            $0.imported.removeAll {
                $0.extensionBundleIdentifier == extensionBundleIdentifier
            }
            $0.imported.append(
                SafariExtensionImportedRecord(
                    extensionBundleIdentifier: extensionBundleIdentifier,
                    appexPath: appexPath,
                    installedExtensionId: installedExtensionId,
                    importedAt: Date()
                )
            )
        }
    }

    // MARK: - Persistence

    private func loadDiscovered() -> [SafariExtensionImportCandidateRecord] {
        loadState().discovered
    }

    private func loadImported() -> [SafariExtensionImportedRecord] {
        loadState().imported
    }

    private func loadState() -> State {
        guard let database else {
            return memoryLock.withLock { memoryState }
        }
        do {
            return try database.read { connection in
                try connection.documents.value(
                    State.self,
                    forKey: Self.documentKey
                ) ?? State()
            }
        } catch {
            Self.log.error(
                "Failed to load Safari extension import registry: \(error.localizedDescription, privacy: .public)"
            )
            return State()
        }
    }

    private func updateState(_ mutation: (inout State) -> Void) {
        guard let database else {
            memoryLock.withLock {
                mutation(&memoryState)
            }
            return
        }
        do {
            try database.transaction { connection in
                var state = try connection.documents.value(
                    State.self,
                    forKey: Self.documentKey
                ) ?? State()
                mutation(&state)
                try connection.documents.save(
                    state,
                    forKey: Self.documentKey
                )
            }
        } catch {
            Self.log.error(
                "Failed to persist Safari extension import registry: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

extension SafariExtensionImportStore: SafariExtensionImportStoring {}
