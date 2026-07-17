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
        let browserManager = makeSafariExtensionTestBrowserManager(
            moduleRegistry: registry,
            profile: profile
        )
        module.attach(
            runtime: BrowserExtensionsModuleRuntimeFactory.runtime(
                for: browserManager
            )
        )
        XCTAssertFalse(module.hasLoadedRuntime)
        _ = try await seedManager.settingsCatalogBinding().enable(installed.id)

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
        _ = try XCTUnwrap(module.managerForTesting())
        XCTAssertNotNil(configuration.webExtensionController)
    }

    func testPrepareConfigurationReplacesMismatchedProfileController() throws {
        let container = try makeTestContainer()
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let browserConfiguration = BrowserConfiguration()
        let fixture = makeSafariExtensionManagerTestFixture(
            context: container.mainContext,
            initialProfile: profileA,
            browserConfiguration: browserConfiguration
        )
        let inspection = fixture.inspection
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        let controllerA = inspection.controller.provisioning
            .ensureExtensionController(for: profileA.id)
        let controllerB = inspection.controller.provisioning
            .ensureExtensionController(for: profileB.id)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        configuration.webExtensionController = controllerA

        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
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
        let fixture = makeSafariExtensionManagerTestFixture(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = fixture.manager
        let inspection = fixture.inspection
        let browserManager = BrowserManager()
        manager.attach(browserManager: browserManager)
        browserManager.profileManager.profiles = [profile]
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        _ = inspection.controller.provisioning.ensureExtensionController(
            for: profile.id
        )

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(
                in: browserManager.spaceStateOwner,
                name: "Autofill",
                profileID: profile.id
            )
        let tab = browserManager.tabFactory.makeTab(
            url: URL(string: "https://example.com")!,
            name: "Test",
            spaceId: space.id
        )
        tab.profileId = profile.id
        browserManager.regularTabLifecycleOwner.addTab(tab)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            inspection: inspection,
            profile: profile
        )
        XCTAssertNil(
            fixture.attachedRuntime.runtime.controller.tabWebViewResolver
                .extensionWebView(
                for: tab,
                extensionContext: extensionContext
            )
        )

        let adapter = try XCTUnwrap(
            fixture.attachedRuntime.runtime.adapters.stableAdapter(for: tab)
        )
        inspection.actionSurfaces.publication.markRuntimePublicationReady()
        tab.extensionPageRuntimeOwner.markEligible(
            for: inspection.runtimeAuthorities.tabPublicationRevisions.issue()
        )
        XCTAssertNil(adapter.webView(for: extensionContext))
    }

    func testRegisterTabWithExtensionRuntimeKeepsStableAdapterEligible() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let fixture = makeSafariExtensionManagerTestFixture(
            context: container.mainContext,
            initialProfile: profile
        )
        let manager = fixture.manager
        let inspection = fixture.inspection
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        manager.attach(browserManager: browserManager)
        browserManager.profileManager.profiles = [profile]

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installAutofillProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        await inspection.normalTabs.deferredRuntime
            .initialDocumentRuntimePreparationOwner
            .ensureContentScriptContextsLoaded(for: profile.id)
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com",
            in: browserManager.spaceStateOwner.currentSpace,
            activate: true
        )
        tab.profileId = profile.id
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = tab.spaceId
        windowState.currentProfileId = profile.id
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        let configuration = inspection.controller.browserConfiguration
            .auxiliaryWebViewConfiguration(surface: .extensionOptions)
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionAutofillRuntimeTests.runtimeReload"
        )
        let webView = FocusableWKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)
        XCTAssertTrue(
            fixture.attachedRuntime.runtime.bridge.tabs.allExtensionTabs
                .contains { $0 === tab }
        )
        XCTAssertTrue(
            fixture.attachedRuntime.runtime.bridge.webViews
                .extensionLiveWebViews(for: tab)
                .contains { $0 === webView }
        )
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            fixture.attachedRuntime.runtime.controller.controllers
                .existingController(for: tab)
        )
        XCTAssertIdentical(
            fixture.attachedRuntime.runtime.bridge.windows
                .currentExtensionTab(in: windowState),
            tab
        )

        inspection.browserPublication.reloads.reloadLoadedRuntime(
            reason: "SafariExtensionAutofillRuntimeTests",
            profileID: profile.id
        )

        let adapter = try XCTUnwrap(
            fixture.attachedRuntime.runtime.adapters.stableAdapter(for: tab)
        )
        XCTAssertTrue(
            fixture.attachedRuntime.runtime.normalTabs.preparedTabs
                .containsPreparedTab(tab)
        )
        XCTAssertNotNil(
            adapter.url(
                for: try XCTUnwrap(
                    inspection.contextState.profileState.context(
                        for: installed.id
                    )
                )
            )
        )
    }

    func testEphemeralTabNeverReturnsExtensionWebView() async throws {
        let container = try makeTestContainer()
        let profile = Profile.createEphemeral()
        let fixture = makeSafariExtensionManagerTestFixture(
            context: container.mainContext,
            initialProfile: profile
        )
        let manager = fixture.manager
        let inspection = fixture.inspection
        let browserManager = BrowserManager()
        browserManager.profileManager.profiles = [profile]
        manager.attach(browserManager: browserManager)
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        _ = inspection.controller.provisioning.ensureExtensionController(
            for: profile.id
        )

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "https://example.com")!
        )
        browserManager.regularTabLifecycleOwner.addTab(tab)
        tab.extensionPageRuntimeOwner.markEligible(
            for: inspection.runtimeAuthorities.tabPublicationRevisions.issue()
        )

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            inspection: inspection,
            profile: profile
        )
        XCTAssertNil(
            fixture.attachedRuntime.runtime.controller.tabWebViewResolver
                .extensionWebView(
                for: tab,
                extensionContext: extensionContext
            )
        )
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
        let fixture = makeSafariExtensionManagerTestFixture(
            context: container.mainContext,
            initialProfile: profile
        )
        let manager = fixture.manager
        let inspection = fixture.inspection
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        _ = inspection.controller.provisioning.ensureExtensionController(
            for: profile.id
        )
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        manager.attach(browserManager: browserManager)
        browserManager.profileManager.profiles = [profile]

        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(
                in: browserManager.spaceStateOwner,
                name: "Autofill",
                profileID: profile.id
            )
        let tab = browserManager.tabFactory.makeTab(
            url: URL(string: "about:blank")!,
            name: "Autofill",
            spaceId: space.id
        )
        tab.profileId = profile.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        browserManager.regularTabLifecycleOwner.addTab(tab)
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = tab.spaceId
        windowState.currentProfileId = profile.id
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        _ = fixture.attachedRuntime.runtime.publications.normalWindows
            .opened(windowState)

        let configuration = BrowserConfiguration().auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionAutofillRuntimeTests"
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        let didOpenExpectation = expectation(description: "didOpenTab after commit")
        manager.testHooks.didOpenTab = { tabID in
            if tabID == tab.id {
                didOpenExpectation.fulfill()
            }
        }

        fixture.attachedRuntime.runtime.normalTabs.tabRegistration
            .markEligibleAfterCommittedNavigation(
            tab,
            reason: "SafariExtensionAutofillRuntimeTests"
        )

        wait(for: [didOpenExpectation], timeout: 2)
        XCTAssertTrue(
            fixture.attachedRuntime.runtime.normalTabs.preparedTabs
                .containsPreparedTab(tab)
        )
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
        inspection: ExtensionManagerTestInspection,
        profile: Profile
    ) async throws -> WKWebExtensionContext {
        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installAutofillProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        let context = try await inspection.contextCoordination.residency
            .ensureExtensionLoaded(
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

        return try await manager.settingsCatalogBinding().install(
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
