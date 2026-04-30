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
        capturesPanelBackgroundPointerEvents: Bool = false
    ) -> NSView? {
        if eventType == .leftMouseDragged || eventType == .leftMouseUp,
           let owner = contextMenuController?.primaryMouseTrackingOwner(in: containerView.window)
        {
            logRoute(
                eventType: eventType,
                originalHit: originalHit,
                originalOwner: owner,
                owner: owner,
                hostedSidebarView: hostedSidebarView,
                decision: "primary-tracking-owner",
                usedBackgroundMenu: false
            )
            return owner
        }

        guard containerView.bounds.contains(point) else {
            return originalHit
        }

        guard eventType == .leftMouseDown || eventType == .rightMouseDown else {
            return capturesPanelBackgroundPointerEvents ? (originalHit ?? containerView) : originalHit
        }

        let windowPoint = containerView.convert(point, to: nil)
        let originalOwner = originalHit?.nearestAncestor(of: SidebarInteractiveItemView.self)
        var originalOwnerPriority: Int?
        if let originalOwner,
           contextMenuController?.prefersOriginalHitOwner(
               originalOwner,
               at: windowPoint,
               in: containerView.window,
               eventType: eventType,
               hostedSidebarView: hostedSidebarView
           ) == true
        {
            let originalPoint = originalOwner.convert(windowPoint, from: nil)
            originalOwnerPriority = originalOwner.routingPriority(
                at: originalPoint,
                eventType: eventType
            )
        }

        if let owner = contextMenuController?.interactiveOwner(
            at: windowPoint,
            in: containerView.window,
            eventType: eventType,
            hostedSidebarView: hostedSidebarView
        ) {
            if let originalOwner,
               originalOwner !== owner,
               let originalOwnerPriority
            {
                let ownerPoint = owner.convert(windowPoint, from: nil)
                let ownerPriority = owner.routingPriority(
                    at: ownerPoint,
                    eventType: eventType
                )
                if originalOwnerPriority >= ownerPriority {
                    logRoute(
                        eventType: eventType,
                        originalHit: originalHit,
                        originalOwner: originalOwner,
                        owner: originalOwner,
                        hostedSidebarView: hostedSidebarView,
                        decision: "original-hit-owner",
                        usedBackgroundMenu: false
                    )
                    return originalOwner
                }
            }

            logRoute(
                eventType: eventType,
                originalHit: originalHit,
                originalOwner: originalOwner,
                owner: owner,
                hostedSidebarView: hostedSidebarView,
                decision: originalOwner === owner ? "original-hit-owner" : "registry-owner",
                usedBackgroundMenu: false
            )
            return owner
        }

        if let originalOwner,
           originalOwnerPriority != nil
        {
            logRoute(
                eventType: eventType,
                originalHit: originalHit,
                originalOwner: originalOwner,
                owner: originalOwner,
                hostedSidebarView: hostedSidebarView,
                decision: "original-hit-owner",
                usedBackgroundMenu: false
            )
            return originalOwner
        }

        guard eventType == .rightMouseDown,
              let hostedSidebarView
        else {
            return originalHit
        }

        if let originalOwner {
            let ownerPoint = originalOwner.convert(windowPoint, from: nil)
            if originalOwner.shouldCaptureInteraction(at: ownerPoint, eventType: eventType) {
                logRoute(
                    eventType: eventType,
                    originalHit: originalHit,
                    originalOwner: originalOwner,
                    owner: originalOwner,
                    hostedSidebarView: hostedSidebarView,
                    decision: "background-fallback-owner",
                    usedBackgroundMenu: false
                )
                return originalOwner
            }
        }

        if originalHit?.nearestAncestor(of: SidebarInteractiveItemView.self) != nil,
           originalHit?.isDescendant(of: hostedSidebarView) != true
        {
            return originalHit
        }

        if let originalHit,
           originalHit === hostedSidebarView || originalHit.isDescendant(of: hostedSidebarView)
        {
            logRoute(
                eventType: eventType,
                originalHit: originalHit,
                originalOwner: originalOwner,
                owner: nil,
                hostedSidebarView: hostedSidebarView,
                decision: "background-menu",
                usedBackgroundMenu: true
            )
            return containerView
        }

        if capturesPanelBackgroundPointerEvents {
            return originalHit ?? containerView
        }

        return originalHit
    }

    private static func logRoute(
        eventType: NSEvent.EventType?,
        originalHit: NSView?,
        originalOwner: SidebarInteractiveItemView?,
        owner: SidebarInteractiveItemView?,
        hostedSidebarView: NSView?,
        decision: String,
        usedBackgroundMenu: Bool
    ) {
        let ownerSource = owner?.sourceID ?? "nil"
        let originalOwnerSource = originalOwner?.sourceID ?? "nil"
        let hostedRootDescription = sidebarViewDebugDescription(hostedSidebarView)
        let ownerRootDescription = sidebarViewDebugDescription(sidebarHostedSidebarRoot(from: owner))
        let originalOwnerRootDescription = sidebarViewDebugDescription(
            sidebarHostedSidebarRoot(from: originalOwner)
        )
        let ownerInHostedRoot = hostedSidebarView.map { owner?.isDescendant(of: $0) == true } ?? false
        let originalOwnerInHostedRoot = hostedSidebarView.map {
            originalOwner?.isDescendant(of: $0) == true
        } ?? false
        RuntimeDiagnostics.emit {
            "🧭 Sidebar column hit-test event=\(eventType.map(String.init(describing:)) ?? "nil") decision=\(decision) hit=\(originalHit.map { String(describing: type(of: $0)) } ?? "nil") originalOwner=\(originalOwner?.recoveryDebugDescription ?? "nil") owner=\(owner?.recoveryDebugDescription ?? "nil") hostedRoot=\(hostedRootDescription) originalOwnerRoot=\(originalOwnerRootDescription) ownerRoot=\(ownerRootDescription) originalOwnerInHostedRoot=\(originalOwnerInHostedRoot) ownerInHostedRoot=\(ownerInHostedRoot) background=\(usedBackgroundMenu)"
        }
        SidebarUITestDragMarker.recordEvent(
            "route",
            dragItemID: owner?.recoveryMetadata.dragItemID ?? originalOwner?.recoveryMetadata.dragItemID,
            ownerDescription: owner?.recoveryDebugDescription ?? originalOwner?.recoveryDebugDescription ?? "nil",
            sourceID: owner?.sourceID ?? originalOwner?.sourceID,
            viewDescription: owner?.debugViewDescription ?? originalOwner?.debugViewDescription,
            details: "event=\(eventType.map(String.init(describing:)) ?? "nil") decision=\(decision) originalHit=\(originalHit.map { String(describing: type(of: $0)) } ?? "nil") originalOwner=\(originalOwner?.recoveryDebugDescription ?? "nil") owner=\(owner?.recoveryDebugDescription ?? "nil") originalOwnerSource=\(originalOwnerSource) ownerSource=\(ownerSource) originalOwnerView=\(originalOwner?.debugViewDescription ?? "nil") ownerView=\(owner?.debugViewDescription ?? "nil") hostedRoot=\(hostedRootDescription) originalOwnerRoot=\(originalOwnerRootDescription) ownerRoot=\(ownerRootDescription) originalOwnerInHostedRoot=\(originalOwnerInHostedRoot) ownerInHostedRoot=\(ownerInHostedRoot) background=\(usedBackgroundMenu)"
        )
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
