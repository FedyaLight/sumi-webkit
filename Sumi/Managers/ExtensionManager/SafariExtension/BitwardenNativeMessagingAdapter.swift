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
        _ = launcher
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
                replyTimeout: replyTimeout
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
        do {
            try await transport.start(
                proxyExecutableURL: proxyURL,
                handshakeTimeout: handshakeTimeout
            )
            state.markTransportReady()
            return nil
        } catch let error as BitwardenDesktopProxyTransportError where error == .desktopNotRunning {
            removePortSession(forKey: sessionKey)?.shutdown()
        } catch let error as BitwardenDesktopProxyTransportError {
            return BitwardenDesktopProxyTransportErrorMapper.relayError(for: error)
        } catch {
            return error as NSError
        }

        do {
            try await launcher.openApplication(
                withBundleIdentifier: session.resolvedHostBundleIdentifier
            )
        } catch {
            BitwardenDesktopTransportDiagnostics.log(outcome: .desktopAppNotRunning)
            return error as NSError
        }

        let queued = state.drainQueuedExtensionMessages()
        let relaunchTransport = transportFactory()
        let relaunchedState = BitwardenPortSessionState(
            session: session,
            transport: relaunchTransport,
            appId: state.appId,
            replyTimeout: replyTimeout
        )
        relaunchedState.enqueueExtensionMessages(queued)
        portSessions[sessionKey] = relaunchedState
        SumiNativeMessagingRuntimeCounters.recordAdapterPortSessionOpened()

        relaunchTransport.onDisconnect = { [weak self] in
            guard let self else { return }
            self.removePortSession(forKey: sessionKey)?.disconnectAssociatedSession()
        }

        do {
            try await relaunchTransport.start(
                proxyExecutableURL: proxyURL,
                handshakeTimeout: handshakeTimeout
            )
            relaunchedState.markTransportReady()
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

@available(macOS 15.5, *)
@MainActor
private final class BitwardenPortSessionState {
    private weak var session: SumiNativeMessagingPortSession?
    private let transport: any BitwardenDesktopProxyTransporting
    let appId: String
    private let replyTimeout: Duration
    private var pendingReplies: [Int: Task<Void, Never>] = [:]
    private var transportReady = false
    private var queuedExtensionMessages: [[String: Any]] = []

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

    func markTransportReady() {
        guard transportReady == false else { return }
        transportReady = true
        flushQueuedExtensionMessages()
    }

    func drainQueuedExtensionMessages() -> [[String: Any]] {
        let queued = queuedExtensionMessages
        queuedExtensionMessages.removeAll()
        return queued
    }

    func enqueueExtensionMessages(_ payloads: [[String: Any]]) {
        guard payloads.isEmpty == false else { return }
        if transportReady {
            payloads.forEach { relayExtensionMessage($0) }
        } else {
            queuedExtensionMessages.append(contentsOf: payloads)
        }
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
        pendingReplies.values.forEach { $0.cancel() }
        pendingReplies.removeAll()
        transport.shutdown()
    }

    func relayExtensionMessage(_ payload: [String: Any]) {
        let command = payload["command"] as? String ?? ""
        switch BitwardenPortCommand.relayOutcome(for: command) {
        case .localSafari:
            if let reply = BitwardenSafariOneShotHandler.portReply(for: payload) {
                if let messageId = payload["messageId"] as? Int {
                    pendingReplies.removeValue(forKey: messageId)?.cancel()
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
            pendingReplies.values.forEach { $0.cancel() }
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
            pendingReplies.removeValue(forKey: messageId)?.cancel()
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
        pendingReplies.removeValue(forKey: messageId)?.cancel()
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

@MainActor
enum BitwardenSafariOneShotHandler {
    /// Public `sleep` command delay from SafariWebExtensionHandler.
    static var sleepDelay: Duration = .seconds(10)

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
            let available = LAContext().bitwardenBiometricsAvailable
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
            let status = LAContext().bitwardenBiometricsAvailable
                ? BitwardenBiometricsStatus.notEnabledInConnectedDesktopApp.rawValue
                : BitwardenBiometricsStatus.hardwareUnavailable.rawValue
            return safariMessageEnvelope(
                command: command,
                response: status,
                messageId: messageId,
                timestamp: timestamp
            )
        case "authenticateWithBiometrics":
            return safariMessageEnvelope(
                command: command,
                response: false,
                messageId: messageId,
                timestamp: timestamp
            )
        case "unlockWithBiometricsForUser":
            return safariMessageEnvelope(
                command: command,
                response: false,
                messageId: messageId,
                timestamp: timestamp
            )
        case "biometricUnlock":
            return safariMessageEnvelope(
                command: command,
                response: "not enabled",
                messageId: messageId,
                timestamp: timestamp
            )
        case "canEnableBiometricUnlock":
            let available = LAContext().bitwardenBiometricsAvailable
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
            return LAContext().bitwardenBiometricsAvailable
                ? BitwardenBiometricsStatus.notEnabledInConnectedDesktopApp.rawValue
                : BitwardenBiometricsStatus.hardwareUnavailable.rawValue
        case "authenticateWithBiometrics":
            return false
        case "unlockWithBiometricsForUser":
            return false
        case "biometricUnlock":
            return "not enabled"
        case "canEnableBiometricUnlock":
            return LAContext().bitwardenBiometricsAvailable
        default:
            return nil
        }
    }

    private static func handleDownloadFile(payload: [String: Any]) -> Bool {
        guard let jsonData = payload["data"] as? String,
              let json = jsonData.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let fileName = object["fileName"] as? String
        else {
            return false
        }

        var blobData: Data?
        if let blobOptions = object["blobOptions"] as? [String: Any],
           blobOptions["type"] as? String == "text/plain",
           let blob = object["blobData"] as? String {
            blobData = blob.data(using: .utf8)
        } else if let blob = object["blobData"] as? String {
            blobData = Data(base64Encoded: blob)
        }
        guard let data = blobData else { return false }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = fileName
        guard panel.runModal() == .OK, let url = panel.url else { return true }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) == false {
            fileManager.createFile(atPath: url.path, contents: Data(), attributes: nil)
        }
        try? data.write(to: url)
        return true
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

private enum BitwardenBiometricsStatus: Int {
    case available = 0
    case unlockNeeded = 1
    case hardwareUnavailable = 2
    case desktopDisconnected = 6
    case notEnabledInConnectedDesktopApp = 8
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
