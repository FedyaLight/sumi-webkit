//
//  SumiNativeMessagingErrorMapper.swift
//  Sumi
//
//  Stable WebExtension-compatible native messaging errors.
//

import Foundation

enum SumiNativeMessagingErrorMapper {
    static let relayErrorDomain = "Sumi.SafariNativeMessaging"

    static func relayError(
        from source: NSError,
        diagnostic: SafariExtensionNativeMessagingDiagnostic?
    ) -> NSError {
        let code: SumiNativeMessagingRelay.ErrorCode
        if source.domain == relayErrorDomain,
           let mapped = SumiNativeMessagingRelay.ErrorCode(rawValue: source.code)
        {
            code = mapped
        } else {
            code = .hostLaunchFailed
        }

        let description = source.localizedDescription.isEmpty ? nil : source.localizedDescription
        return relayError(code: code, description: description, diagnostic: diagnostic)
    }

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
        case .nativeHostManifestMissing:
            message = description
                ?? "The native messaging host manifest was not found."
        case .nativeHostExecutableMissing:
            message = description
                ?? "The native messaging host executable was not found."
        case .nativeHostPermissionDenied:
            message = description
                ?? "Permission denied when starting the native messaging host."
        case .nativeHostUnsupportedKind:
            message = description
                ?? "The native messaging host kind is unsupported."
        case .companionApplicationUnsupportedApplicationId:
            message = description
                ?? "Safari containing-application messaging only supports application.id."
        case .companionApplicationUnsupportedExtension:
            message = description
                ?? "Safari containing-application messaging is not supported for this extension."
        case .companionApplicationUnsupportedBackend:
            message = description
                ?? "No Sumi companion application backend is registered for this extension."
        case .companionApplicationInvalidPayload:
            message = description
                ?? "The companion application message payload is invalid."
        case .companionApplicationUnsupportedMessageType:
            message = description
                ?? "The companion application message type is unsupported."
        case .companionApplicationSecureStoreFailure:
            message = description
                ?? "The companion application secure store operation failed."
        case .companionApplicationExactlyOnceReplyViolation:
            message = description
                ?? "The companion application backend attempted to reply more than once."
        case .companionApplicationSecureStateMissing:
            message = description
                ?? "The companion application secure state is missing."
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
        webExtensionCallbackError(
            from: relayError(code: code, diagnostic: diagnostic)
        )
    }

    static func messagePortNotConnectedError(
        diagnostic: SafariExtensionNativeMessagingDiagnostic?
    ) -> NSError {
        let relayError = relayError(
            code: .companionAppProtocolUnknown,
            diagnostic: diagnostic
        )
        return NSError(
            domain: SumiWebExtensionCallbackErrorMapper.webExtensionMessagePortErrorDomain,
            code: 2,
            userInfo: relayError.userInfo.merging(
                [NSLocalizedDescriptionKey: relayError.localizedDescription],
                uniquingKeysWith: { _, new in new }
            )
        )
    }

    static func webExtensionCallbackError(from error: any Error) -> NSError {
        SumiWebExtensionCallbackErrorMapper.webExtensionCallbackError(from: error)
    }

    static func webExtensionCallbackError(
        code: SumiNativeMessagingRelay.ErrorCode,
        description: String? = nil,
        diagnostic: SafariExtensionNativeMessagingDiagnostic?
    ) -> NSError {
        webExtensionCallbackError(
            from: relayError(
                code: code,
                description: description,
                diagnostic: diagnostic
            )
        )
    }
}
