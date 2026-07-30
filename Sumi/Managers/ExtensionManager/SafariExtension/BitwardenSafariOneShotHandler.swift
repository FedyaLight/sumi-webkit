//
//  BitwardenNativeMessagingAdapter.swift
//  Sumi
//
//  Bitwarden Safari extension native messaging via desktop_proxy (port) and
//  public SafariWebExtensionHandler one-shot commands.
//

import AppKit
import Foundation
import LocalAuthentication
import OSLog

@MainActor
enum BitwardenSafariOneShotHandler {
    struct DownloadFileRequest {
        let fileName: String
        let data: Data
    }

    enum DownloadFileDecodeError: LocalizedError {
        case missingDataString
        case malformedJSON(String)
        case invalidPayloadObject
        case missingFileName
        case missingBlobData
        case invalidBase64Blob

        var errorDescription: String? {
            switch self {
            case .missingDataString:
                return "downloadFile payload is missing its JSON data string."
            case .malformedJSON(let reason):
                return "downloadFile payload JSON is malformed: \(reason)"
            case .invalidPayloadObject:
                return "downloadFile payload JSON is not an object."
            case .missingFileName:
                return "downloadFile payload is missing fileName."
            case .missingBlobData:
                return "downloadFile payload is missing blobData."
            case .invalidBase64Blob:
                return "downloadFile payload blobData is not valid base64."
            }
        }
    }

    private static let log = Logger.sumi(category: "Extensions")

    /// Public `sleep` command delay from SafariWebExtensionHandler.
    static var sleepDelay: Duration = .seconds(10)

    /// Keychain service name Bitwarden uses for the browser biometric user key
    /// (`SafariWebExtensionHandler.ServiceNameBiometric`).
    static let biometricKeychainService = "Bitwarden_biometric"

    /// Injectable biometric prompt + keychain access. Defaults to the system
    /// implementations; tests substitute fakes.
    static var biometricAuthenticator: BitwardenBiometricAuthenticating =
        SystemBitwardenBiometricAuthenticator()
    static var biometricKeychain: BitwardenBiometricKeychainReading =
        SystemBitwardenBiometricKeychain()

    static func handleAsync(
        message: Any,
        replyHandler: @escaping (Any?) -> Void
    ) -> Bool {
        guard let payload = message as? [String: Any],
              let command = payload["command"] as? String,
              command == "sleep"
        else {
            return false
        }
        Task { @MainActor in
            try? await Task.sleep(for: sleepDelay)
            replyHandler(NSNull())
        }
        return true
    }

    static func handle(message: Any) -> Any? {
        guard let payload = message as? [String: Any],
              let command = payload["command"] as? String
        else {
            return nil
        }

        let messageId = payload["messageId"]
        let timestamp = currentTimestampMillis

        switch command {
        case "readFromClipboard":
            return NSPasteboard.general.string(forType: .string) as Any
        case "copyToClipboard":
            guard let data = payload["data"] as? String else { return nil }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(data, forType: .string)
            return NSNull()
        case "showPopover":
            return NSNull()
        case "downloadFile":
            guard handleDownloadFile(payload: payload) else { return nil }
            return NSNull()
        case "biometricUnlockAvailable":
            let available = biometricAuthenticator.isBiometricsAvailable()
            return safariMessageEnvelope(
                command: command,
                response: available ? "available" : "not available",
                messageId: messageId,
                timestamp: timestamp
            )
        case "getBiometricsStatus":
            return safariMessageEnvelope(
                command: command,
                response: BitwardenBiometricsStatus.available.rawValue,
                messageId: messageId,
                timestamp: timestamp
            )
        case "getBiometricsStatusForUser":
            return safariMessageEnvelope(
                command: command,
                response: getBiometricsStatusForUser(payload: payload).rawValue,
                messageId: messageId,
                timestamp: timestamp
            )
        case "canEnableBiometricUnlock":
            let available = biometricAuthenticator.isBiometricsAvailable()
            return safariMessageEnvelope(
                command: command,
                response: available,
                messageId: messageId,
                timestamp: timestamp
            )
        default:
            return nil
        }
    }

    static func portReply(for payload: [String: Any]) -> [String: Any]? {
        guard let command = payload["command"] as? String else { return nil }
        let messageId = payload["messageId"]
        let timestamp = currentTimestampMillis
        guard let response = biometricsResponse(for: command, payload: payload) else { return nil }
        return portMessage(
            command: command,
            response: response,
            messageId: messageId,
            timestamp: timestamp
        )
    }

    static func portMessage(
        command: String,
        response: Any,
        messageId: Any?,
        timestamp: Int64
    ) -> [String: Any] {
        var message: [String: Any] = [
            "command": command,
            "response": response,
            "timestamp": timestamp,
        ]
        if let messageId {
            message["messageId"] = messageId
        }
        return message
    }

    static var currentTimestampMillis: Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func safariMessageEnvelope(
        command: String,
        response: Any,
        messageId: Any?,
        timestamp: Int64
    ) -> [String: Any] {
        ["message": portMessage(command: command, response: response, messageId: messageId, timestamp: timestamp)]
    }

    private static func biometricsResponse(for command: String, payload: [String: Any]) -> Any? {
        switch command {
        case "getBiometricsStatus":
            return BitwardenBiometricsStatus.available.rawValue
        case "getBiometricsStatusForUser":
            return getBiometricsStatusForUser(payload: payload).rawValue
        case "canEnableBiometricUnlock":
            return biometricAuthenticator.isBiometricsAvailable()
        default:
            // Biometric prompt commands (authenticateWithBiometrics,
            // unlockWithBiometricsForUser, biometricUnlock) are handled
            // asynchronously via `handleBiometricPrompt`, not here.
            return nil
        }
    }

    /// Mirrors `SafariWebExtensionHandler.getBiometricsStatusForUser`: without
    /// biometrics hardware it is unavailable; with a stored key the user is
    /// unlockable; otherwise the key still needs to be provisioned.
    static func getBiometricsStatusForUser(
        payload: [String: Any]
    ) -> BitwardenBiometricsStatus {
        guard biometricAuthenticator.isBiometricsAvailable() else {
            return .hardwareUnavailable
        }
        guard let userId = payload["userId"] as? String,
              biometricKeychain.userKey(userId: userId) != nil
        else {
            return .notEnabledInConnectedDesktopApp
        }
        return .available
    }

    static func isBiometricPromptCommand(_ command: String) -> Bool {
        switch command {
        case "authenticateWithBiometrics",
             "unlockWithBiometricsForUser",
             "biometricUnlock":
            return true
        default:
            return false
        }
    }

    /// Performs the local biometric prompt and, on success, returns the stored
    /// user key — mirroring `SafariWebExtensionHandler`'s biometric commands.
    /// Produces the bare port-message dictionary; one-shot callers wrap it in
    /// `["message": …]`.
    static func handleBiometricPrompt(
        payload: [String: Any],
        completion: @escaping ([String: Any]) -> Void
    ) {
        let command = payload["command"] as? String ?? ""
        let messageId = payload["messageId"]
        let reply: (Any, String?) -> Void = { response, userKeyB64 in
            var message = portMessage(
                command: command,
                response: response,
                messageId: messageId,
                timestamp: currentTimestampMillis
            )
            if let userKeyB64 {
                message["userKeyB64"] = userKeyB64
            }
            completion(message)
        }

        switch command {
        case "authenticateWithBiometrics":
            Task { @MainActor in
                let success = await biometricAuthenticator.evaluate(
                    reason: "authenticate",
                    flags: [.privateKeyUsage, .userPresence]
                )
                reply(success, nil)
            }
        case "unlockWithBiometricsForUser":
            guard biometricAuthenticator.canEvaluateIgnoringLockout() else {
                reply(false, nil)
                return
            }
            Task { @MainActor in
                let success = await biometricAuthenticator.evaluate(
                    reason: "unlock your vault",
                    flags: [.privateKeyUsage, .biometryAny]
                )
                guard success, let userId = payload["userId"] as? String else {
                    reply(success, nil)
                    return
                }
                reply(true, biometricKeychain.userKey(userId: userId))
            }
        case "biometricUnlock":
            guard biometricAuthenticator.isBiometricsAvailable() else {
                reply("not supported", nil)
                return
            }
            Task { @MainActor in
                let success = await biometricAuthenticator.evaluate(
                    reason: "Biometric Unlock",
                    flags: [.privateKeyUsage, .userPresence]
                )
                guard success, let userId = payload["userId"] as? String else {
                    reply("not enabled", nil)
                    return
                }
                if let userKey = biometricKeychain.userKey(userId: userId) {
                    reply("unlocked", userKey)
                } else {
                    reply("not enabled", nil)
                }
            }
        default:
            reply(false, nil)
        }
    }

    private static func handleDownloadFile(payload: [String: Any]) -> Bool {
        let request: DownloadFileRequest
        do {
            request = try downloadFileRequest(payload: payload)
        } catch {
            log.error("Bitwarden downloadFile payload decode failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = request.fileName
        guard panel.runModal() == .OK, let url = panel.url else { return true }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) == false {
            fileManager.createFile(atPath: url.path, contents: Data(), attributes: nil)
        }
        do {
            try request.data.write(to: url)
        } catch {
            log.error("Bitwarden downloadFile write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return true
    }

    static func downloadFileRequest(payload: [String: Any]) throws -> DownloadFileRequest {
        guard let jsonData = payload["data"] as? String else {
            throw DownloadFileDecodeError.missingDataString
        }

        let json = Data(jsonData.utf8)
        let rawObject: Any
        do {
            rawObject = try JSONSerialization.jsonObject(with: json)
        } catch {
            throw DownloadFileDecodeError.malformedJSON(error.localizedDescription)
        }

        guard let object = rawObject as? [String: Any] else {
            throw DownloadFileDecodeError.invalidPayloadObject
        }
        guard let fileName = object["fileName"] as? String else {
            throw DownloadFileDecodeError.missingFileName
        }
        guard let blob = object["blobData"] as? String else {
            throw DownloadFileDecodeError.missingBlobData
        }

        if let blobOptions = object["blobOptions"] as? [String: Any],
           blobOptions["type"] as? String == "text/plain" {
            return DownloadFileRequest(fileName: fileName, data: Data(blob.utf8))
        }

        guard let data = Data(base64Encoded: blob) else {
            throw DownloadFileDecodeError.invalidBase64Blob
        }
        return DownloadFileRequest(fileName: fileName, data: data)
    }

    static func publicCommandName(in message: Any) -> String? {
        guard let payload = message as? [String: Any] else { return nil }
        return payload["command"] as? String
    }

    static func relayOutcome(for command: String?) -> BitwardenDesktopTransportOutcome {
        guard let command, command.isEmpty == false else {
            return .unsupportedCommand
        }
        return .unsupportedCommand
    }

    static func relayError(for outcome: BitwardenDesktopTransportOutcome) -> NSError {
        let description: String
        let code: SumiNativeMessagingRelay.ErrorCode
        switch outcome {
        case .unsupportedCommand:
            description = "Unsupported Bitwarden native messaging command."
            code = .companionAppProtocolUnknown
        case .commandNotYetImplemented:
            description = "Bitwarden native messaging command is not yet implemented."
            code = .companionAppProtocolUnknown
        case .setupEncryptionRequired:
            description = "Bitwarden vault unlock is required before this command can run."
            code = .hostLaunchFailed
        default:
            description = "Unsupported Bitwarden native messaging command."
            code = .companionAppProtocolUnknown
        }
        var error = SumiNativeMessagingRelay.makeError(code: code, description: description, diagnostic: nil)
        var userInfo = error.userInfo
        userInfo[BitwardenDesktopProxyTransportErrorMapper.failureBucketUserInfoKey] = outcome.rawValue
        error = NSError(domain: error.domain, code: error.code, userInfo: userInfo)
        return error
    }
}

/// Ordinals from bitwarden/clients `BiometricsStatus` used by the Safari
/// extension handler.
enum BitwardenBiometricsStatus: Int {
    case available = 0
    case unlockNeeded = 1
    case hardwareUnavailable = 2
    case desktopDisconnected = 6
    case notEnabledInConnectedDesktopApp = 8
}
