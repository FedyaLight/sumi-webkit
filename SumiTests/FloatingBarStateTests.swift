import XCTest

@testable import Sumi

@MainActor
final class FloatingBarStateTests: XCTestCase {
    func testFocusUpdateNewTabAndDismissUseWindowStateAsSingleOwner() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        }

        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()

        browserManager.urlBarBundle.floatingBarRoutingOwner.focusFloatingBar(
            in: windowState,
            prefill: "https://example.com",
            navigateCurrentTab: true,
            presentationReason: .keyboard
        )

        XCTAssertTrue(windowState.isFloatingBarVisible)
        XCTAssertEqual(windowState.floatingBarPresentationReason, .keyboard)
        XCTAssertEqual(windowState.floatingBarDraftText, "https://example.com")
        XCTAssertTrue(windowState.floatingBarDraftNavigatesCurrentTab)

        browserManager.urlBarBundle.floatingBarRoutingOwner.updateFloatingBarDraft(in: windowState, text: "swift")
        XCTAssertEqual(windowState.floatingBarDraftText, "swift")
        XCTAssertTrue(windowState.floatingBarDraftNavigatesCurrentTab)

        browserManager.urlBarBundle.floatingBarRoutingOwner.showNewTabFloatingBar(in: windowState)
        XCTAssertTrue(windowState.isFloatingBarVisible)
        XCTAssertEqual(windowState.floatingBarPresentationReason, .emptySpace)
        XCTAssertEqual(windowState.floatingBarDraftText, "")
        XCTAssertFalse(windowState.floatingBarDraftNavigatesCurrentTab)

        browserManager.urlBarBundle.floatingBarRoutingOwner.dismissFloatingBar(
            in: windowState,
            preserveDraft: false,
            cancelEmptySplitPlaceholder: true
        )
        XCTAssertFalse(windowState.isFloatingBarVisible)
        XCTAssertEqual(windowState.floatingBarPresentationReason, .none)
        XCTAssertEqual(windowState.floatingBarDraftText, "")
        XCTAssertFalse(windowState.floatingBarDraftNavigatesCurrentTab)
    }

    func testCapturedCurrentTabNavigationSurvivesDismissReset() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        }

        let (browserManager, _, windowState, space) = makeHarness()
        let currentTab = browserManager.tabLifecycleService.opening.openNewTab(
            url: "https://example.com/start",
            context: .foreground(windowState: windowState)
        )

        browserManager.urlBarBundle.floatingBarRoutingOwner.focusFloatingBar(
            in: windowState,
            prefill: currentTab.url.absoluteString,
            navigateCurrentTab: true,
            presentationReason: .keyboard
        )

        browserManager.urlBarBundle.floatingBarRoutingOwner.commitFloatingBarSuggestion(
            SearchManager.SearchSuggestion(text: "https://example.com/replaced", type: .url),
            in: windowState
        )

        XCTAssertFalse(windowState.floatingBarDraftNavigatesCurrentTab)
        XCTAssertEqual(browserManager.tabManager.regularTabCollectionOwner.tabs(in: space).count, 1)
        XCTAssertEqual(browserManager.windowSessionBundle.tabContextOwner.currentTab(for: windowState)?.id, currentTab.id)
        XCTAssertEqual(currentTab.url.absoluteString, "https://example.com/replaced")
    }

    func testNewTabFloatingBarStillCreatesNewTab() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        }

        let (browserManager, _, windowState, space) = makeHarness()
        let currentTab = browserManager.tabLifecycleService.opening.openNewTab(
            url: "https://example.com/start",
            context: .foreground(windowState: windowState)
        )

        browserManager.urlBarBundle.floatingBarRoutingOwner.showNewTabFloatingBar(in: windowState)
        browserManager.urlBarBundle.floatingBarRoutingOwner.commitFloatingBarSuggestion(
            SearchManager.SearchSuggestion(text: "https://example.com/new", type: .url),
            in: windowState
        )

        XCTAssertEqual(browserManager.tabManager.regularTabCollectionOwner.tabs(in: space).count, 2)
        XCTAssertEqual(browserManager.windowSessionBundle.tabContextOwner.currentTab(for: windowState)?.id, currentTab.id)
    }

    func testDismissFloatingBarForActiveWindowPreservesDraftWhenRequested() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        }

        let (browserManager, windowRegistry, windowState, _) = makeHarness()
        browserManager.urlBarBundle.floatingBarRoutingOwner.focusFloatingBar(
            in: windowState,
            prefill: "https://example.com",
            navigateCurrentTab: true,
            presentationReason: .keyboard
        )

        withExtendedLifetime(windowRegistry) {
            browserManager.urlBarBundle.floatingBarRoutingOwner.dismissFloatingBarForActiveWindow(preserveDraft: true)
        }

        XCTAssertFalse(windowState.isFloatingBarVisible)
        XCTAssertEqual(windowState.floatingBarDraftText, "https://example.com")
        XCTAssertTrue(windowState.floatingBarDraftNavigatesCurrentTab)
    }

    private func makeHarness() -> (BrowserManager, WindowRegistry, BrowserWindowState, Space) {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.bindTestWebViewCoordinator()
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaceStateOwner.replaceSpaces([space])
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(space)

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return (browserManager, windowRegistry, windowState, space)
    }
}
