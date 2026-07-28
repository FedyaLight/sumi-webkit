import XCTest

@testable import Sumi

final class SidebarListPresentationTests: XCTestCase {
    func testInsertionUsesOneStableIdentityFromZeroExtentToTargetExtent() {
        var state = SidebarListPresentationState(
            scene: scene([])
        )
        let target = scene([
            element(id: 1, payload: "first", extent: 36),
        ])

        let transition = state.prepareTransition(to: target)

        XCTAssertEqual(state.items.map(\.id), [1])
        XCTAssertEqual(state.items[0].extent, 0)
        XCTAssertEqual(state.items[0].opacity, 0)
        XCTAssertEqual(state.items[0].phase, .entering)
        XCTAssertTrue(state.items[0].reportsAnimatedExtent)

        state.animate(transition)

        XCTAssertEqual(state.items.map(\.id), [1])
        XCTAssertEqual(state.items[0].extent, 36)
        XCTAssertEqual(state.items[0].opacity, 1)
        XCTAssertEqual(state.items[0].phase, .entering)

        state.settle(transition)

        XCTAssertEqual(state.items[0].phase, .stable)
        XCTAssertFalse(state.items[0].reportsAnimatedExtent)
    }

    func testRemovalRetainsPayloadOnlyUntilLatestTransitionSettles() {
        weak var weakPayload: PayloadBox?
        var state: SidebarListPresentationState<Int, PayloadBox>!

        do {
            let payload = PayloadBox()
            weakPayload = payload
            state = SidebarListPresentationState(
                scene: SidebarListScene(elements: [
                    .init(
                        id: 1,
                        payload: payload,
                        targetExtent: 36
                    ),
                ])
            )
        }

        let emptyScene = SidebarListScene<Int, PayloadBox>(elements: [])
        let transition = state.prepareTransition(to: emptyScene)
        state.animate(transition)

        XCTAssertNotNil(weakPayload)
        XCTAssertEqual(state.items[0].phase, .leaving)

        state.settle(transition)

        XCTAssertNil(weakPayload)
        XCTAssertTrue(state.items.isEmpty)
    }

    func testLatestTransitionWinsOverStaleCompletion() {
        var state = SidebarListPresentationState(
            scene: scene([
                element(id: 1, payload: "first", extent: 36),
                element(id: 2, payload: "second", extent: 36),
            ])
        )

        let firstTransition = state.prepareTransition(to: scene([]))
        state.animate(firstTransition)

        let latestScene = scene([
            element(id: 3, payload: "latest", extent: 36),
        ])
        let latestTransition = state.prepareTransition(to: latestScene)
        state.animate(latestTransition)
        state.settle(latestTransition)

        state.settle(firstTransition)

        XCTAssertEqual(state.items.map(\.id), [3])
        XCTAssertEqual(state.payload(for: 3), "latest")
    }

    func testInsertionPreservesTargetOrderWithoutChangingExistingIdentity() {
        var state = SidebarListPresentationState(
            scene: scene([
                element(id: 1, payload: "first", extent: 36),
                element(id: 3, payload: "third", extent: 36),
            ])
        )
        let target = scene([
            element(id: 1, payload: "first", extent: 36),
            element(id: 2, payload: "second", extent: 36),
            element(id: 3, payload: "third", extent: 36),
        ])

        let transition = state.prepareTransition(to: target)
        XCTAssertEqual(state.items.map(\.id), [1, 2, 3])

        state.animate(transition)
        state.settle(transition)

        XCTAssertEqual(state.items.map(\.id), [1, 2, 3])
    }

    func testInterruptedInsertionDoesNotEnableRowBeforeLatestSettle() {
        var state = SidebarListPresentationState(scene: scene([]))
        let firstTransition = state.prepareTransition(to: scene([
            element(id: 1, payload: "first", extent: 36),
        ]))
        state.animate(firstTransition)

        let latestTransition = state.prepareTransition(to: scene([
            element(id: 1, payload: "first", extent: 36),
            element(id: 2, payload: "second", extent: 36),
        ]))

        XCTAssertEqual(state.items.map(\.phase), [.entering, .entering])

        state.animate(latestTransition)
        state.settle(latestTransition)

        XCTAssertEqual(state.items.map(\.phase), [.stable, .stable])
    }

    func testNonStructuralPayloadUpdateDoesNotNeedAListTransition() {
        let initial = scene([
            element(id: 1, payload: "old", extent: 36),
        ])
        let target = scene([
            element(id: 1, payload: "new", extent: 36),
        ])
        let state = SidebarListPresentationState(scene: initial)

        XCTAssertEqual(initial.structure, target.structure)
        XCTAssertEqual(state.payload(for: 1, targeting: target), "new")
    }

    func testOnlyItemsWhoseExtentChangesReportPresentationTicks() {
        var state = SidebarListPresentationState(
            scene: scene([
                element(id: 1, payload: "stable", extent: 36),
                element(id: 2, payload: "resized", extent: 36),
            ])
        )
        let transition = state.prepareTransition(to: scene([
            element(id: 1, payload: "stable", extent: 36),
            element(id: 2, payload: "resized", extent: 44),
            element(id: 3, payload: "inserted", extent: 36),
        ]))

        XCTAssertEqual(
            state.items.map(\.reportsAnimatedExtent),
            [false, true, true]
        )

        state.animate(transition)

        XCTAssertEqual(
            state.items.map(\.reportsAnimatedExtent),
            [false, true, true]
        )

        state.settle(transition)

        XCTAssertEqual(
            state.items.map(\.reportsAnimatedExtent),
            [false, false, false]
        )
    }

    func testBulkInsertionKeepsTargetOrder() {
        var state = SidebarListPresentationState(scene: scene([]))
        let target = scene(
            (0..<1_000).map {
                element(id: $0, payload: "item-\($0)", extent: 36)
            }
        )

        let transition = state.prepareTransition(to: target)

        XCTAssertEqual(state.items.map(\.id), Array(0..<1_000))
        XCTAssertTrue(state.items.allSatisfy { $0.phase == .entering })

        state.animate(transition)
        state.settle(transition)

        XCTAssertEqual(state.items.map(\.id), Array(0..<1_000))
    }

    func testDeparturesRemainBeforeNearestSurvivingSuccessor() {
        var state = SidebarListPresentationState(
            scene: scene((1...5).map {
                element(id: $0, payload: "item-\($0)", extent: 36)
            })
        )
        let transition = state.prepareTransition(to: scene([
            element(id: 3, payload: "item-3", extent: 36),
            element(id: 6, payload: "item-6", extent: 36),
        ]))

        XCTAssertEqual(state.items.map(\.id), [1, 2, 3, 6, 4, 5])

        state.animate(transition)

        XCTAssertEqual(state.items.map(\.id), [1, 2, 3, 6, 4, 5])
        XCTAssertEqual(
            state.items.map(\.phase),
            [.leaving, .leaving, .stable, .entering, .leaving, .leaving]
        )
    }

    func testReorderKeepsOldPlacementUntilAnimationBegins() {
        var state = SidebarListPresentationState(
            scene: scene([
                element(id: 1, payload: "item-1", extent: 40),
                element(id: 2, payload: "item-2", extent: 40),
                element(id: 3, payload: "item-3", extent: 36),
            ])
        )
        let transition = state.prepareTransition(to: scene([
            element(id: 3, payload: "item-3", extent: 40),
            element(id: 1, payload: "item-1", extent: 40),
            element(id: 2, payload: "item-2", extent: 36),
        ]))

        XCTAssertEqual(state.items.map(\.id), [1, 2, 3])
        XCTAssertEqual(
            state.items.map(\.reportsAnimatedExtent),
            [false, true, true]
        )

        state.animate(transition)

        XCTAssertEqual(state.items.map(\.id), [3, 1, 2])
    }

    private func scene(
        _ elements: [SidebarListScene<Int, String>.Element]
    ) -> SidebarListScene<Int, String> {
        SidebarListScene(elements: elements)
    }

    private func element(
        id: Int,
        payload: String,
        extent: CGFloat
    ) -> SidebarListScene<Int, String>.Element {
        .init(
            id: id,
            payload: payload,
            targetExtent: extent
        )
    }
}

private final class PayloadBox {}
