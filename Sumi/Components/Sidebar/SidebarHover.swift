import AppKit
import SwiftUI

/// SwiftUI adapter for the shared native sidebar hover implementation.
struct SidebarHoverBridge: NSViewRepresentable {
    typealias Coordinator = SidebarHoverBindingCoordinator

    @Binding var isHovered: Bool
    let session: SidebarHoverSession
    let isEnabled: Bool
    let layer: SidebarHoverLayer

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
            isEnabled: isEnabled,
            layer: layer
        )
    }
}

private struct SidebarHoverModifier: ViewModifier {
    @Binding var isHovered: Bool
    let isEnabled: Bool
    let layer: SidebarHoverLayer

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
                isEnabled: effectiveIsEnabled,
                layer: layer
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onChange(of: effectiveIsEnabled) { _, enabled in
            if !enabled {
                isHovered = false
            }
        }
    }
}

private struct SidebarHoverCallbackBridge: NSViewRepresentable {
    typealias Coordinator = SidebarHoverCallbackCoordinator

    let session: SidebarHoverSession
    let isEnabled: Bool
    let layer: SidebarHoverLayer
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
            layer: layer,
            onChange: onChange
        )
    }
}

private struct SidebarHoverActionModifier: ViewModifier {
    let isEnabled: Bool
    let layer: SidebarHoverLayer
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
                layer: layer,
                onChange: onChange
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onChange(of: effectiveIsEnabled) { _, enabled in
            if !enabled {
                onChange(false)
            }
        }
    }
}

extension View {
    func sidebarHover(
        _ isHovered: Binding<Bool>,
        isEnabled: Bool = true,
        layer: SidebarHoverLayer = .normal
    ) -> some View {
        modifier(
            SidebarHoverModifier(
                isHovered: isHovered,
                isEnabled: isEnabled,
                layer: layer
            )
        )
    }

    func sidebarHover(
        isEnabled: Bool = true,
        layer: SidebarHoverLayer = .normal,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        modifier(
            SidebarHoverActionModifier(
                isEnabled: isEnabled,
                layer: layer,
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
}
