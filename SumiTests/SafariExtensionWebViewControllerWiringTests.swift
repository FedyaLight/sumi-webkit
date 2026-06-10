import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionWebViewControllerWiringTests: XCTestCase {
    private func makeManager(
        context: ModelContext,
        profile: Profile,
        browserConfiguration: BrowserConfiguration = BrowserConfiguration()
    ) -> (manager: ExtensionManager, browserConfiguration: BrowserConfiguration) {
        let manager = ExtensionManager(
            context: context,
            initialProfile: profile,
            browserConfiguration: browserConfiguration
        )
        return (manager, browserConfiguration)
    }

    func testAttachExtensionControllerIfNeededAssignsProfileController() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        let expectedController = manager.ensureExtensionController(for: profile.id)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let tab = makeTab(profileId: profile.id, url: URL(string: "about:blank")!)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

        XCTAssertTrue(manager.attachExtensionControllerIfNeeded(to: webView, for: tab))
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            expectedController
        )
    }

    func testExtensionWebViewReturnsNilWithoutControllerOnLoadedPage() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
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
        webView.load(URLRequest(url: URL(string: "https://example.com")!))

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            profile: profile
        )
        XCTAssertNil(manager.extensionWebView(for: tab, extensionContext: extensionContext))
    }

    func testExtensionWebViewReturnsProfileMatchedController() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        let expectedController = manager.ensureExtensionController(for: profile.id)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        let tab = makeTab(profileId: profile.id, url: URL(string: "about:blank")!)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            profile: profile
        )
        let resolvedWebView = try XCTUnwrap(
            manager.extensionWebView(for: tab, extensionContext: extensionContext)
        )
        XCTAssertIdentical(
            resolvedWebView.configuration.webExtensionController,
            expectedController
        )
    }

    func testExtensionWebViewRejectsCrossProfileContext() async throws {
        let container = try makeTestContainer()
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profileA,
            browserConfiguration: browserConfiguration
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profileB.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        let tab = makeTab(profileId: profileB.id, url: URL(string: "about:blank")!)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            profile: profileA
        )
        XCTAssertNil(manager.extensionWebView(for: tab, extensionContext: extensionContext))
    }

    func testIsTabEligibleForCurrentExtensionRuntimeBlocksEphemeralTabs() throws {
        let container = try makeTestContainer()
        let ephemeralProfile = Profile.createEphemeral()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: ephemeralProfile
        )
        manager.tabOpenNotificationGeneration = 7

        let browserManager = BrowserManager()
        browserManager.profileManager.profiles = [ephemeralProfile]

        let tab = makeTab(
            profileId: ephemeralProfile.id,
            url: URL(string: "https://example.com")!
        )
        tab.browserManager = browserManager
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration

        XCTAssertTrue(ephemeralProfile.isEphemeral)
        XCTAssertTrue(tab.isEphemeral)
        XCTAssertFalse(manager.isTabEligibleForCurrentExtensionRuntime(tab))
    }

    func testExtensionTabAdapterDoesNotReturnWebViewWithoutController() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        _ = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true
        manager.tabOpenNotificationGeneration = 3

        let browserManager = BrowserManager()
        manager.attach(browserManager: browserManager)
        browserManager.profileManager.profiles = [profile]

        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab.profileId = profile.id
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            profile: profile
        )
        let adapter = try XCTUnwrap(manager.stableAdapter(for: tab))
        XCTAssertNil(adapter.webView(for: extensionContext))
    }

    func testNormalTabWebViewIncludesProfileExtensionController() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            initialProfileProvider: { profile }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule
        )
        extensionsModule.attach(browserManager: browserManager)
        browserManager.profileManager.profiles = [profile]

        let scratchDirectory = try makeScratchDirectory()
        let manager = try XCTUnwrap(extensionsModule.managerIfEnabled())
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "WebViewWiringExtension"
        )
        _ = try await manager.enableExtension(installed.id)
        manager.extensionsLoaded = true

        let tab = browserManager.tabManager.createNewTab(
            url: "about:blank",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab.profileId = profile.id

        let webView = try XCTUnwrap(tab.makeNormalTabWebView(reason: "SafariExtensionWebViewControllerWiringTests"))
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            manager.ensureExtensionController(for: profile.id)
        )
    }

    func testMarkTabEligibleAfterCommittedNavigationNotifiesTabOpened() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        _ = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true
        manager.tabOpenNotificationGeneration = 9

        let browserManager = BrowserManager()
        manager.attach(browserManager: browserManager)
        browserManager.profileManager.profiles = [profile]

        let tab = makeTab(profileId: profile.id, url: URL(string: "about:blank")!)
        tab.browserManager = browserManager

        let configuration = BrowserConfiguration().auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

        let didOpenExpectation = expectation(description: "didOpenTab")
        manager.testHooks.didOpenTab = { tabID in
            if tabID == tab.id {
                didOpenExpectation.fulfill()
            }
        }

        manager.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        wait(for: [didOpenExpectation], timeout: 2)
        XCTAssertEqual(
            tab.lastExtensionOpenNotificationGeneration,
            manager.tabOpenNotificationGeneration
        )
        XCTAssertTrue(tab.didNotifyOpenToExtensions)
    }

    func testMarkTabEligibleAfterCommittedNavigationDoesNotNotifyTwice() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        _ = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true
        manager.tabOpenNotificationGeneration = 11

        let browserManager = BrowserManager()
        manager.attach(browserManager: browserManager)
        browserManager.profileManager.profiles = [profile]

        let tab = makeTab(profileId: profile.id, url: URL(string: "about:blank")!)
        tab.browserManager = browserManager

        let configuration = BrowserConfiguration().auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

        var notifyCount = 0
        manager.testHooks.didOpenTab = { tabID in
            if tabID == tab.id {
                notifyCount += 1
            }
        }

        manager.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests.first"
        )
        manager.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests.second"
        )

        XCTAssertEqual(notifyCount, 1)
    }

    func testMarkTabEligibleAfterCommittedNavigationEnablesExtensionWebView() async throws {
        let server = try await AutofillPagesHTTPServer.start()
        addTeardownBlock {
            server.stop()
        }

        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        let expectedController = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true

        let browserManager = BrowserManager()
        manager.attach(browserManager: browserManager)
        browserManager.profileManager.profiles = [profile]

        let pageURL = server.loginBasicURL
        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        let tab = makeTab(profileId: profile.id, url: pageURL)
        tab.browserManager = browserManager
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            profile: profile
        )

        let didFinish = expectation(description: "page loaded")
        let delegate = AutofillPagesNavigationDelegateBox {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate
        webView.load(URLRequest(url: pageURL, cachePolicy: .reloadIgnoringLocalCacheData))
        await fulfillment(of: [didFinish], timeout: 5)
        webView.navigationDelegate = nil

        manager.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            expectedController
        )
        XCTAssertNotNil(
            manager.extensionWebView(for: tab, extensionContext: extensionContext)
        )
    }

    func testPrepareWebViewForExtensionRuntimeAttachesControllerOnBlankWebView() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        let expectedController = manager.ensureExtensionController(for: profile.id)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let tab = makeTab(profileId: profile.id, url: URL(string: "about:blank")!)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab

        manager.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: URL(string: "about:blank"),
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            expectedController
        )
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
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ContextProbeExtension"
        )
        _ = try await manager.enableExtension(installed.id)
        let context = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        return try XCTUnwrap(context)
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

    private final class AutofillPagesNavigationDelegateBox: NSObject, WKNavigationDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            onFinish()
        }
    }

    private func installUnpackedExtension(
        manager: ExtensionManager,
        scratchDirectory: URL,
        name: String
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": name,
            "version": "1.0",
            "host_permissions": ["<all_urls>"],
            "action": ["default_popup": "popup.html"],
        ]
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        )
        try manifestData.write(to: manifestURL, options: [.atomic])
        try Data("<!doctype html><title>popup</title>".utf8)
            .write(to: directoryURL.appendingPathComponent("popup.html"), options: [.atomic])

        return try await manager.performInstallation(
            from: directoryURL,
            enableOnInstall: false
        )
    }
}
