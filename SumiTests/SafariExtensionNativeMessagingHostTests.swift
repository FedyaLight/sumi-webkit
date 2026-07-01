import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SumiNativeMessagingRelayHostResolutionTests: XCTestCase {
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

    func testResolverNormalizesKnownHostAliases() {
        XCTAssertEqual(
            SumiNativeMessagingAppResolver.normalizedHostBundleIdentifier(
                "com.8bit.bitwarden"
            ),
            "com.bitwarden.desktop"
        )
        XCTAssertEqual(
            SumiNativeMessagingAppResolver.normalizedHostBundleIdentifier(
                "me.proton.pass.nm"
            ),
            "me.proton.pass.catalyst"
        )
        XCTAssertEqual(
            SumiNativeMessagingAppResolver.normalizedHostBundleIdentifier(
                "com.bitwarden.desktop"
            ),
            "com.bitwarden.desktop"
        )
    }

    func testResolverUsesRequestedApplicationIdentifier() throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.bitwarden.desktop",
            appexBundleID: "com.bitwarden.desktop.safari"
        )
        let importStore = SafariExtensionImportStore(defaults: makeDefaults())
        let installed = makeInstalledExtension(
            id: "ext-bitwarden",
            sourceBundlePath: appexPath
        )

        let hostID = SumiNativeMessagingAppResolver.resolve(
            requestedApplicationIdentifier: "com.bitwarden.desktop",
            extensionId: installed.id,
            installedExtensions: [installed],
            importStore: importStore
        )?.hostBundleIdentifier

        XCTAssertEqual(hostID, "com.bitwarden.desktop")
    }

    func testResolverFallsBackToContainingAppWhenRequestIsEmpty() throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.1password.safari",
            appexBundleID: "com.1password.safari.extension"
        )
        let importStore = SafariExtensionImportStore(defaults: makeDefaults())
        let installed = makeInstalledExtension(
            id: "ext-1password",
            sourceBundlePath: appexPath
        )

        let hostID = SumiNativeMessagingAppResolver.resolve(
            requestedApplicationIdentifier: "",
            extensionId: installed.id,
            installedExtensions: [installed],
            importStore: importStore
        )?.hostBundleIdentifier

        XCTAssertEqual(hostID, "com.1password.safari")
    }

    func testSendMessageUnknownProtocolWithoutLaunch() async throws {
        // Use a resolvable host with no registered protocol adapter (Bitwarden has one now).
        let hostBundleID = "com.example.passwordmanager.desktop"
        let appexPath = try makeFixtureApp(
            appBundleID: hostBundleID,
            appexBundleID: "com.example.passwordmanager.desktop.safari"
        )
        let importStore = SafariExtensionImportStore(defaults: makeDefaults())
        let installed = makeInstalledExtension(
            id: "ext-example-passwordmanager",
            sourceBundlePath: appexPath
        )
        let launcher = MockHostLauncher()
        launcher.bundleURLs[hostBundleID] = URL(
            fileURLWithPath: "/Applications/ExamplePasswordManager.app"
        )
        var diagnostics: [SafariExtensionNativeMessagingDiagnostic] = []
        let host = SumiNativeMessagingRelay(
            importStore: importStore,
            launcher: launcher,
            extensionsModuleEnabled: { true },
            logDiagnostic: { diagnostics.append($0) }
        )

        let reply = await sendMessageReply(
            host: host,
            installed: installed,
            applicationIdentifier: hostBundleID
        )

        XCTAssertTrue(launcher.openedBundleIdentifiers.isEmpty)
        XCTAssertNil(reply.value)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(error.domain, SumiNativeMessagingRelay.errorDomain)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
        )
        XCTAssertTrue(
            diagnostics.contains {
                $0.outcome == .companionAppProtocolUnknown && $0.direction == .send
            }
        )
        XCTAssertFalse(
            diagnostics.contains { $0.outcome == .hostLaunched }
        )
    }

    func testSendMessageReturnsHostNotFoundWhenLauncherCannotResolveApp() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.host",
            appexBundleID: "com.example.host.extension"
        )
        let importStore = SafariExtensionImportStore(defaults: makeDefaults())
        let installed = makeInstalledExtension(
            id: "ext-example",
            sourceBundlePath: appexPath
        )
        let launcher = MockHostLauncher()
        let host = SumiNativeMessagingRelay(
            importStore: importStore,
            launcher: launcher,
            extensionsModuleEnabled: { true },
            logDiagnostic: { _ in /* no-op */ }
        )

        let reply = await sendMessageReply(
            host: host,
            installed: installed,
            applicationIdentifier: "com.example.host"
        )

        XCTAssertTrue(launcher.openedBundleIdentifiers.isEmpty)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(
            error.code,
            SumiNativeMessagingRelay.ErrorCode.hostNotFound.rawValue
        )
    }

    func testResolverReturnsNilForDirectoryExtensionWithoutExplicitHostRequest() {
        let importStore = SafariExtensionImportStore(defaults: makeDefaults())
        let installed = makeInstalledExtension(
            id: "ext-directory",
            sourceBundlePath: "/tmp/unpacked-extension",
            sourceKind: .directory
        )

        let hostID = SumiNativeMessagingAppResolver.resolve(
            requestedApplicationIdentifier: nil,
            extensionId: installed.id,
            installedExtensions: [installed],
            importStore: importStore
        )?.hostBundleIdentifier

        XCTAssertNil(hostID)
    }

    // MARK: - Helpers

    private func sendMessageReply(
        host: SumiNativeMessagingRelay,
        installed: InstalledExtension,
        applicationIdentifier: String
    ) async -> (value: Any?, error: (any Error)?) {
        let expectation = expectation(description: "nativeMessagingReply")
        var replyValue: Any?
        var replyError: (any Error)?
        host.handleSendMessage(
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
        sourceKind: WebExtensionSourceKind = .safariAppExtension
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
            sourceKind: sourceKind,
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
            .appendingPathComponent("SafariNM.\(UUID().uuidString)", isDirectory: true)
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
        let suiteName = "SumiNativeMessagingRelayHostResolutionTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

}
