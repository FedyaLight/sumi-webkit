import AppKit
@testable import Sumi
import SwiftUI
import XCTest

@MainActor
final class SidebarZenMotionTests: XCTestCase {
    func testFolderCollapseHasStickyDestinationOnItsFirstFrame() {
        let selectedID = UUID()

        XCTAssertEqual(
            SidebarFolderDisplayProjection.disclosureTargetStickyItemIDs(
                currentStickyItemIDs: [],
                selectedDescendantItemID: selectedID
            ),
            [selectedID]
        )
    }

    func testSidebarMotionPolicyUsesReducedMotionContract() {
        XCTAssertEqual(SidebarMotionPolicy.currentMode(reduceMotion: true), .reducedMotion)
        XCTAssertNil(SidebarMotionPolicy.dockedLayoutAnimation(for: .reducedMotion, isShowing: true))
        let overlayMotion = SidebarMotionPolicy.overlayMotion(for: .reducedMotion)
        XCTAssertFalse(overlayMotion.usesTravel)
        XCTAssertEqual(overlayMotion.shadowDuration, 0)
        XCTAssertNil(SidebarMotionPolicy.contentLayoutAnimation(for: .reducedMotion))
    }

    func testSidebarMotionPolicyKeepsStandardShellMotion() {
        XCTAssertEqual(SidebarMotionPolicy.currentMode(reduceMotion: false), .standard)
        XCTAssertNotNil(SidebarMotionPolicy.dockedLayoutAnimation(for: .standard, isShowing: true))
        let overlayMotion = SidebarMotionPolicy.overlayMotion(for: .standard)
        XCTAssertTrue(overlayMotion.usesTravel)
        XCTAssertEqual(overlayMotion.shadowDuration, 0.22)
        XCTAssertNotNil(SidebarMotionPolicy.contentLayoutAnimation(for: .standard))
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

        XCTAssertTrue(state.presentsPressVisual(for: "tab-row-test"))
    }

    func testSidebarInteractiveItemActivatesPageOnMouseDownOnlyOnce() {
        let state = SidebarInteractionState()
        let dragState = SidebarDragState()
        let spaceID = UUID()
        var activationCount = 0
        let view = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 160, height: 36)
        )
        view.sidebarDragState = dragState
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(
                        tabId: UUID(),
                        title: "Press activation"
                    ),
                    sourceZone: .spaceRegular(spaceID),
                    previewKind: .row
                ),
                pageActivation: { activationCount += 1 },
                sourceID: "tab-row-test"
            )
        )

        view.mouseDown(with: mouseEvent(.leftMouseDown))

        XCTAssertEqual(activationCount, 1)
        XCTAssertTrue(state.hasActivePointerSession(for: "tab-row-test"))
        XCTAssertTrue(dragState.isInternalDragGeometryArmed)

        view.mouseUp(
            with: mouseEvent(
                .leftMouseUp,
                location: NSPoint(x: 180, y: 12)
            )
        )

        XCTAssertEqual(activationCount, 1)
    }

    func testPageActivationDoesNotRunInsideNestedControlExclusionZone() {
        let state = SidebarInteractionState()
        let spaceID = UUID()
        var activationCount = 0
        let view = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 160, height: 36)
        )
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(
                        tabId: UUID(),
                        title: "Nested control exclusion"
                    ),
                    sourceZone: .spaceRegular(spaceID),
                    previewKind: .row,
                    exclusionZones: [.trailingStrip(40)]
                ),
                primaryActionExclusionZones: [.trailingStrip(40)],
                pageActivation: { activationCount += 1 },
                sourceID: "tab-row-test"
            )
        )

        view.mouseDown(
            with: mouseEvent(
                .leftMouseDown,
                location: NSPoint(x: 140, y: 12)
            )
        )

        XCTAssertEqual(activationCount, 0)
        XCTAssertFalse(state.hasActivePointerSession)
    }

    func testNestedControlExclusionDoesNotDependOnDragSource() {
        let state = SidebarInteractionState()
        var activationCount = 0
        let view = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 160, height: 36)
        )
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                primaryActionExclusionZones: [.trailingStrip(40)],
                pageActivation: { activationCount += 1 },
                sourceID: "launcher-row-without-drag-source"
            )
        )

        view.mouseDown(
            with: mouseEvent(
                .leftMouseDown,
                location: NSPoint(x: 140, y: 12)
            )
        )

        XCTAssertEqual(activationCount, 0)
        XCTAssertFalse(state.hasActivePointerSession)
    }

    func testPageActivationPresentationChurnCannotBecomeReleaseAction() {
        let state = SidebarInteractionState()
        var originalActivationCount = 0
        var currentActivationCount = 0
        let view = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 160, height: 36)
        )
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                pageActivation: { originalActivationCount += 1 },
                sourceID: "launcher-row-test"
            )
        )

        view.mouseDown(with: mouseEvent(.leftMouseDown))
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                releaseAction: { currentActivationCount += 1 },
                sourceID: "launcher-row-test"
            )
        )
        view.mouseUp(with: mouseEvent(.leftMouseUp))

        XCTAssertEqual(originalActivationCount, 1)
        XCTAssertEqual(currentActivationCount, 0)
        XCTAssertFalse(state.hasActivePointerSession)
    }

    func testPageActivationKeepsPressedSessionWhenPresentationReplacesOwner() {
        let state = SidebarInteractionState()
        let dragState = SidebarDragState()
        let sourceID = "launcher-row-test"
        let spaceID = UUID()
        let dragItem = SumiDragItem(
            tabId: UUID(),
            title: "Replacing launcher"
        )
        let originalView = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 160, height: 36)
        )
        let replacementView = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 160, height: 36)
        )
        originalView.sidebarDragState = dragState
        replacementView.sidebarDragState = dragState
        originalView.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                dragSource: SidebarDragSourceConfiguration(
                    item: dragItem,
                    sourceZone: .spaceRegular(spaceID),
                    previewKind: .row
                ),
                pageActivation: { /* no-op */ },
                sourceID: sourceID
            )
        )

        originalView.mouseDown(with: mouseEvent(.leftMouseDown))
        replacementView.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                dragSource: SidebarDragSourceConfiguration(
                    item: dragItem,
                    sourceZone: .spaceRegular(spaceID),
                    previewKind: .row
                ),
                pageActivation: { /* no-op */ },
                sourceID: sourceID
            )
        )
        originalView.prepareForDismantle()

        XCTAssertTrue(state.hasActivePointerSession(for: sourceID))
        XCTAssertTrue(dragState.isInternalDragGeometryArmed)

        replacementView.mouseUp(with: mouseEvent(.leftMouseUp))

        XCTAssertFalse(state.hasActivePointerSession)
        XCTAssertFalse(dragState.isInternalDragGeometryArmed)
    }

    func testLauncherPresentationReplacementKeepsPressedSessionUntilMouseUp() throws {
        let state = SidebarInteractionState()
        let coordinator = SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: state
        )
        let controller = SidebarContextMenuController(
            interactionState: state,
            transientSessionCoordinator: coordinator
        )
        let presentation = SidebarPressReplacementPresentation()
        let host = NSHostingView(
            rootView: SidebarPressReplacementFixture(
                presentation: presentation,
                state: state,
                controller: controller
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 36),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = window.contentView?.bounds ?? .zero
        host.layoutSubtreeIfNeeded()
        let originalOwner = try XCTUnwrap(
            interactiveItemViews(in: host).first
        )
        defer {
            interactiveItemViews(in: host).forEach { $0.prepareForDismantle() }
            window.contentView = nil
            window.close()
        }

        originalOwner.mouseDown(with: mouseEvent(.leftMouseDown))
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(presentation.phase, .gap)
        XCTAssertTrue(interactiveItemViews(in: host).isEmpty)
        XCTAssertTrue(state.hasActivePointerSession(for: "launcher-row-test"))

        presentation.phase = .live
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        host.layoutSubtreeIfNeeded()

        let currentOwner = try XCTUnwrap(
            interactiveItemViews(in: host).first
        )
        XCTAssertNotIdentical(currentOwner, originalOwner)

        currentOwner.mouseUp(with: mouseEvent(.leftMouseUp))

        XCTAssertFalse(state.hasActivePointerSession)
    }

    func testMouseUpEndsPressedSessionWhilePresentationOwnerIsDetached() {
        let state = SidebarInteractionState()
        let owner = makeInteractiveItemView(
            sourceID: "launcher-row-test",
            state: state
        )

        owner.mouseDown(with: mouseEvent(.leftMouseDown))
        owner.prepareForDismantle()

        XCTAssertTrue(state.hasActivePointerSession(for: "launcher-row-test"))
        XCTAssertTrue(
            state.pointerSessions.continueEvent(
                mouseEvent(.leftMouseUp)
            )
        )

        XCTAssertFalse(state.hasActivePointerSession)
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

        XCTAssertEqual(activationCount, 0)

        view.mouseUp(with: mouseEvent(.leftMouseUp))

        XCTAssertFalse(state.hasActivePointerSession)
        XCTAssertEqual(activationCount, 1)
    }

    func testSidebarInteractiveItemClearsPressedSourceOnCancelTracking() {
        let state = SidebarInteractionState()
        let view = makeInteractiveItemView(
            sourceID: "tab-row-test",
            state: state
        )

        view.mouseDown(with: mouseEvent(.leftMouseDown))
        view.cancelPointerSession()

        XCTAssertFalse(state.hasActivePointerSession)
    }

    /// Opening or closing the folder preview writes the transient interaction
    /// state, which re-renders every folder header mid-click. That re-render
    /// reaches the bridge with an unchanged signature, and must leave the row's
    /// in-flight gesture alone — otherwise the click never reaches its action.
    func testBridgeUpdateDuringPressKeepsReleaseActionAlive() {
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
                releaseAction: action,
                sourceID: "folder-header-test"
            )
        )
        view.mouseUp(with: mouseEvent(.leftMouseUp))

        XCTAssertEqual(activationCount, 1)
        XCTAssertFalse(state.hasActivePointerSession)
    }

    func testPresentationConfigurationChurnDuringPressKeepsCurrentReleaseActionAlive() {
        let state = SidebarInteractionState()
        let itemID = UUID()
        let spaceID = UUID()
        var originalActivationCount = 0
        var currentActivationCount = 0
        let view = SidebarInteractiveItemView(
            frame: NSRect(x: 0, y: 0, width: 160, height: 36)
        )
        view.sidebarDragState = SidebarDragState()
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                menu: SidebarContextMenuLeafConfiguration(
                    isEnabled: true,
                    surfaceKind: .row,
                    triggers: .rightClick,
                    entries: { [] },
                    onMenuVisibilityChanged: { _ in /* no-op */ }
                ),
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem.folder(folderId: itemID, title: "Before"),
                    sourceZone: .spacePinned(spaceID),
                    previewKind: .folderRow
                ),
                releaseAction: { originalActivationCount += 1 },
                sourceID: "folder-header-\(itemID.uuidString)"
            )
        )

        view.mouseDown(with: mouseEvent(.leftMouseDown))
        view.update(
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                menu: SidebarContextMenuLeafConfiguration(
                    isEnabled: false,
                    surfaceKind: .row,
                    triggers: [.leftClick, .rightClick],
                    entries: { [] },
                    onMenuVisibilityChanged: { _ in /* no-op */ }
                ),
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem.folder(folderId: itemID, title: "After"),
                    sourceZone: .folder(UUID()),
                    previewKind: .row
                ),
                releaseAction: { currentActivationCount += 1 },
                sourceID: "folder-header-\(itemID.uuidString)",
                suppressesActionAnimation: true,
                presentationMode: .collapsedVisible
            )
        )
        view.mouseUp(with: mouseEvent(.leftMouseUp))

        XCTAssertEqual(originalActivationCount, 0)
        XCTAssertEqual(currentActivationCount, 1)
        XCTAssertFalse(state.hasActivePointerSession)
    }

    func testBridgeReuseForDifferentSourceCancelsInFlightReleaseAction() {
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
                releaseAction: { secondActivationCount += 1 },
                sourceID: "folder-header-second"
            )
        )

        XCTAssertFalse(state.hasActivePointerSession)

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
        XCTAssertTrue(state.hasActivePointerSession(for: "folder-child-test"))
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
                releaseAction: { /* no-op */ },
                sourceID: "folder-header-test"
            )
        )
        view.cancelPointerSession()

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

        XCTAssertTrue(state.hasActivePointerSession(for: "tab-row-test"))
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
        XCTAssertTrue(state.hasActivePointerSession(for: "folder-child-current"))
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
        let interactionState = SidebarInteractionState()
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
                interactionState: interactionState,
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

        view.cancelPointerSession()

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

    func testInteractiveOwnerRoutesOnlyTheVisiblePartOfAClippedRow() {
        let state = SidebarInteractionState()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false

        let sidebarHost = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 160))
        let clippedViewport = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 60))
        clippedViewport.clipsToBounds = true
        let rowOwner = makeInteractiveItemView(
            sourceID: "partially-clipped-row",
            state: state
        )
        rowOwner.frame = NSRect(x: 0, y: 40, width: 200, height: 40)

        window.contentView = sidebarHost
        sidebarHost.addSubview(clippedViewport)
        clippedViewport.addSubview(rowOwner)
        state.registerInteractiveOwner(rowOwner)
        defer {
            state.unregisterInteractiveOwner(rowOwner)
            rowOwner.prepareForDismantle()
            window.contentView = nil
            window.close()
        }

        let visibleHit = state.interactiveOwner(
            at: NSPoint(x: 20, y: 50),
            in: window,
            eventType: .leftMouseDown,
            hostedSidebarView: sidebarHost
        )
        let clippedHit = state.interactiveOwner(
            at: NSPoint(x: 20, y: 70),
            in: window,
            eventType: .leftMouseDown,
            hostedSidebarView: sidebarHost
        )

        XCTAssertTrue(visibleHit === rowOwner)
        XCTAssertNil(clippedHit)
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
                releaseAction: action,
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

@MainActor
private final class SidebarPressReplacementPresentation: ObservableObject {
    enum Phase: Equatable {
        case stored
        case gap
        case live
    }

    @Published var phase: Phase = .stored
}

private struct SidebarPressReplacementFixture: View {
    @ObservedObject var presentation: SidebarPressReplacementPresentation
    let state: SidebarInteractionState
    let controller: SidebarContextMenuController

    var body: some View {
        Group {
            switch presentation.phase {
            case .stored, .live:
                interactiveOwner
            case .gap:
                Color.clear
            }
        }
        .frame(width: 160, height: 36)
    }

    private var interactiveOwner: some View {
        SidebarAppKitItemBridge(
            controller: controller,
            configuration: SidebarAppKitItemConfiguration(
                interactionState: state,
                pageActivation: { presentation.phase = .gap },
                sourceID: "launcher-row-test"
            )
        )
    }
}

@MainActor
private func interactiveItemViews(in root: NSView) -> [SidebarInteractiveItemView] {
    let directMatches = root.subviews.compactMap { $0 as? SidebarInteractiveItemView }
    return directMatches + root.subviews.flatMap(interactiveItemViews)
}
