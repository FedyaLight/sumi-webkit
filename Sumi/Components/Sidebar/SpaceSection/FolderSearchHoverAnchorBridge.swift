import AppKit
import SwiftUI

struct FolderSearchHoverAnchorBridge: NSViewRepresentable {
    let isEnabled: Bool
    let onOpen: (NSView) -> Void
    let onHoverChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SidebarDDGHoverTrackingView {
        let view = SidebarDDGHoverTrackingView(frame: .zero)
        update(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: SidebarDDGHoverTrackingView, context: Context) {
        update(nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: SidebarDDGHoverTrackingView, coordinator: Coordinator) {
        coordinator.cancelHover()
        nsView.onHoverChanged = nil
        nsView.setHoverTrackingEnabled(false)
    }

    private func update(_ view: SidebarDDGHoverTrackingView, coordinator: Coordinator) {
        coordinator.update(
            isEnabled: isEnabled,
            onOpen: onOpen,
            onHoverChanged: onHoverChanged
        )
        view.onHoverChanged = { [weak coordinator, weak view] hovering in
            guard let coordinator, let view else { return }
            coordinator.setHovered(hovering, anchorView: view)
        }
        if view.isHoverTrackingEnabled != isEnabled {
            view.setHoverTrackingEnabled(isEnabled)
        }
        if !isEnabled {
            coordinator.cancelHover()
        }
    }

    @MainActor
    final class Coordinator {
        private var isEnabled = false
        private var isHovered = false
        private var openTask: Task<Void, Never>?
        private var onOpen: (NSView) -> Void = { _ in }
        private var onHoverChanged: (Bool) -> Void = { _ in }

        func update(
            isEnabled: Bool,
            onOpen: @escaping (NSView) -> Void,
            onHoverChanged: @escaping (Bool) -> Void
        ) {
            self.isEnabled = isEnabled
            self.onOpen = onOpen
            self.onHoverChanged = onHoverChanged
            if !isEnabled {
                cancelHover()
            }
        }

        func setHovered(
            _ hovering: Bool,
            anchorView: NSView
        ) {
            guard isEnabled else {
                cancelHover()
                return
            }

            guard isHovered != hovering else { return }
            isHovered = hovering
            onHoverChanged(hovering)

            if hovering {
                scheduleOpen(anchorView: anchorView)
            } else {
                openTask?.cancel()
                openTask = nil
            }
        }

        func cancelHover() {
            openTask?.cancel()
            openTask = nil
            guard isHovered else { return }
            isHovered = false
            onHoverChanged(false)
        }

        private func scheduleOpen(anchorView: NSView) {
            openTask?.cancel()
            openTask = Task { @MainActor [weak self, weak anchorView] in
                try? await Task.sleep(nanoseconds: FolderSearchPopoverPolicy.showDelayNanoseconds)
                guard let self,
                      let anchorView,
                      !Task.isCancelled,
                      self.isEnabled,
                      self.isHovered
                else { return }

                self.onOpen(anchorView)
            }
        }
    }
}
