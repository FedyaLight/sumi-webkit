import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SumiNativeMessagingRelayLoopGuardTests: XCTestCase {
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

    func testRepeatedSendNativeMessageDoesNotRepeatedlyLaunchApp() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.host",
            appexBundleID: "com.example.host.extension"
        )
        let importStore = SafariExtensionImportStore(defaults: makeDefaults())
        let installed = try makeInstalledExtension(id: "ext-loop", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let loopGuard = SumiNativeMessagingRelayLoopGuard()
        let relay = SumiNativeMessagingRelay(
            importStore: importStore,
            launcher: launcher,
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: loopGuard
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

    func testFirstCallRecordsCompanionAppProtocolUnknown() async throws {
        var diagnostics: [SafariExtensionNativeMessagingDiagnostic] = []
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.host",
            appexBundleID: "com.example.host.extension"
        )
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/tmp/Example.app")
        let relay = SumiNativeMessagingRelay(
            importStore: SafariExtensionImportStore(defaults: makeDefaults()),
            launcher: launcher,
            logDiagnostic: { diagnostics.append($0) }
        )
        let installed = try makeInstalledExtension(id: "ext-1", sourceBundlePath: appexPath)

        _ = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.example.host"
        )

        XCTAssertTrue(
            diagnostics.contains {
                $0.outcome == .companionAppProtocolUnknown && $0.direction == .send
            }
        )
    }

    func testSubsequentCallsWithinCooldownAreSuppressed() async throws {
        let loopGuard = SumiNativeMessagingRelayLoopGuard()
        let key = SumiNativeMessagingRelayLoopGuard.SessionKey(
            profileId: UUID(),
            extensionId: "ext-1",
            applicationIdentifier: "com.example.host"
        )
        loopGuard.recordCompanionAppProtocolUnknown(key: key, launchAttempted: false)

        let evaluation = loopGuard.evaluate(
            key: key,
            hostBundleIdentifier: "com.example.host"
        )

        XCTAssertTrue(evaluation.launchSuppressed)
        XCTAssertTrue(evaluation.isWithinCooldown)
        XCTAssertEqual(evaluation.retryCountBucket, .first)
    }

    func testErrorResponseIsDeterministicAndSanitized() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.host",
            appexBundleID: "com.example.host.extension"
        )
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/tmp/Example.app")
        let relay = SumiNativeMessagingRelay(
            importStore: SafariExtensionImportStore(defaults: makeDefaults()),
            launcher: launcher
        )
        let installed = try makeInstalledExtension(id: "ext-1", sourceBundlePath: appexPath)

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

        let firstError = try XCTUnwrap(first.error as NSError?)
        let secondError = try XCTUnwrap(second.error as NSError?)
        XCTAssertEqual(firstError.domain, SumiNativeMessagingRelay.errorDomain)
        XCTAssertEqual(secondError.domain, SumiNativeMessagingRelay.errorDomain)
        XCTAssertEqual(firstError.code, secondError.code)
        XCTAssertEqual(
            firstError.localizedDescription,
            secondError.localizedDescription
        )
        XCTAssertFalse(firstError.localizedDescription.contains("ping"))
    }

    func testDisablingExtensionClearsLoopGuardState() async throws {
        let loopGuard = SumiNativeMessagingRelayLoopGuard()
        let profileId = UUID()
        let key = SumiNativeMessagingRelayLoopGuard.SessionKey(
            profileId: profileId,
            extensionId: "ext-disable",
            applicationIdentifier: "com.example.host"
        )
        loopGuard.recordCompanionAppProtocolUnknown(key: key, launchAttempted: false)

        let relay = SumiNativeMessagingRelay(loopGuard: loopGuard)
        relay.clearLoopGuard(forExtensionId: "ext-disable", profileId: profileId)

        let evaluation = loopGuard.evaluate(
            key: key,
            hostBundleIdentifier: "com.example.host"
        )
        XCTAssertFalse(evaluation.isWithinCooldown)
    }

    func testModuleOffPreventsRelayAndLaunch() async throws {
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/tmp/Example.app")
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            extensionsModuleEnabled: { false }
        )
        let installed = try makeInstalledExtension(
            id: "ext-1",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.example.host",
                appexBundleID: "com.example.host.extension"
            )
        )

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.example.host"
        )

        XCTAssertTrue(launcher.openedBundleIdentifiers.isEmpty)
        XCTAssertEqual(
            (reply.error as NSError?)?.code,
            SumiNativeMessagingRelay.ErrorCode.policyDenied.rawValue
        )
    }

    func testRelaySourceHasNoExtensionSpecificBranches() throws {
        let relaySource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelay.swift"
                ),
            encoding: .utf8
        )
        let loopGuardSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelayLoopGuard.swift"
                ),
            encoding: .utf8
        )

        for token in ["bitwarden", "1password", "proton", "raindrop", "com.bitwarden.desktop"] {
            XCTAssertFalse(loopGuardSource.localizedCaseInsensitiveContains(token))
        }
        XCTAssertFalse(relaySource.contains("if extensionId =="))
        XCTAssertFalse(relaySource.contains("switch extensionId"))
    }

    func testDiagnosticsLoggerDoesNotIncludeMessageBodies() throws {
        let relaySource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelay.swift"
                ),
            encoding: .utf8
        )
        XCTAssertFalse(relaySource.contains("message.body"))
        XCTAssertFalse(relaySource.contains("String(describing: message)"))
    }

    // MARK: - Helpers

    private func sendMessageReply(
        relay: SumiNativeMessagingRelay,
        installed: InstalledExtension,
        applicationIdentifier: String,
        profileId: UUID? = nil
    ) async -> (value: Any?, error: (any Error)?) {
        let expectation = expectation(description: "nativeMessagingReply")
        var replyValue: Any?
        var replyError: (any Error)?
        relay.handleSendMessage(
            applicationIdentifier: applicationIdentifier,
            message: ["type": "ping"],
            extensionId: installed.id,
            profileId: profileId,
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
            .appendingPathComponent("SumiNM.Loop.\(UUID().uuidString)", isDirectory: true)
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
        UserDefaults(suiteName: "SumiNativeMessagingRelayLoopGuardTests.\(UUID().uuidString)")!
    }
}
