//
//  SafariExtensionNativeMessagingProbeBuilder.swift
//  Sumi
//
//  DEBUG native-messaging probe report construction and encoded logging.
//

import AppKit
import Foundation

@MainActor
enum SafariExtensionNativeMessagingProbeBuilder {
    static func build(
        targets: [SafariExtensionCompatibilityTargets.Target] = SafariExtensionCompatibilityTargets.all,
        discovered: [DiscoveredSafariExtensionCandidate],
        importStore: SafariExtensionImportStore = .shared,
        installedExtensions: [InstalledExtension] = [],
        extensionManager: ExtensionManager? = nil,
        extensionsModuleEnabled: Bool = true,
        adapterRegistry: SumiNativeMessagingAdapterRegistry = .shared
    ) -> SafariExtensionNativeMessagingProbeReport {
        let registeredAdapterIdentifiers = adapterRegistry.registeredProtocolIdentifiers
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
            let isPasswordManager = SafariExtensionNativeMessagingClassificationCatalog
                .passwordManagerTargetKeys.contains(target.key)

            let errorBucket: SafariExtensionNativeMessagingErrorBucket = {
                guard extensionsModuleEnabled else { return .moduleDisabled }
                guard compatibilityEntry?.isImported == true else { return .extensionNotImported }
                guard compatibilityEntry?.isEnabled == true else { return .extensionDisabled }
                if isPasswordManager {
                    return passwordManagerPreviewErrorBucket(
                        targetKey: target.key,
                        hostBundleIdentifier: previewHostBundleIdentifier(
                            target: target,
                            installed: installed,
                            importStore: importStore
                        ),
                        adapterRegistry: adapterRegistry
                    )
                }
                return .none
            }()

            let connectionBucket: SafariExtensionNativeMessagingConnectionBucket = {
                guard extensionsModuleEnabled else { return .policyDenied }
                guard compatibilityEntry?.isImported == true else { return .notAttempted }
                if isPasswordManager {
                    let hostBundleIdentifier = previewHostBundleIdentifier(
                        target: target,
                        installed: installed,
                        importStore: importStore
                    )
                    if hostBundleIdentifier.flatMap({
                        adapterRegistry.adapter(forHostBundleIdentifier: $0)
                    }) != nil {
                        return .notAttempted
                    }
                    return .companionProtocolUnknown
                }
                return .notAttempted
            }()

            let applicationIdentifier = previewApplicationIdentifier(for: target)
            let adapterPreview = previewAdapterStatus(
                target: target,
                installed: installed,
                importStore: importStore,
                adapterRegistry: adapterRegistry,
                extensionsModuleEnabled: extensionsModuleEnabled,
                compatibilityImported: compatibilityEntry?.isImported ?? false,
                compatibilityEnabled: compatibilityEntry?.isEnabled ?? false,
                isPasswordManager: isPasswordManager,
                errorBucket: errorBucket
            )

            return SafariExtensionNativeMessagingProbeEntry(
                targetKey: target.key,
                displayName: target.displayName,
                extensionId: compatibilityEntry?.installedExtensionId,
                isImported: compatibilityEntry?.isImported ?? false,
                isEnabled: compatibilityEntry?.isEnabled ?? false,
                popupStatus: compatibilityEntry?.popupLoadStatus ?? .unavailable,
                delegateCallbackObserved: SumiNativeMessagingRelay.delegateMethodsRegistered,
                applicationIdentifier: applicationIdentifier,
                resolverBucket: resolverBucket,
                connectionBucket: connectionBucket,
                errorBucket: errorBucket,
                classifications: SafariExtensionNativeMessagingClassificationCatalog
                    .classifications(forTargetKey: target.key),
                launchSuppressionExpected: isPasswordManager,
                expectedSessionState: isPasswordManager ? .unknownProtocolInitial : nil,
                adapterSelected: adapterPreview.adapterSelected,
                adapterIdentifier: adapterPreview.adapterIdentifier,
                appResolved: adapterPreview.appResolved,
                appLaunched: false,
                protocolStatus: adapterPreview.protocolStatus,
                handshakeStatus: adapterPreview.handshakeStatus,
                autofillPathStatus: adapterPreview.autofillPathStatus,
                failureBucket: adapterPreview.failureBucket
            )
        }

        let adapterCompatibility = targets.map { target in
            let compatibilityEntry = compatibilityByKey[target.key]
            let installed = installedExtensions.first {
                $0.id == compatibilityEntry?.installedExtensionId
            }
            let isPasswordManager = SafariExtensionNativeMessagingClassificationCatalog
                .passwordManagerTargetKeys.contains(target.key)
            let hostBundleIdentifier = previewHostBundleIdentifier(
                target: target,
                installed: installed,
                importStore: importStore
            )
            let errorBucket: SafariExtensionNativeMessagingErrorBucket = {
                guard extensionsModuleEnabled else { return .moduleDisabled }
                guard compatibilityEntry?.isImported == true else { return .extensionNotImported }
                guard compatibilityEntry?.isEnabled == true else { return .extensionDisabled }
                if isPasswordManager {
                    return passwordManagerPreviewErrorBucket(
                        targetKey: target.key,
                        hostBundleIdentifier: hostBundleIdentifier,
                        adapterRegistry: adapterRegistry
                    )
                }
                return .none
            }()
            let preview = previewAdapterStatus(
                target: target,
                installed: installed,
                importStore: importStore,
                adapterRegistry: adapterRegistry,
                extensionsModuleEnabled: extensionsModuleEnabled,
                compatibilityImported: compatibilityEntry?.isImported ?? false,
                compatibilityEnabled: compatibilityEntry?.isEnabled ?? false,
                isPasswordManager: isPasswordManager,
                errorBucket: errorBucket
            )
            let routingDiagnostics = routingDiagnosticsPreview(
                preview: preview,
                isPasswordManager: isPasswordManager,
                launchSuppressionExpected: isPasswordManager
            )
            return SafariExtensionNativeMessagingAdapterCompatibilityStatus(
                targetKey: target.key,
                displayName: target.displayName,
                applicationIdentifier: preview.applicationIdentifier,
                hostBundleIdentifier: preview.hostBundleIdentifier,
                adapterSelected: preview.adapterSelected,
                adapterIdentifier: preview.adapterIdentifier,
                appResolved: preview.appResolved,
                appInstalled: preview.appInstalled,
                launchSuppressionExpected: isPasswordManager,
                protocolStatus: preview.protocolStatus,
                handshakeStatus: preview.handshakeStatus,
                autofillPathStatus: preview.autofillPathStatus,
                failureBucket: preview.failureBucket,
                registeredAdapterIdentifiers: registeredAdapterIdentifiers,
                realTransportAttempted: routingDiagnostics.realTransportAttempted,
                desktopResolved: routingDiagnostics.desktopResolved,
                desktopRunning: routingDiagnostics.desktopRunning,
                desktopLaunchAttempted: routingDiagnostics.desktopLaunchAttempted,
                desktopLaunchSuppressed: routingDiagnostics.desktopLaunchSuppressed,
                biometricsStatusProbe: routingDiagnostics.biometricsStatusProbe,
                repeatedCallCountBucket: routingDiagnostics.repeatedCallCountBucket
            )
        }

        return SafariExtensionNativeMessagingProbeReport(
            generatedAt: Date(),
            entries: entries,
            adapterCompatibility: adapterCompatibility,
            globalClassifications: SafariExtensionNativeMessagingClassificationCatalog
                .globalReportClassifications(sumiRelayImplemented: true),
            suppressionReport: SafariExtensionNativeMessagingSuppressionProbe.evaluate(),
            sdkProbeNote: SafariExtensionHostRelaySDKProbeMetadata.sdkProbeNote,
            delegateMethodsRegistered: SumiNativeMessagingRelay.delegateMethodsRegistered,
            registeredAdapterIdentifiers: registeredAdapterIdentifiers
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

    private static func previewApplicationIdentifier(
        for target: SafariExtensionCompatibilityTargets.Target
    ) -> String? {
        target.nativeMessagingApplicationIdentifier
    }

    private static func previewResolverBucket(
        target: SafariExtensionCompatibilityTargets.Target,
        installed: InstalledExtension?,
        importStore: SafariExtensionImportStore
    ) -> SumiNativeMessagingResolverBucket? {
        guard let installed else { return nil }
        let resolution = SumiNativeMessagingAppResolver.resolve(
            requestedApplicationIdentifier: previewApplicationIdentifier(for: target),
            extensionId: installed.id,
            installedExtensions: [installed],
            importStore: importStore
        )
        return resolution?.bucket
    }

    private struct AdapterPreviewStatus {
        let applicationIdentifier: String?
        let hostBundleIdentifier: String?
        let adapterSelected: Bool
        let adapterIdentifier: String?
        let appResolved: Bool
        let appInstalled: Bool
        let protocolStatus: SumiNativeMessagingProtocolStatus
        let handshakeStatus: SumiNativeMessagingHandshakeStatus
        let autofillPathStatus: SumiNativeMessagingAutofillPathStatus
        let failureBucket: SafariExtensionNativeMessagingErrorBucket
    }

    private static func previewAdapterStatus(
        target: SafariExtensionCompatibilityTargets.Target,
        installed: InstalledExtension?,
        importStore: SafariExtensionImportStore,
        adapterRegistry: SumiNativeMessagingAdapterRegistry,
        extensionsModuleEnabled: Bool,
        compatibilityImported: Bool,
        compatibilityEnabled: Bool,
        isPasswordManager: Bool,
        errorBucket: SafariExtensionNativeMessagingErrorBucket
    ) -> AdapterPreviewStatus {
        let applicationIdentifier = previewApplicationIdentifier(for: target)
        let hostBundleIdentifier = previewHostBundleIdentifier(
            target: target,
            installed: installed,
            importStore: importStore
        )
        let adapter = hostBundleIdentifier.flatMap {
            adapterRegistry.adapter(forHostBundleIdentifier: $0)
        }
        let appResolved = hostBundleIdentifier != nil
        let appInstalled = hostBundleIdentifier.map {
            SumiNSWorkspaceHostApplicationLauncher().urlForApplication(withBundleIdentifier: $0) != nil
        } ?? false

        let protocolStatus: SumiNativeMessagingProtocolStatus = {
            guard extensionsModuleEnabled, compatibilityImported, compatibilityEnabled else {
                return .notApplicable
            }
            if target.key == "raindrop" { return .notApplicable }
            if adapter != nil { return .adapterReady }
            if isPasswordManager { return .protocolUnknown }
            return .adapterUnavailable
        }()

        let handshakeStatus: SumiNativeMessagingHandshakeStatus = {
            guard isPasswordManager else { return .notApplicable }
            return adapter != nil ? .notAttempted : .suppressed
        }()

        let autofillPathStatus: SumiNativeMessagingAutofillPathStatus = {
            guard isPasswordManager else { return .notApplicable }
            if SafariExtensionContentScriptProbe.isTabReconcilePathWiredInSources() {
                return .contentScriptsWired
            }
            return .pendingManualVerification
        }()

        let resolvedFailureBucket: SafariExtensionNativeMessagingErrorBucket = {
            switch errorBucket {
            case .moduleDisabled, .extensionNotImported, .extensionDisabled:
                return errorBucket
            default:
                return adapter != nil ? .none : errorBucket
            }
        }()

        return AdapterPreviewStatus(
            applicationIdentifier: applicationIdentifier,
            hostBundleIdentifier: hostBundleIdentifier,
            adapterSelected: adapter != nil,
            adapterIdentifier: adapter?.protocolIdentifier,
            appResolved: appResolved,
            appInstalled: appInstalled,
            protocolStatus: protocolStatus,
            handshakeStatus: handshakeStatus,
            autofillPathStatus: autofillPathStatus,
            failureBucket: resolvedFailureBucket
        )
    }

    private struct RoutingDiagnosticsPreview {
        let realTransportAttempted: Bool
        let desktopResolved: Bool
        let desktopRunning: Bool
        let desktopLaunchAttempted: Bool
        let desktopLaunchSuppressed: Bool
        let biometricsStatusProbe: SumiNativeMessagingBiometricsStatusProbe
        let repeatedCallCountBucket: SumiNativeMessagingRetryCountBucket
    }

    private static func routingDiagnosticsPreview(
        preview: AdapterPreviewStatus,
        isPasswordManager: Bool,
        launchSuppressionExpected: Bool
    ) -> RoutingDiagnosticsPreview {
        guard isPasswordManager else {
            return RoutingDiagnosticsPreview(
                realTransportAttempted: false,
                desktopResolved: false,
                desktopRunning: false,
                desktopLaunchAttempted: false,
                desktopLaunchSuppressed: false,
                biometricsStatusProbe: .notApplicable,
                repeatedCallCountBucket: .none
            )
        }

        let biometricsProbe: SumiNativeMessagingBiometricsStatusProbe = {
            guard preview.adapterSelected else { return .notApplicable }
            return .notAttempted
        }()

        return RoutingDiagnosticsPreview(
            realTransportAttempted: false,
            desktopResolved: preview.appResolved,
            desktopRunning: isDesktopRunning(bundleIdentifier: preview.hostBundleIdentifier),
            desktopLaunchAttempted: false,
            desktopLaunchSuppressed: launchSuppressionExpected && preview.adapterSelected == false,
            biometricsStatusProbe: biometricsProbe,
            repeatedCallCountBucket: .none
        )
    }

    private static func passwordManagerPreviewErrorBucket(
        targetKey: String,
        hostBundleIdentifier: String?,
        adapterRegistry: SumiNativeMessagingAdapterRegistry
    ) -> SafariExtensionNativeMessagingErrorBucket {
        if let hostBundleIdentifier,
           adapterRegistry.adapter(forHostBundleIdentifier: hostBundleIdentifier) != nil
        {
            return .none
        }
        return .companionAppProtocolUnknown
    }

    private static func isDesktopRunning(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .isEmpty == false
    }

    private static func previewHostBundleIdentifier(
        target: SafariExtensionCompatibilityTargets.Target,
        installed: InstalledExtension?,
        importStore: SafariExtensionImportStore
    ) -> String? {
        if let installed,
           let identity = SumiCompanionAppResolver.resolveIdentity(
               requestedApplicationIdentifier: previewApplicationIdentifier(for: target),
               extensionId: installed.id,
               installedExtensions: [installed],
               importStore: importStore
           )
        {
            return identity.resolvedBundleIdentifier
        }
        return target.nativeMessagingHostBundleIdentifier
    }
}
