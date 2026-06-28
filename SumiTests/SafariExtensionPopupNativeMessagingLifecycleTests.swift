import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionPopupNativeMessagingLifecycleTests: XCTestCase {
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

    private final class SlowOneShotAdapter: SumiNativeMessagingProtocolAdapter {
        let protocolIdentifier = "test.slow"
        private let sleepDuration: Duration

        init(sleepDuration: Duration = .milliseconds(500)) {
            self.sleepDuration = sleepDuration
        }

        func supports(hostBundleIdentifier: String) -> Bool {
            hostBundleIdentifier == "com.example.host"
        }

        func relayOneShotMessage(
            request _: SumiNativeMessagingOneShotRequest,
            launcher _: SumiHostApplicationLaunching,
            replyHandler: @escaping (Any?, (any Error)?) -> Void
        ) {
            Task { @MainActor in
                try? await Task.sleep(for: sleepDuration)
                guard Task.isCancelled == false else { return }
                replyHandler(["ok": true], nil)
            }
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

    override func setUp() {
        super.setUp()
        SumiNativeMessagingRuntimeCounters.resetForTesting()
    }

    func testGenericPopupCloseReleasesPortAndAllowsReconnect() async throws {
        let installed = try makeInstalledExtension(
            id: "ext-generic-popup",
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
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [adapter]),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )

        let firstPort = MockNativeMessagingPort()
        firstPort.applicationIdentifier = "com.example.host"
        _ = await connectReply(relay: relay, port: firstPort, installed: installed)
        XCTAssertFalse(firstPort.isDisconnected)

        relay.clearLaunchSessionOnExtensionContextUnload(forExtensionId: installed.id)

        XCTAssertTrue(firstPort.isDisconnected)
        XCTAssertEqual(SumiNativeMessagingRuntimeCounters.snapshot().liveRelayPortSessions, 0)

        let secondPort = MockNativeMessagingPort()
        secondPort.applicationIdentifier = "com.example.host"
        let reconnectError = await connectReply(relay: relay, port: secondPort, installed: installed)
        XCTAssertNil(reconnectError)
        XCTAssertFalse(secondPort.isDisconnected)
    }

    func testContextUnloadCancelsPendingOneShotRelay() async throws {
        let installed = try makeInstalledExtension(
            id: "ext-pending-cancel",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.example.host",
                appexBundleID: "com.example.host.extension"
            )
        )
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(
                adapters: [SlowOneShotAdapter(sleepDuration: .seconds(2))]
            ),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )

        let expectation = expectation(description: "oneShotCancelled")
        var replyError: (any Error)?
        relay.handleSendMessage(
            applicationIdentifier: "com.example.host",
            message: ["type": "ping"],
            extensionId: installed.id,
            installedExtensions: [installed]
        ) { _, error in
            replyError = error
            expectation.fulfill()
        }

        relay.clearLaunchSessionOnExtensionContextUnload(forExtensionId: installed.id)
        await fulfillment(of: [expectation], timeout: 2)

        let error = try XCTUnwrap(replyError as NSError?)
        XCTAssertEqual(error.code, SumiNativeMessagingRelay.ErrorCode.relayCancelled.rawValue)
    }

    func testPortInactivityTimeoutDisconnectsIdlePort() async throws {
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.example.host"
        let session = SumiNativeMessagingPortSession(
            port: port,
            adapter: nil,
            extensionId: "ext-idle",
            hostBundleIdentifier: "com.example.host",
            resolverBucket: .knownCompanionAlias,
            logDiagnostic: { _ in /* no-op */ },
            companionProtocolErrorProvider: {
                SumiNativeMessagingErrorMapper.relayError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: nil
                )
            },
            portInactivityTimeout: .milliseconds(50)
        )
        _ = session

        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(port.isDisconnected)
    }

    func testPopoverDidCloseUsesGenericNativeMessagingTeardown() throws {
        let uiSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift"
        )
        let popupPresentationSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionActionPopupPresentationOwner.swift"
        )

        XCTAssertFalse(uiSource.contains("func popoverDidClose(_ notification: Notification)"))
        XCTAssertTrue(
            popupPresentationSource.contains("func popoverDidClose(_ notification: Notification)")
        )
        XCTAssertTrue(popupPresentationSource.contains("pruneNativeMessagePortHandlerEntries("))
        let profilesSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift"
        )
        XCTAssertTrue(profilesSource.contains("nativeMessagePortHandlers[handlerID]?.disconnect()"))
        XCTAssertTrue(
            popupPresentationSource.contains("clearLaunchSessionOnExtensionContextUnload(")
        )
        XCTAssertTrue(
            popupPresentationSource.contains("scheduleOrPerformDeferredPopupContextUnload(")
        )
        XCTAssertTrue(popupPresentationSource.contains("ExtensionActionPopupUIDelegate"))
        XCTAssertTrue(popupPresentationSource.contains("popover.close()"))
        XCTAssertTrue(
            popupPresentationSource.contains("SumiNativeMessagingRuntimeCounters.recordPopupClosed")
        )
        XCTAssertFalse(uiSource.contains("BitwardenNativeMessagingAdapter"))
        XCTAssertFalse(uiSource.contains("com.bitwarden.desktop"))
    }

    func testFillSurvivesPopupCloseWhenNativeMessagingObserved() async throws {
        let installed = try makeInstalledExtension(
            id: "ext-fill-survive",
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
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [adapter]),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )

        SafariExtensionAutofillFillDiagnostics.resetForTesting()
        SafariExtensionAutofillFillDiagnostics.beginFillSession(extensionId: installed.id)
        SafariExtensionAutofillFillDiagnostics.recordNativeMessagingActivity(
            extensionId: installed.id
        )
        SafariExtensionAutofillFillDiagnostics.setPopupActive(false, extensionId: installed.id)

        XCTAssertTrue(
            SafariExtensionAutofillFillDiagnostics.shouldDeferNativeMessagingTeardownOnPopupClose()
        )
        XCTAssertTrue(SafariExtensionAutofillFillDiagnostics.isFillSessionActive)

        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.example.host"
        _ = await connectReply(relay: relay, port: port, installed: installed)
        XCTAssertFalse(port.isDisconnected)

        var teardownExtensionId: String?
        SafariExtensionAutofillFillDiagnostics.deferredFillCompletionHandler = { extensionId in
            teardownExtensionId = extensionId
            SafariExtensionAutofillFillDiagnostics.endFillSession(extensionId: extensionId)
            relay.clearLaunchSessionOnExtensionContextUnload(forExtensionId: installed.id)
        }
        SafariExtensionAutofillFillDiagnostics.noteNativeMessagingRelaySucceeded(
            extensionId: installed.id
        )

        XCTAssertEqual(teardownExtensionId, installed.id)
        XCTAssertTrue(port.isDisconnected)
        XCTAssertFalse(SafariExtensionAutofillFillDiagnostics.isFillSessionActive)
    }

    func testRelayNotCancelledMidFillWhenTeardownDeferred() async throws {
        let installed = try makeInstalledExtension(
            id: "ext-mid-fill",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.example.host",
                appexBundleID: "com.example.host.extension"
            )
        )
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(
                adapters: [SlowOneShotAdapter(sleepDuration: .milliseconds(300))]
            ),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )

        SafariExtensionAutofillFillDiagnostics.resetForTesting()
        SafariExtensionAutofillFillDiagnostics.beginFillSession(extensionId: installed.id)
        SafariExtensionAutofillFillDiagnostics.recordNativeMessagingActivity(
            extensionId: installed.id
        )
        SafariExtensionAutofillFillDiagnostics.setPopupActive(false, extensionId: installed.id)

        let expectation = expectation(description: "oneShotCompleted")
        var replyError: (any Error)?
        relay.handleSendMessage(
            applicationIdentifier: "com.example.host",
            message: ["type": "fill"],
            extensionId: installed.id,
            installedExtensions: [installed]
        ) { _, error in
            replyError = error
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertNil(replyError)
        XCTAssertTrue(
            SafariExtensionAutofillFillDiagnostics.shouldDeferNativeMessagingTeardownOnPopupClose()
        )
    }

    // MARK: - Helpers

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
            .appendingPathComponent("PopupLifecycle.\(UUID().uuidString)", isDirectory: true)
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
