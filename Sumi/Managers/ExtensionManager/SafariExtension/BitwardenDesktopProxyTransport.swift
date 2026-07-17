//
//  BitwardenDesktopProxyTransport.swift
//  Sumi
//
//  Length-prefixed JSON stdio transport for Bitwarden desktop_proxy.
//  Public protocol: browser spawns desktop_proxy (stdio, 4-byte LE JSON frames);
//  proxy forwards to Desktop over node-ipc Unix socket (bitwarden/desktop PR #566).
//

import Foundation

/// Sanitized transport outcome buckets for real desktop_proxy verification.
/// Never log message bodies or credential fields — command names only.
enum BitwardenDesktopTransportOutcome: String, Codable, Sendable, Equatable {
    case realDesktopHandshakeSucceeded
    case realDesktopStatusSucceeded
    /// Browser integration disabled in Bitwarden Desktop settings (handshake `disconnected`).
    case browserIntegrationDisabled
    case desktopIntegrationDisabled
    case desktopAppNotInstalled
    case desktopAppNotRunning
    case desktopTransportUnavailable
    case desktopSocketUnavailable
    case desktopProxyProtocolMismatch
    case desktopReplyMalformed
    case desktopTimeout
    case desktopPermissionDenied
    case unsupportedCommand
    /// Public `BiometricsStatus.UnlockNeeded` — vault unlock required before biometrics.
    case setupEncryptionRequired
    /// Public command name is known but not implemented in this adapter cycle.
    case commandNotYetImplemented
    /// Public protocol cannot be bridged on this WebKit path without undocumented behavior.
    case blockedPublicProtocolGap
}

enum BitwardenDesktopProxyTransportError: Error, Equatable {
    case appNotInstalled
    case proxyBinaryMissing
    case desktopNotRunning
    case desktopIntegrationDisabled
    case timeout
    case malformedReply
    case protocolMismatch
    case portDisconnected
    case processLaunchFailed
    case permissionDenied
}

@MainActor
protocol BitwardenDesktopProxyTransporting: AnyObject {
    var isConnected: Bool { get }
    var onDisconnect: (() -> Void)? { get set }
    var onReceive: (([String: Any]) -> Void)? { get set }

    func start(
        proxyExecutableURL: URL,
        handshakeTimeout: Duration
    ) async throws

    func send(_ object: [String: Any]) throws

    func shutdown()
}

@MainActor
enum BitwardenDesktopProxyPathResolver {
    static func proxyExecutableURL(launcher: SumiHostApplicationLaunching) -> URL? {
        guard let appURL = launcher.urlForApplication(
            withBundleIdentifier: BitwardenNativeMessagingIdentifiers.hostBundleIdentifier
        ) else {
            return nil
        }
        let proxyURL = appURL.appendingPathComponent(BitwardenNativeMessagingIdentifiers.proxyRelativePath)
        return FileManager.default.isExecutableFile(atPath: proxyURL.path) ? proxyURL : nil
    }

    static func isHostApplicationInstalled(launcher: SumiHostApplicationLaunching) -> Bool {
        launcher.urlForApplication(
            withBundleIdentifier: BitwardenNativeMessagingIdentifiers.hostBundleIdentifier
        ) != nil
    }
}

@MainActor
enum BitwardenDesktopTransportDiagnostics {
    private static var lastUnsupportedCommandLog: [String: ContinuousClock.Instant] = [:]
    private static let unsupportedCommandCoalesceWindow: Duration = .seconds(5)

    static func log(outcome: BitwardenDesktopTransportOutcome, command: String? = nil) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
            if let command, outcome == .unsupportedCommand || outcome == .commandNotYetImplemented {
                logUnsupportedCommandCoalesced(command: command, outcome: outcome)
                return
            }
            RuntimeDiagnostics.debug(category: "BitwardenDesktopTransport") {
                if let command {
                    return "outcome=\(outcome.rawValue) command=\(command)"
                }
                return "outcome=\(outcome.rawValue)"
            }
        #else
            _ = (outcome, command)
        #endif
    }

    #if DEBUG || SUMI_DIAGNOSTICS
    private static func logUnsupportedCommandCoalesced(
        command: String,
        outcome: BitwardenDesktopTransportOutcome
    ) {
        let now = ContinuousClock.now
        if let last = lastUnsupportedCommandLog[command],
           now - last < unsupportedCommandCoalesceWindow {
            return
        }
        lastUnsupportedCommandLog[command] = now
        RuntimeDiagnostics.debug(category: "BitwardenDesktopTransport") {
            "outcome=\(outcome.rawValue) command=\(command)"
        }
    }
    #endif
}

@MainActor
final class BitwardenDesktopProxyProcessTransport: BitwardenDesktopProxyTransporting {
    private enum HandshakeState {
        case idle
        case waiting(CheckedContinuation<String, any Error>)
        case received(String)
        case failed(any Error)
        case terminal

        var blocksPreconnectionFrames: Bool {
            switch self {
            case .received, .failed, .terminal:
                return true
            case .idle, .waiting:
                return false
            }
        }
    }

    private(set) var isConnected = false
    var onDisconnect: (() -> Void)?
    var onReceive: (([String: Any]) -> Void)?

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readTask: Task<Void, Never>?
    private var pendingBuffer = Data()
    private var handshakeState = HandshakeState.idle
    private var handshakeTimeoutTask: Task<Void, Never>?
    private var transportDidEnd = false

    func start(
        proxyExecutableURL: URL,
        handshakeTimeout: Duration = .seconds(30)
    ) async throws {
        guard isConnected == false else { return }
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        handshakeState = .idle
        transportDidEnd = false

        let process = Process()
        process.executableURL = proxyExecutableURL
        process.standardError = FileHandle.nullDevice

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe

        do {
            try process.run()
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSPOSIXErrorDomain,
               nsError.code == EPERM || nsError.code == EACCES {
                BitwardenDesktopTransportDiagnostics.log(outcome: .desktopPermissionDenied)
                throw BitwardenDesktopProxyTransportError.permissionDenied
            }
            BitwardenDesktopTransportDiagnostics.log(outcome: .desktopTransportUnavailable)
            throw BitwardenDesktopProxyTransportError.processLaunchFailed
        }

        self.process = process
        stdinHandle = stdinPipe.fileHandleForWriting
        SumiNativeMessagingRuntimeCounters.recordDesktopTransportStarted()
        startReadLoop(stdoutPipe.fileHandleForReading)

        let command = try await waitForHandshakeCommand(timeout: handshakeTimeout)
        guard !transportDidEnd else {
            shutdown()
            throw BitwardenDesktopProxyTransportError.desktopNotRunning
        }

        switch command {
        case "connected":
            isConnected = true
            BitwardenDesktopTransportDiagnostics.log(outcome: .realDesktopHandshakeSucceeded)
        case "disconnected":
            shutdown()
            BitwardenDesktopTransportDiagnostics.log(outcome: .browserIntegrationDisabled)
            throw BitwardenDesktopProxyTransportError.desktopIntegrationDisabled
        default:
            shutdown()
            BitwardenDesktopTransportDiagnostics.log(outcome: .desktopProxyProtocolMismatch)
            throw BitwardenDesktopProxyTransportError.protocolMismatch
        }
    }

    func send(_ object: [String: Any]) throws {
        guard isConnected, let stdinHandle else {
            BitwardenDesktopTransportDiagnostics.log(outcome: .desktopSocketUnavailable)
            throw BitwardenDesktopProxyTransportError.portDisconnected
        }
        let payload = try BitwardenDesktopProxyFraming.encode(object)
        try stdinHandle.write(contentsOf: payload)
    }

    func shutdown() {
        let wasActive = isConnected || process != nil || readTask != nil
        isConnected = false
        completeHandshake(.failure(BitwardenDesktopProxyTransportError.portDisconnected))
        readTask?.cancel()
        readTask = nil
        stdinHandle?.closeFile()
        stdinHandle = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        pendingBuffer.removeAll()
        if wasActive {
            SumiNativeMessagingRuntimeCounters.recordDesktopTransportStopped()
        }
    }

    private func startReadLoop(_ handle: FileHandle) {
        readTask = Task.detached(priority: .utility) { [weak self] in
            while Task.isCancelled == false {
                let chunk = handle.availableData
                if chunk.isEmpty {
                    await MainActor.run {
                        self?.handleTransportEnded()
                    }
                    return
                }
                await MainActor.run {
                    self?.ingest(chunk)
                }
            }
        }
    }

    private func ingest(_ chunk: Data) {
        pendingBuffer.append(chunk)
        while let decoded = BitwardenDesktopProxyFraming.decodeNext(from: &pendingBuffer) {
            if decoded is NSNull {
                BitwardenDesktopTransportDiagnostics.log(outcome: .desktopReplyMalformed)
                completeHandshake(.failure(BitwardenDesktopProxyTransportError.malformedReply))
                continue
            }
            guard let object = decoded as? [String: Any] else {
                BitwardenDesktopTransportDiagnostics.log(outcome: .desktopReplyMalformed)
                completeHandshake(.failure(BitwardenDesktopProxyTransportError.malformedReply))
                continue
            }
            if !isConnected, handshakeState.blocksPreconnectionFrames {
                continue
            }
            if let command = object["command"] as? String {
                completeHandshake(.success(command))
                continue
            }
            if !isConnected {
                BitwardenDesktopTransportDiagnostics.log(outcome: .desktopProxyProtocolMismatch)
                completeHandshake(.failure(BitwardenDesktopProxyTransportError.protocolMismatch))
                continue
            }
            onReceive?(object)
        }
    }

    private func waitForHandshakeCommand(timeout: Duration) async throws -> String {
        switch handshakeState {
        case .received(let command):
            finishConsumedHandshake()
            return command
        case .failed(let error):
            finishConsumedHandshake()
            throw error
        case .terminal:
            throw BitwardenDesktopProxyTransportError.portDisconnected
        case .waiting:
            throw BitwardenDesktopProxyTransportError.protocolMismatch
        case .idle:
            break
        }
        if process?.isRunning == false {
            BitwardenDesktopTransportDiagnostics.log(outcome: .desktopAppNotRunning)
            throw BitwardenDesktopProxyTransportError.desktopNotRunning
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                handshakeState = .waiting(continuation)
                handshakeTimeoutTask?.cancel()
                handshakeTimeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    guard let self else { return }
                    BitwardenDesktopTransportDiagnostics.log(outcome: .desktopTimeout)
                    self.completeHandshake(.failure(BitwardenDesktopProxyTransportError.timeout))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.completeHandshake(.failure(CancellationError()))
            }
        }
    }

    private func completeHandshake(_ result: Result<String, any Error>) {
        switch handshakeState {
        case .idle:
            switch result {
            case .success(let command):
                handshakeState = .received(command)
            case .failure(let error):
                handshakeState = .failed(error)
            }
        case .waiting(let continuation):
            handshakeState = .terminal
            handshakeTimeoutTask?.cancel()
            handshakeTimeoutTask = nil
            continuation.resume(with: result)
        case .received, .failed, .terminal:
            break
        }
    }

    private func finishConsumedHandshake() {
        handshakeState = .terminal
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
    }

    private func handleTransportEnded() {
        transportDidEnd = true
        if !isConnected {
            BitwardenDesktopTransportDiagnostics.log(outcome: .desktopAppNotRunning)
            completeHandshake(.failure(BitwardenDesktopProxyTransportError.desktopNotRunning))
        }
        guard isConnected else { return }
        isConnected = false
        BitwardenDesktopTransportDiagnostics.log(outcome: .desktopSocketUnavailable)
        onDisconnect?()
    }
}

enum BitwardenDesktopProxyFraming {
    /// Chrome native messaging frame cap (1 MiB). Oversized length prefixes are discarded.
    static let maxFrameBytes = NativeMessagingStdioFraming.maxFrameBytes

    static func encode(_ object: [String: Any]) throws -> Data {
        do {
            return try NativeMessagingStdioFraming.encode(object)
        } catch {
            throw BitwardenDesktopProxyTransportError.malformedReply
        }
    }

    static func decodeNext(from buffer: inout Data) -> Any? {
        NativeMessagingStdioFraming.decodeNext(from: &buffer)
    }
}

@MainActor
enum BitwardenDesktopProxyTransportErrorMapper {
    static let failureBucketUserInfoKey = "SumiNativeMessagingFailureBucket"

    static func relayError(for error: BitwardenDesktopProxyTransportError) -> NSError {
        let relayError: NSError
        switch error {
        case .appNotInstalled, .proxyBinaryMissing:
            relayError = SumiNativeMessagingRelay.makeError(
                code: .hostNotFound,
                description: "Bitwarden Desktop is not installed.",
                diagnostic: nil
            )
        case .desktopNotRunning:
            relayError = SumiNativeMessagingRelay.makeError(
                code: .hostNotFound,
                description: "Bitwarden Desktop is not running.",
                diagnostic: nil
            )
        case .desktopIntegrationDisabled:
            relayError = SumiNativeMessagingRelay.makeError(
                code: .hostLaunchFailed,
                description: "Bitwarden Desktop browser integration is disabled.",
                diagnostic: nil
            )
        case .processLaunchFailed:
            relayError = SumiNativeMessagingRelay.makeError(
                code: .hostLaunchFailed,
                description: "Bitwarden Desktop native messaging transport is unavailable.",
                diagnostic: nil
            )
        case .permissionDenied:
            relayError = SumiNativeMessagingRelay.makeError(
                code: .hostLaunchFailed,
                description: "Permission denied when starting Bitwarden Desktop native messaging.",
                diagnostic: nil
            )
        case .timeout:
            relayError = SumiNativeMessagingRelay.makeError(code: .relayTimeout, diagnostic: nil)
        case .malformedReply:
            relayError = SumiNativeMessagingRelay.makeError(
                code: .companionAppProtocolUnknown,
                description: "Bitwarden Desktop returned a malformed native messaging reply.",
                diagnostic: nil
            )
        case .protocolMismatch:
            relayError = SumiNativeMessagingRelay.makeError(
                code: .companionAppProtocolUnknown,
                description: "Bitwarden Desktop native messaging protocol mismatch.",
                diagnostic: nil
            )
        case .portDisconnected:
            relayError = SumiNativeMessagingRelay.makeError(code: .relayCancelled, diagnostic: nil)
        }

        var userInfo = relayError.userInfo
        userInfo[failureBucketUserInfoKey] = outcome(for: error).rawValue
        return NSError(domain: relayError.domain, code: relayError.code, userInfo: userInfo)
    }

    static func outcome(for error: BitwardenDesktopProxyTransportError)
        -> BitwardenDesktopTransportOutcome {
        switch error {
        case .appNotInstalled, .proxyBinaryMissing:
            return .desktopAppNotInstalled
        case .desktopNotRunning:
            return .desktopAppNotRunning
        case .desktopIntegrationDisabled:
            return .browserIntegrationDisabled
        case .processLaunchFailed:
            return .desktopTransportUnavailable
        case .permissionDenied:
            return .desktopPermissionDenied
        case .timeout:
            return .desktopTimeout
        case .malformedReply:
            return .desktopReplyMalformed
        case .protocolMismatch:
            return .desktopProxyProtocolMismatch
        case .portDisconnected:
            return .desktopSocketUnavailable
        }
    }
}
