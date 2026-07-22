import AppKit
@testable import Sumi
import XCTest

@MainActor
final class SidebarZenMotionTests: XCTestCase {
    func testSidebarMotionPolicyUsesReducedMotionContract() {
        XCTAssertEqual(SidebarMotionPolicy.currentMode(reduceMotion: true), .reducedMotion)
        XCTAssertNil(SidebarMotionPolicy.dockedLayoutAnimation(for: .reducedMotion, isShowing: true))
        XCTAssertFalse(SidebarMotionPolicy.overlayUsesTravel(for: .reducedMotion))
        XCTAssertEqual(SidebarMotionPolicy.overlayAnimationDuration(for: .reducedMotion), 0.08)
    }

    func testSidebarMotionPolicyKeepsStandardShellMotion() {
        XCTAssertEqual(SidebarMotionPolicy.currentMode(reduceMotion: false), .standard)
        XCTAssertNotNil(SidebarMotionPolicy.dockedLayoutAnimation(for: .standard, isShowing: true))
        XCTAssertTrue(SidebarMotionPolicy.overlayUsesTravel(for: .standard))
        XCTAssertEqual(SidebarMotionPolicy.overlayAnimationDuration(for: .standard), 0.22)
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

    /// Opening or closing the folder preview writes the transient interaction
    /// state, which re-renders every folder header mid-click. That re-render
    /// reaches the bridge with an unchanged signature, and must leave the row's
    /// in-flight gesture alone — otherwise the click never reaches its action.
    func testBridgeUpdateDuringPressKeepsPrimaryActionAlive() {
        let state = SidebarInteractionState()
        var activationCount = 0
        let action = { activationCount += 1 }
        let view = makeInteractiveItemView(
            sourceID: "folder-header-test",
            state: state,
            action: action
        )

        view.mouseDown(with: mouseEvent(.leftMouseDown))
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                primaryAction: action,
                sourceID: "folder-header-test"
            )
        )
        view.mouseUp(with: mouseEvent(.leftMouseUp))

        XCTAssertEqual(activationCount, 1)
        XCTAssertNil(state.activePressedSourceID)
    }

    func testBridgeReuseForDifferentSourceCancelsInFlightPrimaryAction() {
        let state = SidebarInteractionState()
        var firstActivationCount = 0
        var secondActivationCount = 0
        let view = makeInteractiveItemView(
            sourceID: "folder-header-first",
            state: state
        ) {
            firstActivationCount += 1
        }

        view.mouseDown(with: mouseEvent(.leftMouseDown))
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                primaryAction: { secondActivationCount += 1 },
                sourceID: "folder-header-second"
            )
        )

        XCTAssertNil(state.activePressedSourceID)

        view.mouseUp(with: mouseEvent(.leftMouseUp))

        XCTAssertEqual(firstActivationCount, 0)
        XCTAssertEqual(secondActivationCount, 0)
    }

    func testNewPointerSessionCancelsPreviousFoldersInFlightAction() {
        let state = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: state
        )
        let controller = SidebarContextMenuController(
            interactionState: state,
            transientSessionCoordinator: coordinator
        )
        var folderToggleCount = 0
        let folderView = makeInteractiveItemView(
            sourceID: "folder-header-test",
            state: state
        ) {
            folderToggleCount += 1
        }
        let childView = makeInteractiveItemView(
            sourceID: "folder-child-test",
            state: state
        )
        folderView.contextMenuController = controller
        childView.contextMenuController = controller

        folderView.mouseDown(with: mouseEvent(.leftMouseDown))
        childView.mouseDown(with: mouseEvent(.leftMouseDown))
        folderView.mouseUp(with: mouseEvent(.leftMouseUp))

        XCTAssertEqual(folderToggleCount, 0)
        XCTAssertEqual(state.activePressedSourceID, "folder-child-test")
    }

    func testBridgeUpdateWithoutLocalGestureDoesNotCancelAnotherRowsArmedDrag() {
        let dragState = SidebarDragState()
        dragState.armInternalDragGeometry(scope: nil)
        let view = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 160, height: 36)
        )
        view.sidebarDragState = dragState

        view.update(
            configuration: SidebarAppKitItemConfiguration(
                primaryAction: { /* no-op */ },
                sourceID: "folder-header-test"
            )
        )
        view.cancelPrimaryMouseTracking()

        XCTAssertTrue(dragState.isInternalDragGeometryArmed)
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

    func testFolderPreviewKeepsFolderPreviewHoverTrackingAllowed() {
        let state = SidebarInteractionState()
        let tokenID = UUID()

        state.beginSession(kind: .folderPreview, tokenID: tokenID)

        XCTAssertFalse(state.freezesSidebarHoverState)
        XCTAssertTrue(state.allowsFolderPreviewHoverTracking)
        XCTAssertTrue(state.allowsSidebarDragSourceHitTesting)
    }

    func testOtherTransientUIBlocksFolderPreviewHoverTracking() {
        let state = SidebarInteractionState()

        state.beginSession(kind: .folderPreview, tokenID: UUID())
        state.beginSession(kind: .folderEditorPopover, tokenID: UUID())

        XCTAssertTrue(state.freezesSidebarHoverState)
        XCTAssertFalse(state.allowsFolderPreviewHoverTracking)
    }

    func testVisualItemDragSynchronizesHoverSuppressionWithoutDeferredWork() {
        let state = SidebarInteractionState()
        let dragState = SidebarDragState(interactionState: state)

        dragState.beginExternalDragSession(itemId: UUID())

        XCTAssertTrue(state.freezesSidebarHoverState)
        XCTAssertFalse(state.allowsFolderPreviewHoverTracking)

        dragState.resetInteractionState()

        XCTAssertFalse(state.freezesSidebarHoverState)
        XCTAssertTrue(state.allowsFolderPreviewHoverTracking)
    }

    func testIndependentDragSourcesCannotClearEachOthersHoverSuppression() {
        let state = SidebarInteractionState()
        let dragState = SidebarDragState(interactionState: state)

        state.setDragActive(true, source: .spaceReorder)
        dragState.beginExternalDragSession(itemId: UUID())
        dragState.resetInteractionState()

        XCTAssertTrue(state.freezesSidebarHoverState)

        state.setDragActive(false, source: .spaceReorder)

        XCTAssertFalse(state.freezesSidebarHoverState)
    }

    func testRecoveryForOldSourceDoesNotCancelNewPointerSession() {
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
        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        let oldSource = makeInteractiveItemView(
            sourceID: "folder-header-old",
            state: state
        )
        let newSource = makeInteractiveItemView(
            sourceID: "folder-child-current",
            state: state
        )
        window.contentView = container
        container.addSubview(oldSource)
        container.addSubview(newSource)
        oldSource.contextMenuController = controller
        newSource.contextMenuController = controller
        let source = SidebarTransientPresentationSource(
            windowID: coordinator.windowID,
            window: window,
            originOwnerView: oldSource,
            coordinator: coordinator
        )
        defer {
            oldSource.prepareForDismantle()
            newSource.prepareForDismantle()
            window.contentView = nil
            window.close()
        }

        newSource.mouseDown(with: mouseEvent(.leftMouseDown))
        let result = controller.recoverInteractiveOwners(
            in: window,
            source: source
        )

        XCTAssertTrue(result.sourceOwnerResolved)
        XCTAssertEqual(state.activePressedSourceID, "folder-child-current")
    }

    func testStartingOtherTransientDismissesFolderPreview() {
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
        var didDismissFolderPreview = false

        _ = coordinator.beginSession(
            kind: .folderPreview,
            source: source,
            path: "test.folderPreview",
            conflictDismiss: {
                didDismissFolderPreview = true
            }
        )
        _ = coordinator.beginSession(
            kind: .dialog,
            source: source,
            path: "test.dialog"
        )

        XCTAssertTrue(didDismissFolderPreview)
    }

    /// The repair pass cancels primary mouse tracking on every sidebar row, so
    /// it drops any click that is mid-gesture. Only chrome that nests an event
    /// loop or owns a window may ask for it.
    func testOnlyEventLoopOwningChromeRequiresInputRecovery() {
        XCTAssertFalse(SidebarTransientUIKind.folderPreview.requiresInputRecoveryOnEnd)

        for kind in SidebarTransientUIKind.allCases where kind != .folderPreview {
            XCTAssertTrue(
                kind.requiresInputRecoveryOnEnd,
                "\(kind.rawValue) should still repair sidebar input on end"
            )
        }
    }

    func testEndingFolderPreviewDoesNotRecoverInteractiveOwners() {
        let coordinator = makeRecoveryObservingCoordinator()
        var recoveryCount = 0
        coordinator.recoverSidebarInteractiveOwners = { _, _ in
            recoveryCount += 1
            return .none
        }
        let source = SidebarTransientPresentationSource(
            windowID: coordinator.windowID,
            window: nil,
            originOwnerView: nil,
            coordinator: coordinator
        )

        let token = coordinator.beginSession(
            kind: .folderPreview,
            source: source,
            path: "test.folderPreview"
        )
        coordinator.endSession(token)
        drainMainQueue()

        XCTAssertEqual(recoveryCount, 0)
    }

    /// An open preview pins the collapsed sidebar, but it must not defer another
    /// session's repair — deferred repairs flush together later, onto whatever
    /// click is in flight by then.
    func testOpenFolderPreviewDoesNotDeferAnotherSessionsRecovery() {
        let coordinator = makeRecoveryObservingCoordinator()
        var recoveryCount = 0
        coordinator.recoverSidebarInteractiveOwners = { _, _ in
            recoveryCount += 1
            return .none
        }
        let source = SidebarTransientPresentationSource(
            windowID: coordinator.windowID,
            window: nil,
            originOwnerView: nil,
            coordinator: coordinator
        )

        _ = coordinator.beginSession(
            kind: .folderPreview,
            source: source,
            path: "test.folderPreview"
        )
        let menuToken = coordinator.beginSession(
            kind: .contextMenu,
            source: source,
            path: "test.contextMenu"
        )
        coordinator.endSession(menuToken)
        drainMainQueue()

        XCTAssertEqual(recoveryCount, 1)
    }

    private func makeRecoveryObservingCoordinator() -> SidebarTransientSessionCoordinator {
        SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: SidebarInteractionState()
        )
    }

    /// Recovery is scheduled across nested main-queue hops.
    private func drainMainQueue(turns: Int = 4) {
        for _ in 0..<turns {
            let expectation = expectation(description: "main queue turn")
            DispatchQueue.main.async { expectation.fulfill() }
            wait(for: [expectation], timeout: 1)
        }
    }

    func testSidebarInteractiveItemUsesInjectedDragStateForArmedGeometry() {
        let injectedDragState = SidebarDragState()
        let otherDragState = SidebarDragState()
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
        otherDragState.resetInteractionState()
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
        XCTAssertFalse(otherDragState.isInternalDragGeometryArmed)
        XCTAssertEqual(injectedDragState.armedDragScope, scope)
        XCTAssertNil(otherDragState.armedDragScope)

        view.cancelPrimaryMouseTracking()

        XCTAssertFalse(injectedDragState.isInternalDragGeometryArmed)
        XCTAssertNil(injectedDragState.armedDragScope)
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
