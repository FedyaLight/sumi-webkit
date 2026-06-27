//
//  SafariExtensionNativeMessagingDiagnosticEnrichment.swift
//  Sumi
//
//  Native-messaging diagnostic enrichment and failure bucketing.
//

import Foundation

@MainActor
enum SafariExtensionNativeMessagingDiagnosticEnrichment {
    static func failureBucket(
        for diagnostic: SafariExtensionNativeMessagingDiagnostic,
        policyDenial: SumiNativeMessagingRelayPolicyDenial? = nil
    ) -> SafariExtensionNativeMessagingErrorBucket {
        if let policyDenial {
            switch policyDenial {
            case .moduleDisabled:
                return .moduleDisabled
            case .extensionNotEnabled:
                return .extensionDisabled
            case .extensionNotSafariImport, .arbitraryNativeMessagingDenied:
                return .extensionNotImported
            case .privateBrowsingDenied:
                return .privateBrowsingDenied
            }
        }

        switch diagnostic.outcome {
        case .policyDenied:
            return .moduleDisabled
        case .hostNotFound:
            return .hostNotFound
        case .hostLaunchFailed:
            return .hostLaunchFailed
        case .nativeHostManifestMissing:
            return .nativeHostManifestMissing
        case .nativeHostExecutableMissing:
            return .nativeHostExecutableMissing
        case .nativeHostPermissionDenied:
            return .permissionDenied
        case .nativeHostUnsupportedKind:
            return .unsupportedHostKind
        case .companionAppProtocolUnknown:
            if diagnostic.protocolAdapterAvailable == false {
                return .adapterUnavailable
            }
            if diagnostic.launchSuppressed == true {
                return .launchSuppressed
            }
            if diagnostic.adapterSelected == true,
               let errorCode = diagnostic.errorCode,
               diagnostic.errorDomain == SumiNativeMessagingRelay.errorDomain,
               let relayCode = SumiNativeMessagingRelay.ErrorCode(rawValue: errorCode)
            {
                switch relayCode {
                case .relayTimeout:
                    return .relayTimeout
                case .relayCancelled:
                    return .relayCancelled
                case .hostLaunchFailed:
                    return .hostLaunchFailed
                case .nativeHostManifestMissing:
                    return .nativeHostManifestMissing
                case .nativeHostExecutableMissing:
                    return .nativeHostExecutableMissing
                case .nativeHostPermissionDenied:
                    return .permissionDenied
                case .nativeHostUnsupportedKind:
                    return .unsupportedHostKind
                case .hostNotFound:
                    return .hostNotFound
                default:
                    return .unknown
                }
            }
            if diagnostic.adapterSelected == true {
                return .unknown
            }
            return .companionAppProtocolUnknown
        case .launchSuppressed, .launchRateLimited:
            return .launchSuppressed
        case .relayTimeout:
            return .relayTimeout
        case .relayCancelled:
            return .relayCancelled
        case .extensionContextMissing:
            return .extensionContextMissing
        case .hostResolved, .hostLaunched, .portConnected, .hostRelayUnavailable:
            return .none
        }
    }

    static func protocolStatus(
        adapter: SumiNativeMessagingProtocolAdapter?,
        evaluation: SumiCompanionAppResolverResult?,
        diagnostic: SafariExtensionNativeMessagingDiagnostic
    ) -> SumiNativeMessagingProtocolStatus {
        if adapter != nil {
            switch diagnostic.outcome {
            case .portConnected:
                return .relayActive
            case .hostLaunched:
                return .relayPending
            case .launchSuppressed, .launchRateLimited:
                return .suppressed
            case .relayTimeout, .relayCancelled, .hostLaunchFailed,
                 .nativeHostManifestMissing, .nativeHostExecutableMissing,
                 .nativeHostPermissionDenied, .nativeHostUnsupportedKind:
                return .failed
            default:
                return .adapterReady
            }
        }

        if let evaluation {
            switch evaluation {
            case .launchSuppressed, .launchRateLimited:
                return .suppressed
            case .appFoundButProtocolUnknown, .protocolAdapterUnavailable:
                return .adapterUnavailable
            case .appNotFound:
                return .failed
            default:
                break
            }
        }

        if diagnostic.protocolAdapterAvailable == true {
            return .adapterReady
        }
        return .protocolUnknown
    }

    static func handshakeStatus(
        for diagnostic: SafariExtensionNativeMessagingDiagnostic
    ) -> SumiNativeMessagingHandshakeStatus {
        switch diagnostic.direction {
        case .connect:
            switch diagnostic.outcome {
            case .portConnected:
                return .completed
            case .launchSuppressed, .launchRateLimited:
                return .suppressed
            case .hostResolved:
                return .pending
            case .hostLaunchFailed, .companionAppProtocolUnknown, .relayCancelled, .relayTimeout,
                 .nativeHostManifestMissing, .nativeHostExecutableMissing,
                 .nativeHostPermissionDenied, .nativeHostUnsupportedKind:
                return .failed
            default:
                return .notAttempted
            }
        case .send:
            switch diagnostic.outcome {
            case .portConnected, .hostLaunched:
                return .completed
            case .launchSuppressed, .launchRateLimited:
                return .suppressed
            case .hostLaunchFailed, .companionAppProtocolUnknown, .relayCancelled, .relayTimeout,
                 .nativeHostManifestMissing, .nativeHostExecutableMissing,
                 .nativeHostPermissionDenied, .nativeHostUnsupportedKind:
                return .failed
            default:
                return .notAttempted
            }
        case .portReceive, .portRelay:
            switch diagnostic.outcome {
            case .portConnected:
                return .completed
            case .companionAppProtocolUnknown, .relayCancelled:
                return .failed
            default:
                return .pending
            }
        }
    }

    static func autofillPathStatus(
        extensionId: String,
        evaluation: SumiCompanionAppResolverResult?
    ) -> SumiNativeMessagingAutofillPathStatus {
        guard evaluation?.detail != nil else { return .notApplicable }
        if SafariExtensionContentScriptProbe.isTabReconcilePathWiredInSources() {
            return .contentScriptsWired
        }
        return .pendingManualVerification
    }

    static func enrich(
        _ diagnostic: SafariExtensionNativeMessagingDiagnostic,
        adapter: SumiNativeMessagingProtocolAdapter? = nil,
        adapterIdentifier: String? = nil,
        evaluation: SumiCompanionAppResolverResult? = nil,
        policyDenial: SumiNativeMessagingRelayPolicyDenial? = nil,
        sessionState: SumiNativeMessagingSessionState? = nil
    ) -> SafariExtensionNativeMessagingDiagnostic {
        let adapterSelected = adapter != nil || diagnostic.adapterSelected == true
        let resolvedAdapterIdentifier = adapterIdentifier ?? diagnostic.adapterIdentifier
        let appResolved = diagnostic.appResolved
            ?? (diagnostic.hostBundleIdentifier != nil || evaluation?.detail != nil)
        let appLaunched = diagnostic.appLaunched ?? diagnostic.launchAttempted

        return SafariExtensionNativeMessagingDiagnostic(
            extensionId: diagnostic.extensionId,
            direction: diagnostic.direction,
            requestedApplicationIdentifier: diagnostic.requestedApplicationIdentifier,
            hostBundleIdentifier: diagnostic.hostBundleIdentifier,
            resolverBucket: diagnostic.resolverBucket,
            outcome: diagnostic.outcome,
            errorDomain: diagnostic.errorDomain,
            errorCode: diagnostic.errorCode,
            launchAttempted: diagnostic.launchAttempted,
            launchSuppressed: diagnostic.launchSuppressed,
            retryCountBucket: diagnostic.retryCountBucket,
            launchReason: diagnostic.launchReason,
            launchRequestedByAdapter: diagnostic.launchRequestedByAdapter,
            launchCooldownBucket: diagnostic.launchCooldownBucket,
            extensionContextActive: diagnostic.extensionContextActive,
            isContainingApp: diagnostic.isContainingApp,
            protocolAdapterAvailable: diagnostic.protocolAdapterAvailable
                ?? (adapter != nil),
            launchAllowed: diagnostic.launchAllowed,
            sessionState: sessionState ?? diagnostic.sessionState,
            adapterSelected: adapterSelected,
            adapterIdentifier: resolvedAdapterIdentifier,
            appResolved: appResolved,
            appLaunched: appLaunched,
            protocolStatus: diagnostic.protocolStatus
                ?? protocolStatus(
                    adapter: adapter,
                    evaluation: evaluation,
                    diagnostic: diagnostic
                ),
            handshakeStatus: diagnostic.handshakeStatus
                ?? handshakeStatus(for: diagnostic),
            autofillPathStatus: diagnostic.autofillPathStatus
                ?? autofillPathStatus(extensionId: diagnostic.extensionId, evaluation: evaluation),
            failureBucket: diagnostic.failureBucket
                ?? failureBucket(for: diagnostic, policyDenial: policyDenial)
        )
    }
}
