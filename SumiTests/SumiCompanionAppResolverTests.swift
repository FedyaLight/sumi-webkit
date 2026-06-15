import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SumiCompanionAppResolverTests: XCTestCase {
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

    private final class TestAdapter: SumiNativeMessagingProtocolAdapter {
        let protocolIdentifier = "test.adapter"
        let hostBundleIdentifier: String
        var relayCallCount = 0

        init(hostBundleIdentifier: String) {
            self.hostBundleIdentifier = hostBundleIdentifier
        }

        func supports(hostBundleIdentifier: String) -> Bool {
            hostBundleIdentifier == self.hostBundleIdentifier
        }

        func relayOneShotMessage(
            request: SumiNativeMessagingOneShotRequest,
            launcher: SumiHostApplicationLaunching,
            replyHandler: @escaping (Any?, (any Error)?) -> Void
        ) {
            relayCallCount += 1
            Task { @MainActor in
                try? await launcher.openApplication(withBundleIdentifier: request.hostBundleIdentifier)
                replyHandler(nil, SumiNativeMessagingErrorMapper.relayError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: nil
                ))
            }
        }

        func connectPort(
            session: SumiNativeMessagingPortSession,
            launcher: SumiHostApplicationLaunching,
            completionHandler: @escaping ((any Error)?) -> Void
        ) {
            completionHandler(nil)
        }

        func relayPortMessage(session: SumiNativeMessagingPortSession, message: Any) -> Bool {
            false
        }
    }

    override func tearDown() {
        SumiCompanionAppLaunchPolicy.shared.clearPendingState()
        super.tearDown()
    }

    func testResolverResolvesContainingAppFromSyntheticAppex() throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.containing",
            appexBundleID: "com.example.containing.extension"
        )
        let installed = makeInstalledExtension(id: "ext-containing", sourceBundlePath: appexPath)
        let importStore = SafariExtensionImportStore(defaults: makeDefaults())

        let identity = SumiCompanionAppResolver.resolveIdentity(
            requestedApplicationIdentifier: nil,
            extensionId: installed.id,
            installedExtensions: [installed],
            importStore: importStore
        )

        XCTAssertEqual(identity?.resolvedBundleIdentifier, "com.example.containing")
        XCTAssertEqual(identity?.resolutionSource, .containingAppOfImportedAppex)
        XCTAssertTrue(identity?.isContainingApp == true)
    }

    func testResolverResolvesPublicBundleIDMetadata() throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.bitwarden.desktop",
            appexBundleID: "com.bitwarden.desktop.safari"
        )
        let installed = makeInstalledExtension(id: "ext-bw", sourceBundlePath: appexPath)
        let importStore = SafariExtensionImportStore(defaults: makeDefaults())

        let identity = SumiCompanionAppResolver.resolveIdentity(
            requestedApplicationIdentifier: "com.8bit.bitwarden",
            extensionId: installed.id,
            installedExtensions: [installed],
            importStore: importStore
        )

        XCTAssertEqual(identity?.resolvedBundleIdentifier, "com.bitwarden.desktop")
        XCTAssertEqual(identity?.resolutionSource, .publicBundleIdentityAlias)
        XCTAssertFalse(identity?.isContainingApp == true)
    }

    func testApplicationIdResolvesByExtensionContainingApp() throws {
        let appexA = try makeFixtureApp(
            appBundleID: "com.example.containing.a",
            appexBundleID: "com.example.containing.a.extension"
        )
        let appexB = try makeFixtureApp(
            appBundleID: "com.example.containing.b",
            appexBundleID: "com.example.containing.b.extension"
        )
        let installedA = makeInstalledExtension(id: "ext-a", sourceBundlePath: appexA)
        let installedB = makeInstalledExtension(id: "ext-b", sourceBundlePath: appexB)
        let importStore = SafariExtensionImportStore(defaults: makeDefaults())

        let identityA = SumiCompanionAppResolver.resolveIdentity(
            requestedApplicationIdentifier:
                SafariExtensionNativeMessagingRoutingProbe.safariContainingApplicationIdentifier,
            extensionId: installedA.id,
            installedExtensions: [installedA, installedB],
            importStore: importStore
        )
        let identityB = SumiCompanionAppResolver.resolveIdentity(
            requestedApplicationIdentifier:
                SafariExtensionNativeMessagingRoutingProbe.safariContainingApplicationIdentifier,
            extensionId: installedB.id,
            installedExtensions: [installedA, installedB],
            importStore: importStore
        )

        XCTAssertEqual(identityA?.resolvedBundleIdentifier, "com.example.containing.a")
        XCTAssertEqual(identityB?.resolvedBundleIdentifier, "com.example.containing.b")
        XCTAssertEqual(identityA?.resolutionSource, .containingAppOfImportedAppex)
        XCTAssertTrue(identityA?.isContainingApp == true)
        XCTAssertTrue(identityB?.isContainingApp == true)
    }

    func testApplicationIdReturnsTypedUnsupportedBackendWithoutSafariHandlerAdapter()
        async throws
    {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.containing",
            appexBundleID: "com.example.containing.extension"
        )
        let installed = makeInstalledExtension(id: "ext-application-id", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.containing"] = URL(
            fileURLWithPath: "/Applications/Example.app"
        )
        let relay = SumiNativeMessagingRelay(
            importStore: SafariExtensionImportStore(defaults: makeDefaults()),
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(),
            companionApplicationRouter: CompanionApplicationMessageRouter(
                registry: CompanionApplicationBackendRegistry(backends: [])
            ),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier:
                SafariExtensionNativeMessagingRoutingProbe.safariContainingApplicationIdentifier
        )

        XCTAssertTrue(launcher.openedBundleIdentifiers.isEmpty)
        XCTAssertNil(reply.value)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode
                .companionApplicationUnsupportedBackend.rawValue
        )
        XCTAssertFalse(
            error.localizedDescription.contains(
                "Companion host application messaging protocol is not implemented in Sumi"
            )
        )
    }

    func testAppFoundButProtocolUnknownDoesNotLaunchRepeatedly() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.host",
            appexBundleID: "com.example.host.extension"
        )
        let installed = makeInstalledExtension(id: "ext-example", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/tmp/Example.app")
        let launchPolicy = SumiCompanionAppLaunchPolicy()
        let loopGuard = SumiNativeMessagingRelayLoopGuard()
        let relay = SumiNativeMessagingRelay(
            importStore: SafariExtensionImportStore(defaults: makeDefaults()),
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(),
            launchPolicy: launchPolicy,
            loopGuard: loopGuard,
            extensionsModuleEnabled: { true }
        )

        let first = await sendMessageReply(
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
            (first.error as NSError?)?.code,
            SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
        )
        XCTAssertEqual(
            (second.error as NSError?)?.code,
            SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
        )
    }

    func testAppNotFoundReturnsStableError() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.missing",
            appexBundleID: "com.example.missing.extension"
        )
        let installed = makeInstalledExtension(id: "ext-missing", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            extensionsModuleEnabled: { true }
        )

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.example.missing"
        )

        XCTAssertTrue(launcher.openedBundleIdentifiers.isEmpty)
        XCTAssertEqual(
            (reply.error as NSError?)?.code,
            SumiNativeMessagingRelay.ErrorCode.hostNotFound.rawValue
        )

        let evaluation = SumiCompanionAppResolver.evaluate(
            requestedApplicationIdentifier: "com.example.missing",
            extensionId: installed.id,
            installedExtensions: [installed],
            importStore: SafariExtensionImportStore(defaults: makeDefaults()),
            launcher: launcher
        )
        if case .appNotFound = evaluation {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected appNotFound, got \(evaluation)")
        }
    }

    func testLaunchPolicyRefusesArbitraryPaths() {
        XCTAssertTrue(SumiCompanionAppLaunchPolicy.refusesArbitraryExecutablePath("/tmp/evil"))
        XCTAssertTrue(SumiCompanionAppLaunchPolicy.refusesArbitraryExecutablePath(""))
    }

    func testLaunchPolicyRateLimitsRepeatedCalls() async throws {
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/tmp/Example.app")
        let launchPolicy = SumiCompanionAppLaunchPolicy(minimumLaunchInterval: 60)
        let adapter = TestAdapter(hostBundleIdentifier: "com.example.host")
        let registry = SumiNativeMessagingAdapterRegistry(adapters: [adapter])

        let first = SumiCompanionAppResolver.evaluate(
            requestedApplicationIdentifier: "com.example.host",
            extensionId: "ext",
            installedExtensions: [],
            importStore: SafariExtensionImportStore(defaults: makeDefaults()),
            launcher: launcher,
            adapterRegistry: registry,
            launchPolicy: launchPolicy
        )
        XCTAssertTrue(SumiCompanionAppResolver.shouldLaunchApp(for: first))

        try await launchPolicy.launchInstalledApplication(
            hostBundleIdentifier: "com.example.host",
            launcher: launcher
        )

        let second = SumiCompanionAppResolver.evaluate(
            requestedApplicationIdentifier: "com.example.host",
            extensionId: "ext",
            installedExtensions: [],
            importStore: SafariExtensionImportStore(defaults: makeDefaults()),
            launcher: launcher,
            adapterRegistry: registry,
            launchPolicy: launchPolicy
        )
        if case .companionAppResolved(let detail) = second {
            XCTAssertTrue(detail.protocolAdapterAvailable)
            XCTAssertFalse(detail.launchAllowed)
        } else {
            XCTFail("Expected companionAppResolved with launch suppressed, got \(second)")
        }
    }

    func testNoExtensionSpecificBehaviorBranchesInResolverSources() throws {
        let resolverSource = try String(
            contentsOf: sourceURL(named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiCompanionAppResolver.swift"),
            encoding: .utf8
        )
        let policySource = try String(
            contentsOf: sourceURL(named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelayPolicy.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(resolverSource.contains("if targetKey == \"bitwarden\""))
        XCTAssertFalse(policySource.contains("bitwarden"))
        XCTAssertFalse(policySource.contains("1password"))
        XCTAssertFalse(policySource.contains("proton"))
        XCTAssertFalse(policySource.contains("raindrop"))
    }

    func testDiagnosticsSanitized() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.host",
            appexBundleID: "com.example.host.extension"
        )
        let installed = makeInstalledExtension(id: "ext-example", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/tmp/Example.app")
        var diagnostics: [SafariExtensionNativeMessagingDiagnostic] = []
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            extensionsModuleEnabled: { true },
            logDiagnostic: { diagnostics.append($0) }
        )

        _ = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.example.host"
        )

        let diagnostic = try XCTUnwrap(diagnostics.last)
        XCTAssertEqual(diagnostic.requestedApplicationIdentifier, "com.example.host")
        XCTAssertEqual(diagnostic.hostBundleIdentifier, "com.example.host")
        XCTAssertEqual(diagnostic.protocolAdapterAvailable, false)
        XCTAssertEqual(diagnostic.launchAllowed, false)
        XCTAssertEqual(diagnostic.outcome, .companionAppProtocolUnknown)
    }

    func testDisableModuleClearsPendingLaunchState() async throws {
        let launchPolicy = SumiCompanionAppLaunchPolicy()
        let loopGuard = SumiNativeMessagingRelayLoopGuard()
        var moduleEnabled = true
        let relay = SumiNativeMessagingRelay(
            launcher: MockHostLauncher(),
            launchPolicy: launchPolicy,
            loopGuard: loopGuard,
            extensionsModuleEnabled: { moduleEnabled }
        )

        let key = SumiNativeMessagingRelayLoopGuard.SessionKey(
            profileId: nil,
            extensionId: "ext",
            applicationIdentifier: "com.example.host"
        )
        loopGuard.recordCompanionAppProtocolUnknown(key: key, launchAttempted: false)
        launchPolicy.recordLaunchAttempt(
            forHostBundleIdentifier: "com.example.host",
            sessionKey: SumiCompanionAppLaunchPolicy.sessionKey(
                profileId: nil,
                extensionId: "ext",
                requestedApplicationIdentifier: "com.example.host",
                hostBundleIdentifier: "com.example.host"
            )
        )

        relay.clearCompanionState(forExtensionId: "ext")
        moduleEnabled = false

        XCTAssertEqual(
            loopGuard.evaluate(key: key, hostBundleIdentifier: "com.example.host").retryCountBucket,
            .none
        )
        XCTAssertEqual(
            launchPolicy.evaluateLaunch(
                hostBundleIdentifier: "com.example.host",
                appInstalled: true,
                protocolAdapterAvailable: true
            ),
            .allowed
        )
    }

    // MARK: - Helpers

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

    private func makeInstalledExtension(id: String, sourceBundlePath: String) -> InstalledExtension {
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

    private func makeFixtureApp(appBundleID: String, appexBundleID: String) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompanionResolver.\(UUID().uuidString)", isDirectory: true)
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
        try writePlist(appexInfo, to: appexURL.appendingPathComponent("Contents/Info.plist"))
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
        UserDefaults(suiteName: "SumiCompanionAppResolverTests.\(UUID().uuidString)")!
    }

    private func sourceURL(named relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }
}
