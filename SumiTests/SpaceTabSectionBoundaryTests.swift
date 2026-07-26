@testable import Sumi
import XCTest

final class SpaceTabSectionBoundaryTests: XCTestCase {
    // MARK: - Shared layout

    func testHiddenWhenNoRegularTabs() {
        let layout = SpaceTabSectionBoundaryLayout(
            hasPinnedContent: true,
            regularTabCount: 0
        )

        XCTAssertFalse(layout.showsSeparator)
        XCTAssertEqual(layout.topPadding, SidebarRowLayout.rowGap)
        XCTAssertEqual(layout.separatorHeight, 0)
        XCTAssertEqual(layout.bottomPadding, 0)
    }

    func testShownWithAnyRegularTab() {
        XCTAssertTrue(
            SpaceTabSectionBoundaryLayout(
                hasPinnedContent: false,
                regularTabCount: 1
            ).showsSeparator
        )
        XCTAssertTrue(
            SpaceTabSectionBoundaryLayout(
                hasPinnedContent: false,
                regularTabCount: 7
            ).showsSeparator
        )
    }

    // MARK: - Snapshot parity (live and snapshot share this rule)

    func testSnapshotSeparatorHiddenWithPinnedButNoRegularTabs() {
        let snapshot = makeSnapshot(hasPinnedContent: true, regularTabCount: 0)
        XCTAssertFalse(
            snapshot.tabSectionBoundaryLayout.showsSeparator,
            "Zen parity: pinned content alone must not surface the separator."
        )
    }

    func testSnapshotSeparatorShownWithRegularTabsButNoPinnedContent() {
        let snapshot = makeSnapshot(hasPinnedContent: false, regularTabCount: 2)
        XCTAssertTrue(
            snapshot.tabSectionBoundaryLayout.showsSeparator,
            "Zen parity: the separator depends only on regular tabs, not pinned content."
        )
    }

    func testSnapshotSeparatorHiddenWhenSpaceEmpty() {
        let snapshot = makeSnapshot(hasPinnedContent: false, regularTabCount: 0)
        XCTAssertFalse(snapshot.tabSectionBoundaryLayout.showsSeparator)
    }

    func testSnapshotSeparatorShownWithBothSections() {
        let snapshot = makeSnapshot(hasPinnedContent: true, regularTabCount: 3)
        XCTAssertTrue(snapshot.tabSectionBoundaryLayout.showsSeparator)
    }

    // MARK: - Layout metrics

    func testSeparatorGapIsSymmetricWhenShownWithPinned() {
        let layout = SpaceTabSectionBoundaryLayout(
            hasPinnedContent: true,
            regularTabCount: 1
        )

        XCTAssertEqual(layout.topPadding, layout.bottomPadding)
        XCTAssertEqual(
            layout.topPadding,
            SpaceTabSectionBoundaryLayout.separatorPadding
        )
    }

    func testTopPadIsZeroWithoutPinnedContent() {
        XCTAssertEqual(
            SpaceTabSectionBoundaryLayout(
                hasPinnedContent: false,
                regularTabCount: 1
            ).topPadding,
            0
        )
        XCTAssertEqual(
            SpaceTabSectionBoundaryLayout(
                hasPinnedContent: false,
                regularTabCount: 0
            ).topPadding,
            0
        )
    }

    func testLineHeightMatchesLineConstantWhenShown() {
        XCTAssertEqual(
            SpaceTabSectionBoundaryLayout(
                hasPinnedContent: true,
                regularTabCount: 1
            ).separatorHeight,
            SpaceTabSectionBoundaryLayout.hairlineHeight
        )
    }

    func testBoundaryConstants() {
        XCTAssertEqual(SpaceTabSectionBoundaryLayout.separatorPadding, 10)
        XCTAssertEqual(SpaceTabSectionBoundaryLayout.hairlineHeight, 1)
        XCTAssertEqual(SidebarRowLayout.rowGap, 4)
    }

    func testSpaceTitleUsesTheSameVerticalPitchAsRows() {
        XCTAssertEqual(
            SpaceTitleRowLayout.minimumHeight,
            SidebarRowLayout.rowHeight,
            "Space Title and tab rows must share one vertical rhythm."
        )
    }

    func testRegularSectionEndsAtNewTabWithoutTrailingClearance() {
        XCTAssertEqual(
            SpaceRegularTabsTailLayout.trailingClearance,
            0,
            "New Tab must be the final content row in live and snapshot layouts."
        )
    }

    // MARK: - Fixtures

    private func makeSnapshot(
        hasPinnedContent: Bool,
        regularTabCount: Int
    ) -> SpaceSidebarPageSnapshot {
        let regularRows = (0..<regularTabCount).map { index in
            SpaceRegularRowSnapshot.tab(
                SpaceTabRowSnapshot(
                    id: UUID(),
                    title: "Tab \(index)",
                    icon: .system("globe"),
                    isSelected: false,
                    showsUnloadedIndicator: false,
                    showsAudioButton: false,
                    isMuted: false
                )
            )
        }

        return SpaceSidebarPageSnapshot(
            spaceId: UUID(),
            title: "Space",
            iconValue: "globe",
            extensionActions: nil,
            essentials: nil,
            hasPinnedContent: hasPinnedContent,
            isPinnedContentCollapsed: false,
            pinnedItems: [],
            regularRows: regularRows,
            showsNewTabButtonInList: true,
            showsTopNewTabButton: false,
            rowCornerRadius: 12,
            scrollViewport: .zero
        )
    }
}
