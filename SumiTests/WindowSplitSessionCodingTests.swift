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
        XCTAssertNil(object["activeSplitGroupId"])
        XCTAssertEqual(decoded.splitSelection, snapshot.splitSelection)
        XCTAssertNil(decoded.legacyActiveSplitGroupID)
    }

    func testLegacyGroupIDRemainsDecodeOnlyMigrationInput() throws {
        let legacyGroupID = UUID()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(makeSnapshot())
            ) as? [String: Any]
        )
        object["activeSplitGroupId"] = legacyGroupID.uuidString
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            WindowSessionSnapshot.self,
            from: legacyData
        )
        let reencodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(decoded)
            ) as? [String: Any]
        )

        XCTAssertNil(decoded.splitSelection)
        XCTAssertEqual(decoded.legacyActiveSplitGroupID, legacyGroupID)
        XCTAssertNil(reencodedObject["activeSplitGroupId"])
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
        XCTAssertNil(windowState.restorationState.pendingLegacySplitGroup)
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

    private func makeSnapshot(
        splitSelection: WindowSplitSelection? = nil
    ) -> WindowSessionSnapshot {
        WindowSessionSnapshot(
            currentTabId: nil,
            currentSpaceId: nil,
            currentProfileId: nil,
            activeShortcutPinId: nil,
            activeShortcutPinRole: nil,
            isShowingEmptyState: false,
            floatingBarReason: nil,
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
            floatingBarDraft: FloatingBarDraftState(
                text: "",
                navigateCurrentTab: false
            ),
            splitSelection: splitSelection
        )
    }
}
