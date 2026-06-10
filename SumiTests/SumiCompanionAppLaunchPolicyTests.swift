import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SumiCompanionAppLaunchPolicyTests: XCTestCase {
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

    override func tearDown() {
        SumiCompanionAppLaunchPolicy.shared.clearPendingState()
        super.tearDown()
    }

    func testPendingNativeMessagingAfterPopupCloseDoesNotRepeatedlyLaunchDesktop() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.host",
            appexBundleID: "com.example.host.extension"
        )
        let installed = try makeInstalledExtension(id: "ext-supported", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let adapter = SumiNativeMessagingFakePublicAdapter(
            supportedHosts: ["com.example.host"],
            shouldLaunchOnConnect: true
        )
        let launchPolicy = SumiCompanionAppLaunchPolicy()
        let loopGuard = SumiNativeMessagingRelayLoopGuard()
        let relay = SumiNativeMessagingRelay(
            importStore: SafariExtensionImportStore(defaults: makeDefaults()),
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [adapter]),
            launchPolicy: launchPolicy,
            loopGuard: loopGuard,
            extensionsModuleEnabled: { true }
        )

        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.example.host"
        _ = await connectReply(relay: relay, port: port, installed: installed)
        XCTAssertEqual(launcher.openedBundleIdentifiers, ["com.example.host"])

        relay.clearLaunchSessionOnExtensionContextUnload(forExtensionId: installed.id)

        let port2 = MockNativeMessagingPort()
        port2.applicationIdentifier = "com.example.host"
        _ = await connectReply(relay: relay, port: port2, installed: installed)

        XCTAssertEqual(launcher.openedBundleIdentifiers.count, 1)
    }

    func testClosingDesktopDoesNotCauseRelaunchLoop() async throws {
        let launchPolicy = SumiCompanionAppLaunchPolicy(minimumLaunchInterval: 60)
        let launcher = makeLauncherWithBitwardenProxy()
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { BitwardenFakeDesktopProxyTransport(mode: .handshakeConnected) },
            handshakeTimeout: .milliseconds(200)
        )
        let loopGuard = SumiNativeMessagingRelayLoopGuard()
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [adapter]),
            launchPolicy: launchPolicy,
            loopGuard: loopGuard,
            extensionsModuleEnabled: { true }
        )
        let installed = try makeInstalledExtension(
            id: "ext-bw-loop",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.bitwarden.desktop",
                appexBundleID: "com.bitwarden.desktop.safari"
            )
        )

        let firstPort = MockNativeMessagingPort()
        firstPort.applicationIdentifier = "com.8bit.bitwarden"
        _ = await connectReply(relay: relay, port: firstPort, installed: installed)

        loopGuard.recordSupportedAdapterLaunchAttempt(
            key: SumiNativeMessagingRelayLoopGuard.SessionKey(
                profileId: nil,
                extensionId: installed.id,
                applicationIdentifier: "com.bitwarden.desktop"
            )
        )
        launchPolicy.recordLaunchAttempt(
            forHostBundleIdentifier: "com.bitwarden.desktop",
            sessionKey: SumiCompanionAppLaunchPolicy.sessionKey(
                profileId: nil,
                extensionId: installed.id,
                requestedApplicationIdentifier: "com.8bit.bitwarden",
                hostBundleIdentifier: "com.bitwarden.desktop"
            )
        )

        let secondPort = MockNativeMessagingPort()
        secondPort.applicationIdentifier = "com.8bit.bitwarden"
        let second = await connectReply(relay: relay, port: secondPort, installed: installed)

        XCTAssertNil(second.error)
        XCTAssertNotNil(second.session)
        XCTAssertTrue(launcher.openedBundleIdentifiers.isEmpty)
    }

    func testRaindropDoesNotTriggerBitwardenLaunch() async throws {
        let raindropAppex = try makeFixtureApp(
            appBundleID: "io.raindrop.desktop",
            appexBundleID: "io.raindrop.desktop.extension"
        )
        let installed = try makeInstalledExtension(id: "ext-raindrop", sourceBundlePath: raindropAppex)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["io.raindrop.desktop"] = URL(fileURLWithPath: "/Applications/Raindrop.app")
        launcher.bundleURLs["com.bitwarden.desktop"] = URL(fileURLWithPath: "/Applications/Bitwarden.app")
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [
                BitwardenNativeMessagingAdapter(),
            ]),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "io.raindrop.desktop"
        )

        XCTAssertTrue(launcher.openedBundleIdentifiers.isEmpty)
        XCTAssertEqual(
            (reply.error as NSError?)?.code,
            SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
        )
        XCTAssertFalse(launcher.openedBundleIdentifiers.contains("com.bitwarden.desktop"))
    }

    func testUnknownProtocolLaunchSuppressed() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.host",
            appexBundleID: "com.example.host.extension"
        )
        let installed = try makeInstalledExtension(id: "ext-unknown", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let relay = SumiNativeMessagingRelay(
            importStore: SafariExtensionImportStore(defaults: makeDefaults()),
            launcher: launcher,
            extensionsModuleEnabled: { true }
        )

        _ = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.example.host"
        )
        let second = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.example.host"
        )

        XCTAssertTrue(launcher.openedBundleIdentifiers.isEmpty)
        XCTAssertEqual(
            (second.error as NSError?)?.code,
            SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
        )
    }

    func testSupportedAdapterLaunchBoundedPerSession() async throws {
        let launchPolicy = SumiCompanionAppLaunchPolicy(minimumLaunchInterval: 60)
        let sessionKey = SumiCompanionAppLaunchPolicy.sessionKey(
            profileId: UUID(),
            extensionId: "ext-bw",
            requestedApplicationIdentifier: "com.8bit.bitwarden",
            hostBundleIdentifier: "com.bitwarden.desktop"
        )

        launchPolicy.recordLaunchAttempt(
            forHostBundleIdentifier: "com.bitwarden.desktop",
            sessionKey: sessionKey
        )

        let decision: SumiCompanionAppLaunchDecision = launchPolicy.evaluateLaunch(
            hostBundleIdentifier: "com.bitwarden.desktop",
            appInstalled: true,
            protocolAdapterAvailable: true,
            sessionKey: sessionKey,
            isHostRunning: true
        )

        XCTAssertEqual(decision, SumiCompanionAppLaunchDecision.suppressedSessionLaunchAttempted)
    }

    func testConnectIfRunningSuppressesLaunchWhenDesktopNotRunning() {
        let launchPolicy = SumiCompanionAppLaunchPolicy()
        let decision: SumiCompanionAppLaunchDecision = launchPolicy.evaluateLaunch(
            hostBundleIdentifier: "com.bitwarden.desktop",
            appInstalled: true,
            protocolAdapterAvailable: true,
            isHostRunning: false
        )

        XCTAssertEqual(decision, SumiCompanionAppLaunchDecision.suppressedConnectIfNotRunning)
    }

    func testSupportedAdapterLoopGuardSuppressesRepeatLaunch() {
        let loopGuard = SumiNativeMessagingRelayLoopGuard()
        let key = SumiNativeMessagingRelayLoopGuard.SessionKey(
            profileId: UUID(),
            extensionId: "ext-bw",
            applicationIdentifier: "com.bitwarden.desktop"
        )
        loopGuard.recordSupportedAdapterLaunchAttempt(key: key)

        let evaluation = loopGuard.evaluate(
            key: key,
            hostBundleIdentifier: BitwardenNativeMessagingIdentifiers.hostBundleIdentifier
        )

        XCTAssertFalse(evaluation.shouldLaunchHost)
        XCTAssertFalse(evaluation.launchSuppressed)
    }

    // MARK: - Helpers

    private final class MockNativeMessagingPort: SumiNativeMessagingPortControlling {
        var applicationIdentifier: String?
        var isDisconnected = false
        var messageHandler: ((Any?, (any Error)?) -> Void)?
        var disconnectHandler: (((any Error)?) -> Void)?
        var disconnectError: (any Error)?

        func disconnect() {
            isDisconnected = true
            disconnectHandler?(disconnectError)
        }

        func disconnect(throwing error: (any Error)?) {
            disconnectError = error
            disconnect()
        }
    }

    private func connectReply(
        relay: SumiNativeMessagingRelay,
        port: MockNativeMessagingPort,
        installed: InstalledExtension
    ) async -> (session: SumiNativeMessagingPortSession?, error: (any Error)?) {
        let expectation = expectation(description: "nativeMessagingConnect")
        var connectError: (any Error)?
        var session: SumiNativeMessagingPortSession?
        _ = relay.handleConnect(
            port: port,
            extensionId: installed.id,
            installedExtensions: [installed],
            registerHandler: { session = $0 },
            completionHandler: { error in
                connectError = error
                expectation.fulfill()
            }
        )
        await fulfillment(of: [expectation], timeout: 5)
        return (session, connectError)
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
            .appendingPathComponent("LaunchPolicy.\(UUID().uuidString)", isDirectory: true)
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

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SumiCompanionAppLaunchPolicyTests.\(UUID().uuidString)")!
    }

    private func makeLauncherWithBitwardenProxy() -> MockHostLauncher {
        let launcher = MockHostLauncher()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchPolicyBW.\(UUID().uuidString)", isDirectory: true)
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
}
