import Foundation
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SidebarSpacePinnedCollapseStateTests: XCTestCase {
    func testCollapsedSpacesAreWindowLocalAndCanonicallySorted() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()

        firstWindow.sidebarSpacePinnedCollapse.restoreCollapsedSpaceIDs([
            firstID,
            secondID,
            firstID,
        ])

        XCTAssertEqual(
            firstWindow.sidebarSpacePinnedCollapse.persistedCollapsedSpaceIDs,
            [secondID, firstID]
        )
        XCTAssertFalse(
            secondWindow.sidebarSpacePinnedCollapse.isCollapsed(firstID)
        )
    }

    func testExpandingSpaceClearsItsStickyProjection() {
        let spaceID = UUID()
        let pinID = UUID()
        let state = SidebarSpacePinnedCollapseState()
        state.setCollapsed(true, for: spaceID)
        state.scheduleMutation(for: spaceID) { _ in
            SidebarFolderProjectionState(
                stickyItemIDs: [pinID],
                hasActiveProjection: true
            )
        }

        XCTAssertEqual(
            state.pendingOrCurrentProjection(for: spaceID).stickyItemIDs,
            [pinID]
        )

        state.setCollapsed(false, for: spaceID)

        XCTAssertFalse(state.isCollapsed(spaceID))
        XCTAssertEqual(state.projection(for: spaceID), .empty)
    }

    func testRemovingSpaceClearsCollapsedAndStickyState() {
        let spaceID = UUID()
        let state = SidebarSpacePinnedCollapseState()
        state.setCollapsed(true, for: spaceID)
        state.scheduleMutation(for: spaceID) { _ in
            SidebarFolderProjectionState(
                stickyItemIDs: [UUID()],
                hasActiveProjection: true
            )
        }

        XCTAssertTrue(state.removeSpace(spaceID))
        XCTAssertFalse(state.isCollapsed(spaceID))
        XCTAssertEqual(state.projection(for: spaceID), .empty)
    }
}

final class SpaceTitleLeadingPresentationTests: XCTestCase {
    func testEmptySpaceAlwaysUsesItsIcon() {
        XCTAssertEqual(
            SpaceTitleLeadingPresentation.resolve(
                hasPinnedContent: false,
                isCollapsed: true,
                isHovered: true
            ),
            .icon
        )
    }

    func testExpandedSpaceUsesIconUntilHoveredThenDownChevron() {
        XCTAssertEqual(
            SpaceTitleLeadingPresentation.resolve(
                hasPinnedContent: true,
                isCollapsed: false,
                isHovered: false
            ),
            .icon
        )
        XCTAssertEqual(
            SpaceTitleLeadingPresentation.resolve(
                hasPinnedContent: true,
                isCollapsed: false,
                isHovered: true
            ),
            .chevron(isExpanded: true)
        )
    }

    func testCollapsedSpaceAlwaysUsesRightChevron() {
        for isHovered in [false, true] {
            XCTAssertEqual(
                SpaceTitleLeadingPresentation.resolve(
                    hasPinnedContent: true,
                    isCollapsed: true,
                    isHovered: isHovered
                ),
                .chevron(isExpanded: false)
            )
        }
    }

    func testReduceMotionAndChromeSettingDisableChevronAnimation() {
        XCTAssertNotNil(
            SpaceTitleCollapseMotion.animation(
                reduceMotion: false,
                shouldReduceChromeMotion: false
            )
        )
        XCTAssertNil(
            SpaceTitleCollapseMotion.animation(
                reduceMotion: true,
                shouldReduceChromeMotion: false
            )
        )
        XCTAssertNil(
            SpaceTitleCollapseMotion.animation(
                reduceMotion: false,
                shouldReduceChromeMotion: true
            )
        )
    }
}

@MainActor
final class SidebarSpacePinnedCollapseSessionTests: XCTestCase {
    func testSessionCodingCanonicalizesCollapsedSpaceIDs() throws {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let snapshot = makeSnapshot(
            collapsedPinnedSpaceIDs: [firstID, secondID, firstID]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(
            WindowSessionSnapshot.self,
            from: data
        )

        XCTAssertEqual(decoded.collapsedPinnedSpaceIDs, [secondID, firstID])
    }

    func testLegacySessionWithoutCollapsedSpacesDecodesExpanded() throws {
        let data = try JSONEncoder().encode(makeSnapshot())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "collapsedPinnedSpaceIDs")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(
            WindowSessionSnapshot.self,
            from: legacyData
        )

        XCTAssertTrue(decoded.collapsedPinnedSpaceIDs.isEmpty)
    }

    func testFactoryAndApplierRoundTripWindowLocalCollapsedSpaces() {
        let spaceIDs = [UUID(), UUID()]
        let source = BrowserWindowState()
        source.sidebarSpacePinnedCollapse.restoreCollapsedSpaceIDs(spaceIDs)

        let snapshot = WindowSessionSnapshotFactory(
            glanceManager: GlanceManager()
        ).make(for: source)
        let destination = BrowserWindowState()
        WindowSessionSnapshotApplier(glanceManager: GlanceManager()).apply(
            snapshot,
            to: destination
        )

        XCTAssertEqual(
            Set(snapshot.collapsedPinnedSpaceIDs),
            Set(spaceIDs)
        )
        XCTAssertEqual(
            Set(destination.sidebarSpacePinnedCollapse.collapsedSpaceIDs),
            Set(spaceIDs)
        )
    }

    func testDeletedSpacePrunerClearsCollapseProjection() {
        let spaceID = UUID()
        let windowState = BrowserWindowState()
        windowState.sidebarSpacePinnedCollapse.setCollapsed(true, for: spaceID)
        windowState.sidebarSpacePinnedCollapse.scheduleMutation(
            for: spaceID
        ) { _ in
            SidebarFolderProjectionState(
                stickyItemIDs: [UUID()],
                hasActiveProjection: true
            )
        }

        let changed = DeletedSpaceWindowReferencePruner().removeReferences(
            to: SpaceRemovalFootprint(
                spaceId: spaceID,
                tabIds: [],
                shortcutPinIds: [],
                retiredShortcutPinIDsByWindow: [:],
                splitGroupIds: []
            ),
            from: windowState
        )

        XCTAssertTrue(changed)
        XCTAssertFalse(
            windowState.sidebarSpacePinnedCollapse.isCollapsed(spaceID)
        )
        XCTAssertEqual(
            windowState.sidebarSpacePinnedCollapse.projection(for: spaceID),
            .empty
        )
    }

    private func makeSnapshot(
        collapsedPinnedSpaceIDs: [UUID] = []
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
            collapsedPinnedSpaceIDs: collapsedPinnedSpaceIDs,
            sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            savedSidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            sidebarContentWidth: Double(
                BrowserWindowState.sidebarContentWidth(
                    for: BrowserWindowState.sidebarDefaultWidth
                )
            ),
            isSidebarVisible: true,
            floatingBarDraft: FloatingBarDraftState(
                text: "",
                navigateCurrentTab: false
            )
        )
    }
}
