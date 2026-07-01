//
//  SumiWebExtensionCallbackErrorMapper.swift
//  Sumi
//
//  Maps host-side NSError values into shapes WebKit can serialize for extension
//  callback/runtime.lastError consumers (non-null error.message in JS).
//

import Foundation

enum SumiWebExtensionCallbackErrorMapper {
    static let webExtensionContextErrorDomain = "WKWebExtensionContextErrorDomain"
    static let webExtensionMessagePortErrorDomain = "WKWebExtensionMessagePortErrorDomain"
    static let webExtensionErrorDomain = "WKWebExtensionErrorDomain"

    static let underlyingDomainUserInfoKey = "SumiWebExtensionUnderlyingDomain"
    static let underlyingCodeUserInfoKey = "SumiWebExtensionUnderlyingCode"

    static func webExtensionCallbackError(from error: any Error) -> NSError {
        let nsError = error as NSError
        if isWebKitRecognizedCallbackError(nsError),
           hasSerializableMessage(nsError) {
            return nsError
        }

        let message = resolvedMessage(from: nsError)
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
        userInfo[underlyingDomainUserInfoKey] = nsError.domain
        userInfo[underlyingCodeUserInfoKey] = nsError.code

        return NSError(
            domain: webExtensionContextErrorDomain,
            code: 1,
            userInfo: userInfo
        )
    }

    static func resolvedMessage(from error: NSError) -> String {
        if hasSerializableMessage(error) {
            return error.localizedDescription
        }

        if error.domain == SumiNativeMessagingErrorMapper.relayErrorDomain,
           let code = SumiNativeMessagingRelay.ErrorCode(rawValue: error.code) {
            return SumiNativeMessagingErrorMapper.relayError(
                code: code,
                diagnostic: nil
            ).localizedDescription
        }

        if error.domain == webExtensionMessagePortErrorDomain {
            switch error.code {
            case 1:
                return "The extension message port encountered an unknown error."
            case 2:
                return "The extension message port is not connected."
            case 3:
                return "The extension message port received an invalid message."
            default:
                return "The extension message port encountered an error."
            }
        }

        if error.domain == webExtensionContextErrorDomain {
            switch error.code {
            case 1:
                return "An unknown extension context error occurred."
            case 2:
                return "The extension context is already loaded."
            case 3:
                return "The extension context is not loaded."
            case 4:
                return "Another extension context is already using the base URL."
            case 5:
                return "The extension does not have background content."
            case 6:
                return "The extension background content failed to load."
            default:
                return "An extension context error occurred."
            }
        }

        return "The extension operation failed."
    }

    static func hasSerializableMessage(_ error: NSError) -> Bool {
        let message = error.localizedDescription
        return message.isEmpty == false && message != "(null)"
    }

    static func isWebKitRecognizedCallbackError(_ error: NSError) -> Bool {
        error.domain == webExtensionContextErrorDomain
            || error.domain == webExtensionMessagePortErrorDomain
            || error.domain == webExtensionErrorDomain
    }
}
