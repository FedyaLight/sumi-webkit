//
//  SidebarInteractiveItemView.swift
//  Sumi
//

import AppKit

enum SidebarUITestDragMarker {
    private static let argumentPrefix = "--uitest-sidebar-drag-marker="

    static var markerURL: URL? {
        #if DEBUG
        ProcessInfo.processInfo.arguments.lazy.compactMap { argument -> URL? in
            guard argument.hasPrefix(argumentPrefix) else { return nil }
            let path = String(argument.dropFirst(argumentPrefix.count))
            guard path.isEmpty == false else { return nil }
            return URL(fileURLWithPath: path)
        }.first
        #else
        nil
        #endif
    }

    static func recordDragStart(
        itemID: UUID,
        sourceDescription: @autoclosure () -> String,
        ownerDescription: @autoclosure () -> String,
        sourceID: @autoclosure () -> String? = nil,
        viewDescription: @autoclosure () -> String? = nil
    ) {
        #if DEBUG
            append(
                [
                    "event=startDrag",
                    "item=\(itemID.uuidString)",
                    "sourceID=\(sourceID() ?? "nil")",
                    "source=\(sourceDescription())",
                    "view=\(viewDescription() ?? "nil")",
                    "owner=\(ownerDescription())",
                    "timestamp=\(Date().timeIntervalSince1970)",
                ]
            )
        #else
            _ = itemID
            _ = sourceDescription
            _ = ownerDescription
            _ = sourceID
            _ = viewDescription
        #endif
    }

    static func recordEvent(
        _ name: String,
        dragItemID: UUID?,
        ownerDescription: String,
        sourceID: String? = nil,
        viewDescription: String? = nil,
        details: @autoclosure () -> String
    ) {
        #if DEBUG
            append(
                [
                    "event=\(name)",
                    "dragItem=\(dragItemID?.uuidString ?? "nil")",
                    "sourceID=\(sourceID ?? "nil")",
                    "view=\(viewDescription ?? "nil")",
                    "owner=\(ownerDescription)",
                    "details=\(details())",
                    "timestamp=\(Date().timeIntervalSince1970)",
                ]
            )
        #else
            _ = name
            _ = dragItemID
            _ = ownerDescription
            _ = sourceID
            _ = viewDescription
            _ = details
        #endif
    }

    private static func append(_ fields: [String]) {
        guard let markerURL else { return }
        let message = fields.joined(separator: " ") + "\n"
        if let data = message.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: markerURL)
        {
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
            _ = try? handle.close()
            return
        }
        try? message.write(to: markerURL, atomically: true, encoding: String.Encoding.utf8)
    }
}
@MainActor
final class SidebarInteractiveItemView: NSView, NSDraggingSource, SidebarTransientInteractionDisarmable {
    private let dragThreshold: CGFloat = 3

    weak var contextMenuController: SidebarContextMenuController? {
        didSet {
            guard oldValue !== contextMenuController else { return }
            oldValue?.ownerViewDidDetach(self)
            contextMenuController?.ownerViewDidAttach(self)
        }
    }

    private(set) var isInteractive = true
    private var isConfigurationInteractionEnabled = true
    private var isTransientInteractionEnabled = true
    private var itemConfiguration = SidebarAppKitItemConfiguration()
    private var mouseDownEvent: NSEvent?
    private var mouseDownPoint: CGPoint?
    private var mouseDownCanStartDrag = false
    private var didStartDrag = false
    private var isTrackingDragGesture = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
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
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            contextMenuController?.ownerViewDidDetach(self)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func update(configuration: SidebarAppKitItemConfiguration) {
        itemConfiguration = configuration
        isConfigurationInteractionEnabled = configuration.isInteractionEnabled
        isTransientInteractionEnabled = true
        identifier = configuration.sourceID.map { NSUserInterfaceItemIdentifier($0) }
        if !configuration.supportsPrimaryMouseTracking {
            resetMouseState()
        }
        applyEffectiveInteractionEnabled()
        SidebarUITestDragMarker.recordEvent(
            "bridgeUpdate",
            dragItemID: itemConfiguration.dragSource?.item.tabId,
            ownerDescription: recoveryDebugDescription,
            sourceID: itemConfiguration.sourceID,
            viewDescription: debugViewDescription,
            details: "source=\(itemConfiguration.sourceID ?? "nil") surface=\(sidebarContextMenuSurfaceDebugDescription(itemConfiguration.surfaceKind)) mode=\(sidebarPresentationModeDebugDescription(itemConfiguration.presentationMode)) interactive=\(isInteractive) inputEnabled=\(itemConfiguration.isInteractionEnabled) view=\(debugViewDescription) hostedRoot=\(hostedSidebarRootDebugDescription) controller=\(contextMenuControllerDebugDescription)"
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive, bounds.contains(point) else { return nil }
        let eventType = window?.currentEvent?.type
        let captures = shouldCaptureInteraction(at: point, eventType: eventType)
        if eventType == .leftMouseDown || eventType == .rightMouseDown {
            SidebarUITestDragMarker.recordEvent(
                "hitTest",
                dragItemID: itemConfiguration.dragSource?.item.tabId,
                ownerDescription: recoveryDebugDescription,
                sourceID: itemConfiguration.sourceID,
                viewDescription: debugViewDescription,
                details: "source=\(itemConfiguration.sourceID ?? "nil") event=\(eventType.map(String.init(describing:)) ?? "nil") point=\(Int(point.x)),\(Int(point.y)) captures=\(captures) view=\(debugViewDescription) hostedRoot=\(hostedSidebarRootDebugDescription)"
            )
        }
        if captures {
            return self
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if shouldPresentMenu(trigger: .leftMouseDown, at: point) {
            RuntimeDiagnostics.emit(
                "🧭 Sidebar mouseDown presenting menu owner=\(recoveryDebugDescription) trigger=leftMouseDown point=\(Int(point.x)),\(Int(point.y))"
            )
            presentContextMenu(trigger: .leftMouseDown, event: event)
            return
        }

        let capturesPrimaryAction = shouldCapturePrimaryAction(at: point)
        let capturesDrag = shouldCaptureDrag(at: point)
        SidebarUITestDragMarker.recordEvent(
            "mouseDown",
            dragItemID: itemConfiguration.dragSource?.item.tabId,
            ownerDescription: recoveryDebugDescription,
            sourceID: itemConfiguration.sourceID,
            viewDescription: debugViewDescription,
            details: "source=\(itemConfiguration.sourceID ?? "nil") point=\(Int(point.x)),\(Int(point.y)) capturesPrimary=\(capturesPrimaryAction) capturesDrag=\(capturesDrag) allowsHitTesting=\(allowsTransientDragSourceHitTesting) activeKinds=\(contextMenuController?.interactionState.activeKindsDescription ?? "unknown") mode=\(sidebarPresentationModeDebugDescription(itemConfiguration.presentationMode)) surface=\(sidebarContextMenuSurfaceDebugDescription(itemConfiguration.surfaceKind)) view=\(debugViewDescription) hostedRoot=\(hostedSidebarRootDebugDescription) controller=\(contextMenuControllerDebugDescription)"
        )
        logLeftMouseCapture(
            point: point,
            capturesPrimaryAction: capturesPrimaryAction,
            capturesDrag: capturesDrag
        )

        if capturesPrimaryAction || capturesDrag {
            window?.makeFirstResponder(self)
            mouseDownEvent = event
            mouseDownPoint = point
            mouseDownCanStartDrag = capturesDrag
            didStartDrag = false
            isTrackingDragGesture = true
            if capturesDrag {
                SidebarDragState.shared.armInternalDragGeometry(
                    scope: itemConfiguration.dragScope
                )
            }
            contextMenuController?.beginPrimaryMouseTracking(self)
            trackPrimaryMouseEventsIfNeeded(after: event)
            return
        }

        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isInteractive,
              isTrackingDragGesture,
              !didStartDrag,
              let mouseDownPoint
        else {
            super.mouseDragged(with: event)
            return
        }
        guard mouseDownCanStartDrag else { return }

        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
        SidebarUITestDragMarker.recordEvent(
            "mouseDragged",
            dragItemID: itemConfiguration.dragSource?.item.tabId,
            ownerDescription: recoveryDebugDescription,
            sourceID: itemConfiguration.sourceID,
            viewDescription: debugViewDescription,
            details: "source=\(itemConfiguration.sourceID ?? "nil") distance=\(String(format: "%.2f", distance)) canStart=\(mouseDownCanStartDrag) allowsHitTesting=\(allowsTransientDragSourceHitTesting) activeKinds=\(contextMenuController?.interactionState.activeKindsDescription ?? "unknown") view=\(debugViewDescription) hostedRoot=\(hostedSidebarRootDebugDescription)"
        )
        guard distance >= dragThreshold else { return }
        RuntimeDiagnostics.emit(
            "🧭 Sidebar mouseDragged starting drag owner=\(recoveryDebugDescription) distance=\(String(format: "%.2f", distance))"
        )
        startDrag(
            with: event,
            sessionEvent: mouseDownEvent ?? event,
            anchorPoint: mouseDownPoint
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingDragGesture else {
            super.mouseUp(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let primaryAction = itemConfiguration.primaryAction ?? itemConfiguration.dragSource?.onActivate
        let shouldInvokePrimaryAction = !didStartDrag && shouldCapturePrimaryAction(at: point)
        resetMouseState()
        if shouldInvokePrimaryAction {
            RuntimeDiagnostics.emit(
                "🧭 Sidebar primary click activated owner=\(String(describing: type(of: self)))"
            )
            primaryAction?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard shouldPresentMenu(trigger: .rightMouseDown, at: point) else {
            super.rightMouseDown(with: event)
            return
        }
        presentContextMenu(trigger: .rightMouseDown, event: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard shouldHandleMiddleClick(event, at: point) else {
            super.otherMouseUp(with: event)
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
        SidebarDragState.shared.resetInteractionState()
        resetMouseState()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        movedTo screenPoint: NSPoint
    ) {
        guard didStartDrag,
              let locations = SidebarDragLocationMapper.sourceLocationsFromScreenPoint(
                callbackScreenPoint: screenPoint,
                in: self
              ) else { return }
        updateInternalDragState(
            at: locations.dropLocation,
            previewLocation: locations.previewLocation
        )
    }

    func setTransientInteractionEnabled(_ isEnabled: Bool) {
        guard isTransientInteractionEnabled != isEnabled else { return }
        isTransientInteractionEnabled = isEnabled
        applyEffectiveInteractionEnabled()
    }

    private func applyEffectiveInteractionEnabled() {
        let effectiveInteractionEnabled = isConfigurationInteractionEnabled
            && isTransientInteractionEnabled
        guard isInteractive != effectiveInteractionEnabled else { return }

        if !effectiveInteractionEnabled,
           didStartDrag,
           !shouldPreserveSharedDragStateOnTeardown {
            SidebarDragState.shared.resetInteractionState()
        }

        isInteractive = effectiveInteractionEnabled
        resetMouseState()
    }

    func cancelPrimaryMouseTracking() {
        resetMouseState()
    }

    func prepareForDismantle() {
        setTransientInteractionEnabled(false)
        itemConfiguration = SidebarAppKitItemConfiguration()
        contextMenuController = nil
        resetMouseState()
    }

    func shouldCaptureInteraction(
        at point: NSPoint,
        eventType: NSEvent.EventType?
    ) -> Bool {
        guard isInteractive, bounds.contains(point) else { return false }

        switch eventType {
        case .leftMouseDown?:
            if shouldPresentMenu(trigger: .leftMouseDown, at: point) {
                return true
            }
            return shouldCapturePrimaryAction(at: point) || shouldCaptureDrag(at: point)
        case .rightMouseDown?:
            return shouldPresentMenu(trigger: .rightMouseDown, at: point)
        case .otherMouseUp?:
            return itemConfiguration.onMiddleClick != nil
        default:
            return false
        }
    }

    func routingPriority(
        at point: NSPoint,
        eventType: NSEvent.EventType?
    ) -> Int {
        guard isInteractive, bounds.contains(point) else { return 0 }

        let inputBonus = itemConfiguration.isInteractionEnabled ? 100 : 0
        switch eventType {
        case .leftMouseDown?:
            if shouldCaptureDrag(at: point) {
                return inputBonus + 30
            }
            if shouldPresentMenu(trigger: .leftMouseDown, at: point) {
                return inputBonus + 20
            }
            if shouldCapturePrimaryAction(at: point) {
                return inputBonus + 10
            }
        case .rightMouseDown?:
            if shouldPresentMenu(trigger: .rightMouseDown, at: point) {
                return inputBonus + 20
            }
        case .otherMouseUp?:
            if itemConfiguration.onMiddleClick != nil {
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

    private func shouldCapturePrimaryAction(at point: NSPoint) -> Bool {
        guard itemConfiguration.primaryAction != nil || itemConfiguration.dragSource?.onActivate != nil,
              bounds.contains(point)
        else {
            return false
        }

        return !isInPrimaryActionExclusionZone(point)
    }

    private func isInPrimaryActionExclusionZone(_ point: NSPoint) -> Bool {
        guard let dragSource = itemConfiguration.dragSource else { return false }
        return dragSource.exclusionZones.contains { $0.contains(point, in: bounds) }
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

        RuntimeDiagnostics.emit(
            "🧭 Sidebar present context menu owner=\(recoveryDebugDescription) trigger=\(String(describing: trigger))"
        )

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

    private func startDrag(
        with event: NSEvent,
        sessionEvent: NSEvent,
        anchorPoint: CGPoint?
    ) {
        guard let configuration = itemConfiguration.dragSource,
              isInteractive,
              configuration.isEnabled,
              allowsTransientDragSourceHitTesting
        else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let resolvedAnchorPoint = anchorPoint ?? point
        guard let previewSession = SidebarDragPreviewSessionFactory.make(
            configuration: configuration,
            sourceSize: bounds.size,
            sourceOffsetFromBottomLeading: resolvedAnchorPoint
        ) else { return }

        didStartDrag = true
        let dragLocation = SidebarDragLocationMapper.swiftUIGlobalPoint(
            fromLocalPoint: point,
            in: self
        )
        let previewLocation = SidebarDragLocationMapper.swiftUIPreviewPoint(
            fromLocalPoint: point,
            in: self
        )
        SidebarDragState.shared.beginInternalDragSession(
            itemId: configuration.item.tabId,
            location: dragLocation,
            previewLocation: previewLocation,
            previewKind: configuration.previewKind,
            previewAssets: previewSession.previewAssets,
            previewModel: previewSession.previewModel,
            scope: itemConfiguration.dragScope
        )
        SidebarDragState.shared.flushDeferredGeometryForDragStart()
        RuntimeDiagnostics.emit(
            "🧭 Sidebar drag started owner=\(recoveryDebugDescription) item=\(configuration.item.tabId.uuidString) source=\(sidebarDropZoneDebugDescription(configuration.sourceZone)) isDragging=\(SidebarDragState.shared.isDragging)"
        )
        SidebarUITestDragMarker.recordDragStart(
            itemID: configuration.item.tabId,
            sourceDescription: sidebarDropZoneDebugDescription(configuration.sourceZone),
            ownerDescription: recoveryDebugDescription,
            sourceID: itemConfiguration.sourceID,
            viewDescription: debugViewDescription
        )
        updateInternalDragState(
            at: dragLocation,
            previewLocation: previewLocation
        )

        let dragItem = NSDraggingItem(pasteboardWriter: configuration.item.pasteboardItem())
        let frame = NSRect(
            x: resolvedAnchorPoint.x - previewSession.primaryAsset.anchorOffset.x,
            y: resolvedAnchorPoint.y - previewSession.primaryAsset.anchorOffset.y,
            width: previewSession.primaryAsset.size.width,
            height: previewSession.primaryAsset.size.height
        )
        dragItem.setDraggingFrame(frame, contents: transparentImage(size: previewSession.primaryAsset.size))

        let session = beginDraggingSession(with: [dragItem], event: sessionEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func updateInternalDragState(
        at location: CGPoint,
        previewLocation: CGPoint? = nil
    ) {
        guard let configuration = itemConfiguration.dragSource else { return }
        SidebarDropResolver.updateState(
            location: location,
            previewLocation: previewLocation,
            state: SidebarDragState.shared,
            draggedItem: configuration.item
        )
    }

    private var shouldPreserveSharedDragStateOnTeardown: Bool {
        guard didStartDrag,
              let dragItemID = itemConfiguration.dragSource?.item.tabId else {
            return false
        }

        let state = SidebarDragState.shared
        return state.isDragging
            && state.isInternalDragSession
            && state.activeDragItemId == dragItemID
    }

    private var allowsTransientDragSourceHitTesting: Bool {
        contextMenuController?.interactionState.allowsSidebarDragSourceHitTesting ?? true
    }

    private func resetMouseState() {
        let hadMouseState = mouseDownEvent != nil
            || mouseDownPoint != nil
            || mouseDownCanStartDrag
            || didStartDrag
            || isTrackingDragGesture
        let shouldCancelArmedGeometry = !didStartDrag
        mouseDownEvent = nil
        mouseDownPoint = nil
        mouseDownCanStartDrag = false
        didStartDrag = false
        isTrackingDragGesture = false
        if shouldCancelArmedGeometry {
            SidebarDragState.shared.cancelArmedDragGeometry()
        }
        contextMenuController?.endPrimaryMouseTracking(self)
        if hadMouseState {
            SidebarUITestDragMarker.recordEvent(
                "resetMouseState",
                dragItemID: itemConfiguration.dragSource?.item.tabId,
                ownerDescription: recoveryDebugDescription,
                sourceID: itemConfiguration.sourceID,
                viewDescription: debugViewDescription,
                details: "source=\(itemConfiguration.sourceID ?? "nil") interactive=\(isInteractive) allowsHitTesting=\(allowsTransientDragSourceHitTesting) activeKinds=\(contextMenuController?.interactionState.activeKindsDescription ?? "unknown") view=\(debugViewDescription) hostedRoot=\(hostedSidebarRootDebugDescription) controller=\(contextMenuControllerDebugDescription)"
            )
        }
    }

    private func trackPrimaryMouseEventsIfNeeded(after event: NSEvent) {
        guard event.timestamp > 0,
              let trackingWindow = window,
              event.windowNumber == trackingWindow.windowNumber,
              contextMenuController?.interactionState.isContextMenuPresented != true
        else {
            return
        }

        RuntimeDiagnostics.emit(
            "🧭 Sidebar primary tracking loop started owner=\(String(describing: type(of: self))) window=\(trackingWindow.windowNumber)"
        )
        trackingWindow.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { [weak self, weak trackingWindow] trackedEvent, stop in
            guard let self,
                  let trackingWindow,
                  self.window === trackingWindow,
                  self.superview != nil,
                  self.isTrackingDragGesture,
                  let trackedEvent
            else {
                stop.pointee = true
                return
            }

            switch trackedEvent.type {
            case .leftMouseDragged:
                self.mouseDragged(with: trackedEvent)
                if self.didStartDrag {
                    stop.pointee = true
                }
            case .leftMouseUp:
                self.mouseUp(with: trackedEvent)
                stop.pointee = true
            default:
                break
            }
        }
    }

    private func logLeftMouseCapture(
        point: NSPoint,
        capturesPrimaryAction: Bool,
        capturesDrag: Bool
    ) {
        RuntimeDiagnostics.emit(
            "🧭 Sidebar left-click capture owner=\(recoveryDebugDescription) point=\(Int(point.x)),\(Int(point.y)) inputEnabled=\(itemConfiguration.isInteractionEnabled) primaryAction=\(itemConfiguration.primaryAction != nil) dragEnabled=\(itemConfiguration.dragSource?.isEnabled == true) capturesPrimary=\(capturesPrimaryAction) capturesDrag=\(capturesDrag) activeKinds=\(contextMenuController?.interactionState.activeKindsDescription ?? "unknown")"
        )
    }

    var recoveryMetadata: SidebarInteractiveOwnerRecoveryMetadata {
        SidebarInteractiveOwnerRecoveryMetadata(
            ownerObjectID: ObjectIdentifier(self),
            ownerTypeName: String(describing: type(of: self)),
            dragItemID: itemConfiguration.dragSource?.item.tabId,
            dragSourceZone: itemConfiguration.dragSource?.sourceZone
        )
    }

    var sourceID: String? {
        itemConfiguration.sourceID
    }

    var debugViewDescription: String {
        sidebarViewDebugDescription(self)
    }

    var hostedSidebarRootDebugDescription: String {
        sidebarViewDebugDescription(sidebarHostedSidebarRoot(from: self))
    }

    var contextMenuControllerDebugDescription: String {
        sidebarObjectDebugDescription(contextMenuController)
    }

    var recoveryDebugDescription: String {
        let sourceID = itemConfiguration.sourceID ?? "nil"
        let surface = sidebarContextMenuSurfaceDebugDescription(itemConfiguration.surfaceKind)
        let mode = sidebarPresentationModeDebugDescription(itemConfiguration.presentationMode)
        return "\(recoveryMetadata.description){source=\(sourceID),surface=\(surface),mode=\(mode)}"
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

private extension SidebarAppKitItemConfiguration {
    var supportsPrimaryMouseTracking: Bool {
        primaryAction != nil || dragSource?.isEnabled == true || dragSource?.onActivate != nil
    }
}
private func transparentImage(size: CGSize) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    image.unlockFocus()
    return image
}
