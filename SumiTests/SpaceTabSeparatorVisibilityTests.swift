import CoreGraphics
@testable import Sumi
import XCTest

final class SpaceTabSeparatorVisibilityTests: XCTestCase {
    // MARK: - Pure rule

    func testHiddenWhenNoRegularTabs() {
        XCTAssertFalse(SpaceTabSeparatorVisibility.shouldShow(regularTabCount: 0))
    }

    func testShownWithAnyRegularTab() {
        XCTAssertTrue(SpaceTabSeparatorVisibility.shouldShow(regularTabCount: 1))
        XCTAssertTrue(SpaceTabSeparatorVisibility.shouldShow(regularTabCount: 7))
    }

    // MARK: - Snapshot parity (live and snapshot share this rule)

    func testSnapshotSeparatorHiddenWithPinnedButNoRegularTabs() {
        let snapshot = makeSnapshot(hasPinnedContent: true, regularTabCount: 0)
        XCTAssertFalse(
            snapshot.showsPinnedSeparator,
            "Zen parity: pinned content alone must not surface the separator."
        )
    }

    func testSnapshotSeparatorShownWithRegularTabsButNoPinnedContent() {
        let snapshot = makeSnapshot(hasPinnedContent: false, regularTabCount: 2)
        XCTAssertTrue(
            snapshot.showsPinnedSeparator,
            "Zen parity: the separator depends only on regular tabs, not pinned content."
        )
    }

    func testSnapshotSeparatorHiddenWhenSpaceEmpty() {
        let snapshot = makeSnapshot(hasPinnedContent: false, regularTabCount: 0)
        XCTAssertFalse(snapshot.showsPinnedSeparator)
    }

    func testSnapshotSeparatorShownWithBothSections() {
        let snapshot = makeSnapshot(hasPinnedContent: true, regularTabCount: 3)
        XCTAssertTrue(snapshot.showsPinnedSeparator)
    }

    // MARK: - Layout metrics

    func testSeparatorGapIsSymmetricWhenShownWithPinned() {
        // The whole point of the rework: line→pinned == line→regular.
        let top = SpaceTabSeparatorLayout.topPad(hasPinnedContent: true, showsSeparator: true)
        let bottom = SpaceTabSeparatorLayout.bottomPad(showsSeparator: true)
        XCTAssertEqual(top, bottom)
        XCTAssertEqual(top, SpaceTabSeparatorLayout.separatorPadding)
    }

    func testNoLineGapIsOneRowGapWithPinned() {
        // No line + pinned → the New-Tab button sits one uniform row gap below the
        // pinned list (Zen row rhythm), not flush.
        XCTAssertEqual(
            SpaceTabSeparatorLayout.topPad(hasPinnedContent: true, showsSeparator: false),
            SidebarRowLayout.rowGap
        )
        XCTAssertEqual(SpaceTabSeparatorLayout.lineHeight(showsSeparator: false), 0)
        XCTAssertEqual(SpaceTabSeparatorLayout.bottomPad(showsSeparator: false), 0)
    }

    func testTopPadIsZeroWithoutPinnedContent() {
        // No pinned rows above → the shown line sits under the title, no top gap.
        XCTAssertEqual(SpaceTabSeparatorLayout.topPad(hasPinnedContent: false, showsSeparator: true), 0)
        XCTAssertEqual(SpaceTabSeparatorLayout.topPad(hasPinnedContent: false, showsSeparator: false), 0)
    }

    func testLineHeightMatchesLineConstantWhenShown() {
        XCTAssertEqual(
            SpaceTabSeparatorLayout.lineHeight(showsSeparator: true),
            SpaceTabSeparatorLayout.line
        )
    }

    func testBoundaryConstants() {
        XCTAssertEqual(SpaceTabSeparatorLayout.separatorPadding, 10)
        XCTAssertEqual(SpaceTabSeparatorLayout.line, 1)
        XCTAssertEqual(SidebarRowLayout.rowGap, 4)
    }

    // MARK: - Pinned drop geometry is spacing-aware

    func testPinnedHitMetricsDerivesRowPitchFromFrame() {
        let leadingInset = SidebarInsertionGuide.visualCenterY
        let rowCount = 3
        let gap = SidebarRowLayout.rowGap
        let height = leadingInset
            + CGFloat(rowCount) * SidebarRowLayout.rowHeight
            + CGFloat(rowCount - 1) * gap
        let metrics = SidebarPinnedListHitMetrics(
            frame: CGRect(x: 0, y: 100, width: 240, height: height),
            rowCount: rowCount,
            leadingInset: leadingInset
        )

        XCTAssertEqual(metrics.rowPitch, SidebarRowLayout.rowHeight + gap, accuracy: 0.01)
        // Boundary 0 is the top of the first row; interior boundary 1 centers in
        // the gap above row 1.
        XCTAssertEqual(metrics.boundaryY(for: 0), 100 + leadingInset, accuracy: 0.01)
        XCTAssertEqual(
            metrics.boundaryY(for: 1),
            100 + leadingInset + SidebarRowLayout.rowHeight + gap / 2,
            accuracy: 0.01
        )
        // A Y just past the first row's pitch resolves to slot 1.
        let midSecondRow = 100 + leadingInset + SidebarRowLayout.rowHeight + gap + 2
        XCTAssertEqual(metrics.rowBoundaryIndex(forGlobalY: midSecondRow), 1)
    }

    // MARK: - Fixtures

    private func makeSnapshot(
        hasPinnedContent: Bool,
        regularTabCount: Int
    ) -> SpaceSidebarPageSnapshot {
        let regularTabs = (0..<regularTabCount).map { index in
            SpaceTabRowSnapshot(
                id: UUID(),
                title: "Tab \(index)",
                icon: .system("globe"),
                isSelected: false,
                showsUnloadedIndicator: false,
                showsAudioButton: false,
                isMuted: false
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
            regularTabs: regularTabs,
            showsNewTabButtonInList: true,
            showsTopNewTabButton: false,
            rowCornerRadius: 12,
            scrollViewport: .zero
        )
    }
}
