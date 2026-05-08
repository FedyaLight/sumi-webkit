//
//  NativeMessagingHandler.swift
//  Sumi
//
//  Native messaging host lookup and process bridge for Sumi's WebExtension runtime.
//

import Darwin
import Foundation
import OSLog
import WebKit

@available(macOS 15.5, *)
struct NativeMessagingHostManifest {
    let path: String

    init?(jsonObject: [String: Any]) {
        guard let path = jsonObject["path"] as? String, path.isEmpty == false else {
            return nil
        }
        self.path = path
    }
}

@available(macOS 15.5, *)
final class NativeMessagingProcessSession {
    enum CloseReason {
        case cancelled
        case endOfFile
        case processExited(Int32)
        case error(Error)
    }

    private struct PendingWrite {
        var data: Data
        var offset: Int
        let completion: ((Error?) -> Void)?
    }

    private static let readChunkSize = 64 * 1024
    private static let maximumInboundMessageSize = 1024 * 1024
    private static let maximumQueuedWriteCount = 64
    private static let maximumQueuedWriteBytes = 16 * 1024 * 1024
    private static let processExitDrainGrace: TimeInterval = 0.5

    private let manifest: NativeMessagingHostManifest
    private let closeOnMalformedMessage: Bool
    private let stateQueue: DispatchQueue
    private let onMessage: (Data) -> Void
    private let onClose: (CloseReason) -> Void

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdinWriteSource: DispatchSourceWrite?
    private var stdoutReadSource: DispatchSourceRead?
    private var stderrReadSource: DispatchSourceRead?
    private var isWriteSourceResumed = false
    private var pendingWrites: [PendingWrite] = []
    private var queuedWriteBytes = 0
    private var outputBuffer = Data()
    private var isClosed = false
    private var processExitStatus: Int32?
    private lazy var terminationObserver = NativeMessagingProcessTerminationObserver(
        stateQueue: stateQueue,
        session: self
    )

    init(
        manifest: NativeMessagingHostManifest,
        closeOnMalformedMessage: Bool,
        onMessage: @escaping (Data) -> Void,
        onClose: @escaping (CloseReason) -> Void
    ) {
        self.manifest = manifest
        self.closeOnMalformedMessage = closeOnMalformedMessage
        self.onMessage = onMessage
        self.onClose = onClose
        self.stateQueue = DispatchQueue(
            label: "app.sumi.native-messaging.session.\(UUID().uuidString)",
            qos: .userInitiated
        )
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        stateQueue.async { [weak self] in
            guard let self else { return }

            do {
                try self.startLocked()
                completion(.success(()))
            } catch {
                self.closeHandlesAfterLaunchFailure()
                completion(.failure(error))
            }
        }
    }

    func send(
        _ message: Any,
        completion: ((Error?) -> Void)? = nil
    ) {
        let frameResult = Result {
            try Self.frame(for: message)
        }

        stateQueue.async { [weak self] in
            guard let self else { return }
            guard self.isClosed == false else {
                completion?(Self.error(
                    code: 6,
                    message: "Native messaging session is closed"
                ))
                return
            }

            let frame: Data
            switch frameResult {
            case .success(let preparedFrame):
                frame = preparedFrame
            case .failure(let error):
                completion?(error)
                return
            }

            guard self.pendingWrites.count < Self.maximumQueuedWriteCount,
                  self.queuedWriteBytes + frame.count <= Self.maximumQueuedWriteBytes
            else {
                completion?(Self.error(
                    code: 7,
                    message: "Native messaging write queue is full"
                ))
                return
            }

            self.pendingWrites.append(
                PendingWrite(data: frame, offset: 0, completion: completion)
            )
            self.queuedWriteBytes += frame.count
            self.resumeWriteSourceIfNeeded()
        }
    }

    func cancel(notify: Bool = true) {
        stateQueue.async {
            self.closeLocked(.cancelled, notify: notify)
        }
    }

    private func startLocked() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: manifest.path)

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        let stdinHandle = input.fileHandleForWriting
        let stdoutHandle = output.fileHandleForReading
        let stderrHandle = error.fileHandleForReading

        try Self.setNonBlocking(stdinHandle.fileDescriptor)
        try Self.setNonBlocking(stdoutHandle.fileDescriptor)
        try Self.setNonBlocking(stderrHandle.fileDescriptor)

        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        self.process = process
        self.stdinHandle = stdinHandle
        self.stdoutHandle = stdoutHandle
        self.stderrHandle = stderrHandle

        let terminationObserver = terminationObserver
        process.terminationHandler = { process in
            terminationObserver.processDidTerminate(status: process.terminationStatus)
        }

        configureSources()
        try process.run()
        stdoutReadSource?.resume()
        stderrReadSource?.resume()
    }

    private func configureSources() {
        guard let stdoutHandle, let stderrHandle, let stdinHandle else {
            return
        }

        let stdoutSource = DispatchSource.makeReadSource(
            fileDescriptor: stdoutHandle.fileDescriptor,
            queue: stateQueue
        )
        stdoutSource.setEventHandler { [weak self] in
            self?.readAvailableOutput()
        }
        stdoutSource.setCancelHandler { [weak self] in
            self?.closeStdoutHandle()
        }
        stdoutReadSource = stdoutSource

        let stderrSource = DispatchSource.makeReadSource(
            fileDescriptor: stderrHandle.fileDescriptor,
            queue: stateQueue
        )
        stderrSource.setEventHandler { [weak self] in
            self?.drainAvailableErrorOutput()
        }
        stderrSource.setCancelHandler { [weak self] in
            self?.closeStderrHandle()
        }
        stderrReadSource = stderrSource

        let stdinSource = DispatchSource.makeWriteSource(
            fileDescriptor: stdinHandle.fileDescriptor,
            queue: stateQueue
        )
        stdinSource.setEventHandler { [weak self] in
            self?.writeAvailableInput()
        }
        stdinSource.setCancelHandler { [weak self] in
            self?.closeStdinHandle()
        }
        stdinWriteSource = stdinSource
    }

    private func resumeWriteSourceIfNeeded() {
        guard let stdinWriteSource, isWriteSourceResumed == false else {
            return
        }
        isWriteSourceResumed = true
        stdinWriteSource.resume()
    }

    private func suspendWriteSourceIfNeeded() {
        guard let stdinWriteSource,
              isWriteSourceResumed,
              pendingWrites.isEmpty,
              isClosed == false
        else {
            return
        }
        stdinWriteSource.suspend()
        isWriteSourceResumed = false
    }

    private func readAvailableOutput() {
        guard isClosed == false,
              let stdoutHandle
        else { return }

        var buffer = [UInt8](repeating: 0, count: Self.readChunkSize)
        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(
                    stdoutHandle.fileDescriptor,
                    rawBuffer.baseAddress,
                    rawBuffer.count
                )
            }

            if count > 0 {
                outputBuffer.append(contentsOf: buffer.prefix(count))
                parseOutputBuffer()
                if isClosed {
                    return
                }
                continue
            }

            if count == 0 {
                closeForOutputEndLocked()
                return
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }

            if errno == EINTR {
                continue
            }

            closeLocked(.error(Self.posixError(message: "Native host output read failed")), notify: true)
            return
        }
    }

    private func drainAvailableErrorOutput() {
        guard isClosed == false,
              let stderrHandle
        else { return }

        var buffer = [UInt8](repeating: 0, count: Self.readChunkSize)
        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(
                    stderrHandle.fileDescriptor,
                    rawBuffer.baseAddress,
                    rawBuffer.count
                )
            }

            if count > 0 {
                continue
            }

            if count == 0 {
                stderrReadSource?.cancel()
                stderrReadSource = nil
                return
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }

            if errno == EINTR {
                continue
            }

            stderrReadSource?.cancel()
            stderrReadSource = nil
            return
        }
    }

    private func writeAvailableInput() {
        guard isClosed == false,
              let stdinHandle
        else { return }

        while pendingWrites.isEmpty == false {
            var entry = pendingWrites[0]
            let remaining = entry.data.count - entry.offset
            let count = entry.data.withUnsafeBytes { rawBuffer in
                Darwin.write(
                    stdinHandle.fileDescriptor,
                    rawBuffer.baseAddress?.advanced(by: entry.offset),
                    remaining
                )
            }

            if count > 0 {
                entry.offset += count
                queuedWriteBytes -= count
                pendingWrites[0] = entry

                if entry.offset == entry.data.count {
                    let completion = pendingWrites.removeFirst().completion
                    completion?(nil)
                }
                continue
            }

            if count == 0 {
                let error = Self.error(
                    code: 8,
                    message: "Native host input pipe closed"
                )
                failPendingWrites(error)
                closeLocked(.error(error), notify: true)
                return
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }

            if errno == EINTR {
                continue
            }

            let error = Self.posixError(message: "Native host input write failed")
            failPendingWrites(error)
            closeLocked(.error(error), notify: true)
            return
        }

        suspendWriteSourceIfNeeded()
    }

    private func parseOutputBuffer() {
        while outputBuffer.count >= 4 {
            let length = Self.decodeLength(from: outputBuffer)
            guard length <= Self.maximumInboundMessageSize else {
                closeLocked(.error(Self.error(
                    code: 5,
                    message: "Native host response exceeds maximum size"
                )), notify: true)
                return
            }

            let payloadLength = Int(length)
            let totalLength = 4 + payloadLength
            guard outputBuffer.count >= totalLength else {
                break
            }

            let payload = outputBuffer.subdata(in: 4..<totalLength)
            outputBuffer.removeSubrange(0..<totalLength)

            do {
                _ = try JSONSerialization.jsonObject(with: payload)
                onMessage(payload)
            } catch {
                if closeOnMalformedMessage {
                    closeLocked(.error(error), notify: true)
                    return
                }
            }
        }
    }

    fileprivate func handleProcessExit(status: Int32) {
        guard isClosed == false else { return }

        processExitStatus = status
        drainOutputAfterProcessExit(
            status: status,
            deadline: Date().addingTimeInterval(Self.processExitDrainGrace)
        )
    }

    private func drainOutputAfterProcessExit(status: Int32, deadline: Date) {
        readAvailableOutput()
        guard isClosed == false,
              processExitStatus == status
        else { return }

        guard Date() >= deadline else {
            stateQueue.asyncAfter(deadline: .now() + 0.025) { [weak self] in
                self?.drainOutputAfterProcessExit(
                    status: status,
                    deadline: deadline
                )
            }
            return
        }

        if outputBuffer.isEmpty {
            closeLocked(.processExited(status), notify: true)
        } else {
            closeLocked(.error(Self.error(
                code: 3,
                message: "Native host sent a truncated response"
            )), notify: true)
        }
    }

    private func closeForOutputEndLocked() {
        guard outputBuffer.isEmpty else {
            closeLocked(.error(Self.error(
                code: 3,
                message: "Native host sent a truncated response"
            )), notify: true)
            return
        }

        closeLocked(.endOfFile, notify: true)
    }

    private func closeLocked(_ reason: CloseReason, notify: Bool) {
        guard isClosed == false else { return }

        isClosed = true
        let completions = pendingWrites.map(\.completion)
        let writeError = Self.closeReasonError(reason)
        pendingWrites.removeAll()
        queuedWriteBytes = 0

        stdoutReadSource?.cancel()
        stdoutReadSource = nil
        stderrReadSource?.cancel()
        stderrReadSource = nil
        if let stdinWriteSource {
            if isWriteSourceResumed == false {
                stdinWriteSource.resume()
            }
            stdinWriteSource.cancel()
            self.stdinWriteSource = nil
            isWriteSourceResumed = true
        } else {
            closeStdinHandle()
        }

        if let process, process.isRunning {
            process.terminate()
        }
        process?.terminationHandler = nil
        process = nil
        outputBuffer.removeAll()
        processExitStatus = nil

        completions.forEach { $0?(writeError) }

        if notify {
            onClose(reason)
        }
    }

    private func failPendingWrites(_ error: Error) {
        let completions = pendingWrites.map(\.completion)
        pendingWrites.removeAll()
        queuedWriteBytes = 0
        completions.forEach { $0?(error) }
    }

    private func closeHandlesAfterLaunchFailure() {
        if let stdoutReadSource {
            stdoutReadSource.resume()
            stdoutReadSource.cancel()
            self.stdoutReadSource = nil
        } else {
            closeStdoutHandle()
        }

        if let stderrReadSource {
            stderrReadSource.resume()
            stderrReadSource.cancel()
            self.stderrReadSource = nil
        } else {
            closeStderrHandle()
        }

        if let stdinWriteSource {
            stdinWriteSource.resume()
            stdinWriteSource.cancel()
            self.stdinWriteSource = nil
            isWriteSourceResumed = true
        } else {
            closeStdinHandle()
        }

        process = nil
    }

    private func closeStdinHandle() {
        try? stdinHandle?.close()
        stdinHandle = nil
    }

    private func closeStdoutHandle() {
        try? stdoutHandle?.close()
        stdoutHandle = nil
    }

    private func closeStderrHandle() {
        try? stderrHandle?.close()
        stderrHandle = nil
    }

    private static func frame(for message: Any) throws -> Data {
        let jsonData = try JSONSerialization.data(withJSONObject: message)
        guard jsonData.count <= Int(UInt32.max) else {
            throw error(
                code: 9,
                message: "Native message exceeds maximum encodable size"
            )
        }

        var length = UInt32(jsonData.count)
        var frame = Data(bytes: &length, count: 4)
        frame.append(jsonData)
        return frame
    }

    private static func decodeLength(from data: Data) -> UInt32 {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBufferPointer { pointer in
            data.copyBytes(to: pointer, from: 0..<4)
        }
        return bytes.withUnsafeBufferPointer { pointer in
            var value: UInt32 = 0
            memcpy(&value, pointer.baseAddress, 4)
            return value
        }
    }

    private static func setNonBlocking(_ fileDescriptor: Int32) throws {
        let flags = fcntl(fileDescriptor, F_GETFL)
        guard flags >= 0 else {
            throw posixError(message: "Native messaging pipe configuration failed")
        }

        guard fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw posixError(message: "Native messaging pipe configuration failed")
        }
    }

    private static func closeReasonError(_ reason: CloseReason) -> Error {
        switch reason {
        case .cancelled:
            return CancellationError()
        case .endOfFile:
            return error(
                code: 2,
                message: "Native host closed without sending a response"
            )
        case .processExited:
            return error(
                code: 2,
                message: "Native host closed without sending a response"
            )
        case .error(let error):
            return error
        }
    }

    private static func posixError(message: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [
                NSLocalizedDescriptionKey: "\(message): \(String(cString: strerror(errno)))",
            ]
        )
    }

    private static func error(code: Int, message: String) -> NSError {
        NSError(
            domain: "NativeMessaging",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

@available(macOS 15.5, *)
private final class NativeMessagingProcessTerminationObserver: @unchecked Sendable {
    // Process invokes terminationHandler as @Sendable; this observer is sendable
    // because it only schedules session access back onto the session's state queue.
    private let stateQueue: DispatchQueue
    private weak var session: NativeMessagingProcessSession?

    init(
        stateQueue: DispatchQueue,
        session: NativeMessagingProcessSession
    ) {
        self.stateQueue = stateQueue
        self.session = session
    }

    func processDidTerminate(status: Int32) {
        stateQueue.async { [weak self] in
            self?.session?.handleProcessExit(status: status)
        }
    }
}

@available(macOS 15.5, *)
@MainActor
private final class NativeMessagingSingleShotCompletion {
    private var completion: ((Any?, Error?) -> Void)?

    init(_ completion: @escaping (Any?, Error?) -> Void) {
        self.completion = completion
    }

    func complete(response: Any?, error: Error?) {
        guard let completion else { return }
        self.completion = nil
        completion(response, error)
    }
}

@available(macOS 15.5, *)
@MainActor
final class NativeMessagingHandler: NSObject {
    private static let logger = Logger.sumi(category: "NativeMessaging")
    private static let missingHostBackoff: TimeInterval = 5
    private static let negativeManifestCacheLimit = 128
    private static let negativeManifestCacheLock = NSLock()
    nonisolated(unsafe) private static var negativeManifestCache: [String: Date] = [:]

    private let applicationId: String
    private let browserSupportDirectory: URL
    private let appBundleURL: URL
    private let responseTimeout: TimeInterval

    private var session: NativeMessagingProcessSession?
    private weak var port: WKWebExtension.MessagePort?
    private var onDisconnect: (() -> Void)?

    init(
        applicationId: String,
        browserSupportDirectory: URL,
        appBundleURL: URL,
        responseTimeout: TimeInterval = 5
    ) {
        self.applicationId = applicationId
        self.browserSupportDirectory = browserSupportDirectory
        self.appBundleURL = appBundleURL
        self.responseTimeout = responseTimeout
        super.init()
    }

    static func manifestSearchURLs(
        applicationId: String,
        browserSupportDirectory: URL,
        appBundleURL: URL
    ) -> [URL] {
        let manifestName = "\(applicationId).json"
        return [
            browserSupportDirectory
                .appendingPathComponent("NativeMessagingHosts", isDirectory: true)
                .appendingPathComponent(manifestName),
            appBundleURL
                .appendingPathComponent("Contents/Resources/NativeMessagingHosts", isDirectory: true)
                .appendingPathComponent(manifestName),
        ]
    }

    static func resolveManifestURL(
        applicationId: String,
        browserSupportDirectory: URL,
        appBundleURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        guard isNegativeManifestCacheEntryActive(applicationId) == false else {
            return nil
        }

        let manifestURL = manifestSearchURLs(
            applicationId: applicationId,
            browserSupportDirectory: browserSupportDirectory,
            appBundleURL: appBundleURL
        ).first(where: { fileManager.fileExists(atPath: $0.path) })

        if manifestURL == nil {
            insertNegativeManifestCacheEntry(applicationId)
        }

        return manifestURL
    }

    private static func isNegativeManifestCacheEntryActive(
        _ applicationId: String,
        now: Date = Date()
    ) -> Bool {
        negativeManifestCacheLock.lock()
        defer { negativeManifestCacheLock.unlock() }

        guard let cachedAt = negativeManifestCache[applicationId] else {
            return false
        }

        if now.timeIntervalSince(cachedAt) > missingHostBackoff {
            negativeManifestCache.removeValue(forKey: applicationId)
            return false
        }

        return true
    }

    private static func insertNegativeManifestCacheEntry(
        _ applicationId: String,
        now: Date = Date()
    ) {
        negativeManifestCacheLock.lock()
        defer { negativeManifestCacheLock.unlock() }

        negativeManifestCache = negativeManifestCache.filter {
            now.timeIntervalSince($0.value) <= missingHostBackoff
        }
        negativeManifestCache[applicationId] = now

        if negativeManifestCache.count > negativeManifestCacheLimit {
            let overflow = negativeManifestCache.count - negativeManifestCacheLimit
            let keysToRemove = negativeManifestCache
                .sorted { $0.value < $1.value }
                .prefix(overflow)
                .map(\.key)
            keysToRemove.forEach { negativeManifestCache.removeValue(forKey: $0) }
        }
    }

    func sendMessage(
        _ message: Any,
        completion: @escaping (Any?, Error?) -> Void
    ) {
        let singleShotCompletion = NativeMessagingSingleShotCompletion(completion)

        do {
            let manifest = try loadManifest()
            weak var sessionReference: NativeMessagingProcessSession?
            let session = NativeMessagingProcessSession(
                manifest: manifest,
                closeOnMalformedMessage: true,
                onMessage: { [weak self] responsePayload in
                    self?.completeSingleShot(
                        sessionID: sessionReference.map(ObjectIdentifier.init),
                        responsePayload: responsePayload,
                        error: nil,
                        completion: singleShotCompletion
                    )
                },
                onClose: { [weak self] reason in
                    self?.completeSingleShot(
                        sessionID: sessionReference.map(ObjectIdentifier.init),
                        responsePayload: nil,
                        error: Self.error(from: reason),
                        completion: singleShotCompletion
                    )
                }
            )
            sessionReference = session
            self.session = session
            let sessionID = ObjectIdentifier(session)

            session.start { [weak self] result in
                DispatchQueue.main.async {
                    guard let self,
                          let session = self.session,
                          ObjectIdentifier(session) == sessionID
                    else {
                        return
                    }

                    switch result {
                    case .failure(let error):
                        Self.logger.warning("Native messaging send failed: \(error.localizedDescription, privacy: .public). Delaying failure to prevent extension retry loops.")
                        DispatchQueue.main.asyncAfter(deadline: .now() + Self.missingHostBackoff) { [weak self] in
                            guard let self,
                                  let currentSession = self.session,
                                  ObjectIdentifier(currentSession) == sessionID
                            else {
                                return
                            }
                            self.session = nil
                            singleShotCompletion.complete(response: nil, error: error)
                        }
                    case .success:
                        self.startResponseTimeout(
                            for: session,
                            completion: singleShotCompletion
                        )
                        session.send(message) { [weak self, weak session] error in
                            guard let error else { return }
                            self?.completeSingleShot(
                                sessionID: session.map(ObjectIdentifier.init),
                                responsePayload: nil,
                                error: error,
                                completion: singleShotCompletion
                            )
                        }
                    }
                }
            }
        } catch {
            Self.logger.warning("Native messaging send failed: \(error.localizedDescription, privacy: .public). Delaying failure to prevent extension retry loops.")
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.missingHostBackoff) {
                singleShotCompletion.complete(response: nil, error: error)
            }
        }
    }

    func connect(
        port: WKWebExtension.MessagePort,
        onDisconnect: @escaping () -> Void
    ) {
        self.port = port
        self.onDisconnect = onDisconnect

        do {
            let manifest = try loadManifest()
            let session = NativeMessagingProcessSession(
                manifest: manifest,
                closeOnMalformedMessage: false,
                onMessage: { [weak self] payload in
                    DispatchQueue.main.async {
                        guard let object = Self.decodeMessagePayload(payload) else {
                            return
                        }
                        self?.port?.sendMessage(object) { _ in }
                    }
                },
                onClose: { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.finishConnection(disconnectPort: true)
                    }
                }
            )
            self.session = session
            let sessionID = ObjectIdentifier(session)

            port.messageHandler = { [weak self] _, message in
                guard let message else { return }
                self?.session?.send(message) { error in
                    if let error {
                        Self.logger.error("Failed to send message to native host: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }

            port.disconnectHandler = { [weak self] _ in
                self?.disconnect()
            }

            session.start { [weak self, weak port] result in
                DispatchQueue.main.async {
                    guard let self,
                          let currentSession = self.session,
                          ObjectIdentifier(currentSession) == sessionID
                    else {
                        return
                    }

                    if case .failure(let error) = result {
                        Self.logger.warning("Native messaging connection failed: \(error.localizedDescription, privacy: .public). Delaying disconnect to prevent extension retry loops.")
                        DispatchQueue.main.asyncAfter(deadline: .now() + Self.missingHostBackoff) { [weak self, weak port] in
                            guard let self,
                                  let currentSession = self.session,
                                  ObjectIdentifier(currentSession) == sessionID
                            else {
                                return
                            }
                            port?.disconnect()
                            self.finishConnection(disconnectPort: false)
                        }
                    }
                }
            }
        } catch {
            Self.logger.warning("Native messaging connection failed: \(error.localizedDescription, privacy: .public). Delaying disconnect to prevent extension retry loops.")
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.missingHostBackoff) { [weak self, weak port] in
                port?.disconnect()
                self?.finishConnection(disconnectPort: false)
            }
        }
    }

    func disconnect() {
        finishConnection(disconnectPort: false)
    }

    private func startResponseTimeout(
        for session: NativeMessagingProcessSession,
        completion: NativeMessagingSingleShotCompletion
    ) {
        let sessionID = ObjectIdentifier(session)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + responseTimeout) { [weak self] in
            Task { @MainActor [weak self] in
                self?.completeSingleShot(
                    sessionID: sessionID,
                    responsePayload: nil,
                    error: NSError(
                        domain: "NativeMessaging",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Native host response timed out"]
                    ),
                    completion: completion
                )
            }
        }
    }

    private func completeSingleShot(
        sessionID: ObjectIdentifier?,
        responsePayload: Data?,
        error: Error?,
        completion: NativeMessagingSingleShotCompletion
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let sessionID,
                  let currentSession = self.session,
                  ObjectIdentifier(currentSession) == sessionID
            else {
                return
            }

            self.session = nil
            currentSession.cancel(notify: false)
            let response = responsePayload.flatMap(Self.decodeMessagePayload)
            completion.complete(response: response, error: error)
        }
    }

    private func finishConnection(disconnectPort: Bool) {
        let session = self.session
        self.session = nil
        session?.cancel(notify: false)

        let port = self.port
        self.port = nil

        let onDisconnect = self.onDisconnect
        self.onDisconnect = nil

        if disconnectPort {
            port?.disconnect()
        }
        onDisconnect?()
    }

    private func loadManifest() throws -> NativeMessagingHostManifest {
        guard let url = Self.resolveManifestURL(
            applicationId: applicationId,
            browserSupportDirectory: browserSupportDirectory,
            appBundleURL: appBundleURL
        ) else {
            throw NSError(
                domain: "NativeMessaging",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Sumi could not find a native messaging host manifest for \(applicationId)"]
            )
        }

        let object = try ExtensionUtils.loadJSONObject(at: url)
        if let manifest = NativeMessagingHostManifest(jsonObject: object) {
            return manifest
        }

        throw NSError(
            domain: "NativeMessaging",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Sumi found an invalid native messaging host manifest for \(applicationId)"]
        )
    }

    private static func error(
        from reason: NativeMessagingProcessSession.CloseReason
    ) -> Error {
        switch reason {
        case .cancelled:
            return CancellationError()
        case .endOfFile:
            return NSError(
                domain: "NativeMessaging",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Native host closed without sending a response"]
            )
        case .processExited:
            return NSError(
                domain: "NativeMessaging",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Native host closed without sending a response"]
            )
        case .error(let error):
            return error
        }
    }

    private static func decodeMessagePayload(_ payload: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: payload)
    }
}
