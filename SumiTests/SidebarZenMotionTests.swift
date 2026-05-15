import AppKit
import XCTest
@testable import Sumi

@MainActor
final class SidebarZenMotionTests: XCTestCase {
    func testSidebarMotionPolicyUsesReducedMotionContract() {
        XCTAssertEqual(SidebarMotionPolicy.currentMode(reduceMotion: true), .reducedMotion)
        XCTAssertNil(SidebarMotionPolicy.dockedLayoutAnimation(for: .reducedMotion, isShowing: true))
        XCTAssertFalse(SidebarMotionPolicy.overlayUsesTravel(for: .reducedMotion))
        XCTAssertNil(SidebarMotionPolicy.rowLifecycleAnimation(for: .reducedMotion))
    }

    func testSidebarMotionPolicyKeepsStandardShellMotion() {
        XCTAssertEqual(SidebarMotionPolicy.currentMode(reduceMotion: false), .standard)
        XCTAssertNotNil(SidebarMotionPolicy.dockedLayoutAnimation(for: .standard, isShowing: true))
        XCTAssertTrue(SidebarMotionPolicy.overlayUsesTravel(for: .standard))
        XCTAssertNotNil(SidebarMotionPolicy.rowLifecycleAnimation(for: .standard))
    }

    func testSidebarInteractiveItemPublishesPressedSourceDuringPrimaryMouseDown() {
        let state = SidebarInteractionState()
        let view = makeInteractiveItemView(
            sourceID: "tab-row-test",
            state: state
        )

        view.mouseDown(with: mouseEvent(.leftMouseDown))

        XCTAssertEqual(state.activePressedSourceID, "tab-row-test")
    }

    func testSidebarInteractiveItemClearsPressedSourceOnMouseUp() {
        let state = SidebarInteractionState()
        var activationCount = 0
        let view = makeInteractiveItemView(
            sourceID: "tab-row-test",
            state: state
        ) {
            activationCount += 1
        }

        view.mouseDown(with: mouseEvent(.leftMouseDown))
        view.mouseUp(with: mouseEvent(.leftMouseUp))

        XCTAssertNil(state.activePressedSourceID)
        XCTAssertEqual(activationCount, 1)
    }

    func testSidebarInteractiveItemClearsPressedSourceOnCancelTracking() {
        let state = SidebarInteractionState()
        let view = makeInteractiveItemView(
            sourceID: "tab-row-test",
            state: state
        )

        view.mouseDown(with: mouseEvent(.leftMouseDown))
        view.cancelPrimaryMouseTracking()

        XCTAssertNil(state.activePressedSourceID)
    }

    func testUnrelatedBridgeUpdateWithoutSourceDoesNotClearPressedSource() {
        let state = SidebarInteractionState()
        let pressedView = makeInteractiveItemView(
            sourceID: "tab-row-test",
            state: state
        )
        let unrelatedView = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 160, height: 36)
        )

        pressedView.mouseDown(with: mouseEvent(.leftMouseDown))
        unrelatedView.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                sourceID: nil
            )
        )

        XCTAssertEqual(state.activePressedSourceID, "tab-row-test")
    }

    func testPrimaryActionWithSourceIDUsesAppKitOwnerForPressTrackingInDockedSidebar() {
        let context = SidebarPresentationContext.docked(sidebarWidth: 280)

        XCTAssertTrue(
            SidebarPrimaryActionInputRouting.usesAppKitOwner(
                in: context,
                sourceID: "space-new-tab-test"
            )
        )
    }

    func testPrimaryActionWithoutSourceIDKeepsNativeRoutingInDockedSidebar() {
        let context = SidebarPresentationContext.docked(sidebarWidth: 280)

        XCTAssertFalse(SidebarPrimaryActionInputRouting.usesAppKitOwner(in: context))
    }

    private func makeInteractiveItemView(
        sourceID: String,
        state: SidebarInteractionState,
        action: @escaping () -> Void = {}
    ) -> SidebarInteractiveItemView {
        let view = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 160, height: 36))
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                primaryAction: action,
                sourceID: sourceID
            )
        )
        return view
    }

    private func mouseEvent(_ type: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: 12, y: 12),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
    }
}
