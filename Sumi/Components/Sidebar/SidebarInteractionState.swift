import AppKit
import Observation

enum SidebarDragActivitySource: Hashable {
    case visualItem
    case spaceReorder
}

/// Window-local policy for sidebar input, hover suspension, and transient UI.
///
/// Accepted primary gestures are delegated to `pointerSessions`; hit routing
/// is delegated to `interactiveOwners`.
@MainActor
@Observable
final class SidebarInteractionState {
    @ObservationIgnored
    let hoverSession: SidebarHoverSession
    @ObservationIgnored
    let pointerSessions: SidebarPointerSessionAuthority
    @ObservationIgnored
    private let interactiveOwners = SidebarInteractiveOwnerRegistry()

    private var activeSessionTokenIDsByKind: [SidebarTransientUIKind: Set<UUID>] = [:]
    private var activeDragSources: Set<SidebarDragActivitySource> = []
    private var activePressVisualSourceID: String?

    init(
        hoverSession: SidebarHoverSession = SidebarHoverSession(),
        pointerEventMonitor: any SidebarPointerEventMonitoring =
            SidebarAppKitPointerEventMonitor(),
        nativeDragStarter: SidebarNativeDragSessionStarter = .appKit,
        pressVisual: SidebarPressVisualPresenter = SidebarPressVisualPresenter()
    ) {
        self.hoverSession = hoverSession
        pointerSessions = SidebarPointerSessionAuthority(
            eventMonitor: pointerEventMonitor,
            nativeDragStarter: nativeDragStarter,
            pressVisual: pressVisual
        )
        pointerSessions.onPressVisualSourceIDChanged = { [weak self] sourceID in
            self?.activePressVisualSourceID = sourceID
        }
    }

    var freezesSidebarHoverState: Bool {
        !activeDragSources.isEmpty
            || activeKinds.contains(where: \.freezesSidebarHoverState)
    }

    var allowsFolderPreviewHoverTracking: Bool {
        activeDragSources.isEmpty
            && activeKinds.allSatisfy { $0 == .folderPreview }
    }

    var allowsSidebarSwipeCapture: Bool {
        activeKinds.isEmpty && activeDragSources.isEmpty
    }

    var allowsSidebarDragSourceHitTesting: Bool {
        activeKinds.contains(where: \.blocksSidebarDragSources) == false
    }

    func presentsPressVisual(for sourceID: String) -> Bool {
        activePressVisualSourceID == sourceID
    }

    func presentsPressVisual(forAny sourceIDs: [String]) -> Bool {
        guard let activePressVisualSourceID else { return false }
        return sourceIDs.contains(activePressVisualSourceID)
    }

    var hasActivePointerSession: Bool {
        pointerSessions.hasActiveSession
    }

    func hasActivePointerSession(for sourceID: String) -> Bool {
        pointerSessions.hasActiveSession(for: sourceID)
    }

    func registerInteractiveOwner(_ owner: SidebarInteractiveItemView) {
        interactiveOwners.register(owner)
    }

    func unregisterInteractiveOwner(_ owner: SidebarInteractiveItemView) {
        pointerSessions.detach(owner)
        interactiveOwners.unregister(owner)
    }

    func interactiveOwner(
        at windowPoint: NSPoint,
        in window: NSWindow?,
        eventType: NSEvent.EventType?,
        eventButtonNumber: Int? = nil,
        hostedSidebarView: NSView? = nil
    ) -> SidebarInteractiveItemView? {
        interactiveOwners.owner(
            at: windowPoint,
            in: window,
            eventType: eventType,
            eventButtonNumber: eventButtonNumber,
            hostedSidebarView: hostedSidebarView
        )
    }

    func prefersOriginalHitOwner(
        _ owner: SidebarInteractiveItemView,
        at windowPoint: NSPoint,
        in window: NSWindow?,
        eventType: NSEvent.EventType?,
        eventButtonNumber: Int? = nil,
        hostedSidebarView: NSView? = nil
    ) -> Bool {
        guard owner.window === window,
              owner.superview != nil,
              !owner.isHiddenOrHasHiddenAncestor
        else {
            return false
        }
        if let hostedSidebarView,
           owner.isDescendant(of: hostedSidebarView) != true {
            return false
        }

        let localPoint = owner.convert(windowPoint, from: nil)
        return owner.containsVisibleSidebarRoutingPoint(
            windowPoint,
            boundedBy: hostedSidebarView
        )
            && owner.shouldCaptureInteraction(
                at: localPoint,
                eventType: eventType,
                eventButtonNumber: eventButtonNumber
            )
    }

    func recoverInteractiveOwners(
        in window: NSWindow?,
        sourceMetadata: SidebarInteractiveOwnerRecoveryMetadata?
    ) -> SidebarInteractiveOwnerRecoveryResult {
        interactiveOwners.recoverOwners(
            in: window,
            sourceMetadata: sourceMetadata
        )
    }

    func setDragActive(
        _ isActive: Bool,
        source: SidebarDragActivitySource
    ) {
        if isActive {
            guard activeDragSources.insert(source).inserted else { return }
            pointerSessions.cancel()
        } else {
            guard activeDragSources.remove(source) != nil else { return }
        }
        syncHoverSuspension()
    }

    func beginSession(kind: SidebarTransientUIKind, tokenID: UUID) {
        var tokens = activeSessionTokenIDsByKind[kind] ?? []
        tokens.insert(tokenID)
        activeSessionTokenIDsByKind[kind] = tokens
        syncHoverSuspension()
    }

    func endSession(kind: SidebarTransientUIKind, tokenID: UUID) {
        guard var tokens = activeSessionTokenIDsByKind[kind] else { return }
        tokens.remove(tokenID)
        if tokens.isEmpty {
            activeSessionTokenIDsByKind.removeValue(forKey: kind)
        } else {
            activeSessionTokenIDsByKind[kind] = tokens
        }
        syncHoverSuspension()
    }

    func reconcileSessions(_ activeTokenIDsByKind: [SidebarTransientUIKind: Set<UUID>]) {
        activeSessionTokenIDsByKind = activeTokenIDsByKind.filter { !$0.value.isEmpty }
        if freezesSidebarHoverState {
            pointerSessions.cancel()
        }
        syncHoverSuspension()
    }

    private func syncHoverSuspension() {
        hoverSession.setSuspended(freezesSidebarHoverState)
    }

    private var activeKinds: Set<SidebarTransientUIKind> {
        Set(activeSessionTokenIDsByKind.keys)
    }
}
