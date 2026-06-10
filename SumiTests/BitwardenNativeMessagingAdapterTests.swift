import SwiftData
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

    func testPortGetBiometricsStatusHandledLocallyWithoutDesktopRelay() async throws {
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
        XCTAssertTrue(fake.sentMessages.isEmpty)
        XCTAssertEqual(port.repliesSent.count, 1)
        let reply = try XCTUnwrap(port.repliesSent.first as? [String: Any])
        XCTAssertEqual(reply["command"] as? String, "getBiometricsStatus")
        XCTAssertEqual(reply["messageId"] as? Int, 1)
        XCTAssertNotNil(reply["response"])
    }

    func testSetupEncryptionRelaysToDesktopProxy() async throws {
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
                "command": "setupEncryption",
                "messageId": 1,
                "publicKey": "abc",
                "userId": "user-1",
            ]
        )

        XCTAssertTrue(relayed)
        XCTAssertEqual(fake.sentMessages.count, 1)
        XCTAssertEqual(
            (fake.sentMessages.first?["message"] as? [String: Any])?["command"] as? String,
            "setupEncryption"
        )
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

        let handshakeError = await connectAndWaitForHandshakeDisconnect(
            adapter: adapter,
            session: session,
            launcher: launcher,
            port: port
        )
        let nsError = try XCTUnwrap(handshakeError as NSError?)
        XCTAssertEqual(
            nsError.code,
            SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
        )
        XCTAssertEqual(
            nsError.localizedDescription,
            "Bitwarden Desktop returned a malformed native messaging reply."
        )
    }

    func testDesktopIntegrationDisabledReturnsSpecificErrorMessage() async throws {
        let fake = BitwardenFakeDesktopProxyTransport(mode: .handshakeDisconnected)
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { fake },
            handshakeTimeout: .milliseconds(200)
        )
        let launcher = makeLauncherWithProxy()
        let port = MockNativeMessagingPort()
        let session = makeSession(port: port, adapter: adapter)

        let handshakeError = await connectAndWaitForHandshakeDisconnect(
            adapter: adapter,
            session: session,
            launcher: launcher,
            port: port
        )
        let nsError = try XCTUnwrap(handshakeError as NSError?)
        XCTAssertEqual(
            nsError.code,
            SumiNativeMessagingRelay.ErrorCode.hostLaunchFailed.rawValue
        )
        XCTAssertEqual(
            nsError.localizedDescription,
            "Bitwarden Desktop browser integration is disabled."
        )
        XCTAssertEqual(
            nsError.userInfo[BitwardenDesktopProxyTransportErrorMapper.failureBucketUserInfoKey] as? String,
            BitwardenDesktopTransportOutcome.browserIntegrationDisabled.rawValue
        )
    }

    func testUnsupportedOneShotCommandReturnsSpecificErrorMessage() async throws {
        let adapter = BitwardenNativeMessagingAdapter()
        let launcher = makeLauncherWithProxy()
        let expectation = expectation(description: "unsupportedOneShot")
        var replyError: (any Error)?

        adapter.relayOneShotMessage(
            request: SumiNativeMessagingOneShotRequest(
                applicationIdentifier: "com.8bit.bitwarden",
                extensionId: "ext-bitwarden",
                hostBundleIdentifier: "com.bitwarden.desktop",
                resolverBucket: .knownCompanionAlias,
                message: ["command": "unknownCommand"]
            ),
            launcher: launcher
        ) { _, error in
            replyError = error
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2)
        let nsError = try XCTUnwrap(replyError as NSError?)
        XCTAssertEqual(
            nsError.localizedDescription,
            "Unsupported Bitwarden native messaging command."
        )
        XCTAssertNotEqual(
            nsError.localizedDescription,
            "Companion host application messaging protocol is not implemented in Sumi."
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

        let handshakeError = await connectAndWaitForHandshakeDisconnect(
            adapter: adapter,
            session: session,
            launcher: launcher,
            port: port
        )
        let nsError = try XCTUnwrap(handshakeError as NSError?)
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
            .browserIntegrationDisabled
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

    func testUnsupportedPortCommandRepliesWithoutDesktopRelay() async throws {
        let fake = BitwardenFakeDesktopProxyTransport(mode: .handshakeConnected)
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { fake },
            handshakeTimeout: .milliseconds(200),
            replyTimeout: .milliseconds(80)
        )
        let launcher = makeLauncherWithProxy()
        let port = MockNativeMessagingPort()
        let session = makeSession(port: port, adapter: adapter)

        _ = await connect(adapter: adapter, session: session, launcher: launcher)

        let relayed = adapter.relayPortMessage(
            session: session,
            message: [
                "command": "vaultExport",
                "messageId": 99,
            ]
        )

        XCTAssertTrue(relayed)
        XCTAssertTrue(fake.sentMessages.isEmpty)
        XCTAssertEqual(port.repliesSent.count, 1)
        let reply = try XCTUnwrap(port.repliesSent.first as? [String: Any])
        XCTAssertEqual(reply["command"] as? String, "vaultExport")
        XCTAssertEqual(reply["messageId"] as? Int, 99)
        XCTAssertEqual(reply["response"] as? Bool, false)
        XCTAssertFalse(port.isDisconnected)

        try await Task.sleep(for: .milliseconds(120))
        XCTAssertFalse(port.isDisconnected)
    }

    func testBiometricUnlockHandledLocallyViaPort() async throws {
        let fake = BitwardenFakeDesktopProxyTransport(mode: .handshakeConnected)
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { fake },
            handshakeTimeout: .milliseconds(200)
        )
        let launcher = makeLauncherWithProxy()
        let port = MockNativeMessagingPort()
        let session = makeSession(port: port, adapter: adapter)

        _ = await connect(adapter: adapter, session: session, launcher: launcher)
        _ = adapter.relayPortMessage(
            session: session,
            message: [
                "command": "biometricUnlock",
                "messageId": 2,
            ]
        )

        XCTAssertTrue(fake.sentMessages.isEmpty)
        XCTAssertEqual(port.repliesSent.count, 1)
        let reply = try XCTUnwrap(port.repliesSent.first as? [String: Any])
        XCTAssertEqual(reply["response"] as? String, "not enabled")
    }

    func testDisconnectCancelsPendingReplyTimeout() async throws {
        let fake = BitwardenFakeDesktopProxyTransport(mode: .handshakeConnected)
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { fake },
            handshakeTimeout: .milliseconds(200),
            replyTimeout: .milliseconds(80)
        )
        let launcher = makeLauncherWithProxy()
        let port = MockNativeMessagingPort()
        let session = makeSession(port: port, adapter: adapter)

        _ = await connect(adapter: adapter, session: session, launcher: launcher)
        _ = adapter.relayPortMessage(
            session: session,
            message: [
                "command": "setupEncryption",
                "messageId": 3,
            ]
        )
        XCTAssertEqual(fake.sentMessages.count, 1)
        fake.simulateDisconnect()

        XCTAssertTrue(port.isDisconnected)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(port.repliesSent.count, 0)
    }

    func testRepeatedUnsupportedCommandsDoNotAccumulateTransportSends() async throws {
        let fake = BitwardenFakeDesktopProxyTransport(mode: .handshakeConnected)
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { fake },
            handshakeTimeout: .milliseconds(200)
        )
        let launcher = makeLauncherWithProxy()
        let port = MockNativeMessagingPort()
        let session = makeSession(port: port, adapter: adapter)

        _ = await connect(adapter: adapter, session: session, launcher: launcher)

        for index in 0..<5 {
            _ = adapter.relayPortMessage(
                session: session,
                message: [
                    "command": "unknownCommand\(index)",
                    "messageId": index,
                ]
            )
        }

        XCTAssertTrue(fake.sentMessages.isEmpty)
        XCTAssertEqual(port.repliesSent.count, 5)
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

    func testRegistryResolvesAllBitwardenPublicApplicationIdentifiers() {
        let registry = SumiNativeMessagingAdapterRegistry(adapters: [
            BitwardenNativeMessagingAdapter(),
        ])

        for applicationIdentifier in BitwardenNativeMessagingIdentifiers.publicApplicationIdentifiers {
            XCTAssertNotNil(
                registry.adapter(forApplicationIdentifier: applicationIdentifier),
                "Expected adapter for \(applicationIdentifier)"
            )
            XCTAssertTrue(registry.isAdapterAvailable(forApplicationIdentifier: applicationIdentifier))
        }
    }

    func testRegistryResolvesByLegacyContainingHostBundleIdentifier() {
        let registry = SumiNativeMessagingAdapterRegistry(adapters: [
            BitwardenNativeMessagingAdapter(),
        ])

        XCTAssertNotNil(
            registry.adapter(forHostBundleIdentifier: "com.8bit.bitwarden.desktop")
        )
        XCTAssertTrue(
            registry.isAdapterAvailable(
                forApplicationIdentifier: nil,
                hostBundleIdentifier: "com.8bit.bitwarden.desktop"
            )
        )
    }

    func testRelaySelectsBitwardenAdapterForAllPublicIdentifiers() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.bitwarden.desktop",
            appexBundleID: "com.bitwarden.desktop.safari"
        )
        let installed = try makeInstalledExtension(id: "ext-bitwarden", sourceBundlePath: appexPath)
        let launcher = makeLauncherWithProxy()
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { BitwardenFakeDesktopProxyTransport(mode: .handshakeConnected) },
            handshakeTimeout: .milliseconds(200)
        )

        for applicationIdentifier in BitwardenNativeMessagingIdentifiers.publicApplicationIdentifiers {
            var diagnostics: [SafariExtensionNativeMessagingDiagnostic] = []
            let relay = SumiNativeMessagingRelay(
                launcher: launcher,
                adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [adapter]),
                launchPolicy: SumiCompanionAppLaunchPolicy(),
                loopGuard: SumiNativeMessagingRelayLoopGuard(),
                extensionsModuleEnabled: { true },
                logDiagnostic: { diagnostics.append($0) }
            )
            let port = MockNativeMessagingPort()
            port.applicationIdentifier = applicationIdentifier

            let connectResult = await connectReply(
                relay: relay,
                port: port,
                installed: installed
            )

            XCTAssertNil(
                connectResult.error,
                "Expected connect success for \(applicationIdentifier)"
            )
            XCTAssertTrue(
                diagnostics.contains { $0.adapterSelected == true },
                "Expected adapterSelected=true for \(applicationIdentifier)"
            )
            XCTAssertTrue(
                diagnostics.contains {
                    $0.adapterIdentifier == BitwardenNativeMessagingIdentifiers.protocolIdentifier
                }
            )
        }
    }

    func testContainingAppLegacyBundleSelectsBitwardenAdapterWithoutExplicitAppId() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.8bit.bitwarden.desktop",
            appexBundleID: "com.8bit.bitwarden.desktop.safari"
        )
        let installed = try makeInstalledExtension(id: "ext-bitwarden-legacy", sourceBundlePath: appexPath)
        let launcher = makeLauncherWithProxy()
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { BitwardenFakeDesktopProxyTransport(mode: .handshakeConnected) },
            handshakeTimeout: .milliseconds(200)
        )
        var diagnostics: [SafariExtensionNativeMessagingDiagnostic] = []
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [adapter]),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true },
            logDiagnostic: { diagnostics.append($0) }
        )

        let evaluation = SumiCompanionAppResolver.evaluate(
            requestedApplicationIdentifier: nil,
            extensionId: installed.id,
            installedExtensions: [installed],
            importStore: SafariExtensionImportStore(defaults: makeDefaults()),
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [adapter])
        )

        XCTAssertEqual(evaluation.detail?.resolvedBundleIdentifier, "com.bitwarden.desktop")
        XCTAssertTrue(evaluation.detail?.protocolAdapterAvailable == true)

        let port = MockNativeMessagingPort()
        let connectResult = await connectReply(relay: relay, port: port, installed: installed)

        XCTAssertNil(connectResult.error)
        XCTAssertTrue(diagnostics.contains { $0.adapterSelected == true })
    }

    func testSupportedBitwardenSendAfterConnectNeverReturnsGenericProtocolUnknown() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.bitwarden.desktop",
            appexBundleID: "com.bitwarden.desktop.safari"
        )
        let installed = try makeInstalledExtension(id: "ext-bitwarden-send", sourceBundlePath: appexPath)
        let launcher = makeLauncherWithProxy()
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { BitwardenFakeDesktopProxyTransport(mode: .handshakeConnected) },
            handshakeTimeout: .milliseconds(200)
        )
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [adapter]),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )

        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.8bit.bitwarden"
        let connectResult = await connectReply(relay: relay, port: port, installed: installed)
        XCTAssertNil(connectResult.error)

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.8bit.bitwarden",
            message: [
                "command": "getBiometricsStatus",
                "messageId": 1,
            ]
        )

        XCTAssertNotNil(reply.value)
        XCTAssertNil(reply.error)
    }

    func testRelayPreservesBitwardenSpecificErrorDescription() async throws {
        let adapter = BitwardenNativeMessagingAdapter()
        let launcher = makeLauncherWithProxy()
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [adapter]),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )
        let installed = try makeInstalledExtension(
            id: "ext-bitwarden-desc",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.bitwarden.desktop",
                appexBundleID: "com.bitwarden.desktop.safari"
            )
        )

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.bitwarden.desktop",
            message: ["command": "unknownCommand"]
        )

        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.localizedDescription,
            "Unsupported Bitwarden native messaging command."
        )
        XCTAssertNotEqual(
            error.localizedDescription,
            "Companion host application messaging protocol is not implemented in Sumi."
        )
    }

    func testBitwardenPublicOneShotCommandsNeverReturnGenericProtocolUnknown() async throws {
        let adapter = BitwardenNativeMessagingAdapter()
        let launcher = makeLauncherWithProxy()
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [adapter]),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )
        let installed = try makeInstalledExtension(
            id: "ext-bitwarden-oneshot",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.bitwarden.desktop",
                appexBundleID: "com.bitwarden.desktop.safari"
            )
        )

        let commands = [
            "getBiometricsStatus",
            "getBiometricsStatusForUser",
            "authenticateWithBiometrics",
            "unlockWithBiometricsForUser",
            "biometricUnlockAvailable",
            "biometricUnlock",
            "canEnableBiometricUnlock",
            "showPopover",
            "readFromClipboard",
            "copyToClipboard",
        ]

        for command in commands {
            var message: [String: Any] = [
                "command": command,
                "messageId": 1,
                "userId": "user-1",
            ]
            if command == "copyToClipboard" {
                message["data"] = "copied"
            }
            let reply = await sendMessageReply(
                relay: relay,
                installed: installed,
                applicationIdentifier: "com.bitwarden.desktop",
                message: message
            )
            XCTAssertNil(
                reply.error,
                "Expected success for \(command), got \(String(describing: reply.error))"
            )
            XCTAssertNotNil(reply.value, "Expected value for \(command)")
        }
    }

    func testShowPopoverOneShotMatchesSafariWebExtensionHandler() async throws {
        let adapter = BitwardenNativeMessagingAdapter()
        let expectation = expectation(description: "showPopover")
        var replyValue: Any?

        adapter.relayOneShotMessage(
            request: SumiNativeMessagingOneShotRequest(
                applicationIdentifier: "com.8bit.bitwarden",
                extensionId: "ext-bitwarden",
                hostBundleIdentifier: "com.bitwarden.desktop",
                resolverBucket: .knownCompanionAlias,
                message: ["command": "showPopover", "data": NSNull()]
            ),
            launcher: makeLauncherWithProxy()
        ) { value, error in
            replyValue = value
            XCTAssertNil(error)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertTrue(replyValue is NSNull)
    }

    func testSleepOneShotCompletesAsynchronously() async throws {
        let priorDelay = BitwardenSafariOneShotHandler.sleepDelay
        defer { BitwardenSafariOneShotHandler.sleepDelay = priorDelay }
        BitwardenSafariOneShotHandler.sleepDelay = .milliseconds(50)

        let adapter = BitwardenNativeMessagingAdapter()
        let expectation = expectation(description: "sleep")
        var replyValue: Any?

        adapter.relayOneShotMessage(
            request: SumiNativeMessagingOneShotRequest(
                applicationIdentifier: "com.8bit.bitwarden",
                extensionId: "ext-bitwarden",
                hostBundleIdentifier: "com.bitwarden.desktop",
                resolverBucket: .knownCompanionAlias,
                message: ["command": "sleep"]
            ),
            launcher: makeLauncherWithProxy()
        ) { value, error in
            replyValue = value
            XCTAssertNil(error)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertTrue(replyValue is NSNull)
    }

    func testPopupOpenPortSequenceGetBiometricsStatusBeforeHandshake() async throws {
        let fake = BitwardenFakeDesktopProxyTransport(mode: .handshakeConnected, startDelay: .milliseconds(150))
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { fake },
            handshakeTimeout: .milliseconds(500)
        )
        let launcher = makeLauncherWithProxy()
        let port = MockNativeMessagingPort()
        let session = makeSession(port: port, adapter: adapter)

        let connectExpectation = expectation(description: "connectCompletesEarly")
        adapter.connectPort(session: session, launcher: launcher) { _ in
            connectExpectation.fulfill()
        }
        await fulfillment(of: [connectExpectation], timeout: 1)

        let relayed = adapter.relayPortMessage(
            session: session,
            message: [
                "command": "getBiometricsStatus",
                "messageId": 42,
            ]
        )
        XCTAssertTrue(relayed)
        XCTAssertTrue(fake.sentMessages.isEmpty)
        XCTAssertEqual(port.repliesSent.count, 1)
    }

    func testConnectCompletesBeforeHandshakeAcceptsEarlyPortMessage() async throws {
        let fake = BitwardenFakeDesktopProxyTransport(mode: .handshakeConnected, startDelay: .milliseconds(150))
        let adapter = BitwardenNativeMessagingAdapter(
            transportFactory: { fake },
            handshakeTimeout: .milliseconds(500)
        )
        let launcher = makeLauncherWithProxy()
        let port = MockNativeMessagingPort()
        let session = makeSession(port: port, adapter: adapter)

        let connectExpectation = expectation(description: "connectCompletesEarly")
        var connectError: (any Error)?
        adapter.connectPort(session: session, launcher: launcher) { error in
            connectError = error
            connectExpectation.fulfill()
        }
        await fulfillment(of: [connectExpectation], timeout: 1)
        XCTAssertNil(connectError)

        let relayed = adapter.relayPortMessage(
            session: session,
            message: [
                "command": "setupEncryption",
                "messageId": 42,
                "publicKey": "abc",
                "userId": "user-1",
            ]
        )
        XCTAssertTrue(relayed)

        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(fake.sentMessages.count, 1)
    }

    func testDelegateNativeMessagingSelectorsVisibleToObjC() throws {
        let container = try ModelContainer(
            for: ExtensionEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let manager = ExtensionManager(
            context: ModelContext(container),
            initialProfile: nil
        )
        XCTAssertTrue(
            manager.responds(
                to: NSSelectorFromString(
                    "webExtensionController:sendMessage:toApplicationWithIdentifier:forExtensionContext:replyHandler:"
                )
            )
        )
        XCTAssertTrue(
            manager.responds(
                to: NSSelectorFromString(
                    "webExtensionController:connectUsingMessagePort:forExtensionContext:completionHandler:"
                )
            )
        )
    }

    func testDelegateImplementsWebKitNativeMessagingSelectors() throws {
        let delegateSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift"
        )
        XCTAssertTrue(
            delegateSource.contains(
                "func webExtensionController(\n        _ controller: WKWebExtensionController,\n        sendMessage message: Any,\n        toApplicationWithIdentifier applicationIdentifier: String?,"
            )
        )
        XCTAssertTrue(
            delegateSource.contains(
                "func webExtensionController(\n        _ controller: WKWebExtensionController,\n        connectUsing port: WKWebExtension.MessagePort,"
            )
        )
    }

    func testUnsupportedHostFailsSafelyWithoutLaunch() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.vendor.unknown.desktop",
            appexBundleID: "com.vendor.unknown.desktop.safari"
        )
        let installed = try makeInstalledExtension(id: "ext-unknown", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.vendor.unknown.desktop"] = URL(
            fileURLWithPath: "/Applications/Unknown.app"
        )
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [BitwardenNativeMessagingAdapter()]),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.vendor.unknown.desktop"
        )

        XCTAssertTrue(launcher.openedBundleIdentifiers.isEmpty)
        XCTAssertNil(reply.value)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
        )
        XCTAssertEqual(
            error.localizedDescription,
            "Companion host application messaging protocol is not implemented in Sumi."
        )
    }

    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let suiteName = "BitwardenNativeMessagingAdapterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
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

    private func connectAndWaitForHandshakeDisconnect(
        adapter: BitwardenNativeMessagingAdapter,
        session: SumiNativeMessagingPortSession,
        launcher: MockHostLauncher,
        port: MockNativeMessagingPort
    ) async -> (any Error)? {
        let connectError = await connect(adapter: adapter, session: session, launcher: launcher)
        XCTAssertNil(connectError)

        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            await Task.yield()
            if port.isDisconnected {
                return port.disconnectError
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }

    private func sendMessageReply(
        relay: SumiNativeMessagingRelay,
        installed: InstalledExtension,
        applicationIdentifier: String,
        message: Any = ["type": "ping"]
    ) async -> (value: Any?, error: (any Error)?) {
        let expectation = expectation(description: "nativeMessagingReply")
        var replyValue: Any?
        var replyError: (any Error)?
        relay.handleSendMessage(
            applicationIdentifier: applicationIdentifier,
            message: message,
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
