//
//  SumiNativeMessagingSessionState.swift
//  Sumi
//
//  Per-session native messaging failure states for bounded repeat-error handling.
//

import Foundation

enum SumiNativeMessagingSessionState: String, Codable, Sendable, Equatable {
    case unknownProtocolInitial
    case unknownProtocolSuppressed
    case unknownProtocolCooldown
    case protocolAdapterUnavailable
    case moduleOff
    case extensionDisabled
    case profileRuntimeUnloaded
}

enum SumiNativeMessagingSessionStateMachine {
    static func resolve(
        policyDenial: SumiNativeMessagingRelayPolicyDenial?,
        profileRuntimeLoaded: Bool,
        evaluation: SumiCompanionAppResolverResult?,
        loopEvaluation: SumiNativeMessagingRelayLoopGuard.Evaluation?,
        adapterAvailable: Bool
    ) -> SumiNativeMessagingSessionState? {
        guard profileRuntimeLoaded else {
            return .profileRuntimeUnloaded
        }

        if let policyDenial {
            switch policyDenial {
            case .moduleDisabled:
                return .moduleOff
            case .extensionNotEnabled:
                return .extensionDisabled
            default:
                return nil
            }
        }

        if let loopEvaluation, loopEvaluation.launchSuppressed {
            return .unknownProtocolSuppressed
        }

        if adapterAvailable == false {
            if case .protocolAdapterUnavailable = evaluation {
                return .protocolAdapterUnavailable
            }
            if case .appFoundButProtocolUnknown = evaluation {
                return .protocolAdapterUnavailable
            }
            if case .launchSuppressed = evaluation {
                return .protocolAdapterUnavailable
            }
        }

        guard let loopEvaluation else {
            return .unknownProtocolInitial
        }

        if loopEvaluation.isWithinCooldown == false,
           loopEvaluation.retryCountBucket != .none
        {
            return .unknownProtocolCooldown
        }

        return .unknownProtocolInitial
    }
}
