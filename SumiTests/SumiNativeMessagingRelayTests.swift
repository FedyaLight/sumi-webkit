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

    func testResolverBucketForExplicitIdentifier() throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.bitwarden.desktop",
            appexBundleID: "com.bitwarden.desktop.safari"
        )
        let installed = try makeInstalledExtension(id: "ext-bw", sourceBundlePath: appexPath)
        let resolution = SumiNativeMessagingAppResolver.resolve(
            requestedApplicationIdentifier: "com.8bit.bitwarden",
            extensionId: installed.id,
            installedExtensions: [installed],
            importStore: SafariExtensionImportStore(defaults: makeDefaults())
        )

        XCTAssertEqual(resolution?.hostBundleIdentifier, "com.bitwarden.desktop")
        XCTAssertEqual(resolution?.bucket, .knownCompanionAlias)
    }

    func testSendMessageWakesHostThenReturnsCompanionProtocolUnknown() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.bitwarden.desktop",
            appexBundleID: "com.bitwarden.desktop.safari"
        )
        let importStore = SafariExtensionImportStore(defaults: makeDefaults())
        let installed = try makeInstalledExtension(id: "ext-bitwarden", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.bitwarden.desktop"] = URL(
            fileURLWithPath: "/Applications/Bitwarden.app"
        )
        var diagnostics: [SafariExtensionNativeMessagingDiagnostic] = []
        let relay = SumiNativeMessagingRelay(
            importStore: importStore,
            launcher: launcher,
            extensionsModuleEnabled: { true },
            logDiagnostic: { diagnostics.append($0) }
        )

        let reply = await sendMessageReply(
            relay: relay,
            installed: installed,
            applicationIdentifier: "com.bitwarden.desktop"
        )

        XCTAssertEqual(launcher.openedBundleIdentifiers, ["com.bitwarden.desktop"])
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

    func testClassificationCatalogForPasswordManagers() {
        let bitwarden = SafariExtensionNativeMessagingClassificationCatalog
            .classifications(forTargetKey: "bitwarden")
        XCTAssertTrue(bitwarden.contains(.noChromeStyleNativeHostRelay))
        XCTAssertTrue(bitwarden.contains(.wkWebExtensionAppMessagingAvailable))
        XCTAssertTrue(bitwarden.contains(.companionAppProtocolUnknown))
        XCTAssertFalse(bitwarden.contains(.platformBlocked))

        let raindrop = SafariExtensionNativeMessagingClassificationCatalog
            .classifications(forTargetKey: "raindrop")
        XCTAssertFalse(raindrop.contains(.companionAppProtocolUnknown))
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

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SumiNativeMessagingRelayTests.\(UUID().uuidString)")!
    }
}
