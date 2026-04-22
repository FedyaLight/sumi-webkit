import AppKit
import SwiftUI
import XCTest

@testable import Sumi

@MainActor
private func makeSidebarContextMenuController(
    interactionState: SidebarInteractionState
) -> SidebarContextMenuController {
    SidebarContextMenuController(
        interactionState: interactionState,
        transientSessionCoordinator: SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
    )
}

private extension SidebarInteractionState {
    @discardableResult
    func beginContextMenuSessionForTesting() -> UUID {
        let tokenID = UUID()
        beginSession(kind: .contextMenu, tokenID: tokenID)
        return tokenID
    }

    func endContextMenuSessionForTesting(_ tokenID: UUID) {
        endSession(kind: .contextMenu, tokenID: tokenID)
    }
}

@MainActor
final class SidebarColumnViewControllerTests: XCTestCase {
    func testSidebarColumnViewControllerHostsUpdatesAndTeardown() {
        let vc = SidebarColumnViewController()
        vc.loadView()

        let first = AnyView(Color.clear.frame(width: 10, height: 10))
        vc.updateHostedSidebar(root: first, width: 240)
        XCTAssertFalse(vc.view.subviews.isEmpty)

        let second = AnyView(Color.clear.frame(width: 20, height: 20))
        vc.updateHostedSidebar(root: second, width: 300)

        vc.teardownSidebarHosting()
        XCTAssertTrue(vc.view.subviews.isEmpty)
    }

    func testSidebarHostRecoveryCoordinatorTracksAnchorsPerWindow() {
        let coordinator = SidebarHostRecoveryCoordinator()
        let firstWindow = makeWindow()
        let secondWindow = makeWindow()
        let firstAnchor = NSView(frame: .zero)
        let secondAnchor = NSView(frame: .zero)
        let thirdAnchor = NSView(frame: .zero)

        coordinator.sync(anchor: firstAnchor, window: firstWindow)
        coordinator.sync(anchor: secondAnchor, window: firstWindow)
        coordinator.sync(anchor: thirdAnchor, window: secondWindow)

        XCTAssertEqual(anchorIDs(in: firstWindow, coordinator: coordinator), Set([
            ObjectIdentifier(firstAnchor),
            ObjectIdentifier(secondAnchor),
        ]))
        XCTAssertEqual(anchorIDs(in: secondWindow, coordinator: coordinator), Set([
            ObjectIdentifier(thirdAnchor),
        ]))

        coordinator.sync(anchor: firstAnchor, window: secondWindow)
        XCTAssertEqual(anchorIDs(in: firstWindow, coordinator: coordinator), Set([
            ObjectIdentifier(secondAnchor),
        ]))
        XCTAssertEqual(anchorIDs(in: secondWindow, coordinator: coordinator), Set([
            ObjectIdentifier(firstAnchor),
            ObjectIdentifier(thirdAnchor),
        ]))

        coordinator.unregister(anchor: secondAnchor)
        XCTAssertTrue(coordinator.registeredAnchors(in: firstWindow).isEmpty)
    }

    func testSidebarHostRecoveryCoordinatorRecoversAllAnchorsInTargetWindowOnly() async {
        var invalidatedAnchorIDs: [ObjectIdentifier] = []
        let coordinator = SidebarHostRecoveryCoordinator { anchor in
            guard let anchor else { return }
            invalidatedAnchorIDs.append(ObjectIdentifier(anchor))
        }
        let firstWindow = makeWindow()
        let secondWindow = makeWindow()
        let firstAnchor = NSView(frame: .zero)
        let secondAnchor = NSView(frame: .zero)
        let otherWindowAnchor = NSView(frame: .zero)

        coordinator.sync(anchor: firstAnchor, window: firstWindow)
        coordinator.sync(anchor: secondAnchor, window: firstWindow)
        coordinator.sync(anchor: otherWindowAnchor, window: secondWindow)

        coordinator.recover(in: firstWindow)
        let secondPassCompleted = expectation(description: "sidebar recovery second pass")
        DispatchQueue.main.async {
            secondPassCompleted.fulfill()
        }
        await fulfillment(of: [secondPassCompleted], timeout: 1.0)

        XCTAssertEqual(invalidatedAnchorIDs.count, 4)
        XCTAssertEqual(invalidatedAnchorIDs.filter { $0 == ObjectIdentifier(firstAnchor) }.count, 2)
        XCTAssertEqual(invalidatedAnchorIDs.filter { $0 == ObjectIdentifier(secondAnchor) }.count, 2)
        XCTAssertFalse(invalidatedAnchorIDs.contains(ObjectIdentifier(otherWindowAnchor)))
    }

    func testSidebarColumnViewControllerRegistersHostedSidebarWithRecoveryCoordinator() {
        let spy = SidebarHostRecoverySpy()
        let vc = SidebarColumnViewController()
        vc.sidebarRecoveryCoordinator = spy
        vc.loadView()

        let window = makeWindow()
        window.contentView?.addSubview(vc.view)

        vc.updateHostedSidebar(root: AnyView(Color.clear.frame(width: 10, height: 10)), width: 240)

        XCTAssertEqual(spy.syncedWindows.count, 1)
        XCTAssertTrue(spy.syncedWindows.first === window)
        XCTAssertTrue(spy.syncedAnchors.first === vc.view.subviews.first)

        vc.teardownSidebarHosting()
        XCTAssertTrue(spy.unregisteredAnchors.first === spy.syncedAnchors.first)
    }

    func testDialogManagerCloseRequestsWindowScopedSidebarRecovery() {
        let spy = SidebarHostRecoverySpy()
        let manager = DialogManager()
        manager.sidebarRecoveryCoordinator = spy

        let window = makeWindow()
        manager.showDialog(EmptyView(), in: window)
        manager.closeDialog()

        XCTAssertFalse(manager.isVisible)
        XCTAssertNil(manager.activeDialog)
        XCTAssertEqual(spy.recoveredWindows.count, 1)
        XCTAssertTrue(spy.recoveredWindows.first === window)
        XCTAssertTrue(spy.recoveredAnchors.isEmpty)
    }

    func testDialogManagerPresentationIsBoundToCapturedWindow() {
        let manager = DialogManager()
        let firstWindow = makeWindow()
        let secondWindow = makeWindow()

        manager.showDialog(EmptyView(), in: firstWindow)

        XCTAssertTrue(manager.isPresented(in: firstWindow))
        XCTAssertFalse(manager.isPresented(in: secondWindow))
    }

    func testWorkspaceThemePickerDismissRecoveryUsesWindowAndOverlayAnchor() {
        let spy = SidebarHostRecoverySpy()
        let window = makeWindow()
        let anchor = NSView(frame: .zero)

        WorkspaceThemePickerOverlay.performDismissRecovery(
            in: window,
            anchor: anchor,
            using: spy
        )

        XCTAssertEqual(spy.recoveredWindows.count, 1)
        XCTAssertTrue(spy.recoveredWindows.first === window)
        XCTAssertEqual(spy.recoveredAnchors.count, 1)
        XCTAssertTrue(spy.recoveredAnchors.first === anchor)
        XCTAssertEqual(spy.recoveryOrder, ["window", "anchor"])
    }

    func testWorkspaceThemePickerDismissRecoveryIsRepeatableAcrossSessions() {
        let spy = SidebarHostRecoverySpy()
        let window = makeWindow()
        let anchor = NSView(frame: .zero)

        WorkspaceThemePickerOverlay.performDismissRecovery(
            in: window,
            anchor: anchor,
            using: spy
        )
        WorkspaceThemePickerOverlay.performDismissRecovery(
            in: window,
            anchor: anchor,
            using: spy
        )

        XCTAssertEqual(spy.recoveredWindows.count, 2)
        XCTAssertEqual(spy.recoveredAnchors.count, 2)
        XCTAssertEqual(spy.recoveryOrder, ["window", "anchor", "window", "anchor"])
    }

    func testMouseEventShieldDisarmStopsHitTestingAndCallbacks() {
        let shield = MouseEventShieldNSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        var clickCount = 0

        shield.update(onClick: { clickCount += 1 }, isInteractive: true)
        XCTAssertTrue(shield.hitTest(NSPoint(x: 5, y: 5)) === shield)

        shield.mouseDown(with: makeMouseEvent(type: .leftMouseDown))
        XCTAssertEqual(clickCount, 1)

        shield.setTransientInteractionEnabled(false)
        XCTAssertNil(shield.hitTest(NSPoint(x: 5, y: 5)))

        shield.mouseDown(with: makeMouseEvent(type: .leftMouseDown))
        XCTAssertEqual(clickCount, 1)
    }

    func testMouseEventShieldDismantleDisarmsView() {
        let shield = MouseEventShieldNSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        shield.update(onClick: {}, isInteractive: true)

        MouseEventShieldView.dismantleNSView(shield, coordinator: ())

        XCTAssertNil(shield.hitTest(NSPoint(x: 5, y: 5)))
    }

    func testBlockingInteractionSurfaceDisarmStopsHitTestingAndBackgroundCallbacks() {
        let surface = BlockingInteractionSurfaceContainer(
            rootView: AnyView(Color.clear.frame(width: 40, height: 40)),
            onBackgroundClick: nil,
            isInteractive: true
        )
        surface.frame = NSRect(x: 0, y: 0, width: 40, height: 40)

        var clickCount = 0
        surface.update(
            rootView: AnyView(Color.clear.frame(width: 40, height: 40)),
            onBackgroundClick: { clickCount += 1 },
            isInteractive: true
        )
        XCTAssertTrue(surface.hitTest(NSPoint(x: 5, y: 5)) === surface)

        surface.mouseDown(with: makeMouseEvent(type: .leftMouseDown))
        XCTAssertEqual(clickCount, 1)

        surface.setTransientInteractionEnabled(false)
        XCTAssertNil(surface.hitTest(NSPoint(x: 5, y: 5)))

        surface.mouseDown(with: makeMouseEvent(type: .leftMouseDown))
        XCTAssertEqual(clickCount, 1)
    }

    func testBlockingInteractionSurfaceDismantleDisarmsView() {
        let surface = BlockingInteractionSurfaceContainer(
            rootView: AnyView(Color.clear.frame(width: 40, height: 40)),
            onBackgroundClick: { },
            isInteractive: true
        )
        surface.frame = NSRect(x: 0, y: 0, width: 40, height: 40)

        BlockingInteractionSurface<AnyView>.dismantleNSView(surface, coordinator: ())

        XCTAssertNil(surface.hitTest(NSPoint(x: 5, y: 5)))
    }

    func testSidebarDragSourceDisarmStopsHitTestingAndResetsPartialMouseState() {
        let dragView = SidebarDragSourceView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        dragView.update(
            configuration: SidebarDragSourceConfiguration(
                item: SumiDragItem(tabId: UUID(), title: "Drag"),
                sourceZone: .spaceRegular(UUID()),
                previewKind: .row
            )
        )

        XCTAssertTrue(
            dragView.shouldCaptureInteraction(
                at: NSPoint(x: 5, y: 5),
                eventType: .leftMouseDown
            )
        )

        dragView.mouseDown(
            with: makeMouseEvent(
                type: .leftMouseDown,
                location: NSPoint(x: 5, y: 5)
            )
        )
        dragView.setTransientInteractionEnabled(false)

        XCTAssertFalse(
            dragView.shouldCaptureInteraction(
                at: NSPoint(x: 5, y: 5),
                eventType: .leftMouseDown
            )
        )

        dragView.setTransientInteractionEnabled(true)
        dragView.mouseDragged(
            with: makeMouseEvent(
                type: .leftMouseDragged,
                location: NSPoint(x: 24, y: 24)
            )
        )

        XCTAssertFalse(SidebarDragState.shared.isDragging)
    }

    func testSidebarDragSourceDismantleDisarmsView() {
        let dragView = SidebarDragSourceView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        dragView.update(
            configuration: SidebarDragSourceConfiguration(
                item: SumiDragItem(tabId: UUID(), title: "Drag"),
                sourceZone: .spaceRegular(UUID()),
                previewKind: .row
            )
        )

        SidebarDragSourceBridge.dismantleNSView(
            dragView,
            coordinator: SidebarDragSourceBridge.Coordinator(
                configuration: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row
                )
            )
        )

        XCTAssertFalse(
            dragView.shouldCaptureInteraction(
                at: NSPoint(x: 5, y: 5),
                eventType: .leftMouseDown
            )
        )
    }

    func testSidebarColumnRoutingPrefersRegisteredOwnerForRightClickWhenOriginalHitIsHostedView() {
        let controller = makeSidebarContextMenuController(interactionState: SidebarInteractionState())
        let (window, container, hostedView, owner) = makeRegisteredSidebarOwner(controller: controller)
        _ = window
        owner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                menu: SidebarContextMenuLeafConfiguration(
                    isEnabled: true,
                    surfaceKind: .row,
                    triggers: .rightClick,
                    entries: { [.action(.init(title: "Open", onAction: {}))] },
                    onMenuVisibilityChanged: { _ in }
                )
            )
        )

        let routed = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 30, y: 30),
            in: container,
            originalHit: hostedView,
            hostedSidebarView: hostedView,
            contextMenuController: controller,
            eventType: .rightMouseDown
        )

        XCTAssertTrue(routed === owner)
    }

    func testSidebarColumnRoutingLeftClickInvokesRegisteredOwnerPrimaryAction() {
        let controller = makeSidebarContextMenuController(interactionState: SidebarInteractionState())
        let (window, container, hostedView, owner) = makeRegisteredSidebarOwner(controller: controller)
        var primaryActivations = 0
        owner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                primaryAction: { primaryActivations += 1 }
            )
        )

        let routed = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 30, y: 30),
            in: container,
            originalHit: hostedView,
            hostedSidebarView: hostedView,
            contextMenuController: controller,
            eventType: .leftMouseDown
        )

        XCTAssertTrue(routed === owner)
        owner.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 30, y: 30)))
        owner.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: NSPoint(x: 30, y: 30)))
        XCTAssertEqual(primaryActivations, 1)
        _ = window
    }

    func testSidebarColumnRoutingSendsMouseUpToActivePrimaryTrackingOwner() {
        let controller = makeSidebarContextMenuController(interactionState: SidebarInteractionState())
        let (window, container, hostedView, owner) = makeRegisteredSidebarOwner(controller: controller)
        var primaryActivations = 0
        owner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                primaryAction: { primaryActivations += 1 }
            )
        )

        let down = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 30, y: 30),
            in: container,
            originalHit: hostedView,
            hostedSidebarView: hostedView,
            contextMenuController: controller,
            eventType: .leftMouseDown
        )

        XCTAssertTrue(down === owner)
        owner.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 30, y: 30)))

        let up = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 30, y: 30),
            in: container,
            originalHit: hostedView,
            hostedSidebarView: hostedView,
            contextMenuController: controller,
            eventType: .leftMouseUp
        )

        XCTAssertTrue(up === owner)
        owner.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: NSPoint(x: 30, y: 30)))
        XCTAssertEqual(primaryActivations, 1)
        XCTAssertNil(controller.primaryMouseTrackingOwner(in: window))
    }

    func testSidebarColumnRoutingPrimaryOnlyOwnerRightClickFallsBackToBackgroundMenu() {
        let controller = makeSidebarContextMenuController(interactionState: SidebarInteractionState())
        let (window, container, hostedView, owner) = makeRegisteredSidebarOwner(controller: controller)
        owner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(primaryAction: {})
        )

        let routed = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 30, y: 30),
            in: container,
            originalHit: owner,
            hostedSidebarView: hostedView,
            contextMenuController: controller,
            eventType: .rightMouseDown
        )

        XCTAssertTrue(routed === container)
        _ = window
    }

    func testSidebarColumnRoutingPrefersNestedActionOwnerForLeftClickAndParentForRightClick() {
        let controller = makeSidebarContextMenuController(interactionState: SidebarInteractionState())
        let (window, container, hostedView, rowOwner) = makeRegisteredSidebarOwner(controller: controller)
        rowOwner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                menu: SidebarContextMenuLeafConfiguration(
                    isEnabled: true,
                    surfaceKind: .row,
                    triggers: .rightClick,
                    entries: { [.action(.init(title: "Open", onAction: {}))] },
                    onMenuVisibilityChanged: { _ in }
                ),
                primaryAction: {}
            )
        )

        let actionOwner = SidebarInteractiveItemView(frame: NSRect(x: 52, y: 6, width: 24, height: 24))
        rowOwner.addSubview(actionOwner)
        actionOwner.contextMenuController = controller
        actionOwner.update(
            rootView: AnyView(Color.clear.frame(width: 24, height: 24)),
            configuration: SidebarAppKitItemConfiguration(primaryAction: {})
        )

        let left = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 76, y: 38),
            in: container,
            originalHit: hostedView,
            hostedSidebarView: hostedView,
            contextMenuController: controller,
            eventType: .leftMouseDown
        )
        let right = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 76, y: 38),
            in: container,
            originalHit: hostedView,
            hostedSidebarView: hostedView,
            contextMenuController: controller,
            eventType: .rightMouseDown
        )

        XCTAssertTrue(left === actionOwner)
        XCTAssertTrue(right === rowOwner)
        _ = window
    }

    func testSidebarColumnRoutingPrefersOriginalHitOwnerOverLaterRegisteredMatch() {
        let controller = makeSidebarContextMenuController(interactionState: SidebarInteractionState())
        let (_, container, hostedView, visibleOwner) = makeRegisteredSidebarOwner(controller: controller)
        visibleOwner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(primaryAction: {})
        )

        let laterRegisteredOwner = SidebarInteractiveItemView(frame: visibleOwner.frame)
        hostedView.addSubview(laterRegisteredOwner)
        laterRegisteredOwner.contextMenuController = controller
        laterRegisteredOwner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(primaryAction: {})
        )

        let routed = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 30, y: 30),
            in: container,
            originalHit: visibleOwner,
            hostedSidebarView: hostedView,
            contextMenuController: controller,
            eventType: .leftMouseDown
        )

        XCTAssertTrue(routed === visibleOwner)
    }

    func testSidebarColumnRoutingRestrictsRegistryLookupToCurrentHostedSidebarView() {
        let controller = makeSidebarContextMenuController(interactionState: SidebarInteractionState())
        let window = makeWindow()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let currentHostedView = NSView(frame: container.bounds)
        let staleHostedView = NSView(frame: container.bounds)
        let currentOwner = SidebarInteractiveItemView(frame: NSRect(x: 20, y: 20, width: 80, height: 36))
        let staleOwner = SidebarInteractiveItemView(frame: currentOwner.frame)

        window.contentView?.addSubview(container)
        container.addSubview(staleHostedView)
        container.addSubview(currentHostedView)
        currentHostedView.addSubview(currentOwner)
        staleHostedView.addSubview(staleOwner)

        currentOwner.contextMenuController = controller
        currentOwner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(primaryAction: {})
        )

        staleOwner.contextMenuController = controller
        staleOwner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(primaryAction: {})
        )

        let windowPoint = container.convert(NSPoint(x: 30, y: 30), to: nil)
        XCTAssertTrue(
            controller.interactiveOwner(
                at: windowPoint,
                in: window,
                eventType: .leftMouseDown
            ) === staleOwner
        )
        XCTAssertTrue(
            controller.interactiveOwner(
                at: windowPoint,
                in: window,
                eventType: .leftMouseDown,
                hostedSidebarView: currentHostedView
            ) === currentOwner
        )

        let routed = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 30, y: 30),
            in: container,
            originalHit: currentHostedView,
            hostedSidebarView: currentHostedView,
            contextMenuController: controller,
            eventType: .leftMouseDown
        )

        XCTAssertTrue(routed === currentOwner)
    }

    func testSidebarColumnRoutingRestoresLiveDragOwnerOnlyAfterMenuEndTracking() {
        let interactionState = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: interactionState)
        let (window, container, hostedView, owner) = makeRegisteredSidebarOwner(controller: controller)
        let menu = NSMenu()

        owner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                menu: SidebarContextMenuLeafConfiguration(
                    isEnabled: true,
                    surfaceKind: .row,
                    triggers: .rightClick,
                    entries: { [.action(.init(title: "Open", onAction: {}))] },
                    onMenuVisibilityChanged: { _ in }
                ),
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )

        let sessionID = controller.beginMenuSessionForTesting(
            ownerView: owner,
            menu: menu
        )
        controller.markMenuOpenedForTesting(sessionID: sessionID)
        controller.markMenuClosedForTesting(sessionID: sessionID)

        XCTAssertTrue(interactionState.isContextMenuPresented)
        XCTAssertFalse(interactionState.allowsSidebarDragSourceHitTesting)

        let blockedDown = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 30, y: 30),
            in: container,
            originalHit: hostedView,
            hostedSidebarView: hostedView,
            contextMenuController: controller,
            eventType: .leftMouseDown
        )

        XCTAssertTrue(blockedDown === hostedView)

        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        drainMainRunLoop()

        XCTAssertEqual(interactionState.activeKindsDescription, "none")
        XCTAssertTrue(interactionState.allowsSidebarDragSourceHitTesting)

        let down = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 30, y: 30),
            in: container,
            originalHit: hostedView,
            hostedSidebarView: hostedView,
            contextMenuController: controller,
            eventType: .leftMouseDown
        )

        XCTAssertTrue(down === owner)
        owner.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 30, y: 30)))

        let drag = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 30, y: 30),
            in: container,
            originalHit: hostedView,
            hostedSidebarView: hostedView,
            contextMenuController: controller,
            eventType: .leftMouseDragged
        )

        XCTAssertTrue(drag === owner)
        owner.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: NSPoint(x: 30, y: 30)))
        XCTAssertNil(controller.primaryMouseTrackingOwner(in: window))
    }

    func testSidebarInteractiveOwnerRegistryRespectsPrimaryActionExclusionZones() {
        let controller = makeSidebarContextMenuController(interactionState: SidebarInteractionState())
        let (window, _, _, owner) = makeRegisteredSidebarOwner(controller: controller)
        owner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row,
                    exclusionZones: [.trailingStrip(20)],
                    isEnabled: false
                ),
                primaryAction: {}
            )
        )

        let excludedWindowPoint = owner.convert(NSPoint(x: 72, y: 12), to: nil)
        XCTAssertNil(
            controller.interactiveOwner(
                at: excludedWindowPoint,
                in: window,
                eventType: .leftMouseDown
            )
        )
    }

    func testSidebarInteractiveOwnerRegistryDoesNotRouteOwnersAcrossWindows() {
        let controller = makeSidebarContextMenuController(interactionState: SidebarInteractionState())
        let (_, _, _, owner) = makeRegisteredSidebarOwner(controller: controller)
        owner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(primaryAction: {})
        )
        let otherWindow = makeWindow()

        XCTAssertNil(
            controller.interactiveOwner(
                at: NSPoint(x: 30, y: 30),
                in: otherWindow,
                eventType: .leftMouseDown
            )
        )
    }

    func testSidebarHoverOverlayThemePinningPolicyPinsCollapsedSidebarOnlyForMatchingThemePickerWindow() {
        let windowID = UUID()

        XCTAssertTrue(
            SidebarHoverOverlayTransientPinningPolicy.shouldPinHoverSidebar(
                transientWindowID: windowID,
                currentWindowID: windowID,
                isSidebarVisible: false
            )
        )
        XCTAssertFalse(
            SidebarHoverOverlayTransientPinningPolicy.shouldPinHoverSidebar(
                transientWindowID: windowID,
                currentWindowID: windowID,
                isSidebarVisible: true
            )
        )
        XCTAssertFalse(
            SidebarHoverOverlayTransientPinningPolicy.shouldPinHoverSidebar(
                transientWindowID: nil,
                currentWindowID: windowID,
                isSidebarVisible: false
            )
        )
        XCTAssertFalse(
            SidebarHoverOverlayTransientPinningPolicy.shouldPinHoverSidebar(
                transientWindowID: UUID(),
                currentWindowID: windowID,
                isSidebarVisible: false
            )
        )
    }

    func testSidebarTransientSessionCoordinatorPreservesPendingSourceAcrossMenuToDialogHandoff() {
        let interactionState = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
        let window = makeWindow()
        let ownerView = NSView(frame: .zero)
        window.contentView?.addSubview(ownerView)

        coordinator.prepareMenuPresentationSource(ownerView: ownerView)
        let menuSource = coordinator.preparedPresentationSource(
            window: window,
            ownerView: ownerView
        )
        let menuToken = coordinator.beginSession(
            kind: .contextMenu,
            source: menuSource,
            path: "test.menu",
            preservePendingSource: true
        )

        XCTAssertTrue(interactionState.isContextMenuPresented)
        XCTAssertTrue(interactionState.isContextMenuPresented)

        coordinator.endSession(menuToken)

        XCTAssertFalse(interactionState.isContextMenuPresented)
        let dialogSource = coordinator.consumePresentationSource(window: nil)
        XCTAssertTrue(dialogSource === menuSource)
        XCTAssertTrue(dialogSource.originOwnerView === ownerView)

        let dialogToken = coordinator.beginSession(
            kind: .dialog,
            source: dialogSource,
            path: "test.dialog"
        )

        XCTAssertTrue(interactionState.suppressesSidebarAffordances)
        XCTAssertTrue(coordinator.hasPinnedTransientUI(for: coordinator.windowID))

        coordinator.endSession(dialogToken)

        XCTAssertFalse(interactionState.suppressesSidebarAffordances)
        XCTAssertFalse(coordinator.hasPinnedTransientUI(for: coordinator.windowID))
    }

    func testSidebarTransientSessionCoordinatorRecoveryTargetsSourceWindowAndOwnerOnly() {
        let interactionState = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
        let spy = SidebarHostRecoverySpy()
        var inputRecoveryReasons: [String] = []
        coordinator.sidebarRecoveryCoordinator = spy
        coordinator.scheduleSidebarInputRehydrate = { inputRecoveryReasons.append($0) }
        coordinator.recoverSidebarInteractiveOwners = { _, _ in
            SidebarInteractiveOwnerRecoveryResult(
                recoveredOwnerCount: 1,
                sourceOwnerResolved: true,
                resolvedOwnerDescription: "owner",
                resolutionReason: "test"
            )
        }

        let sourceWindow = makeWindow()
        let ownerView = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        ownerView.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )
        sourceWindow.contentView?.addSubview(ownerView)
        let otherWindow = makeWindow()

        let source = SidebarTransientPresentationSource(
            windowID: coordinator.windowID,
            window: sourceWindow,
            originOwnerView: ownerView,
            previousFirstResponder: otherWindow.contentView,
            wasKeyWindow: false,
            coordinator: coordinator
        )
        let token = coordinator.beginSession(
            kind: .dialog,
            source: source,
            path: "test.recovery"
        )

        coordinator.endSession(token)

        XCTAssertTrue(spy.recoveredWindows.isEmpty)
        XCTAssertTrue(spy.recoveredAnchors.isEmpty)

        drainMainRunLoop()

        XCTAssertEqual(spy.recoveredWindows.count, 2)
        XCTAssertTrue(spy.recoveredWindows.allSatisfy { $0 === sourceWindow })
        XCTAssertEqual(spy.recoveredAnchors.count, 2)
        XCTAssertTrue(spy.recoveredAnchors.allSatisfy { $0 === ownerView })
        XCTAssertTrue(inputRecoveryReasons.isEmpty)
    }

    func testSidebarTransientSessionCoordinatorDefersRecoveryUntilMenuActionDrains() {
        let interactionState = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
        let spy = SidebarHostRecoverySpy()
        var inputRecoveryReasons: [String] = []
        coordinator.sidebarRecoveryCoordinator = spy
        coordinator.scheduleSidebarInputRehydrate = { inputRecoveryReasons.append($0) }
        coordinator.recoverSidebarInteractiveOwners = { _, _ in
            SidebarInteractiveOwnerRecoveryResult(
                recoveredOwnerCount: 1,
                sourceOwnerResolved: true,
                resolvedOwnerDescription: "owner",
                resolutionReason: "test"
            )
        }

        let sourceWindow = makeWindow()
        let ownerView = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        ownerView.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )
        sourceWindow.contentView?.addSubview(ownerView)
        let source = SidebarTransientPresentationSource(
            windowID: coordinator.windowID,
            window: sourceWindow,
            originOwnerView: ownerView,
            coordinator: coordinator
        )
        let token = coordinator.beginSession(
            kind: .contextMenu,
            source: source,
            path: "test.menu"
        )

        coordinator.beginMenuActionDispatch(
            path: "test.action",
            classification: .stateMutationNonStructural
        )
        coordinator.endSession(token)
        drainMainRunLoop()

        XCTAssertTrue(spy.recoveredWindows.isEmpty)
        XCTAssertTrue(inputRecoveryReasons.isEmpty)

        coordinator.finishMenuActionDispatch(
            path: "test.action",
            classification: .stateMutationNonStructural
        )
        drainMainRunLoop()

        XCTAssertEqual(spy.recoveredWindows.count, 2)
        XCTAssertTrue(spy.recoveredWindows.allSatisfy { $0 === sourceWindow })
        XCTAssertEqual(spy.recoveredAnchors.count, 2)
        XCTAssertTrue(spy.recoveredAnchors.allSatisfy { $0 === ownerView })
        XCTAssertTrue(inputRecoveryReasons.isEmpty)
    }

    func testSidebarTransientSessionCoordinatorRecoversClosedContextMenuSessionWithoutHardRehydrate() {
        let interactionState = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
        let spy = SidebarHostRecoverySpy()
        var inputRecoveryReasons: [String] = []
        coordinator.sidebarRecoveryCoordinator = spy
        coordinator.scheduleSidebarInputRehydrate = { inputRecoveryReasons.append($0) }
        coordinator.recoverSidebarInteractiveOwners = { _, _ in
            SidebarInteractiveOwnerRecoveryResult(
                recoveredOwnerCount: 1,
                sourceOwnerResolved: true,
                resolvedOwnerDescription: "owner",
                resolutionReason: "test"
            )
        }

        let sourceWindow = makeWindow()
        let ownerView = NSView(frame: .zero)
        sourceWindow.contentView?.addSubview(ownerView)
        let source = SidebarTransientPresentationSource(
            windowID: coordinator.windowID,
            window: sourceWindow,
            originOwnerView: ownerView,
            coordinator: coordinator
        )
        let token = coordinator.beginSession(
            kind: .contextMenu,
            source: source,
            path: "test.menu-preopen"
        )

        XCTAssertFalse(interactionState.allowsSidebarDragSourceHitTesting)

        coordinator.endSession(token)
        drainMainRunLoop()

        XCTAssertTrue(interactionState.allowsSidebarDragSourceHitTesting)
        XCTAssertEqual(spy.recoveredWindows.count, 2)
        XCTAssertTrue(spy.recoveredWindows.allSatisfy { $0 === sourceWindow })
        XCTAssertEqual(spy.recoveredAnchors.count, 2)
        XCTAssertTrue(spy.recoveredAnchors.allSatisfy { $0 === ownerView })
        XCTAssertTrue(inputRecoveryReasons.isEmpty)
    }

    func testSidebarTransientSessionCoordinatorHandoffRecoversAfterFinalTransientOnly() {
        let interactionState = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
        let spy = SidebarHostRecoverySpy()
        var inputRecoveryReasons: [String] = []
        coordinator.sidebarRecoveryCoordinator = spy
        coordinator.scheduleSidebarInputRehydrate = { inputRecoveryReasons.append($0) }
        coordinator.recoverSidebarInteractiveOwners = { _, _ in
            SidebarInteractiveOwnerRecoveryResult(
                recoveredOwnerCount: 1,
                sourceOwnerResolved: true,
                resolvedOwnerDescription: "owner",
                resolutionReason: "test"
            )
        }

        let sourceWindow = makeWindow()
        let ownerView = NSView(frame: .zero)
        sourceWindow.contentView?.addSubview(ownerView)

        coordinator.prepareMenuPresentationSource(ownerView: ownerView)
        let menuSource = coordinator.preparedPresentationSource(
            window: sourceWindow,
            ownerView: ownerView
        )
        let menuToken = coordinator.beginSession(
            kind: .contextMenu,
            source: menuSource,
            path: "test.menu",
            preservePendingSource: true
        )

        coordinator.beginMenuActionDispatch(
            path: "test.action",
            classification: .presentationOnly
        )
        coordinator.endSession(menuToken)
        let dialogSource = coordinator.consumePresentationSource(window: nil)
        let dialogToken = coordinator.beginSession(
            kind: .dialog,
            source: dialogSource,
            path: "test.dialog"
        )
        coordinator.finishMenuActionDispatch(
            path: "test.action",
            classification: .presentationOnly
        )
        drainMainRunLoop()

        XCTAssertTrue(spy.recoveredWindows.isEmpty)
        XCTAssertTrue(inputRecoveryReasons.isEmpty)

        coordinator.endSession(dialogToken)
        drainMainRunLoop()

        XCTAssertEqual(spy.recoveredWindows.count, 2)
        XCTAssertTrue(spy.recoveredWindows.allSatisfy { $0 === sourceWindow })
        XCTAssertTrue(inputRecoveryReasons.isEmpty)
    }

    func testSidebarTransientSessionCoordinatorReconcilesStaleInteractionTokensAfterFinalRecovery() {
        let interactionState = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
        let spy = SidebarHostRecoverySpy()
        var inputRecoveryReasons: [String] = []
        coordinator.sidebarRecoveryCoordinator = spy
        coordinator.scheduleSidebarInputRehydrate = { inputRecoveryReasons.append($0) }
        var interactiveOwnerRecoveryWindows: [NSWindow?] = []
        coordinator.recoverSidebarInteractiveOwners = { window, _ in
            interactiveOwnerRecoveryWindows.append(window)
            return SidebarInteractiveOwnerRecoveryResult(
                recoveredOwnerCount: 1,
                sourceOwnerResolved: true,
                resolvedOwnerDescription: "owner",
                resolutionReason: "test"
            )
        }

        interactionState.beginContextMenuSessionForTesting()
        XCTAssertFalse(interactionState.allowsSidebarDragSourceHitTesting)

        let sourceWindow = makeWindow()
        let ownerView = NSView(frame: .zero)
        sourceWindow.contentView?.addSubview(ownerView)
        let source = SidebarTransientPresentationSource(
            windowID: coordinator.windowID,
            window: sourceWindow,
            originOwnerView: ownerView,
            coordinator: coordinator
        )
        let token = coordinator.beginSession(
            kind: .dialog,
            source: source,
            path: "test.reconcile-stale-token"
        )

        XCTAssertFalse(interactionState.allowsSidebarDragSourceHitTesting)

        coordinator.endSession(token)
        drainMainRunLoop()

        XCTAssertTrue(interactionState.allowsSidebarDragSourceHitTesting)
        XCTAssertFalse(interactionState.suppressesSidebarAffordances)
        XCTAssertTrue(inputRecoveryReasons.isEmpty)
        XCTAssertEqual(interactiveOwnerRecoveryWindows.count, 2)
        XCTAssertTrue(interactiveOwnerRecoveryWindows.allSatisfy { $0 === sourceWindow })
        XCTAssertEqual(spy.recoveredWindows.count, 2)
        XCTAssertTrue(spy.recoveredWindows.allSatisfy { $0 === sourceWindow })
    }

    func testSidebarTransientSessionCoordinatorStructuralMenuActionTriggersSingleHardRehydrate() {
        let interactionState = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
        let spy = SidebarHostRecoverySpy()
        var inputRecoveryReasons: [String] = []
        coordinator.sidebarRecoveryCoordinator = spy
        coordinator.scheduleSidebarInputRehydrate = { inputRecoveryReasons.append($0) }
        coordinator.recoverSidebarInteractiveOwners = { _, _ in
            SidebarInteractiveOwnerRecoveryResult(
                recoveredOwnerCount: 1,
                sourceOwnerResolved: true,
                resolvedOwnerDescription: "owner",
                resolutionReason: "test"
            )
        }

        let sourceWindow = makeWindow()
        let ownerView = NSView(frame: .zero)
        sourceWindow.contentView?.addSubview(ownerView)
        let source = SidebarTransientPresentationSource(
            windowID: coordinator.windowID,
            window: sourceWindow,
            originOwnerView: ownerView,
            coordinator: coordinator
        )
        let token = coordinator.beginSession(
            kind: .contextMenu,
            source: source,
            path: "test.structural-menu"
        )

        coordinator.beginMenuActionDispatch(
            path: "test.close",
            classification: .structuralMutation
        )
        coordinator.endSession(token)
        coordinator.finishMenuActionDispatch(
            path: "test.close",
            classification: .structuralMutation
        )
        drainMainRunLoop()

        XCTAssertEqual(spy.recoveredWindows.count, 2)
        XCTAssertEqual(inputRecoveryReasons.count, 1)
    }

    func testSidebarTransientSessionCoordinatorSoftRecoveryStaysSoftWhenSourceOwnerRemainsResolvable() {
        let interactionState = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
        let spy = SidebarHostRecoverySpy()
        var inputRecoveryReasons: [String] = []
        coordinator.sidebarRecoveryCoordinator = spy
        coordinator.scheduleSidebarInputRehydrate = { inputRecoveryReasons.append($0) }
        coordinator.recoverSidebarInteractiveOwners = { _, source in
            XCTAssertNotNil(source.interactiveOwnerRecoveryMetadata)
            return SidebarInteractiveOwnerRecoveryResult(
                recoveredOwnerCount: 1,
                sourceOwnerResolved: true,
                resolvedOwnerDescription: "SidebarInteractiveItemView{replacement}",
                resolutionReason: "dragKey"
            )
        }

        let sourceWindow = makeWindow()
        let ownerView = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        ownerView.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )
        sourceWindow.contentView?.addSubview(ownerView)
        let source = SidebarTransientPresentationSource(
            windowID: coordinator.windowID,
            window: sourceWindow,
            originOwnerView: ownerView,
            coordinator: coordinator
        )
        let token = coordinator.beginSession(
            kind: .contextMenu,
            source: source,
            path: "test.source-owner-soft"
        )

        coordinator.endSession(token)
        drainMainRunLoop()

        XCTAssertEqual(spy.recoveredWindows.count, 2)
        XCTAssertTrue(spy.recoveredWindows.allSatisfy { $0 === sourceWindow })
        XCTAssertTrue(inputRecoveryReasons.isEmpty)
    }

    func testSidebarTransientSessionCoordinatorSoftRecoveryEscalatesWhenSourceOwnerIsUnresolvedDespiteOtherRecoveredOwners() {
        let interactionState = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
        let spy = SidebarHostRecoverySpy()
        var inputRecoveryReasons: [String] = []
        coordinator.sidebarRecoveryCoordinator = spy
        coordinator.scheduleSidebarInputRehydrate = { inputRecoveryReasons.append($0) }
        coordinator.recoverSidebarInteractiveOwners = { _, source in
            XCTAssertNotNil(source.interactiveOwnerRecoveryMetadata)
            return SidebarInteractiveOwnerRecoveryResult(
                recoveredOwnerCount: 2,
                sourceOwnerResolved: false,
                resolvedOwnerDescription: "SidebarInteractiveItemView{other}",
                resolutionReason: "unrelatedOwner"
            )
        }

        let sourceWindow = makeWindow()
        let ownerView = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        ownerView.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )
        sourceWindow.contentView?.addSubview(ownerView)
        let source = SidebarTransientPresentationSource(
            windowID: coordinator.windowID,
            window: sourceWindow,
            originOwnerView: ownerView,
            coordinator: coordinator
        )
        let token = coordinator.beginSession(
            kind: .contextMenu,
            source: source,
            path: "test.source-owner-hard"
        )

        coordinator.endSession(token)
        drainMainRunLoop()

        XCTAssertEqual(spy.recoveredWindows.count, 2)
        XCTAssertTrue(spy.recoveredWindows.allSatisfy { $0 === sourceWindow })
        XCTAssertEqual(inputRecoveryReasons.count, 1)
    }

    func testSidebarTransientSessionCoordinatorSoftRecoveryEscalatesWhenOwnerRecoveryFindsNoLiveOwners() {
        let interactionState = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
        let spy = SidebarHostRecoverySpy()
        var inputRecoveryReasons: [String] = []
        coordinator.sidebarRecoveryCoordinator = spy
        coordinator.scheduleSidebarInputRehydrate = { inputRecoveryReasons.append($0) }
        coordinator.recoverSidebarInteractiveOwners = { _, _ in
            SidebarInteractiveOwnerRecoveryResult(
                recoveredOwnerCount: 0,
                sourceOwnerResolved: false,
                resolvedOwnerDescription: nil,
                resolutionReason: nil
            )
        }

        let sourceWindow = makeWindow()
        let ownerView = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        ownerView.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )
        sourceWindow.contentView?.addSubview(ownerView)
        let source = SidebarTransientPresentationSource(
            windowID: coordinator.windowID,
            window: sourceWindow,
            originOwnerView: ownerView,
            coordinator: coordinator
        )
        let token = coordinator.beginSession(
            kind: .dialog,
            source: source,
            path: "test.soft-escalation"
        )

        coordinator.endSession(token)
        drainMainRunLoop()

        XCTAssertEqual(spy.recoveredWindows.count, 2)
        XCTAssertEqual(inputRecoveryReasons.count, 1)
    }

    func testSidebarDeferredStateMutationAppliesLatestValueAfterCallbackBoundary() {
        let mutation = SidebarDeferredStateMutation<Int>()
        var appliedValues: [Int] = []

        mutation.schedule(1) { appliedValues.append($0) }
        mutation.schedule(2) { appliedValues.append($0) }

        XCTAssertTrue(appliedValues.isEmpty)

        drainMainRunLoop()

        XCTAssertEqual(appliedValues, [2])
    }

    func testBrowserWindowStateCoalescesSidebarInputRehydrateRequestsPerRunLoopTurn() {
        let windowState = BrowserWindowState()

        windowState.scheduleSidebarInputRehydrate(reason: "first")
        windowState.scheduleSidebarInputRehydrate(reason: "second")

        XCTAssertEqual(windowState.sidebarInputRecoveryGeneration, 0)

        drainMainRunLoop()

        XCTAssertEqual(windowState.sidebarInputRecoveryGeneration, 1)

        windowState.scheduleSidebarInputRehydrate(reason: "third")
        drainMainRunLoop()

        XCTAssertEqual(windowState.sidebarInputRecoveryGeneration, 2)
    }

    func testWorkspaceAppearanceServicePrefersExplicitSidebarSourceWindowForThemePickerSession() {
        let service = WorkspaceAppearanceService()
        let space = Space(name: "Personal")

        let preferredWindow = BrowserWindowState()
        preferredWindow.currentSpaceId = space.id
        preferredWindow.window = makeWindow()

        let activeWindow = BrowserWindowState()
        activeWindow.currentSpaceId = UUID()
        activeWindow.window = makeWindow()

        let registry = WindowRegistry()
        registry.register(preferredWindow)
        registry.register(activeWindow)
        registry.setActive(activeWindow)

        let source = SidebarTransientPresentationSource(
            windowID: preferredWindow.id,
            window: preferredWindow.window,
            originOwnerView: nil,
            coordinator: preferredWindow.sidebarTransientSessionCoordinator
        )

        var presentedSession: WorkspaceThemePickerSession?
        var shownDialogSource: SidebarTransientPresentationSource?
        let context = WorkspaceAppearanceService.Context(
            currentSpace: { space },
            spaceLookup: { $0 == space.id ? space : nil },
            windowRegistry: { registry },
            commitWorkspaceTheme: { _, _ in },
            syncWorkspaceThemeAcrossWindows: { _, _ in },
            scheduleStructuralPersistence: {},
            presentPicker: { presentedSession = $0 },
            showDialog: { _, dialogSource in
                shownDialogSource = dialogSource
            },
            closeDialog: {}
        )

        service.showGradientEditor(using: context, preferredSource: source)

        XCTAssertNil(shownDialogSource)
        XCTAssertEqual(presentedSession?.hostWindowID, preferredWindow.id)
        XCTAssertTrue(presentedSession?.presentationSource === source)
    }

    func testWorkspaceAppearanceServiceFallbackDialogKeepsExplicitSidebarSource() {
        let service = WorkspaceAppearanceService()
        let source = SidebarTransientPresentationSource(
            windowID: UUID(),
            window: makeWindow(),
            originOwnerView: nil,
            coordinator: nil
        )

        var shownDialogSource: SidebarTransientPresentationSource?
        let context = WorkspaceAppearanceService.Context(
            currentSpace: { nil },
            spaceLookup: { _ in nil },
            windowRegistry: { nil },
            commitWorkspaceTheme: { _, _ in },
            syncWorkspaceThemeAcrossWindows: { _, _ in },
            scheduleStructuralPersistence: {},
            presentPicker: { _ in
                XCTFail("Theme picker should not present without a current space")
            },
            showDialog: { _, dialogSource in
                shownDialogSource = dialogSource
            },
            closeDialog: {}
        )

        service.showGradientEditor(using: context, preferredSource: source)

        XCTAssertTrue(shownDialogSource === source)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private func makeRegisteredSidebarOwner(
        controller: SidebarContextMenuController
    ) -> (
        window: NSWindow,
        container: NSView,
        hostedView: NSView,
        owner: SidebarInteractiveItemView
    ) {
        let window = makeWindow()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let hostedView = NSView(frame: container.bounds)
        let owner = SidebarInteractiveItemView(frame: NSRect(x: 20, y: 20, width: 80, height: 36))

        window.contentView?.addSubview(container)
        container.addSubview(hostedView)
        hostedView.addSubview(owner)
        owner.contextMenuController = controller

        return (window, container, hostedView, owner)
    }

    private func anchorIDs(
        in window: NSWindow,
        coordinator: SidebarHostRecoveryCoordinator
    ) -> Set<ObjectIdentifier> {
        Set(coordinator.registeredAnchors(in: window).map(ObjectIdentifier.init))
    }

    private func makeMouseEvent(
        type: NSEvent.EventType,
        location: NSPoint = NSPoint(x: 5, y: 5)
    ) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            fatalError("Failed to create mouse event for test.")
        }
        return event
    }

    private func drainMainRunLoop() {
        for _ in 0..<8 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

}

@MainActor
private final class SidebarHostRecoverySpy: SidebarHostRecoveryHandling {
    private(set) var syncedAnchors: [NSView] = []
    private(set) var syncedWindows: [NSWindow] = []
    private(set) var unregisteredAnchors: [NSView] = []
    private(set) var recoveredWindows: [NSWindow] = []
    private(set) var recoveredAnchors: [NSView] = []
    private(set) var recoveryOrder: [String] = []

    func sync(anchor: NSView, window: NSWindow?) {
        syncedAnchors.append(anchor)
        if let window {
            syncedWindows.append(window)
        }
    }

    func unregister(anchor: NSView) {
        unregisteredAnchors.append(anchor)
    }

    func recover(in window: NSWindow?) {
        if let window {
            recoveredWindows.append(window)
            recoveryOrder.append("window")
        }
    }

    func recover(anchor: NSView?) {
        if let anchor {
            recoveredAnchors.append(anchor)
            recoveryOrder.append("anchor")
        }
    }
}
