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
        importStore: any SafariExtensionImportRecordProviding,
        installedExtensions: [InstalledExtension] = [],
        contentBlockerRecords: [InstalledSafariContentBlockerRecord] = [],
        attachedSafariContentRuleListIdentifiers: [String] = [],
        extensionsModuleEnabled: Bool = true,
        runtime: SafariCompatibilityReportRuntime? = nil,
        adapterRegistry: SumiNativeMessagingAdapterRegistry = .production()
    ) -> SafariExtensionRuntimeDiagnosticReport {
        let compatibility = SafariExtensionCompatibilityReportBuilder.build(
            targets: targets,
            discovered: discovered,
            importStore: importStore,
            installedExtensions: installedExtensions,
            extensionsModuleEnabled: extensionsModuleEnabled,
            runtime: runtime
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
                (runtime ?? .inactive).context($0)
            }

            let runtimeStatus = buildRuntimeStatus(
                RuntimeStatusInput(
                    target: target,
                    installed: installed,
                    context: context,
                    compatibilityEntry: compatibilityEntry,
                    extensionsModuleEnabled: extensionsModuleEnabled,
                    suppressionReport: suppressionReport,
                    adapterRegistry: adapterRegistry
                )
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

            do {
                let json = try SafariExtensionDiagnosticJSON.prettyPrintedString(report)
                RuntimeDiagnostics.debug(
                    "SafariExtensionRuntimeDiagnosticReport \(json)",
                    category: "SafariExtension"
                )
            } catch {
                RuntimeDiagnostics.debug(
                    "SafariExtensionRuntimeDiagnosticReport encode failed: \(error.localizedDescription)",
                    category: "SafariExtension"
                )
            }
        #else
            _ = report
        #endif
    }

    private struct RuntimeStatusInput {
        let target: SafariExtensionCompatibilityTargets.Target
        let installed: InstalledExtension?
        let context: WKWebExtensionContext?
        let compatibilityEntry: SafariExtensionCompatibilityEntry?
        let extensionsModuleEnabled: Bool
        let suppressionReport: SafariExtensionNativeMessagingSuppressionReport
        let adapterRegistry: SumiNativeMessagingAdapterRegistry
    }

    private static func buildRuntimeStatus(
        _ input: RuntimeStatusInput
    ) -> SafariExtensionRuntimeStatusSnapshot {
        var notes: [String] = []

        let scriptingStatus = resolveScriptingStatus(
            installed: input.installed,
            context: input.context,
            extensionsModuleEnabled: input.extensionsModuleEnabled
        )
        let contentScriptStatus = resolveContentScriptStatus(
            installed: input.installed,
            compatibilityEntry: input.compatibilityEntry,
            extensionsModuleEnabled: input.extensionsModuleEnabled
        )
        let hostPermissionStatus = resolveHostPermissionStatus(
            installed: input.installed,
            context: input.context,
            extensionsModuleEnabled: input.extensionsModuleEnabled
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
            .passwordManagerTargetKeys.contains(input.target.key)
        let launchSuppressionExpected = isPasswordManager && input.suppressionReport.repeatedCallSuppressionEnabled
        let sessionState: SumiNativeMessagingSessionState? =
            isPasswordManager ? .unknownProtocolInitial : nil

        let autofillInfrastructure = SafariExtensionAutofillInfrastructureClassifier
            .classifyInfrastructure(extensionsModuleEnabled: input.extensionsModuleEnabled)
        if autofillInfrastructure.isReady == false {
            notes.append(
                "autofill blocker=\(autofillInfrastructure.primaryBlocker.rawValue): \(autofillInfrastructure.detail)"
            )
        }

        if isPasswordManager {
            if input.target.key == "bitwarden",
               input.adapterRegistry.adapter(
                   forHostBundleIdentifier: BitwardenNativeMessagingIdentifiers.hostBundleIdentifier
               ) != nil {
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
            suppressionReport: input.suppressionReport,
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
