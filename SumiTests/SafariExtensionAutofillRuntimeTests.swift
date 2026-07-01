import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionAutofillRuntimeTests: XCTestCase {
    func testModuleBootstrapsControllerBeforeManagerWasCached() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Autofill Profile")

        let seedManager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installAutofillProbeExtension(
            manager: seedManager,
            scratchDirectory: scratchDirectory
        )
        _ = try await seedManager.enableExtension(installed.id)

        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)

        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            initialProfileProvider: { profile }
        )
        XCTAssertFalse(module.hasLoadedRuntime)

        let configuration = BrowserConfiguration.shared.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://example.com")!
        )
        module.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionAutofillRuntimeTests"
        )

        XCTAssertTrue(module.hasLoadedRuntime)
        let manager = try XCTUnwrap(module.managerIfEnabled())
        XCTAssertIdentical(
            configuration.webExtensionController,
            manager.ensureExtensionController(for: profile.id)
        )
        XCTAssertNotNil(configuration.webExtensionController)
    }

    func testPrepareConfigurationReplacesMismatchedProfileController() throws {
        let container = try makeTestContainer()
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let browserConfiguration = BrowserConfiguration()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profileA,
            browserConfiguration: browserConfiguration
        )
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        let controllerA = manager.ensureExtensionController(for: profileA.id)
        let controllerB = manager.ensureExtensionController(for: profileB.id)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        configuration.webExtensionController = controllerA

        manager.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profileB.id,
            reason: "SafariExtensionAutofillRuntimeTests"
        )

        XCTAssertIdentical(configuration.webExtensionController, controllerB)
        XCTAssertNotIdentical(configuration.webExtensionController, controllerA)
    }

    func testExtensionWebViewRejectsLoadedPageWithoutController() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration
        )
        let browserManager = BrowserManager()
        manager.attach(browserManager: browserManager)
        browserManager.profileManager.profiles = [profile]
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        _ = manager.ensureExtensionController(for: profile.id)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        let tab = makeTab(profileId: profile.id, url: URL(string: "https://example.com")!)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            profile: profile
        )
        XCTAssertNil(manager.extensionWebView(for: tab, extensionContext: extensionContext))

        let adapter = try XCTUnwrap(manager.stableAdapter(for: tab))
        manager.extensionsLoaded = true
        tab.extensionPageRuntimeOwner.eligibleGeneration = manager.tabOpenNotificationGeneration
        XCTAssertNil(adapter.webView(for: extensionContext))
    }

    func testRegisterTabWithExtensionRuntimeKeepsStableAdapterEligible() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        let browserManager = BrowserManager()
        manager.attach(browserManager: browserManager)
        browserManager.profileManager.profiles = [profile]

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installAutofillProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.enableExtension(installed.id)
        await manager.ensureContentScriptContextsLoaded(for: profile.id)
        manager.extensionsLoaded = true

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab.profileId = profile.id

        manager.reconcileOpenTabsAfterExtensionContextLoad(
            reason: "SafariExtensionAutofillRuntimeTests",
            profileId: profile.id
        )

        let adapter = try XCTUnwrap(manager.stableAdapter(for: tab))
        XCTAssertTrue(manager.isTabEligibleForCurrentExtensionRuntime(tab))
        XCTAssertNotNil(adapter.url(for: try XCTUnwrap(manager.getExtensionContext(for: installed.id))))
    }

    func testEphemeralTabNeverReturnsExtensionWebView() async throws {
        let container = try makeTestContainer()
        let profile = Profile.createEphemeral()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        _ = manager.ensureExtensionController(for: profile.id)

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "https://example.com")!
        )
        tab.extensionPageRuntimeOwner.eligibleGeneration = manager.tabOpenNotificationGeneration

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            profile: profile
        )
        XCTAssertNil(manager.extensionWebView(for: tab, extensionContext: extensionContext))
    }

    func testAutofillPagesHTTPServerServesLoginBasic() async throws {
        let server = try await AutofillPagesHTTPServer.start()
        addTeardownBlock {
            server.stop()
        }

        let url = server.loginBasicURL
        XCTAssertTrue(url.absoluteString.contains("login-basic.html"))

        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)
        let html = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(html.contains("autocomplete=\"username\""))
        XCTAssertTrue(html.contains("autocomplete=\"current-password\""))
    }

    func testMarkTabEligibleAfterCommittedNavigationTriggersContentScriptPath() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        _ = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true
        manager.tabOpenNotificationGeneration = 4

        let browserManager = BrowserManager()
        manager.attach(browserManager: browserManager)
        browserManager.profileManager.profiles = [profile]

        let tab = makeTab(profileId: profile.id, url: URL(string: "about:blank")!)
        tab.attachBrowserRuntime(browserManager.makeTabBrowserRuntime())

        let configuration = BrowserConfiguration().auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionAutofillRuntimeTests"
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

        let didOpenExpectation = expectation(description: "didOpenTab after commit")
        manager.testHooks.didOpenTab = { tabID in
            if tabID == tab.id {
                didOpenExpectation.fulfill()
            }
        }

        manager.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: "SafariExtensionAutofillRuntimeTests"
        )

        wait(for: [didOpenExpectation], timeout: 2)
        XCTAssertTrue(manager.isTabEligibleForCurrentExtensionRuntime(tab))
    }

    func testLoginFormFixtureExistsForManualAutofillVerification() throws {
        let loginForm = try fixtureURL(named: "login-form.html")
        let iframeLogin = try fixtureURL(named: "iframe-login.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: loginForm.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: iframeLogin.path))

        let loginHTML = try String(contentsOf: loginForm, encoding: .utf8)
        XCTAssertTrue(loginHTML.contains("autocomplete=\"username\""))
        XCTAssertTrue(loginHTML.contains("autocomplete=\"current-password\""))
    }

    private func fixtureURL(named filename: String) -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Extensions/\(filename)")
    }

    private func makeTab(profileId: UUID, url: URL) -> Tab {
        let tab = Tab(url: url, name: "Test")
        tab.profileId = profileId
        return tab
    }

    private func makeLoadedExtensionContext(
        manager: ExtensionManager,
        profile: Profile
    ) async throws -> WKWebExtensionContext {
        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installAutofillProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.enableExtension(installed.id)
        let context = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        return try XCTUnwrap(context)
    }

    private func installAutofillProbeExtension(
        manager: ExtensionManager,
        scratchDirectory: URL
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(
            "AutofillProbeExtension",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "AutofillProbeExtension",
            "version": "1.0",
            "host_permissions": ["<all_urls>"],
            "content_scripts": [[
                "matches": ["<all_urls>"],
                "js": ["content.js"],
                "run_at": "document_idle",
            ]],
            "action": ["default_popup": "popup.html"],
        ]
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: manifestURL, options: [.atomic])
        try Data("document.documentElement.dataset.sumiProbe='1';".utf8)
            .write(to: directoryURL.appendingPathComponent("content.js"), options: [.atomic])
        try Data("<!doctype html><title>popup</title>".utf8)
            .write(to: directoryURL.appendingPathComponent("popup.html"), options: [.atomic])

        return try await manager.performInstallation(
            from: directoryURL,
            enableOnInstall: false
        )
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
