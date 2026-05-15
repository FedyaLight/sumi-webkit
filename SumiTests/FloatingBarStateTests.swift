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

        browserManager.focusFloatingBar(
            in: windowState,
            prefill: "https://example.com",
            navigateCurrentTab: true
        )

        XCTAssertTrue(windowState.isFloatingBarVisible)
        XCTAssertEqual(windowState.floatingBarPresentationReason, .keyboard)
        XCTAssertEqual(windowState.floatingBarDraftText, "https://example.com")
        XCTAssertTrue(windowState.floatingBarDraftNavigatesCurrentTab)

        browserManager.updateFloatingBarDraft(in: windowState, text: "swift")
        XCTAssertEqual(windowState.floatingBarDraftText, "swift")
        XCTAssertTrue(windowState.floatingBarDraftNavigatesCurrentTab)

        browserManager.showNewTabFloatingBar(in: windowState)
        XCTAssertTrue(windowState.isFloatingBarVisible)
        XCTAssertEqual(windowState.floatingBarPresentationReason, .emptySpace)
        XCTAssertEqual(windowState.floatingBarDraftText, "")
        XCTAssertFalse(windowState.floatingBarDraftNavigatesCurrentTab)

        browserManager.dismissFloatingBar(in: windowState, preserveDraft: false)
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

        let (browserManager, windowState, space) = makeHarness()
        let currentTab = browserManager.openNewTab(
            url: "https://example.com/start",
            context: .foreground(windowState: windowState)
        )

        browserManager.focusFloatingBar(
            in: windowState,
            prefill: currentTab.url.absoluteString,
            navigateCurrentTab: true
        )

        let navigatesCurrentTab = windowState.floatingBarDraftNavigatesCurrentTab
            && browserManager.currentTab(for: windowState) != nil
        browserManager.dismissFloatingBar(in: windowState, preserveDraft: false)

        XCTAssertFalse(windowState.floatingBarDraftNavigatesCurrentTab)

        browserManager.openFloatingBarSuggestion(
            SearchManager.SearchSuggestion(text: "https://example.com/replaced", type: .url),
            in: windowState,
            navigatesCurrentTab: navigatesCurrentTab
        )

        XCTAssertEqual(browserManager.tabManager.tabs(in: space).count, 1)
        XCTAssertEqual(browserManager.currentTab(for: windowState)?.id, currentTab.id)
        XCTAssertEqual(currentTab.url.absoluteString, "https://example.com/replaced")
    }

    func testNewTabFloatingBarStillCreatesNewTab() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        }

        let (browserManager, windowState, space) = makeHarness()
        let currentTab = browserManager.openNewTab(
            url: "https://example.com/start",
            context: .foreground(windowState: windowState)
        )

        browserManager.showNewTabFloatingBar(in: windowState)
        let navigatesCurrentTab = windowState.floatingBarDraftNavigatesCurrentTab
            && browserManager.currentTab(for: windowState) != nil
        browserManager.dismissFloatingBar(in: windowState, preserveDraft: false)

        browserManager.openFloatingBarSuggestion(
            SearchManager.SearchSuggestion(text: "https://example.com/new", type: .url),
            in: windowState,
            navigatesCurrentTab: navigatesCurrentTab
        )

        XCTAssertEqual(browserManager.tabManager.tabs(in: space).count, 2)
        XCTAssertEqual(browserManager.currentTab(for: windowState)?.id, currentTab.id)
    }

    private func makeHarness() -> (BrowserManager, BrowserWindowState, Space) {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return (browserManager, windowState, space)
    }
}
