//
//  SumiNativeMessagingErrorMapper.swift
//  Sumi
//
//  Stable WebExtension-compatible native messaging errors.
//

import Foundation
import WebKit

enum SumiNativeMessagingErrorMapper {
    static let relayErrorDomain = "Sumi.SafariNativeMessaging"

    static func relayError(
        code: SumiNativeMessagingRelay.ErrorCode,
        description: String? = nil,
        diagnostic: SafariExtensionNativeMessagingDiagnostic?
    ) -> NSError {
        let message: String
        switch code {
        case .hostNotFound:
            message = description
                ?? "The native messaging host application could not be resolved."
        case .hostLaunchFailed:
            message = description
                ?? "The native messaging host application could not be launched."
        case .companionAppProtocolUnknown:
            message = description
                ?? "Companion host application messaging protocol is not implemented in Sumi."
        case .extensionContextMissing:
            message = description
                ?? "The extension context for native messaging could not be resolved."
        case .policyDenied:
            message = description
                ?? "Native messaging is not permitted for this extension session."
        case .relayTimeout:
            message = description
                ?? "Native messaging relay timed out."
        case .relayCancelled:
            message = description
                ?? "Native messaging relay was cancelled."
        }

        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let diagnostic {
            userInfo["SumiNativeMessagingDiagnostic"] = diagnostic.outcome.rawValue
            if let hostBundleIdentifier = diagnostic.hostBundleIdentifier {
                userInfo["SumiNativeMessagingHostBundleIdentifier"] = hostBundleIdentifier
            }
            if let resolverBucket = diagnostic.resolverBucket {
                userInfo["SumiNativeMessagingResolverBucket"] = resolverBucket.rawValue
            }
        }
        return NSError(domain: relayErrorDomain, code: code.rawValue, userInfo: userInfo)
    }

    static func messagePortDisconnectError(
        code: SumiNativeMessagingRelay.ErrorCode,
        diagnostic: SafariExtensionNativeMessagingDiagnostic?
    ) -> NSError {
        relayError(code: code, diagnostic: diagnostic)
    }

    static func messagePortNotConnectedError(
        diagnostic: SafariExtensionNativeMessagingDiagnostic?
    ) -> NSError {
        let relayError = relayError(
            code: .companionAppProtocolUnknown,
            diagnostic: diagnostic
        )
        return NSError(
            domain: WKWebExtension.MessagePort.errorDomain,
            code: WKWebExtension.MessagePort.Error.notConnected.rawValue,
            userInfo: relayError.userInfo
        )
    }
}
