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

    func testTabNeedsExtensionContentScriptRebindWhenContextsWereNotLoadedAtNotify() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profile.id, url: pageURL)
        tab.extensionRuntimeOpenNotifiedDocumentSequence = 0
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 0
        tab.extensionRuntimeOpenNotifiedWithLoadedContexts = false
        tab.noteCommittedMainDocumentNavigation(to: pageURL)

        XCTAssertTrue(manager.tabNeedsExtensionContentScriptRebind(tab))
    }

    func testNotifyTabOpenedDefersUntilContentScriptContextsLoad() async throws {
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

        let browserManager = BrowserManager()
        manager.attach(browserManager: browserManager)
        browserManager.profileManager.profiles = [profile]

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.enableExtension(installed.id)
        manager.unloadExtensionContextIfLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "http://127.0.0.1:8765/login-basic.html")!
        )
        tab.browserManager = browserManager
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration

        XCTAssertFalse(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))
        XCTAssertFalse(manager.notifyTabOpened(tab))

        await manager.ensureContentScriptContextsLoaded(for: profile.id)
        XCTAssertTrue(manager.profileHasLoadedContentScriptContexts(profileId: profile.id))
        XCTAssertTrue(manager.notifyTabOpened(tab))
        XCTAssertEqual(tab.extensionRuntimeOpenNotifiedWithLoadedContexts, true)
    }

    func testTabNeedsExtensionContentScriptRebindWhenOpenNotifiedAfterCommit() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "http://127.0.0.1:8765/login-basic.html")!
        )
        tab.noteCommittedMainDocumentNavigation(to: tab.url)
        tab.extensionRuntimeOpenNotifiedDocumentSequence = tab.extensionRuntimeDocumentSequence

        XCTAssertTrue(manager.tabNeedsExtensionContentScriptRebind(tab))
    }

    func testTabDoesNotNeedExtensionContentScriptRebindWhenOpenPrecededCommit() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager

        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "http://127.0.0.1:8765/login-basic.html")!
        )
        tab.extensionRuntimeOpenNotifiedDocumentSequence = 0
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 0
        tab.noteCommittedMainDocumentNavigation(to: tab.url)

        XCTAssertFalse(manager.tabNeedsExtensionContentScriptRebind(tab))
    }

    func testTabNeedsExtensionContentScriptRebindAfterReloadCommitWithoutWillStartNotification() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profile.id, url: pageURL)
        tab.extensionRuntimeOpenNotifiedDocumentSequence = 0
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 0
        tab.noteCommittedMainDocumentNavigation(to: pageURL)

        XCTAssertFalse(manager.tabNeedsExtensionContentScriptRebind(tab))

        tab.noteCommittedMainDocumentNavigation(to: pageURL)

        XCTAssertTrue(manager.tabNeedsExtensionContentScriptRebind(tab))
    }

    func testPrepareExtensionRuntimeBeforeNavigationReNotifiesOnReload() throws {
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
        manager.tabOpenNotificationGeneration = 21

        let browserManager = BrowserManager()
        manager.attach(browserManager: browserManager)
        browserManager.profileManager.profiles = [profile]

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profile.id, url: pageURL)
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

        tab.extensionRuntimeOpenNotifiedDocumentSequence = 0
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 0
        tab.noteCommittedMainDocumentNavigation(to: pageURL)
        tab.lastExtensionOpenNotificationGeneration = manager.tabOpenNotificationGeneration
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration

        XCTAssertFalse(manager.tabNeedsExtensionContentScriptRebind(tab))

        let didCloseExpectation = expectation(description: "didCloseTab before reload commit")
        let didOpenExpectation = expectation(description: "didOpenTab before reload commit")
        manager.testHooks.didCloseTab = { tabID in
            if tabID == tab.id {
                didCloseExpectation.fulfill()
            }
        }
        manager.testHooks.didOpenTab = { tabID in
            if tabID == tab.id {
                didOpenExpectation.fulfill()
            }
        }

        manager.prepareExtensionRuntimeBeforeCommittedMainFrameNavigation(
            tab,
            destinationURL: pageURL,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        wait(for: [didCloseExpectation, didOpenExpectation], timeout: 2)
        XCTAssertEqual(tab.extensionRuntimeOpenNotifiedDocumentSequence, tab.extensionRuntimeDocumentSequence)
        XCTAssertEqual(
            tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration,
            manager.extensionContextBindingGeneration(for: profile.id)
        )

        tab.noteCommittedMainDocumentNavigation(to: pageURL)
        XCTAssertFalse(manager.tabNeedsExtensionContentScriptRebind(tab))
    }

    func testPrepareBeforeNavigationCyclesCloseOpenOnReload() throws {
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
        let controller = manager.ensureExtensionController(for: profile.id)
        manager.extensionsLoaded = true
        _ = controller

        let browserManager = BrowserManager()
        manager.attach(browserManager: browserManager)
        browserManager.profileManager.profiles = [profile]

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profile.id, url: pageURL)
        tab.browserManager = browserManager
        tab.extensionRuntimeOpenNotifiedDocumentSequence = 0
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 0
        tab.noteCommittedMainDocumentNavigation(to: pageURL)
        tab.extensionRuntimeEligibleGeneration = manager.tabOpenNotificationGeneration

        let didCloseExpectation = expectation(description: "didCloseTab before reload commit")
        let didOpenExpectation = expectation(description: "didOpenTab before reload commit")
        manager.testHooks.didCloseTab = { tabID in
            if tabID == tab.id {
                didCloseExpectation.fulfill()
            }
        }
        manager.testHooks.didOpenTab = { tabID in
            if tabID == tab.id {
                didOpenExpectation.fulfill()
            }
        }

        manager.prepareExtensionRuntimeBeforeCommittedMainFrameNavigation(
            tab,
            destinationURL: pageURL,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        wait(for: [didCloseExpectation, didOpenExpectation], timeout: 2)
    }

    func testTabNeedsRebindWhenExtensionContextBindingChanges() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profile.id, url: pageURL)
        tab.extensionRuntimeOpenNotifiedDocumentSequence = 0
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 0
        tab.noteCommittedMainDocumentNavigation(to: pageURL)

        XCTAssertFalse(manager.tabNeedsExtensionContentScriptRebind(tab))

        manager.bumpExtensionContextBindingGeneration(
            for: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertTrue(manager.tabNeedsExtensionContentScriptRebind(tab))
    }

    func testWrongControllerTriggersContentScriptRebind() throws {
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
        let controllerA = manager.ensureExtensionController(for: profileA.id)
        let controllerB = manager.ensureExtensionController(for: profileB.id)

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(profileId: profileA.id, url: pageURL)
        tab.extensionRuntimeOpenNotifiedDocumentSequence = 0
        tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration = 0
        tab.noteCommittedMainDocumentNavigation(to: pageURL)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        configuration.webExtensionController = controllerB
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.load(URLRequest(url: pageURL))
        tab._webView = webView

        XCTAssertTrue(manager.webViewNeedsExtensionRuntimeRebuild(webView, for: tab))
        XCTAssertTrue(manager.tabNeedsExtensionContentScriptRebind(tab))
        _ = controllerA
    }

    func testLifecycleNavigationResponderReNotifiesExtensionBeforeCommit() throws {
        let lifecyclePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sumi/Models/Tab/Navigation/SumiTabLifecycleNavigationResponder.swift")
        let lifecycleSource = try XCTUnwrap(
            String(contentsOf: lifecyclePath, encoding: .utf8)
        )
        XCTAssertTrue(
            lifecycleSource.contains("prepareExtensionRuntimeBeforeCommittedMainFrameNavigationIfLoaded")
        )
        XCTAssertTrue(lifecycleSource.contains("navigationType.isBackForward != true"))
    }

    func testEnsureExtensionControllerAttachedRebuildsWhenContentScriptRebindNeeded() throws {
        let profileRuntimePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sumi/Managers/ExtensionManager/ExtensionManager+ProfileRuntime.swift")
        let profileRuntimeSource = try XCTUnwrap(
            String(contentsOf: profileRuntimePath, encoding: .utf8)
        )
        XCTAssertTrue(profileRuntimeSource.contains("tabNeedsExtensionContentScriptRebind(tab)"))
        XCTAssertTrue(
            profileRuntimeSource.contains("resetExtensionRuntimeDocumentBindingForContentScriptRebind()")
        )
    }

    func testRegisterTabWithExtensionRuntimeAttachesControllerBeforeNotifying() throws {
        let profilesPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift")
        let profilesSource = try XCTUnwrap(
            String(contentsOf: profilesPath, encoding: .utf8)
        )
        let registerRange = try XCTUnwrap(
            profilesSource.range(of: "func registerTabWithExtensionRuntime")
        )
        let registerBody = String(profilesSource[registerRange.lowerBound...])
        let ensureIndex = try XCTUnwrap(
            registerBody.range(of: "ensureExtensionControllerAttachedForTab")?.lowerBound
        )
        let notifyIndex = try XCTUnwrap(
            registerBody.range(of: "notifyTabOpenedIfNeeded")?.lowerBound
        )
        XCTAssertLessThan(ensureIndex, notifyIndex)
    }

    func testPerformInstallationUpdatesWebViewsBeforeTabResync() throws {
        let installationPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sumi/Managers/ExtensionManager/ExtensionManager+Installation.swift")
        let installationSource = try XCTUnwrap(
            String(contentsOf: installationPath, encoding: .utf8)
        )
        let blockMarker = "tabOpenNotificationGeneration &+= 1"
        let blockStart = try XCTUnwrap(installationSource.range(of: blockMarker).map(\.lowerBound))
        let blockEnd = try XCTUnwrap(
            installationSource[blockStart...].range(
                of: "registerExistingWindowStateIfAttached()"
            )?.upperBound
        )
        let installBlock = String(installationSource[blockStart..<blockEnd])
        XCTAssertTrue(installBlock.contains("ExtensionManager.performInstallation.afterLoad"))
        let webViewIndex = try XCTUnwrap(installBlock.range(of: "updateWebViewsForProfile")?.lowerBound)
        let resyncIndex = try XCTUnwrap(
            installBlock.range(of: "resyncOpenTabsWithExtensionRuntimeAfterGenerationBump")?.lowerBound
        )
        XCTAssertLessThan(webViewIndex, resyncIndex)
    }

    func testContentScriptProbeExtensionDeclaresManifestCSS() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager
        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        let manifestURL = URL(fileURLWithPath: installed.packagePath)
            .appendingPathComponent("manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let contentScripts = manifest?["content_scripts"] as? [[String: Any]]
        let css = contentScripts?.first?["css"] as? [String]
        XCTAssertEqual(css, ["overlay.css"])
        XCTAssertTrue(
            ((manifest?["web_accessible_resources"] as? [[String: Any]])?.first?["resources"] as? [String])?
                .contains("overlay.html") == true
        )
    }

    func testConfigureContextIdentitySetsWebkitExtensionBaseURL() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager
        let extensionId = "probe-extension-id"
        let scratchDirectory = try makeScratchDirectory()
        let directoryURL = scratchDirectory.appendingPathComponent("BaseURLProbe", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Probe",
            "version": "1.0",
        ]
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: manifestURL, options: [.atomic])

        let webExtension = try await WKWebExtension(resourceBaseURL: directoryURL)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        manager.configureContextIdentity(
            extensionContext,
            extensionId: extensionId,
            profileId: profile.id
        )

        let baseURL = try XCTUnwrap(extensionContext.baseURL)
        XCTAssertEqual(baseURL.scheme, "webkit-extension")
        XCTAssertTrue(baseURL.host?.hasPrefix("ext-") == true)
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

    private func installContentScriptProbeExtension(
        manager: ExtensionManager,
        scratchDirectory: URL
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(
            "ContentScriptCSSProbe",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "ContentScriptCSSProbe",
            "version": "1.0",
            "host_permissions": ["<all_urls>"],
            "content_scripts": [[
                "matches": ["<all_urls>"],
                "js": ["content.js"],
                "css": ["overlay.css"],
                "run_at": "document_idle",
            ]],
            "web_accessible_resources": [[
                "resources": ["overlay.html"],
                "matches": ["<all_urls>"],
            ]],
        ]
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: manifestURL, options: [.atomic])
        try Data("true;".utf8)
            .write(to: directoryURL.appendingPathComponent("content.js"), options: [.atomic])
        try Data("iframe{height:1px;}".utf8)
            .write(to: directoryURL.appendingPathComponent("overlay.css"), options: [.atomic])
        try Data("<!doctype html><title>overlay</title>".utf8)
            .write(to: directoryURL.appendingPathComponent("overlay.html"), options: [.atomic])

        return try await manager.performInstallation(
            from: directoryURL,
            enableOnInstall: false
        )
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
