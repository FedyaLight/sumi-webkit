//
//  SidebarInteractiveItemView.swift
//  Sumi
//

import AppKit
import SwiftUI

@MainActor
final class SidebarInteractiveItemView: NSView, NSDraggingSource {
    var sidebarDragState: SidebarDragState?

    weak var contextMenuController: SidebarContextMenuController? {
        didSet {
            guard oldValue !== contextMenuController else { return }
            oldValue?.ownerViewDidDetach(self)
            contextMenuController?.ownerViewDidAttach(self)
        }
    }

    private(set) var isInteractive = true
    private var itemConfiguration = SidebarAppKitItemConfiguration()
    private var middleMouseDownPoint: CGPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var isOpaque: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        contextMenuController?.ownerViewDidAttach(self)
        pointerSessionAuthority?.present(
            sourceID: itemConfiguration.sourceID,
            with: self,
            release: configuredReleaseIntent
        )
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            pointerSessionAuthority?.detach(self)
            contextMenuController?.ownerViewDidDetach(self)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func update(configuration: SidebarAppKitItemConfiguration) {
        let previousSignature = itemConfiguration.bridgeUpdateSignature
        let nextSignature = configuration.bridgeUpdateSignature
        let didChangeConfiguration = previousSignature != nextSignature
        let didReplaceInteraction =
            itemConfiguration.interactionIdentity != configuration.interactionIdentity

        if didReplaceInteraction {
            middleMouseDownPoint = nil
        }
        itemConfiguration = configuration
        pointerSessionAuthority?.present(
            sourceID: configuration.sourceID,
            with: self,
            release: configuredReleaseIntent
        )
        guard didChangeConfiguration else { return }

        isInteractive = configuration.isInteractionEnabled
        identifier = configuration.sourceID.map { NSUserInterfaceItemIdentifier($0) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive, bounds.contains(point) else { return nil }
        let event = window?.currentEvent
        let captures = shouldCaptureInteraction(
            at: point,
            eventType: event?.type,
            eventButtonNumber: event?.buttonNumber
        )
        if captures {
            return self
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if shouldPresentMenu(trigger: .leftMouseDown, at: point) {
            presentContextMenu(trigger: .leftMouseDown, event: event)
            return
        }

        let capturesPageActivation = shouldCapturePageActivation(at: point)
        let capturesReleaseAction = shouldCaptureReleaseAction(at: point)
        let capturesDrag = shouldCaptureDrag(at: point)

        if capturesPageActivation || capturesReleaseAction || capturesDrag {
            window?.makeFirstResponder(self)
            pointerSessionAuthority?.begin(
                event: event,
                owner: self,
                intent: primaryPointerIntent(
                    capturesDrag: capturesDrag,
                    capturesReleaseAction: capturesReleaseAction
                )
            )
            if capturesPageActivation {
                performAction(itemConfiguration.pageActivation)
            }
            return
        }

        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if pointerSessionAuthority?.continueEvent(
            event,
            deliveredTo: self
        ) == true {
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if pointerSessionAuthority?.continueEvent(
            event,
            deliveredTo: self
        ) == true {
            return
        }
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard shouldPresentMenu(trigger: .rightMouseDown, at: point) else {
            super.rightMouseDown(with: event)
            return
        }
        presentContextMenu(trigger: .rightMouseDown, event: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard shouldHandleMiddleClick(event, at: point) else {
            super.otherMouseDown(with: event)
            return
        }

        window?.makeFirstResponder(self)
        middleMouseDownPoint = point
    }

    override func otherMouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard middleMouseDownPoint != nil else {
            super.otherMouseUp(with: event)
            return
        }
        defer { middleMouseDownPoint = nil }

        guard shouldHandleMiddleClick(event, at: point) else {
            return
        }
        itemConfiguration.onMiddleClick?()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        pointerSessionAuthority?.nativeDragEnded(from: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        movedTo screenPoint: NSPoint
    ) {
        pointerSessionAuthority?.nativeDragMoved(
            from: self,
            to: screenPoint
        )
    }

    func cancelPointerSession() {
        pointerSessionAuthority?.cancel(presentedBy: self)
    }

    func prepareForDismantle() {
        pointerSessionAuthority?.detach(self)
        isInteractive = false
        itemConfiguration = SidebarAppKitItemConfiguration()
        contextMenuController = nil
        middleMouseDownPoint = nil
    }

    func shouldCaptureInteraction(
        at point: NSPoint,
        eventType: NSEvent.EventType?,
        eventButtonNumber: Int? = nil
    ) -> Bool {
        guard isInteractive, bounds.contains(point) else { return false }

        switch eventType {
        case .leftMouseDown?:
            if shouldPresentMenu(trigger: .leftMouseDown, at: point) {
                return true
            }
            return shouldCapturePageActivation(at: point)
                || shouldCaptureReleaseAction(at: point)
                || shouldCaptureDrag(at: point)
        case .rightMouseDown?:
            return shouldPresentMenu(trigger: .rightMouseDown, at: point)
        case .otherMouseDown?, .otherMouseUp?:
            return eventButtonNumber == 2 && itemConfiguration.onMiddleClick != nil
        default:
            return false
        }
    }

    func routingPriority(
        at point: NSPoint,
        eventType: NSEvent.EventType?,
        eventButtonNumber: Int? = nil
    ) -> Int {
        guard isInteractive, bounds.contains(point) else { return 0 }

        let inputBonus = itemConfiguration.isInteractionEnabled
            ? 100 + itemConfiguration.routingPriorityBoost
            : 0
        switch eventType {
        case .leftMouseDown?:
            if shouldCaptureReleaseAction(at: point) {
                return inputBonus + 40
            }
            if shouldCaptureDrag(at: point) {
                return inputBonus + 30
            }
            if shouldPresentMenu(trigger: .leftMouseDown, at: point) {
                return inputBonus + 20
            }
            if shouldCapturePageActivation(at: point) {
                return inputBonus + 10
            }
        case .rightMouseDown?:
            if shouldPresentMenu(trigger: .rightMouseDown, at: point) {
                return inputBonus + 20
            }
        case .otherMouseDown?, .otherMouseUp?:
            if eventButtonNumber == 2, itemConfiguration.onMiddleClick != nil {
                return inputBonus + 10
            }
        default:
            break
        }

        return 0
    }

    private func shouldPresentMenu(
        trigger: SidebarContextMenuMouseTrigger,
        at point: NSPoint
    ) -> Bool {
        guard bounds.contains(point),
              let menu = itemConfiguration.menu,
              menu.isEnabled,
              SidebarContextMenuRoutingPolicy.shouldIntercept(trigger, triggers: menu.triggers)
        else {
            return false
        }
        return menu.entries().isEmpty == false
    }

    private func shouldCaptureDrag(at point: NSPoint) -> Bool {
        guard let configuration = itemConfiguration.dragSource,
              configuration.isEnabled,
              allowsTransientDragSourceHitTesting,
              bounds.contains(point)
        else {
            return false
        }

        return !configuration.exclusionZones.contains { $0.contains(point, in: bounds) }
    }

    private func shouldCapturePageActivation(at point: NSPoint) -> Bool {
        guard itemConfiguration.pageActivation != nil,
              bounds.contains(point)
        else {
            return false
        }

        return !isInActionExclusionZone(point)
    }

    private func shouldCaptureReleaseAction(at point: NSPoint) -> Bool {
        guard itemConfiguration.releaseAction != nil,
              bounds.contains(point)
        else {
            return false
        }

        return !isInActionExclusionZone(point)
    }

    private func isInActionExclusionZone(_ point: NSPoint) -> Bool {
        itemConfiguration.primaryActionExclusionZones.contains {
            $0.contains(point, in: bounds)
        }
    }

    private func shouldHandleMiddleClick(_ event: NSEvent, at point: NSPoint) -> Bool {
        guard bounds.contains(point),
              event.buttonNumber == 2,
              itemConfiguration.onMiddleClick != nil
        else {
            return false
        }
        return true
    }

    private func presentContextMenu(
        trigger: SidebarContextMenuMouseTrigger,
        event: NSEvent
    ) {
        guard let menu = itemConfiguration.menu else { return }

        contextMenuController?.presentMenu(
            SidebarContextMenuResolvedTarget(
                entries: menu.entries(),
                onMenuVisibilityChanged: menu.onMenuVisibilityChanged
            ),
            trigger: trigger,
            event: event,
            in: self
        )
    }

    private var allowsTransientDragSourceHitTesting: Bool {
        pointerInteractionState?.allowsSidebarDragSourceHitTesting ?? true
    }

    private var pointerInteractionState: SidebarInteractionState? {
        itemConfiguration.interactionState ?? contextMenuController?.interactionState
    }

    private var pointerSessionAuthority: SidebarPointerSessionAuthority? {
        pointerInteractionState?.pointerSessions
    }

    private func primaryPointerIntent(
        capturesDrag: Bool,
        capturesReleaseAction: Bool
    ) -> SidebarPrimaryPointerIntent {
        let drag: SidebarPrimaryPointerIntent.Drag?
        if capturesDrag,
           let source = itemConfiguration.dragSource,
           let sidebarDragState {
            drag = SidebarPrimaryPointerIntent.Drag(
                source: source,
                scope: itemConfiguration.dragScope,
                state: sidebarDragState
            )
        } else {
            drag = nil
        }

        return SidebarPrimaryPointerIntent(
            sourceID: itemConfiguration.sourceID,
            showsPressVisual: itemConfiguration.showsPressVisual,
            drag: drag,
            release: capturesReleaseAction ? configuredReleaseIntent : nil
        )
    }

    private var configuredReleaseIntent: SidebarPrimaryPointerIntent.Release? {
        guard let action = itemConfiguration.releaseAction else { return nil }
        return SidebarPrimaryPointerIntent.Release(
            action: action,
            exclusionZones: itemConfiguration.primaryActionExclusionZones,
            suppressesAnimation: itemConfiguration.suppressesActionAnimation
        )
    }

    private func performAction(_ action: (() -> Void)?) {
        guard let action else { return }
        if itemConfiguration.suppressesActionAnimation {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction, action)
            return
        }
        action()
    }

    var recoveryMetadata: SidebarInteractiveOwnerRecoveryMetadata {
        SidebarInteractiveOwnerRecoveryMetadata(
            ownerObjectID: ObjectIdentifier(self),
            ownerTypeName: String(describing: type(of: self)),
            dragItemID: itemConfiguration.dragSource?.item.tabId,
            dragSourceZone: itemConfiguration.dragSource?.sourceZone
        )
    }

    func recoveryResolutionReason(
        matching metadata: SidebarInteractiveOwnerRecoveryMetadata
    ) -> String? {
        if metadata.ownerObjectID == ObjectIdentifier(self) {
            return "objectIdentity"
        }

        guard let dragSource = itemConfiguration.dragSource,
              metadata.dragItemID == dragSource.item.tabId,
              metadata.dragSourceZone == dragSource.sourceZone
        else {
            return nil
        }

        return "dragKey"
    }
}
