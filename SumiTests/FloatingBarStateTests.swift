import XCTest

@testable import Sumi

@MainActor
final class FloatingBarStateTests: XCTestCase {
    func testFocusUpdateNewTabAndDismissUseWindowStateAsSingleOwner() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        }

        let browserManager = BrowserManager(windowRegistry: WindowRegistry())
        let windowState = BrowserWindowState()

        browserManager.urlBarBundle.floatingBar.presentation.focus(
            in: windowState,
            prefill: "https://example.com",
            navigateCurrentTab: true,
            reason: .keyboard
        )

        XCTAssertTrue(windowState.presentationState.isFloatingBarVisible)
        XCTAssertEqual(windowState.floatingBarPresentationReason, .keyboard)
        XCTAssertEqual(windowState.floatingBarDraftText, "https://example.com")
        XCTAssertTrue(windowState.floatingBarDraftNavigatesCurrentTab)

        browserManager.urlBarBundle.floatingBar.presentation
            .updateDraft(in: windowState, text: "swift")
        XCTAssertEqual(windowState.floatingBarDraftText, "swift")
        XCTAssertTrue(windowState.floatingBarDraftNavigatesCurrentTab)

        browserManager.urlBarBundle.floatingBar.presentation.showNewTab(in: windowState)
        XCTAssertTrue(windowState.presentationState.isFloatingBarVisible)
        XCTAssertEqual(windowState.floatingBarPresentationReason, .emptySpace)
        XCTAssertEqual(windowState.floatingBarDraftText, "")
        XCTAssertFalse(windowState.floatingBarDraftNavigatesCurrentTab)

        browserManager.urlBarBundle.floatingBar.presentation.dismiss(
            in: windowState,
            preserveDraft: false,
            cancelEmptySplitPlaceholder: true
        )
        XCTAssertFalse(windowState.presentationState.isFloatingBarVisible)
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
        let currentTab = browserManager.tabOpening.openNewTab(
            url: "https://example.com/start",
            context: .foreground(windowState: windowState)
        )

        browserManager.urlBarBundle.floatingBar.presentation.focus(
            in: windowState,
            prefill: currentTab.url.absoluteString,
            navigateCurrentTab: true,
            reason: .keyboard
        )

        browserManager.urlBarBundle.floatingBar.commit.commitSuggestion(
            SearchManager.SearchSuggestion(text: "https://example.com/replaced", type: .url),
            in: windowState
        )

        XCTAssertFalse(windowState.floatingBarDraftNavigatesCurrentTab)
        XCTAssertEqual(browserManager.regularTabCollectionOwner.tabs(in: space).count, 1)
        XCTAssertEqual(browserManager.shellRuntime.windowTabs.currentTab(for: windowState)?.id, currentTab.id)
        XCTAssertEqual(currentTab.url.absoluteString, "https://example.com/replaced")
    }

    func testNewTabFloatingBarStillCreatesNewTab() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        }

        let (browserManager, _, windowState, space) = makeHarness()
        let currentTab = browserManager.tabOpening.openNewTab(
            url: "https://example.com/start",
            context: .foreground(windowState: windowState)
        )

        browserManager.urlBarBundle.floatingBar.presentation.showNewTab(in: windowState)
        browserManager.urlBarBundle.floatingBar.commit.commitSuggestion(
            SearchManager.SearchSuggestion(text: "https://example.com/new", type: .url),
            in: windowState
        )

        XCTAssertEqual(browserManager.regularTabCollectionOwner.tabs(in: space).count, 2)
        XCTAssertEqual(browserManager.shellRuntime.windowTabs.currentTab(for: windowState)?.id, currentTab.id)
    }

    func testDismissFloatingBarForActiveWindowPreservesDraftWhenRequested() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        }

        let (browserManager, windowRegistry, windowState, _) = makeHarness()
        browserManager.urlBarBundle.floatingBar.presentation.focus(
            in: windowState,
            prefill: "https://example.com",
            navigateCurrentTab: true,
            reason: .keyboard
        )

        withExtendedLifetime(windowRegistry) {
            browserManager.urlBarBundle.floatingBar.presentation
                .dismissActiveWindow(preserveDraft: true)
        }

        XCTAssertFalse(windowState.presentationState.isFloatingBarVisible)
        XCTAssertEqual(windowState.floatingBarDraftText, "https://example.com")
        XCTAssertTrue(windowState.floatingBarDraftNavigatesCurrentTab)
    }

    private func makeHarness() -> (BrowserManager, WindowRegistry, BrowserWindowState, Space) {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        browserManager.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return (browserManager, windowRegistry, windowState, space)
    }
}
