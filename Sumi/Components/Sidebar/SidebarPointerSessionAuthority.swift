import AppKit
import SwiftUI

@MainActor
protocol SidebarPointerEventMonitoring: AnyObject {
    func start(_ handler: @escaping (NSEvent) -> Bool)
    func stop()
}

@MainActor
final class SidebarAppKitPointerEventMonitor: SidebarPointerEventMonitoring {
    private var monitor: Any?

    func start(_ handler: @escaping (NSEvent) -> Bool) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { event in
            let isConsumed = MainActor.assumeIsolated {
                handler(event)
            }
            return isConsumed ? nil : event
        }
    }

    func stop() {
        guard let monitor else { return }
        self.monitor = nil
        NSEvent.removeMonitor(monitor)
    }

    isolated deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

@MainActor
struct SidebarNativeDragSessionStarter {
    let start: (
        SidebarInteractiveItemView,
        [NSDraggingItem],
        NSEvent
    ) -> Void

    static let appKit = Self { owner, items, event in
        let session = owner.beginDraggingSession(
            with: items,
            event: event,
            source: owner
        )
        session.animatesToStartingPositionsOnCancelOrFail = true
    }
}

@MainActor
struct SidebarPrimaryPointerIntent {
    struct Drag {
        let source: SidebarDragSourceConfiguration
        let scope: SidebarDragScope?
        let state: SidebarDragState
    }

    struct Release {
        let action: () -> Void
        let exclusionZones: [SidebarDragSourceExclusionZone]
        let suppressesAnimation: Bool
    }

    let sourceID: String?
    let showsPressVisual: Bool
    let drag: Drag?
    let release: Release?
}

/// Window-local authority for one accepted sidebar primary-pointer gesture.
///
/// The accepted intent and drag geometry live here rather than in a SwiftUI-
/// managed NSView, so replacing the presenting row cannot interrupt the
/// gesture. The AppKit view is only the current presenter and drag source.
@MainActor
final class SidebarPointerSessionAuthority {
    @MainActor
    private final class PointerSession {
        let sourceID: String?
        weak var window: NSWindow?
        weak var presenter: SidebarInteractiveItemView?
        let mouseDownEvent: NSEvent
        let mouseDownWindowPoint: NSPoint
        let drag: SidebarPrimaryPointerIntent.Drag?
        var release: SidebarPrimaryPointerIntent.Release?
        let acceptsRelease: Bool
        let pressVisualSourceID: String?

        init(
            event: NSEvent,
            owner: SidebarInteractiveItemView,
            intent: SidebarPrimaryPointerIntent
        ) {
            sourceID = intent.sourceID
            window = owner.window
            presenter = owner
            mouseDownEvent = event
            mouseDownWindowPoint = event.locationInWindow
            drag = intent.drag
            release = intent.release
            acceptsRelease = intent.release != nil
            pressVisualSourceID = intent.showsPressVisual
                ? intent.sourceID
                : nil
        }
    }

    @MainActor
    private final class NativeDrag {
        weak var owner: SidebarInteractiveItemView?
        let source: SidebarDragSourceConfiguration
        let state: SidebarDragState

        init(
            owner: SidebarInteractiveItemView,
            source: SidebarDragSourceConfiguration,
            state: SidebarDragState
        ) {
            self.owner = owner
            self.source = source
            self.state = state
        }
    }

    private let dragThreshold: CGFloat = 3
    private let eventMonitor: any SidebarPointerEventMonitoring
    private let nativeDragStarter: SidebarNativeDragSessionStarter
    private var pointerSession: PointerSession? {
        didSet {
            syncEventMonitor()
            publishPressVisualIfNeeded()
        }
    }
    private var nativeDrag: NativeDrag?
    private var publishedPressVisualSourceID: String?

    var onPressVisualSourceIDChanged: ((String?) -> Void)?

    init(
        eventMonitor: any SidebarPointerEventMonitoring =
            SidebarAppKitPointerEventMonitor(),
        nativeDragStarter: SidebarNativeDragSessionStarter = .appKit
    ) {
        self.eventMonitor = eventMonitor
        self.nativeDragStarter = nativeDragStarter
    }

    isolated deinit {
        eventMonitor.stop()
    }

    var hasActiveSession: Bool {
        pointerSession != nil
    }

    func hasActiveSession(for sourceID: String) -> Bool {
        pointerSession?.sourceID == sourceID
    }

    func begin(
        event: NSEvent,
        owner: SidebarInteractiveItemView,
        intent: SidebarPrimaryPointerIntent
    ) {
        cancel()

        let session = PointerSession(
            event: event,
            owner: owner,
            intent: intent
        )
        pointerSession = session
        session.drag?.state.armInternalDragGeometry(
            scope: session.drag?.scope
        )
    }

    func present(
        sourceID: String?,
        with owner: SidebarInteractiveItemView,
        release: SidebarPrimaryPointerIntent.Release?
    ) {
        guard let session = pointerSession else { return }

        if session.presenter === owner {
            if session.sourceID != sourceID {
                cancel()
            } else if session.acceptsRelease {
                session.release = release
            }
            return
        }

        guard let sourceID,
              session.sourceID == sourceID
        else {
            return
        }
        if let acceptedWindow = session.window {
            guard owner.window === acceptedWindow else { return }
        } else {
            guard owner.window == nil else { return }
        }
        session.presenter = owner
        if session.acceptsRelease {
            session.release = release
        }
    }

    func detach(_ owner: SidebarInteractiveItemView) {
        guard pointerSession?.presenter === owner else { return }
        pointerSession?.presenter = nil
    }

    func cancel(presentedBy owner: SidebarInteractiveItemView? = nil) {
        guard let session = pointerSession else { return }
        if let owner, session.presenter !== owner {
            return
        }

        pointerSession = nil
        session.drag?.state.cancelArmedDragGeometry()
    }

    @discardableResult
    func continueEvent(
        _ event: NSEvent,
        deliveredTo deliveredOwner: SidebarInteractiveItemView? = nil
    ) -> Bool {
        guard let session = pointerSession else { return false }

        if let deliveredOwner {
            guard session.presenter === deliveredOwner else { return false }
        } else {
            if let acceptedWindow = session.window {
                guard event.window === acceptedWindow else { return false }
            } else {
                guard event.window == nil else { return false }
            }
            if let presenter = session.presenter,
               presenter.window == nil {
                session.presenter = nil
            }
        }

        switch event.type {
        case .leftMouseDragged:
            continueDrag(event, session: session)
        case .leftMouseUp:
            completeRelease(event, session: session)
        default:
            return false
        }
        return true
    }

    func nativeDragMoved(
        from owner: SidebarInteractiveItemView,
        to screenPoint: NSPoint
    ) {
        guard let nativeDrag,
              nativeDrag.owner === owner,
              let locations = SidebarDragLocationMapper.sourceLocationsFromScreenPoint(
                  callbackScreenPoint: screenPoint,
                  in: owner
              )
        else {
            return
        }
        updateInternalDragState(
            nativeDrag,
            location: locations.dropLocation,
            previewLocation: locations.previewLocation
        )
    }

    func nativeDragEnded(from owner: SidebarInteractiveItemView) {
        guard let nativeDrag,
              nativeDrag.owner === owner
        else {
            return
        }
        self.nativeDrag = nil
        nativeDrag.state.resetInteractionState()
    }

    private func continueDrag(
        _ event: NSEvent,
        session: PointerSession
    ) {
        guard pointerSession === session,
              let drag = session.drag,
              let dragScope = drag.scope,
              let owner = session.presenter
        else {
            return
        }

        let deltaX = event.locationInWindow.x - session.mouseDownWindowPoint.x
        let deltaY = event.locationInWindow.y - session.mouseDownWindowPoint.y
        guard hypot(deltaX, deltaY) >= dragThreshold else { return }

        startNativeDrag(
            event: event,
            session: session,
            drag: drag,
            dragScope: dragScope,
            owner: owner
        )
    }

    private func completeRelease(
        _ event: NSEvent,
        session: PointerSession
    ) {
        guard pointerSession === session else { return }

        let release = session.release
        let owner = session.presenter
        let shouldPerformRelease: Bool
        if let release, let owner {
            let point = owner.convert(event.locationInWindow, from: nil)
            shouldPerformRelease = owner.bounds.contains(point)
                && !release.exclusionZones.contains {
                    $0.contains(point, in: owner.bounds)
                }
        } else {
            shouldPerformRelease = false
        }

        pointerSession = nil
        session.drag?.state.cancelArmedDragGeometry()
        guard shouldPerformRelease, let release else { return }
        perform(
            release.action,
            suppressingAnimation: release.suppressesAnimation
        )
    }

    private func startNativeDrag(
        event: NSEvent,
        session: PointerSession,
        drag: SidebarPrimaryPointerIntent.Drag,
        dragScope: SidebarDragScope,
        owner: SidebarInteractiveItemView
    ) {
        let point = owner.convert(event.locationInWindow, from: nil)
        let anchorPoint = owner.convert(session.mouseDownWindowPoint, from: nil)
        let previewSourceSize = drag.source.previewSourceGeometry?.size
            ?? owner.bounds.size
        let previewAnchorPoint = drag.source.previewSourceGeometry?
            .anchor(forLocalPoint: anchorPoint)
            ?? anchorPoint
        guard let previewSession = SidebarDragPreviewSessionFactory.make(
            configuration: drag.source,
            sourceSize: previewSourceSize,
            sourceOffsetFromBottomLeading: previewAnchorPoint
        ) else {
            return
        }

        pointerSession = nil
        let dragLocation = SidebarDragLocationMapper.swiftUIGlobalPoint(
            fromLocalPoint: point,
            in: owner
        )
        let previewLocation = SidebarDragLocationMapper.swiftUIPreviewPoint(
            fromLocalPoint: point,
            in: owner
        )
        drag.state.beginInternalDragSession(
            itemId: drag.source.item.tabId,
            location: dragLocation,
            previewLocation: previewLocation,
            previewKind: drag.source.previewKind,
            previewAssets: previewSession.previewAssets,
            previewModel: previewSession.previewModel,
            scope: dragScope
        )
        drag.state.geometry.flushDeferredGeometryForDragStart()

        let activeDrag = NativeDrag(
            owner: owner,
            source: drag.source,
            state: drag.state
        )
        nativeDrag = activeDrag
        updateInternalDragState(
            activeDrag,
            location: dragLocation,
            previewLocation: previewLocation
        )

        let dragItem = NSDraggingItem(
            pasteboardWriter: drag.source.item.pasteboardItem(scope: dragScope)
        )
        dragItem.setDraggingFrame(
            NSRect(
                x: anchorPoint.x,
                y: anchorPoint.y,
                width: 1,
                height: 1
            ),
            contents: Self.transparentDragImage
        )
        nativeDragStarter.start(
            owner,
            [dragItem],
            session.mouseDownEvent
        )
    }

    private func updateInternalDragState(
        _ drag: NativeDrag,
        location: CGPoint,
        previewLocation: CGPoint?
    ) {
        SidebarDropResolver.updateState(
            location: location,
            previewLocation: previewLocation,
            state: drag.state,
            draggedItem: drag.source.item
        )
    }

    private func syncEventMonitor() {
        guard pointerSession != nil else {
            eventMonitor.stop()
            return
        }
        eventMonitor.start { [weak self] event in
            self?.continueEvent(event) ?? false
        }
    }

    private func publishPressVisualIfNeeded() {
        let sourceID = pointerSession?.pressVisualSourceID
        guard publishedPressVisualSourceID != sourceID else { return }
        publishedPressVisualSourceID = sourceID
        onPressVisualSourceIDChanged?(sourceID)
    }

    private func perform(
        _ action: () -> Void,
        suppressingAnimation: Bool
    ) {
        guard suppressingAnimation else {
            action()
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction, action)
    }

    private static let transparentDragImage = NSImage(
        size: NSSize(width: 1, height: 1)
    )
}
