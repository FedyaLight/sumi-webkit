import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class BitwardenNativeMessagingAdapterTests: XCTestCase {
    private final class MockHostLauncher: SumiHostApplicationLaunching {
        var bundleURLs: [String: URL] = [:]
        var openedBundleIdentifiers: [String] = []

        func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
            bundleURLs[bundleIdentifier]
        }

        func openApplication(withBundleIdentifier bundleIdentifier: String) async throws {
            openedBundleIdentifiers.append(bundleIdentifier)
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

    func testHandshakeWithFakeDesktopTransport() async throws {
        let fake = BitwardenFakeDesktopProxyTransport(mode: .handshakeConnected)
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { fake },
            handshakeTimeout: .milliseconds(200)
        )
        let launcher = makeLauncherWithProxy()
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.8bit.bitwarden"
        let session = makeSession(port: port, adapter: adapter)

        let error = await connect(adapter: adapter, session: session, launcher: launcher)

        XCTAssertNil(error)
        XCTAssertTrue(launcher.openedBundleIdentifiers.isEmpty)
        XCTAssertTrue(fake.isConnected)
    }

    func testStatusWithFakeTransport() async throws {
        let fake = BitwardenFakeDesktopProxyTransport(mode: .handshakeConnected)
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { fake },
            handshakeTimeout: .milliseconds(200)
        )
        let launcher = makeLauncherWithProxy()
        let port = MockNativeMessagingPort()
        let session = makeSession(port: port, adapter: adapter)

        _ = await connect(adapter: adapter, session: session, launcher: launcher)
        let relayed = adapter.relayPortMessage(
            session: session,
            message: [
                "command": "getBiometricsStatus",
                "messageId": 1,
            ]
        )

        XCTAssertTrue(relayed)
        XCTAssertEqual(fake.sentMessages.count, 1)
        XCTAssertEqual(
            (fake.sentMessages.first?["message"] as? [String: Any])?["command"] as? String,
            "getBiometricsStatus"
        )
        XCTAssertEqual(port.repliesSent.count, 1)
    }

    func testConnectLaunchesDesktopWhenHandshakeReportsAppNotRunning() async throws {
        var attempt = 0
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: {
                attempt += 1
                return BitwardenFakeDesktopProxyTransport(
                    mode: attempt == 1 ? .handshakeAppNotRunning : .handshakeConnected
                )
            },
            handshakeTimeout: .milliseconds(200)
        )
        let launcher = makeLauncherWithProxy()
        let port = MockNativeMessagingPort()
        let session = makeSession(port: port, adapter: adapter)

        let error = await connect(adapter: adapter, session: session, launcher: launcher)

        XCTAssertNil(error)
        XCTAssertEqual(launcher.openedBundleIdentifiers, ["com.bitwarden.desktop"])
    }

    func testMalformedResponseHandledSafely() async throws {
        let fake = BitwardenFakeDesktopProxyTransport(mode: .handshakeMalformed)
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { fake },
            handshakeTimeout: .milliseconds(200)
        )
        let launcher = makeLauncherWithProxy()
        let port = MockNativeMessagingPort()
        let session = makeSession(port: port, adapter: adapter)

        let error = await connect(adapter: adapter, session: session, launcher: launcher)

        let nsError = try XCTUnwrap(error as NSError?)
        XCTAssertEqual(
            nsError.code,
            SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
        )
    }

    func testTimeoutHandledSafely() async throws {
        let fake = BitwardenFakeDesktopProxyTransport(mode: .handshakeTimeout)
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { fake },
            handshakeTimeout: .milliseconds(50)
        )
        let launcher = makeLauncherWithProxy()
        let port = MockNativeMessagingPort()
        let session = makeSession(port: port, adapter: adapter)

        let error = await connect(adapter: adapter, session: session, launcher: launcher)

        let nsError = try XCTUnwrap(error as NSError?)
        XCTAssertEqual(nsError.code, SumiNativeMessagingRelay.ErrorCode.relayTimeout.rawValue)
        XCTAssertEqual(
            BitwardenDesktopProxyTransportErrorMapper.capability(for: .timeout),
            .timeout
        )
    }

    func testPortDisconnectHandledSafely() async throws {
        let fake = BitwardenFakeDesktopProxyTransport(mode: .handshakeConnected)
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { fake },
            handshakeTimeout: .milliseconds(200)
        )
        let launcher = makeLauncherWithProxy()
        let port = MockNativeMessagingPort()
        let session = makeSession(port: port, adapter: adapter)

        _ = await connect(adapter: adapter, session: session, launcher: launcher)
        fake.simulateDisconnect()

        XCTAssertTrue(port.isDisconnected)
    }

    func testTransportOutcomeMappingCoversFailureBuckets() {
        XCTAssertEqual(
            BitwardenDesktopProxyTransportErrorMapper.outcome(for: .proxyBinaryMissing),
            .desktopAppNotInstalled
        )
        XCTAssertEqual(
            BitwardenDesktopProxyTransportErrorMapper.outcome(for: .desktopNotRunning),
            .desktopAppNotRunning
        )
        XCTAssertEqual(
            BitwardenDesktopProxyTransportErrorMapper.outcome(for: .desktopIntegrationDisabled),
            .desktopIntegrationDisabled
        )
        XCTAssertEqual(
            BitwardenDesktopProxyTransportErrorMapper.outcome(for: .protocolMismatch),
            .desktopProxyProtocolMismatch
        )
        XCTAssertEqual(
            BitwardenDesktopProxyTransportErrorMapper.outcome(for: .permissionDenied),
            .desktopPermissionDenied
        )
    }

    func testAdapterSourcesDoNotLogPayloads() throws {
        let adapterSource = try source(named: "Sumi/Managers/ExtensionManager/SafariExtension/BitwardenNativeMessagingAdapter.swift")
        let transportSource = try source(named: "Sumi/Managers/ExtensionManager/SafariExtension/BitwardenDesktopProxyTransport.swift")

        XCTAssertFalse(adapterSource.contains("print(message"))
        XCTAssertFalse(transportSource.contains("print(message"))
        XCTAssertTrue(adapterSource.contains("_ = message") || adapterSource.contains("_ = payload"))
    }

    func testAdapterUnavailableReturnsCompanionAppProtocolUnknown() async throws {
        let installed = try makeInstalledExtension(
            id: "ext-bitwarden-off",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.bitwarden.desktop",
                appexBundleID: "com.bitwarden.desktop.safari"
            )
        )
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.bitwarden.desktop"] = URL(
            fileURLWithPath: "/Applications/Bitwarden.app"
        )
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: []),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.8bit.bitwarden"
        )

        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
        )
    }

    func testGenericRuntimeHasNoBitwardenBranchesExceptRegistration() throws {
        let relaySource = try source(named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelay.swift")
        let adapterSource = try source(named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingProtocolAdapter.swift")
        let transportSource = try source(named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingAdapterTransport.swift")

        for token in ["bitwarden", "1password", "proton", "raindrop", "com.bitwarden.desktop"] {
            XCTAssertFalse(relaySource.localizedCaseInsensitiveContains(token))
            XCTAssertFalse(adapterSource.localizedCaseInsensitiveContains(token))
            XCTAssertFalse(transportSource.localizedCaseInsensitiveContains(token))
        }
    }

    func testRegistryRegistersBitwardenAdapter() {
        let registry = SumiNativeMessagingAdapterRegistry(adapters: [
            BitwardenNativeMessagingAdapter(),
        ])
        XCTAssertNotNil(registry.adapter(forApplicationIdentifier: "com.8bit.bitwarden"))
        XCTAssertEqual(
            registry.adapter(forProtocolIdentifier: BitwardenNativeMessagingIdentifiers.protocolIdentifier)?
                .protocolIdentifier,
            BitwardenNativeMessagingIdentifiers.protocolIdentifier
        )
    }

    // MARK: - Helpers

    private func makeLauncherWithProxy() -> MockHostLauncher {
        let launcher = MockHostLauncher()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BitwardenAdapter.\(UUID().uuidString)", isDirectory: true)
        let proxyURL = root
            .appendingPathComponent("Bitwarden.app/Contents/MacOS/desktop_proxy")
        try? FileManager.default.createDirectory(
            at: proxyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: proxyURL.path, contents: Data())
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: proxyURL.path
        )
        launcher.bundleURLs["com.bitwarden.desktop"] = root.appendingPathComponent("Bitwarden.app")
        return launcher
    }

    private func makeSession(
        port: MockNativeMessagingPort,
        adapter: BitwardenNativeMessagingAdapter
    ) -> SumiNativeMessagingPortSession {
        SumiNativeMessagingPortSession(
            port: port,
            adapter: adapter,
            extensionId: "ext-bitwarden",
            hostBundleIdentifier: "com.bitwarden.desktop",
            resolverBucket: .knownCompanionAlias,
            logDiagnostic: { _ in },
            companionProtocolErrorProvider: {
                SumiNativeMessagingErrorMapper.relayError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: nil
                )
            }
        )
    }

    private func connect(
        adapter: BitwardenNativeMessagingAdapter,
        session: SumiNativeMessagingPortSession,
        launcher: MockHostLauncher
    ) async -> (any Error)? {
        let expectation = expectation(description: "connect")
        var connectError: (any Error)?
        adapter.connectPort(session: session, launcher: launcher) { error in
            connectError = error
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2)
        return connectError
    }

    private func sendMessageReply(
        relay: SumiNativeMessagingRelay,
        installed: InstalledExtension,
        applicationIdentifier: String
    ) async -> (value: Any?, error: (any Error)?) {
        let expectation = expectation(description: "nativeMessagingReply")
        var replyValue: Any?
        var replyError: (any Error)?
        relay.handleSendMessage(
            applicationIdentifier: applicationIdentifier,
            message: ["type": "ping"],
            extensionId: installed.id,
            installedExtensions: [installed]
        ) { value, error in
            replyValue = value
            replyError = error
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 5)
        return (replyValue, replyError)
    }

    private func makeInstalledExtension(
        id: String,
        sourceBundlePath: String
    ) throws -> InstalledExtension {
        InstalledExtension(
            id: id,
            name: "Fixture",
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: true,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: "/tmp/\(id)",
            iconPath: nil,
            sourceKind: .safariAppExtension,
            backgroundModel: .serviceWorker,
            incognitoMode: .split,
            sourcePathFingerprint: "fp",
            manifestRootFingerprint: "mf",
            sourceBundlePath: sourceBundlePath,
            optionsPagePath: nil,
            defaultPopupPath: nil,
            hasBackground: true,
            hasAction: true,
            hasOptionsPage: false,
            hasContentScripts: true,
            hasExtensionPages: true,
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: [],
                broadScope: false,
                hasContentScripts: true,
                hasAction: true,
                hasOptionsPage: false,
                hasExtensionPages: true
            ),
            manifest: [:]
        )
    }

    private func makeFixtureApp(
        appBundleID: String,
        appexBundleID: String
    ) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BitwardenAdapterFixture.\(UUID().uuidString)", isDirectory: true)
        let appURL = root.appendingPathComponent("Host.app", isDirectory: true)
        let appexURL = appURL
            .appendingPathComponent("Contents/PlugIns/Extension.appex", isDirectory: true)

        try FileManager.default.createDirectory(
            at: appexURL.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )

        let appInfo: [String: Any] = ["CFBundleIdentifier": appBundleID]
        let appexInfo: [String: Any] = [
            "CFBundleIdentifier": appexBundleID,
            "NSExtension": [
                "NSExtensionPointIdentifier": SafariExtensionScanner.safariWebExtensionPointIdentifier,
            ],
        ]
        try writePlist(appInfo, to: appURL.appendingPathComponent("Contents/Info.plist"))
        try writePlist(
            appexInfo,
            to: appexURL.appendingPathComponent("Contents/Info.plist")
        )
        return appexURL.path
    }

    private func writePlist(_ dictionary: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }

    private func source(named relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
