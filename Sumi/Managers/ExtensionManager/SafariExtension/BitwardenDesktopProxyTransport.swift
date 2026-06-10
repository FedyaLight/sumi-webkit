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
    static func log(outcome: BitwardenDesktopTransportOutcome, command: String? = nil) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
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
}

@MainActor
final class BitwardenDesktopProxyProcessTransport: BitwardenDesktopProxyTransporting {
    private(set) var isConnected = false
    var onDisconnect: (() -> Void)?
    var onReceive: (([String: Any]) -> Void)?

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readTask: Task<Void, Never>?
    private var pendingBuffer = Data()
    private var handshakeCommand: String?

    func start(
        proxyExecutableURL: URL,
        handshakeTimeout: Duration = .seconds(30)
    ) async throws {
        guard isConnected == false else { return }

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
               nsError.code == EPERM || nsError.code == EACCES
            {
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
        handshakeCommand = nil
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
                continue
            }
            guard let object = decoded as? [String: Any] else {
                BitwardenDesktopTransportDiagnostics.log(outcome: .desktopReplyMalformed)
                continue
            }
            if handshakeCommand == nil, let command = object["command"] as? String {
                handshakeCommand = command
                continue
            }
            onReceive?(object)
        }
    }

    private func waitForHandshakeCommand(timeout: Duration) async throws -> String {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let handshakeCommand {
                return handshakeCommand
            }
            if process?.isRunning == false {
                if handshakeCommand == nil {
                    BitwardenDesktopTransportDiagnostics.log(outcome: .desktopAppNotRunning)
                    throw BitwardenDesktopProxyTransportError.desktopNotRunning
                }
                BitwardenDesktopTransportDiagnostics.log(outcome: .desktopIntegrationDisabled)
                throw BitwardenDesktopProxyTransportError.desktopIntegrationDisabled
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        BitwardenDesktopTransportDiagnostics.log(outcome: .desktopTimeout)
        throw BitwardenDesktopProxyTransportError.timeout
    }

    private func handleTransportEnded() {
        guard isConnected else { return }
        isConnected = false
        BitwardenDesktopTransportDiagnostics.log(outcome: .desktopSocketUnavailable)
        onDisconnect?()
    }
}

enum BitwardenDesktopProxyFraming {
    /// Chrome native messaging frame cap (1 MiB). Oversized length prefixes are discarded.
    static let maxFrameBytes = 1_048_576

    static func encode(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw BitwardenDesktopProxyTransportError.malformedReply
        }
        let json = try JSONSerialization.data(withJSONObject: object)
        var length = UInt32(json.count).littleEndian
        var data = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        data.append(json)
        return data
    }

    static func decodeNext(from buffer: inout Data) -> Any? {
        guard buffer.count >= MemoryLayout<UInt32>.size else { return nil }
        let length: UInt32 = buffer.withUnsafeBytes { raw in
            raw.load(as: UInt32.self).littleEndian
        }
        let frameSize = Int(length)
        guard frameSize >= 0 else {
            buffer.removeAll(keepingCapacity: false)
            return NSNull()
        }
        guard frameSize <= maxFrameBytes else {
            buffer.removeAll(keepingCapacity: false)
            return NSNull()
        }
        guard buffer.count >= MemoryLayout<UInt32>.size + frameSize else {
            return nil
        }
        let jsonStart = MemoryLayout<UInt32>.size
        let jsonEnd = jsonStart + frameSize
        let json = buffer.subdata(in: jsonStart..<jsonEnd)
        buffer.removeSubrange(0..<jsonEnd)
        guard let object = try? JSONSerialization.jsonObject(with: json) else {
            return NSNull()
        }
        return object
    }
}

@MainActor
enum BitwardenDesktopProxyTransportErrorMapper {
    static func relayError(for error: BitwardenDesktopProxyTransportError) -> NSError {
        switch error {
        case .appNotInstalled, .proxyBinaryMissing, .desktopNotRunning:
            return SumiNativeMessagingRelay.makeError(code: .hostNotFound, diagnostic: nil)
        case .desktopIntegrationDisabled, .processLaunchFailed, .permissionDenied:
            return SumiNativeMessagingRelay.makeError(code: .companionAppProtocolUnknown, diagnostic: nil)
        case .timeout:
            return SumiNativeMessagingRelay.makeError(code: .relayTimeout, diagnostic: nil)
        case .malformedReply, .protocolMismatch:
            return SumiNativeMessagingRelay.makeError(code: .companionAppProtocolUnknown, diagnostic: nil)
        case .portDisconnected:
            return SumiNativeMessagingRelay.makeError(code: .relayCancelled, diagnostic: nil)
        }
    }

    static func capability(for error: BitwardenDesktopProxyTransportError)
        -> SumiNativeMessagingAdapterCapability
    {
        switch error {
        case .appNotInstalled, .proxyBinaryMissing:
            return .appNotInstalled
        case .desktopNotRunning:
            return .adapterUnavailable
        case .desktopIntegrationDisabled, .processLaunchFailed, .permissionDenied:
            return .desktopIntegrationDisabled
        case .timeout:
            return .timeout
        case .malformedReply, .protocolMismatch:
            return .adapterUnavailable
        case .portDisconnected:
            return .portDisconnected
        }
    }

    static func outcome(for error: BitwardenDesktopProxyTransportError)
        -> BitwardenDesktopTransportOutcome
    {
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
