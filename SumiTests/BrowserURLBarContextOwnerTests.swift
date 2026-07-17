import AppKit
import SwiftUI
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserURLBarContextOwnerTests: XCTestCase {
    func testURLHubPopoverHostingRootPreservesProductionWindowRegistryAcrossLayoutAndUpdate() throws {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        let registry = try XCTUnwrap(harness.browserManager.windowRegistry)
        let context = harness.browserManager.urlBarBundle.contextOwner.urlBarHubContext
        let controller = NSHostingController(
            rootView: makeURLHubRoot(
                context: context,
                windowState: harness.windowState,
                windowRegistry: registry,
                profileId: harness.primarySpace.profileId
            )
        )
        let controllerIdentity = ObjectIdentifier(controller)

        let initialSize = controller.view.fittingSize

        XCTAssertGreaterThan(initialSize.width, 1)
        XCTAssertGreaterThan(initialSize.height, 1)
        XCTAssertIdentical(controller.rootView.windowRegistry, registry)
        XCTAssertIdentical(controller.rootView.windowRegistry.activeWindow, harness.windowState)

        let replacementWindow = BrowserWindowState()
        registry.register(replacementWindow)
        registry.setActive(replacementWindow)
        let replacementProfileID = UUID()
        controller.rootView = makeURLHubRoot(
            context: context,
            windowState: replacementWindow,
            windowRegistry: registry,
            profileId: replacementProfileID
        )

        let updatedSize = controller.view.fittingSize

        XCTAssertEqual(ObjectIdentifier(controller), controllerIdentity)
        XCTAssertGreaterThan(updatedSize.width, 1)
        XCTAssertGreaterThan(updatedSize.height, 1)
        XCTAssertIdentical(controller.rootView.windowRegistry, registry)
        XCTAssertIdentical(controller.rootView.windowRegistry.activeWindow, replacementWindow)
        XCTAssertEqual(controller.rootView.profileId, replacementProfileID)
    }

    func testNavigationHistorySelectedURLUsesWindowSpaceAndSelectsOpenedTab() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        let source = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example",
            in: harness.primarySpace,
            activate: false
        )
        harness.windowState.currentTabId = source.id
        let targetURL = URL(string: "https://selected.example/page")!

        harness.browserManager.urlBarBundle.contextOwner
            .navigationHistoryContext(for: harness.windowState)
            .openURLInNewTab(targetURL, true, source)

        let opened = harness.browserManager.regularTabCollectionOwner.tabs(in: harness.primarySpace)
            .first { $0.url == targetURL }
        guard let opened else {
            XCTFail("Expected navigation history context to open selected URL")
            return
        }
        XCTAssertEqual(opened.spaceId, harness.primarySpace.id)
        XCTAssertEqual(harness.windowState.currentTabId, opened.id)
        XCTAssertEqual(harness.windowState.currentSpaceId, harness.primarySpace.id)
    }

    func testNavigationHistoryBackgroundURLInsertsAfterSourceWithoutChangingSelection() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        let source = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example",
            in: harness.primarySpace,
            activate: false
        )
        let trailing = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://trailing.example",
            in: harness.primarySpace,
            activate: false
        )
        harness.windowState.currentTabId = source.id
        let targetURL = URL(string: "https://background.example/page")!

        harness.browserManager.urlBarBundle.contextOwner
            .navigationHistoryContext(for: harness.windowState)
            .openURLInNewTab(targetURL, false, source)

        let tabs = harness.browserManager.regularTabCollectionOwner.tabs(in: harness.primarySpace)
        let opened = tabs.first { $0.url == targetURL }
        guard let opened else {
            XCTFail("Expected navigation history context to open background URL")
            return
        }
        XCTAssertEqual(harness.windowState.currentTabId, source.id)
        XCTAssertEqual(tabs.map(\.id), [source.id, opened.id, trailing.id])
    }

    func testNavigationHistoryCurrentURLLoadsCurrentTabInBoundWindow() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        let source = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example",
            in: harness.primarySpace,
            activate: false
        )
        harness.windowState.currentTabId = source.id
        let targetURL = URL(string: "https://current.example/page")!

        harness.browserManager.urlBarBundle.contextOwner
            .navigationHistoryContext(for: harness.windowState)
            .openURLInCurrentTab(targetURL, source)

        XCTAssertEqual(source.url, targetURL)
        XCTAssertEqual(harness.windowState.currentTabId, source.id)
        XCTAssertEqual(harness.windowState.currentSpaceId, harness.primarySpace.id)
    }

    func testURLBarContextReflectsFreshSnapshotState() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        let request = SumiBookmarkEditorPresentationRequest(
            windowID: harness.windowState.id,
            tabID: UUID()
        )

        for _ in 0..<41 {
            harness.browserManager.zoomRevisionState.publishChange()
        }
        harness.browserManager.bookmarkEditorPresentationState.present(request)

        var context = harness.browserManager.urlBarBundle.contextOwner.urlBarContext
        XCTAssertEqual(context.zoom.stateRevision, 41)
        XCTAssertEqual(context.bookmarkEditorPresentationRequest, request)

        harness.browserManager.zoomRevisionState.publishChange()
        harness.browserManager.bookmarkEditorPresentationState.clear(request)

        context = harness.browserManager.urlBarBundle.contextOwner.urlBarContext
        XCTAssertEqual(context.zoom.stateRevision, 42)
        XCTAssertNil(context.bookmarkEditorPresentationRequest)
    }

    func testNavigationToolbarReloadUsesWindowScopedRefreshPath() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        let tab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://reload.example",
            in: harness.primarySpace,
            activate: false
        )
        harness.windowState.currentTabId = tab.id
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        _ = tab.installNavigationDelegate(on: webView)
        let admission = harness.browserManager.testWebViewRuntime()
            .trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
                webView,
                for: tab,
                in: harness.windowState.id
            )
        XCTAssertTrue(admission.isAccepted)
        let previousRevision = tab.mainFrameLoads.currentIntent.revision

        harness.browserManager.urlBarBundle.contextOwner
            .navigationToolbarContext(for: harness.windowState)
            .reload(tab)

        XCTAssertGreaterThan(
            tab.mainFrameLoads.currentIntent.revision,
            previousRevision
        )
        XCTAssertEqual(tab.mainFrameLoads.currentIntent.targetURL, tab.url)
        webView.stopLoading()
    }

    func testURLBarReloadPageUsesWindowScopedRefreshPath() throws {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        let tab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://urlbar-reload.example",
            in: harness.primarySpace,
            activate: false
        )
        harness.windowState.currentTabId = tab.id
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        _ = tab.installNavigationDelegate(on: webView)
        let admission = harness.browserManager.testWebViewRuntime()
            .trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
                webView,
                for: tab,
                in: harness.windowState.id
            )
        XCTAssertTrue(admission.isAccepted)
        let previousRevision = tab.mainFrameLoads.currentIntent.revision

        let context = harness.browserManager.urlBarBundle.contextOwner.urlBarContext
        let page = try XCTUnwrap(context.activePage(harness.windowState))
        XCTAssertTrue(context.reloadPage(
            page,
            "BrowserURLBarContextOwnerTests.reload"
        ))

        XCTAssertGreaterThan(
            tab.mainFrameLoads.currentIntent.revision,
            previousRevision
        )
        XCTAssertEqual(tab.mainFrameLoads.currentIntent.targetURL, tab.url)
        webView.stopLoading()
    }

    private func makeHarness() -> Harness {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        let profile = Profile(name: "Primary")
        let primarySpace = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([primarySpace])
        browserManager.spaceStateOwner.replaceCurrentSpace(primarySpace)

        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = primarySpace.id
        windowState.currentProfileId = profile.id

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return Harness(
            browserManager: browserManager,
            windowState: windowState,
            primarySpace: primarySpace
        )
    }

    private func makeURLHubRoot(
        context: URLBarHubBrowserContext,
        windowState: BrowserWindowState,
        windowRegistry: WindowRegistry,
        profileId: UUID?
    ) -> URLBarHubPopoverRootView {
        URLBarHubPopoverRootView(
            browserContext: context,
            windowState: windowState,
            windowRegistry: windowRegistry,
            settings: SumiSettingsService(),
            themeContext: .default,
            colorScheme: .light,
            currentTab: nil,
            profile: nil,
            profileId: profileId,
            onClose: {},
            onContentSizeChange: { _ in }
        )
    }

    private func removePersistedWindowSession() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
    }
}

@MainActor
private struct Harness {
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let primarySpace: Space
}
