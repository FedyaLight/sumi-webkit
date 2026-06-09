import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionNativeMessagingHostTests: XCTestCase {
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
            SafariExtensionNativeMessagingResolver.normalizedHostBundleIdentifier(
                "com.8bit.bitwarden"
            ),
            "com.bitwarden.desktop"
        )
        XCTAssertEqual(
            SafariExtensionNativeMessagingResolver.normalizedHostBundleIdentifier(
                "me.proton.pass.nm"
            ),
            "me.proton.pass.catalyst"
        )
        XCTAssertEqual(
            SafariExtensionNativeMessagingResolver.normalizedHostBundleIdentifier(
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

        let hostID = SafariExtensionNativeMessagingResolver.resolveHostApplicationBundleIdentifier(
            requestedApplicationIdentifier: "com.bitwarden.desktop",
            extensionId: installed.id,
            installedExtensions: [installed],
            importStore: importStore
        )

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

        let hostID = SafariExtensionNativeMessagingResolver.resolveHostApplicationBundleIdentifier(
            requestedApplicationIdentifier: "",
            extensionId: installed.id,
            installedExtensions: [installed],
            importStore: importStore
        )

        XCTAssertEqual(hostID, "com.1password.safari")
    }

    func testSendMessageWakesHostThenReturnsCompanionProtocolUnknown() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.bitwarden.desktop",
            appexBundleID: "com.bitwarden.desktop.safari"
        )
        let importStore = SafariExtensionImportStore(defaults: makeDefaults())
        let installed = makeInstalledExtension(
            id: "ext-bitwarden",
            sourceBundlePath: appexPath
        )
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.bitwarden.desktop"] = URL(
            fileURLWithPath: "/Applications/Bitwarden.app"
        )
        var diagnostics: [SafariExtensionNativeMessagingDiagnostic] = []
        let host = SafariExtensionNativeMessagingHost(
            importStore: importStore,
            launcher: launcher,
            extensionsModuleEnabled: { true },
            logDiagnostic: { diagnostics.append($0) }
        )

        let reply = await sendMessageReply(
            host: host,
            installed: installed,
            applicationIdentifier: "com.bitwarden.desktop"
        )

        XCTAssertEqual(launcher.openedBundleIdentifiers, ["com.bitwarden.desktop"])
        XCTAssertNil(reply.value)
        let error = try XCTUnwrap(reply.error as NSError?)
        XCTAssertEqual(error.domain, SafariExtensionNativeMessagingHost.errorDomain)
        XCTAssertEqual(
            error.code,
            SafariExtensionNativeMessagingHost.ErrorCode.companionAppProtocolUnknown.rawValue
        )
        XCTAssertTrue(
            diagnostics.contains {
                $0.outcome == .hostLaunched && $0.direction == .send
            }
        )
        XCTAssertTrue(
            diagnostics.contains {
                $0.outcome == .companionAppProtocolUnknown && $0.direction == .send
            }
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
        let host = SafariExtensionNativeMessagingHost(
            importStore: importStore,
            launcher: launcher,
            extensionsModuleEnabled: { true },
            logDiagnostic: { _ in }
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
            SafariExtensionNativeMessagingHost.ErrorCode.hostNotFound.rawValue
        )
    }

    func testResolverReturnsNilForDirectoryExtensionWithoutExplicitHostRequest() throws {
        let importStore = SafariExtensionImportStore(defaults: makeDefaults())
        let installed = makeInstalledExtension(
            id: "ext-directory",
            sourceBundlePath: "/tmp/unpacked-extension",
            sourceKind: .directory
        )

        let hostID = SafariExtensionNativeMessagingResolver.resolveHostApplicationBundleIdentifier(
            requestedApplicationIdentifier: nil,
            extensionId: installed.id,
            installedExtensions: [installed],
            importStore: importStore
        )

        XCTAssertNil(hostID)
    }

    func testProductNativeMessagingSourceAvoidsChromeShimAndSubprocessIO() throws {
        let relaySource = try Self.source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelay.swift"
        )
        let portSource = try Self.source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingPortSession.swift"
        )
        let delegateSource = try Self.source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift"
        )

        XCTAssertFalse(relaySource.contains("ChromeMV3NativeMessagingInternalRuntime"))
        XCTAssertFalse(portSource.contains("ChromeMV3NativeMessagingInternalRuntime"))
        XCTAssertTrue(delegateSource.contains("safariNativeMessagingHost.handleSendMessage"))
        XCTAssertTrue(delegateSource.contains("safariNativeMessagingHost.handleConnect"))
        XCTAssertTrue(portSource.contains("WKWebExtension.MessagePort"))

        let processCallToken = "Process" + "("
        assertSourceExcludes(
            relaySource + portSource,
            [
                processCallToken,
                "NativeMessagingProcessSession",
                "readDataToEndOfFile",
                "waitUntilExit",
                ".write(contentsOf",
            ],
            context: "Safari native messaging foundation"
        )
    }

    // MARK: - Helpers

    private func sendMessageReply(
        host: SafariExtensionNativeMessagingHost,
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
        let suiteName = "SafariExtensionNativeMessagingHostTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
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

    private func assertSourceExcludes(
        _ source: String,
        _ forbidden: [String],
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for token in forbidden {
            XCTAssertFalse(
                source.contains(token),
                "\(context) should not contain \(token)",
                file: file,
                line: line
            )
        }
    }
}
