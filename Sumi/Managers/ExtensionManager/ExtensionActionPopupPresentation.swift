import AppKit
import WebKit

@available(macOS 15.5, *)
@MainActor
enum ExtensionActionPopupPresentation {
    struct TransientSession {
        let coordinator: SidebarTransientSessionCoordinator
        let token: SidebarTransientSessionToken?
    }

    static func beginTransientSession(
        for target: ExtensionActionPopupPresentationTarget
    ) -> TransientSession {
        let coordinator = target.source.windowState
            .sidebarTransientSessionCoordinator
        let source = coordinator.preparedPresentationSource(
            window: target.presentationWindow,
            ownerView: target.anchor?.buttonView
        )
        return TransientSession(
            coordinator: coordinator,
            token: coordinator.beginSession(
                kind: .extensionActionPopover,
                source: source,
                path: "ExtensionActionPopupCoordinator.present"
            )
        )
    }

    static func anchorRect(for anchorView: NSView) -> CGRect {
        let bounds = anchorView.bounds
        guard bounds.width < 4 || bounds.height < 4 else {
            return bounds
        }
        let side = max(28, max(bounds.width, bounds.height))
        return CGRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
    }

    static func show(
        _ popover: NSPopover,
        relativeTo anchorView: NSView,
        preferredEdge: NSRectEdge
    ) {
        popover.show(
            relativeTo: anchorRect(for: anchorView),
            of: anchorView,
            preferredEdge: preferredEdge
        )
    }
}
