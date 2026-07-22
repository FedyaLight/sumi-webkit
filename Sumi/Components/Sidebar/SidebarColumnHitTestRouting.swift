import AppKit

@MainActor
enum SidebarColumnHitTestRouting {
    static func routedHit(
        point: NSPoint,
        in containerView: NSView,
        originalHit: NSView?,
        hostedSidebarView: NSView?,
        contextMenuController: SidebarContextMenuController?,
        eventType: NSEvent.EventType?,
        eventButtonNumber: Int? = nil,
        capturesOverlayBackgroundPointerEvents: Bool = false
    ) -> NSView? {
        if eventType == .leftMouseDragged || eventType == .leftMouseUp,
           let owner = contextMenuController?.interactionState.activePointerSessionOwner(
            in: containerView.window
           ) {
            return owner
        }

        guard containerView.bounds.contains(point) else {
            return originalHit
        }

        let isMiddleMouseEvent = (eventType == .otherMouseDown || eventType == .otherMouseUp)
            && eventButtonNumber == 2

        guard eventType == .leftMouseDown
            || eventType == .rightMouseDown
            || isMiddleMouseEvent
        else {
            return capturesOverlayBackgroundPointerEvents ? (originalHit ?? containerView) : originalHit
        }

        let windowPoint = containerView.convert(point, to: nil)
        let originalOwner = originalHit?.nearestAncestor(of: SidebarInteractiveItemView.self)
        var originalOwnerPriority: Int?
        if let originalOwner,
           contextMenuController?.interactionState.prefersOriginalHitOwner(
               originalOwner,
               at: windowPoint,
               in: containerView.window,
               eventType: eventType,
               eventButtonNumber: eventButtonNumber,
               hostedSidebarView: hostedSidebarView
           ) == true {
            let originalPoint = originalOwner.convert(windowPoint, from: nil)
            originalOwnerPriority = originalOwner.routingPriority(
                at: originalPoint,
                eventType: eventType,
                eventButtonNumber: eventButtonNumber
            )
        }

        if let owner = contextMenuController?.interactionState.interactiveOwner(
            at: windowPoint,
            in: containerView.window,
            eventType: eventType,
            eventButtonNumber: eventButtonNumber,
            hostedSidebarView: hostedSidebarView
        ) {
            if let originalOwner,
               originalOwner !== owner,
               let originalOwnerPriority {
                let ownerPoint = owner.convert(windowPoint, from: nil)
                let ownerPriority = owner.routingPriority(
                    at: ownerPoint,
                    eventType: eventType,
                    eventButtonNumber: eventButtonNumber
                )
                if originalOwnerPriority >= ownerPriority {
                    return originalOwner
                }
            }

            return owner
        }

        if let originalOwner,
           originalOwnerPriority != nil {
            return originalOwner
        }

        guard eventType == .rightMouseDown,
              let hostedSidebarView
        else {
            return originalHit
        }

        if let originalOwner {
            let ownerPoint = originalOwner.convert(windowPoint, from: nil)
            if originalOwner.shouldCaptureInteraction(
                at: ownerPoint,
                eventType: eventType,
                eventButtonNumber: eventButtonNumber
            ) {
                return originalOwner
            }
        }

        if originalHit?.nearestAncestor(of: SidebarInteractiveItemView.self) != nil,
           originalHit?.isDescendant(of: hostedSidebarView) != true {
            return originalHit
        }

        if let originalHit,
           originalHit === hostedSidebarView || originalHit.isDescendant(of: hostedSidebarView) {
            return containerView
        }

        if capturesOverlayBackgroundPointerEvents {
            return originalHit ?? containerView
        }

        return originalHit
    }
}

private extension NSView {
    func nearestAncestor<T: NSView>(of type: T.Type) -> T? {
        var current: NSView? = self
        while let view = current {
            if let match = view as? T {
                return match
            }
            current = view.superview
        }
        return nil
    }
}
