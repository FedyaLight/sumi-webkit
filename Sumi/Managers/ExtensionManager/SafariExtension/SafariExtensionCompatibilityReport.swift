//
//  SafariExtensionCompatibilityReport.swift
//  Sumi
//
//  Dev diagnostics for Safari Web Extension import → enable → runtime status.
//  Sanitized output only — no secrets, tokens, or host-app messaging payloads.
//

import Foundation
import WebKit

enum SafariExtensionPopupLoadStatus: String, Codable, CaseIterable, Sendable {
    /// Manifest has no `action.default_popup` / `browser_action.default_popup`.
    case notApplicable
    /// Extension disabled, module off, or runtime not ready to evaluate popup.
    case unavailable
    /// Popup declared and runtime is ready, but WebKit has not surfaced popup UI yet.
    case empty
    /// Action surface reports popup presentation is available.
    case loaded
    /// Popup declared but action/runtime failed or popup resource is missing.
    case error
}

enum SafariExtensionCompatibilityErrorBucket: String, Codable, CaseIterable, Sendable {
    case none
    case notDiscovered
    case notImported
    case notInstalled
    case disabled
    case moduleDisabled
    case runtimeUnavailable
    case contextMissing
    case actionUnavailable
    case runtimeLoadFailed
    case nativeMessagingUnavailable
    case unknown
}

struct SafariExtensionCompatibilityEntry: Codable, Equatable, Sendable, Identifiable {
    var id: String { targetKey }

    let targetKey: String
    let displayName: String
    let containingAppName: String
    let extensionBundleIdentifier: String?
    let containingAppBundleIdentifier: String?
    let isDiscovered: Bool
    let isImported: Bool
    let installedExtensionId: String?
    let isEnabled: Bool
    let isContextLoaded: Bool
    let isActionAvailable: Bool
    let popupLoadStatus: SafariExtensionPopupLoadStatus
    /// When imported from Safari, whether runtime would load the on-disk `.appex` vs copied package.
    let safariRuntimeLoadSource: SafariAppExtensionRuntimeLoadSource?
    let lastErrorBucket: SafariExtensionCompatibilityErrorBucket
    let platformBlockers: [SafariExtensionPlatformBlocker]
    let nativeMessagingClassifications: [SafariExtensionNativeMessagingClassification]
    let inlineUIClassification: SafariExtensionInlineUIClassification
    let manualVerification: SafariExtensionManualVerificationRow
}

struct SafariExtensionCompatibilityReport: Codable, Equatable, Sendable {
    let generatedAt: Date
    let entries: [SafariExtensionCompatibilityEntry]
    let platformBlockers: [SafariExtensionPlatformBlocker]
    let nativeMessagingClassifications: [SafariExtensionNativeMessagingClassification]
    let sdkProbeNote: String
}

protocol SafariExtensionImportRecordProviding: AnyObject {
    func importedRecords() -> [SafariExtensionImportedRecord]
}

extension SafariExtensionImportStore: SafariExtensionImportRecordProviding {}

/// PM target extensions for manual acceptance and dev-machine bundle probes.
enum SafariExtensionCompatibilityTargets {
    struct Target: Equatable, Sendable {
        let key: String
        let displayName: String
        let containingAppName: String
        /// Expected `.appex` bundle identifier when installed (from Cycle 3 dev probe).
        let expectedAppexBundleIdentifier: String
        let nativeMessagingApplicationIdentifier: String?
        let nativeMessagingHostBundleIdentifier: String?

        init(
            key: String,
            displayName: String,
            containingAppName: String,
            expectedAppexBundleIdentifier: String,
            nativeMessagingApplicationIdentifier: String? = nil,
            nativeMessagingHostBundleIdentifier: String? = nil
        ) {
            self.key = key
            self.displayName = displayName
            self.containingAppName = containingAppName
            self.expectedAppexBundleIdentifier = expectedAppexBundleIdentifier
            self.nativeMessagingApplicationIdentifier = nativeMessagingApplicationIdentifier
            self.nativeMessagingHostBundleIdentifier = nativeMessagingHostBundleIdentifier
        }
    }

    static let all: [Target] = [
        Target(
            key: "bitwarden",
            displayName: "Bitwarden",
            containingAppName: "Bitwarden",
            expectedAppexBundleIdentifier: "com.bitwarden.desktop.safari",
            nativeMessagingApplicationIdentifier: BitwardenNativeMessagingIdentifiers.hostBundleIdentifier,
            nativeMessagingHostBundleIdentifier: BitwardenNativeMessagingIdentifiers.hostBundleIdentifier
        ),
        Target(
            key: "1password",
            displayName: "1Password",
            containingAppName: "1Password for Safari",
            expectedAppexBundleIdentifier: "com.1password.safari.extension",
            nativeMessagingApplicationIdentifier: "com.1password.safari",
            nativeMessagingHostBundleIdentifier: "com.1password.safari"
        ),
        Target(
            key: "proton-pass",
            displayName: "Proton Pass",
            containingAppName: "Proton Pass for Safari",
            expectedAppexBundleIdentifier: "me.proton.pass.catalyst.safari-extension",
            nativeMessagingApplicationIdentifier: ProtonNativeMessagingIdentifiers.requestedApplicationIdentifier,
            nativeMessagingHostBundleIdentifier: ProtonNativeMessagingIdentifiers.safariHostBundleIdentifier
        ),
        Target(
            key: "raindrop",
            displayName: "Raindrop",
            containingAppName: "Save to Raindrop.io",
            expectedAppexBundleIdentifier: "io.raindrop.safari.extension",
            nativeMessagingHostBundleIdentifier: "io.raindrop.safari"
        ),
    ]
}

@MainActor
enum SafariExtensionCompatibilityReportBuilder {
    static func build(
        targets: [SafariExtensionCompatibilityTargets.Target] = SafariExtensionCompatibilityTargets.all,
        discovered: [DiscoveredSafariExtensionCandidate],
        importStore: any SafariExtensionImportRecordProviding,
        installedExtensions: [InstalledExtension] = [],
        extensionManager: ExtensionManager? = nil,
        extensionsModuleEnabled: Bool = true
    ) -> SafariExtensionCompatibilityReport {
        let discoveredByAppexID = Dictionary(
            uniqueKeysWithValues: discovered.map { ($0.extensionBundleIdentifier, $0) }
        )
        let importedByAppexID = Dictionary(
            uniqueKeysWithValues: importStore.importedRecords().map {
                ($0.extensionBundleIdentifier, $0)
            }
        )
        let installedByID = Dictionary(
            uniqueKeysWithValues: installedExtensions.map { ($0.id, $0) }
        )
        let installedBySourcePath = Dictionary(
            uniqueKeysWithValues: installedExtensions.map { ($0.sourceBundlePath, $0) }
        )

        let entries = targets.map { target in
            let candidate = discoveredByAppexID[target.expectedAppexBundleIdentifier]
                ?? discovered.first {
                    $0.containingAppName == target.containingAppName
                        || $0.displayName.localizedCaseInsensitiveContains(target.displayName)
                }
            let imported = candidate.map {
                importedByAppexID[$0.extensionBundleIdentifier]
            } ?? nil

            let installed = candidate.flatMap { installedBySourcePath[$0.appexURL.path] }
                ?? imported.flatMap { installedByID[$0.installedExtensionId] }

            let extensionId = installed?.id ?? imported?.installedExtensionId
            let isEnabled = installed?.isEnabled == true
            let context = extensionId.flatMap { extensionManager?.getExtensionContext(for: $0) }
            let isContextLoaded = context != nil
            let isActionAvailable: Bool = {
                guard let context, let extensionId else { return false }
                if extensionManager?.actionStatesByExtensionID[extensionId] != nil {
                    return true
                }
                let tab = extensionManager?.browserManager?.currentTabForActiveWindow()
                let adapter = tab.flatMap { extensionManager?.stableAdapter(for: $0) }
                return context.action(for: adapter) != nil
            }()

            let lastErrorBucket = resolveErrorBucket(
                target: target,
                candidate: candidate,
                imported: imported,
                installed: installed,
                isEnabled: isEnabled,
                isContextLoaded: isContextLoaded,
                isActionAvailable: isActionAvailable,
                extensionsModuleEnabled: extensionsModuleEnabled,
                extensionManager: extensionManager
            )
            let actionState = extensionId.flatMap {
                extensionManager?.actionStatesByExtensionID[$0]
            }
            let popupLoadStatus = resolvePopupLoadStatus(
                installed: installed,
                isEnabled: isEnabled,
                isContextLoaded: isContextLoaded,
                isActionAvailable: isActionAvailable,
                actionState: actionState,
                extensionsModuleEnabled: extensionsModuleEnabled,
                lastErrorBucket: lastErrorBucket
            )
            let safariRuntimeLoadSource: SafariAppExtensionRuntimeLoadSource? = {
                guard let installed, installed.sourceKind == .safariAppExtension else {
                    return nil
                }
                if SafariAppExtensionResources.installedAppexBundleURL(
                    sourceKind: installed.sourceKind,
                    sourceBundlePath: installed.sourceBundlePath
                ) != nil {
                    return .originalAppexBundle
                }
                return nil
            }()

            return SafariExtensionCompatibilityEntry(
                targetKey: target.key,
                displayName: target.displayName,
                containingAppName: target.containingAppName,
                extensionBundleIdentifier: candidate?.extensionBundleIdentifier,
                containingAppBundleIdentifier: candidate?.containingAppBundleIdentifier,
                isDiscovered: candidate != nil,
                isImported: imported != nil,
                installedExtensionId: extensionId,
                isEnabled: isEnabled,
                isContextLoaded: isContextLoaded,
                isActionAvailable: isActionAvailable,
                popupLoadStatus: popupLoadStatus,
                safariRuntimeLoadSource: safariRuntimeLoadSource,
                lastErrorBucket: lastErrorBucket,
                platformBlockers: [],
                nativeMessagingClassifications:
                    SafariExtensionNativeMessagingClassificationCatalog
                    .classifications(forTargetKey: target.key),
                inlineUIClassification: SafariExtensionInlineUIClassificationCatalog
                    .classification(forTargetKey: target.key),
                manualVerification: SafariExtensionManualVerificationCatalog.row(
                    forTargetKey: target.key
                )
            )
        }

        return SafariExtensionCompatibilityReport(
            generatedAt: Date(),
            entries: entries,
            platformBlockers: [],
            nativeMessagingClassifications:
                SafariExtensionNativeMessagingClassificationCatalog
                .globalReportClassifications(sumiRelayImplemented: true),
            sdkProbeNote: SafariExtensionHostRelayAPIProbe.sdkProbeNote
        )
    }

    static func logIfDiagnosticsEnabled(_ report: SafariExtensionCompatibilityReport) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            guard let data = try? encoder.encode(report),
                  let json = String(data: data, encoding: .utf8)
            else {
                RuntimeDiagnostics.debug(
                    "SafariExtensionCompatibilityReport encode failed",
                    category: "SafariExtension"
                )
                return
            }

            RuntimeDiagnostics.debug(
                "SafariExtensionCompatibilityReport \(json)",
                category: "SafariExtension"
            )
        #else
            _ = report
        #endif
    }

    static func resolvePopupLoadStatus(
        installed: InstalledExtension?,
        isEnabled: Bool,
        isContextLoaded: Bool,
        isActionAvailable: Bool,
        actionState: BrowserExtensionActionSurfaceState?,
        extensionsModuleEnabled: Bool,
        lastErrorBucket: SafariExtensionCompatibilityErrorBucket
    ) -> SafariExtensionPopupLoadStatus {
        guard installed?.defaultPopupPath != nil else { return .notApplicable }
        guard extensionsModuleEnabled else { return .unavailable }
        guard isEnabled else { return .unavailable }

        switch lastErrorBucket {
        case .runtimeLoadFailed, .contextMissing, .runtimeUnavailable:
            return .error
        case .moduleDisabled, .notDiscovered, .notImported, .notInstalled, .disabled:
            return .unavailable
        case .actionUnavailable:
            return .error
        case .nativeMessagingUnavailable, .unknown, .none:
            break
        }

        guard isContextLoaded else { return .unavailable }
        guard isActionAvailable else { return .error }

        if actionState?.presentsPopup == true {
            return .loaded
        }

        if let installed,
           let popupPath = installed.defaultPopupPath,
           popupPath.isEmpty == false {
            let popupURL = URL(fileURLWithPath: installed.packagePath, isDirectory: true)
                .appendingPathComponent(popupPath)
            if FileManager.default.fileExists(atPath: popupURL.path) {
                return .empty
            }
            return .error
        }

        return .empty
    }

    private static func resolveErrorBucket(
        target: SafariExtensionCompatibilityTargets.Target,
        candidate: DiscoveredSafariExtensionCandidate?,
        imported: SafariExtensionImportedRecord?,
        installed: InstalledExtension?,
        isEnabled: Bool,
        isContextLoaded: Bool,
        isActionAvailable: Bool,
        extensionsModuleEnabled: Bool,
        extensionManager: ExtensionManager?
    ) -> SafariExtensionCompatibilityErrorBucket {
        _ = target

        guard extensionsModuleEnabled else { return .moduleDisabled }
        guard candidate != nil else { return .notDiscovered }
        guard imported != nil || installed != nil else { return .notImported }
        guard installed != nil else { return .notInstalled }
        guard isEnabled else { return .disabled }

        if let extensionManager {
            switch extensionManager.runtimeState {
            case .failed:
                return .runtimeLoadFailed
            case .unavailable:
                return .runtimeUnavailable
            case .idle, .loading:
                if isContextLoaded == false {
                    return .contextMissing
                }
            case .ready:
                break
            }
        } else if isContextLoaded == false {
            return .contextMissing
        }

        guard isContextLoaded else { return .contextMissing }
        guard isActionAvailable else { return .actionUnavailable }
        return .none
    }
}

@MainActor
extension SumiExtensionsModule {
    func safariExtensionCompatibilityReport() -> SafariExtensionCompatibilityReport {
        var issues: [SafariExtensionScannerIssue] = []
        let discovered = SafariExtensionScanner().scanInstalledExtensions(issues: &issues)
        refreshDiscoveredSafariWebExtensionCandidates(discovered)

        let manager = managerIfLoadedAndEnabled()
        let installed = manager?.installedExtensions ?? []
        let report = SafariExtensionCompatibilityReportBuilder.build(
            discovered: discovered,
            importStore: safariExtensionImportRecordsForDiagnostics(),
            installedExtensions: installed,
            extensionManager: manager,
            extensionsModuleEnabled: isEnabled
        )
        SafariExtensionCompatibilityReportBuilder.logIfDiagnosticsEnabled(report)
        return report
    }
}
