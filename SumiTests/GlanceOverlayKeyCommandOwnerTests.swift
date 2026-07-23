import XCTest

@testable import Sumi

@MainActor
final class GlanceOverlayKeyCommandOwnerTests: XCTestCase {
    func testEscapePassesThroughWithoutActiveSessionWindow() {
        var didCloseOverlay = false
        let owner = makeOwner(
            activeWindowID: nil,
            closeOverlay: { didCloseOverlay = true }
        )

        XCTAssertFalse(owner.handleEscapeKeyForActiveOverlay())
        XCTAssertFalse(didCloseOverlay)
    }

    func testCommandPaletteDismissalConsumesEscapeBeforeFindBarOrOverlayClose() {
        let windowID = UUID()
        var dismissedWindowIDs: [UUID] = []
        var didHideFindBar = false
        var didCloseOverlay = false
        let owner = makeOwner(
            activeWindowID: windowID,
            dismissCommandPaletteIfVisible: { dismissedWindowIDs.append($0); return true },
            isFindBarVisible: { true },
            hideFindBar: { didHideFindBar = true },
            closeOverlay: { didCloseOverlay = true }
        )

        XCTAssertTrue(owner.handleEscapeKeyForActiveOverlay())
        XCTAssertEqual(dismissedWindowIDs, [windowID])
        XCTAssertFalse(didHideFindBar)
        XCTAssertFalse(didCloseOverlay)
    }

    func testFindBarConsumesEscapeBeforeOverlayClose() {
        var didHideFindBar = false
        var didCloseOverlay = false
        let owner = makeOwner(
            dismissCommandPaletteIfVisible: { _ in false },
            isFindBarVisible: { true },
            hideFindBar: { didHideFindBar = true },
            closeOverlay: { didCloseOverlay = true }
        )

        XCTAssertTrue(owner.handleEscapeKeyForActiveOverlay())
        XCTAssertTrue(didHideFindBar)
        XCTAssertFalse(didCloseOverlay)
    }

    func testEscapeClosesOverlayWhenNoHigherPrioritySurfaceConsumesIt() {
        var didCloseOverlay = false
        let owner = makeOwner(
            dismissCommandPaletteIfVisible: { _ in false },
            isFindBarVisible: { false },
            closeOverlay: { didCloseOverlay = true }
        )

        XCTAssertTrue(owner.handleEscapeKeyForActiveOverlay())
        XCTAssertTrue(didCloseOverlay)
    }

    private func makeOwner(
        activeWindowID: UUID? = UUID(),
        dismissCommandPaletteIfVisible: @escaping (UUID) -> Bool = { _ in false },
        isFindBarVisible: @escaping () -> Bool = { false },
        hideFindBar: @escaping () -> Void = {},
        closeOverlay: @escaping () -> Void = {}
    ) -> GlanceOverlayKeyCommandOwner {
        GlanceOverlayKeyCommandOwner(
            rootWindow: { nil },
            activeWindowID: { activeWindowID },
            dismissCommandPaletteIfVisible: dismissCommandPaletteIfVisible,
            isFindBarVisible: isFindBarVisible,
            hideFindBar: hideFindBar,
            closeOverlay: closeOverlay
        )
    }
}
