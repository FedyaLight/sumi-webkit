import AppKit

@MainActor
final class SidebarInteractiveOwnerRegistry {
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
            else {
                continue
            }

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
            else {
                continue
            }

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
                    || (candidate.priority == current.priority
                        && candidate.depth > current.depth)
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
            else {
                continue
            }
            guard owner.recoveryResolutionReason(matching: sourceMetadata) != nil else {
                continue
            }

            owner.cancelPointerSession()
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

extension NSView {
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
