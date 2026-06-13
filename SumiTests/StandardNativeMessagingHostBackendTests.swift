import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class StandardNativeMessagingHostBackendTests: XCTestCase {
    private final class MockHostLauncher: SumiHostApplicationLaunching {
        var bundleURLs: [String: URL] = [:]

        func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
            bundleURLs[bundleIdentifier]
        }

        func openApplication(withBundleIdentifier bundleIdentifier: String) async throws {
            _ = bundleIdentifier
        }
    }

    private final class MockNativeMessagingPort: SumiNativeMessagingPortReplyRecording {
        var applicationIdentifier: String?
        var isDisconnected = false
        var messageHandler: ((Any?, (any Error)?) -> Void)?
        var disconnectHandler: (((any Error)?) -> Void)?
        var disconnectError: (any Error)?
        private(set) var repliesSent: [Any] = []

        func recordReplyToExtension(_ message: Any) {
            repliesSent.append(message)
        }

        func disconnect() {
            isDisconnected = true
            disconnectHandler?(disconnectError)
        }

        func disconnect(throwing error: (any Error)?) {
            disconnectError = error
            disconnect()
        }

        func simulateIncomingMessage(_ message: Any?) {
            messageHandler?(message, nil)
        }
    }

    private final class FakeNativeHostTransport: NativeMessagingHostTransporting {
        enum Mode {
            case start
            case fail(NativeMessagingHostTransportError)
        }

        private let mode: Mode
        private(set) var isConnected = false
        private(set) var startedURL: URL?
        private(set) var sentMessages: [[String: Any]] = []
        private(set) var shutdownCount = 0
        var onDisconnect: (() -> Void)?
        var onReceive: (([String: Any]) -> Void)?

        init(mode: Mode = .start) {
            self.mode = mode
        }

        func start(hostExecutableURL: URL) async throws {
            startedURL = hostExecutableURL
            switch mode {
            case .start:
                isConnected = true
            case .fail(let error):
                throw error
            }
        }

        func send(_ object: [String: Any]) throws {
            guard isConnected else {
                throw NativeMessagingHostTransportError.portDisconnected
            }
            sentMessages.append(object)
        }

        func shutdown() {
            isConnected = false
            shutdownCount += 1
        }

        func emit(_ object: [String: Any]) {
            onReceive?(object)
        }

        func disconnectFromHost() {
            isConnected = false
            onDisconnect?()
        }
    }

    private final class FakeNativeHostResolver: NativeMessagingHostManifestResolving {
        var result: NativeMessagingHostResolutionResult

        init(result: NativeMessagingHostResolutionResult) {
            self.result = result
        }

        func resolve(mapping: StandardNativeMessagingHostMapping)
            -> NativeMessagingHostResolutionResult
        {
            _ = mapping
            return result
        }
    }

    func testStandardStdioFrameEncodeDecodeRoundTrips() throws {
        let encoded = try NativeMessagingStdioFraming.encode([
            "type": "unlock",
            "messageId": "msg-1",
        ])
        var buffer = encoded

        let decoded = try XCTUnwrap(
            NativeMessagingStdioFraming.decodeNext(from: &buffer) as? [String: Any]
        )

        XCTAssertEqual(decoded["type"] as? String, "unlock")
        XCTAssertEqual(decoded["messageId"] as? String, "msg-1")
        XCTAssertTrue(buffer.isEmpty)
    }

    func testStandardStdioFrameRejectsOversizedFrame() {
        var oversizedLength = UInt32(NativeMessagingStdioFraming.maxFrameBytes + 1).littleEndian
        var buffer = Data(bytes: &oversizedLength, count: MemoryLayout<UInt32>.size)
        buffer.append(Data(repeating: 0, count: 8))

        let decoded = NativeMessagingStdioFraming.decodeNext(from: &buffer)

        XCTAssertTrue(decoded is NSNull)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testHostResolverReportsMissingManifest() {
        let root = temporaryDirectory()
        let appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let fileManager = StandardResolverTestFileManager(applicationSupportURL: appSupport)
        let resolver = NativeMessagingHostManifestResolver(
            fileManager: fileManager,
            appBundleURLResolver: { _ in nil }
        )

        let result = resolver.resolve(mapping: Self.exampleMapping)

        XCTAssertEqual(result, .missingHostManifest(hostName: Self.exampleMapping.nativeHostName))
    }

    func testHostResolverReportsMissingExecutableFromManifest() throws {
        let root = temporaryDirectory()
        let appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        let manifestDirectory = appSupport.appendingPathComponent(
            "Google/Chrome/NativeMessagingHosts",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: manifestDirectory,
            withIntermediateDirectories: true
        )
        let missingExecutable = root.appendingPathComponent("missing-host")
        let manifest = """
        {
          "name": "\(Self.exampleMapping.nativeHostName)",
          "description": "Example host",
          "path": "\(missingExecutable.path)",
          "type": "stdio"
        }
        """
        try manifest.write(
            to: manifestDirectory.appendingPathComponent(Self.exampleMapping.manifestFileName),
            atomically: true,
            encoding: .utf8
        )
        let fileManager = StandardResolverTestFileManager(applicationSupportURL: appSupport)
        let resolver = NativeMessagingHostManifestResolver(
            fileManager: fileManager,
            appBundleURLResolver: { _ in nil }
        )

        let result = resolver.resolve(mapping: Self.exampleMapping)

        XCTAssertEqual(
            result,
            .missingHostExecutable(
                hostName: Self.exampleMapping.nativeHostName,
                manifest: NativeMessagingHostManifest(
                    name: Self.exampleMapping.nativeHostName,
                    path: missingExecutable.path,
                    type: "stdio"
                ),
                sourceKind: .nativeMessagingManifest
            )
        )
    }

    func testHostResolverFindsExecutableFromManifest() throws {
        let root = temporaryDirectory()
        let appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        let manifestDirectory = appSupport.appendingPathComponent(
            "Google/Chrome/NativeMessagingHosts",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: manifestDirectory,
            withIntermediateDirectories: true
        )
        let executable = root.appendingPathComponent("example-host")
        FileManager.default.createFile(atPath: executable.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let manifest = """
        {
          "name": "\(Self.exampleMapping.nativeHostName)",
          "description": "Example host",
          "path": "\(executable.path)",
          "type": "stdio"
        }
        """
        try manifest.write(
            to: manifestDirectory.appendingPathComponent(Self.exampleMapping.manifestFileName),
            atomically: true,
            encoding: .utf8
        )
        let fileManager = StandardResolverTestFileManager(applicationSupportURL: appSupport)
        let resolver = NativeMessagingHostManifestResolver(
            fileManager: fileManager,
            appBundleURLResolver: { _ in nil }
        )

        let result = resolver.resolve(mapping: Self.exampleMapping)

        XCTAssertEqual(result.hostExecutable, executable)
        XCTAssertEqual(result.sourceKind, .nativeMessagingManifest)
    }

    func testOneShotRelaysThroughStandardHostAndCompletesExactlyOnce() async throws {
        let fake = FakeNativeHostTransport()
        let backend = makeBackend(transport: fake)
        let expectation = expectation(description: "one-shot reply")
        var replies: [Any?] = []
        var errors: [Error?] = []

        backend.relayOneShotMessage(
            request: SumiNativeMessagingOneShotRequest(
                applicationIdentifier: Self.exampleMapping.nativeHostName,
                extensionId: "ext-standard",
                hostBundleIdentifier: Self.exampleBundleIdentifier,
                resolverBucket: .knownCompanionAlias,
                message: [
                    "type": "unlock",
                    "messageId": "msg-one-shot",
                ]
            ),
            launcher: MockHostLauncher()
        ) { value, error in
            replies.append(value)
            errors.append(error)
            expectation.fulfill()
        }

        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fake.sentMessages.count, 1)
        fake.emit([
            "type": "unlock",
            "messageId": "msg-one-shot",
            "reply": "real-host-response",
        ])
        fake.emit([
            "type": "unlock",
            "messageId": "msg-one-shot",
            "reply": "late-host-response",
        ])

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(replies.count, 1)
        XCTAssertNil(errors.first ?? nil)
        let reply = try XCTUnwrap(replies.first as? [String: Any])
        XCTAssertEqual(reply["reply"] as? String, "real-host-response")
        XCTAssertEqual(fake.shutdownCount, 1)
    }

    func testPersistentPortRelaysRealHostResponsesAndClosesTransport() async throws {
        let fake = FakeNativeHostTransport()
        let backend = makeBackend(transport: fake)
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = Self.exampleMapping.nativeHostName
        let session = makeSession(port: port, backend: backend)

        let connectError = await connect(backend: backend, session: session)
        XCTAssertNil(connectError)

        XCTAssertTrue(
            backend.relayPortMessage(
                session: session,
                message: [
                    "type": "setup-lock-secret",
                    "messageId": "msg-port",
                ]
            )
        )
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fake.sentMessages.count, 1)

        fake.emit([
            "type": "setup-lock-secret",
            "messageId": "msg-port",
            "reply": "real-host-port-response",
        ])

        let reply = try XCTUnwrap(port.repliesSent.first as? [String: Any])
        XCTAssertEqual(reply["reply"] as? String, "real-host-port-response")
        backend.disconnectPort(session: session)
        XCTAssertEqual(fake.shutdownCount, 1)
    }

    func testMissingHostFailsWithoutFakeSuccess() async throws {
        let resolver = FakeNativeHostResolver(
            result: .missingHostManifest(hostName: Self.exampleMapping.nativeHostName)
        )
        let fake = FakeNativeHostTransport()
        let backend = StandardNativeMessagingHostBackend(
            mappings: [Self.exampleMapping],
            resolver: resolver,
            transportFactory: { fake },
            replyTimeout: .milliseconds(200)
        )
        let expectation = expectation(description: "missing host reply")
        var replyValue: Any?
        var replyError: Error?

        backend.relayOneShotMessage(
            request: SumiNativeMessagingOneShotRequest(
                applicationIdentifier: Self.exampleMapping.nativeHostName,
                extensionId: "ext-standard",
                hostBundleIdentifier: Self.exampleBundleIdentifier,
                resolverBucket: .knownCompanionAlias,
                message: ["type": "unlock", "messageId": "msg-missing"]
            ),
            launcher: MockHostLauncher()
        ) { value, error in
            replyValue = value
            replyError = error
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertNil(replyValue)
        let error = try XCTUnwrap(replyError as NSError?)
        XCTAssertEqual(error.domain, SumiNativeMessagingRelay.errorDomain)
        XCTAssertEqual(error.code, SumiNativeMessagingRelay.ErrorCode.nativeHostManifestMissing.rawValue)
        XCTAssertEqual(
            error.userInfo[NativeMessagingHostBackendErrorMapper.failureCategoryUserInfoKey] as? String,
            NativeMessagingHostFailureCategory.nativeHostManifestMissing.rawValue
        )
        XCTAssertTrue(fake.sentMessages.isEmpty)
    }

    func testConnectMissingExecutableFailsWithoutPortReply() async throws {
        let resolver = FakeNativeHostResolver(
            result: .missingHostExecutable(
                hostName: Self.exampleMapping.nativeHostName,
                manifest: nil,
                sourceKind: .appBundleEmbeddedExecutable
            )
        )
        let backend = StandardNativeMessagingHostBackend(
            mappings: [Self.exampleMapping],
            resolver: resolver,
            transportFactory: { FakeNativeHostTransport() }
        )
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = Self.exampleMapping.nativeHostName
        let session = makeSession(port: port, backend: backend)

        let connectError = await connect(backend: backend, session: session)

        let error = try XCTUnwrap(connectError as NSError?)
        XCTAssertEqual(error.domain, SumiNativeMessagingRelay.errorDomain)
        XCTAssertEqual(error.code, SumiNativeMessagingRelay.ErrorCode.nativeHostExecutableMissing.rawValue)
        XCTAssertTrue(port.repliesSent.isEmpty)
    }

    func testProtonMappingUsesGenericStandardBackend() {
        let registry = SumiNativeMessagingAdapterRegistry(adapters: [
            StandardNativeMessagingHostBackend(
                mappings: [ProtonNativeMessagingIdentifiers.standardNativeHostMapping]
            ),
        ])

        let adapter = registry.adapter(
            forApplicationIdentifier: ProtonNativeMessagingIdentifiers.requestedApplicationIdentifier
        )

        XCTAssertTrue(adapter is StandardNativeMessagingHostBackend)
        XCTAssertEqual(adapter?.protocolIdentifier, StandardNativeMessagingHostBackend.backendIdentifier)
    }

    func testGenericRuntimeHasNoProtonBranchesOutsideRegistryAndMetadata() throws {
        let forbiddenSources = [
            "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelay.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingProtocolAdapter.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingAdapterTransport.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/StandardNativeMessagingHostBackend.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/NativeMessagingHostManifestResolver.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/NativeMessagingHostProcessTransport.swift",
            "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift",
        ]

        for sourcePath in forbiddenSources {
            let source = try source(named: sourcePath)
            XCTAssertFalse(
                source.localizedCaseInsensitiveContains("proton"),
                "\(sourcePath) must not contain Proton-specific routing"
            )
            XCTAssertFalse(
                source.contains(ProtonNativeMessagingIdentifiers.requestedApplicationIdentifier),
                "\(sourcePath) must not contain Proton native host id"
            )
        }
    }

    func testStandardTransportDiagnosticsDoNotLogPayloadBodies() throws {
        let source = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/NativeMessagingHostProcessTransport.swift"
        )
        XCTAssertFalse(source.contains("debugDescription"))
        XCTAssertFalse(source.contains("RuntimeDiagnostics.debug(category: \"StandardNativeMessagingHost\") { object"))
        XCTAssertFalse(source.contains("RuntimeDiagnostics.debug(category: \"StandardNativeMessagingHost\") { payload"))
        XCTAssertFalse(source.contains("messageBody"))
        XCTAssertFalse(source.contains("authPayload"))
    }

    private static let exampleBundleIdentifier = "com.example.standardhost"
    private static let exampleExecutableURL = URL(fileURLWithPath: "/tmp/example-standard-host")
    private static let exampleMapping = StandardNativeMessagingHostMapping(
        nativeHostName: "com.example.standardhost.nm",
        displayName: "Example Standard Host",
        requestedApplicationIdentifiers: ["com.example.standardhost.nm"],
        registryHostBundleIdentifiers: [exampleBundleIdentifier],
        appBundleIdentifiers: [exampleBundleIdentifier],
        manifestFileName: "com.example.standardhost.nm.json",
        embeddedHostExecutableRelativePaths: ["Contents/MacOS/example-standard-host"]
    )

    private func makeBackend(
        transport: FakeNativeHostTransport,
        replyTimeout: Duration = .milliseconds(500)
    ) -> StandardNativeMessagingHostBackend {
        StandardNativeMessagingHostBackend(
            mappings: [Self.exampleMapping],
            resolver: FakeNativeHostResolver(
                result: .resolved(
                    hostExecutable: Self.exampleExecutableURL,
                    manifest: nil,
                    sourceKind: .nativeMessagingManifest
                )
            ),
            transportFactory: { transport },
            replyTimeout: replyTimeout
        )
    }

    private func makeSession(
        port: MockNativeMessagingPort,
        backend: StandardNativeMessagingHostBackend
    ) -> SumiNativeMessagingPortSession {
        SumiNativeMessagingPortSession(
            port: port,
            adapter: backend,
            extensionId: "ext-standard",
            hostBundleIdentifier: Self.exampleBundleIdentifier,
            resolverBucket: .knownCompanionAlias,
            logDiagnostic: { _ in },
            companionProtocolErrorProvider: {
                SumiNativeMessagingErrorMapper.messagePortDisconnectError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: nil
                )
            },
            portInactivityTimeout: .seconds(5)
        )
    }

    private func connect(
        backend: StandardNativeMessagingHostBackend,
        session: SumiNativeMessagingPortSession,
        launcher: SumiHostApplicationLaunching = MockHostLauncher()
    ) async -> Error? {
        await withCheckedContinuation { continuation in
            backend.connectPort(session: session, launcher: launcher) { error in
                continuation.resume(returning: error)
            }
        }
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiStandardNativeMessagingHostBackendTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func source(named relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private final class StandardResolverTestFileManager: FileManager {
    private let applicationSupportURL: URL

    init(applicationSupportURL: URL) {
        self.applicationSupportURL = applicationSupportURL
        super.init()
    }

    override func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        guard directory == .applicationSupportDirectory else {
            return super.urls(for: directory, in: domainMask)
        }
        if domainMask.contains(.userDomainMask) {
            return [applicationSupportURL]
        }
        return []
    }
}
