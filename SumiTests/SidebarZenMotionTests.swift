import AppKit
@testable import Sumi
import XCTest

@MainActor
final class SidebarZenMotionTests: XCTestCase {
    func testSidebarMotionPolicyUsesReducedMotionContract() {
        XCTAssertEqual(SidebarMotionPolicy.currentMode(reduceMotion: true), .reducedMotion)
        XCTAssertNil(SidebarMotionPolicy.dockedLayoutAnimation(for: .reducedMotion, isShowing: true))
        XCTAssertFalse(SidebarMotionPolicy.overlayUsesTravel(for: .reducedMotion))
    }

    func testSidebarMotionPolicyKeepsStandardShellMotion() {
        XCTAssertEqual(SidebarMotionPolicy.currentMode(reduceMotion: false), .standard)
        XCTAssertNotNil(SidebarMotionPolicy.dockedLayoutAnimation(for: .standard, isShowing: true))
        XCTAssertTrue(SidebarMotionPolicy.overlayUsesTravel(for: .standard))
    }

    func testSidebarMotionPolicyUsesReducedMotionWhenEnergySaverRequestsIt() {
        XCTAssertEqual(
            SidebarMotionPolicy.currentMode(
                reduceMotion: false,
                energySaverReducesMotion: true
            ),
            .reducedMotion
        )
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

    func testFolderSearchPopoverKeepsFolderSearchHoverTrackingAllowed() {
        let state = SidebarInteractionState()
        let tokenID = UUID()

        state.beginSession(kind: .folderSearchPopover, tokenID: tokenID)

        XCTAssertFalse(state.freezesSidebarHoverState)
        XCTAssertTrue(state.allowsFolderSearchHoverTracking)
    }

    func testOtherTransientUIBlocksFolderSearchHoverTracking() {
        let state = SidebarInteractionState()

        state.beginSession(kind: .folderSearchPopover, tokenID: UUID())
        state.beginSession(kind: .folderEditorPopover, tokenID: UUID())

        XCTAssertTrue(state.freezesSidebarHoverState)
        XCTAssertFalse(state.allowsFolderSearchHoverTracking)
    }

    func testStartingOtherTransientDismissesFolderSearchPopover() {
        let state = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: state
        )
        let source = SidebarTransientPresentationSource(
            windowID: coordinator.windowID,
            window: nil,
            originOwnerView: nil,
            coordinator: coordinator
        )
        var didDismissFolderSearch = false

        _ = coordinator.beginSession(
            kind: .folderSearchPopover,
            source: source,
            path: "test.folderSearch",
            conflictDismiss: {
                didDismissFolderSearch = true
            }
        )
        _ = coordinator.beginSession(
            kind: .dialog,
            source: source,
            path: "test.dialog"
        )

        XCTAssertTrue(didDismissFolderSearch)
    }

    func testSidebarInteractiveItemUsesInjectedDragStateForArmedGeometry() {
        let injectedDragState = SidebarDragState()
        let sharedDragState = SidebarDragState.shared
        let itemId = UUID()
        let spaceId = UUID()
        let item = SumiDragItem(
            tabId: itemId,
            title: "Injected drag state"
        )
        let scope = SidebarDragScope(
            windowId: UUID(),
            spaceId: spaceId,
            profileId: nil,
            sourceContainer: .spaceRegular(spaceId),
            sourceItemId: itemId,
            sourceItemKind: .tab
        )
        let view = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 160, height: 36))

        injectedDragState.resetInteractionState()
        sharedDragState.resetInteractionState()
        view.sidebarDragState = injectedDragState
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: item,
                    sourceZone: .spaceRegular(spaceId),
                    previewKind: .row
                ),
                dragScope: scope
            )
        )

        view.mouseDown(with: mouseEvent(.leftMouseDown))

        XCTAssertTrue(injectedDragState.isInternalDragGeometryArmed)
        XCTAssertFalse(sharedDragState.isInternalDragGeometryArmed)
        XCTAssertEqual(injectedDragState.armedDragScope, scope)
        XCTAssertNil(sharedDragState.armedDragScope)
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

    func testPrimaryActionWithMiddleClickUsesAppKitOwnerInDockedSidebar() {
        let context = SidebarPresentationContext.docked(sidebarWidth: 280)

        XCTAssertTrue(SidebarPrimaryActionInputRouting.usesAppKitOwner(in: context, hasMiddleClick: true))
    }

    func testMiddleClickOwnerCapturesOnlyMiddleMouseButton() {
        let point = NSPoint(x: 12, y: 12)
        let view = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 160, height: 36))
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                onMiddleClick: { /* no-op */ }
            )
        )

        XCTAssertTrue(view.shouldCaptureInteraction(
            at: point,
            eventType: .otherMouseDown,
            eventButtonNumber: 2
        ))
        XCTAssertTrue(view.shouldCaptureInteraction(
            at: point,
            eventType: .otherMouseUp,
            eventButtonNumber: 2
        ))
        XCTAssertFalse(view.shouldCaptureInteraction(
            at: point,
            eventType: .otherMouseDown,
            eventButtonNumber: 3
        ))
        XCTAssertFalse(view.shouldCaptureInteraction(
            at: point,
            eventType: .otherMouseDown,
            eventButtonNumber: 4
        ))
        XCTAssertGreaterThan(view.routingPriority(
            at: point,
            eventType: .otherMouseDown,
            eventButtonNumber: 2
        ), 0)
        XCTAssertEqual(view.routingPriority(
            at: point,
            eventType: .otherMouseDown,
            eventButtonNumber: 3
        ), 0)
    }

    func testMiniPlayerCardSurfaceFocusesSourceAndBlocksOverlappingSidebarRowOwner() {
        let state = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: state
        )
        let controller = SidebarContextMenuController(
            interactionState: state,
            transientSessionCoordinator: coordinator
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 160))
        let rowHostView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 60))
        var focusCount = 0
        var rowActivationCount = 0
        var playPauseCount = 0
        let miniPlayerCardOwner = makeInteractiveItemView(
            sourceID: "sidebar-mini-player-card-test",
            state: state,
            routingPriorityBoost: 40
        ) {
            focusCount += 1
        }
        let rowOwner = makeInteractiveItemView(
            sourceID: "space-new-tab-test",
            state: state
        ) {
            rowActivationCount += 1
        }
        let playPauseOwner = makeInteractiveItemView(
            sourceID: "sidebar-mini-player-play-pause-test",
            state: state,
            routingPriorityBoost: 50
        ) {
            playPauseCount += 1
        }
        let cardPoint = NSPoint(x: 20, y: 20)
        let playPausePoint = NSPoint(x: 112, y: 20)

        miniPlayerCardOwner.frame = NSRect(x: 0, y: 0, width: 200, height: 60)
        rowOwner.frame = rowHostView.bounds
        playPauseOwner.frame = NSRect(x: 100, y: 7, width: 26, height: 26)
        window.contentView = containerView
        containerView.addSubview(miniPlayerCardOwner)
        containerView.addSubview(rowHostView)
        rowHostView.addSubview(rowOwner)
        miniPlayerCardOwner.addSubview(playPauseOwner)
        miniPlayerCardOwner.contextMenuController = controller
        rowOwner.contextMenuController = controller
        playPauseOwner.contextMenuController = controller
        defer {
            miniPlayerCardOwner.prepareForDismantle()
            rowOwner.prepareForDismantle()
            playPauseOwner.prepareForDismantle()
            window.contentView = nil
            window.close()
        }

        let routedCardClick = SidebarColumnHitTestRouting.routedHit(
            point: cardPoint,
            in: containerView,
            originalHit: rowOwner,
            hostedSidebarView: containerView,
            contextMenuController: controller,
            eventType: .leftMouseDown
        )
        let routedPlayPauseClick = SidebarColumnHitTestRouting.routedHit(
            point: playPausePoint,
            in: containerView,
            originalHit: miniPlayerCardOwner,
            hostedSidebarView: containerView,
            contextMenuController: controller,
            eventType: .leftMouseDown
        )

        XCTAssertTrue(routedCardClick === miniPlayerCardOwner)
        XCTAssertTrue(routedPlayPauseClick === playPauseOwner)

        miniPlayerCardOwner.mouseDown(with: mouseEvent(.leftMouseDown, location: cardPoint))
        miniPlayerCardOwner.mouseUp(with: mouseEvent(.leftMouseUp, location: cardPoint))
        playPauseOwner.mouseDown(with: mouseEvent(.leftMouseDown, location: playPausePoint))
        playPauseOwner.mouseUp(with: mouseEvent(.leftMouseUp, location: playPausePoint))

        XCTAssertEqual(focusCount, 1)
        XCTAssertEqual(rowActivationCount, 0)
        XCTAssertEqual(playPauseCount, 1)
    }

    func testSidebarColumnLeavesSideButtonsForWorkspaceCaptureSurface() {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 160))
        let captureView = NSView(frame: containerView.bounds)
        containerView.addSubview(captureView)

        let backHit = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 12, y: 12),
            in: containerView,
            originalHit: captureView,
            hostedSidebarView: containerView,
            contextMenuController: nil,
            eventType: .otherMouseDown,
            eventButtonNumber: 3
        )
        let forwardHit = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 12, y: 12),
            in: containerView,
            originalHit: captureView,
            hostedSidebarView: containerView,
            contextMenuController: nil,
            eventType: .otherMouseDown,
            eventButtonNumber: 4
        )

        XCTAssertTrue(backHit === captureView)
        XCTAssertTrue(forwardHit === captureView)
    }

    private func makeInteractiveItemView(
        sourceID: String,
        state: SidebarInteractionState,
        routingPriorityBoost: Int = 0,
        action: @escaping () -> Void = { /* no-op */ }
    ) -> SidebarInteractiveItemView {
        let view = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 160, height: 36))
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                primaryAction: action,
                sourceID: sourceID,
                routingPriorityBoost: routingPriorityBoost
            )
        )
        return view
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        location: NSPoint = NSPoint(x: 12, y: 12)
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: location,
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
