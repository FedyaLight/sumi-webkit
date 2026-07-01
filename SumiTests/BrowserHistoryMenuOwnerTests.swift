import XCTest

@testable import Sumi

@MainActor
final class BrowserHistoryMenuOwnerTests: XCTestCase {
    func testClearAllHistoryDismissesCollapsedSidebarBeforeConfirmationAndClearsWhenConfirmed() async {
        var events: [String] = []
        let owner = BrowserHistoryMenuOwner(
            dependencies: BrowserHistoryMenuOwner.Dependencies(
                requestCollapsedSidebarOverlayDismissal: {
                    events.append("dismiss")
                },
                confirmClearAllHistory: {
                    events.append("confirm")
                    return true
                },
                clearAllHistory: {
                    events.append("clear")
                },
                existingWindowIds: { [] },
                createNewWindow: { /* No-op. */ },
                awaitNextRegisteredWindow: { _ in nil },
                applyWindowSessionSnapshot: { _, _ in /* No-op. */ },
                bringWindowToFront: { _ in /* No-op. */ },
                activateApplication: { /* No-op. */ }
            )
        )

        owner.clearAllHistoryFromMenu()
        await Task.yield()

        XCTAssertEqual(events, ["dismiss", "confirm", "clear"])
    }

    func testClearAllHistoryDoesNotClearWhenUserCancels() async {
        var events: [String] = []
        let owner = BrowserHistoryMenuOwner(
            dependencies: BrowserHistoryMenuOwner.Dependencies(
                requestCollapsedSidebarOverlayDismissal: {
                    events.append("dismiss")
                },
                confirmClearAllHistory: {
                    events.append("confirm")
                    return false
                },
                clearAllHistory: {
                    events.append("clear")
                },
                existingWindowIds: { [] },
                createNewWindow: { /* No-op. */ },
                awaitNextRegisteredWindow: { _ in nil },
                applyWindowSessionSnapshot: { _, _ in /* No-op. */ },
                bringWindowToFront: { _ in /* No-op. */ },
                activateApplication: { /* No-op. */ }
            )
        )

        owner.clearAllHistoryFromMenu()
        await Task.yield()

        XCTAssertEqual(events, ["dismiss", "confirm"])
    }

    func testReopenWindowCapturesExistingWindowsBeforeCreatingNewWindowThenAppliesSnapshot() async {
        let existingWindowId = UUID()
        let targetWindow = BrowserWindowState()
        let snapshot = makeWindowSessionSnapshot()
        var events: [String] = []
        var awaitedExistingWindowIds = Set<UUID>()
        var appliedSnapshot: WindowSessionSnapshot?
        var appliedWindow: BrowserWindowState?
        let owner = BrowserHistoryMenuOwner(
            dependencies: BrowserHistoryMenuOwner.Dependencies(
                requestCollapsedSidebarOverlayDismissal: { /* No-op. */ },
                confirmClearAllHistory: { false },
                clearAllHistory: { /* No-op. */ },
                existingWindowIds: {
                    events.append("existing")
                    return [existingWindowId]
                },
                createNewWindow: {
                    events.append("create")
                },
                awaitNextRegisteredWindow: { existingWindowIds in
                    events.append("await")
                    awaitedExistingWindowIds = existingWindowIds
                    return targetWindow
                },
                applyWindowSessionSnapshot: { restoredSnapshot, windowState in
                    events.append("apply")
                    appliedSnapshot = restoredSnapshot
                    appliedWindow = windowState
                },
                bringWindowToFront: { windowState in
                    events.append("front")
                    XCTAssertIdentical(windowState, targetWindow)
                },
                activateApplication: {
                    events.append("activate")
                }
            )
        )

        await owner.reopenWindow(from: snapshot)

        XCTAssertEqual(events, ["existing", "create", "await", "apply", "front", "activate"])
        XCTAssertEqual(awaitedExistingWindowIds, [existingWindowId])
        XCTAssertEqual(appliedSnapshot, snapshot)
        XCTAssertIdentical(appliedWindow, targetWindow)
    }

    private func makeWindowSessionSnapshot() -> WindowSessionSnapshot {
        WindowSessionSnapshot(
            currentTabId: UUID(),
            currentSpaceId: UUID(),
            currentProfileId: nil,
            activeShortcutPinId: nil,
            activeShortcutPinRole: nil,
            isShowingEmptyState: false,
            floatingBarReason: FloatingBarPresentationReason.none,
            activeTabsBySpace: [],
            activeShortcutsBySpace: [],
            sidebarWidth: 280,
            savedSidebarWidth: 280,
            sidebarContentWidth: 260,
            isSidebarVisible: true,
            floatingBarDraft: FloatingBarDraftState(text: "", navigateCurrentTab: false)
        )
    }
}
