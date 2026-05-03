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

    func testDialogManagerUsesParentBrowserWindowForChildPanelSource() {
        let manager = DialogManager()
        let parentWindow = makeWindow()
        let panel = CollapsedSidebarPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        parentWindow.addChildWindow(panel, ordered: .above)

        let source = SidebarTransientPresentationSource(
            windowID: UUID(),
            window: panel,
            originOwnerView: nil,
            coordinator: nil
        )

        manager.showDialog(EmptyView(), source: source)

        XCTAssertTrue(manager.isPresented(in: parentWindow))
        XCTAssertFalse(manager.isPresented(in: panel))

        parentWindow.removeChildWindow(panel)
    }

    func testWorkspaceThemePickerDismissRecoveryUsesWindowAndPopoverAnchor() {
        let spy = SidebarHostRecoverySpy()
        let window = makeWindow()
        let anchor = NSView(frame: .zero)

        WorkspaceThemePickerPopoverPresenter.performDismissRecovery(
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

        WorkspaceThemePickerPopoverPresenter.performDismissRecovery(
            in: window,
            anchor: anchor,
            using: spy
        )
        WorkspaceThemePickerPopoverPresenter.performDismissRecovery(
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

    func testSidebarInteractiveItemDisarmStopsHitTestingAndResetsPartialMouseState() {
        let dragView = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        dragView.update(
            rootView: AnyView(Color.clear.frame(width: 40, height: 40)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row
                )
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
            eventType: .leftMouseDown,
            capturesPanelBackgroundPointerEvents: true
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

    func testSidebarPresentationContextCapturesPanelBackgroundOnlyWhenCollapsedVisible() {
        XCTAssertFalse(
            SidebarPresentationContext.docked(sidebarWidth: 280).capturesPanelBackgroundPointerEvents
        )
        XCTAssertFalse(
            SidebarPresentationContext.collapsedHidden(sidebarWidth: 280).capturesPanelBackgroundPointerEvents
        )
        XCTAssertTrue(
            SidebarPresentationContext.collapsedVisible(sidebarWidth: 280).capturesPanelBackgroundPointerEvents
        )
    }

    func testSidebarPresentationContextOnlySuppressesInteractiveWorkWhileCollapsedHidden() {
        XCTAssertTrue(
            SidebarPresentationContext.docked(sidebarWidth: 280).allowsInteractiveWork
        )
        XCTAssertFalse(
            SidebarPresentationContext.collapsedHidden(sidebarWidth: 280).allowsInteractiveWork
        )
        XCTAssertTrue(
            SidebarPresentationContext.collapsedVisible(sidebarWidth: 280).allowsInteractiveWork
        )
    }

    func testSidebarPresentationContextInputModeSeparatesDockedLayoutFromCollapsedOverlay() {
        XCTAssertEqual(
            SidebarPresentationContext.docked(sidebarWidth: 280).inputMode,
            .dockedLayout
        )
        XCTAssertEqual(
            SidebarPresentationContext.collapsedHidden(sidebarWidth: 280).inputMode,
            .collapsedOverlay
        )
        XCTAssertEqual(
            SidebarPresentationContext.collapsedVisible(sidebarWidth: 280).inputMode,
            .collapsedOverlay
        )
    }

    func testSimplePrimaryActionsUseNativeDockedInputAndCollapsedAppKitOwnerRouting() {
        XCTAssertFalse(
            SidebarPrimaryActionInputRouting.usesAppKitOwner(
                in: SidebarPresentationContext.docked(sidebarWidth: 280)
            )
        )
        XCTAssertTrue(
            SidebarPrimaryActionInputRouting.usesAppKitOwner(
                in: SidebarPresentationContext.collapsedHidden(sidebarWidth: 280)
            )
        )
        XCTAssertTrue(
            SidebarPrimaryActionInputRouting.usesAppKitOwner(
                in: SidebarPresentationContext.collapsedVisible(sidebarWidth: 280)
            )
        )
    }

    func testSidebarColumnRoutingShieldsCollapsedVisiblePanelBackgroundFromWebContent() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))

        let routed = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 30, y: 30),
            in: container,
            originalHit: nil,
            hostedSidebarView: nil,
            contextMenuController: nil,
            eventType: .mouseMoved,
            capturesPanelBackgroundPointerEvents: true
        )

        XCTAssertTrue(routed === container)
    }

    func testSidebarColumnRoutingLeavesCollapsedHiddenPanelBackgroundPassThrough() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))

        let routed = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 30, y: 30),
            in: container,
            originalHit: nil,
            hostedSidebarView: nil,
            contextMenuController: nil,
            eventType: .mouseMoved,
            capturesPanelBackgroundPointerEvents: false
        )

        XCTAssertNil(routed)
    }

    func testSidebarColumnRoutingDoesNotShieldOutsidePanelBounds() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let webContentHit = NSView(frame: .zero)

        let routed = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 220, y: 30),
            in: container,
            originalHit: webContentHit,
            hostedSidebarView: nil,
            contextMenuController: nil,
            eventType: .mouseMoved,
            capturesPanelBackgroundPointerEvents: true
        )

        XCTAssertTrue(routed === webContentHit)
    }

    func testSidebarColumnRoutingRegisteredOwnerWinsOverCollapsedPanelBackgroundShield() {
        let controller = makeSidebarContextMenuController(interactionState: SidebarInteractionState())
        let (_, container, hostedView, owner) = makeRegisteredSidebarOwner(controller: controller)
        owner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(primaryAction: {})
        )

        let routed = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 30, y: 30),
            in: container,
            originalHit: hostedView,
            hostedSidebarView: hostedView,
            contextMenuController: controller,
            eventType: .leftMouseDown,
            capturesPanelBackgroundPointerEvents: true
        )

        XCTAssertTrue(routed === owner)
    }

    func testSidebarHoverOverlayHostMountPolicySkipsHiddenIdleAndDockedStates() {
        XCTAssertFalse(
            SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
                isSidebarVisible: false,
                isOverlayVisible: false,
                isOverlayHostPrewarmed: false,
                transientUIPinsHoverSidebar: false,
                sidebarDragPinsHoverSidebar: false
            )
        )
        XCTAssertFalse(
            SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
                isSidebarVisible: true,
                isOverlayVisible: true,
                isOverlayHostPrewarmed: true,
                transientUIPinsHoverSidebar: true,
                sidebarDragPinsHoverSidebar: true
            )
        )
    }

    func testSidebarHoverOverlayHostMountPolicyMountsForRevealPrewarmTransientAndDragPins() {
        XCTAssertTrue(
            SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
                isSidebarVisible: false,
                isOverlayVisible: true,
                isOverlayHostPrewarmed: false,
                transientUIPinsHoverSidebar: false,
                sidebarDragPinsHoverSidebar: false
            )
        )
        XCTAssertTrue(
            SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
                isSidebarVisible: false,
                isOverlayVisible: false,
                isOverlayHostPrewarmed: true,
                transientUIPinsHoverSidebar: false,
                sidebarDragPinsHoverSidebar: false
            )
        )
        XCTAssertTrue(
            SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
                isSidebarVisible: false,
                isOverlayVisible: false,
                isOverlayHostPrewarmed: false,
                transientUIPinsHoverSidebar: true,
                sidebarDragPinsHoverSidebar: false
            )
        )
        XCTAssertTrue(
            SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
                isSidebarVisible: false,
                isOverlayVisible: false,
                isOverlayHostPrewarmed: false,
                transientUIPinsHoverSidebar: false,
                sidebarDragPinsHoverSidebar: true
            )
        )
    }

    func testRightSidebarCollapsedRevealUsesSameHostMountPolicy() {
        let hidden = SidebarPresentationContext.collapsedHidden(
            sidebarWidth: 280,
            sidebarPosition: .right
        )
        let visible = SidebarPresentationContext.collapsedVisible(
            sidebarWidth: 280,
            sidebarPosition: .right
        )

        XCTAssertTrue(hidden.shellEdge.isRight)
        XCTAssertTrue(visible.shellEdge.isRight)
        XCTAssertFalse(
            SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
                isSidebarVisible: false,
                isOverlayVisible: false,
                isOverlayHostPrewarmed: false,
                transientUIPinsHoverSidebar: false,
                sidebarDragPinsHoverSidebar: false
            )
        )
        XCTAssertTrue(
            SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
                isSidebarVisible: false,
                isOverlayVisible: true,
                isOverlayHostPrewarmed: false,
                transientUIPinsHoverSidebar: false,
                sidebarDragPinsHoverSidebar: false
            )
        )
    }

    func testSidebarHoverOverlaySourceMountsFullHostOnlyBehindMountPolicy() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SidebarHoverOverlayView.swift")
        let bodyStart = try XCTUnwrap(source.range(of: "var body: some View")).lowerBound
        let hostStart = try XCTUnwrap(source.range(of: "private var collapsedPanelHost")).lowerBound
        let bodySource = String(source[bodyStart..<hostStart])
        let hostSource = String(source[hostStart...])

        XCTAssertTrue(source.contains("enum SidebarHoverOverlayHostMountPolicy"))
        XCTAssertTrue(bodySource.contains("collapsedPanelHost"))
        XCTAssertFalse(bodySource.contains("SidebarColumnRepresentable("))
        XCTAssertTrue(hostSource.contains("CollapsedSidebarPanelHost("))
        XCTAssertTrue(hostSource.contains("isHostRequested: shouldMountCollapsedSidebarHost"))
        XCTAssertTrue(bodySource.contains(".frame(width: hoverManager.triggerWidth)"))
        XCTAssertTrue(bodySource.contains("hoverManager.requestOverlayReveal"))
        XCTAssertTrue(bodySource.contains(".allowsHitTesting(false)"))
    }

    func testCollapsedPanelRootIsOnlyUsedForCollapsedController() {
        let docked = SidebarColumnViewController(usesCollapsedPanelRoot: false)
        docked.loadView()
        XCTAssertFalse(docked.view is CollapsedSidebarPanelRootView)

        let collapsed = SidebarColumnViewController(usesCollapsedPanelRoot: true)
        collapsed.loadView()
        XCTAssertTrue(collapsed.view is CollapsedSidebarPanelRootView)
    }

    func testCollapsedPanelRootBackgroundHitReturnsRootInsideBoundsAndNilOutside() {
        let root = CollapsedSidebarPanelRootView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        root.isPanelHitTestingEnabled = true

        XCTAssertTrue(root.hitTest(NSPoint(x: 30, y: 30)) === root)
        XCTAssertNil(root.hitTest(NSPoint(x: 230, y: 30)))

        root.isPanelHitTestingEnabled = false
        XCTAssertNil(root.hitTest(NSPoint(x: 30, y: 30)))
    }

    func testCollapsedPanelRootReturnsChildButtonBeforeRoot() {
        let root = CollapsedSidebarPanelRootView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let button = NSButton(frame: NSRect(x: 20, y: 20, width: 80, height: 30))
        root.addSubview(button)
        root.isPanelHitTestingEnabled = true

        XCTAssertTrue(root.hitTest(NSPoint(x: 30, y: 30)) === button)
        XCTAssertTrue(root.hitTest(NSPoint(x: 4, y: 4)) === root)
    }

    func testCollapsedPanelRootRoutesHostedBackgroundToRootForWindowDrag() {
        let root = CollapsedSidebarPanelRootView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let hosted = NSView(frame: root.bounds)
        root.hostedSidebarView = hosted
        root.addSubview(hosted)
        root.isPanelHitTestingEnabled = true

        XCTAssertTrue(root.hitTest(NSPoint(x: 30, y: 30)) === root)
    }

    func testCollapsedPanelRootReturnsSidebarInteractiveOwnerPathBeforeRoot() {
        let root = CollapsedSidebarPanelRootView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let owner = SidebarInteractiveItemView(frame: NSRect(x: 20, y: 20, width: 80, height: 36))
        owner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(primaryAction: {})
        )
        root.addSubview(owner)
        root.isPanelHitTestingEnabled = true

        let hit = root.hitTest(NSPoint(x: 30, y: 30))
        XCTAssertNotNil(hit)
        XCTAssertTrue(hit === owner || hit?.isDescendant(of: owner) == true)
    }

    func testCollapsedPanelRootReturnsSidebarTextInputBeforeRoot() {
        let root = CollapsedSidebarPanelRootView(frame: NSRect(x: 0, y: 0, width: 200, height: 120))
        let textField = NSTextField(frame: NSRect(x: 20, y: 20, width: 120, height: 24))
        textField.isEditable = true
        root.addSubview(textField)
        root.isPanelHitTestingEnabled = true

        let hit = root.hitTest(NSPoint(x: 30, y: 30))
        XCTAssertNotNil(hit)
        XCTAssertTrue(hit === textField || hit?.isDescendant(of: textField) == true)
    }

    func testCollapsedPanelRootPreventsUnderlyingContentHitInsidePanelBounds() {
        let window = makeWindow()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let webContent = NSView(frame: content.bounds)
        let root = CollapsedSidebarPanelRootView(frame: NSRect(x: 0, y: 0, width: 120, height: 240))
        root.isPanelHitTestingEnabled = true

        window.contentView = content
        content.addSubview(webContent)
        content.addSubview(root)

        XCTAssertTrue(content.hitTest(NSPoint(x: 30, y: 30)) === root)
        XCTAssertTrue(content.hitTest(NSPoint(x: 180, y: 30)) === webContent)
    }

    func testCollapsedPanelRootUsesPanelLocalBoundsNotFullParentWindow() {
        let root = CollapsedSidebarPanelRootView(frame: NSRect(x: 0, y: 0, width: 120, height: 240))
        root.isPanelHitTestingEnabled = true

        XCTAssertTrue(root.hitTest(NSPoint(x: 30, y: 30)) === root)
        XCTAssertNil(root.hitTest(NSPoint(x: 180, y: 30)))
    }

    func testCollapsedSidebarPanelFrameResolverAlignsLeftAndRight() {
        let parentFrame = NSRect(x: 100, y: 200, width: 640, height: 480)

        XCTAssertEqual(
            CollapsedSidebarPanelFrameResolver.panelFrame(
                parentContentScreenFrame: parentFrame,
                sidebarWidth: 220,
                sidebarPosition: .left
            ),
            NSRect(x: 100, y: 200, width: 220, height: 480)
        )
        XCTAssertEqual(
            CollapsedSidebarPanelFrameResolver.panelFrame(
                parentContentScreenFrame: parentFrame,
                sidebarWidth: 220,
                sidebarPosition: .right
            ),
            NSRect(x: 520, y: 200, width: 220, height: 480)
        )
        XCTAssertEqual(
            CollapsedSidebarPanelFrameResolver.hiddenContentOffset(
                for: 220,
                sidebarPosition: .left
            ),
            -220
        )
        XCTAssertEqual(
            CollapsedSidebarPanelFrameResolver.hiddenContentOffset(
                for: 220,
                sidebarPosition: .right
            ),
            220
        )
    }

    func testCollapsedSidebarDragPreviewOverlayFrameUsesFullParentContent() {
        let parentWindow = makeWindow()
        parentWindow.setFrame(NSRect(x: 100, y: 120, width: 420, height: 300), display: false)

        let expectedFrame = CollapsedSidebarPanelFrameResolver.parentContentScreenFrame(in: parentWindow)
        XCTAssertEqual(
            CollapsedSidebarDragPreviewOverlayFrameResolver.overlayFrame(in: parentWindow),
            expectedFrame
        )
    }

    func testCollapsedSidebarPanelControllerHiddenIdleHasNoPanelAndNoChildWindow() {
        let parentWindow = makeWindow()
        let controller = CollapsedSidebarPanelController()

        controller.update(
            parentWindow: parentWindow,
            root: AnyView(Color.clear),
            width: 220,
            presentationContext: .collapsedHidden(sidebarWidth: 220),
            contextMenuController: nil,
            isHostRequested: false
        )

        XCTAssertNil(controller.panelWindowForTesting)
        XCTAssertTrue(parentWindow.childWindows?.isEmpty ?? true)
        XCTAssertFalse(controller.isPanelAttachedForTesting)
    }

    func testCollapsedSidebarPanelControllerPrewarmsWithoutAttachingAndVisibleAttaches() throws {
        let parentWindow = makeWindow()
        let controller = CollapsedSidebarPanelController()
        controller.frameSyncBurstDurationOverrideForTesting = 0.04

        controller.update(
            parentWindow: parentWindow,
            root: AnyView(Color.clear.frame(width: 220, height: 240)),
            width: 220,
            presentationContext: .collapsedHidden(sidebarWidth: 220),
            contextMenuController: nil,
            isHostRequested: true
        )

        let prewarmedPanel = try XCTUnwrap(controller.panelWindowForTesting)
        XCTAssertFalse(controller.isPanelAttachedForTesting)
        XCTAssertFalse(controller.isFrameSyncTimerActiveForTesting)
        XCTAssertTrue(parentWindow.childWindows?.isEmpty ?? true)
        let visibleFrame = try XCTUnwrap(CollapsedSidebarPanelFrameResolver.panelFrame(
            in: parentWindow,
            sidebarWidth: 220,
            sidebarPosition: .left
        ))
        XCTAssertEqual(
            prewarmedPanel.frame,
            visibleFrame
        )

        controller.update(
            parentWindow: parentWindow,
            root: AnyView(Color.clear.frame(width: 220, height: 240)),
            width: 220,
            presentationContext: .collapsedVisible(sidebarWidth: 220),
            contextMenuController: nil,
            isHostRequested: true
        )

        XCTAssertTrue(controller.panelWindowForTesting === prewarmedPanel)
        XCTAssertTrue(controller.isPanelAttachedForTesting)
        XCTAssertTrue(controller.isFrameSyncTimerActiveForTesting)
        XCTAssertTrue(parentWindow.childWindows?.contains { $0 === prewarmedPanel } == true)

        drainMainRunLoop()

        XCTAssertTrue(controller.isPanelAttachedForTesting)
        XCTAssertTrue(parentWindow.childWindows?.contains { $0 === prewarmedPanel } == true)
        XCTAssertFalse(controller.isFrameSyncTimerActiveForTesting)
    }

    func testCollapsedSidebarPanelControllerResizeNotificationAndOverlayAttachDoNotStartIdleTimer() throws {
        let parentWindow = makeWindow()
        let controller = CollapsedSidebarPanelController()
        controller.frameSyncBurstDurationOverrideForTesting = 0.04

        controller.update(
            parentWindow: parentWindow,
            root: AnyView(Color.clear.frame(width: 220, height: 240)),
            width: 220,
            presentationContext: .collapsedVisible(sidebarWidth: 220),
            contextMenuController: nil,
            isHostRequested: true
        )
        drainMainRunLoop()
        XCTAssertFalse(controller.isFrameSyncTimerActiveForTesting)

        controller.updateDragPreviewOverlay(
            parentWindow: parentWindow,
            root: AnyView(Color.clear),
            isPresented: true
        )
        XCTAssertTrue(controller.isDragPreviewOverlayAttachedForTesting)
        XCTAssertFalse(controller.isFrameSyncTimerActiveForTesting)

        parentWindow.setFrame(NSRect(x: 40, y: 60, width: 500, height: 360), display: false)
        drainMainRunLoop()
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: parentWindow)
        drainMainRunLoop()

        XCTAssertTrue(controller.isPanelAttachedForTesting)
        XCTAssertTrue(controller.isDragPreviewOverlayAttachedForTesting)
        XCTAssertFalse(controller.isFrameSyncTimerActiveForTesting)
    }

    func testCollapsedSidebarPanelControllerLiveResizeUsesTemporaryFrameSyncBurst() throws {
        let parentWindow = makeWindow()
        let controller = CollapsedSidebarPanelController()
        controller.frameSyncBurstDurationOverrideForTesting = 0.05

        controller.update(
            parentWindow: parentWindow,
            root: AnyView(Color.clear.frame(width: 220, height: 240)),
            width: 220,
            presentationContext: .collapsedVisible(sidebarWidth: 220),
            contextMenuController: nil,
            isHostRequested: true
        )
        drainMainRunLoop()
        XCTAssertFalse(controller.isFrameSyncTimerActiveForTesting)

        controller.frameSyncBurstDurationOverrideForTesting = 0.3
        NotificationCenter.default.post(name: NSWindow.willStartLiveResizeNotification, object: parentWindow)
        drainMainRunLoop()
        XCTAssertTrue(controller.isFrameSyncTimerActiveForTesting)
        XCTAssertEqual(controller.frameSyncBurstReasonForTesting, "live-resize")

        parentWindow.setFrame(NSRect(x: 20, y: 30, width: 480, height: 340), display: false)
        drainMainRunLoop()
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: parentWindow)
        drainMainRunLoop()

        XCTAssertTrue(controller.isFrameSyncTimerActiveForTesting)

        NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: parentWindow)
        runMainRunLoopBriefly()

        XCTAssertFalse(controller.isFrameSyncTimerActiveForTesting)
    }

    func testCollapsedSidebarPanelControllerVisiblePanelIsInteractiveAndNonActivating() throws {
        let parentWindow = makeWindow()
        let controller = CollapsedSidebarPanelController()

        controller.update(
            parentWindow: parentWindow,
            root: AnyView(Button("Hit") {}.frame(width: 80, height: 28)),
            width: 220,
            presentationContext: .collapsedVisible(sidebarWidth: 220),
            contextMenuController: nil,
            isHostRequested: true
        )

        let panel = try XCTUnwrap(controller.panelWindowForTesting)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.contentViewController is SidebarColumnViewController)
        XCTAssertTrue(controller.isPanelAttachedForTesting)
    }

    func testCollapsedSidebarPanelControllerOrdersDragPreviewOverlayAbovePanel() throws {
        let parentWindow = makeWindow()
        let controller = CollapsedSidebarPanelController()

        controller.update(
            parentWindow: parentWindow,
            root: AnyView(Color.clear.frame(width: 220, height: 240)),
            width: 220,
            presentationContext: .collapsedVisible(sidebarWidth: 220),
            contextMenuController: nil,
            isHostRequested: true
        )
        controller.updateDragPreviewOverlay(
            parentWindow: parentWindow,
            root: AnyView(Color.clear),
            isPresented: true
        )

        let panel = try XCTUnwrap(controller.panelWindowForTesting)
        let overlay = try XCTUnwrap(controller.dragPreviewOverlayWindowForTesting)
        let childWindows = try XCTUnwrap(parentWindow.childWindows)

        XCTAssertTrue(controller.isPanelAttachedForTesting)
        XCTAssertTrue(controller.isDragPreviewOverlayAttachedForTesting)
        XCTAssertTrue(childWindows.contains { $0 === panel })
        XCTAssertTrue(childWindows.contains { $0 === overlay })
        XCTAssertTrue(overlay.ignoresMouseEvents)
        XCTAssertFalse(overlay.canBecomeKey)
        XCTAssertFalse(overlay.canBecomeMain)
        XCTAssertTrue(overlay.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(
            overlay.frame,
            try XCTUnwrap(CollapsedSidebarDragPreviewOverlayFrameResolver.overlayFrame(in: parentWindow))
        )
    }

    func testCollapsedSidebarPanelControllerDetachesDragPreviewOverlayOnHide() {
        let parentWindow = makeWindow()
        let controller = CollapsedSidebarPanelController()

        controller.update(
            parentWindow: parentWindow,
            root: AnyView(Color.clear.frame(width: 220, height: 240)),
            width: 220,
            presentationContext: .collapsedVisible(sidebarWidth: 220),
            contextMenuController: nil,
            isHostRequested: true
        )
        controller.updateDragPreviewOverlay(
            parentWindow: parentWindow,
            root: AnyView(Color.clear),
            isPresented: true
        )
        XCTAssertTrue(controller.isDragPreviewOverlayAttachedForTesting)

        controller.update(
            parentWindow: parentWindow,
            root: AnyView(EmptyView()),
            width: 220,
            presentationContext: .collapsedHidden(sidebarWidth: 220),
            contextMenuController: nil,
            isHostRequested: false
        )

        XCTAssertNil(controller.dragPreviewOverlayWindowForTesting)
        XCTAssertFalse(controller.isDragPreviewOverlayAttachedForTesting)
        XCTAssertTrue(parentWindow.childWindows?.isEmpty ?? true)
    }

    func testCollapsedSidebarPanelControllerOrdersOutAndDestroysOnHiddenIdle() {
        let parentWindow = makeWindow()
        let controller = CollapsedSidebarPanelController()

        controller.update(
            parentWindow: parentWindow,
            root: AnyView(Color.clear.frame(width: 220, height: 240)),
            width: 220,
            presentationContext: .collapsedVisible(sidebarWidth: 220),
            contextMenuController: nil,
            isHostRequested: true
        )
        XCTAssertTrue(controller.isPanelAttachedForTesting)

        controller.update(
            parentWindow: parentWindow,
            root: AnyView(EmptyView()),
            width: 220,
            presentationContext: .collapsedHidden(sidebarWidth: 220),
            contextMenuController: nil,
            isHostRequested: false
        )

        XCTAssertNil(controller.panelWindowForTesting)
        XCTAssertTrue(parentWindow.childWindows?.isEmpty ?? true)
        XCTAssertFalse(controller.isPanelAttachedForTesting)
        XCTAssertFalse(controller.isFrameSyncTimerActiveForTesting)
    }

    func testCollapsedSidebarPanelControllerDetachesOnParentClose() {
        let parentWindow = makeWindow()
        let controller = CollapsedSidebarPanelController()

        controller.update(
            parentWindow: parentWindow,
            root: AnyView(Color.clear.frame(width: 220, height: 240)),
            width: 220,
            presentationContext: .collapsedVisible(sidebarWidth: 220),
            contextMenuController: nil,
            isHostRequested: true
        )
        XCTAssertTrue(controller.isPanelAttachedForTesting)

        parentWindow.close()
        drainMainRunLoop()

        XCTAssertNil(controller.panelWindowForTesting)
        XCTAssertFalse(controller.isPanelAttachedForTesting)
        XCTAssertFalse(controller.isFrameSyncTimerActiveForTesting)
    }

    func testSidebarDragPreviewMapperUsesParentWindowForChildPanelPreviewCoordinates() {
        let parentWindow = makeWindow()
        parentWindow.setFrame(NSRect(x: 100, y: 100, width: 320, height: 240), display: false)

        let panel = CollapsedSidebarPanelWindow(
            contentRect: NSRect(x: 300, y: 100, width: 120, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        parentWindow.addChildWindow(panel, ordered: .above)

        let childWindowPoint = NSPoint(x: 10, y: 20)
        let dropLocation = SidebarDragLocationMapper.swiftUIGlobalPoint(
            fromWindowPoint: childWindowPoint,
            in: panel
        )
        let previewLocation = SidebarDragLocationMapper.swiftUIPreviewPoint(
            fromWindowPoint: childWindowPoint,
            in: panel
        )

        let panelContentHeight = panel.contentView?.bounds.height ?? panel.frame.height
        let parentContentHeight = parentWindow.contentView?.bounds.height ?? parentWindow.frame.height
        XCTAssertEqual(dropLocation, CGPoint(x: 10, y: panelContentHeight - childWindowPoint.y))
        XCTAssertEqual(previewLocation, CGPoint(x: 210, y: parentContentHeight - childWindowPoint.y))

        parentWindow.removeChildWindow(panel)
    }

    func testCollapsedSidebarPanelAnimatesContentInsideBrowserEdge() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/CollapsedSidebarPanelHost.swift")
        let controllerSource = try Self.source(named: "Sumi/Components/Sidebar/SidebarColumnViewController.swift")

        XCTAssertTrue(source.contains("setSidebarContentOffset("))
        XCTAssertTrue(source.contains("CAKeyframeAnimation(keyPath: \"transform\")"))
        XCTAssertTrue(source.contains("revealDuration: TimeInterval = 0.25"))
        XCTAssertTrue(source.contains("hideDuration: TimeInterval = 0.15"))
        XCTAssertTrue(source.contains("CATransform3DMakeTranslation(offset, 0, 0)"))
        XCTAssertTrue(source.contains("startingOffset.map { CATransform3DMakeTranslation($0, 0, 0) }"))
        XCTAssertTrue(source.contains("startingOffset: wasAlreadyRevealed ? nil : initialContentOffset"))
        XCTAssertTrue(source.contains("collapsedPanelAnimatedContentView"))
        XCTAssertTrue(source.contains("panel.contentView?.layer?.masksToBounds = true"))
        XCTAssertTrue(controllerSource.contains("var collapsedPanelAnimatedContentView: NSView?"))
        XCTAssertTrue(source.contains(".sumiShouldHideCollapsedSidebarOverlay"))
        XCTAssertFalse(source.contains("panel.animator().setFrame"))
        XCTAssertFalse(source.contains("hiddenPanelFrame"))
    }

    func testCollapsedPanelRootSourceDoesNotUseEventSpecificHitTesting() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SidebarColumnContainerView.swift")
        let rootStart = try XCTUnwrap(source.range(of: "final class CollapsedSidebarPanelRootView"))
        let chromeStart = try XCTUnwrap(source.range(of: "enum SidebarColumnPaintlessChrome"))
        let rootSource = String(source[rootStart.lowerBound..<chromeStart.lowerBound])

        XCTAssertTrue(rootSource.contains("override func hitTest"))
        XCTAssertFalse(rootSource.contains("window?.currentEvent"))
        XCTAssertFalse(rootSource.contains("SidebarColumnHitTestRouting.routedHit"))
        XCTAssertTrue(rootSource.contains("if hit === hostedSidebarView"))
        XCTAssertTrue(rootSource.contains("parentWindow.performZoom(nil)"))
        XCTAssertTrue(rootSource.contains("parentWindow.performDrag(with: event)"))
    }

    func testCollapsedSidebarFooterActionsUseAppKitRouting() throws {
        let bottomBarSource = try Self.source(named: "Navigation/Sidebar/SidebarBottomBar.swift")
        let downloadsSource = try Self.source(named: "Sumi/Components/Downloads/DownloadsToolbarButton.swift")

        XCTAssertTrue(downloadsSource.contains(".sidebarAppKitPrimaryAction(action: action)"))
        XCTAssertTrue(bottomBarSource.contains("presentationContext.inputMode == .collapsedOverlay"))
        XCTAssertTrue(bottomBarSource.contains("triggers: [.leftClick, .rightClick]"))
        XCTAssertTrue(bottomBarSource.contains("newSpaceMenuEntries"))
    }

    func testCollapsedHostedRootContainsFullVisiblePanelChromeInOneSubtree() throws {
        let hostedRootSource = try Self.source(named: "Sumi/Components/Sidebar/SidebarColumnRepresentable.swift")
        let sidebarSource = try Self.source(named: "Navigation/Sidebar/SpacesSideBarView.swift")
        let headerSource = try Self.source(named: "Navigation/Sidebar/SidebarHeader.swift")

        XCTAssertTrue(hostedRootSource.contains("SpacesSideBarView()"))
        XCTAssertTrue(hostedRootSource.contains("collapsedSidebarChromeBackground"))
        XCTAssertTrue(sidebarSource.contains("SidebarHeader()"))
        XCTAssertTrue(sidebarSource.contains("spacesPageView(spaces: spaces)"))
        XCTAssertTrue(sidebarSource.contains("SidebarBottomBar("))
        XCTAssertTrue(headerSource.contains("NavButtonsView()"))
        XCTAssertTrue(headerSource.contains("URLBarView(presentationMode: .sidebar)"))
    }

    func testCollapsedSidebarCleanupRemovedFailedCursorShieldAndCorrectionPaths() throws {
        let overlaySource = try Self.source(named: "Sumi/Components/Sidebar/SidebarHoverOverlayView.swift")
        let columnSource = try Self.source(named: "Sumi/Components/Sidebar/SidebarColumnViewController.swift")
        let containerSource = try Self.source(named: "Sumi/Components/Sidebar/SidebarColumnContainerView.swift")
        let panelHostSource = try Self.source(named: "Sumi/Components/Sidebar/CollapsedSidebarPanelHost.swift")
        let combinedProductionSource = [
            overlaySource,
            columnSource,
            containerSource,
            panelHostSource,
        ].joined(separator: "\n")

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: Self.repoRoot
                .appendingPathComponent(
                    "Sumi/Components/Sidebar/" + "CollapsedSidebarCursor" + "OwnerView.swift"
                )
                .path
        ))
        XCTAssertFalse(combinedProductionSource.contains("CollapsedSidebar" + "CursorOwner"))
        XCTAssertFalse(combinedProductionSource.contains("CollapsedSidebar" + "PointerShield"))
        XCTAssertFalse(combinedProductionSource.contains("CollapsedSidebar" + "HitTestSurface"))
        XCTAssertFalse(combinedProductionSource.contains("CollapsedSidebar" + "PointerSuppressionController"))
        XCTAssertFalse(overlaySource.contains("collapsedCursor" + "Owner"))
        XCTAssertFalse(overlaySource.contains(".alwaysArrowCursor()"))
        XCTAssertFalse(columnSource.contains("pointerSuppressionController"))
        XCTAssertFalse(columnSource.contains("updatePointerSuppression"))
        XCTAssertFalse(combinedProductionSource.contains("schedulePostDispatchCursorCorrection"))
    }

    func testSidebarColumnContainerDoesNotContainObsoleteCursorShieldLayer() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SidebarColumnContainerView.swift")
        let containerStart = try XCTUnwrap(source.range(of: "final class SidebarColumnContainerView"))
        let containerEnd = try XCTUnwrap(source.range(of: "final class CollapsedSidebarPanelRootView"))
        let containerSource = String(source[containerStart.lowerBound..<containerEnd.lowerBound])

        XCTAssertFalse(containerSource.contains("CollapsedSidebar" + "PointerSuppressionController"))
        XCTAssertTrue(containerSource.contains("capturesPanelBackgroundPointerEvents"))
        XCTAssertFalse(containerSource.contains("resetCursorRects"))
        XCTAssertFalse(containerSource.contains("cursor" + "Update(with:"))
        XCTAssertFalse(containerSource.contains("NSTrackingArea"))
        XCTAssertFalse(containerSource.contains("trackingArea"))
        XCTAssertFalse(containerSource.contains("invalidateCursorRects"))
    }

    #if DEBUG
    func testSidebarDebugMetricsSnapshotAndReset() {
        SidebarDebugMetrics.resetForTesting()

        var owner: SidebarInteractiveItemView? = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 40, height: 40)
        )
        let controller = makeSidebarContextMenuController(interactionState: SidebarInteractionState())
        owner?.contextMenuController = controller

        let columnController = SidebarColumnViewController()
        SidebarDebugMetrics.recordCollapsedHiddenSidebarHost(
            controller: columnController,
            isMounted: true
        )

        let windowState = BrowserWindowState()
        windowState.scheduleSidebarInputRehydrate(reason: .explicitFallback)
        drainMainRunLoop()

        let dragState = SidebarDragState()
        let spaceID = UUID()
        dragState.schedulePageGeometry(
            spaceId: spaceID,
            profileId: nil,
            frame: CGRect(x: 0, y: 0, width: 200, height: 300),
            renderMode: .interactive,
            generation: dragState.activeGeometryGeneration
        )
        dragState.publishGeometrySnapshotForTesting()

        var snapshot = SidebarDebugMetrics.snapshot(dragState: dragState)
        XCTAssertEqual(snapshot.liveInteractiveItemViewCount, 1)
        XCTAssertEqual(snapshot.liveInteractiveOwnerAttachmentCount, 1)
        XCTAssertEqual(snapshot.interactiveOwnerHostingViewCreatedCount, 1)
        XCTAssertEqual(snapshot.mountedCollapsedSidebarHostCount, 1)
        XCTAssertEqual(snapshot.collapsedHiddenMountedSidebarHostCount, 1)
        XCTAssertEqual(snapshot.hardSidebarInputRehydrateCount, 1)
        XCTAssertEqual(snapshot.hardSidebarInputRehydrateReasons[SidebarInputRecoveryReason.explicitFallback.description], 1)
        XCTAssertEqual(snapshot.dragGeometryReporterCountBySection["page"], 1)
        XCTAssertEqual(snapshot.totalActiveDragGeometryReporterCount, 1)
        XCTAssertFalse(snapshot.isDragging)
        XCTAssertFalse(snapshot.isInternalDragGeometryArmed)

        owner?.contextMenuController = nil
        SidebarDebugMetrics.recordCollapsedHiddenSidebarHost(
            controller: columnController,
            isMounted: false
        )

        snapshot = SidebarDebugMetrics.snapshot(dragState: dragState)
        XCTAssertEqual(snapshot.liveInteractiveOwnerAttachmentCount, 0)
        XCTAssertEqual(snapshot.mountedCollapsedSidebarHostCount, 0)
        XCTAssertEqual(snapshot.collapsedHiddenMountedSidebarHostCount, 0)

        SidebarDebugMetrics.recordCollapsedSidebarHost(
            controller: columnController,
            presentationMode: .collapsedVisible,
            isMounted: true
        )
        snapshot = SidebarDebugMetrics.snapshot(dragState: dragState)
        XCTAssertEqual(snapshot.mountedCollapsedSidebarHostCount, 1)
        XCTAssertEqual(snapshot.collapsedHiddenMountedSidebarHostCount, 0)

        owner = nil
        SidebarDebugMetrics.resetForTesting()
        snapshot = SidebarDebugMetrics.snapshot(dragState: dragState)
        XCTAssertEqual(snapshot.liveInteractiveItemViewCount, 0)
        XCTAssertEqual(snapshot.interactiveOwnerHostingViewCreatedCount, 0)
        XCTAssertEqual(snapshot.mountedCollapsedSidebarHostCount, 0)
        XCTAssertEqual(snapshot.collapsedHiddenMountedSidebarHostCount, 0)
        XCTAssertEqual(snapshot.hardSidebarInputRehydrateCount, 0)
    }

    func testDockedRightClickOnlyContextMenuModifierAvoidsHeavyOwnerMetricsComparedToDragSurface() {
        SidebarDebugMetrics.resetForTesting()
        let (leanWindow, leanHost) = mountSidebarInputHost(
            presentationContext: .docked(sidebarWidth: 280)
        ) {
            Color.clear
                .frame(width: 80, height: 36)
                .sidebarAppKitContextMenu(entries: {
                    [.action(SidebarContextMenuAction(title: "Open", action: {}))]
                })
        }
        let leanSnapshot = SidebarDebugMetrics.snapshot()
        unmountSidebarInputHost(window: leanWindow, host: leanHost)

        SidebarDebugMetrics.resetForTesting()
        let (heavyWindow, heavyHost) = mountSidebarInputHost(
            presentationContext: .docked(sidebarWidth: 280)
        ) {
            Color.clear
                .frame(width: 80, height: 36)
                .sidebarAppKitContextMenu(
                    dragSource: SidebarDragSourceConfiguration(
                        item: SumiDragItem(tabId: UUID(), title: "Drag"),
                        sourceZone: .spaceRegular(UUID()),
                        previewKind: .row
                    ),
                    entries: {
                        [.action(SidebarContextMenuAction(title: "Open", action: {}))]
                    }
                )
        }
        let heavySnapshot = SidebarDebugMetrics.snapshot()
        unmountSidebarInputHost(window: heavyWindow, host: heavyHost)
        SidebarDebugMetrics.resetForTesting()

        XCTAssertEqual(leanSnapshot.liveInteractiveItemViewCount, 0)
        XCTAssertEqual(leanSnapshot.liveSidebarAppKitItemBridgeCount, 0)
        XCTAssertEqual(leanSnapshot.liveInteractiveOwnerAttachmentCount, 0)
        XCTAssertEqual(leanSnapshot.interactiveOwnerHostingViewCreatedCount, 0)
        XCTAssertGreaterThan(heavySnapshot.liveInteractiveItemViewCount, 0)
        XCTAssertGreaterThan(heavySnapshot.liveSidebarAppKitItemBridgeCount, 0)
        XCTAssertGreaterThan(heavySnapshot.liveInteractiveOwnerAttachmentCount, 0)
        XCTAssertGreaterThan(
            heavySnapshot.interactiveOwnerHostingViewCreatedCount,
            leanSnapshot.interactiveOwnerHostingViewCreatedCount
        )
    }

    func testCollapsedOverlayRightClickOnlyContextMenuModifierKeepsHeavyOwnerMetrics() {
        SidebarDebugMetrics.resetForTesting()
        let (window, host) = mountSidebarInputHost(
            presentationContext: .collapsedVisible(sidebarWidth: 280)
        ) {
            Color.clear
                .frame(width: 80, height: 36)
                .sidebarAppKitContextMenu(entries: {
                    [.action(SidebarContextMenuAction(title: "Open", action: {}))]
                })
        }
        let snapshot = SidebarDebugMetrics.snapshot()
        unmountSidebarInputHost(window: window, host: host)
        SidebarDebugMetrics.resetForTesting()

        XCTAssertGreaterThan(snapshot.liveInteractiveItemViewCount, 0)
        XCTAssertGreaterThan(snapshot.liveSidebarAppKitItemBridgeCount, 0)
        XCTAssertGreaterThan(snapshot.liveInteractiveOwnerAttachmentCount, 0)
        XCTAssertGreaterThan(snapshot.interactiveOwnerHostingViewCreatedCount, 0)
    }

    func testSidebarDebugMetricsRecordsTypedHardInputRecoveryReasons() {
        SidebarDebugMetrics.resetForTesting()
        let windowState = BrowserWindowState()

        windowState.scheduleSidebarInputRehydrate(reason: .explicitFallback)
        windowState.scheduleSidebarInputRehydrate(reason: .ownerUnresolvedAfterSoftRecovery)
        drainMainRunLoop()

        let snapshot = SidebarDebugMetrics.snapshot()
        XCTAssertEqual(snapshot.hardSidebarInputRehydrateCount, 2)
        XCTAssertEqual(snapshot.hardSidebarInputRehydrateReasons[SidebarInputRecoveryReason.explicitFallback.description], 1)
        XCTAssertEqual(snapshot.hardSidebarInputRehydrateReasons[SidebarInputRecoveryReason.ownerUnresolvedAfterSoftRecovery.description], 1)
        SidebarDebugMetrics.resetForTesting()
    }
    #endif

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

    func testSidebarHoverOverlayDragPinningPolicyPinsOnlyActiveCollapsedInternalDrag() {
        let windowID = UUID()

        XCTAssertTrue(
            SidebarHoverOverlayDragPinningPolicy.shouldPinHoverSidebar(
                activeWindowID: windowID,
                currentWindowID: windowID,
                isSidebarVisible: false,
                isDragging: true,
                isInternalDragSession: true
            )
        )
        XCTAssertFalse(
            SidebarHoverOverlayDragPinningPolicy.shouldPinHoverSidebar(
                activeWindowID: windowID,
                currentWindowID: windowID,
                isSidebarVisible: false,
                isDragging: true,
                isInternalDragSession: false
            )
        )
        XCTAssertFalse(
            SidebarHoverOverlayDragPinningPolicy.shouldPinHoverSidebar(
                activeWindowID: windowID,
                currentWindowID: windowID,
                isSidebarVisible: true,
                isDragging: true,
                isInternalDragSession: true
            )
        )
        XCTAssertFalse(
            SidebarHoverOverlayDragPinningPolicy.shouldPinHoverSidebar(
                activeWindowID: UUID(),
                currentWindowID: windowID,
                isSidebarVisible: false,
                isDragging: true,
                isInternalDragSession: true
            )
        )
        XCTAssertFalse(
            SidebarHoverOverlayDragPinningPolicy.shouldPinHoverSidebar(
                activeWindowID: windowID,
                currentWindowID: windowID,
                isSidebarVisible: false,
                isDragging: false,
                isInternalDragSession: true
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

        XCTAssertTrue(interactionState.freezesSidebarHoverState)
        XCTAssertFalse(interactionState.allowsSidebarSwipeCapture)
        XCTAssertTrue(coordinator.hasPinnedTransientUI(for: coordinator.windowID))

        coordinator.endSession(dialogToken)

        XCTAssertFalse(interactionState.freezesSidebarHoverState)
        XCTAssertTrue(interactionState.allowsSidebarSwipeCapture)
        XCTAssertFalse(coordinator.hasPinnedTransientUI(for: coordinator.windowID))
    }

    func testUrlHubPopoverTransientSessionPinsCollapsedSidebar() {
        let interactionState = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
        let window = makeWindow()
        let source = coordinator.preparedPresentationSource(window: window)

        let token = coordinator.beginSession(
            kind: .urlHubPopover,
            source: source,
            path: "test.url-hub"
        )

        XCTAssertEqual(interactionState.activeKindsDescription, "urlHubPopover")
        XCTAssertTrue(interactionState.freezesSidebarHoverState)
        XCTAssertFalse(interactionState.allowsSidebarSwipeCapture)
        XCTAssertFalse(interactionState.allowsSidebarDragSourceHitTesting)
        XCTAssertTrue(coordinator.hasPinnedTransientUI(for: coordinator.windowID))

        coordinator.endSession(token)

        XCTAssertEqual(interactionState.activeKindsDescription, "none")
        XCTAssertFalse(interactionState.freezesSidebarHoverState)
        XCTAssertTrue(interactionState.allowsSidebarSwipeCapture)
        XCTAssertTrue(interactionState.allowsSidebarDragSourceHitTesting)
        XCTAssertFalse(coordinator.hasPinnedTransientUI(for: coordinator.windowID))
    }

    func testSidebarTransientSessionCoordinatorRecoveryTargetsSourceWindowAndOwnerOnly() {
        let interactionState = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
        let spy = SidebarHostRecoverySpy()
        var inputRecoveryReasons: [SidebarInputRecoveryReason] = []
        coordinator.sidebarRecoveryCoordinator = spy
        coordinator.scheduleSidebarInputRehydrate = { inputRecoveryReasons.append($0) }
        coordinator.recoverSidebarInteractiveOwners = { _, source in
            XCTAssertNotNil(source.interactiveOwnerRecoveryMetadata)
            return SidebarInteractiveOwnerRecoveryResult(
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
        var inputRecoveryReasons: [SidebarInputRecoveryReason] = []
        coordinator.sidebarRecoveryCoordinator = spy
        coordinator.scheduleSidebarInputRehydrate = { inputRecoveryReasons.append($0) }
        coordinator.recoverSidebarInteractiveOwners = { _, source in
            XCTAssertNotNil(source.interactiveOwnerRecoveryMetadata)
            return SidebarInteractiveOwnerRecoveryResult(
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
        var inputRecoveryReasons: [SidebarInputRecoveryReason] = []
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
        var inputRecoveryReasons: [SidebarInputRecoveryReason] = []
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
        var inputRecoveryReasons: [SidebarInputRecoveryReason] = []
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
        XCTAssertTrue(interactionState.allowsSidebarSwipeCapture)
        XCTAssertTrue(inputRecoveryReasons.isEmpty)
        XCTAssertEqual(interactiveOwnerRecoveryWindows.count, 2)
        XCTAssertTrue(interactiveOwnerRecoveryWindows.allSatisfy { $0 === sourceWindow })
        XCTAssertEqual(spy.recoveredWindows.count, 2)
        XCTAssertTrue(spy.recoveredWindows.allSatisfy { $0 === sourceWindow })
    }

    func testSidebarTransientSessionCoordinatorStructuralMenuActionStaysSoftWhenOwnerRecovers() {
        let interactionState = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
        let spy = SidebarHostRecoverySpy()
        var inputRecoveryReasons: [SidebarInputRecoveryReason] = []
        coordinator.sidebarRecoveryCoordinator = spy
        coordinator.scheduleSidebarInputRehydrate = { inputRecoveryReasons.append($0) }
        coordinator.recoverSidebarInteractiveOwners = { _, source in
            XCTAssertNotNil(source.interactiveOwnerRecoveryMetadata)
            return SidebarInteractiveOwnerRecoveryResult(
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
        XCTAssertTrue(inputRecoveryReasons.isEmpty)
    }

    func testSidebarTransientSessionCoordinatorSoftRecoveryStaysSoftWhenSourceOwnerRemainsResolvable() {
        let interactionState = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
        let spy = SidebarHostRecoverySpy()
        var inputRecoveryReasons: [SidebarInputRecoveryReason] = []
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
        var inputRecoveryReasons: [SidebarInputRecoveryReason] = []
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
        XCTAssertEqual(inputRecoveryReasons, [.ownerUnresolvedAfterSoftRecovery])
    }

    func testSidebarTransientSessionCoordinatorSoftRecoveryEscalatesWhenOwnerRecoveryFindsNoLiveOwners() {
        let interactionState = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
        let spy = SidebarHostRecoverySpy()
        var inputRecoveryReasons: [SidebarInputRecoveryReason] = []
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
        XCTAssertEqual(inputRecoveryReasons, [.ownerUnresolvedAfterSoftRecovery])
    }

    func testWorkspaceThemePickerUncoordinatedDismissRecoveryStaysSoftWhenOwnerResolves() {
        let windowState = BrowserWindowState()
        let window = makeWindow()
        windowState.window = window
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
        ownerView.contextMenuController = windowState.sidebarContextMenuController
        window.contentView?.addSubview(ownerView)
        let source = SidebarTransientPresentationSource(
            windowID: windowState.id,
            window: window,
            originOwnerView: ownerView,
            coordinator: nil
        )
        let spy = SidebarHostRecoverySpy()

        WorkspaceThemePickerPopoverPresenter.performUncoordinatedSidebarDismissRecovery(
            windowState: windowState,
            source: source,
            anchor: ownerView,
            using: spy
        )
        drainMainRunLoop()

        XCTAssertEqual(windowState.sidebarInputRecoveryGeneration, 0)
        XCTAssertTrue(windowState.sidebarInteractionState.allowsSidebarDragSourceHitTesting)
        XCTAssertEqual(spy.recoveredWindows.count, 1)
        XCTAssertEqual(spy.recoveredAnchors.count, 1)
        XCTAssertTrue(
            windowState.sidebarContextMenuController.interactiveOwner(
                at: NSPoint(x: 12, y: 12),
                in: window,
                eventType: .leftMouseDown
            ) === ownerView
        )
    }

    func testWorkspaceThemePickerUncoordinatedDismissRecoveryHardRehydratesWhenOwnerUnresolved() {
        let windowState = BrowserWindowState()
        let window = makeWindow()
        windowState.window = window
        var ownerView: SidebarInteractiveItemView? = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 80, height: 36)
        )
        ownerView?.update(
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
        window.contentView?.addSubview(ownerView!)
        let source = SidebarTransientPresentationSource(
            windowID: windowState.id,
            window: window,
            originOwnerView: ownerView,
            coordinator: nil
        )
        ownerView?.removeFromSuperview()
        ownerView = nil

        WorkspaceThemePickerPopoverPresenter.performUncoordinatedSidebarDismissRecovery(
            windowState: windowState,
            source: source,
            anchor: source.originOwnerView,
            using: SidebarHostRecoverySpy()
        )
        drainMainRunLoop()

        XCTAssertEqual(windowState.sidebarInputRecoveryGeneration, 1)
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

        windowState.scheduleSidebarInputRehydrate(reason: .menuEnded)
        windowState.scheduleSidebarInputRehydrate(reason: .popoverDismissed)

        XCTAssertEqual(windowState.sidebarInputRecoveryGeneration, 0)

        drainMainRunLoop()

        XCTAssertEqual(windowState.sidebarInputRecoveryGeneration, 1)

        windowState.scheduleSidebarInputRehydrate(reason: .explicitFallback)
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
            presentPicker: { session, _ in presentedSession = session },
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

    func testWorkspaceAppearanceServiceCreatesFallbackThemePickerSourceForMenuEntryPoints() {
        let service = WorkspaceAppearanceService()
        let space = Space(name: "Personal")

        let hostWindow = BrowserWindowState()
        hostWindow.currentSpaceId = space.id
        hostWindow.window = makeWindow()

        let registry = WindowRegistry()
        registry.register(hostWindow)
        registry.setActive(hostWindow)

        var presentedSession: WorkspaceThemePickerSession?
        var presentedWindowState: BrowserWindowState?
        let context = WorkspaceAppearanceService.Context(
            currentSpace: { space },
            spaceLookup: { $0 == space.id ? space : nil },
            windowRegistry: { registry },
            commitWorkspaceTheme: { _, _ in },
            syncWorkspaceThemeAcrossWindows: { _, _ in },
            scheduleStructuralPersistence: {},
            presentPicker: { session, windowState in
                presentedSession = session
                presentedWindowState = windowState
            },
            showDialog: { _, _ in
                XCTFail("Theme picker should present when a matching browser window exists")
            },
            closeDialog: {}
        )

        service.showGradientEditor(using: context)

        XCTAssertEqual(presentedWindowState?.id, hostWindow.id)
        XCTAssertEqual(presentedSession?.hostWindowID, hostWindow.id)
        XCTAssertEqual(presentedSession?.transientSessionToken?.kind, .themePicker)
        XCTAssertTrue(hostWindow.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: hostWindow.id))

        hostWindow.sidebarTransientSessionCoordinator.finishSession(
            presentedSession?.transientSessionToken,
            reason: "WorkspaceAppearanceServiceTests"
        )
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
            presentPicker: { _, _ in
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

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func source(named relativePath: String) throws -> String {
        try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
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
        location: NSPoint = NSPoint(x: 5, y: 5),
        windowNumber: Int = 0
    ) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
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

    private func runMainRunLoopBriefly() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }

    #if DEBUG
    private func mountSidebarInputHost<Content: View>(
        presentationContext: SidebarPresentationContext,
        @ViewBuilder content: () -> Content
    ) -> (window: NSWindow, host: NSHostingView<AnyView>) {
        let windowState = BrowserWindowState()
        let rootView = AnyView(
            content()
                .environment(windowState)
                .environment(\.sidebarPresentationContext, presentationContext)
        )
        let host = NSHostingView(rootView: rootView)
        host.frame = NSRect(x: 0, y: 0, width: 120, height: 60)

        let window = makeWindow()
        window.contentView?.addSubview(host)
        host.layoutSubtreeIfNeeded()
        drainMainRunLoop()
        return (window, host)
    }

    private func unmountSidebarInputHost(
        window: NSWindow,
        host: NSHostingView<AnyView>
    ) {
        host.removeFromSuperview()
        window.close()
        drainMainRunLoop()
    }
    #endif

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
