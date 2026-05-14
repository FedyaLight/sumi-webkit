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
}
