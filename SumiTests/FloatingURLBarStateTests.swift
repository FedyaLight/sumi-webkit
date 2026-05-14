import XCTest

@testable import Sumi

@MainActor
final class FloatingURLBarStateTests: XCTestCase {
    func testFocusUpdateNewTabAndDismissUseWindowStateAsSingleOwner() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        }

        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()

        browserManager.focusFloatingURLBar(
            in: windowState,
            prefill: "https://example.com",
            navigateCurrentTab: true
        )

        XCTAssertTrue(windowState.isCommandPaletteVisible)
        XCTAssertEqual(windowState.commandPalettePresentationReason, .keyboard)
        XCTAssertEqual(windowState.commandPaletteDraftText, "https://example.com")
        XCTAssertTrue(windowState.commandPaletteDraftNavigatesCurrentTab)

        browserManager.updateFloatingURLBarDraft(in: windowState, text: "swift")
        XCTAssertEqual(windowState.commandPaletteDraftText, "swift")
        XCTAssertTrue(windowState.commandPaletteDraftNavigatesCurrentTab)

        browserManager.showNewTabPalette(in: windowState)
        XCTAssertTrue(windowState.isCommandPaletteVisible)
        XCTAssertEqual(windowState.commandPalettePresentationReason, .emptySpace)
        XCTAssertEqual(windowState.commandPaletteDraftText, "")
        XCTAssertFalse(windowState.commandPaletteDraftNavigatesCurrentTab)

        browserManager.dismissFloatingURLBar(in: windowState, preserveDraft: false)
        XCTAssertFalse(windowState.isCommandPaletteVisible)
        XCTAssertEqual(windowState.commandPalettePresentationReason, .none)
        XCTAssertEqual(windowState.commandPaletteDraftText, "")
        XCTAssertFalse(windowState.commandPaletteDraftNavigatesCurrentTab)
    }
}
