//
//  SafariExtensionRuntimeDiagnostics.swift
//  Sumi
//
//  Sanitized runtime capability diagnostics for Safari Web Extension targets.
//  Never logs message bodies, storage payloads, or credentials.
//

import Foundation
import WebKit

enum SafariExtensionCapabilityStatus: String, Codable, CaseIterable, Sendable {
    case notApplicable
    case unavailable
    case declared
    case granted
    case wired
    case suppressed
    case error
}

struct SafariExtensionNativeMessagingSuppressionReport: Codable, Equatable, Sendable {
    let repeatedCallSuppressionEnabled: Bool
    let coalescedLoggingEnabled: Bool
    let sessionStateTrackingEnabled: Bool
    let companionProtocolUnknownDeterministic: Bool
    let supportedRelayProtocolHostCount: Int
    let note: String
}

struct SafariExtensionRuntimeStatusSnapshot: Codable, Equatable, Sendable {
    let scriptingStatus: SafariExtensionCapabilityStatus
    let contentScriptStatus: SafariExtensionCapabilityStatus
    let hostPermissionStatus: SafariExtensionCapabilityStatus
    let tabFrameMappingStatus: SafariExtensionCapabilityStatus
    let popupAnchorStatus: SafariExtensionCapabilityStatus
    let autofillInfrastructureBlocker: SafariExtensionAutofillBlocker
    let nativeMessagingSessionState: SumiNativeMessagingSessionState?
    let launchSuppressionExpected: Bool
    let suppressionReport: SafariExtensionNativeMessagingSuppressionReport
    let detailNotes: [String]
}

struct SafariExtensionRuntimeDiagnosticEntry: Codable, Equatable, Sendable, Identifiable {
    var id: String { targetKey }

    let targetKey: String
    let displayName: String
    let runtimeStatus: SafariExtensionRuntimeStatusSnapshot
    let manualVerification: SafariExtensionManualVerificationRow
    let compatibilityEntry: SafariExtensionCompatibilityEntry?
}

struct SafariExtensionRuntimeDiagnosticReport: Codable, Equatable, Sendable {
    let generatedAt: Date
    let entries: [SafariExtensionRuntimeDiagnosticEntry]
    let discoveredBundleKindCounts: [String: Int]
    let contentBlockers: [SafariContentBlockerRuntimeDiagnosticRecord]
    let attachedSafariContentRuleListIdentifiers: [String]
    let unsupportedLegacyCandidates: [UnsupportedSafariExtensionDiagnosticCandidate]
    let globalSuppressionReport: SafariExtensionNativeMessagingSuppressionReport
    let sdkProbeNote: String
}

struct SafariContentBlockerRuntimeDiagnosticRecord: Codable, Equatable, Sendable {
    let extensionBundleIdentifier: String
    let displayName: String
    let containingAppName: String
    let resourceFingerprint: String
    let isEnabled: Bool
    let compileStatus: SafariContentBlockerCompileStatus
    let lastError: String?
    let ruleListCount: Int
    let ignoredEmptyRuleListCount: Int
}

struct UnsupportedSafariExtensionDiagnosticCandidate: Codable, Equatable, Sendable {
    let extensionBundleIdentifier: String
    let displayName: String
    let containingAppName: String
    let extensionPointIdentifier: String
    let reason: String
}

@MainActor
enum SafariExtensionRuntimeDiagnosticsBuilder {
    static func build(
        targets: [SafariExtensionCompatibilityTargets.Target] = SafariExtensionCompatibilityTargets.all,
        discovered: [DiscoveredSafariExtensionCandidate],
        importStore: SafariExtensionImportStore = .shared,
        installedExtensions: [InstalledExtension] = [],
        contentBlockerRecords: [InstalledSafariContentBlockerRecord] = [],
        attachedSafariContentRuleListIdentifiers: [String] = [],
        extensionManager: ExtensionManager? = nil,
        extensionsModuleEnabled: Bool = true
    ) -> SafariExtensionRuntimeDiagnosticReport {
        let compatibility = SafariExtensionCompatibilityReportBuilder.build(
            targets: targets,
            discovered: discovered,
            importStore: importStore,
            installedExtensions: installedExtensions,
            extensionManager: extensionManager,
            extensionsModuleEnabled: extensionsModuleEnabled
        )
        let compatibilityByKey = Dictionary(
            uniqueKeysWithValues: compatibility.entries.map { ($0.targetKey, $0) }
        )
        let suppressionReport = SafariExtensionNativeMessagingSuppressionProbe.evaluate()

        let entries = targets.map { target in
            let compatibilityEntry = compatibilityByKey[target.key]
            let installed = installedExtensions.first {
                $0.id == compatibilityEntry?.installedExtensionId
            }
            let context = compatibilityEntry?.installedExtensionId.flatMap {
                extensionManager?.getExtensionContext(for: $0)
            }

            let runtimeStatus = buildRuntimeStatus(
                target: target,
                installed: installed,
                context: context,
                compatibilityEntry: compatibilityEntry,
                extensionsModuleEnabled: extensionsModuleEnabled,
                suppressionReport: suppressionReport
            )

            return SafariExtensionRuntimeDiagnosticEntry(
                targetKey: target.key,
                displayName: target.displayName,
                runtimeStatus: runtimeStatus,
                manualVerification: SafariExtensionManualVerificationCatalog.row(
                    forTargetKey: target.key
                ),
                compatibilityEntry: compatibilityEntry
            )
        }

        return SafariExtensionRuntimeDiagnosticReport(
            generatedAt: Date(),
            entries: entries,
            discoveredBundleKindCounts: discoveredBundleKindCounts(discovered),
            contentBlockers: contentBlockerRecords.map {
                SafariContentBlockerRuntimeDiagnosticRecord(record: $0)
            },
            attachedSafariContentRuleListIdentifiers: attachedSafariContentRuleListIdentifiers.sorted(),
            unsupportedLegacyCandidates: unsupportedLegacyCandidates(discovered),
            globalSuppressionReport: suppressionReport,
            sdkProbeNote: SafariExtensionHostRelayAPIProbe.sdkProbeNote
        )
    }

    static func logIfDiagnosticsEnabled(_ report: SafariExtensionRuntimeDiagnosticReport) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            guard let data = try? encoder.encode(report),
                  let json = String(data: data, encoding: .utf8)
            else {
                RuntimeDiagnostics.debug(
                    "SafariExtensionRuntimeDiagnosticReport encode failed",
                    category: "SafariExtension"
                )
                return
            }

            RuntimeDiagnostics.debug(
                "SafariExtensionRuntimeDiagnosticReport \(json)",
                category: "SafariExtension"
            )
        #else
            _ = report
        #endif
    }

    private static func buildRuntimeStatus(
        target: SafariExtensionCompatibilityTargets.Target,
        installed: InstalledExtension?,
        context: WKWebExtensionContext?,
        compatibilityEntry: SafariExtensionCompatibilityEntry?,
        extensionsModuleEnabled: Bool,
        suppressionReport: SafariExtensionNativeMessagingSuppressionReport
    ) -> SafariExtensionRuntimeStatusSnapshot {
        var notes: [String] = []

        let scriptingStatus = resolveScriptingStatus(
            installed: installed,
            context: context,
            extensionsModuleEnabled: extensionsModuleEnabled
        )
        let contentScriptStatus = resolveContentScriptStatus(
            installed: installed,
            compatibilityEntry: compatibilityEntry,
            extensionsModuleEnabled: extensionsModuleEnabled
        )
        let hostPermissionStatus = resolveHostPermissionStatus(
            installed: installed,
            context: context,
            extensionsModuleEnabled: extensionsModuleEnabled
        )
        let tabFrameMappingStatus = SafariExtensionTabFrameMappingProbe.evaluate().status
        if tabFrameMappingStatus != .wired {
            notes.append(SafariExtensionTabFrameMappingProbe.evaluate().detail)
        }
        let popupAnchorStatus = SafariExtensionPopupAnchorProbe.evaluate().status
        if popupAnchorStatus != .wired {
            notes.append(SafariExtensionPopupAnchorProbe.evaluate().detail)
        }

        let isPasswordManager = SafariExtensionNativeMessagingClassificationCatalog
            .passwordManagerTargetKeys.contains(target.key)
        let launchSuppressionExpected = isPasswordManager && suppressionReport.repeatedCallSuppressionEnabled
        let sessionState: SumiNativeMessagingSessionState? =
            isPasswordManager ? .unknownProtocolInitial : nil

        let autofillInfrastructure = SafariExtensionAutofillInfrastructureClassifier
            .classifyInfrastructure(extensionsModuleEnabled: extensionsModuleEnabled)
        if autofillInfrastructure.isReady == false {
            notes.append(
                "autofill blocker=\(autofillInfrastructure.primaryBlocker.rawValue): \(autofillInfrastructure.detail)"
            )
        }

        if isPasswordManager {
            if target.key == "bitwarden",
               SumiNativeMessagingAdapterRegistry.shared.adapter(
                   forHostBundleIdentifier: BitwardenNativeMessagingIdentifiers.hostBundleIdentifier
               ) != nil
            {
                notes.append(
                    "Bitwarden adapter registered; use adapterCompatibility routing fields and failure buckets instead of companionAppProtocolUnknown"
                )
            } else {
                notes.append("companionAppProtocolUnknown expected until companion IPC is documented")
            }
            if autofillInfrastructure.isReady {
                notes.append(
                    "autofill infrastructure ready; tab-level blockers require active tab probe (file:// needs http://127.0.0.1 fixture server)"
                )
            }
        }

        return SafariExtensionRuntimeStatusSnapshot(
            scriptingStatus: scriptingStatus,
            contentScriptStatus: contentScriptStatus,
            hostPermissionStatus: hostPermissionStatus,
            tabFrameMappingStatus: tabFrameMappingStatus,
            popupAnchorStatus: popupAnchorStatus,
            autofillInfrastructureBlocker: autofillInfrastructure.primaryBlocker,
            nativeMessagingSessionState: sessionState,
            launchSuppressionExpected: launchSuppressionExpected,
            suppressionReport: suppressionReport,
            detailNotes: notes
        )
    }

    private static func resolveScriptingStatus(
        installed: InstalledExtension?,
        context: WKWebExtensionContext?,
        extensionsModuleEnabled: Bool
    ) -> SafariExtensionCapabilityStatus {
        guard extensionsModuleEnabled else { return .unavailable }
        guard let installed else { return .notApplicable }

        let permissions = stringArray(from: installed.manifest["permissions"])
            + stringArray(from: installed.manifest["optional_permissions"])
        guard permissions.contains("scripting") else { return .notApplicable }
        guard let context else { return .declared }

        let requested = Set(context.webExtension.requestedPermissions.map(\.rawValue))
        return requested.contains(WKWebExtension.Permission.scripting.rawValue) ? .granted : .declared
    }

    private static func resolveContentScriptStatus(
        installed: InstalledExtension?,
        compatibilityEntry: SafariExtensionCompatibilityEntry?,
        extensionsModuleEnabled: Bool
    ) -> SafariExtensionCapabilityStatus {
        guard extensionsModuleEnabled else { return .unavailable }
        guard let installed, installed.hasContentScripts else { return .notApplicable }
        guard compatibilityEntry?.isEnabled == true else { return .declared }

        if SafariExtensionContentScriptProbe.isTabReconcilePathWiredInSources() {
            return compatibilityEntry?.isContextLoaded == true ? .wired : .declared
        }
        return .error
    }

    private static func resolveHostPermissionStatus(
        installed: InstalledExtension?,
        context: WKWebExtensionContext?,
        extensionsModuleEnabled: Bool
    ) -> SafariExtensionCapabilityStatus {
        guard extensionsModuleEnabled else { return .unavailable }
        guard let installed else { return .notApplicable }

        let declared =
            stringArray(from: installed.manifest["host_permissions"])
            + stringArray(from: installed.manifest["permissions"]).filter {
                $0 == "<all_urls>" || $0.hasPrefix("http") || $0.hasPrefix("*://")
            }
        guard declared.isEmpty == false else { return .notApplicable }
        guard let context else { return .declared }

        let granted = context.grantedPermissionMatchPatterns.count
        return granted > 0 ? .granted : .declared
    }

    private static func stringArray(from value: Any?) -> [String] {
        value as? [String] ?? []
    }

    private static func discoveredBundleKindCounts(
        _ candidates: [DiscoveredSafariExtensionCandidate]
    ) -> [String: Int] {
        var counts = Dictionary(
            uniqueKeysWithValues: SafariExtensionBundleKind.allCases.map { ($0.rawValue, 0) }
        )
        for candidate in candidates {
            counts[candidate.bundleKind.rawValue, default: 0] += 1
        }
        return counts
    }

    private static func unsupportedLegacyCandidates(
        _ candidates: [DiscoveredSafariExtensionCandidate]
    ) -> [UnsupportedSafariExtensionDiagnosticCandidate] {
        candidates
            .filter { $0.bundleKind == .legacySafariAppExtension }
            .map {
                UnsupportedSafariExtensionDiagnosticCandidate(
                    extensionBundleIdentifier: $0.extensionBundleIdentifier,
                    displayName: $0.displayName,
                    containingAppName: $0.containingAppName,
                    extensionPointIdentifier: $0.extensionPointIdentifier,
                    reason: "Legacy Safari App Extensions are hosted by Safari.app and cannot run inside Sumi through public WebKit APIs."
                )
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }
}

extension SafariContentBlockerRuntimeDiagnosticRecord {
    init(record: InstalledSafariContentBlockerRecord) {
        self.extensionBundleIdentifier = record.extensionBundleIdentifier
        self.displayName = record.displayName
        self.containingAppName = record.containingAppName
        self.resourceFingerprint = record.resourceFingerprint
        self.isEnabled = record.isEnabled
        self.compileStatus = record.compileStatus
        self.lastError = record.lastError
        self.ruleListCount = record.ruleListCount
        self.ignoredEmptyRuleListCount = record.ignoredEmptyRuleListCount
    }
}

enum SafariExtensionPopupAnchorProbe {
    struct Result: Equatable {
        let passed: Bool
        let status: SafariExtensionCapabilityStatus
        let detail: String
    }

    static let requiredSymbols: [String] = [
        "func captureActionPopupAnchor(",
        "func resolveActionPopupAnchor(",
        "func presentResolvedExtensionActionPopup(",
        "ExtensionActionPopupAnchorResolution",
        "extensionActionPopupAnchorRect(for:",
    ]

    static func evaluate(anchorSource: String? = nil) -> Result {
        let source = anchorSource ?? loadAnchorSource()
        guard let source else {
            return Result(
                passed: false,
                status: .error,
                detail: "ExtensionManager+ActionPopupAnchor.swift source unavailable"
            )
        }

        let missing = requiredSymbols.filter { source.contains($0) == false }
        guard missing.isEmpty else {
            return Result(
                passed: false,
                status: .error,
                detail: "Popup anchor probe missing: \(missing.joined(separator: ", "))"
            )
        }

        return Result(
            passed: true,
            status: .wired,
            detail: "Click-time anchor capture + resolve + present path wired"
        )
    }

    private static func loadAnchorSource() -> String? {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ExtensionManager+ActionPopupAnchor.swift")
        return try? String(contentsOf: path, encoding: .utf8)
    }
}

enum SafariExtensionTabFrameMappingProbe {
    struct Result: Equatable {
        let passed: Bool
        let status: SafariExtensionCapabilityStatus
        let detail: String
    }

    static let requiredBridgeSymbols: [String] = [
        "final class ExtensionWindowAdapter",
        "final class ExtensionTabAdapter",
        "func activeTab(for extensionContext:",
        "func tabs(for extensionContext:",
        "func frame(for extensionContext:",
        "func webView(for extensionContext:",
    ]

    static func evaluate(bridgeSource: String? = nil) -> Result {
        let source = bridgeSource ?? loadBridgeAdapterSource()
        guard let source else {
            return Result(
                passed: false,
                status: .error,
                detail: "Extension bridge adapter source unavailable"
            )
        }

        let missing = requiredBridgeSymbols.filter { source.contains($0) == false }
        guard missing.isEmpty else {
            return Result(
                passed: false,
                status: .error,
                detail: "Tab/frame mapping probe missing: \(missing.joined(separator: ", "))"
            )
        }

        return Result(
            passed: true,
            status: .wired,
            detail: "Window/tab adapters expose activeTab, tabs, frame, and webView surfaces"
        )
    }

    private static func loadBridgeAdapterSource() -> String? {
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

enum SafariExtensionNativeMessagingSuppressionProbe {
    static func evaluate(
        relaySource: String? = nil,
        loopGuardSource: String? = nil,
        coalescerSource: String? = nil
    ) -> SafariExtensionNativeMessagingSuppressionReport {
        let relay = relaySource ?? loadSource(named: "SumiNativeMessagingRelay.swift")
        let loopGuard = loopGuardSource ?? loadSource(named: "SumiNativeMessagingRelayLoopGuard.swift")
        let coalescer = coalescerSource ?? loadSource(named: "SumiNativeMessagingDiagnosticCoalescer.swift")

        let suppressionEnabled =
            loopGuard?.contains("recordCompanionAppProtocolUnknown") == true
            && loopGuard?.contains("launchSuppressed") == true
            && relay?.contains("recordSuppressedRetry") == true
        let coalescedLogging =
            coalescer?.contains("shouldCoalesce") == true
            && relay?.contains("SumiNativeMessagingDiagnosticCoalescer") == true
        let sessionStateTracking =
            relay?.contains("sessionState:") == true
            && loopGuard?.contains("func sessionState(") == true

        return SafariExtensionNativeMessagingSuppressionReport(
            repeatedCallSuppressionEnabled: suppressionEnabled,
            coalescedLoggingEnabled: coalescedLogging,
            sessionStateTrackingEnabled: sessionStateTracking,
            companionProtocolUnknownDeterministic: relay?.contains("companionAppProtocolUnknown") == true,
            supportedRelayProtocolHostCount: SumiNativeMessagingRelayLoopGuard
                .supportedRelayProtocolHostBundleIdentifiers.count,
            note: """
            Repeated companionAppProtocolUnknown / launchSuppressed diagnostics are coalesced when verbose logging is enabled. \
            WebKit extension console may still log one NSError per delegate callback; Sumi coalesces duplicate SafariNativeMessaging \
            lines (coalesced ext=… repeatCount=… bucket=…) after the first detailed line per session key.
            """
        )
    }

    private static func loadSource(named fileName: String) -> String? {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent(fileName)
        return try? String(contentsOf: path, encoding: .utf8)
    }
}

enum SafariExtensionPasswordManagerFormFixtureProbe {
    struct Result: Equatable {
        let passed: Bool
        let detail: String
    }

    static let legacyFixtureRelativePath = "SumiTests/Fixtures/Extensions/login-form.html"
    static let autofillFixtureRelativePaths = [
        "SumiTests/Fixtures/AutofillPages/login-basic.html",
        "SumiTests/Fixtures/AutofillPages/login-autocomplete.html",
        "SumiTests/Fixtures/AutofillPages/login-same-origin-iframe.html",
        "SumiTests/Fixtures/AutofillPages/login-cross-origin-iframe.html",
        "SumiTests/Fixtures/AutofillPages/login-dynamic-spa.html",
        "SumiTests/Fixtures/AutofillPages/shared/fill-probe.js",
    ]

    static func evaluate() -> Result {
        let repoRoot = repoRootURL()
        let missing = missingFixturePaths(repoRoot: repoRoot)
        guard missing.isEmpty else {
            return Result(
                passed: false,
                detail: "Missing autofill fixtures: \(missing.joined(separator: ", "))"
            )
        }

        let basicURL = repoRoot.appendingPathComponent(
            "SumiTests/Fixtures/AutofillPages/login-basic.html"
        )
        guard let contents = try? String(contentsOf: basicURL, encoding: .utf8),
              contents.contains("type=\"password\""),
              contents.contains("autocomplete=\"username\"")
        else {
            return Result(
                passed: false,
                detail: "login-basic.html missing password/username fields"
            )
        }

        return Result(
            passed: true,
            detail: """
            Controlled autofill fixtures available; serve with scripts/serve_autofill_fixtures.sh \
            at http://127.0.0.1:8765/login-basic.html (do not use file:// for <all_urls> PM tests)
            """
        )
    }

    private static func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func missingFixturePaths(repoRoot: URL) -> [String] {
        var paths = autofillFixtureRelativePaths
        paths.append(legacyFixtureRelativePath)
        return paths.filter {
            FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent($0).path) == false
        }
    }
}

@MainActor
extension SumiExtensionsModule {
    func safariExtensionRuntimeDiagnosticReport() -> SafariExtensionRuntimeDiagnosticReport {
        var issues: [SafariExtensionScannerIssue] = []
        let discovered = SafariExtensionScanner().scanInstalledExtensions(issues: &issues)
        SafariExtensionImportStore.shared.refreshDiscoveredCandidates(discovered)

        let manager = managerIfLoadedAndEnabled()
        let report = SafariExtensionRuntimeDiagnosticsBuilder.build(
            discovered: discovered,
            installedExtensions: manager?.installedExtensions ?? [],
            contentBlockerRecords: installedSafariContentBlockers(),
            attachedSafariContentRuleListIdentifiers: safariContentBlockerAttachedRuleListIdentifiers(),
            extensionManager: manager,
            extensionsModuleEnabled: isEnabled
        )
        SafariExtensionRuntimeDiagnosticsBuilder.logIfDiagnosticsEnabled(report)
        return report
    }

    #if DEBUG
    func printSafariExtensionDevDiagnosticsReportToConsole() {
        guard isEnabled else {
            print("SafariExtensionDevDiagnosticsReport: skipped — Extensions module is disabled")
            return
        }

        let acceptance = safariExtensionAcceptanceMatrix()
        let runtime = safariExtensionRuntimeDiagnosticReport()
        let nativeMessaging = safariExtensionNativeMessagingProbe()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]

        struct DevReport: Codable {
            let acceptanceMatrix: SafariExtensionAcceptanceMatrix
            let runtimeDiagnostics: SafariExtensionRuntimeDiagnosticReport
            let nativeMessagingProbe: SafariExtensionNativeMessagingProbeReport
            let adapterCompatibility: [SafariExtensionNativeMessagingAdapterCompatibilityStatus]
        }

        let report = DevReport(
            acceptanceMatrix: acceptance,
            runtimeDiagnostics: runtime,
            nativeMessagingProbe: nativeMessaging,
            adapterCompatibility: nativeMessaging.adapterCompatibility
        )

        guard let data = try? encoder.encode(report),
              let json = String(data: data, encoding: .utf8)
        else {
            print("SafariExtensionDevDiagnosticsReport: encode failed")
            return
        }

        print("SafariExtensionDevDiagnosticsReport:\n\(json)")
        SafariExtensionRuntimeDiagnosticsBuilder.logIfDiagnosticsEnabled(runtime)
    }
    #endif
}
