//
//  SumiNativeMessagingAdapterTransport.swift
//  Sumi
//
//  Transport contract and capability model for public companion-app protocol adapters.
//  Generic runtime owns timeout, cancellation, disconnect, and error mapping; adapters
//  implement protocol-specific relay only.
//

import Foundation

/// Adapter-facing capability outcomes surfaced to diagnostics and relay policy.
enum SumiNativeMessagingAdapterCapability: String, Codable, Sendable, Equatable {
    case adapterAvailable
    case adapterUnavailable
    case appNotInstalled
    case desktopIntegrationDisabled
    case protocolVersionUnsupported
    case userActionRequired
    case timeout
    case portDisconnected
}

@MainActor
enum SumiNativeMessagingAdapterTransport {
    static let defaultOneShotTimeout: Duration = SumiNativeMessagingConnection.defaultReplyTimeout

    static func relayErrorCode(for capability: SumiNativeMessagingAdapterCapability)
        -> SumiNativeMessagingRelay.ErrorCode
    {
        switch capability {
        case .adapterAvailable:
            return .companionAppProtocolUnknown
        case .adapterUnavailable, .desktopIntegrationDisabled, .protocolVersionUnsupported,
             .userActionRequired:
            return .companionAppProtocolUnknown
        case .appNotInstalled:
            return .hostNotFound
        case .timeout:
            return .relayTimeout
        case .portDisconnected:
            return .relayCancelled
        }
    }

    static func capability(
        for evaluation: SumiCompanionAppResolverResult?,
        adapterAvailable: Bool,
        relayErrorCode: SumiNativeMessagingRelay.ErrorCode? = nil
    ) -> SumiNativeMessagingAdapterCapability {
        if let relayErrorCode {
            switch relayErrorCode {
            case .relayTimeout:
                return .timeout
            case .relayCancelled:
                return .portDisconnected
            case .hostNotFound:
                return .appNotInstalled
            case .policyDenied:
                return .desktopIntegrationDisabled
            default:
                break
            }
        }

        guard let evaluation else {
            return adapterAvailable ? .adapterAvailable : .adapterUnavailable
        }

        switch evaluation {
        case .appNotFound:
            return .appNotInstalled
        case .protocolAdapterUnavailable, .appFoundButProtocolUnknown:
            return .adapterUnavailable
        case .launchSuppressed, .launchRateLimited:
            return .desktopIntegrationDisabled
        case .containingAppResolved, .companionAppResolved:
            return adapterAvailable ? .adapterAvailable : .adapterUnavailable
        case .notRequested, .applicationIdentifierMissing:
            return .adapterUnavailable
        }
    }

    static func mapRelayError(_ error: NSError) -> SumiNativeMessagingAdapterCapability {
        guard error.domain == SumiNativeMessagingRelay.errorDomain,
              let code = SumiNativeMessagingRelay.ErrorCode(rawValue: error.code)
        else {
            return .adapterUnavailable
        }
        return capability(for: nil, adapterAvailable: false, relayErrorCode: code)
    }
}
