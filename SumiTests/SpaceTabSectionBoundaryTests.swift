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

    func testIncognitoSnapshotHidesSeparator() {
        let snapshot = makeSnapshot(
            hasPinnedContent: false,
            regularTabCount: 2,
            supportsPinnedContent: false
        )

        XCTAssertFalse(snapshot.tabSectionBoundaryLayout.showsSeparator)
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

    func testSeparatorKeepsHalfARowAboveItWithoutPinnedContent() {
        let layout = SpaceTabSectionBoundaryLayout(
            hasPinnedContent: false,
            regularTabCount: 1
        )

        XCTAssertEqual(
            layout.topPadding,
            SpaceTabSectionBoundaryLayout.emptyPinnedTopPadding,
            "Without pinned content the hairline needs room above it, or the element's own clip shaves it."
        )
        XCTAssertEqual(
            SpaceTabSectionBoundaryLayout.emptyPinnedTopPadding,
            SidebarRowLayout.rowHeight / 2
        )
    }

    func testEmptySpaceKeepsEveryBoundaryMetricAtZero() {
        let layout = SpaceTabSectionBoundaryLayout(
            hasPinnedContent: false,
            regularTabCount: 0
        )

        XCTAssertFalse(layout.showsSeparator)
        XCTAssertEqual(
            layout.topPadding,
            0,
            "New Tab must sit directly under the space title when nothing else is in the list."
        )
        XCTAssertEqual(layout.separatorHeight, 0)
        XCTAssertEqual(layout.bottomPadding, 0)
    }

    func testIncognitoDoesNotShowThePinnedBoundary() {
        let layout = SpaceTabSectionBoundaryLayout(
            hasPinnedContent: false,
            regularTabCount: 3,
            supportsPinnedContent: false
        )

        XCTAssertFalse(layout.showsSeparator)
        XCTAssertEqual(layout.topPadding, 0)
        XCTAssertEqual(layout.separatorHeight, 0)
        XCTAssertEqual(layout.bottomPadding, 0)
    }

    func testPinnedContentKeepsItsExistingPadding() {
        XCTAssertEqual(
            SpaceTabSectionBoundaryLayout(
                hasPinnedContent: true,
                regularTabCount: 1
            ).topPadding,
            SpaceTabSectionBoundaryLayout.separatorPadding
        )
        XCTAssertEqual(
            SpaceTabSectionBoundaryLayout(
                hasPinnedContent: true,
                regularTabCount: 0
            ).topPadding,
            SidebarRowLayout.rowGap
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
        XCTAssertEqual(SpaceTabSectionBoundaryLayout.emptyPinnedTopPadding, 18)
        XCTAssertEqual(SidebarRowLayout.rowGap, 4)
    }

    func testSpaceTitleUsesTheSameVerticalPitchAsRows() {
        XCTAssertEqual(
            SpaceTitleRowLayout.minimumHeight,
            SidebarRowLayout.rowHeight,
            "Space Title and tab rows must share one vertical rhythm."
        )
    }

    // MARK: - Fixtures

    private func makeSnapshot(
        hasPinnedContent: Bool,
        regularTabCount: Int,
        supportsPinnedContent: Bool = true
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
            supportsPinnedContent: supportsPinnedContent,
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
