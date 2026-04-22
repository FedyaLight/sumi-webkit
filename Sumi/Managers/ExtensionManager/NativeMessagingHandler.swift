//
//  NativeMessagingHandler.swift
//  Sumi
//
//  Native messaging host lookup and process bridge for Sumi's WebExtension runtime.
//

import Foundation
import OSLog
import WebKit

@available(macOS 15.5, *)
private struct NativeMessagingHostManifest {
    let path: String

    init?(jsonObject: [String: Any]) {
        guard let path = jsonObject["path"] as? String, path.isEmpty == false else {
            return nil
        }
        self.path = path
    }
}

@available(macOS 15.5, *)
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

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private weak var port: WKWebExtension.MessagePort?
    private var outputBuffer = Data()
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
        launchProcess { [weak self] result in
            guard let self else { return }

            switch result {
            case .failure(let error):
                Self.logger.warning("Native messaging send failed: \(error.localizedDescription, privacy: .public). Delaying failure to prevent extension retry loops.")
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.missingHostBackoff) {
                    completion(nil, error)
                }
            case .success:
                do {
                    self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                    try self.writeMessage(message)
                } catch {
                    self.terminate()
                    completion(nil, error)
                    return
                }

                let responseHandle = self.outputPipe?.fileHandleForReading
                DispatchQueue.global(qos: .userInitiated).async {
                    var response: Any?
                    var readError: Error?
                    let semaphore = DispatchSemaphore(value: 0)

                    DispatchQueue.global(qos: .userInitiated).async {
                        defer { semaphore.signal() }

                        guard let responseHandle else {
                            readError = NSError(
                                domain: "NativeMessaging",
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Native host output pipe is unavailable"]
                            )
                            return
                        }

                        do {
                            let lengthData = responseHandle.readData(ofLength: 4)
                            guard lengthData.count == 4 else {
                                throw NSError(
                                    domain: "NativeMessaging",
                                    code: 2,
                                    userInfo: [NSLocalizedDescriptionKey: "Native host closed without sending a response"]
                                )
                            }

                            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }
                            let payloadData = responseHandle.readData(ofLength: Int(length))
                            guard payloadData.count == Int(length) else {
                                throw NSError(
                                    domain: "NativeMessaging",
                                    code: 3,
                                    userInfo: [NSLocalizedDescriptionKey: "Native host sent a truncated response"]
                                )
                            }

                            response = try JSONSerialization.jsonObject(with: payloadData)
                        } catch {
                            readError = error
                        }
                    }

                    let waitResult = semaphore.wait(timeout: .now() + self.responseTimeout)
                    DispatchQueue.main.async {
                        self.terminate()

                        if waitResult == .timedOut {
                            completion(nil, NSError(
                                domain: "NativeMessaging",
                                code: 4,
                                userInfo: [NSLocalizedDescriptionKey: "Native host response timed out"]
                            ))
                        } else if let readError {
                            completion(nil, readError)
                        } else {
                            completion(response, nil)
                        }
                    }
                }
            }
        }
    }

    func connect(
        port: WKWebExtension.MessagePort,
        onDisconnect: @escaping () -> Void
    ) {
        self.port = port
        self.onDisconnect = onDisconnect

        port.messageHandler = { [weak self] _, message in
            guard let message else { return }
            do {
                try self?.writeMessage(message)
            } catch {
                Self.logger.error("Failed to send message to native host: \(error.localizedDescription, privacy: .public)")
            }
        }

        port.disconnectHandler = { [weak self] _ in
            self?.terminate()
        }

        launchProcess { [weak self] result in
            guard let self else { return }

            switch result {
            case .failure(let error):
                Self.logger.warning("Native messaging connection failed: \(error.localizedDescription, privacy: .public). Delaying disconnect to prevent extension retry loops.")
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.missingHostBackoff) { [weak port, weak self] in
                    port?.disconnect()
                    self?.terminate()
                }
            case .success:
                self.outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
                    let data = handle.availableData
                    guard data.isEmpty == false else {
                        self?.terminate()
                        return
                    }
                    self?.handleOutput(data)
                }
            }
        }
    }

    func disconnect() {
        terminate()
    }

    private func launchProcess(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            let manifest = try loadManifest()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: manifest.path)

            let input = Pipe()
            let output = Pipe()
            let error = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = error

            self.process = process
            self.inputPipe = input
            self.outputPipe = output

            try process.run()
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
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

    private func writeMessage(_ message: Any) throws {
        guard let inputPipe else {
            throw NSError(
                domain: "NativeMessaging",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Native host input pipe is unavailable"]
            )
        }

        let jsonData = try JSONSerialization.data(withJSONObject: message)
        var length = UInt32(jsonData.count)
        let lengthData = Data(bytes: &length, count: 4)
        try inputPipe.fileHandleForWriting.write(contentsOf: lengthData)
        try inputPipe.fileHandleForWriting.write(contentsOf: jsonData)
    }

    private func handleOutput(_ data: Data) {
        outputBuffer.append(data)

        while outputBuffer.count >= 4 {
            let length = outputBuffer.withUnsafeBytes { $0.load(as: UInt32.self) }
            let totalLength = 4 + Int(length)
            guard outputBuffer.count >= totalLength else { break }

            let payload = outputBuffer.subdata(in: 4..<totalLength)
            outputBuffer.removeSubrange(0..<totalLength)

            if let object = try? JSONSerialization.jsonObject(with: payload) {
                port?.sendMessage(object) { _ in }
            }
        }
    }

    private func terminate() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        inputPipe = nil
        outputPipe = nil
        onDisconnect?()
        onDisconnect = nil
    }
}
