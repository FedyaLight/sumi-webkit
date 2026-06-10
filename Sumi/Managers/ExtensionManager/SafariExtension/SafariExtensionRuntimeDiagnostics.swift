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
    let globalSuppressionReport: SafariExtensionNativeMessagingSuppressionReport
    let sdkProbeNote: String
}

@MainActor
enum SafariExtensionRuntimeDiagnosticsBuilder {
    static func build(
        targets: [SafariExtensionCompatibilityTargets.Target] = SafariExtensionCompatibilityTargets.all,
        discovered: [DiscoveredSafariExtensionCandidate],
        importStore: SafariExtensionImportStore = .shared,
        installedExtensions: [InstalledExtension] = [],
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
        }

        return SafariExtensionRuntimeStatusSnapshot(
            scriptingStatus: scriptingStatus,
            contentScriptStatus: contentScriptStatus,
            hostPermissionStatus: hostPermissionStatus,
            tabFrameMappingStatus: tabFrameMappingStatus,
            popupAnchorStatus: popupAnchorStatus,
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
        let source = bridgeSource ?? loadBridgeSource()
        guard let source else {
            return Result(
                passed: false,
                status: .error,
                detail: "ExtensionBridge.swift source unavailable"
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

    private static func loadBridgeSource() -> String? {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ExtensionBridge.swift")
        return try? String(contentsOf: path, encoding: .utf8)
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

    static let fixtureRelativePath = "SumiTests/Fixtures/Extensions/login-form.html"

    static func evaluate() -> Result {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repoRoot.appendingPathComponent(fixtureRelativePath)
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            return Result(
                passed: false,
                detail: "Missing local login form fixture at \(fixtureRelativePath)"
            )
        }

        guard let contents = try? String(contentsOf: fixtureURL, encoding: .utf8),
              contents.contains("type=\"password\""),
              contents.contains("autocomplete=\"username\"")
        else {
            return Result(
                passed: false,
                detail: "Login form fixture missing password/username fields"
            )
        }

        return Result(
            passed: true,
            detail: "Local login-form.html fixture available for PM autofill manual probe"
        )
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
