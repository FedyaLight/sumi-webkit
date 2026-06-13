//
//  NativeMessagingHostProcessTransport.swift
//  Sumi
//
//  Generic stdio transport for standard native-messaging hosts.
//

import Foundation

enum NativeMessagingHostTransportError: Error, Equatable {
    case hostManifestMissing
    case hostExecutableMissing
    case unsupportedHostKind
    case processLaunchFailed
    case permissionDenied
    case malformedMessage
    case malformedHostResponse
    case portDisconnected
    case timeout
}

@MainActor
protocol NativeMessagingHostTransporting: AnyObject {
    var isConnected: Bool { get }
    var onDisconnect: (() -> Void)? { get set }
    var onReceive: (([String: Any]) -> Void)? { get set }

    func start(hostExecutableURL: URL) async throws
    func send(_ object: [String: Any]) throws
    func shutdown()
}

@MainActor
final class NativeMessagingHostProcessTransport: NativeMessagingHostTransporting {
    private(set) var isConnected = false
    var onDisconnect: (() -> Void)?
    var onReceive: (([String: Any]) -> Void)?

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readTask: Task<Void, Never>?
    private var pendingBuffer = Data()

    func start(hostExecutableURL: URL) async throws {
        guard isConnected == false else { return }

        let process = Process()
        process.executableURL = hostExecutableURL
        process.currentDirectoryURL = hostExecutableURL.deletingLastPathComponent()
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
                NativeMessagingHostBackendDiagnostics.log(
                    outcome: .permissionDenied,
                    hostName: nil,
                    backend: StandardNativeMessagingHostBackend.backendIdentifier,
                    sourceKind: nil
                )
                throw NativeMessagingHostTransportError.permissionDenied
            }
            NativeMessagingHostBackendDiagnostics.log(
                outcome: .hostProcessLaunchFailed,
                hostName: nil,
                backend: StandardNativeMessagingHostBackend.backendIdentifier,
                sourceKind: nil
            )
            throw NativeMessagingHostTransportError.processLaunchFailed
        }

        self.process = process
        stdinHandle = stdinPipe.fileHandleForWriting
        isConnected = true
        SumiNativeMessagingRuntimeCounters.recordDesktopTransportStarted()
        startReadLoop(stdoutPipe.fileHandleForReading)
        NativeMessagingHostBackendDiagnostics.log(
            outcome: .hostProcessStarted,
            hostName: nil,
            backend: StandardNativeMessagingHostBackend.backendIdentifier,
            sourceKind: nil
        )
    }

    func send(_ object: [String: Any]) throws {
        guard isConnected, let stdinHandle else {
            NativeMessagingHostBackendDiagnostics.log(
                outcome: .hostDisconnected,
                hostName: nil,
                backend: StandardNativeMessagingHostBackend.backendIdentifier,
                sourceKind: nil
            )
            throw NativeMessagingHostTransportError.portDisconnected
        }
        let payload = try NativeMessagingStdioFraming.encode(object)
        try stdinHandle.write(contentsOf: payload)
    }

    func shutdown() {
        let wasActive = isConnected || process != nil || readTask != nil
        isConnected = false
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
        while let decoded = NativeMessagingStdioFraming.decodeNext(from: &pendingBuffer) {
            guard decoded is NSNull == false,
                  let object = decoded as? [String: Any]
            else {
                NativeMessagingHostBackendDiagnostics.log(
                    outcome: .malformedHostResponse,
                    hostName: nil,
                    backend: StandardNativeMessagingHostBackend.backendIdentifier,
                    sourceKind: nil
                )
                continue
            }
            NativeMessagingHostBackendDiagnostics.log(
                outcome: .hostResponseReceived,
                hostName: nil,
                backend: StandardNativeMessagingHostBackend.backendIdentifier,
                sourceKind: nil
            )
            onReceive?(object)
        }
    }

    private func handleTransportEnded() {
        guard isConnected else { return }
        isConnected = false
        NativeMessagingHostBackendDiagnostics.log(
            outcome: .hostDisconnected,
            hostName: nil,
            backend: StandardNativeMessagingHostBackend.backendIdentifier,
            sourceKind: nil
        )
        onDisconnect?()
    }
}

enum NativeMessagingStdioFraming {
    /// Standard native messaging frame cap used by Chromium-style hosts.
    static let maxFrameBytes = 1_048_576

    static func encode(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw NativeMessagingHostTransportError.malformedMessage
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
        guard frameSize >= 0, frameSize <= maxFrameBytes else {
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
        return (try? JSONSerialization.jsonObject(with: json)) ?? NSNull()
    }
}

enum NativeMessagingJSONPayload {
    static func object(from message: Any) -> [String: Any]? {
        if let object = message as? [String: Any] {
            return object
        }
        if let object = message as? NSDictionary {
            return object as? [String: Any]
        }
        if let string = message as? String,
           let data = string.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            return object
        }
        if let data = message as? Data,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            return object
        }
        return nil
    }
}

enum NativeMessagingHostBackendDiagnosticOutcome: String {
    case backendSelected
    case hostManifestMissing
    case hostExecutableFound
    case hostExecutableMissing
    case unsupportedHostKind
    case hostProcessStarted
    case hostProcessLaunchFailed
    case hostRequestRelayed
    case hostResponseReceived
    case hostDisconnected
    case portOpened
    case portClosed
    case malformedExtensionMessage
    case malformedHostResponse
    case messageTimedOut
    case relayCancelled
    case permissionDenied
}

enum NativeMessagingHostBackendDiagnostics {
    static func log(
        outcome: NativeMessagingHostBackendDiagnosticOutcome,
        hostName: String?,
        backend: String,
        sourceKind: NativeMessagingHostResolutionSourceKind?
    ) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
            RuntimeDiagnostics.debug(category: "StandardNativeMessagingHost") {
                var parts = [
                    "outcome=\(outcome.rawValue)",
                    "backend=\(backend)",
                ]
                if let hostName {
                    parts.append("host=\(hostName)")
                }
                if let sourceKind {
                    parts.append("source=\(sourceKind.rawValue)")
                }
                return parts.joined(separator: " ")
            }
        #else
            _ = (outcome, hostName, backend, sourceKind)
        #endif
    }
}

typealias NativeHostProcessTransport = NativeMessagingHostProcessTransport
