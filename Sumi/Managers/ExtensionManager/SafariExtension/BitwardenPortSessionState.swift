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

@available(macOS 15.5, *)
@MainActor
final class BitwardenPortSessionState {
    private weak var session: SumiNativeMessagingPortSession?
    private let transport: any BitwardenDesktopProxyTransporting
    let appId: String
    private let replyTimeout: Duration
    private let delayedActions: MainActorDelayedActionScheduler
    private var pendingReplies: [Int: MainActorDelayedActionScheduler.Cancellation] = [:]
    private var transportReady = false
    private var queuedExtensionMessages: [[String: Any]] = []

    init(
        session: SumiNativeMessagingPortSession,
        transport: any BitwardenDesktopProxyTransporting,
        appId: String,
        replyTimeout: Duration,
        delayedActions: MainActorDelayedActionScheduler
    ) {
        self.session = session
        self.transport = transport
        self.appId = appId
        self.replyTimeout = replyTimeout
        self.delayedActions = delayedActions
        transport.onReceive = { [weak self] incoming in
            self?.handleDesktopMessage(incoming)
        }
    }

    func markTransportReady() {
        guard transportReady == false else { return }
        transportReady = true
        flushQueuedExtensionMessages()
    }

    private func flushQueuedExtensionMessages() {
        let queued = queuedExtensionMessages
        queuedExtensionMessages.removeAll()
        for payload in queued {
            relayExtensionMessage(payload)
        }
    }

    func disconnectAssociatedSession(throwing error: NSError? = nil) {
        shutdown()
        session?.disconnect(throwing: error)
    }

    func shutdown() {
        pendingReplies.values.forEach { $0() }
        pendingReplies.removeAll()
        transport.shutdown()
    }

    func relayExtensionMessage(_ payload: [String: Any]) {
        let command = payload["command"] as? String ?? ""
        switch BitwardenPortCommand.relayOutcome(for: command) {
        case .localSafari:
            if BitwardenSafariOneShotHandler.isBiometricPromptCommand(command) {
                if let messageId = payload["messageId"] as? Int {
                    pendingReplies.removeValue(forKey: messageId)?()
                }
                BitwardenSafariOneShotHandler.handleBiometricPrompt(payload: payload) { [weak self] reply in
                    self?.session?.sendReplyToExtension(reply)
                }
                return
            }
            if let reply = BitwardenSafariOneShotHandler.portReply(for: payload) {
                if let messageId = payload["messageId"] as? Int {
                    pendingReplies.removeValue(forKey: messageId)?()
                }
                session?.sendReplyToExtension(reply)
            }
            return
        case .unsupportedCommand, .commandNotYetImplemented, .blockedPublicProtocolGap:
            BitwardenDesktopTransportDiagnostics.log(
                outcome: BitwardenPortCommand.transportOutcome(for: command),
                command: command
            )
            replyPortUnavailable(payload: payload, command: command)
            return
        case .relay:
            break
        }

        guard transportReady else {
            queuedExtensionMessages.append(payload)
            return
        }

        let wrapped: [String: Any] = [
            "appId": appId,
            "message": payload,
        ]
        do {
            try transport.send(wrapped)
            if let messageId = payload["messageId"] as? Int {
                scheduleReplyTimeout(for: messageId, command: command)
            }
        } catch let error as BitwardenDesktopProxyTransportError {
            session?.disconnect()
            _ = BitwardenDesktopProxyTransportErrorMapper.relayError(for: error)
        } catch {
            session?.disconnect()
        }
    }

    private func handleDesktopMessage(_ incoming: [String: Any]) {
        if let command = incoming["command"] as? String, command == "disconnected" {
            BitwardenDesktopTransportDiagnostics.log(outcome: .browserIntegrationDisabled, command: command)
            pendingReplies.values.forEach { $0() }
            pendingReplies.removeAll()
            session?.disconnect()
            return
        }

        let replyPayload: Any?
        if let nested = incoming["message"] {
            replyPayload = nested
        } else {
            replyPayload = incoming
        }

        guard let replyObject = replyPayload as? [String: Any] else {
            BitwardenDesktopTransportDiagnostics.log(outcome: .desktopReplyMalformed)
            return
        }

        if let command = replyObject["command"] as? String {
            switch command {
            case BitwardenPortCommand.getBiometricsStatus:
                classifyBiometricsStatusReply(replyObject, command: command)
            case BitwardenPortCommand.setupEncryption:
                if replyObject["response"] != nil {
                    BitwardenDesktopTransportDiagnostics.log(outcome: .realDesktopStatusSucceeded, command: command)
                } else {
                    BitwardenDesktopTransportDiagnostics.log(outcome: .desktopReplyMalformed, command: command)
                }
            default:
                break
            }
        }

        if let messageId = replyObject["messageId"] as? Int {
            pendingReplies.removeValue(forKey: messageId)?()
        }

        session?.sendReplyToExtension(replyObject)
    }

    private func classifyBiometricsStatusReply(_ replyObject: [String: Any], command: String) {
        guard let response = replyObject["response"] else {
            BitwardenDesktopTransportDiagnostics.log(outcome: .desktopReplyMalformed, command: command)
            return
        }

        let statusCode: Int? = {
            if let value = response as? Int { return value }
            if let value = response as? NSNumber { return value.intValue }
            return nil
        }()

        guard let statusCode else {
            BitwardenDesktopTransportDiagnostics.log(outcome: .desktopReplyMalformed, command: command)
            return
        }

        switch statusCode {
        case BitwardenPublicBiometricsStatus.available.rawValue:
            BitwardenDesktopTransportDiagnostics.log(outcome: .realDesktopStatusSucceeded, command: command)
        case BitwardenPublicBiometricsStatus.unlockNeeded.rawValue:
            BitwardenDesktopTransportDiagnostics.log(outcome: .setupEncryptionRequired, command: command)
        case BitwardenPublicBiometricsStatus.desktopDisconnected.rawValue:
            BitwardenDesktopTransportDiagnostics.log(outcome: .browserIntegrationDisabled, command: command)
        case BitwardenPublicBiometricsStatus.notEnabledInConnectedDesktopApp.rawValue:
            BitwardenDesktopTransportDiagnostics.log(outcome: .browserIntegrationDisabled, command: command)
        default:
            BitwardenDesktopTransportDiagnostics.log(outcome: .realDesktopStatusSucceeded, command: command)
        }
    }

    private func replyPortUnavailable(payload: [String: Any], command: String) {
        guard let messageId = payload["messageId"] as? Int else { return }
        pendingReplies.removeValue(forKey: messageId)?()
        let outcome = BitwardenPortCommand.transportOutcome(for: command)
        let response: Any = {
            switch command {
            case BitwardenPortCommand.getBiometricsStatus, BitwardenPortCommand.getBiometricsStatusForUser:
                return BitwardenBiometricsStatus.desktopDisconnected.rawValue
            default:
                return false
            }
        }()
        session?.sendReplyToExtension(
            BitwardenSafariOneShotHandler.portMessage(
                command: command,
                response: response,
                messageId: messageId,
                timestamp: BitwardenSafariOneShotHandler.currentTimestampMillis
            )
        )
        _ = outcome
    }

    private func scheduleReplyTimeout(for messageId: Int, command: String?) {
        pendingReplies[messageId]?()
        pendingReplies[messageId] = delayedActions.schedule(after: replyTimeout) { [weak self] in
            guard let self, self.pendingReplies[messageId] != nil else { return }
            self.pendingReplies.removeValue(forKey: messageId)
            BitwardenDesktopTransportDiagnostics.log(
                outcome: .desktopTimeout,
                command: command
            )
            self.session?.disconnect()
        }
    }
}
/// Public port command names from bitwarden/clients native messaging IPC.
private enum BitwardenPortCommand {
    static let getBiometricsStatus = "getBiometricsStatus"
    static let getBiometricsStatusForUser = "getBiometricsStatusForUser"
    static let authenticateWithBiometrics = "authenticateWithBiometrics"
    static let unlockWithBiometricsForUser = "unlockWithBiometricsForUser"
    static let canEnableBiometricUnlock = "canEnableBiometricUnlock"
    static let setupEncryption = "setupEncryption"
    static let biometricUnlock = "biometricUnlock"

    enum RelayOutcome {
        case relay
        /// Safari posts biometrics IPC unencrypted to the native handler (public SafariWebExtensionHandler).
        case localSafari
        case unsupportedCommand
        case commandNotYetImplemented
        case blockedPublicProtocolGap
    }

    static func relayOutcome(for command: String) -> RelayOutcome {
        switch command {
        case getBiometricsStatus,
             getBiometricsStatusForUser,
             authenticateWithBiometrics,
             unlockWithBiometricsForUser,
             canEnableBiometricUnlock,
             biometricUnlock:
            return .localSafari
        case setupEncryption:
            return .relay
        case "":
            return .unsupportedCommand
        default:
            return .unsupportedCommand
        }
    }

    static func transportOutcome(for command: String) -> BitwardenDesktopTransportOutcome {
        switch relayOutcome(for: command) {
        case .relay, .localSafari:
            return .unsupportedCommand
        case .unsupportedCommand:
            return .unsupportedCommand
        case .commandNotYetImplemented:
            return .commandNotYetImplemented
        case .blockedPublicProtocolGap:
            return .blockedPublicProtocolGap
        }
    }
}

/// Public `BiometricsStatus` ordinals from bitwarden/clients key-management.
private enum BitwardenPublicBiometricsStatus: Int {
    case available = 0
    case unlockNeeded = 1
    case desktopDisconnected = 6
    case notEnabledInConnectedDesktopApp = 8
}
