//
//  AuxiliaryWindowManagerTests.swift
//  SumiTests
//

import AppKit
@testable import Sumi
import SwiftData
import WebKit
import XCTest

@available(macOS 15.5, *)
@MainActor
final class AuxiliaryWindowManagerTests: XCTestCase {
    private final class RecordingWKWebView: WKWebView {
        private(set) var loadedRequestURLs: [URL] = []

        override func load(_ request: URLRequest) -> WKNavigation? {
            if let url = request.url {
                loadedRequestURLs.append(url)
            }
            return nil
        }
    }

    private struct Harness {
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
        let sourceTab: Tab
        let windowState: BrowserWindowState
    }

    private struct ExtensionHarness {
        let container: ModelContainer
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
        let extensionManager: ExtensionManager
        let sourceTab: Tab
        let profile: Profile
        let windowState: BrowserWindowState
        let extensionContext: WKWebExtensionContext
        let controller: WKWebExtensionController
    }

    func testCloseAllForExtensionIdClosesExternalAuthPopupWithoutContextOverride() {
        let harness = makeHarness()
        let extensionURL = URL(string: "safari-web-extension://owner-extension-id/popup.html")!
        harness.sourceTab.url = extensionURL

        let popupWebView = harness.browserManager.auxiliaryWindowManager.presentExtensionExternalWebPopup(
            configuration: WKWebViewConfiguration(),
            request: URLRequest(url: URL(string: "https://auth.example/login")!),
            windowFeatures: WKWindowFeatures(),
            openerTab: harness.sourceTab,
            extensionOwnedSourceURL: extensionURL
        )

        XCTAssertNotNil(popupWebView)
        XCTAssertEqual(
            harness.browserManager.auxiliaryWindowManager.ownerExtensionID(for: popupWebView!),
            "owner-extension-id"
        )
        XCTAssertNil(harness.sourceTab.webExtensionContextOverride)

        harness.browserManager.auxiliaryWindowManager.closeAll(forExtensionId: "owner-extension-id")
        XCTAssertFalse(harness.browserManager.auxiliaryWindowManager.contains(webView: popupWebView!))
    }

    func testCloseAllForExtensionIdPreservesUnrelatedWebPopup() {
        let harness = makeHarness()

        let popupWebView = harness.browserManager.auxiliaryWindowManager.presentWebPopup(
            configuration: WKWebViewConfiguration(),
            request: URLRequest(url: URL(string: "https://example.com/popup")!),
            windowFeatures: WKWindowFeatures(),
            openerTab: harness.sourceTab
        )

        XCTAssertNotNil(popupWebView, "Expected generic web popup to open")
        XCTAssertNil(
            harness.browserManager.auxiliaryWindowManager.ownerExtensionID(for: popupWebView!),
            "Generic web popup must not inherit extension ownership"
        )

        harness.browserManager.auxiliaryWindowManager.closeAll(forExtensionId: "owner-extension-id")
        XCTAssertTrue(harness.browserManager.auxiliaryWindowManager.contains(webView: popupWebView!))

        harness.browserManager.auxiliaryWindowManager.closeAll(reason: .managerCloseAll)
    }

    func testCloseAllForExtensionIdRemovesRegisteredMiniWindowAdapter() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Auxiliary Owner")
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionManager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration()
        )
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in extensionManager }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule
        )
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        extensionsModule.attach(browserManager: browserManager)
        extensionManager.attach(browserManager: browserManager)
        XCTAssertIdentical(extensionsModule.managerIfEnabled(), extensionManager)
        extensionManager.extensionsLoaded = true

        let sourceTab = browserManager.tabManager.createNewTab(
            url: "safari-web-extension://adapter-owner/popup.html",
            in: browserManager.tabManager.currentSpace,
            activate: true
        )
        sourceTab.profileId = profile.id

        let extensionURL = URL(string: "safari-web-extension://adapter-owner/popup.html")!
        let popupWebView = browserManager.auxiliaryWindowManager.presentExtensionExternalWebPopup(
            configuration: WKWebViewConfiguration(),
            request: URLRequest(url: URL(string: "https://auth.example/login")!),
            windowFeatures: WKWindowFeatures(),
            openerTab: sourceTab,
            extensionOwnedSourceURL: extensionURL
        )
        XCTAssertNotNil(popupWebView)
        XCTAssertFalse(extensionManager.adapterStore.miniWindowAdapters.isEmpty)

        browserManager.auxiliaryWindowManager.closeAll(forExtensionId: "adapter-owner")
        XCTAssertTrue(extensionManager.adapterStore.miniWindowAdapters.isEmpty)
        XCTAssertFalse(browserManager.auxiliaryWindowManager.contains(webView: popupWebView!))
    }

    func testParentWindowFrameUnchangedAfterPresentExtensionExternalWebPopupWithExtensionHarness() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Auxiliary Owner")
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionManager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration()
        )
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in extensionManager }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule
        )
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        extensionsModule.attach(browserManager: browserManager)
        extensionManager.attach(browserManager: browserManager)
        XCTAssertIdentical(extensionsModule.managerIfEnabled(), extensionManager)
        extensionManager.extensionsLoaded = true

        let sourceTab = browserManager.tabManager.createNewTab(
            url: "safari-web-extension://adapter-owner/popup.html",
            in: browserManager.tabManager.currentSpace,
            activate: true
        )
        sourceTab.profileId = profile.id

        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = browserManager.tabManager.currentSpace?.id
        windowState.currentProfileId = browserManager.currentProfile?.id
        windowState.window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        browserManager.windowRegistry = windowRegistry

        let originalMainFrame = windowState.window!.frame
        let extensionURL = URL(string: "safari-web-extension://adapter-owner/popup.html")!
        sourceTab.url = extensionURL

        let popupWebView = browserManager.auxiliaryWindowManager.presentExtensionExternalWebPopup(
            configuration: WKWebViewConfiguration(),
            request: URLRequest(url: URL(string: "https://auth.example/login")!),
            windowFeatures: WKWindowFeatures(),
            openerTab: sourceTab,
            extensionOwnedSourceURL: extensionURL
        )

        XCTAssertNotNil(popupWebView)
        XCTAssertEqual(windowState.window!.frame, originalMainFrame)
    }

    func testActionPopupWindowOpenRoutesExternalURLToNormalTab() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "action-owner")
        let sourceURL = URL(string: "safari-web-extension://action-owner/popup.html")!
        let targetURL = URL(string: "https://account.example.test/login")!
        let mainWindow = try XCTUnwrap(harness.windowState.window)
        let originalMainFrame = mainWindow.frame
        let initialRegularTabCount = harness.browserManager.tabManager.tabsBySpace[
            harness.browserManager.tabManager.currentSpace!.id
        ]?.count ?? 0
        let delegate = ExtensionActionPopupUIDelegate(
            manager: harness.extensionManager,
            popover: NSPopover()
        )
        let popupWebView = WKWebView(frame: .zero)
        let action = popupNavigationAction(
            sourceURL: sourceURL,
            targetURL: targetURL,
            webView: popupWebView
        )

        let childWebView = delegate.webView(
            popupWebView,
            createWebViewWith: WKWebViewConfiguration(),
            for: action,
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        XCTAssertTrue(harness.browserManager.tabManager.auxiliaryMiniWindowTabsByID.isEmpty)
        XCTAssertEqual(
            harness.browserManager.tabManager.tabsBySpace[
                harness.browserManager.tabManager.currentSpace!.id
            ]?.count,
            initialRegularTabCount + 1
        )
        let openedTab = try XCTUnwrap(harness.browserManager.tabManager.tabs.last)
        XCTAssertEqual(openedTab.url, targetURL)
        XCTAssertEqual(openedTab.profileId, harness.profile.id)
        XCTAssertFalse(openedTab.isAuxiliaryMiniWindow)
        XCTAssertFalse(openedTab.isPopupHost)
        XCTAssertEqual(mainWindow.frame, originalMainFrame)
    }

    func testPrivateExtensionPopupWindowIsBlockedBeforeProfileRuntimeMaterializes() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "private-popup-owner")
        let configuration = AuxiliaryWindowConfigurationMock(
            windowType: .popup,
            tabURLs: [URL(string: "safari-web-extension://private-popup-owner/popup.html")!],
            shouldBePrivate: true
        ).windowConfiguration

        XCTAssertNil(harness.extensionManager.extensionController)

        let adapter = await harness.browserManager.auxiliaryWindowManager.presentExtensionPopupWindow(
            configuration: configuration,
            controller: harness.controller,
            extensionContext: harness.extensionContext,
            extensionManager: harness.extensionManager,
            parentWindow: harness.windowState.window
        )

        XCTAssertNil(adapter)
        XCTAssertTrue(harness.browserManager.tabManager.auxiliaryMiniWindowTabsByID.isEmpty)
        XCTAssertTrue(harness.extensionManager.adapterStore.miniWindowAdapters.isEmpty)
        XCTAssertNil(
            harness.extensionManager.extensionController,
            "Private extension popups must not create the normal profile-backed extension controller"
        )
    }

    func testNonPrivateExtensionPopupWindowStillUsesProfileRuntime() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "normal-popup-owner")
        let configuration = AuxiliaryWindowConfigurationMock(
            windowType: .popup,
            tabURLs: [URL(string: "safari-web-extension://normal-popup-owner/popup.html")!],
            shouldBePrivate: false
        ).windowConfiguration

        let maybeAdapter = await harness.browserManager.auxiliaryWindowManager
            .presentExtensionPopupWindow(
                configuration: configuration,
                controller: harness.controller,
                extensionContext: harness.extensionContext,
                extensionManager: harness.extensionManager,
                parentWindow: harness.windowState.window
            )
        let adapter = try XCTUnwrap(maybeAdapter)
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindowManager.session(for: adapter.sessionId)
        )
        defer {
            harness.browserManager.auxiliaryWindowManager.teardown(
                for: session.webView,
                reason: .managerCloseAll
            )
        }

        XCTAssertFalse(session.isPrivate)
        XCTAssertIdentical(
            session.webView.configuration.websiteDataStore,
            harness.extensionManager.getExtensionDataStore(for: harness.profile.id)
        )
        XCTAssertIdentical(
            session.webView.configuration.webExtensionController,
            harness.extensionManager.ensureExtensionController(for: harness.profile.id)
        )
    }

    func testPrivateExtensionNormalWindowIsRejectedBeforeTabCreation() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "private-window-owner")
        let initialRegularTabCount = harness.browserManager.tabManager.tabsBySpace.values
            .flatMap { $0 }
            .filter { $0.isAuxiliaryMiniWindow == false }
            .count
        let openedWindow = expectation(description: "private extension window rejected")
        var completionWindow: (any WKWebExtensionWindow)?
        var completionError: (any Error)?
        let configuration = AuxiliaryWindowConfigurationMock(
            windowType: .normal,
            tabURLs: [URL(string: "https://account.example.test/private")!],
            shouldBePrivate: true
        ).windowConfiguration

        harness.extensionManager.webExtensionController(
            harness.controller,
            openNewWindowUsing: configuration,
            for: harness.extensionContext
        ) { window, error in
            completionWindow = window
            completionError = error
            openedWindow.fulfill()
        }

        await fulfillment(of: [openedWindow], timeout: 2.0)

        XCTAssertNil(completionWindow)
        XCTAssertNotNil(completionError)
        XCTAssertTrue(harness.browserManager.tabManager.auxiliaryMiniWindowTabsByID.isEmpty)
        XCTAssertEqual(
            harness.browserManager.tabManager.tabsBySpace.values
                .flatMap { $0 }
                .filter { $0.isAuxiliaryMiniWindow == false }
                .count,
            initialRegularTabCount
        )
        XCTAssertNil(
            harness.extensionManager.extensionController,
            "Private extension windows must not create the normal profile-backed extension controller"
        )
    }

    func testExtensionRequestedTeardownClosesAuxiliaryMiniWindowSession() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Auxiliary Owner")
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionManager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration()
        )
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in extensionManager }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule
        )
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        extensionsModule.attach(browserManager: browserManager)
        extensionManager.attach(browserManager: browserManager)
        XCTAssertIdentical(extensionsModule.managerIfEnabled(), extensionManager)
        extensionManager.extensionsLoaded = true

        let sourceTab = browserManager.tabManager.createNewTab(
            url: "safari-web-extension://adapter-owner/popup.html",
            in: browserManager.tabManager.currentSpace,
            activate: true
        )
        sourceTab.profileId = profile.id

        let extensionURL = URL(string: "safari-web-extension://adapter-owner/popup.html")!
        let popupWebView = try XCTUnwrap(
            browserManager.auxiliaryWindowManager.presentExtensionExternalWebPopup(
                configuration: WKWebViewConfiguration(),
                request: URLRequest(url: URL(string: "https://auth.example/login")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: sourceTab,
                extensionOwnedSourceURL: extensionURL
            )
        )
        XCTAssertFalse(extensionManager.adapterStore.miniWindowAdapters.isEmpty)

        browserManager.auxiliaryWindowManager.teardown(
            for: popupWebView,
            reason: .extensionRequestedClose
        )

        XCTAssertFalse(browserManager.auxiliaryWindowManager.contains(webView: popupWebView))
        XCTAssertTrue(extensionManager.adapterStore.miniWindowAdapters.isEmpty)
    }

    func testRemoveTabAuxiliaryRoutesThroughFullTeardown() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Auxiliary Owner")
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionManager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration()
        )
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in extensionManager }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule
        )
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        extensionsModule.attach(browserManager: browserManager)
        extensionManager.attach(browserManager: browserManager)
        XCTAssertIdentical(extensionsModule.managerIfEnabled(), extensionManager)
        extensionManager.extensionsLoaded = true

        let sourceTab = browserManager.tabManager.createNewTab(
            url: "safari-web-extension://adapter-owner/popup.html",
            in: browserManager.tabManager.currentSpace,
            activate: true
        )
        sourceTab.profileId = profile.id

        let extensionURL = URL(string: "safari-web-extension://adapter-owner/popup.html")!
        let popupWebView = try XCTUnwrap(
            browserManager.auxiliaryWindowManager.presentExtensionExternalWebPopup(
                configuration: WKWebViewConfiguration(),
                request: URLRequest(url: URL(string: "https://auth.example/login")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: sourceTab,
                extensionOwnedSourceURL: extensionURL
            )
        )
        XCTAssertFalse(extensionManager.adapterStore.miniWindowAdapters.isEmpty)
        let auxiliaryTab = try XCTUnwrap(
            browserManager.tabManager.auxiliaryMiniWindowTabsByID.values.first
        )

        browserManager.tabManager.removeTab(auxiliaryTab.id)

        XCTAssertFalse(browserManager.auxiliaryWindowManager.contains(webView: popupWebView))
        XCTAssertTrue(extensionManager.adapterStore.miniWindowAdapters.isEmpty)
        XCTAssertNil(browserManager.tabManager.auxiliaryMiniWindowTabsByID[auxiliaryTab.id])
    }

    func testFocusedMiniWindowAdapterDoesNotCrossContaminateBetweenExtensions() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Auxiliary Owner")
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionManager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration()
        )
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in extensionManager }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule
        )
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        extensionsModule.attach(browserManager: browserManager)
        extensionManager.attach(browserManager: browserManager)
        XCTAssertIdentical(extensionsModule.managerIfEnabled(), extensionManager)
        extensionManager.extensionsLoaded = true

        let sourceTab = browserManager.tabManager.createNewTab(
            url: "safari-web-extension://adapter-owner/popup.html",
            in: browserManager.tabManager.currentSpace,
            activate: true
        )
        sourceTab.profileId = profile.id

        let manager = browserManager.auxiliaryWindowManager

        _ = manager.presentExtensionExternalWebPopup(
            configuration: WKWebViewConfiguration(),
            request: URLRequest(url: URL(string: "https://auth-a.example/login")!),
            windowFeatures: WKWindowFeatures(),
            openerTab: sourceTab,
            extensionOwnedSourceURL: URL(string: "safari-web-extension://owner-a/popup.html")!
        )
        _ = manager.presentExtensionExternalWebPopup(
            configuration: WKWebViewConfiguration(),
            request: URLRequest(url: URL(string: "https://auth-b.example/login")!),
            windowFeatures: WKWindowFeatures(),
            openerTab: sourceTab,
            extensionOwnedSourceURL: URL(string: "safari-web-extension://owner-b/popup.html")!
        )

        let adapterA = manager.focusedMiniWindowAdapter(forOwnerExtensionID: "owner-a")
        let adapterB = manager.focusedMiniWindowAdapter(forOwnerExtensionID: "owner-b")

        XCTAssertNotNil(adapterA)
        XCTAssertNotNil(adapterB)
        XCTAssertNotEqual(adapterA?.sessionId, adapterB?.sessionId)
    }

    func testFocusedWindowForExtensionContextPrefersOwnerMiniWindowBeforeMainWindow() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "adapter-owner")
        let mainWindow = try XCTUnwrap(harness.windowState.window)
        mainWindow.makeKeyAndOrderFront(nil)

        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindowManager.presentExtensionExternalWebPopup(
                configuration: WKWebViewConfiguration(),
                request: URLRequest(url: URL(string: "https://auth.example/login")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: URL(string: "safari-web-extension://adapter-owner/popup.html")!
            )
        )
        defer {
            harness.browserManager.auxiliaryWindowManager.teardown(
                for: popupWebView,
                reason: .managerCloseAll
            )
        }

        mainWindow.makeKeyAndOrderFront(nil)

        let focusedWindow = harness.extensionManager.webExtensionController(
            harness.controller,
            focusedWindowFor: harness.extensionContext
        )
        let focusedMiniWindow = focusedWindow as? ExtensionMiniWindowAdapter

        XCTAssertNotNil(focusedMiniWindow)
        XCTAssertEqual(
            focusedMiniWindow?.sessionId,
            harness.extensionManager.extensionMiniWindowAdapters(
                ownerExtensionID: "adapter-owner",
                profileId: harness.profile.id
            ).first?.sessionId
        )
    }

    func testOpenWindowsForExtensionContextOrdersOwnerMiniWindowBeforeMainWindow() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "adapter-owner")
        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindowManager.presentExtensionExternalWebPopup(
                configuration: WKWebViewConfiguration(),
                request: URLRequest(url: URL(string: "https://auth.example/login")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: URL(string: "safari-web-extension://adapter-owner/popup.html")!
            )
        )
        defer {
            harness.browserManager.auxiliaryWindowManager.teardown(
                for: popupWebView,
                reason: .managerCloseAll
            )
        }
        XCTAssertEqual(
            harness.browserManager.auxiliaryWindowManager.ownerExtensionID(for: popupWebView),
            "adapter-owner"
        )
        XCTAssertFalse(
            harness.extensionManager.adapterStore.miniWindowAdapters.isEmpty,
            "Expected extension-owned mini-window presentation to register a mini-window adapter"
        )

        let openWindows = harness.extensionManager.webExtensionController(
            harness.controller,
            openWindowsFor: harness.extensionContext
        )
        let ownerMiniWindowAdapter = try XCTUnwrap(
            harness.extensionManager.extensionMiniWindowAdapters(
                ownerExtensionID: "adapter-owner",
                profileId: harness.profile.id
            ).first
        )
        let mainWindowAdapter = try XCTUnwrap(
            harness.extensionManager.windowAdapter(for: harness.windowState.id)
        )

        let firstOpenWindow = try XCTUnwrap(openWindows.first)
        XCTAssertTrue((firstOpenWindow as AnyObject) === ownerMiniWindowAdapter)
        XCTAssertTrue(
            openWindows.dropFirst().contains { window in
                (window as AnyObject) === mainWindowAdapter
            }
        )
    }

    func testFocusedMiniWindowSetFrameDoesNotMutateParentWindowFrame() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "adapter-owner")
        let mainWindow = try XCTUnwrap(harness.windowState.window)
        let originalMainFrame = mainWindow.frame

        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindowManager.presentExtensionExternalWebPopup(
                configuration: WKWebViewConfiguration(),
                request: URLRequest(url: URL(string: "https://auth.example/login")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: URL(string: "safari-web-extension://adapter-owner/popup.html")!
            )
        )
        defer {
            harness.browserManager.auxiliaryWindowManager.teardown(
                for: popupWebView,
                reason: .managerCloseAll
            )
        }

        let focusedWindow = try XCTUnwrap(
            harness.extensionManager.webExtensionController(
                harness.controller,
                focusedWindowFor: harness.extensionContext
            ) as? ExtensionMiniWindowAdapter
        )
        let resizedFrame = NSRect(x: 180, y: 160, width: 500, height: 620)
        var callbackError: Error?

        focusedWindow.setFrame(resizedFrame, for: harness.extensionContext) { error in
            callbackError = error
        }

        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindowManager.session(for: focusedWindow.sessionId)
        )
        XCTAssertNil(callbackError)
        XCTAssertEqual(mainWindow.frame, originalMainFrame)
        XCTAssertEqual(session.window.frame, resizedFrame)
    }

    func testAuxiliaryMiniWindowFocusSurvivesMainWindowFocusNotification() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "adapter-owner")

        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindowManager.presentExtensionExternalWebPopup(
                configuration: WKWebViewConfiguration(),
                request: URLRequest(url: URL(string: "https://auth.example/login")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: URL(string: "safari-web-extension://adapter-owner/popup.html")!
            )
        )
        defer {
            harness.browserManager.auxiliaryWindowManager.teardown(
                for: popupWebView,
                reason: .managerCloseAll
            )
        }

        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindowManager.session(for: popupWebView)
        )
        session.window.makeKeyAndOrderFront(nil)
        harness.extensionManager.notifyWindowFocused(harness.windowState)

        let focusedWindow = harness.extensionContext.focusedWindow as? ExtensionMiniWindowAdapter

        XCTAssertEqual(focusedWindow?.sessionId, session.id)
    }

    func testExtensionRequestedExternalTabFromMiniWindowCreatesNormalSameProfileTab() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "adapter-owner")
        let mainWindow = try XCTUnwrap(harness.windowState.window)
        let originalMainFrame = mainWindow.frame
        let initialRegularTabCount = harness.browserManager.tabManager.tabsBySpace[
            harness.browserManager.tabManager.currentSpace!.id
        ]?.count ?? 0

        let sourcePopupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindowManager.presentExtensionExternalWebPopup(
                configuration: WKWebViewConfiguration(),
                request: URLRequest(url: URL(string: "https://popup.example/start")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: URL(string: "safari-web-extension://adapter-owner/popup.html")!
            )
        )
        defer {
            harness.browserManager.auxiliaryWindowManager.closeAll(reason: .managerCloseAll)
        }

        let sourceMiniWindow = try XCTUnwrap(
            harness.extensionManager.extensionMiniWindowAdapters(
                ownerExtensionID: "adapter-owner",
                profileId: harness.profile.id
            ).first
        )
        let authURL = URL(string: "https://account.example.test/login?client_id=abc")!

        let authTab = try harness.extensionManager.openExtensionRequestedTab(
            url: authURL,
            shouldBeActive: true,
            shouldBePinned: false,
            requestedWindow: sourceMiniWindow,
            controller: harness.controller,
            extensionContext: harness.extensionContext,
            reason: "AuxiliaryWindowManagerTests"
        )

        XCTAssertTrue(harness.browserManager.auxiliaryWindowManager.contains(webView: sourcePopupWebView))
        XCTAssertFalse(harness.browserManager.tabManager.isAuxiliaryMiniWindowTab(authTab))
        XCTAssertFalse(authTab.isAuxiliaryMiniWindow)
        XCTAssertFalse(authTab.isPopupHost)
        XCTAssertEqual(authTab.profileId, harness.profile.id)
        XCTAssertEqual(authTab.spaceId, harness.browserManager.tabManager.currentSpace?.id)
        XCTAssertEqual(mainWindow.frame, originalMainFrame)
        XCTAssertEqual(
            harness.browserManager.tabManager.tabsBySpace[
                harness.browserManager.tabManager.currentSpace!.id
            ]?.count,
            initialRegularTabCount + 1
        )
        XCTAssertNil(harness.browserManager.auxiliaryWindowManager.session(for: authTab))
        XCTAssertEqual(harness.windowState.currentTabId, authTab.id)

        harness.extensionManager.extensionRuntimeAllowsWithoutEnabledExtensions = true
        let webView = try XCTUnwrap(authTab.assignedWebView ?? authTab.existingWebView)
        harness.extensionManager.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: nil,
            reason: "AuxiliaryWindowManagerTests.materializedExternalNormalTab"
        )
        harness.extensionManager.registerExtensionCreatedTabWithExtensionRuntime(
            authTab,
            reason: "AuxiliaryWindowManagerTests.materializedExternalNormalTab"
        )
        XCTAssertIdentical(
            webView.configuration.websiteDataStore,
            harness.extensionManager.getExtensionDataStore(for: harness.profile.id)
        )
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            harness.extensionManager.ensureExtensionController(for: harness.profile.id)
        )
        XCTAssertNotNil(harness.extensionManager.stableAdapter(for: authTab))
        XCTAssertTrue(authTab.extensionPageRuntimeOwner.didNotifyOpenToExtensions)
    }

    func testExtensionExternalWindowCreateUsesNormalBrowserTab() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "adapter-owner")
        let mainWindow = try XCTUnwrap(harness.windowState.window)
        let originalMainFrame = mainWindow.frame
        let initialRegularTabCount = harness.browserManager.tabManager.tabsBySpace[
            harness.browserManager.tabManager.currentSpace!.id
        ]?.count ?? 0
        let openedWindow = expectation(description: "extension external tab opened")
        var createWindowCallCount = 0
        var completionWindow: (any WKWebExtensionWindow)?
        var completionError: (any Error)?
        let authURL = URL(string: "https://account.example.test/login?client_id=abc")!

        harness.extensionManager.openExtensionWindowUsingTabURLs(
            [authURL],
            controller: harness.controller,
            extensionContext: harness.extensionContext,
            createWindow: {
                createWindowCallCount += 1
            },
            awaitWindowRegistration: { _ in
                nil
            },
            completionHandler: { window, error in
                completionWindow = window
                completionError = error
                openedWindow.fulfill()
            }
        )

        await fulfillment(of: [openedWindow], timeout: 2.0)

        XCTAssertNil(completionError)
        let window = try XCTUnwrap(completionWindow as? ExtensionWindowAdapter)
        XCTAssertEqual(window.windowId, harness.windowState.id)
        XCTAssertEqual(createWindowCallCount, 0)
        XCTAssertEqual(mainWindow.frame, originalMainFrame)
        let authTab = try await waitForRegularTab(
            with: authURL,
            in: harness.browserManager.tabManager
        )
        let authSpaceId = try XCTUnwrap(authTab.spaceId)
        XCTAssertEqual(
            harness.browserManager.tabManager.tabsBySpace[authSpaceId]?.count,
            initialRegularTabCount + 1
        )
        XCTAssertEqual(authTab.url, authURL)
        XCTAssertEqual(authTab.profileId, harness.profile.id)
        XCTAssertFalse(authTab.isAuxiliaryMiniWindow)
        XCTAssertFalse(authTab.isPopupHost)
        XCTAssertNil(authTab.webExtensionContextOverride)
        XCTAssertNil(harness.browserManager.auxiliaryWindowManager.session(for: authTab))
    }

    func testExtensionAuxiliaryMiniWindowNotifiesOwnerContextWindowLifecycle() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "adapter-owner")
        let extensionURL = URL(string: "safari-web-extension://adapter-owner/popup.html")!

        XCTAssertTrue(harness.extensionContext.openWindows.isEmpty)
        XCTAssertNil(harness.extensionContext.focusedWindow)

        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindowManager.presentExtensionExternalWebPopup(
                configuration: WKWebViewConfiguration(),
                request: URLRequest(url: URL(string: "https://auth.example/login")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: extensionURL
            )
        )
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindowManager.session(for: popupWebView)
        )

        let openedMiniWindow = try XCTUnwrap(
            harness.extensionContext.openWindows.first as? ExtensionMiniWindowAdapter
        )
        XCTAssertEqual(openedMiniWindow.sessionId, session.id)
        XCTAssertEqual(
            (harness.extensionContext.focusedWindow as? ExtensionMiniWindowAdapter)?.sessionId,
            session.id
        )

        harness.browserManager.auxiliaryWindowManager.closeAll(forExtensionId: "adapter-owner")
        XCTAssertFalse(
            harness.extensionContext.openWindows.contains { window in
                (window as? ExtensionMiniWindowAdapter)?.sessionId == session.id
            }
        )
    }

    func testMaxNestedDepthBlocksSizedPopupWithoutInPlaceLoad() {
        let harness = makeHarness()
        let manager = harness.browserManager.auxiliaryWindowManager

        XCTAssertNil(
            manager.presentWebPopup(
                configuration: WKWebViewConfiguration(),
                request: URLRequest(url: URL(string: "https://example.com/nested-sized")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                nestedDepth: manager.maxNestedDepth
            ),
            "Sized and unsized popups must be blocked once nested depth reaches maxNestedDepth"
        )
    }

    func testUnsizedNestedPopupStillUsesConfiguredInPlacePolicy() {
        let harness = makeHarness()
        let manager = harness.browserManager.auxiliaryWindowManager
        let delegate = AuxiliaryWindowUIDelegate(
            manager: manager,
            openerTab: harness.sourceTab,
            nestedDepth: manager.maxNestedDepth
        )
        let recordingWebView = RecordingWKWebView()
        let targetURL = URL(string: "https://example.com/nested-unsized")!
        let action = popupNavigationAction(
            sourceURL: harness.sourceTab.url,
            targetURL: targetURL,
            webView: recordingWebView
        )

        let childWebView = delegate.webView(
            recordingWebView,
            createWebViewWith: WKWebViewConfiguration(),
            for: action,
            windowFeatures: WKWindowFeatures()
        )

        XCTAssertNil(childWebView)
        XCTAssertEqual(recordingWebView.loadedRequestURLs, [targetURL])
    }

    func testPrivatePopupTabStaysEphemeralAndOutOfRegularPersistence() throws {
        let harness = makeHarness()
        let privateProfile = Profile.createEphemeral()
        let privateWindow = BrowserWindowState()
        privateWindow.tabManager = harness.browserManager.tabManager
        privateWindow.isIncognito = true
        privateWindow.ephemeralProfile = privateProfile
        privateWindow.window = NSWindow(
            contentRect: NSRect(x: 160, y: 160, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        harness.windowRegistry.register(privateWindow)

        let sourceTab = harness.browserManager.tabManager.createEphemeralTab(
            url: URL(string: "https://private.example/source")!,
            in: privateWindow,
            profile: privateProfile
        )
        let regularTabCount = harness.browserManager.tabManager.tabsBySpace.values
            .flatMap { $0 }
            .count

        let popupTab = try XCTUnwrap(
            harness.browserManager.createPopupTab(
                from: sourceTab,
                activate: false
            )
        )

        XCTAssertTrue(popupTab.isEphemeral)
        XCTAssertTrue(popupTab.isPopupHost)
        XCTAssertNil(popupTab.spaceId)
        XCTAssertEqual(popupTab.profileId, privateProfile.id)
        XCTAssertTrue(privateWindow.ephemeralTabs.contains { $0.id == popupTab.id })
        XCTAssertEqual(privateWindow.currentTabId, sourceTab.id)
        XCTAssertEqual(
            harness.browserManager.tabManager.tabsBySpace.values.flatMap { $0 }.count,
            regularTabCount
        )
        XCTAssertFalse(harness.browserManager.tabManager.shouldPersistRegularTab(popupTab))
    }

    private func makeHarness() -> Harness {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.sumiSettings = settings
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        windowState.window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let sourceTab = browserManager.tabManager.createNewTab(
            url: "https://source.example/page",
            in: space,
            activate: true
        )
        browserManager.selectTab(sourceTab, in: windowState)

        return Harness(
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            sourceTab: sourceTab,
            windowState: windowState
        )
    }

    private func makeExtensionHarness(
        ownerExtensionID: String
    ) async throws -> ExtensionHarness {
        let container = try makeTestContainer()
        let profile = Profile(name: "Auxiliary Owner")
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionManager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration()
        )
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in extensionManager }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule
        )
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        extensionsModule.attach(browserManager: browserManager)
        extensionManager.attach(browserManager: browserManager)
        XCTAssertIdentical(extensionsModule.managerIfEnabled(), extensionManager)
        extensionManager.extensionsLoaded = true

        let windowRegistry = WindowRegistry()
        let space = Space(name: "Primary", profileId: profile.id)
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        windowState.window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let sourceTab = browserManager.tabManager.createNewTab(
            url: "safari-web-extension://\(ownerExtensionID)/popup.html",
            in: space,
            activate: true
        )
        sourceTab.profileId = profile.id
        browserManager.selectTab(sourceTab, in: windowState)

        let extensionContext = try await makeExtensionContext(
            ownerExtensionID: ownerExtensionID
        )
        extensionManager.setExtensionContext(
            extensionContext,
            extensionId: ownerExtensionID,
            profileId: profile.id
        )
        let controller = WKWebExtensionController(
            configuration: .nonPersistent()
        )

        return ExtensionHarness(
            container: container,
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            extensionManager: extensionManager,
            sourceTab: sourceTab,
            profile: profile,
            windowState: windowState,
            extensionContext: extensionContext,
            controller: controller
        )
    }

    private func makeExtensionContext(
        ownerExtensionID: String
    ) async throws -> WKWebExtensionContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Auxiliary \(ownerExtensionID)",
            "version": "1.0",
            "permissions": ["tabs", "windows"],
            "action": ["default_popup": "popup.html"],
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        )
        try manifestData.write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        try Data("<!doctype html><title>popup</title>".utf8)
            .write(to: directory.appendingPathComponent("popup.html"), options: [.atomic])

        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        return WKWebExtensionContext(for: webExtension)
    }

    private func waitForRegularTab(
        with url: URL,
        in tabManager: TabManager,
        timeout: TimeInterval = 2.0
    ) async throws -> Tab {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let tab = tabManager.tabsBySpace.values
                .flatMap({ $0 })
                .first(where: { $0.url == url && $0.isAuxiliaryMiniWindow == false }) {
                return tab
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        } while Date() < deadline

        return try XCTUnwrap(
            tabManager.tabsBySpace.values
                .flatMap({ $0 })
                .first(where: { $0.url == url && $0.isAuxiliaryMiniWindow == false })
        )
    }

    private func popupNavigationAction(
        sourceURL: URL?,
        targetURL: URL,
        webView: WKWebView
    ) -> WKNavigationAction {
        let sourceFrame = sourceURL.map {
            AuxiliaryWindowNavigationFrameMock(
                isMainFrame: true,
                request: URLRequest(url: $0),
                securityOrigin: AuxiliaryWindowSecurityOriginMock.new(url: $0),
                webView: webView
            ).frameInfo
        }
        return AuxiliaryWindowNavigationActionMock(
            sourceFrame: sourceFrame,
            targetFrame: nil,
            navigationType: .linkActivated,
            request: URLRequest(url: targetURL)
        ).navigationAction
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private final class AuxiliaryWindowConfigurationMock: NSObject {
    @objc var windowType: WKWebExtension.WindowType
    @objc var windowState: WKWebExtension.WindowState
    @objc var frame: CGRect
    @objc var tabURLs: [URL]
    @objc var tabs: [Any]
    @objc var shouldBeFocused: Bool
    @objc var shouldBePrivate: Bool

    init(
        windowType: WKWebExtension.WindowType,
        windowState: WKWebExtension.WindowState = .normal,
        frame: CGRect = CGRect(
            x: CGFloat.nan,
            y: CGFloat.nan,
            width: CGFloat.nan,
            height: CGFloat.nan
        ),
        tabURLs: [URL] = [],
        tabs: [Any] = [],
        shouldBeFocused: Bool = false,
        shouldBePrivate: Bool
    ) {
        self.windowType = windowType
        self.windowState = windowState
        self.frame = frame
        self.tabURLs = tabURLs
        self.tabs = tabs
        self.shouldBeFocused = shouldBeFocused
        self.shouldBePrivate = shouldBePrivate
        super.init()
    }

    var windowConfiguration: WKWebExtension.WindowConfiguration {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(
                to: WKWebExtension.WindowConfiguration.self,
                capacity: 1
            ) { $0 }
        }.pointee
    }
}

@available(macOS 15.5, *)
private final class AuxiliaryWindowNavigationActionMock: NSObject {
    @objc var sourceFrame: WKFrameInfo?
    @objc var targetFrame: WKFrameInfo?
    @objc var navigationType: WKNavigationType
    @objc var request: URLRequest
    @objc var isUserInitiated: Bool

    init(
        sourceFrame: WKFrameInfo?,
        targetFrame: WKFrameInfo?,
        navigationType: WKNavigationType,
        request: URLRequest,
        isUserInitiated: Bool = false
    ) {
        self.sourceFrame = sourceFrame
        self.targetFrame = targetFrame
        self.navigationType = navigationType
        self.request = request
        self.isUserInitiated = isUserInitiated
    }

    var navigationAction: WKNavigationAction {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(to: WKNavigationAction.self, capacity: 1) { $0 }
        }.pointee
    }
}

@available(macOS 15.5, *)
private final class AuxiliaryWindowNavigationFrameMock: NSObject {
    @objc var isMainFrame: Bool
    @objc var request: URLRequest?
    @objc var securityOrigin: WKSecurityOrigin
    @objc weak var webView: WKWebView?

    init(
        isMainFrame: Bool,
        request: URLRequest?,
        securityOrigin: WKSecurityOrigin,
        webView: WKWebView?
    ) {
        self.isMainFrame = isMainFrame
        self.request = request
        self.securityOrigin = securityOrigin
        self.webView = webView
    }

    var frameInfo: WKFrameInfo {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(to: WKFrameInfo.self, capacity: 1) { $0 }
        }.pointee
    }
}

@available(macOS 15.5, *)
@objc
private final class AuxiliaryWindowSecurityOriginMock: WKSecurityOrigin {
    private var mockedProtocol = ""
    private var mockedHost = ""
    private var mockedPort = 0

    override var `protocol`: String { mockedProtocol }
    override var host: String { mockedHost }
    override var port: Int { mockedPort }

    private func setURL(_ url: URL) {
        mockedProtocol = url.scheme ?? ""
        mockedHost = url.host ?? ""
        mockedPort = url.port ?? 0
    }

    static func new(url: URL) -> AuxiliaryWindowSecurityOriginMock {
        let mock = perform(NSSelectorFromString("alloc"))
            .takeUnretainedValue() as! AuxiliaryWindowSecurityOriginMock
        mock.setURL(url)
        return mock
    }
}
