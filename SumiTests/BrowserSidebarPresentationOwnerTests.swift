import XCTest

@testable import Sumi

@MainActor
final class BrowserSidebarPresentationOwnerTests: XCTestCase {
    func testUpdateSidebarWidthPersistsWithDefaultDelay() {
        let harness = BrowserSidebarPresentationOwnerHarness()
        let windowState = BrowserWindowState()
        let owner = harness.makeOwner()

        owner.updateSidebarWidth(10, for: windowState)

        XCTAssertEqual(windowState.sidebarWidth, BrowserWindowState.sidebarMinimumWidth)
        XCTAssertEqual(
            harness.persistedSessions,
            [.init(windowId: windowState.id, delayNanoseconds: 450_000_000)]
        )
    }

    func testUpdateSidebarWidthCanSkipPersistence() {
        let harness = BrowserSidebarPresentationOwnerHarness()
        let windowState = BrowserWindowState()
        let owner = harness.makeOwner()

        owner.updateSidebarWidth(320, for: windowState, persist: false)

        XCTAssertTrue(harness.persistedSessions.isEmpty)
    }

    func testGlobalToggleUsesActiveWindowWithoutChangingRegistryActiveWindow() {
        let activeWindow = BrowserWindowState()
        let harness = BrowserSidebarPresentationOwnerHarness(
            activeWindow: activeWindow,
            allWindows: [activeWindow]
        )
        let owner = harness.makeOwner()

        owner.toggleSidebar()

        XCTAssertFalse(activeWindow.isSidebarVisible)
        XCTAssertTrue(harness.activatedWindows.isEmpty)
        XCTAssertEqual(
            harness.persistedSessions,
            [.init(windowId: activeWindow.id, delayNanoseconds: 150_000_000)]
        )
    }

    func testGlobalToggleActivatesKeyWindowWhenNoActiveWindowExists() {
        let keyWindow = BrowserWindowState()
        let otherWindow = BrowserWindowState()
        let harness = BrowserSidebarPresentationOwnerHarness(
            activeWindow: nil,
            allWindows: [otherWindow, keyWindow],
            keyWindowState: keyWindow
        )
        let owner = harness.makeOwner()

        owner.toggleSidebar()

        XCTAssertFalse(keyWindow.isSidebarVisible)
        XCTAssertTrue(otherWindow.isSidebarVisible)
        XCTAssertEqual(harness.activatedWindows, [keyWindow.id])
    }

    func testGlobalToggleActivatesOnlyRegisteredWindowWhenNoActiveOrKeyWindowExists() {
        let onlyWindow = BrowserWindowState()
        let harness = BrowserSidebarPresentationOwnerHarness(
            activeWindow: nil,
            allWindows: [onlyWindow]
        )
        let owner = harness.makeOwner()

        owner.toggleSidebar()

        XCTAssertFalse(onlyWindow.isSidebarVisible)
        XCTAssertEqual(harness.activatedWindows, [onlyWindow.id])
    }

    func testGlobalToggleFallsBackToSavedVisibilityWhenNoWindowTargetExists() {
        let harness = BrowserSidebarPresentationOwnerHarness()
        let owner = harness.makeOwner()

        owner.toggleSidebar()

        XCTAssertTrue(harness.activatedWindows.isEmpty)
        XCTAssertTrue(harness.persistedSessions.isEmpty)
    }
}

@MainActor
private final class BrowserSidebarPresentationOwnerHarness {
    struct PersistedSession: Equatable {
        let windowId: UUID
        let delayNanoseconds: UInt64
    }

    var activeWindow: BrowserWindowState?
    var allWindows: [BrowserWindowState]
    var keyWindowState: BrowserWindowState?
    var activatedWindows: [UUID] = []
    var persistedSessions: [PersistedSession] = []

    init(
        activeWindow: BrowserWindowState? = nil,
        allWindows: [BrowserWindowState] = [],
        keyWindowState: BrowserWindowState? = nil
    ) {
        self.activeWindow = activeWindow
        self.allWindows = allWindows
        self.keyWindowState = keyWindowState
    }

    func makeOwner() -> BrowserSidebarPresentationOwner {
        BrowserSidebarPresentationOwner(
            dependencies: BrowserSidebarPresentationOwner.Dependencies(
                activeWindow: { [weak self] in self?.activeWindow },
                allWindows: { [weak self] in self?.allWindows ?? [] },
                setActiveWindow: { [weak self] windowState in
                    self?.activeWindow = windowState
                    self?.activatedWindows.append(windowState.id)
                },
                keyWindowState: { [weak self] in self?.keyWindowState },
                schedulePersistWindowSession: { [weak self] windowState, delayNanoseconds in
                    self?.persistedSessions.append(
                        PersistedSession(
                            windowId: windowState.id,
                            delayNanoseconds: delayNanoseconds
                        )
                    )
                }
            )
        )
    }
}
