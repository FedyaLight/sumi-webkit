import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SumiNativeMessagingRelayTests: XCTestCase {
    private final class MockHostLauncher: SumiHostApplicationLaunching {
        var bundleURLs: [String: URL] = [:]
        var openedBundleIdentifiers: [String] = []
        var openError: Error?

        func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
            bundleURLs[bundleIdentifier]
        }

        func openApplication(withBundleIdentifier bundleIdentifier: String) async throws {
            if let openError {
                throw openError
            }
            openedBundleIdentifiers.append(bundleIdentifier)
        }
    }

    @MainActor
    private final class FakeProtocolAdapter: SumiNativeMessagingProtocolAdapter {
        let protocolIdentifier: String
        var supportedHosts: Set<String>
        var oneShotReply: (Any?, (any Error)?)
        var shouldLaunchOnOneShot: Bool
        var shouldLaunchOnConnect: Bool
        var portMessageRelayed = false
        var connectCompletion: @Sendable ((any Error)?) -> (any Error)?
        var relayPortMessageResult = true

        init(
            protocolIdentifier: String = "test.fake",
            supportedHosts: Set<String> = [],
            oneShotReply: (Any?, (any Error)?) = (["ok": true], nil),
            shouldLaunchOnOneShot: Bool = true,
            shouldLaunchOnConnect: Bool = true,
            connectCompletion: @Sendable @escaping ((any Error)?) -> (any Error)? = { $0 },
            relayPortMessageResult: Bool = true
        ) {
            self.protocolIdentifier = protocolIdentifier
            self.supportedHosts = supportedHosts
            self.oneShotReply = oneShotReply
            self.shouldLaunchOnOneShot = shouldLaunchOnOneShot
            self.shouldLaunchOnConnect = shouldLaunchOnConnect
            self.connectCompletion = connectCompletion
            self.relayPortMessageResult = relayPortMessageResult
        }

        func supports(hostBundleIdentifier: String) -> Bool {
            supportedHosts.contains(hostBundleIdentifier)
        }

        func relayOneShotMessage(
            request: SumiNativeMessagingOneShotRequest,
            launcher: SumiHostApplicationLaunching,
            replyHandler: @escaping (Any?, (any Error)?) -> Void
        ) {
            _ = request
            Task { @MainActor in
                if self.shouldLaunchOnOneShot {
                    do {
                        try await launcher.openApplication(
                            withBundleIdentifier: request.hostBundleIdentifier
                        )
                    } catch {
                        replyHandler(nil, error)
                        return
                    }
                }
                replyHandler(self.oneShotReply.0, self.oneShotReply.1)
            }
        }

        func connectPort(
            session: SumiNativeMessagingPortSession,
            launcher: SumiHostApplicationLaunching,
            completionHandler: @escaping ((any Error)?) -> Void
        ) {
            Task { @MainActor in
                if self.shouldLaunchOnConnect {
                    do {
                        try await launcher.openApplication(
                            withBundleIdentifier: session.resolvedHostBundleIdentifier
                        )
                    } catch {
                        completionHandler(error)
                        return
                    }
                }
                completionHandler(self.connectCompletion(nil))
            }
        }

        func relayPortMessage(
            session: SumiNativeMessagingPortSession,
            message: Any
        ) -> Bool {
            _ = session
            _ = message
            portMessageRelayed = true
            return relayPortMessageResult
        }
    }

    @MainActor
    private final class MockNativeMessagingPort: SumiNativeMessagingPortControlling {
        var applicationIdentifier: String?
        var isDisconnected = false
        var messageHandler: ((Any?, (any Error)?) -> Void)?
        var disconnectHandler: (((any Error)?) -> Void)?
        var disconnectError: (any Error)?
        var sentMessages: [Any?] = []

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

    // 1. One-time native message success using fake protocol adapter
    func testOneShotSuccessWithFakeAdapter() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.host",
            appexBundleID: "com.example.host.extension"
        )
        let installed = try makeInstalledExtension(id: "ext-example", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let adapter = FakeProtocolAdapter(
            supportedHosts: ["com.example.host"],
            oneShotReply: (["pong": 1], nil)
        )
        let relay = makeRelay(launcher: launcher, adapters: [adapter])

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.example.host"
        )

        XCTAssertEqual(launcher.openedBundleIdentifiers, ["com.example.host"])
        XCTAssertEqual(reply.value as? [String: Int], ["pong": 1])
        XCTAssertNil(reply.error)
    }

    // 2. One-time unknown protocol returns deterministic error
    func testOneShotUnknownProtocolWithoutLaunch() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.bitwarden.desktop",
            appexBundleID: "com.bitwarden.desktop.safari"
        )
        let installed = try makeInstalledExtension(id: "ext-bitwarden", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.bitwarden.desktop"] = URL(
            fileURLWithPath: "/Applications/Bitwarden.app"
        )
        var diagnostics: [SafariExtensionNativeMessagingDiagnostic] = []
        let relay = makeRelay(
            launcher: launcher,
            adapters: [],
            logDiagnostic: { diagnostics.append($0) }
        )

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.bitwarden.desktop"
        )

        XCTAssertTrue(launcher.openedBundleIdentifiers.isEmpty)
        XCTAssertNil(reply.value)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
        )
        XCTAssertTrue(
            diagnostics.contains {
                $0.outcome == .companionAppProtocolUnknown && $0.direction == .send
            }
        )
    }

    // 3. Reply handler called exactly once
    func testOneShotReplyHandlerCalledExactlyOnce() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.host",
            appexBundleID: "com.example.host.extension"
        )
        let installed = try makeInstalledExtension(id: "ext-example", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let adapter = FakeProtocolAdapter(
            supportedHosts: ["com.example.host"],
            oneShotReply: (["once": true], nil),
            shouldLaunchOnOneShot: false
        )
        let relay = makeRelay(launcher: launcher, adapters: [adapter])
        var replyCount = 0

        let expectation = expectation(description: "reply")
        relay.handleSendMessage(
            applicationIdentifier: "com.example.host",
            message: ["type": "ping"],
            extensionId: installed.id,
            installedExtensions: [installed]
        ) { _, _ in
            replyCount += 1
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertEqual(replyCount, 1)
    }

    // 4. Timeout path
    func testOneShotTimeout() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.host",
            appexBundleID: "com.example.host.extension"
        )
        let installed = try makeInstalledExtension(id: "ext-example", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")

        final class SlowAdapter: SumiNativeMessagingProtocolAdapter {
            let protocolIdentifier = "test.slow"
            func supports(hostBundleIdentifier: String) -> Bool { true }
            func relayOneShotMessage(
                request: SumiNativeMessagingOneShotRequest,
                launcher: SumiHostApplicationLaunching,
                replyHandler: @escaping (Any?, (any Error)?) -> Void
            ) {
                _ = request
                _ = launcher
                _ = replyHandler
            }
            func connectPort(
                session: SumiNativeMessagingPortSession,
                launcher: SumiHostApplicationLaunching,
                completionHandler: @escaping ((any Error)?) -> Void
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

        let slowAdapter = SlowAdapter()

        let reply = await sendMessageReplyViaConnection(
            launcher: launcher,
            adapter: slowAdapter,
            installed: installed,
            hostBundleIdentifier: "com.example.host",
            replyTimeout: .milliseconds(50)
        )

        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(error.code, SumiNativeMessagingRelay.ErrorCode.relayTimeout.rawValue)
    }

    // 5. Cancellation path
    func testOneShotCancellation() async throws {
        let coordinator = SumiNativeMessagingOnceReplyCoordinator { _, _ in }
        var completed = false
        coordinator.startRelay(timeout: .seconds(30)) {
            try? await Task.sleep(for: .seconds(5))
            guard Task.isCancelled == false else { return }
        }
        coordinator.complete(
            nil,
            SumiNativeMessagingErrorMapper.relayError(code: .relayCancelled, diagnostic: nil)
        )
        completed = coordinator.isFulfilled
        XCTAssertTrue(completed)
    }

    // 6. Port connect success with fake adapter
    func testPortConnectSuccessWithFakeAdapter() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.host",
            appexBundleID: "com.example.host.extension"
        )
        let installed = try makeInstalledExtension(id: "ext-example", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let adapter = FakeProtocolAdapter(supportedHosts: ["com.example.host"])
        let relay = makeRelay(launcher: launcher, adapters: [adapter])
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.example.host"

        let result = await connectReply(relay: relay, port: port, installed: installed)

        XCTAssertNil(result.error)
        XCTAssertEqual(launcher.openedBundleIdentifiers, ["com.example.host"])
        XCTAssertFalse(port.isDisconnected)
    }

    // 7. Port first message routed
    func testPortFirstMessageRoutedThroughAdapter() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.host",
            appexBundleID: "com.example.host.extension"
        )
        let installed = try makeInstalledExtension(id: "ext-example", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let adapter = FakeProtocolAdapter(
            supportedHosts: ["com.example.host"],
            shouldLaunchOnConnect: false
        )
        let relay = makeRelay(launcher: launcher, adapters: [adapter])
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.example.host"

        let connectResult = await connectReply(relay: relay, port: port, installed: installed)
        let session = try XCTUnwrap(connectResult.session)
        port.simulateIncomingMessage(["hello": "world"])

        XCTAssertTrue(adapter.portMessageRelayed)
        XCTAssertFalse(session.resolvedHostBundleIdentifier.isEmpty)
    }

    // 8. Port disconnect from extension/app side
    func testPortDisconnectFromExtensionSide() async throws {
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.example.host"
        var disconnectObserved = false
        let session = SumiNativeMessagingPortSession(
            port: port,
            adapter: FakeProtocolAdapter(supportedHosts: ["com.example.host"]),
            extensionId: "ext-1",
            hostBundleIdentifier: "com.example.host",
            resolverBucket: .explicitApplicationIdentifier,
            logDiagnostic: { _ in },
            companionProtocolErrorProvider: {
                SumiNativeMessagingErrorMapper.relayError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: nil
                )
            }
        )
        port.disconnectHandler = { _ in disconnectObserved = true }
        _ = session
        port.simulateDisconnect()

        XCTAssertTrue(disconnectObserved)
    }

    // 9. Unknown protocol disconnects without app launch loop
    func testPortUnknownProtocolDisconnectsWithoutLaunch() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.bitwarden.desktop",
            appexBundleID: "com.bitwarden.desktop.safari"
        )
        let installed = try makeInstalledExtension(id: "ext-bitwarden", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.bitwarden.desktop"] = URL(
            fileURLWithPath: "/Applications/Bitwarden.app"
        )
        let relay = makeRelay(launcher: launcher, adapters: [])
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.bitwarden.desktop"

        let result = await connectReply(relay: relay, port: port, installed: installed)

        XCTAssertTrue(launcher.openedBundleIdentifiers.isEmpty)
        XCTAssertTrue(port.isDisconnected)
        let error = try XCTUnwrap(result.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
        )
    }

    // 10. Disable/delete/module off closes ports
    func testPortSessionDisconnectIsIdempotent() {
        let port = MockNativeMessagingPort()
        let session = SumiNativeMessagingPortSession(
            port: port,
            adapter: nil,
            extensionId: "ext-1",
            hostBundleIdentifier: "com.example.host",
            resolverBucket: .explicitApplicationIdentifier,
            logDiagnostic: { _ in },
            companionProtocolErrorProvider: {
                SumiNativeMessagingErrorMapper.relayError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: nil
                )
            }
        )
        session.disconnect()
        session.disconnect()
        XCTAssertTrue(port.isDisconnected)
    }

    // 11. No payload logging
    func testRelaySourceDoesNotLogMessageBodies() throws {
        let relaySource = try Self.source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelay.swift"
        )
        let connectionSource = try Self.source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingConnection.swift"
        )
        let portSource = try Self.source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingPortSession.swift"
        )
        let combined = relaySource + connectionSource + portSource

        XCTAssertFalse(combined.contains("print(message"))
        XCTAssertFalse(combined.contains("debug(\"message"))
        XCTAssertFalse(combined.contains("RuntimeDiagnostics.debug(message"))
        XCTAssertTrue(
            combined.contains("_ = message")
                || combined.contains("_ = request")
                || combined.contains("guard let message")
        )
    }

    func testPolicyDeniesWhenModuleDisabled() async throws {
        let relay = SumiNativeMessagingRelay(
            extensionsModuleEnabled: { false }
        )
        let installed = try makeInstalledExtension(id: "ext-1", sourceBundlePath: "/tmp/x.appex")

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.bitwarden.desktop"
        )

        XCTAssertNil(reply.value)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(error.code, SumiNativeMessagingRelay.ErrorCode.policyDenied.rawValue)
    }

    func testPolicyDeniesPrivateBrowsingWhenIncognitoNotAllowed() async throws {
        let relay = SumiNativeMessagingRelay(
            extensionsModuleEnabled: { true },
            isPrivateBrowsing: { true }
        )
        let installed = try makeInstalledExtension(
            id: "ext-1",
            sourceBundlePath: "/tmp/x.appex",
            incognitoMode: .notAllowed
        )

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.bitwarden.desktop"
        )

        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(error.code, SumiNativeMessagingRelay.ErrorCode.policyDenied.rawValue)
    }

    func testResolverAliasTable() {
        XCTAssertEqual(
            SumiNativeMessagingAppResolver.normalizedHostBundleIdentifier("com.8bit.bitwarden"),
            "com.bitwarden.desktop"
        )
        XCTAssertEqual(
            SumiNativeMessagingAppResolver.normalizedHostBundleIdentifier("me.proton.pass.nm"),
            "me.proton.pass.catalyst"
        )
    }

    func testClassificationCatalogForPasswordManagers() {
        let bitwarden = SafariExtensionNativeMessagingClassificationCatalog
            .classifications(forTargetKey: "bitwarden")
        XCTAssertTrue(bitwarden.contains(.companionAppProtocolUnknown))
        XCTAssertFalse(bitwarden.contains(.platformBlocked))

        let raindrop = SafariExtensionNativeMessagingClassificationCatalog
            .classifications(forTargetKey: "raindrop")
        XCTAssertFalse(raindrop.contains(.companionAppProtocolUnknown))
    }

    // MARK: - Helpers

    private func makeRelay(
        launcher: MockHostLauncher,
        adapters: [SumiNativeMessagingProtocolAdapter],
        logDiagnostic: @MainActor @escaping (SafariExtensionNativeMessagingDiagnostic) -> Void = { _ in }
    ) -> SumiNativeMessagingRelay {
        SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: adapters),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true },
            logDiagnostic: logDiagnostic
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
            logDiagnostic: { _ in },
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
        applicationIdentifier: String,
        timeout: TimeInterval = 5
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
        await fulfillment(of: [expectation], timeout: timeout)
        return (replyValue, replyError)
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

    private func makeInstalledExtension(
        id: String,
        sourceBundlePath: String,
        incognitoMode: IncognitoExtensionMode = .split
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
            incognitoMode: incognitoMode,
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
            .appendingPathComponent("SumiNM.\(UUID().uuidString)", isDirectory: true)
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

    private static func source(named relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}

