import AppKit
import SwiftUI

/// SwiftUI adapter for the shared native sidebar hover implementation.
struct SidebarHoverBridge: NSViewRepresentable {
    typealias Coordinator = SidebarHoverBindingCoordinator

    @Binding var isHovered: Bool
    let session: SidebarHoverSession
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SidebarHoverTrackingView {
        let view = SidebarHoverTrackingView(frame: .zero)
        update(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: SidebarHoverTrackingView, context: Context) {
        update(nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(
        _ nsView: SidebarHoverTrackingView,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }

    private func update(
        _ view: SidebarHoverTrackingView,
        coordinator: Coordinator
    ) {
        coordinator.update(
            view: view,
            session: session,
            isHovered: $isHovered,
            isEnabled: isEnabled
        )
    }
}

private struct SidebarHoverModifier: ViewModifier {
    @Binding var isHovered: Bool
    let isEnabled: Bool

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarPresentationContext) private var presentationContext
    @Environment(\.nativeSurfaceHoverUpdatesEnabled) private var nativeSurfaceHoverUpdatesEnabled

    private var effectiveIsEnabled: Bool {
        isEnabled
            && presentationContext.allowsInteractiveWork
            && nativeSurfaceHoverUpdatesEnabled
    }

    func body(content: Content) -> some View {
        content.overlay {
            SidebarHoverBridge(
                isHovered: $isHovered,
                session: windowState.sidebarInteractionState.hoverSession,
                isEnabled: effectiveIsEnabled
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct SidebarHoverCallbackBridge: NSViewRepresentable {
    typealias Coordinator = SidebarHoverCallbackCoordinator

    let session: SidebarHoverSession
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SidebarHoverTrackingView {
        let view = SidebarHoverTrackingView(frame: .zero)
        update(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: SidebarHoverTrackingView, context: Context) {
        update(nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(
        _ nsView: SidebarHoverTrackingView,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }

    private func update(
        _ view: SidebarHoverTrackingView,
        coordinator: Coordinator
    ) {
        coordinator.update(
            view: view,
            session: session,
            isEnabled: isEnabled,
            onChange: onChange
        )
    }
}

private struct SidebarHoverActionModifier: ViewModifier {
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarPresentationContext) private var presentationContext
    @Environment(\.nativeSurfaceHoverUpdatesEnabled) private var nativeSurfaceHoverUpdatesEnabled

    private var effectiveIsEnabled: Bool {
        isEnabled
            && presentationContext.allowsInteractiveWork
            && nativeSurfaceHoverUpdatesEnabled
    }

    func body(content: Content) -> some View {
        content.overlay {
            SidebarHoverCallbackBridge(
                session: windowState.sidebarInteractionState.hoverSession,
                isEnabled: effectiveIsEnabled,
                onChange: onChange
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    func sidebarHover(
        _ isHovered: Binding<Bool>,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            SidebarHoverModifier(
                isHovered: isHovered,
                isEnabled: isEnabled
            )
        )
    }

    func sidebarHover(
        isEnabled: Bool = true,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        modifier(
            SidebarHoverActionModifier(
                isEnabled: isEnabled,
                onChange: onChange
            )
        )
    }
}

enum SidebarHoverVisualState: Equatable {
    case selected
    case hovered
    case idle
}

enum SidebarHoverChrome {
    static func visualState(isSelected: Bool, isHovered: Bool) -> SidebarHoverVisualState {
        if isSelected {
            return .selected
        }
        if isHovered {
            return .hovered
        }
        return .idle
    }

    static func showsTrailingAction(isHovered: Bool, isSelected: Bool) -> Bool {
        isHovered || isSelected
    }

    static func trailingPadding(showsTrailingAction: Bool) -> CGFloat {
        showsTrailingAction ? SidebarRowLayout.trailingActionPadding : 0
    }
}
