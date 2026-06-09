//
//  SafariExtensionNativeMessagingDiagnostics.swift
//  Sumi
//
//  Sanitized native-messaging diagnostics and DEBUG probe reporting.
//  Never logs message bodies or credentials.
//

import Foundation
import WebKit

enum SafariExtensionNativeMessagingDirection: String, Codable, Sendable {
    case send
    case connect
    case portReceive
    case portRelay
}

enum SafariExtensionNativeMessagingOutcome: String, Codable, Sendable {
    case policyDenied
    case hostResolved
    case hostNotFound
    case hostLaunched
    case hostLaunchFailed
    case portConnected
    case companionAppProtocolUnknown
    case relayTimeout
    case relayCancelled
    case extensionContextMissing
    /// Legacy diagnostic bucket retained for decode compatibility in persisted logs.
    case hostRelayUnavailable
}

struct SafariExtensionNativeMessagingDiagnostic: Sendable, Equatable, Codable {
    let extensionId: String
    let direction: SafariExtensionNativeMessagingDirection
    let requestedApplicationIdentifier: String?
    let hostBundleIdentifier: String?
    let resolverBucket: SumiNativeMessagingResolverBucket?
    let outcome: SafariExtensionNativeMessagingOutcome
    let errorDomain: String?
    let errorCode: Int?
}

enum SafariExtensionNativeMessagingConnectionBucket: String, Codable, Sendable {
    case notAttempted
    case sendDelegateObserved
    case connectDelegateObserved
    case portSessionActive
    case portDisconnected
    case policyDenied
    case resolverNoMatch
    case companionProtocolUnknown
}

enum SafariExtensionNativeMessagingErrorBucket: String, Codable, Sendable {
    case none
    case moduleDisabled
    case extensionDisabled
    case extensionNotImported
    case privateBrowsingDenied
    case hostNotFound
    case hostLaunchFailed
    case companionAppProtocolUnknown
    case relayTimeout
    case relayCancelled
    case extensionContextMissing
    case unknown
}

struct SafariExtensionNativeMessagingProbeEntry: Codable, Equatable, Sendable, Identifiable {
    var id: String { extensionId ?? targetKey }

    let targetKey: String
    let displayName: String
    let extensionId: String?
    let isImported: Bool
    let isEnabled: Bool
    let popupStatus: SafariExtensionPopupLoadStatus
    let delegateCallbackObserved: Bool
    let applicationIdentifier: String?
    let resolverBucket: SumiNativeMessagingResolverBucket?
    let connectionBucket: SafariExtensionNativeMessagingConnectionBucket
    let errorBucket: SafariExtensionNativeMessagingErrorBucket
    let classifications: [SafariExtensionNativeMessagingClassification]
}

struct SafariExtensionNativeMessagingProbeReport: Codable, Equatable, Sendable {
    let generatedAt: Date
    let entries: [SafariExtensionNativeMessagingProbeEntry]
    let globalClassifications: [SafariExtensionNativeMessagingClassification]
    let sdkProbeNote: String
    let delegateMethodsRegistered: Bool
}

@MainActor
enum SafariExtensionNativeMessagingProbeBuilder {
    static func build(
        targets: [SafariExtensionCompatibilityTargets.Target] = SafariExtensionCompatibilityTargets.all,
        discovered: [DiscoveredSafariExtensionCandidate],
        importStore: SafariExtensionImportStore = .shared,
        installedExtensions: [InstalledExtension] = [],
        extensionManager: ExtensionManager? = nil,
        extensionsModuleEnabled: Bool = true
    ) -> SafariExtensionNativeMessagingProbeReport {
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

        let entries = targets.map { target in
            let compatibilityEntry = compatibilityByKey[target.key]
            let installed = installedExtensions.first {
                $0.id == compatibilityEntry?.installedExtensionId
            }
            let resolverBucket = previewResolverBucket(
                target: target,
                installed: installed,
                importStore: importStore
            )

            let errorBucket: SafariExtensionNativeMessagingErrorBucket = {
                guard extensionsModuleEnabled else { return .moduleDisabled }
                guard compatibilityEntry?.isImported == true else { return .extensionNotImported }
                guard compatibilityEntry?.isEnabled == true else { return .extensionDisabled }
                if SafariExtensionNativeMessagingClassificationCatalog
                    .passwordManagerTargetKeys.contains(target.key)
                {
                    return .companionAppProtocolUnknown
                }
                return .none
            }()

            let connectionBucket: SafariExtensionNativeMessagingConnectionBucket = {
                guard extensionsModuleEnabled else { return .policyDenied }
                guard compatibilityEntry?.isImported == true else { return .notAttempted }
                if SafariExtensionNativeMessagingClassificationCatalog
                    .passwordManagerTargetKeys.contains(target.key)
                {
                    return .companionProtocolUnknown
                }
                return .notAttempted
            }()

            return SafariExtensionNativeMessagingProbeEntry(
                targetKey: target.key,
                displayName: target.displayName,
                extensionId: compatibilityEntry?.installedExtensionId,
                isImported: compatibilityEntry?.isImported ?? false,
                isEnabled: compatibilityEntry?.isEnabled ?? false,
                popupStatus: compatibilityEntry?.popupLoadStatus ?? .unavailable,
                delegateCallbackObserved: SumiNativeMessagingRelay.delegateMethodsRegistered,
                applicationIdentifier: previewApplicationIdentifier(for: target.key),
                resolverBucket: resolverBucket,
                connectionBucket: connectionBucket,
                errorBucket: errorBucket,
                classifications: SafariExtensionNativeMessagingClassificationCatalog
                    .classifications(forTargetKey: target.key)
            )
        }

        return SafariExtensionNativeMessagingProbeReport(
            generatedAt: Date(),
            entries: entries,
            globalClassifications: SafariExtensionNativeMessagingClassificationCatalog
                .globalReportClassifications(sumiRelayImplemented: true),
            sdkProbeNote: SafariExtensionHostRelaySDKProbeMetadata.sdkProbeNote,
            delegateMethodsRegistered: SumiNativeMessagingRelay.delegateMethodsRegistered
        )
    }

    static func logIfDiagnosticsEnabled(_ report: SafariExtensionNativeMessagingProbeReport) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            guard let data = try? encoder.encode(report),
                  let json = String(data: data, encoding: .utf8)
            else {
                RuntimeDiagnostics.debug(
                    "SafariExtensionNativeMessagingProbe encode failed",
                    category: "SafariNativeMessaging"
                )
                return
            }

            RuntimeDiagnostics.debug(
                "SafariExtensionNativeMessagingProbe \(json)",
                category: "SafariNativeMessaging"
            )
        #else
            _ = report
        #endif
    }

    private static func previewApplicationIdentifier(for targetKey: String) -> String? {
        switch targetKey {
        case "bitwarden":
            return "com.bitwarden.desktop"
        case "1password":
            return "com.1password.safari"
        case "proton-pass":
            return "me.proton.pass.nm"
        case "raindrop":
            return nil
        default:
            return nil
        }
    }

    private static func previewResolverBucket(
        target: SafariExtensionCompatibilityTargets.Target,
        installed: InstalledExtension?,
        importStore: SafariExtensionImportStore
    ) -> SumiNativeMessagingResolverBucket? {
        guard let installed else { return nil }
        let resolution = SumiNativeMessagingAppResolver.resolve(
            requestedApplicationIdentifier: previewApplicationIdentifier(for: target.key),
            extensionId: installed.id,
            installedExtensions: [installed],
            importStore: importStore
        )
        return resolution?.bucket
    }
}

@MainActor
extension SumiExtensionsModule {
    func safariExtensionNativeMessagingProbe() -> SafariExtensionNativeMessagingProbeReport {
        var issues: [SafariExtensionScannerIssue] = []
        let discovered = SafariExtensionScanner().scanInstalledExtensions(issues: &issues)
        SafariExtensionImportStore.shared.refreshDiscoveredCandidates(discovered)

        let manager = managerIfLoadedAndEnabled()
        let report = SafariExtensionNativeMessagingProbeBuilder.build(
            discovered: discovered,
            installedExtensions: manager?.installedExtensions ?? [],
            extensionManager: manager,
            extensionsModuleEnabled: isEnabled
        )
        SafariExtensionNativeMessagingProbeBuilder.logIfDiagnosticsEnabled(report)
        return report
    }

    #if DEBUG
    func printSafariExtensionNativeMessagingProbeToConsole() {
        guard isEnabled else {
            print("SafariExtensionNativeMessagingProbe: skipped — Extensions module is disabled")
            return
        }

        let report = safariExtensionNativeMessagingProbe()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(report),
              let json = String(data: data, encoding: .utf8)
        else {
            print("SafariExtensionNativeMessagingProbe: encode failed")
            return
        }

        print("SafariExtensionNativeMessagingProbe:\n\(json)")
        SafariExtensionNativeMessagingProbeBuilder.logIfDiagnosticsEnabled(report)
    }
    #endif
}
