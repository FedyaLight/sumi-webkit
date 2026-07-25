import AppKit
import Observation

enum SidebarDragActivitySource: Hashable {
    case visualItem
    case spaceReorder
}

/// Window-local owner of the Sidebar Pointer Session and transient input policy.
///
/// A row keeps only gesture mechanics such as its drag threshold. Exclusive
/// ownership, pressed chrome, hit routing, and cancellation live here so a new
/// pointer-down cannot leave an older Sidebar Visual Item armed.
@MainActor
@Observable
final class SidebarInteractionState {
    @ObservationIgnored
    let hoverSession: SidebarHoverSession
    private var activeSessionTokenIDsByKind: [SidebarTransientUIKind: Set<UUID>] = [:]
    private var activeDragSources: Set<SidebarDragActivitySource> = []
    private(set) var activePressedSourceID: String?

    @ObservationIgnored
    private let interactiveOwners = SidebarInteractiveOwnerRegistry()
    @ObservationIgnored
    private weak var activePointerOwner: SidebarInteractiveItemView?

    init(hoverSession: SidebarHoverSession = SidebarHoverSession()) {
        self.hoverSession = hoverSession
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

    func registerInteractiveOwner(_ owner: SidebarInteractiveItemView) {
        interactiveOwners.register(owner)
    }

    func unregisterInteractiveOwner(_ owner: SidebarInteractiveItemView) {
        endPointerSession(owner)
        interactiveOwners.unregister(owner)
    }

    /// Starts the only pointer session allowed in this window.
    /// Cancelling the old owner happens before the new row arms drag geometry,
    /// so cleanup from the old row cannot erase the new row's state.
    func beginPointerSession(
        owner: SidebarInteractiveItemView,
        sourceID: String?
    ) {
        if activePointerOwner !== owner {
            let previousOwner = activePointerOwner
            activePointerOwner = nil
            previousOwner?.cancelPrimaryMouseTracking()
            activePointerOwner = owner
        }
        activePressedSourceID = sourceID
    }

    func transitionPointerSessionToDrag(owner: SidebarInteractiveItemView) {
        guard activePointerOwner === owner else { return }
        activePressedSourceID = nil
    }

    func endPointerSession(_ owner: SidebarInteractiveItemView) {
        guard activePointerOwner === owner else { return }
        activePointerOwner = nil
        activePressedSourceID = nil
    }

    func activePointerSessionOwner(in window: NSWindow?) -> SidebarInteractiveItemView? {
        guard let owner = activePointerOwner,
              owner.window != nil,
              owner.window === window,
              owner.superview != nil,
              !owner.isHiddenOrHasHiddenAncestor
        else {
            if activePointerOwner != nil {
                activePointerOwner = nil
                activePressedSourceID = nil
            }
            return nil
        }
        return owner
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
            activePressedSourceID = nil
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
            activePressedSourceID = nil
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

@MainActor
private final class SidebarInteractiveOwnerRegistry {
    private struct WeakOwner {
        weak var view: SidebarInteractiveItemView?
    }

    private var ownersByID: [ObjectIdentifier: WeakOwner] = [:]
    private var ownerOrder: [ObjectIdentifier] = []

    func register(_ owner: SidebarInteractiveItemView) {
        let id = ObjectIdentifier(owner)
        ownersByID[id] = WeakOwner(view: owner)
        ownerOrder.removeAll { $0 == id }
        ownerOrder.append(id)
        pruneStaleOwners()
    }

    func unregister(_ owner: SidebarInteractiveItemView) {
        let id = ObjectIdentifier(owner)
        ownersByID[id] = nil
        ownerOrder.removeAll { $0 == id }
    }

    func owner(
        at windowPoint: NSPoint,
        in window: NSWindow?,
        eventType: NSEvent.EventType?,
        eventButtonNumber: Int?,
        hostedSidebarView: NSView?
    ) -> SidebarInteractiveItemView? {
        pruneStaleOwners()

        var bestCandidate: (
            owner: SidebarInteractiveItemView,
            priority: Int,
            depth: Int,
            orderIndex: Int
        )?

        for (orderIndex, id) in ownerOrder.enumerated() {
            guard let owner = ownersByID[id]?.view,
                  isLive(owner, in: window, hostedSidebarView: hostedSidebarView)
            else { continue }

            let localPoint = owner.convert(windowPoint, from: nil)
            guard owner.containsVisibleSidebarRoutingPoint(
                    windowPoint,
                    boundedBy: hostedSidebarView
                  ),
                  owner.shouldCaptureInteraction(
                    at: localPoint,
                    eventType: eventType,
                    eventButtonNumber: eventButtonNumber
                  )
            else { continue }

            let candidate = (
                owner: owner,
                priority: owner.routingPriority(
                    at: localPoint,
                    eventType: eventType,
                    eventButtonNumber: eventButtonNumber
                ),
                depth: owner.sidebarOwnerHierarchyDepth,
                orderIndex: orderIndex
            )
            if let current = bestCandidate {
                if candidate.priority > current.priority
                    || (candidate.priority == current.priority && candidate.depth > current.depth)
                    || (candidate.priority == current.priority
                        && candidate.depth == current.depth
                        && candidate.orderIndex > current.orderIndex) {
                    bestCandidate = candidate
                }
            } else {
                bestCandidate = candidate
            }
        }

        return bestCandidate?.owner
    }

    func recoverOwners(
        in window: NSWindow?,
        sourceMetadata: SidebarInteractiveOwnerRecoveryMetadata?
    ) -> SidebarInteractiveOwnerRecoveryResult {
        pruneStaleOwners()
        guard let sourceMetadata else { return .none }

        for id in ownerOrder {
            guard let owner = ownersByID[id]?.view,
                  isLive(owner, in: window, hostedSidebarView: nil)
            else { continue }
            guard owner.recoveryResolutionReason(matching: sourceMetadata) != nil else {
                continue
            }

            owner.cancelPrimaryMouseTracking()
            SidebarTransientUIHitTestingRecovery.invalidateLayoutChain(from: owner)
            return SidebarInteractiveOwnerRecoveryResult(sourceOwnerResolved: true)
        }

        return .none
    }

    private func pruneStaleOwners() {
        ownerOrder.removeAll { id in
            guard let owner = ownersByID[id]?.view,
                  owner.window != nil,
                  owner.superview != nil
            else {
                ownersByID[id] = nil
                return true
            }
            return false
        }
    }

    private func isLive(
        _ owner: SidebarInteractiveItemView,
        in window: NSWindow?,
        hostedSidebarView: NSView?
    ) -> Bool {
        guard owner.window != nil,
              owner.window === window,
              owner.superview != nil,
              !owner.isHiddenOrHasHiddenAncestor
        else {
            return false
        }
        if let hostedSidebarView,
           owner.isDescendant(of: hostedSidebarView) != true {
            return false
        }
        return true
    }
}

private extension NSView {
    func containsVisibleSidebarRoutingPoint(
        _ windowPoint: NSPoint,
        boundedBy hostedSidebarView: NSView?
    ) -> Bool {
        guard bounds.contains(convert(windowPoint, from: nil)) else {
            return false
        }

        var ancestor = superview
        while let view = ancestor {
            let constrainsVisibleContent = view === hostedSidebarView
                || view is NSClipView
                || view.clipsToBounds
                || view.layer?.masksToBounds == true
            if constrainsVisibleContent,
               !view.bounds.contains(view.convert(windowPoint, from: nil)) {
                return false
            }
            if view === hostedSidebarView {
                return true
            }
            ancestor = view.superview
        }

        return hostedSidebarView == nil
    }

    var sidebarOwnerHierarchyDepth: Int {
        var depth = 0
        var current = superview
        while let view = current {
            depth += 1
            current = view.superview
        }
        return depth
    }
}
