import XCTest

@testable import Sumi

/// The container-transfer contract: a drop that moves a row between the pinned
/// and regular sections must present one row throughout, and must never leave
/// the retired identity behind.
final class SidebarListIdentityTransferTests: XCTestCase {
    func testStandaloneContainerConversionMovesOnePresentedRow() {
        let pinID = UUID()
        let tabID = UUID()
        var state = SidebarListPresentationState(
            scene: SidebarListScene<PresentedRowID, String>(
                elements: [
                    .init(
                        id: .shortcut(pinID),
                        payload: "pinned",
                        targetExtent: 36
                    ),
                    .init(
                        id: .boundary,
                        payload: "boundary",
                        targetExtent: 8
                    ),
                ]
            )
        )
        let target = SidebarListScene<PresentedRowID, String>(
            elements: [
                .init(
                    id: .boundary,
                    payload: "boundary",
                    targetExtent: 8
                ),
                .init(
                    id: .regularTab(tabID),
                    payload: "regular",
                    targetExtent: 36
                ),
            ]
        )

        let transition = state.prepareTransition(
            to: target,
            transferring: transfer(retiring: pinID)
        )
        state.animate(transition)

        XCTAssertEqual(state.items.count, 2)
        XCTAssertEqual(state.items.map(\.id), [.boundary, .shortcut(pinID)])
        XCTAssertEqual(state.payload(for: .shortcut(pinID)), "regular")
        XCTAssertEqual(
            state.items.map(\.phase),
            [.stable, .stable],
            "A transferred row slides; it never collapses and regrows"
        )

        state.settle(transition)

        XCTAssertEqual(state.items.map(\.id), [.boundary, .regularTab(tabID)])
    }

    func testReverseStandaloneContainerConversionMovesOnePresentedRow() {
        let tabID = UUID()
        let pinID = UUID()
        var state = SidebarListPresentationState(
            scene: SidebarListScene<PresentedRowID, String>(
                elements: [
                    .init(
                        id: .boundary,
                        payload: "boundary",
                        targetExtent: 8
                    ),
                    .init(
                        id: .regularTab(tabID),
                        payload: "regular",
                        targetExtent: 36
                    ),
                ]
            )
        )
        let target = SidebarListScene<PresentedRowID, String>(
            elements: [
                .init(
                    id: .shortcut(pinID),
                    payload: "pinned",
                    targetExtent: 36
                ),
                .init(
                    id: .boundary,
                    payload: "boundary",
                    targetExtent: 8
                ),
            ]
        )

        let transition = state.prepareTransition(
            to: target,
            transferring: transfer(retiring: tabID)
        )
        state.animate(transition)

        XCTAssertEqual(state.items.count, 2)
        XCTAssertEqual(state.items.map(\.id), [.regularTab(tabID), .boundary])
        XCTAssertEqual(state.payload(for: .regularTab(tabID)), "pinned")

        state.settle(transition)

        XCTAssertEqual(state.items.map(\.id), [.shortcut(pinID), .boundary])
    }

    func testIdentityTransferRequiresOneRemovedAndOneInsertedRow() {
        let firstID = UUID()
        let secondID = UUID()
        var state = SidebarListPresentationState(
            scene: SidebarListScene<PresentedRowID, String>(
                elements: [
                    .init(
                        id: .regularTab(firstID),
                        payload: "first",
                        targetExtent: 36
                    ),
                ]
            )
        )
        let target = SidebarListScene<PresentedRowID, String>(
            elements: [
                .init(
                    id: .regularTab(firstID),
                    payload: "first",
                    targetExtent: 36
                ),
                .init(
                    id: .regularTab(secondID),
                    payload: "second",
                    targetExtent: 36
                ),
            ]
        )

        let transition = state.prepareTransition(
            to: target,
            transferring: transfer(retiring: firstID)
        )

        XCTAssertEqual(state.items.map(\.id), [
            .regularTab(firstID),
            .regularTab(secondID),
        ])
        XCTAssertEqual(state.items.last?.phase, .entering)

        state.animate(transition)
        state.settle(transition)
    }

    func testIdentityTransferRequiresTheRetiredRowToBeTheDragSource() {
        let draggedPinID = UUID()
        let unrelatedPinID = UUID()
        let tabID = UUID()
        var state = SidebarListPresentationState(
            scene: SidebarListScene<PresentedRowID, String>(
                elements: [
                    .init(
                        id: .shortcut(unrelatedPinID),
                        payload: "unrelated",
                        targetExtent: 36
                    ),
                    .init(
                        id: .boundary,
                        payload: "boundary",
                        targetExtent: 8
                    ),
                ]
            )
        )
        let target = SidebarListScene<PresentedRowID, String>(
            elements: [
                .init(
                    id: .boundary,
                    payload: "boundary",
                    targetExtent: 8
                ),
                .init(
                    id: .regularTab(tabID),
                    payload: "regular",
                    targetExtent: 36
                ),
            ]
        )

        let transition = state.prepareTransition(
            to: target,
            transferring: transfer(retiring: draggedPinID)
        )

        XCTAssertEqual(
            state.items.first { $0.id == .shortcut(unrelatedPinID) }?.phase,
            .leaving,
            "A removal the drag did not cause must not donate its identity"
        )
        XCTAssertEqual(
            state.items.first { $0.id == .regularTab(tabID) }?.phase,
            .entering
        )

        state.animate(transition)
        state.settle(transition)

        XCTAssertEqual(state.items.map(\.id), [.boundary, .regularTab(tabID)])
    }

    func testSupersededTransferDoesNotStrandTheRetiredIdentity() {
        let pinID = UUID()
        let tabID = UUID()
        var state = SidebarListPresentationState(
            scene: SidebarListScene<PresentedRowID, String>(
                elements: [
                    .init(
                        id: .shortcut(pinID),
                        payload: "pinned",
                        targetExtent: 36
                    ),
                    .init(
                        id: .boundary,
                        payload: "boundary",
                        targetExtent: 8
                    ),
                ]
            )
        )
        let converted = SidebarListScene<PresentedRowID, String>(
            elements: [
                .init(
                    id: .boundary,
                    payload: "boundary",
                    targetExtent: 8
                ),
                .init(
                    id: .regularTab(tabID),
                    payload: "regular",
                    targetExtent: 36
                ),
            ]
        )

        let conversion = state.prepareTransition(
            to: converted,
            transferring: transfer(retiring: pinID)
        )
        state.animate(conversion)

        // The settle never lands: a later structural change supersedes it.
        let interruption = state.prepareTransition(to: converted)
        state.animate(interruption)
        state.settle(interruption)
        state.settle(conversion)

        XCTAssertEqual(
            state.items.map(\.id),
            [.boundary, .regularTab(tabID)],
            "A superseded transfer must hand the borrowed identity back"
        )
        XCTAssertFalse(
            state.items.contains { $0.id == .shortcut(pinID) },
            "The retired pin must not survive as a non-interactive row"
        )
        XCTAssertEqual(state.items.map(\.phase), [.stable, .stable])
    }

    func testRepeatedTransferDoesNotReadoptItsOwnLeftover() {
        let pinID = UUID()
        let tabID = UUID()
        var state = SidebarListPresentationState(
            scene: SidebarListScene<PresentedRowID, String>(
                elements: [
                    .init(
                        id: .shortcut(pinID),
                        payload: "pinned",
                        targetExtent: 36
                    ),
                ]
            )
        )
        let converted = SidebarListScene<PresentedRowID, String>(
            elements: [
                .init(
                    id: .regularTab(tabID),
                    payload: "regular",
                    targetExtent: 36
                ),
            ]
        )

        let first = state.prepareTransition(
            to: converted,
            transferring: transfer(retiring: pinID)
        )
        state.animate(first)

        let second = state.prepareTransition(
            to: converted,
            transferring: transfer(retiring: pinID)
        )
        state.animate(second)
        state.settle(second)

        XCTAssertEqual(state.items.map(\.id), [.regularTab(tabID)])
        XCTAssertEqual(state.items.map(\.phase), [.stable])
    }

    func testSplitGroupContainerConversionPresentsOneRow() {
        let groupID = UUID()
        var state = SidebarListPresentationState(
            scene: SidebarListScene<PresentedRowID, String>(
                elements: [
                    .init(
                        id: .splitGroup(groupID),
                        payload: "pinned",
                        targetExtent: 36
                    ),
                ]
            )
        )
        let target = SidebarListScene<PresentedRowID, String>(
            elements: [
                .init(
                    id: .splitGroup(groupID),
                    payload: "regular",
                    targetExtent: 36
                ),
            ]
        )

        let transition = state.prepareTransition(to: target)
        state.animate(transition)

        let presentedGroupIDs = state.items.compactMap { item -> UUID? in
            switch item.id {
            case .splitGroup(let id):
                return id
            default:
                return nil
            }
        }
        XCTAssertEqual(
            presentedGroupIDs,
            [groupID],
            "A container conversion must move one visual row, not retain a pinned duplicate"
        )
    }
}

private enum PresentedRowID: Hashable {
    case shortcut(UUID)
    case regularTab(UUID)
    case splitGroup(UUID)
    case boundary

    var transferableItemID: UUID? {
        switch self {
        case .shortcut(let itemID), .regularTab(let itemID):
            return itemID
        case .splitGroup, .boundary:
            return nil
        }
    }
}

private func transfer(
    retiring itemID: UUID
) -> SidebarListIdentityTransfer<PresentedRowID> {
    SidebarListIdentityTransfer(
        isSource: { $0.transferableItemID == itemID },
        isTransferable: { $0.transferableItemID != nil }
    )
}
