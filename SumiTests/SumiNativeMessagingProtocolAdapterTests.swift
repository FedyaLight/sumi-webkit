import XCTest

@testable import Sumi

// Manual acceptance checklist: docs/SafariExtensionNativeMessagingAdapterAcceptance.md
// Regression guards: SumiNativeMessagingAdapterRegressionGuardTests

@available(macOS 15.5, *)
@MainActor
final class SumiNativeMessagingProtocolAdapterTests: XCTestCase {
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

        func simulateIncomingMessage(_ message: Any?) {
            messageHandler?(message, nil)
        }

        func simulateDisconnect(error: (any Error)? = nil) {
            isDisconnected = true
            disconnectHandler?(error)
        }
    }

    // 1. Fake public adapter handles one-shot native message
    func testFakePublicAdapterHandlesOneShotMessage() async throws {
        let installed = makeInstalledExtension(
            id: "ext-one-shot",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.example.host",
                appexBundleID: "com.example.host.extension"
            )
        )
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let adapter = SumiNativeMessagingFakePublicAdapter(
            supportedHosts: ["com.example.host"],
            oneShotReply: (["pong": 1], nil)
        )
        let relay = makeRelay(launcher: launcher, adapters: [adapter])

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.example.host"
        )

        XCTAssertEqual(adapter.oneShotRequestCount, 1)
        XCTAssertEqual(launcher.openedBundleIdentifiers, ["com.example.host"])
        XCTAssertEqual(reply.value as? [String: Int], ["pong": 1])
        XCTAssertNil(reply.error)
    }

    // 2. Fake public adapter handles persistent port
    func testFakePublicAdapterHandlesPersistentPort() async throws {
        let installed = makeInstalledExtension(
            id: "ext-port",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.example.host",
                appexBundleID: "com.example.host.extension"
            )
        )
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let adapter = SumiNativeMessagingFakePublicAdapter(supportedHosts: ["com.example.host"])
        let relay = makeRelay(launcher: launcher, adapters: [adapter])
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.example.host"

        let connectResult = await connectReply(relay: relay, port: port, installed: installed)
        let session = try XCTUnwrap(connectResult.session)
        port.simulateIncomingMessage(["hello": "world"])

        XCTAssertNil(connectResult.error)
        XCTAssertEqual(adapter.connectRequestCount, 1)
        XCTAssertTrue(adapter.portMessageRelayed)
        XCTAssertFalse(port.isDisconnected)
        XCTAssertEqual(session.resolvedHostBundleIdentifier, "com.example.host")
    }

    // 3. Unknown adapter returns companionAppProtocolUnknown
    func testUnknownAdapterReturnsCompanionAppProtocolUnknown() async throws {
        let installed = makeInstalledExtension(
            id: "ext-unknown",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.vendor.desktop",
                appexBundleID: "com.vendor.desktop.safari"
            )
        )
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.vendor.desktop"] = URL(fileURLWithPath: "/Applications/Vendor.app")
        let relay = makeRelay(launcher: launcher, adapters: [])

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.vendor.desktop"
        )

        XCTAssertTrue(launcher.openedBundleIdentifiers.isEmpty)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
        )
    }

    // 4. Adapter unavailable does not launch app repeatedly
    func testAdapterUnavailableDoesNotLaunchAppRepeatedly() async throws {
        let installed = makeInstalledExtension(
            id: "ext-no-launch-loop",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.example.host",
                appexBundleID: "com.example.host.extension"
            )
        )
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let relay = makeRelay(launcher: launcher, adapters: [])

        _ = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.example.host"
        )
        _ = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.example.host"
        )

        XCTAssertTrue(launcher.openedBundleIdentifiers.isEmpty)
    }

    // 5. Adapter timeout maps to deterministic error
    func testAdapterTimeoutMapsToDeterministicError() async throws {
        let installed = makeInstalledExtension(
            id: "ext-timeout",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.example.host",
                appexBundleID: "com.example.host.extension"
            )
        )
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")

        final class SlowAdapter: SumiNativeMessagingProtocolAdapter {
            let protocolIdentifier = "test.slow"
            func supports(hostBundleIdentifier _: String) -> Bool { true }
            func relayOneShotMessage(
                request: SumiNativeMessagingOneShotRequest,
                launcher: SumiHostApplicationLaunching,
                replyHandler: (Any?, (any Error)?) -> Void
            ) {
                _ = request
                _ = launcher
                _ = replyHandler
            }
            func connectPort(
                session: SumiNativeMessagingPortSession,
                launcher: SumiHostApplicationLaunching,
                completionHandler: ((any Error)?) -> Void
            ) {
                _ = session
                _ = launcher
                completionHandler(nil)
            }
            func relayPortMessage(session: SumiNativeMessagingPortSession, message: Any) -> Bool {
                _ = session
                _ = message
                return true
            }
        }

        let reply = await sendMessageReplyViaConnection(
            launcher: launcher,
            adapter: SlowAdapter(),
            installed: installed,
            hostBundleIdentifier: "com.example.host",
            replyTimeout: .milliseconds(50)
        )

        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(error.code, SumiNativeMessagingRelay.ErrorCode.relayTimeout.rawValue)
    }

    // 6. Adapter disconnect cleans sessions
    func testAdapterDisconnectCleansProfileScopedSessions() async {
        let profileId = UUID()
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.example.host"
        let adapter = SumiNativeMessagingFakePublicAdapter(supportedHosts: ["com.example.host"])
        let session = SumiNativeMessagingPortSession(
            port: port,
            adapter: adapter,
            extensionId: "ext-disconnect",
            profileId: profileId,
            hostBundleIdentifier: "com.example.host",
            resolverBucket: .explicitApplicationIdentifier,
            logDiagnostic: { _ in /* no-op */ },
            companionProtocolErrorProvider: {
                SumiNativeMessagingErrorMapper.relayError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: nil
                )
            }
        )
        _ = session
        port.simulateDisconnect()

        XCTAssertEqual(session.profileId, profileId)
        XCTAssertTrue(port.isDisconnected)
    }

    // 7. Disable/delete/module off closes sessions
    func testClearCompanionStateDisconnectsTrackedPortSessions() async throws {
        let profileId = UUID()
        let installed = makeInstalledExtension(
            id: "ext-clear",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.example.host",
                appexBundleID: "com.example.host.extension"
            )
        )
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let adapter = SumiNativeMessagingFakePublicAdapter(
            supportedHosts: ["com.example.host"],
            shouldLaunchOnConnect: false
        )
        let relay = makeRelay(launcher: launcher, adapters: [adapter])
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.example.host"

        let connectResult = await connectReply(
            relay: relay,
            port: port,
            installed: installed,
            profileId: profileId
        )
        XCTAssertNil(connectResult.error)
        XCTAssertFalse(port.isDisconnected)

        relay.clearCompanionState(forExtensionId: installed.id, profileId: profileId)

        XCTAssertTrue(port.isDisconnected)
    }

    func testRegistryResolvesByApplicationIdentifierAlias() {
        let adapter = SumiNativeMessagingFakePublicAdapter(
            supportedHosts: ["com.bitwarden.desktop"]
        )
        let registry = SumiNativeMessagingAdapterRegistry(adapters: [adapter])

        XCTAssertNotNil(registry.adapter(forApplicationIdentifier: "com.8bit.bitwarden"))
        XCTAssertNotNil(registry.adapter(forApplicationIdentifier: "com.8bit.bitwarden.desktop"))
        XCTAssertNotNil(registry.adapter(forHostBundleIdentifier: "com.8bit.bitwarden.desktop"))
        XCTAssertNotNil(registry.adapter(forProtocolIdentifier: adapter.protocolIdentifier))
        XCTAssertTrue(registry.isAdapterAvailable(forApplicationIdentifier: "com.8bit.bitwarden"))
        XCTAssertTrue(
            registry.isAdapterAvailable(
                forApplicationIdentifier: nil,
                hostBundleIdentifier: "com.8bit.bitwarden.desktop"
            )
        )
    }

    func testRelayDefaultAdapterRegistryIsInstanceScoped() {
        let first = SumiNativeMessagingRelay()
        let second = SumiNativeMessagingRelay()

        XCTAssertFalse(first.diagnosticsAdapterRegistry === second.diagnosticsAdapterRegistry)
        XCTAssertEqual(
            first.diagnosticsAdapterRegistry.registeredProtocolIdentifiers,
            [BitwardenNativeMessagingIdentifiers.protocolIdentifier]
        )
        XCTAssertEqual(
            second.diagnosticsAdapterRegistry.registeredProtocolIdentifiers,
            [BitwardenNativeMessagingIdentifiers.protocolIdentifier]
        )
    }

    // MARK: - Helpers

    private func makeRelay(
        launcher: MockHostLauncher,
        adapters: [SumiNativeMessagingProtocolAdapter]
    ) -> SumiNativeMessagingRelay {
        SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: adapters),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )
    }

    private func sendMessageReplyViaConnection(
        launcher: MockHostLauncher,
        adapter: SumiNativeMessagingProtocolAdapter,
        installed: InstalledExtension,
        hostBundleIdentifier: String,
        replyTimeout: Duration
    ) async -> (value: Any?, error: (any Error)?) {
        let detail = SumiCompanionAppResolutionDetail(
            requestedApplicationIdentifier: hostBundleIdentifier,
            resolvedBundleIdentifier: hostBundleIdentifier,
            isContainingApp: false,
            resolutionSource: .explicitApplicationIdentifier,
            appInstalled: true,
            protocolAdapterAvailable: true,
            launchAllowed: true,
            launchDecision: .allowed
        )
        let evaluation = SumiCompanionAppResolverResult.companionAppResolved(detail)
        let expectation = expectation(description: "connectionReply")
        var replyValue: Any?
        var replyError: (any Error)?
        SumiNativeMessagingConnection.relayOneShot(
            applicationIdentifier: hostBundleIdentifier,
            message: ["type": "ping"],
            extensionId: installed.id,
            evaluation: evaluation,
            adapter: adapter,
            launcher: launcher,
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            logDiagnostic: { _ in /* no-op */ },
            replyHandler: { value, error in
                replyValue = value
                replyError = error
                expectation.fulfill()
            },
            replyTimeout: replyTimeout
        )
        await fulfillment(of: [expectation], timeout: 2)
        return (replyValue, replyError)
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

    private func connectReply(
        relay: SumiNativeMessagingRelay,
        port: MockNativeMessagingPort,
        installed: InstalledExtension,
        profileId: UUID? = nil
    ) async -> (session: SumiNativeMessagingPortSession?, error: (any Error)?) {
        let expectation = expectation(description: "nativeMessagingConnect")
        var connectError: (any Error)?
        var session: SumiNativeMessagingPortSession?
        _ = relay.handleConnect(
            port: port,
            extensionId: installed.id,
            profileId: profileId,
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
            .appendingPathComponent("SumiNMAdapter.\(UUID().uuidString)", isDirectory: true)
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
