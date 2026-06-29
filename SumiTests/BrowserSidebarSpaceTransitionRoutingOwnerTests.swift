import XCTest
@testable import Sumi

@MainActor
final class BrowserSidebarSpaceTransitionRoutingOwnerTests: XCTestCase {
    func testActionsRouteSpaceSelectionCalls() {
        let spy = Spy()
        let owner = makeOwner(spy: spy)
        let actions = owner.makeActions()
        let windowState = BrowserWindowState()
        let space = Space(name: "Space")
        let identity = SpaceTransitionIdentity(
            sourceSpaceId: UUID(),
            destinationSpaceId: space.id
        )

        actions.completePendingSplitGroupFocusIfReady(windowState, space.id)
        actions.setActiveSpace(space, windowState)
        actions.setActiveSpaceFromTransition(space, windowState, identity)

        XCTAssertEqual(
            spy.events,
            [
                .completePendingSplitGroupFocus(windowState.id, space.id),
                .setActiveSpace(space.id, windowState.id),
                .setActiveSpaceFromTransition(space.id, windowState.id, identity),
            ]
        )
    }

    func testActionsRouteInteractiveTransitionCallsAndReturnIdentity() {
        let spy = Spy()
        let returnedIdentity = SpaceTransitionIdentity(
            sourceSpaceId: UUID(),
            destinationSpaceId: UUID()
        )
        let owner = makeOwner(spy: spy, returnedIdentity: returnedIdentity)
        let actions = owner.makeActions()
        let windowState = BrowserWindowState()
        let source = Space(name: "Source")
        let destination = Space(name: "Destination")
        let requestedIdentity = SpaceTransitionIdentity(
            sourceSpaceId: source.id,
            destinationSpaceId: destination.id
        )

        let resolvedIdentity = actions.beginInteractiveSpaceTransition(
            source,
            destination,
            requestedIdentity,
            windowState
        )
        actions.updateInteractiveSpaceTransition(0.42, requestedIdentity, windowState)
        actions.cancelInteractiveSpaceTransition(requestedIdentity, windowState)

        XCTAssertEqual(resolvedIdentity, returnedIdentity)
        XCTAssertEqual(
            spy.events,
            [
                .beginInteractiveSpaceTransition(source.id, destination.id, requestedIdentity, windowState.id),
                .updateInteractiveSpaceTransition(0.42, requestedIdentity, windowState.id),
                .cancelInteractiveSpaceTransition(requestedIdentity, windowState.id),
            ]
        )
    }

    private func makeOwner(
        spy: Spy,
        returnedIdentity: SpaceTransitionIdentity? = nil
    ) -> BrowserSidebarSpaceTransitionRoutingOwner {
        BrowserSidebarSpaceTransitionRoutingOwner(
            dependencies: BrowserSidebarSpaceTransitionRoutingOwner.Dependencies(
                completePendingSplitGroupFocusIfReady: { windowState, spaceId in
                    spy.events.append(.completePendingSplitGroupFocus(windowState.id, spaceId))
                },
                setActiveSpace: { space, windowState in
                    spy.events.append(.setActiveSpace(space.id, windowState.id))
                },
                setActiveSpaceFromTransition: { space, windowState, identity in
                    spy.events.append(.setActiveSpaceFromTransition(space.id, windowState.id, identity))
                },
                beginInteractiveSpaceTransition: { source, destination, identity, windowState in
                    spy.events.append(
                        .beginInteractiveSpaceTransition(
                            source.id,
                            destination.id,
                            identity,
                            windowState.id
                        )
                    )
                    return returnedIdentity
                },
                updateInteractiveSpaceTransition: { progress, identity, windowState in
                    spy.events.append(.updateInteractiveSpaceTransition(progress, identity, windowState.id))
                },
                cancelInteractiveSpaceTransition: { identity, windowState in
                    spy.events.append(.cancelInteractiveSpaceTransition(identity, windowState.id))
                }
            )
        )
    }
}

private final class Spy {
    var events: [BrowserSidebarSpaceTransitionRoutingOwnerTests.Event] = []
}

extension BrowserSidebarSpaceTransitionRoutingOwnerTests {
    enum Event: Equatable {
        case completePendingSplitGroupFocus(UUID, UUID)
        case setActiveSpace(UUID, UUID)
        case setActiveSpaceFromTransition(UUID, UUID, SpaceTransitionIdentity)
        case beginInteractiveSpaceTransition(UUID, UUID, SpaceTransitionIdentity, UUID)
        case updateInteractiveSpaceTransition(Double, SpaceTransitionIdentity?, UUID)
        case cancelInteractiveSpaceTransition(SpaceTransitionIdentity?, UUID)
    }
}
