import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class BitwardenNativeMessagingCPUTeardownTests: XCTestCase {
    private final class MockHostLauncher: SumiHostApplicationLaunching {
        var bundleURLs: [String: URL] = [:]
        var openedBundleIdentifiers: [String] = []

        func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
            bundleURLs[bundleIdentifier]
        }

        func openApplication(withBundleIdentifier bundleIdentifier: String) async {
            openedBundleIdentifiers.append(bundleIdentifier)
        }
    }

    private final class MockNativeMessagingPort: SumiNativeMessagingPortReplyRecording {
        var applicationIdentifier: String?
        var isDisconnected = false
        var messageHandler: ((Any?, (any Error)?) -> Void)?
        var disconnectHandler: (((any Error)?) -> Void)?
        var disconnectError: (any Error)?

        func recordReplyToExtension(_: Any) { /* no-op */ }

        func disconnect() {
            isDisconnected = true
            disconnectHandler?(disconnectError)
        }

        func disconnect(throwing error: (any Error)?) {
            disconnectError = error
            disconnect()
        }
    }

    private final class ShutdownTrackingTransport: BitwardenDesktopProxyTransporting {
        private(set) var isConnected = false
        private(set) var shutdownCount = 0
        var onDisconnect: (() -> Void)?
        var onReceive: (([String: Any]) -> Void)?

        func start(
            proxyExecutableURL: URL,
            handshakeTimeout: Duration
        ) async {
            _ = proxyExecutableURL
            _ = handshakeTimeout
            isConnected = true
        }

        func send(_ object: [String: Any]) {
            _ = object
        }

        func shutdown() {
            shutdownCount += 1
            isConnected = false
        }
    }

    override func setUp() {
        super.setUp()
        SumiNativeMessagingRuntimeCounters.resetForTesting()
    }

    func testClearLaunchSessionShutsDownBitwardenDesktopTransport() async {
        let transport = ShutdownTrackingTransport()
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { transport },
            handshakeTimeout: .milliseconds(200)
        )
        let launcher = makeLauncherWithProxy()
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.8bit.bitwarden"
        let session = makeSession(port: port, adapter: adapter)

        _ = await connect(adapter: adapter, session: session, launcher: launcher)
        XCTAssertEqual(transport.shutdownCount, 0)
        XCTAssertEqual(SumiNativeMessagingRuntimeCounters.snapshot().liveAdapterPortSessions, 1)

        adapter.disconnectPort(session: session)

        XCTAssertEqual(transport.shutdownCount, 1)
        XCTAssertEqual(SumiNativeMessagingRuntimeCounters.snapshot().liveAdapterPortSessions, 0)
    }

    func testRelayContextUnloadInvokesAdapterDisconnectPort() async throws {
        let transport = ShutdownTrackingTransport()
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { transport },
            handshakeTimeout: .milliseconds(200)
        )
        let installed = try makeInstalledExtension(
            id: "ext-bitwarden-cpu",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.bitwarden.desktop",
                appexBundleID: "com.bitwarden.desktop.safari"
            )
        )
        let launcher = makeLauncherWithProxy()
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [adapter]),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.bitwarden.desktop"

        let connectResult = await connectReply(
            relay: relay,
            port: port,
            installed: installed
        )
        XCTAssertNil(connectResult)
        XCTAssertEqual(transport.shutdownCount, 0)

        relay.clearLaunchSessionOnExtensionContextUnload(forExtensionId: installed.id)

        XCTAssertEqual(transport.shutdownCount, 1)
        XCTAssertTrue(port.isDisconnected)
        let snapshot = SumiNativeMessagingRuntimeCounters.snapshot()
        XCTAssertEqual(snapshot.liveRelayPortSessions, 0)
        XCTAssertEqual(snapshot.liveAdapterPortSessions, 0)
        XCTAssertEqual(snapshot.contextUnloadCount, 1)
        XCTAssertEqual(snapshot.popupCloseCount, 0)
    }

    func testRuntimeCountersTrackPopupAndPortLifecycle() async throws {
        let adapter = SumiNativeMessagingFakePublicAdapter(
            supportedHosts: ["com.example.host"],
            shouldLaunchOnConnect: false
        )
        let installed = try makeInstalledExtension(
            id: "ext-counter",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.example.host",
                appexBundleID: "com.example.host.extension"
            )
        )
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [adapter]),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.example.host"

        _ = await connectReply(relay: relay, port: port, installed: installed)
        SumiNativeMessagingRuntimeCounters.recordPopupOpened(extensionId: installed.id)
        SumiNativeMessagingRuntimeCounters.recordPopupClosed(extensionId: installed.id)
        relay.clearLaunchSessionOnExtensionContextUnload(forExtensionId: installed.id)

        let snapshot = SumiNativeMessagingRuntimeCounters.snapshot()
        XCTAssertEqual(snapshot.connectCount, 1)
        XCTAssertEqual(snapshot.portOpenCount, 1)
        XCTAssertEqual(snapshot.portCloseCount, 1)
        XCTAssertEqual(snapshot.liveRelayPortSessions, 0)
        XCTAssertEqual(snapshot.popupOpenCount, 1)
        XCTAssertEqual(snapshot.popupCloseCount, 1)
        XCTAssertEqual(snapshot.contextUnloadCount, 1)
    }

    // MARK: - Helpers

    private func makeLauncherWithProxy() -> MockHostLauncher {
        let launcher = MockHostLauncher()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BitwardenCPU.\(UUID().uuidString)", isDirectory: true)
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
            logDiagnostic: { _ in /* no-op */ },
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

    private func connectReply(
        relay: SumiNativeMessagingRelay,
        port: MockNativeMessagingPort,
        installed: InstalledExtension
    ) async -> (any Error)? {
        let expectation = expectation(description: "connect")
        var connectError: (any Error)?
        _ = relay.handleConnect(
            port: port,
            extensionId: installed.id,
            installedExtensions: [installed],
            registerHandler: { _ in /* no-op */ },
            completionHandler: { error in
                connectError = error
                expectation.fulfill()
            }
        )
        await fulfillment(of: [expectation], timeout: 2)
        return connectError
    }

    private func makeInstalledExtension(
        id: String,
        sourceBundlePath: String
    ) -> InstalledExtension {
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
            .appendingPathComponent("BitwardenCPUFixture.\(UUID().uuidString)", isDirectory: true)
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
}
