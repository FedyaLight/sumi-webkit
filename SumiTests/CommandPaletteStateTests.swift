import XCTest

@testable import Sumi

@MainActor
final class CommandPaletteStateTests: XCTestCase {
    func testFocusUpdateNewTabAndDismissUseWindowStateAsSingleOwner() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        }

        let browserManager = BrowserManager(windowRegistry: WindowRegistry())
        let windowState = BrowserWindowState()

        browserManager.urlBarBundle.commandPalettePresentation.focus(
            in: windowState,
            prefill: "https://example.com",
            navigateCurrentTab: true,
            reason: .keyboard
        )

        XCTAssertTrue(windowState.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(windowState.commandPalettePresentationReason, .keyboard)
        XCTAssertEqual(windowState.commandPaletteDraftText, "https://example.com")
        XCTAssertTrue(windowState.commandPaletteDraftNavigatesCurrentTab)

        browserManager.urlBarBundle.commandPalettePresentation
            .updateDraft(in: windowState, text: "swift")
        XCTAssertEqual(windowState.commandPaletteDraftText, "swift")
        XCTAssertTrue(windowState.commandPaletteDraftNavigatesCurrentTab)

        browserManager.urlBarBundle.commandPalettePresentation.showNewTab(in: windowState)
        XCTAssertTrue(windowState.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(windowState.commandPalettePresentationReason, .emptySpace)
        XCTAssertEqual(windowState.commandPaletteDraftText, "")
        XCTAssertFalse(windowState.commandPaletteDraftNavigatesCurrentTab)

        browserManager.urlBarBundle.commandPalettePresentation.dismiss(
            in: windowState,
            preserveDraft: false,
            cancelEmptySplitPlaceholder: true
        )
        XCTAssertFalse(windowState.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(windowState.commandPalettePresentationReason, .none)
        XCTAssertEqual(windowState.commandPaletteDraftText, "")
        XCTAssertFalse(windowState.commandPaletteDraftNavigatesCurrentTab)
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

        browserManager.urlBarBundle.commandPalettePresentation.focus(
            in: windowState,
            prefill: currentTab.url.absoluteString,
            navigateCurrentTab: true,
            reason: .keyboard
        )

        browserManager.urlBarBundle.commandPaletteCommit.commitActivation(
            .input("https://example.com/replaced"),
            in: windowState
        )

        XCTAssertFalse(windowState.commandPaletteDraftNavigatesCurrentTab)
        XCTAssertEqual(browserManager.regularTabCollectionOwner.tabs(in: space).count, 1)
        XCTAssertEqual(browserManager.shellRuntime.windowTabs.currentTab(for: windowState)?.id, currentTab.id)
        XCTAssertEqual(
            currentTab.mainFrameLoads.currentIntent.targetURL.absoluteString,
            "https://example.com/replaced"
        )
        XCTAssertEqual(currentTab.url.absoluteString, "https://example.com/start")
    }

    func testNewTabCommandPaletteStillCreatesNewTab() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        }

        let (browserManager, _, windowState, space) = makeHarness()
        let currentTab = browserManager.tabOpening.openNewTab(
            url: "https://example.com/start",
            context: .foreground(windowState: windowState)
        )

        browserManager.urlBarBundle.commandPalettePresentation.showNewTab(in: windowState)
        browserManager.urlBarBundle.commandPaletteCommit.commitActivation(
            .input("https://example.com/new"),
            in: windowState
        )

        XCTAssertEqual(browserManager.regularTabCollectionOwner.tabs(in: space).count, 2)
        XCTAssertEqual(browserManager.shellRuntime.windowTabs.currentTab(for: windowState)?.id, currentTab.id)
    }

    func testDismissCommandPaletteForActiveWindowPreservesDraftWhenRequested() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        }

        let (browserManager, windowRegistry, windowState, _) = makeHarness()
        browserManager.urlBarBundle.commandPalettePresentation.focus(
            in: windowState,
            prefill: "https://example.com",
            navigateCurrentTab: true,
            reason: .keyboard
        )

        withExtendedLifetime(windowRegistry) {
            browserManager.urlBarBundle.commandPalettePresentation
                .dismissActiveWindow(preserveDraft: true)
        }

        XCTAssertFalse(windowState.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(windowState.commandPaletteDraftText, "https://example.com")
        XCTAssertTrue(windowState.commandPaletteDraftNavigatesCurrentTab)
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
