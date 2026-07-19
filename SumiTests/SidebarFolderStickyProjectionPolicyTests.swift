@testable import Sumi
import XCTest

final class SidebarFolderStickyProjectionPolicyTests: XCTestCase {
    private let pinA = UUID()
    private let pinB = UUID()
    private let pinC = UUID()
    private let splitGroup = UUID()
    private let outsider = UUID()

    private func makeContext(
        isFolderOpen: Bool = false,
        ordered: [UUID]? = nil,
        eligible: Set<UUID>? = nil,
        selected: UUID? = nil
    ) -> SidebarFolderStickyProjectionPolicy.Context {
        let orderedIDs = ordered ?? [pinA, splitGroup, pinB, pinC]
        return SidebarFolderStickyProjectionPolicy.Context(
            isFolderOpen: isFolderOpen,
            orderedDescendantItemIDs: orderedIDs,
            visibleEligibleItemIDs: eligible ?? Set(orderedIDs),
            selectedDescendantItemID: selected
        )
    }

    // MARK: stickyOnCollapse

    func testCollapseSeedsSelectedDescendant() {
        let sticky = SidebarFolderStickyProjectionPolicy.stickyOnCollapse(
            context: makeContext(selected: pinB)
        )
        XCTAssertEqual(sticky, [pinB])
    }

    func testCollapseSeedsSelectedSplitGroup() {
        let sticky = SidebarFolderStickyProjectionPolicy.stickyOnCollapse(
            context: makeContext(selected: splitGroup)
        )
        XCTAssertEqual(sticky, [splitGroup])
    }

    func testCollapseWithSelectionOutsideSeedsNothing() {
        let sticky = SidebarFolderStickyProjectionPolicy.stickyOnCollapse(
            context: makeContext(selected: nil)
        )
        XCTAssertTrue(sticky.isEmpty)
    }

    // MARK: stickyAppendingSelection

    func testSelectionsAccumulateInPositionalOrderRegardlessOfSelectionOrder() {
        var sticky = SidebarFolderStickyProjectionPolicy.stickyAppendingSelection(
            current: [],
            context: makeContext(selected: pinC)
        )
        sticky = SidebarFolderStickyProjectionPolicy.stickyAppendingSelection(
            current: sticky,
            context: makeContext(selected: pinA)
        )
        sticky = SidebarFolderStickyProjectionPolicy.stickyAppendingSelection(
            current: sticky,
            context: makeContext(selected: splitGroup)
        )
        XCTAssertEqual(sticky, [pinA, splitGroup, pinC])
    }

    func testSelectionMovingElsewhereKeepsStickyUntouched() {
        let sticky = SidebarFolderStickyProjectionPolicy.stickyAppendingSelection(
            current: [pinA, pinB],
            context: makeContext(selected: nil)
        )
        XCTAssertEqual(sticky, [pinA, pinB])
    }

    func testAppendIsNoOpForAlreadyStickyItem() {
        let sticky = SidebarFolderStickyProjectionPolicy.stickyAppendingSelection(
            current: [pinA],
            context: makeContext(selected: pinA)
        )
        XCTAssertEqual(sticky, [pinA])
    }

    func testAppendWhileOpenIsNoOp() {
        let sticky = SidebarFolderStickyProjectionPolicy.stickyAppendingSelection(
            current: [pinA],
            context: makeContext(isFolderOpen: true, selected: pinB)
        )
        XCTAssertEqual(sticky, [pinA])
    }

    func testUnloadedStickyIsReplacedBySelectedLiveSibling() {
        let context = makeContext(eligible: [pinB], selected: pinB)
        let sticky = SidebarFolderStickyProjectionPolicy.stickyAppendingSelection(
            current: [pinA],
            context: context
        )

        XCTAssertEqual(sticky, [pinA, pinB])
        XCTAssertEqual(
            SidebarFolderStickyProjectionPolicy.visibleStickyIDs(
                sticky: sticky,
                context: context
            ),
            [pinB]
        )
    }

    // MARK: stickyPruned

    func testPruneDropsItemsThatLeftTheSubtree() {
        let sticky = SidebarFolderStickyProjectionPolicy.stickyPruned(
            current: [pinA, outsider, pinB],
            context: makeContext()
        )
        XCTAssertEqual(sticky, [pinA, pinB])
    }

    func testPruneClearsEverythingWhenFolderIsOpen() {
        let sticky = SidebarFolderStickyProjectionPolicy.stickyPruned(
            current: [pinA, pinB],
            context: makeContext(isFolderOpen: true)
        )
        XCTAssertTrue(sticky.isEmpty)
    }

    func testPruneIsIdempotent() {
        let context = makeContext()
        let once = SidebarFolderStickyProjectionPolicy.stickyPruned(
            current: [pinC, outsider, pinA],
            context: context
        )
        let twice = SidebarFolderStickyProjectionPolicy.stickyPruned(
            current: once,
            context: context
        )
        XCTAssertEqual(once, twice)
        XCTAssertEqual(once, [pinA, pinC])
    }

    // MARK: visibleStickyIDs

    func testVisibleFiltersNonLiveLaunchers() {
        let visible = SidebarFolderStickyProjectionPolicy.visibleStickyIDs(
            sticky: [pinA, pinB],
            context: makeContext(eligible: [pinB])
        )
        XCTAssertEqual(visible, [pinB])
    }

    func testClosingLastLiveStickyYieldsEmptyProjection() {
        let visible = SidebarFolderStickyProjectionPolicy.visibleStickyIDs(
            sticky: [pinA],
            context: makeContext(eligible: [])
        )
        XCTAssertTrue(visible.isEmpty)
    }

    // MARK: expandTransfers

    func testExpandRoutesItemToRootmostCollapsedAncestor() {
        let inner = UUID()
        let outer = UUID()
        let transfers = SidebarFolderStickyProjectionPolicy.expandTransfers(
            sticky: [pinA],
            ancestorChainsByItemID: [pinA: [outer, inner]],
            collapsedFolderIDs: [outer, inner]
        )
        XCTAssertEqual(transfers, [outer: [pinA]])
    }

    func testExpandSkipsChainsWithNoCollapsedFolder() {
        let inner = UUID()
        let transfers = SidebarFolderStickyProjectionPolicy.expandTransfers(
            sticky: [pinA],
            ancestorChainsByItemID: [pinA: [inner]],
            collapsedFolderIDs: []
        )
        XCTAssertTrue(transfers.isEmpty)
    }

    func testExpandLeavesDirectChildrenBehind() {
        let transfers = SidebarFolderStickyProjectionPolicy.expandTransfers(
            sticky: [pinA, pinB],
            ancestorChainsByItemID: [pinA: []],
            collapsedFolderIDs: [UUID()]
        )
        XCTAssertTrue(transfers.isEmpty)
    }

    func testExpandGroupsMultipleItemsPerTargetFolder() {
        let inner = UUID()
        let transfers = SidebarFolderStickyProjectionPolicy.expandTransfers(
            sticky: [pinA, pinB],
            ancestorChainsByItemID: [pinA: [inner], pinB: [inner]],
            collapsedFolderIDs: [inner]
        )
        XCTAssertEqual(transfers, [inner: [pinA, pinB]])
    }

    // MARK: hasActiveProjection

    func testHasActiveProjectionTracksVisibleRows() {
        XCTAssertTrue(
            SidebarFolderStickyProjectionPolicy.hasActiveProjection(visibleStickyIDs: [pinA])
        )
        XCTAssertFalse(
            SidebarFolderStickyProjectionPolicy.hasActiveProjection(visibleStickyIDs: [])
        )
    }
}
