import Foundation
import XCTest
@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class NativeMessagingHandlerTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testValidResponseIsDecodedAsBeforeAndReadAsynchronously() async throws {
        let supportRoot = try temporaryDirectory()
        let applicationId = uniqueApplicationId("valid")
        let hostPath = try makeNativeHostScript(
            in: supportRoot,
            name: "valid-host.sh",
            body: Self.nativeHostPrelude + """

            message = read_message()
            write_message({"ok": True, "ping": message.get("ping")})
            """
        )
        try writeNativeMessagingManifest(
            in: supportRoot,
            applicationId: applicationId,
            hostPath: hostPath
        )

        let handler = NativeMessagingHandler(
            applicationId: applicationId,
            browserSupportDirectory: supportRoot,
            appBundleURL: Bundle.main.bundleURL,
            responseTimeout: 1
        )

        let result = await sendNativeMessage(["ping": true], with: handler)
        let response = try XCTUnwrap(try result.get() as? [String: Any])
        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertEqual(response["ping"] as? Bool, true)
    }

    func testNativeMessagingConnectDoesNotBlockMainActorForSlowHost() async throws {
        let supportRoot = try temporaryDirectory()
        let applicationId = uniqueApplicationId("slow")
        let hostPath = try makeNativeHostScript(
            in: supportRoot,
            name: "slow-host.sh",
            body: Self.nativeHostPrelude + """

            message = read_message()
            time.sleep(0.35)
            write_message({"ok": True})
            """
        )
        try writeNativeMessagingManifest(
            in: supportRoot,
            applicationId: applicationId,
            hostPath: hostPath
        )

        let handler = NativeMessagingHandler(
            applicationId: applicationId,
            browserSupportDirectory: supportRoot,
            appBundleURL: Bundle.main.bundleURL,
            responseTimeout: 1
        )

        var completed = false
        let startedAt = Date()
        let result: Result<Any?, Error> = await withCheckedContinuation { continuation in
            handler.sendMessage(["ping": true]) { response, error in
                completed = true
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(response))
                }
            }

            XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.1)
            XCTAssertFalse(completed)
        }

        XCTAssertNotNil(try result.get())
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(startedAt), 0.3)
    }

    func testWriteSerializationPreservesMessageOrder() async throws {
        let supportRoot = try temporaryDirectory()
        let applicationId = uniqueApplicationId("ordered")
        let hostPath = try makeNativeHostScript(
            in: supportRoot,
            name: "ordered-host.sh",
            body: Self.nativeHostPrelude + """

            seen = []
            for _ in range(3):
                message = read_message()
                if message is None:
                    break
                seen.append(message.get("index"))
                write_message({"index": message.get("index"), "seen": seen[:]})
            time.sleep(0.1)
            """
        )
        try writeNativeMessagingManifest(
            in: supportRoot,
            applicationId: applicationId,
            hostPath: hostPath
        )

        let handler = NativeMessagingHandler(
            applicationId: applicationId,
            browserSupportDirectory: supportRoot,
            appBundleURL: Bundle.main.bundleURL,
            responseTimeout: 1
        )

        var received: [[String: Any]] = []
        try await debugConnect(handler) { message in
            if let message = message as? [String: Any] {
                received.append(message)
            }
        }

        for index in 1...3 {
            let error = await debugPost(["index": index], with: handler)
            XCTAssertNil(error)
        }

        try await waitUntil(timeout: 2) {
            received.count == 3
        }

        XCTAssertEqual(received.compactMap { $0["index"] as? Int }, [1, 2, 3])
        let seen = (received.last?["seen"] as? [Any])?
            .compactMap { ($0 as? NSNumber)?.intValue }
        XCTAssertEqual(seen, [1, 2, 3])
        handler.disconnect()
    }

    func testProcessExitCancelsReadAndWriteTasksCleanly() async throws {
        let supportRoot = try temporaryDirectory()
        let applicationId = uniqueApplicationId("exit")
        let hostPath = try makeNativeHostScript(
            in: supportRoot,
            name: "exit-host.sh",
            body: """
            import sys
            sys.exit(0)
            """
        )
        try writeNativeMessagingManifest(
            in: supportRoot,
            applicationId: applicationId,
            hostPath: hostPath
        )

        let handler = NativeMessagingHandler(
            applicationId: applicationId,
            browserSupportDirectory: supportRoot,
            appBundleURL: Bundle.main.bundleURL,
            responseTimeout: 1
        )

        let startedAt = Date()
        let result = await sendNativeMessage(["ping": true], with: handler)
        if case .success = result {
            XCTFail("Process exit before a response should fail")
        }
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
    }

    func testDisconnectCancelsTasksAndTerminatesProcess() async throws {
        let supportRoot = try temporaryDirectory()
        let applicationId = uniqueApplicationId("disconnect")
        let markerURL = supportRoot.appendingPathComponent("terminated.txt")
        let readyURL = supportRoot.appendingPathComponent("ready.txt")
        let markerPath = Self.pythonStringLiteral(markerURL.path)
        let readyPath = Self.pythonStringLiteral(readyURL.path)
        let hostPath = try makeNativeHostScript(
            in: supportRoot,
            name: "disconnect-host.sh",
            body: """
            import signal
            import sys
            import time

            marker_path = \(markerPath)
            ready_path = \(readyPath)

            def terminate(sig, frame):
                with open(marker_path, "w") as marker:
                    marker.write("terminated")
                sys.exit(0)

            signal.signal(signal.SIGTERM, terminate)
            with open(ready_path, "w") as ready:
                ready.write("ready")
            while True:
                time.sleep(1)
            """
        )
        try writeNativeMessagingManifest(
            in: supportRoot,
            applicationId: applicationId,
            hostPath: hostPath
        )

        let handler = NativeMessagingHandler(
            applicationId: applicationId,
            browserSupportDirectory: supportRoot,
            appBundleURL: Bundle.main.bundleURL,
            responseTimeout: 1
        )

        var didDisconnect = false
        try await debugConnect(handler, onDisconnect: {
            didDisconnect = true
        }, onMessage: { _ in })

        try await waitUntil(timeout: 2) {
            FileManager.default.fileExists(atPath: readyURL.path)
        }

        handler.disconnect()
        try await waitUntil(timeout: 2) {
            didDisconnect && FileManager.default.fileExists(atPath: markerURL.path)
        }
    }

    func testBrokenPipeOrEOFIsHandledWithoutHanging() async throws {
        let supportRoot = try temporaryDirectory()
        let applicationId = uniqueApplicationId("eof")
        let hostPath = try makeNativeHostScript(
            in: supportRoot,
            name: "eof-host.sh",
            body: """
            import sys
            sys.exit(0)
            """
        )
        try writeNativeMessagingManifest(
            in: supportRoot,
            applicationId: applicationId,
            hostPath: hostPath
        )

        let handler = NativeMessagingHandler(
            applicationId: applicationId,
            browserSupportDirectory: supportRoot,
            appBundleURL: Bundle.main.bundleURL,
            responseTimeout: 1
        )

        let result = await sendNativeMessage(
            ["payload": String(repeating: "x", count: 2 * 1024 * 1024)],
            with: handler
        )

        if case .success = result {
            XCTFail("EOF or broken pipe should fail")
        }
    }

    func testTimeoutBehaviorStillWorksWithoutBlockingThread() async throws {
        let supportRoot = try temporaryDirectory()
        let applicationId = uniqueApplicationId("timeout")
        let hostPath = try makeNativeHostScript(
            in: supportRoot,
            name: "timeout-host.sh",
            body: Self.nativeHostPrelude + """

            _ = read_message()
            time.sleep(5)
            """
        )
        try writeNativeMessagingManifest(
            in: supportRoot,
            applicationId: applicationId,
            hostPath: hostPath
        )

        let handler = NativeMessagingHandler(
            applicationId: applicationId,
            browserSupportDirectory: supportRoot,
            appBundleURL: Bundle.main.bundleURL,
            responseTimeout: 0.2
        )

        let result = await sendNativeMessage(["ping": true], with: handler)
        switch result {
        case .success:
            XCTFail("Timed out native host should not succeed")
        case .failure(let error):
            XCTAssertTrue(error.localizedDescription.contains("timed out"))
        }
    }

    func testMalformedResponseIsRejectedAsBefore() async throws {
        let supportRoot = try temporaryDirectory()
        let applicationId = uniqueApplicationId("malformed")
        let hostPath = try makeNativeHostScript(
            in: supportRoot,
            name: "malformed-host.sh",
            body: Self.nativeHostPrelude + """

            _ = read_message()
            payload = b"not-json"
            sys.stdout.buffer.write(struct.pack("I", len(payload)))
            sys.stdout.buffer.write(payload)
            sys.stdout.buffer.flush()
            """
        )
        try writeNativeMessagingManifest(
            in: supportRoot,
            applicationId: applicationId,
            hostPath: hostPath
        )

        let handler = NativeMessagingHandler(
            applicationId: applicationId,
            browserSupportDirectory: supportRoot,
            appBundleURL: Bundle.main.bundleURL,
            responseTimeout: 1
        )

        let result = await sendNativeMessage(["ping": true], with: handler)
        if case .success = result {
            XCTFail("Malformed native host response should fail")
        }
    }

    func testOversizedResponseIsRejected() async throws {
        let supportRoot = try temporaryDirectory()
        let applicationId = uniqueApplicationId("oversized")
        let hostPath = try makeNativeHostScript(
            in: supportRoot,
            name: "oversized-host.sh",
            body: Self.nativeHostPrelude + """

            _ = read_message()
            sys.stdout.buffer.write(struct.pack("I", 1048577))
            sys.stdout.buffer.flush()
            time.sleep(5)
            """
        )
        try writeNativeMessagingManifest(
            in: supportRoot,
            applicationId: applicationId,
            hostPath: hostPath
        )

        let handler = NativeMessagingHandler(
            applicationId: applicationId,
            browserSupportDirectory: supportRoot,
            appBundleURL: Bundle.main.bundleURL,
            responseTimeout: 1
        )

        let result = await sendNativeMessage(["ping": true], with: handler)
        switch result {
        case .success:
            XCTFail("Oversized native host response should fail")
        case .failure(let error):
            XCTAssertTrue(error.localizedDescription.contains("maximum size"))
        }
    }

    func testProductionNativeMessagingIOUsesNonBlockingSources() throws {
        let source = try Self.source(named: "Sumi/Managers/ExtensionManager/NativeMessagingHandler.swift")

        XCTAssertTrue(source.contains("DispatchSource.makeReadSource"))
        XCTAssertTrue(source.contains("DispatchSource.makeWriteSource"))
        XCTAssertFalse(source.contains("readDataToEndOfFile"))
        XCTAssertFalse(source.contains("readData(ofLength"))
        XCTAssertFalse(source.contains("waitUntilExit"))
        XCTAssertFalse(source.contains("DispatchSemaphore"))
        XCTAssertFalse(source.contains("availableData"))
        XCTAssertFalse(source.contains(".write(contentsOf"))
    }

    func testDisabledExtensionPathsDoNotReachNativeMessagingRuntime() throws {
        let guardedSources = [
            "Sumi/Managers/BrowserManager/BrowserManager.swift",
            "Sumi/Managers/BrowserManager/BrowserManager+DialogsUtilities.swift",
            "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift",
            "Sumi/Components/Settings/SettingsView.swift",
            "Sumi/Components/Settings/SumiSettingsModuleToggles.swift",
            "Sumi/Components/Extensions/ExtensionActionView.swift",
            "Navigation/Sidebar/SidebarHeader.swift",
            "Sumi/Models/BrowserConfig/BrowserConfig.swift",
            "Sumi/Models/Tab/Tab+WebViewRuntime.swift",
        ]

        for relativePath in guardedSources {
            let source = try Self.source(named: relativePath)
            XCTAssertFalse(source.contains("NativeMessagingHandler("), relativePath)
            XCTAssertFalse(source.contains("NativeMessagingProcessSession"), relativePath)
            XCTAssertFalse(source.contains("resolveManifestURL("), relativePath)
            XCTAssertFalse(source.contains("Process()"), relativePath)
            XCTAssertFalse(source.contains("Pipe()"), relativePath)
            XCTAssertFalse(source.contains("DispatchSource.makeReadSource"), relativePath)
            XCTAssertFalse(source.contains("DispatchSource.makeWriteSource"), relativePath)
        }
    }

    private func sendNativeMessage(
        _ message: Any,
        with handler: NativeMessagingHandler
    ) async -> Result<Any?, Error> {
        await withCheckedContinuation { continuation in
            handler.sendMessage(message) { response, error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(response))
                }
            }
        }
    }

    private func debugConnect(
        _ handler: NativeMessagingHandler,
        onDisconnect: (() -> Void)? = nil,
        onMessage: @escaping (Any) -> Void
    ) async throws {
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            handler.debugConnectForTesting(
                onReady: { error in
                    if let error {
                        continuation.resume(returning: .failure(error))
                    } else {
                        continuation.resume(returning: .success(()))
                    }
                },
                onMessage: onMessage,
                onDisconnect: {
                    onDisconnect?()
                }
            )
        }
        try result.get()
    }

    private func debugPost(
        _ message: Any,
        with handler: NativeMessagingHandler
    ) async -> Error? {
        await withCheckedContinuation { continuation in
            handler.debugPostMessageForTesting(message) { error in
                continuation.resume(returning: error)
            }
        }
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while condition() == false {
            if Date() >= deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiNativeMessagingHandlerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(url)
        return url
    }

    private func makeNativeHostScript(
        in rootURL: URL,
        name: String,
        body: String
    ) throws -> String {
        let scriptURL = rootURL.appendingPathComponent(name)
        let script = """
        #!/usr/bin/python3
        \(body)
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL.path
    }

    private func writeNativeMessagingManifest(
        in supportRoot: URL,
        applicationId: String,
        hostPath: String
    ) throws {
        let manifestDirectory = supportRoot.appendingPathComponent(
            "NativeMessagingHosts",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: manifestDirectory,
            withIntermediateDirectories: true
        )
        let manifestURL = manifestDirectory.appendingPathComponent("\(applicationId).json")
        try ExtensionUtils.writeJSONObject(
            ["path": hostPath],
            to: manifestURL
        )
    }

    private func uniqueApplicationId(_ suffix: String) -> String {
        "com.sumi.tests.native.\(suffix).\(UUID().uuidString.lowercased())"
    }

    private static let nativeHostPrelude = """
    import json
    import struct
    import sys
    import time

    def read_message():
        length = sys.stdin.buffer.read(4)
        if len(length) != 4:
            return None
        size = struct.unpack("I", length)[0]
        payload = sys.stdin.buffer.read(size)
        if len(payload) != size:
            return None
        return json.loads(payload.decode("utf-8"))

    def write_message(message):
        payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
        sys.stdout.buffer.write(struct.pack("I", len(payload)))
        sys.stdout.buffer.write(payload)
        sys.stdout.buffer.flush()
    """

    private static func pythonStringLiteral(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func source(named relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
