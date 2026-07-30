//
//  SafariExtensionRuntimeDiagnostics.swift
//  Sumi
//
//  Sanitized runtime capability diagnostics for Safari Web Extension targets.
//  Never logs message bodies, storage payloads, or credentials.
//

import Foundation
import WebKit
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
        "func presentResolvedExtensionActionPopup(",
        "ExtensionActionPopupAnchorResolution",
        "extensionActionPopupAnchorRect(for:",
    ]

    static func evaluate(anchorSource: String? = nil) -> Result {
        if let anchorSource {
            let missing = requiredSymbols.filter { anchorSource.contains($0) == false }
            guard missing.isEmpty else {
                return Result(
                    passed: false,
                    status: .error,
                    detail: "Popup anchor probe missing: \(missing.joined(separator: ", "))"
                )
            }
        }

        _ = ExtensionActionPopupAnchorResolution.self

        return Result(
            passed: true,
            status: .wired,
            detail: "Click-time anchor capture + resolve + present path wired"
        )
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
        if let bridgeSource {
            let missing = requiredBridgeSymbols.filter { bridgeSource.contains($0) == false }
            guard missing.isEmpty else {
                return Result(
                    passed: false,
                    status: .error,
                    detail: "Tab/frame mapping probe missing: \(missing.joined(separator: ", "))"
                )
            }
        }

        guard #available(macOS 15.5, *) else {
            return Result(
                passed: false,
                status: .error,
                detail: "WebKit extension bridge adapters require macOS 15.5+"
            )
        }

        _ = ExtensionWindowAdapter.self
        _ = ExtensionTabAdapter.self

        return Result(
            passed: true,
            status: .wired,
            detail: "Compiled window/tab adapters expose activeTab, tabs, frame, and webView surfaces"
        )
    }
}

enum SafariExtensionNativeMessagingSuppressionProbe {
    @MainActor
    static func evaluate(
        relaySource: String? = nil,
        loopGuardSource: String? = nil,
        coalescerSource: String? = nil
    ) -> SafariExtensionNativeMessagingSuppressionReport {
        if relaySource != nil || loopGuardSource != nil || coalescerSource != nil {
            return evaluateSources(
                relay: relaySource,
                loopGuard: loopGuardSource,
                coalescer: coalescerSource
            )
        }

        let loopGuard = SumiNativeMessagingRelayLoopGuard()
        let unsupportedKey = SumiNativeMessagingRelayLoopGuard.SessionKey(
            profileId: nil,
            extensionId: "diagnostic-probe",
            applicationIdentifier: "com.example.unsupported"
        )
        loopGuard.recordCompanionAppProtocolUnknown(
            key: unsupportedKey,
            launchAttempted: false
        )
        loopGuard.recordSuppressedRetry(key: unsupportedKey)
        let suppressionEvaluation = loopGuard.evaluate(
            key: unsupportedKey,
            hostBundleIdentifier: "com.example.unsupported"
        )
        let sessionState = loopGuard.sessionState(
            policyDenial: nil,
            profileRuntimeLoaded: true,
            evaluation: nil,
            hostBundleIdentifier: "com.example.unsupported",
            key: unsupportedKey
        )
        let coalescedLogging = coalescerEmitsSummaryForSuppressedRetry()

        return SafariExtensionNativeMessagingSuppressionReport(
            repeatedCallSuppressionEnabled: suppressionEvaluation.launchSuppressed,
            coalescedLoggingEnabled: coalescedLogging,
            sessionStateTrackingEnabled: sessionState != nil,
            companionProtocolUnknownDeterministic: SumiNativeMessagingRelay.ErrorCode
                .companionAppProtocolUnknown.rawValue > 0,
            supportedRelayProtocolHostCount: SumiNativeMessagingRelayLoopGuard
                .supportedRelayProtocolHostBundleIdentifiers.count,
            note: """
            Repeated companionAppProtocolUnknown / launchSuppressed diagnostics are coalesced when verbose logging is enabled. \
            WebKit extension console may still log one NSError per delegate callback; Sumi coalesces duplicate SafariNativeMessaging \
            lines (coalesced ext=… repeatCount=… bucket=…) after the first detailed line per session key.
            """
        )
    }

    private static func evaluateSources(
        relay: String?,
        loopGuard: String?,
        coalescer: String?
    ) -> SafariExtensionNativeMessagingSuppressionReport {
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

    @MainActor
    private static func coalescerEmitsSummaryForSuppressedRetry() -> Bool {
        var styles: [SumiNativeMessagingDiagnosticLogStyle] = []
        let coalescer = SumiNativeMessagingDiagnosticCoalescer { _, style in
            styles.append(style)
        }
        let base = SafariExtensionNativeMessagingDiagnostic(
            extensionId: "diagnostic-probe",
            direction: .send,
            requestedApplicationIdentifier: "com.example.unsupported",
            hostBundleIdentifier: "com.example.unsupported",
            resolverBucket: nil,
            outcome: .companionAppProtocolUnknown,
            errorDomain: SumiNativeMessagingRelay.errorDomain,
            errorCode: SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue,
            retryCountBucket: SumiNativeMessagingRetryCountBucket.none
        )
        coalescer.record(base)
        coalescer.record(
            SafariExtensionNativeMessagingDiagnostic(
                extensionId: base.extensionId,
                direction: base.direction,
                requestedApplicationIdentifier: base.requestedApplicationIdentifier,
                hostBundleIdentifier: base.hostBundleIdentifier,
                resolverBucket: base.resolverBucket,
                outcome: .launchSuppressed,
                errorDomain: base.errorDomain,
                errorCode: base.errorCode,
                launchSuppressed: true,
                retryCountBucket: .first
            )
        )
        return styles.contains {
            if case .summarized = $0 { return true }
            return false
        }
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

        let contents: String
        do {
            contents = try String(contentsOf: basicURL, encoding: .utf8)
        } catch {
            return Result(
                passed: false,
                detail: "Could not read login-basic.html: \(error.localizedDescription)"
            )
        }

        guard contents.contains("type=\"password\""),
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
        compatibilityDiagnostics.runtimeDiagnosticReport()
    }

    #if DEBUG
    func printSafariExtensionAcceptanceCheckToConsole() {
        guard isEnabled else {
            print("SafariExtensionAcceptanceMatrix: skipped — Extensions module is disabled")
            return
        }

        let matrix = safariExtensionAcceptanceMatrix()
        do {
            let json = try SafariExtensionDiagnosticJSON.prettyPrintedString(matrix)
            print("SafariExtensionAcceptanceMatrix:\n\(json)")
        } catch {
            print("SafariExtensionAcceptanceMatrix: encode failed: \(error.localizedDescription)")
        }
        SafariExtensionAcceptanceMatrixBuilder.logIfDiagnosticsEnabled(matrix)
    }

    func printSafariExtensionDevDiagnosticsReportToConsole() {
        guard isEnabled else {
            print("SafariExtensionDevDiagnosticsReport: skipped — Extensions module is disabled")
            return
        }

        let acceptance = safariExtensionAcceptanceMatrix()
        let runtime = safariExtensionRuntimeDiagnosticReport()
        let nativeMessaging = safariExtensionNativeMessagingProbe()

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

        do {
            let json = try SafariExtensionDiagnosticJSON.prettyPrintedString(report)
            print("SafariExtensionDevDiagnosticsReport:\n\(json)")
        } catch {
            print("SafariExtensionDevDiagnosticsReport: encode failed: \(error.localizedDescription)")
        }
        SafariExtensionRuntimeDiagnosticsBuilder.logIfDiagnosticsEnabled(runtime)
    }
    #endif
}
