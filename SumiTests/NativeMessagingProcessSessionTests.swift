import XCTest

@testable import Sumi

@available(macOS 15.5, *)
final class NativeMessagingProcessSessionTests: XCTestCase {
    private static let processTimeout: TimeInterval = 5
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testStartFailureCompletesWithErrorAndReleasesSession() throws {
        let missingExecutable = try makeTemporaryDirectory()
            .appendingPathComponent("missing-native-host")
        let completion = expectation(description: "start completion")
        var startResult: Result<Void, Error>?
        weak var weakSession: NativeMessagingProcessSession?

        autoreleasepool {
            var session: NativeMessagingProcessSession? = makeSession(
                hostURL: missingExecutable
            )
            weakSession = session

            session?.start { result in
                startResult = result
                completion.fulfill()
            }

            wait(for: [completion], timeout: Self.processTimeout)
            session = nil
        }

        guard case .failure = try XCTUnwrap(startResult) else {
            return XCTFail("Expected missing executable launch to fail")
        }
        XCTAssertNil(weakSession)
    }

    func testSendWritesValidPayloadAndReceivesResponse() throws {
        let hostURL = try makePythonHost(
            body: """
            header = sys.stdin.buffer.read(4)
            if len(header) != 4:
                sys.exit(2)
            length = struct.unpack("<I", header)[0]
            payload = sys.stdin.buffer.read(length)
            request = json.loads(payload.decode("utf-8"))
            response = json.dumps(
                {"ok": True, "request": request},
                separators=(",", ":")
            ).encode("utf-8")
            sys.stdout.buffer.write(struct.pack("<I", len(response)) + response)
            sys.stdout.buffer.flush()
            time.sleep(0.05)
            """
        )
        let message = expectation(description: "message")
        let write = expectation(description: "write completion")
        var writeError: Error?
        var responsePayload: Data?
        let session = makeSession(
            hostURL: hostURL,
            onMessage: { payload in
                responsePayload = payload
                message.fulfill()
            }
        )
        defer { session.cancel(notify: false) }

        try start(session)
        session.send(["ping": true]) { error in
            writeError = error
            write.fulfill()
        }

        wait(for: [write, message], timeout: Self.processTimeout)

        XCTAssertNil(writeError)
        let payload = try XCTUnwrap(responsePayload)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )
        XCTAssertEqual(object["ok"] as? Bool, true)
        XCTAssertEqual((object["request"] as? [String: Any])?["ping"] as? Bool, true)
    }

    func testCancelFailsPendingWriteOnceAndClosesOnce() throws {
        let hostURL = try makePythonHost(body: "time.sleep(2)")
        let write = expectation(description: "write completion")
        let close = expectation(description: "close")
        close.expectedFulfillmentCount = 1
        close.assertForOverFulfill = true
        var writeErrors: [Error?] = []
        var closeReasons: [NativeMessagingProcessSession.CloseReason] = []
        let session = makeSession(
            hostURL: hostURL,
            onClose: { reason in
                closeReasons.append(reason)
                close.fulfill()
            }
        )

        try start(session)
        session.send(["payload": String(repeating: "x", count: 1_000_000)]) { error in
            writeErrors.append(error)
            write.fulfill()
        }
        session.cancel()
        session.cancel()

        wait(for: [write, close], timeout: Self.processTimeout)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(writeErrors.count, 1)
        XCTAssertTrue(writeErrors[0] is CancellationError)
        XCTAssertEqual(closeReasons.count, 1)
        guard case .cancelled = closeReasons[0] else {
            return XCTFail("Expected cancellation close reason")
        }
    }

    func testProcessExitClosesSessionOnce() throws {
        let hostURL = try makePythonHost(body: "sys.exit(0)")
        let close = expectation(description: "close")
        close.expectedFulfillmentCount = 1
        close.assertForOverFulfill = true
        var closeReasons: [NativeMessagingProcessSession.CloseReason] = []
        let session = makeSession(
            hostURL: hostURL,
            onClose: { reason in
                closeReasons.append(reason)
                close.fulfill()
            }
        )

        try start(session)

        wait(for: [close], timeout: Self.processTimeout)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(closeReasons.count, 1)
        switch closeReasons[0] {
        case .endOfFile, .processExited:
            break
        default:
            XCTFail("Expected EOF or process-exited close reason")
        }
    }

    func testTruncatedResponseClosesWithNativeMessagingError() throws {
        let hostURL = try makePythonHost(
            body: """
            sys.stdout.buffer.write(struct.pack("<I", 8) + b"{")
            sys.stdout.buffer.flush()
            """
        )
        let close = expectation(description: "close")
        var closeReason: NativeMessagingProcessSession.CloseReason?
        let session = makeSession(
            hostURL: hostURL,
            onClose: { reason in
                closeReason = reason
                close.fulfill()
            }
        )

        try start(session)

        wait(for: [close], timeout: Self.processTimeout)

        let error = try XCTUnwrap(error(from: closeReason))
        XCTAssertEqual((error as NSError).domain, "NativeMessaging")
        XCTAssertEqual((error as NSError).code, 3)
    }

    func testMalformedResponseClosesWhenPolicyRequiresIt() throws {
        let hostURL = try makePythonHost(
            body: """
            payload = b"not-json"
            sys.stdout.buffer.write(struct.pack("<I", len(payload)) + payload)
            sys.stdout.buffer.flush()
            time.sleep(0.05)
            """
        )
        let close = expectation(description: "close")
        let unexpectedMessage = expectation(description: "message")
        unexpectedMessage.isInverted = true
        var closeReason: NativeMessagingProcessSession.CloseReason?
        let session = makeSession(
            hostURL: hostURL,
            closeOnMalformedMessage: true,
            onMessage: { _ in unexpectedMessage.fulfill() },
            onClose: { reason in
                closeReason = reason
                close.fulfill()
            }
        )

        try start(session)

        wait(for: [close], timeout: Self.processTimeout)
        wait(for: [unexpectedMessage], timeout: 0.1)

        XCTAssertNotNil(error(from: closeReason))
    }

    func testOversizedQueuedWriteFailsWithQueueFullError() throws {
        let hostURL = try makePythonHost(body: "time.sleep(2)")
        let write = expectation(description: "write completion")
        var writeError: Error?
        let session = makeSession(hostURL: hostURL)
        defer { session.cancel(notify: false) }

        try start(session)
        session.send(["payload": String(repeating: "x", count: 17 * 1024 * 1024)]) { error in
            writeError = error
            write.fulfill()
        }

        wait(for: [write], timeout: Self.processTimeout)

        let error = try XCTUnwrap(writeError as NSError?)
        XCTAssertEqual(error.domain, "NativeMessaging")
        XCTAssertEqual(error.code, 7)
    }

    private func start(
        _ session: NativeMessagingProcessSession,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let completion = expectation(description: "start completion")
        var startResult: Result<Void, Error>?

        session.start { result in
            startResult = result
            completion.fulfill()
        }

        wait(for: [completion], timeout: Self.processTimeout)

        guard case .success = try XCTUnwrap(startResult, file: file, line: line) else {
            return XCTFail("Expected native messaging session start to succeed", file: file, line: line)
        }
    }

    private func makeSession(
        hostURL: URL,
        closeOnMalformedMessage: Bool = true,
        onMessage: @escaping (Data) -> Void = { _ in },
        onClose: @escaping (NativeMessagingProcessSession.CloseReason) -> Void = { _ in }
    ) -> NativeMessagingProcessSession {
        let manifest = NativeMessagingHostManifest(jsonObject: ["path": hostURL.path])!
        return NativeMessagingProcessSession(
            manifest: manifest,
            closeOnMalformedMessage: closeOnMalformedMessage,
            onMessage: onMessage,
            onClose: onClose
        )
    }

    private func makePythonHost(body: String) throws -> URL {
        let directory = try makeTemporaryDirectory()
        let url = directory.appendingPathComponent("native-host-\(UUID().uuidString).py")
        let source = """
        #!/usr/bin/env python3
        import json
        import struct
        import sys
        import time

        \(body)
        """
        try source.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiNativeMessagingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }

    private func error(
        from reason: NativeMessagingProcessSession.CloseReason?
    ) -> Error? {
        guard let reason else { return nil }
        if case .error(let error) = reason {
            return error
        }
        return nil
    }
}
