//
//  SafariExtensionAcceptanceMatrix.swift
//  Sumi
//
//  Automated acceptance checks for Safari Web Extension import → enable → runtime.
//  Runnable in DEBUG and unit tests; complements manual E2E in compatibility doc.
//

import Foundation
import WebKit

enum SafariExtensionAcceptanceCheck: String, Codable, CaseIterable, Sendable {
    case scannerFindsInstalledTarget
    case importSourceResolvable
    case syntheticEnableActionSurfaceReady
    case contentScriptTabReconcileWired
    case raindropTabAdapterPrerequisites
    case popupAnchorPresentationWired
    case nativeMessagingSuppressionReportWired
    case passwordManagerLocalFormFixtureAvailable
}

struct SafariExtensionAcceptanceCheckResult: Codable, Equatable, Sendable {
    let check: SafariExtensionAcceptanceCheck
    let passed: Bool
    let detail: String
}

struct SafariExtensionAcceptanceMatrixEntry: Codable, Equatable, Sendable, Identifiable {
    var id: String { targetKey }

    let targetKey: String
    let displayName: String
    let results: [SafariExtensionAcceptanceCheckResult]
    let platformBlockers: [SafariExtensionPlatformBlocker]
    let nativeMessagingClassifications: [SafariExtensionNativeMessagingClassification]
    let compatibilityEntry: SafariExtensionCompatibilityEntry?
}

struct SafariExtensionAcceptanceMatrix: Codable, Equatable, Sendable {
    let generatedAt: Date
    let entries: [SafariExtensionAcceptanceMatrixEntry]
    let globalChecks: [SafariExtensionAcceptanceCheckResult]
    let globalPlatformBlockers: [SafariExtensionPlatformBlocker]
    let globalNativeMessagingClassifications: [SafariExtensionNativeMessagingClassification]
    let globalSuppressionReport: SafariExtensionNativeMessagingSuppressionReport
    let sdkProbeNote: String
}

@MainActor
enum SafariExtensionAcceptanceMatrixBuilder {
    static func build(
        targets: [SafariExtensionCompatibilityTargets.Target] = SafariExtensionCompatibilityTargets.all,
        discovered: [DiscoveredSafariExtensionCandidate],
        importStore: SafariExtensionImportStore = .shared,
        installedExtensions: [InstalledExtension] = [],
        extensionManager: ExtensionManager? = nil,
        extensionsModuleEnabled: Bool = true,
        applicationSearchRoots: [URL] = SafariExtensionScanner.defaultApplicationSearchRoots()
    ) -> SafariExtensionAcceptanceMatrix {
        let compatibilityReport = SafariExtensionCompatibilityReportBuilder.build(
            targets: targets,
            discovered: discovered,
            importStore: importStore,
            installedExtensions: installedExtensions,
            extensionManager: extensionManager,
            extensionsModuleEnabled: extensionsModuleEnabled
        )
        let compatibilityByKey = Dictionary(
            uniqueKeysWithValues: compatibilityReport.entries.map { ($0.targetKey, $0) }
        )

        let globalChecks: [SafariExtensionAcceptanceCheckResult] = [
            evaluatePopupAnchorPresentationWired(),
            evaluateNativeMessagingSuppressionReportWired(),
            evaluatePasswordManagerLocalFormFixtureAvailable(),
        ]

        let entries = targets.map { target in
            let candidate = discovered.first {
                $0.extensionBundleIdentifier == target.expectedAppexBundleIdentifier
            } ?? discovered.first {
                $0.containingAppName == target.containingAppName
                    || $0.displayName.localizedCaseInsensitiveContains(target.displayName)
            }
            let compatibilityEntry = compatibilityByKey[target.key]
            let installed = resolveInstalled(
                target: target,
                candidate: candidate,
                importStore: importStore,
                installedExtensions: installedExtensions
            )

            var results: [SafariExtensionAcceptanceCheckResult] = [
                evaluateScannerFindsTarget(
                    target: target,
                    candidate: candidate,
                    applicationSearchRoots: applicationSearchRoots
                ),
                evaluateImportSourceResolvable(
                    target: target,
                    candidate: candidate
                ),
                evaluateSyntheticEnableActionSurface(
                    installed: installed,
                    compatibilityEntry: compatibilityEntry
                ),
                evaluateContentScriptTabReconcileWired(),
            ]

            if target.key == "raindrop" {
                results.append(evaluateRaindropTabAdapterPrerequisites())
            }

            return SafariExtensionAcceptanceMatrixEntry(
                targetKey: target.key,
                displayName: target.displayName,
                results: results,
                platformBlockers: [],
                nativeMessagingClassifications:
                    SafariExtensionNativeMessagingClassificationCatalog
                    .classifications(forTargetKey: target.key),
                compatibilityEntry: compatibilityEntry
            )
        }

        return SafariExtensionAcceptanceMatrix(
            generatedAt: Date(),
            entries: entries,
            globalChecks: globalChecks,
            globalPlatformBlockers: [],
            globalNativeMessagingClassifications:
                SafariExtensionNativeMessagingClassificationCatalog
                .globalReportClassifications(sumiRelayImplemented: true),
            globalSuppressionReport: SafariExtensionNativeMessagingSuppressionProbe.evaluate(),
            sdkProbeNote: SafariExtensionHostRelayAPIProbe.sdkProbeNote
        )
    }

    static func logIfDiagnosticsEnabled(_ matrix: SafariExtensionAcceptanceMatrix) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            guard let data = try? encoder.encode(matrix),
                  let json = String(data: data, encoding: .utf8)
            else {
                RuntimeDiagnostics.debug(
                    "SafariExtensionAcceptanceMatrix encode failed",
                    category: "SafariExtension"
                )
                return
            }

            RuntimeDiagnostics.debug(
                "SafariExtensionAcceptanceMatrix \(json)",
                category: "SafariExtension"
            )
        #else
            _ = matrix
        #endif
    }

    // MARK: - Pure evaluators (unit-testable)

    static func isActionSurfaceReadyAfterSyntheticEnable(
        hasAction: Bool,
        isEnabled: Bool,
        isContextLoaded: Bool,
        isActionAvailable: Bool,
        hasSeededActionState: Bool
    ) -> Bool {
        guard hasAction else { return true }
        guard isEnabled, isContextLoaded else { return false }
        return isActionAvailable || hasSeededActionState
    }

    static func evaluateScannerFindsTarget(
        target: SafariExtensionCompatibilityTargets.Target,
        candidate: DiscoveredSafariExtensionCandidate?,
        applicationSearchRoots: [URL]
    ) -> SafariExtensionAcceptanceCheckResult {
        let appInstalled = applicationSearchRoots.contains {
            FileManager.default.fileExists(
                atPath: $0.appendingPathComponent("\(target.containingAppName).app").path
            )
        }

        if appInstalled == false {
            return SafariExtensionAcceptanceCheckResult(
                check: .scannerFindsInstalledTarget,
                passed: true,
                detail: "Skipped — \(target.containingAppName).app not present in search roots"
            )
        }

        let passed = candidate?.extensionBundleIdentifier == target.expectedAppexBundleIdentifier
        return SafariExtensionAcceptanceCheckResult(
            check: .scannerFindsInstalledTarget,
            passed: passed,
            detail: passed
                ? "Scanner found \(target.expectedAppexBundleIdentifier)"
                : "Expected \(target.expectedAppexBundleIdentifier) when \(target.containingAppName) is installed"
        )
    }

    static func evaluateImportSourceResolvable(
        target: SafariExtensionCompatibilityTargets.Target,
        candidate: DiscoveredSafariExtensionCandidate?
    ) -> SafariExtensionAcceptanceCheckResult {
        guard let candidate else {
            return SafariExtensionAcceptanceCheckResult(
                check: .importSourceResolvable,
                passed: true,
                detail: "Skipped — target not discovered"
            )
        }

        let appexURL = SafariAppExtensionResources.installedAppexBundleURL(
            sourceKind: .safariAppExtension,
            sourceBundlePath: candidate.appexURL.path
        )
        let manifestExists = candidate.manifestURL.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
        let passed = appexURL != nil || manifestExists

        return SafariExtensionAcceptanceCheckResult(
            check: .importSourceResolvable,
            passed: passed,
            detail: passed
                ? "Import source resolves (appex=\(appexURL != nil) manifest=\(manifestExists))"
                : "No appex path or manifest for \(target.key)"
        )
    }

    static func evaluateSyntheticEnableActionSurface(
        installed: InstalledExtension?,
        compatibilityEntry: SafariExtensionCompatibilityEntry?
    ) -> SafariExtensionAcceptanceCheckResult {
        guard let installed else {
            return SafariExtensionAcceptanceCheckResult(
                check: .syntheticEnableActionSurfaceReady,
                passed: true,
                detail: "Skipped — not installed in Sumi store"
            )
        }

        guard installed.isEnabled else {
            return SafariExtensionAcceptanceCheckResult(
                check: .syntheticEnableActionSurfaceReady,
                passed: true,
                detail: "Skipped — extension disabled (synthetic enable uses enabled fixture)"
            )
        }

        let entry = compatibilityEntry
        let passed = isActionSurfaceReadyAfterSyntheticEnable(
            hasAction: installed.hasAction,
            isEnabled: installed.isEnabled,
            isContextLoaded: entry?.isContextLoaded ?? false,
            isActionAvailable: entry?.isActionAvailable ?? false,
            hasSeededActionState: entry?.popupLoadStatus == .loaded
                || entry?.popupLoadStatus == .empty
        )

        return SafariExtensionAcceptanceCheckResult(
            check: .syntheticEnableActionSurfaceReady,
            passed: passed,
            detail: passed
                ? "Action surface ready (hasAction=\(installed.hasAction))"
                : "Enabled extension missing context/action after synthetic enable path"
        )
    }

    static func evaluateContentScriptTabReconcileWired() -> SafariExtensionAcceptanceCheckResult {
        let wired = SafariExtensionContentScriptProbe.isTabReconcilePathWiredInSources()
        return SafariExtensionAcceptanceCheckResult(
            check: .contentScriptTabReconcileWired,
            passed: wired,
            detail: wired
                ? "reconcileOpenTabsAfterExtensionContextLoad wired in enable/finalize path"
                : "Tab reconcile symbols missing from ExtensionManager sources"
        )
    }

    static func evaluateRaindropTabAdapterPrerequisites() -> SafariExtensionAcceptanceCheckResult {
        let probe = SafariExtensionRaindropTabAdapterProbe.evaluate()
        return SafariExtensionAcceptanceCheckResult(
            check: .raindropTabAdapterPrerequisites,
            passed: probe.passed,
            detail: probe.detail
        )
    }

    static func evaluatePopupAnchorPresentationWired() -> SafariExtensionAcceptanceCheckResult {
        let probe = SafariExtensionPopupAnchorProbe.evaluate()
        return SafariExtensionAcceptanceCheckResult(
            check: .popupAnchorPresentationWired,
            passed: probe.passed,
            detail: probe.detail
        )
    }

    static func evaluateNativeMessagingSuppressionReportWired() -> SafariExtensionAcceptanceCheckResult {
        let report = SafariExtensionNativeMessagingSuppressionProbe.evaluate()
        let passed =
            report.repeatedCallSuppressionEnabled
            && report.coalescedLoggingEnabled
            && report.sessionStateTrackingEnabled
            && report.companionProtocolUnknownDeterministic
        return SafariExtensionAcceptanceCheckResult(
            check: .nativeMessagingSuppressionReportWired,
            passed: passed,
            detail: passed
                ? "NM repeated-call suppression + coalesced logging + sessionState wired"
                : "NM suppression report incomplete: repeated=\(report.repeatedCallSuppressionEnabled) coalesced=\(report.coalescedLoggingEnabled) sessionState=\(report.sessionStateTrackingEnabled)"
        )
    }

    static func evaluatePasswordManagerLocalFormFixtureAvailable() -> SafariExtensionAcceptanceCheckResult {
        let probe = SafariExtensionPasswordManagerFormFixtureProbe.evaluate()
        return SafariExtensionAcceptanceCheckResult(
            check: .passwordManagerLocalFormFixtureAvailable,
            passed: probe.passed,
            detail: probe.detail
        )
    }

    private static func resolveInstalled(
        target: SafariExtensionCompatibilityTargets.Target,
        candidate: DiscoveredSafariExtensionCandidate?,
        importStore: SafariExtensionImportStore,
        installedExtensions: [InstalledExtension]
    ) -> InstalledExtension? {
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

        let imported = candidate.flatMap { importedByAppexID[$0.extensionBundleIdentifier] }
        return candidate.flatMap { installedBySourcePath[$0.appexURL.path] }
            ?? imported.flatMap { installedByID[$0.installedExtensionId] }
    }
}

enum SafariExtensionContentScriptProbe {
    static func isTabReconcilePathWiredInSources() -> Bool {
        isTabReconcilePathWiredViaCompileTimePaths()
    }

    static func isTabReconcilePathWiredViaCompileTimePaths() -> Bool {
        let profilesPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ExtensionManager+Profiles.swift")
        let uiPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ExtensionManager+UI.swift")

        guard let profiles = try? String(contentsOf: profilesPath, encoding: .utf8),
              let ui = try? String(contentsOf: uiPath, encoding: .utf8)
        else {
            return false
        }

        return profiles.contains("reconcileOpenTabsAfterExtensionContextLoad")
            && profiles.contains("Attach or rebuild WebViews before `didOpenTab`")
            && profiles.contains("tabNeedsExtensionContentScriptRebind")
            && ui.contains("finalizeEnabledExtensionRuntime")
    }
}

enum SafariExtensionRaindropTabAdapterProbe {
    struct Result: Equatable {
        let passed: Bool
        let detail: String
    }

    static let requiredTabAdapterSymbols: [String] = [
        "func url(for extensionContext:",
        "func title(for extensionContext:",
        "func isSelected(for extensionContext:",
        "func webView(for extensionContext:",
        "func shouldGrantPermissionsOnUserGesture(for extensionContext:",
        "func shouldBypassPermissions(for extensionContext:",
    ]

    static func evaluate(
        bridgeSource: String? = nil
    ) -> Result {
        let source = bridgeSource ?? loadExtensionBridgeAdapterSource()
        guard let source else {
            return Result(passed: false, detail: "Extension bridge adapter source unavailable")
        }

        let missing = requiredTabAdapterSymbols.filter { source.contains($0) == false }
        guard missing.isEmpty else {
            return Result(
                passed: false,
                detail: "ExtensionTabAdapter missing: \(missing.joined(separator: ", "))"
            )
        }

        return Result(
            passed: true,
            detail: "Tab adapter exposes url/title/selection/webView/activeTab gesture + permission enforcement for save flow"
        )
    }

    private static func loadExtensionBridgeAdapterSource() -> String? {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = [
            "ExtensionBridge.swift",
            "ExtensionTabAdapter.swift",
        ].compactMap {
            try? String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8)
        }
        guard sources.isEmpty == false else { return nil }
        return sources.joined(separator: "\n")
    }
}

@MainActor
extension SumiExtensionsModule {
    func safariExtensionAcceptanceMatrix() -> SafariExtensionAcceptanceMatrix {
        var issues: [SafariExtensionScannerIssue] = []
        let discovered = SafariExtensionScanner().scanInstalledExtensions(issues: &issues)
        SafariExtensionImportStore.shared.refreshDiscoveredCandidates(
            discovered.filter { $0.bundleKind == .webExtension }
        )

        let manager = managerIfLoadedAndEnabled()
        let matrix = SafariExtensionAcceptanceMatrixBuilder.build(
            discovered: discovered,
            installedExtensions: manager?.installedExtensions ?? [],
            extensionManager: manager,
            extensionsModuleEnabled: isEnabled
        )
        SafariExtensionAcceptanceMatrixBuilder.logIfDiagnosticsEnabled(matrix)
        return matrix
    }
}
