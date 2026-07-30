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
final class BitwardenNativeMessagingAdapter: SumiNativeMessagingProtocolAdapter {
    static let supportedHostBundleIdentifier = BitwardenNativeMessagingIdentifiers.hostBundleIdentifier

    let protocolIdentifier = BitwardenNativeMessagingIdentifiers.protocolIdentifier

    private let transportFactory: () -> any BitwardenDesktopProxyTransporting
    private let handshakeTimeout: Duration
    private let replyTimeout: Duration
    private let delayedActions: MainActorDelayedActionScheduler
    private var portSessions: [ObjectIdentifier: BitwardenPortSessionState] = [:]

    init(
        transportFactory: @escaping () -> any BitwardenDesktopProxyTransporting = {
            BitwardenDesktopProxyProcessTransport()
        },
        handshakeTimeout: Duration = .seconds(30),
        replyTimeout: Duration = SumiNativeMessagingConnection.defaultReplyTimeout,
        delayedActions: MainActorDelayedActionScheduler = .live
    ) {
        self.transportFactory = transportFactory
        self.handshakeTimeout = handshakeTimeout
        self.replyTimeout = replyTimeout
        self.delayedActions = delayedActions
    }

    func supports(hostBundleIdentifier: String) -> Bool {
        hostBundleIdentifier == Self.supportedHostBundleIdentifier
    }

    func relayOneShotMessage(
        request: SumiNativeMessagingOneShotRequest,
        launcher: SumiHostApplicationLaunching,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        _ = launcher
        if let payload = request.message as? [String: Any],
           let command = payload["command"] as? String,
           BitwardenSafariOneShotHandler.isBiometricPromptCommand(command) {
            BitwardenSafariOneShotHandler.handleBiometricPrompt(payload: payload) { message in
                replyHandler(["message": message], nil)
            }
            return
        }
        if BitwardenSafariOneShotHandler.handleAsync(
            message: request.message,
            replyHandler: { replyHandler($0, nil) }
        ) {
            return
        }
        if let reply = BitwardenSafariOneShotHandler.handle(message: request.message) {
            replyHandler(reply, nil)
            return
        }

        let command = BitwardenSafariOneShotHandler.publicCommandName(in: request.message)
        let outcome = BitwardenSafariOneShotHandler.relayOutcome(for: command)
        BitwardenDesktopTransportDiagnostics.log(
            outcome: outcome,
            command: command
        )
        replyHandler(nil, BitwardenSafariOneShotHandler.relayError(for: outcome))
    }

    func connectPort(
        session: SumiNativeMessagingPortSession,
        launcher: SumiHostApplicationLaunching,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        let sessionKey = ObjectIdentifier(session)
        Task { @MainActor [weak self] in
            guard let self else {
                completionHandler(
                    SumiNativeMessagingErrorMapper.relayError(
                        code: .relayCancelled,
                        diagnostic: nil
                    )
                )
                return
            }
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
            let transport = transportFactory()
            let state = BitwardenPortSessionState(
                session: session,
                transport: transport,
                appId: appId,
                replyTimeout: replyTimeout,
                delayedActions: delayedActions
            )
            portSessions[sessionKey] = state
            SumiNativeMessagingRuntimeCounters.recordAdapterPortSessionOpened()

            transport.onDisconnect = { [weak self] in
                guard let self else { return }
                self.removePortSession(forKey: sessionKey)?.disconnectAssociatedSession()
            }

            // Safari Bitwarden treats connectNative as immediately ready; complete WebKit before
            // desktop_proxy handshake so early port.postMessage calls are queued, not dropped.
            completionHandler(nil)

            let handshakeError = await self.establishDesktopTransport(
                sessionKey: sessionKey,
                session: session,
                transport: transport,
                state: state,
                proxyURL: proxyURL,
                launcher: launcher
            )
            if let handshakeError {
                self.removePortSession(forKey: sessionKey)?.disconnectAssociatedSession(
                    throwing: handshakeError
                )
            }
        }
    }

    private func establishDesktopTransport(
        sessionKey: ObjectIdentifier,
        session: SumiNativeMessagingPortSession,
        transport: any BitwardenDesktopProxyTransporting,
        state: BitwardenPortSessionState,
        proxyURL: URL,
        launcher: SumiHostApplicationLaunching
    ) async -> NSError? {
        _ = launcher
        do {
            try await transport.start(
                proxyExecutableURL: proxyURL,
                handshakeTimeout: handshakeTimeout
            )
            state.markTransportReady()
            return nil
        } catch let error as BitwardenDesktopProxyTransportError where error == .desktopNotRunning {
            // Safari parity: the Bitwarden Safari extension never launches the
            // desktop app. When the desktop is not running its native-messaging
            // proxy is simply unavailable, so we disconnect the port (the
            // extension observes "desktop disconnected") rather than calling
            // NSWorkspace to open Bitwarden. Local biometric commands continue
            // to be served without the desktop.
            BitwardenDesktopTransportDiagnostics.log(outcome: .desktopAppNotRunning)
            removePortSession(forKey: sessionKey)?.disconnectAssociatedSession()
            return nil
        } catch let error as BitwardenDesktopProxyTransportError {
            return BitwardenDesktopProxyTransportErrorMapper.relayError(for: error)
        } catch {
            return error as NSError
        }
    }

    func disconnectPort(session: SumiNativeMessagingPortSession) {
        removePortSession(forKey: ObjectIdentifier(session))?.shutdown()
    }

    private func removePortSession(forKey sessionKey: ObjectIdentifier) -> BitwardenPortSessionState? {
        guard let state = portSessions.removeValue(forKey: sessionKey) else { return nil }
        SumiNativeMessagingRuntimeCounters.recordAdapterPortSessionClosed()
        return state
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
