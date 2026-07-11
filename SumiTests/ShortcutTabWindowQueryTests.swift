import XCTest

@testable import Sumi

@MainActor
final class ShortcutTabWindowQueryTests: XCTestCase {
    func testSelectedWindowsPreferPrimaryThenPreferredThenUUIDOrder() {
        let tabId = UUID()
        let firstWindow = makeWindow(
            id: fixedUUID("00000000-0000-0000-0000-000000000001"),
            selectedTabId: tabId
        )
        let preferredWindow = makeWindow(
            id: fixedUUID("00000000-0000-0000-0000-000000000002"),
            selectedTabId: tabId
        )
        let primaryWindow = makeWindow(
            id: fixedUUID("00000000-0000-0000-0000-000000000003"),
            selectedTabId: tabId
        )
        let lastWindow = makeWindow(
            id: fixedUUID("00000000-0000-0000-0000-000000000004"),
            selectedTabId: tabId
        )
        let windows = [lastWindow, preferredWindow, firstWindow, primaryWindow]
        let query = makeQuery(
            windows: windows,
            primaryWindowId: primaryWindow.id
        )

        let selectedWindowIds = query.windowIdsSelecting(
            tabId: tabId,
            preferredWindowId: preferredWindow.id
        )

        XCTAssertEqual(
            selectedWindowIds,
            [
                primaryWindow.id,
                preferredWindow.id,
                firstWindow.id,
                lastWindow.id,
            ]
        )
    }

    func testDisplayedWindowsPreferCallerThenPrimaryAndIncludeSplitOnlyWindows() {
        let tabId = UUID()
        let selectedWindow = makeWindow(
            id: fixedUUID("00000000-0000-0000-0000-000000000001"),
            selectedTabId: tabId
        )
        let splitOnlyWindow = makeWindow(
            id: fixedUUID("00000000-0000-0000-0000-000000000002"),
            selectedTabId: UUID()
        )
        let primaryWindow = makeWindow(
            id: fixedUUID("00000000-0000-0000-0000-000000000003"),
            selectedTabId: tabId
        )
        let preferredWindow = makeWindow(
            id: fixedUUID("00000000-0000-0000-0000-000000000004"),
            selectedTabId: tabId
        )
        let windows = [primaryWindow, splitOnlyWindow, preferredWindow, selectedWindow]
        let query = makeQuery(
            windows: windows,
            primaryWindowId: primaryWindow.id,
            splitWindowId: splitOnlyWindow.id,
            splitTabId: tabId
        )

        let displayedWindowIds = query.windowIdsDisplaying(
            tabId: tabId,
            preferredWindowId: preferredWindow.id
        )

        XCTAssertEqual(
            displayedWindowIds,
            [
                preferredWindow.id,
                primaryWindow.id,
                selectedWindow.id,
                splitOnlyWindow.id,
            ]
        )
        XCTAssertEqual(
            query.windowIdsSelecting(tabId: tabId),
            [primaryWindow.id, selectedWindow.id, preferredWindow.id]
        )
        XCTAssertEqual(
            query.windowIdDisplaying(
                tabId: tabId,
                preferredWindowId: splitOnlyWindow.id
            ),
            splitOnlyWindow.id
        )
    }

    func testWindowStateDisplayingUsesDeterministicPrimaryWindow() {
        let tabId = UUID()
        let firstWindow = makeWindow(
            id: fixedUUID("00000000-0000-0000-0000-000000000001"),
            selectedTabId: tabId
        )
        let primaryWindow = makeWindow(
            id: fixedUUID("00000000-0000-0000-0000-000000000002"),
            selectedTabId: tabId
        )
        let query = makeQuery(
            windows: [firstWindow, primaryWindow],
            primaryWindowId: primaryWindow.id
        )

        XCTAssertIdentical(query.windowStateDisplaying(tabId: tabId), primaryWindow)
    }

    private func makeQuery(
        windows: [BrowserWindowState],
        primaryWindowId: UUID?,
        splitWindowId: UUID? = nil,
        splitTabId: UUID? = nil
    ) -> ShortcutTabWindowQuery {
        let statesById = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        let runtime = TestRuntimePorts.make(
            windowState: { statesById[$0] },
            windows: { windows.map { ($0.id, $0) } },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                primaryTrackedWindowId: { _ in primaryWindowId }
            ),
            visibleSplitTabIds: { windowId in
                guard windowId == splitWindowId, let splitTabId else { return [] }
                return [splitTabId]
            }
        )
        return ShortcutTabWindowQuery(runtimePorts: { runtime })
    }

    private func makeWindow(id: UUID, selectedTabId: UUID) -> BrowserWindowState {
        let window = BrowserWindowState(id: id)
        window.currentTabId = selectedTabId
        return window
    }

    private func fixedUUID(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            XCTFail("Invalid UUID test fixture")
            return UUID()
        }
        return id
    }
}
