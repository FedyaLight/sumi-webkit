import Foundation
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class WindowSplitSessionCodingTests: XCTestCase {
    func testCurrentSnapshotRoundTripPersistsOnlyTypedWindowSelection() throws {
        let groupID = UUID()
        let memberID = SplitMemberID.shortcutPin(UUID())
        let snapshot = makeSnapshot(
            splitSelection: WindowSplitSelection(
                groupID: groupID,
                activeMemberID: memberID
            )
        )

        let data = try JSONEncoder().encode(snapshot)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let decoded = try JSONDecoder().decode(
            WindowSessionSnapshot.self,
            from: data
        )

        XCTAssertNotNil(object["splitSelection"])
        XCTAssertEqual(decoded.splitSelection, snapshot.splitSelection)
    }

    func testSnapshotApplierStagesExactStableMemberWithoutActivatingGroup() {
        let selection = WindowSplitSelection(
            groupID: UUID(),
            activeMemberID: .regularTab(UUID())
        )
        let windowState = BrowserWindowState()
        windowState.splitSelection = WindowSplitSelection(
            groupID: UUID(),
            activeMemberID: .regularTab(UUID())
        )

        WindowSessionSnapshotApplier(glanceManager: GlanceManager()).apply(
            makeSnapshot(splitSelection: selection),
            to: windowState
        )

        XCTAssertNil(windowState.splitSelection)
        XCTAssertEqual(
            windowState.restorationState.pendingSplitSelection,
            PendingWindowSplitSelection(
                groupID: selection.groupID,
                preferredMemberID: selection.activeMemberID
            )
        )
    }

    func testSnapshotFactoryReadsWindowLocalSelectionWithoutSplitManager() {
        let selection = WindowSplitSelection(
            groupID: UUID(),
            activeMemberID: .shortcutPin(UUID())
        )
        let windowState = BrowserWindowState()
        windowState.splitSelection = selection

        let snapshot = WindowSessionSnapshotFactory(
            glanceManager: GlanceManager()
        ).make(for: windowState)

        XCTAssertEqual(snapshot.splitSelection, selection)
    }

    func testWindowGeometryRoundTripAndRestoreStaging() throws {
        let geometry = BrowserWindowGeometrySnapshot(
            frame: BrowserWindowFrameSnapshot(
                CGRect(x: 80, y: 120, width: 900, height: 640)
            ),
            displayMode: .zoomed
        )
        let snapshot = makeSnapshot(windowGeometry: geometry)

        let decoded = try JSONDecoder().decode(
            WindowSessionSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        let windowState = BrowserWindowState()
        WindowSessionSnapshotApplier(glanceManager: GlanceManager()).apply(
            decoded,
            to: windowState
        )

        XCTAssertEqual(decoded.windowGeometry, geometry)
        XCTAssertEqual(
            windowState.restorationState.pendingWindowGeometry,
            geometry
        )
    }

    func testSnapshotFactoryUsesInjectedNativeWindowGeometryProjection() {
        let geometry = BrowserWindowGeometrySnapshot(
            frame: BrowserWindowFrameSnapshot(
                CGRect(x: 20, y: 40, width: 700, height: 500)
            ),
            displayMode: .normal
        )
        let windowState = BrowserWindowState()
        let snapshot = WindowSessionSnapshotFactory(
            glanceManager: GlanceManager(),
            windowGeometry: { state in
                XCTAssertIdentical(state, windowState)
                return geometry
            }
        ).make(for: windowState)

        XCTAssertEqual(snapshot.windowGeometry, geometry)
    }

    private func makeSnapshot(
        splitSelection: WindowSplitSelection? = nil,
        windowGeometry: BrowserWindowGeometrySnapshot? = nil
    ) -> WindowSessionSnapshot {
        WindowSessionSnapshot(
            currentTabId: nil,
            currentSpaceId: nil,
            currentProfileId: nil,
            activeShortcutPinId: nil,
            activeShortcutPinRole: nil,
            isShowingEmptyState: false,
            commandPaletteReason: nil,
            activeTabsBySpace: [],
            activeShortcutsBySpace: [],
            sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            savedSidebarWidth: Double(
                BrowserWindowState.sidebarDefaultWidth
            ),
            sidebarContentWidth: Double(
                BrowserWindowState.sidebarContentWidth(
                    for: BrowserWindowState.sidebarDefaultWidth
                )
            ),
            isSidebarVisible: true,
            commandPaletteDraft: CommandPaletteDraftState(
                text: "",
                navigateCurrentTab: false
            ),
            splitSelection: splitSelection,
            windowGeometry: windowGeometry
        )
    }
}
