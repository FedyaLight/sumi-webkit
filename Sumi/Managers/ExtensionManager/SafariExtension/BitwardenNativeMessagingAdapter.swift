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

@available(macOS 15.5, *)
@MainActor
final class BitwardenNativeMessagingAdapter: SumiNativeMessagingProtocolAdapter {
    static let supportedHostBundleIdentifier = BitwardenNativeMessagingIdentifiers.hostBundleIdentifier

    let protocolIdentifier = BitwardenNativeMessagingIdentifiers.protocolIdentifier

    private let transportFactory: () -> any BitwardenDesktopProxyTransporting
    private let handshakeTimeout: Duration
    private let replyTimeout: Duration
    private var portSessions: [ObjectIdentifier: BitwardenPortSessionState] = [:]

    init(
        transportFactory: @escaping () -> any BitwardenDesktopProxyTransporting = {
            BitwardenDesktopProxyProcessTransport()
        },
        handshakeTimeout: Duration = .seconds(30),
        replyTimeout: Duration = SumiNativeMessagingConnection.defaultReplyTimeout
    ) {
        self.transportFactory = transportFactory
        self.handshakeTimeout = handshakeTimeout
        self.replyTimeout = replyTimeout
    }

    func supports(hostBundleIdentifier: String) -> Bool {
        hostBundleIdentifier == Self.supportedHostBundleIdentifier
    }

    func relayOneShotMessage(
        request: SumiNativeMessagingOneShotRequest,
        launcher: SumiHostApplicationLaunching,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        _ = request.message
        Task { @MainActor in
            do {
                try await launcher.openApplication(
                    withBundleIdentifier: request.hostBundleIdentifier
                )
            } catch {
                replyHandler(nil, error)
                return
            }

            guard let reply = BitwardenSafariOneShotHandler.handle(message: request.message) else {
                BitwardenDesktopTransportDiagnostics.log(
                    outcome: .unsupportedCommand,
                    command: BitwardenSafariOneShotHandler.publicCommandName(in: request.message)
                )
                replyHandler(
                    nil,
                    SumiNativeMessagingRelay.makeError(
                        code: .companionAppProtocolUnknown,
                        diagnostic: nil
                    )
                )
                return
            }
            replyHandler(reply, nil)
        }
    }

    func connectPort(
        session: SumiNativeMessagingPortSession,
        launcher: SumiHostApplicationLaunching,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        let sessionKey = ObjectIdentifier(session)
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard BitwardenDesktopProxyPathResolver.isHostApplicationInstalled(launcher: launcher) else {
                BitwardenDesktopTransportDiagnostics.log(outcome: .desktopAppNotInstalled)
                completionHandler(
                    BitwardenDesktopProxyTransportErrorMapper.relayError(for: .proxyBinaryMissing)
                )
                return
            }

            guard let proxyURL = BitwardenDesktopProxyPathResolver.proxyExecutableURL(launcher: launcher) else {
                BitwardenDesktopTransportDiagnostics.log(outcome: .desktopAppNotInstalled)
                completionHandler(
                    BitwardenDesktopProxyTransportErrorMapper.relayError(for: .proxyBinaryMissing)
                )
                return
            }

            let appId = UUID().uuidString
            var transport = transportFactory()
            let state = BitwardenPortSessionState(
                session: session,
                transport: transport,
                appId: appId,
                replyTimeout: replyTimeout
            )
            portSessions[sessionKey] = state

            transport.onDisconnect = { [weak self] in
                guard let self else { return }
                self.portSessions.removeValue(forKey: sessionKey)?.disconnectAssociatedSession()
            }

            do {
                try await transport.start(
                    proxyExecutableURL: proxyURL,
                    handshakeTimeout: handshakeTimeout
                )
                completionHandler(nil)
                return
            } catch let error as BitwardenDesktopProxyTransportError where error == .desktopNotRunning {
                transport.shutdown()
                portSessions.removeValue(forKey: sessionKey)
            } catch let error as BitwardenDesktopProxyTransportError {
                portSessions.removeValue(forKey: sessionKey)
                transport.shutdown()
                completionHandler(BitwardenDesktopProxyTransportErrorMapper.relayError(for: error))
                return
            } catch {
                portSessions.removeValue(forKey: sessionKey)
                transport.shutdown()
                completionHandler(error)
                return
            }

            do {
                try await launcher.openApplication(
                    withBundleIdentifier: session.resolvedHostBundleIdentifier
                )
            } catch {
                BitwardenDesktopTransportDiagnostics.log(outcome: .desktopAppNotRunning)
                completionHandler(error)
                return
            }

            transport = transportFactory()
            let relaunchedState = BitwardenPortSessionState(
                session: session,
                transport: transport,
                appId: appId,
                replyTimeout: replyTimeout
            )
            portSessions[sessionKey] = relaunchedState

            transport.onDisconnect = { [weak self] in
                guard let self else { return }
                self.portSessions.removeValue(forKey: sessionKey)?.disconnectAssociatedSession()
            }

            do {
                try await transport.start(
                    proxyExecutableURL: proxyURL,
                    handshakeTimeout: handshakeTimeout
                )
                completionHandler(nil)
            } catch let error as BitwardenDesktopProxyTransportError {
                portSessions.removeValue(forKey: sessionKey)
                transport.shutdown()
                completionHandler(BitwardenDesktopProxyTransportErrorMapper.relayError(for: error))
            } catch {
                portSessions.removeValue(forKey: sessionKey)
                transport.shutdown()
                completionHandler(error)
            }
        }
    }

    func relayPortMessage(
        session: SumiNativeMessagingPortSession,
        message: Any
    ) -> Bool {
        guard let state = portSessions[ObjectIdentifier(session)] else {
            return false
        }
        _ = message
        guard let payload = message as? [String: Any] else {
            return false
        }
        state.relayExtensionMessage(payload)
        return true
    }
}

@available(macOS 15.5, *)
@MainActor
private final class BitwardenPortSessionState {
    private weak var session: SumiNativeMessagingPortSession?
    private let transport: any BitwardenDesktopProxyTransporting
    private let appId: String
    private let replyTimeout: Duration
    private var pendingReplies: [Int: Task<Void, Never>] = [:]

    init(
        session: SumiNativeMessagingPortSession,
        transport: any BitwardenDesktopProxyTransporting,
        appId: String,
        replyTimeout: Duration
    ) {
        self.session = session
        self.transport = transport
        self.appId = appId
        self.replyTimeout = replyTimeout
        transport.onReceive = { [weak self] incoming in
            self?.handleDesktopMessage(incoming)
        }
    }

    func disconnectAssociatedSession() {
        session?.disconnect()
    }

    func relayExtensionMessage(_ payload: [String: Any]) {
        let command = payload["command"] as? String
        if let command, BitwardenPortCommand.isRelaySupported(command) == false {
            BitwardenDesktopTransportDiagnostics.log(outcome: .unsupportedCommand, command: command)
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
            BitwardenDesktopTransportDiagnostics.log(outcome: .desktopIntegrationDisabled, command: command)
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
                if replyObject["response"] != nil {
                    BitwardenDesktopTransportDiagnostics.log(
                        outcome: .realDesktopStatusSucceeded,
                        command: command
                    )
                } else {
                    BitwardenDesktopTransportDiagnostics.log(
                        outcome: .desktopReplyMalformed,
                        command: command
                    )
                }
            default:
                break
            }
        }

        if let messageId = replyObject["messageId"] as? Int {
            pendingReplies.removeValue(forKey: messageId)?.cancel()
        }

        session?.sendReplyToExtension(replyObject)
    }

    private func scheduleReplyTimeout(for messageId: Int, command: String?) {
        pendingReplies[messageId]?.cancel()
        pendingReplies[messageId] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.replyTimeout ?? .seconds(30))
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

private enum BitwardenPortCommand {
    static let getBiometricsStatus = "getBiometricsStatus"
    static let setupEncryption = "setupEncryption"

    static func isRelaySupported(_ command: String) -> Bool {
        switch command {
        case getBiometricsStatus, setupEncryption:
            return true
        default:
            return false
        }
    }
}

@MainActor
enum BitwardenSafariOneShotHandler {
    static func handle(message: Any) -> Any? {
        guard let payload = message as? [String: Any],
              let command = payload["command"] as? String
        else {
            return nil
        }

        switch command {
        case "readFromClipboard":
            return NSPasteboard.general.string(forType: .string) as Any
        case "copyToClipboard":
            guard let data = payload["data"] as? String else { return nil }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(data, forType: .string)
            return NSNull()
        case "biometricUnlockAvailable":
            let available = LAContext().bitwardenBiometricsAvailable
            return [
                "message": [
                    "command": command,
                    "response": available ? "available" : "not available",
                    "timestamp": currentTimestampMillis,
                ],
            ]
        case "getBiometricsStatus":
            let messageId = payload["messageId"]
            return [
                "message": [
                    "command": command,
                    "response": BitwardenBiometricsStatus.available.rawValue,
                    "timestamp": currentTimestampMillis,
                    "messageId": messageId as Any,
                ],
            ]
        default:
            return nil
        }
    }

    static func publicCommandName(in message: Any) -> String? {
        guard let payload = message as? [String: Any] else { return nil }
        return payload["command"] as? String
    }

    private static var currentTimestampMillis: Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

private enum BitwardenBiometricsStatus: Int {
    case available = 0
}

private extension LAContext {
    var bitwardenBiometricsAvailable: Bool {
        var error: NSError?
        canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        if let error, error.code != LAError.biometryLockout.rawValue {
            return false
        }
        return true
    }
}

#if DEBUG
@MainActor
enum BitwardenNativeMessagingManualProbe {
    static func probeInstalledDesktopProxy(
        launcher: SumiHostApplicationLaunching = SumiNSWorkspaceHostApplicationLauncher()
    ) async -> String {
        guard BitwardenDesktopProxyPathResolver.isHostApplicationInstalled(launcher: launcher) else {
            return BitwardenDesktopTransportOutcome.desktopAppNotInstalled.rawValue
        }
        guard let proxyURL = BitwardenDesktopProxyPathResolver.proxyExecutableURL(launcher: launcher) else {
            return BitwardenDesktopTransportOutcome.desktopAppNotInstalled.rawValue
        }
        let transport = BitwardenDesktopProxyProcessTransport()
        do {
            try await transport.start(proxyExecutableURL: proxyURL, handshakeTimeout: .seconds(5))
            transport.shutdown()
            return BitwardenDesktopTransportOutcome.realDesktopHandshakeSucceeded.rawValue
        } catch let error as BitwardenDesktopProxyTransportError {
            return BitwardenDesktopProxyTransportErrorMapper.outcome(for: error).rawValue
        } catch {
            return BitwardenDesktopTransportOutcome.desktopTransportUnavailable.rawValue
        }
    }
}
#endif
