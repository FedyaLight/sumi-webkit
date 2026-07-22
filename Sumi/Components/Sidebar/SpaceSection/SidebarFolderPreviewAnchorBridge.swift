import AppKit
import SwiftUI

/// Hover sensor over a collapsed folder header that arms the preview panel.
///
/// Mirrors Zen's `mouseenter`/`mouseleave` pair on `.tab-group-label-container`:
/// a delayed open, cancelled the moment the pointer leaves.
struct SidebarFolderPreviewAnchorBridge: NSViewRepresentable {
    let hoverSession: SidebarHoverSession
    let isEnabled: Bool
    /// Reports the anchor view plus its frame in the window's SwiftUI-global space.
    let onOpen: (NSView, CGRect) -> Void
    let onHoverChanged: (Bool) -> Void

    /// Whether a text editor currently holds the keyboard in `window`.
    ///
    /// Opening the preview focuses its search field, so this is the Sumi
    /// counterpart to Zen's `gURLBar.focused || zen-renaming-tab` bail-out —
    /// widened to any field editor, since the floating bar is permanently
    /// visible on the new-tab page and visibility alone says nothing about who
    /// owns keyboard input.
    @MainActor
    static func isTextEntryActive(in window: NSWindow?) -> Bool {
        switch window?.firstResponder {
        case let textView as NSTextView:
            return textView.isFieldEditor || textView.isEditable
        case is NSTextField:
            return true
        default:
            return false
        }
    }

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

    static func dismantleNSView(_ nsView: SidebarHoverTrackingView, coordinator: Coordinator) {
        coordinator.disconnect()
    }

    private func update(_ view: SidebarHoverTrackingView, coordinator: Coordinator) {
        coordinator.update(
            view: view,
            hoverSession: hoverSession,
            isEnabled: isEnabled,
            onOpen: onOpen,
            onHoverChanged: onHoverChanged
        )
        // Deliberately no re-arm from the current pointer position here: it would
        // fire the hover timer again the instant a click collapses the folder,
        // and the panel that opens under the pointer swallows the next click.
        // Arming stays driven by real enter/exit events — enforced one level down
        // in `setHovered`, since enabling hover tracking makes the view re-read
        // the parked pointer and report that as a hover of its own.
    }

    @MainActor
    final class Coordinator {
        private let hoverRegistration = SidebarHoverRegistration()
        private var isEnabled = false
        private var isHovered = false
        private var openTask: Task<Void, Never>?
        private var onOpen: (NSView, CGRect) -> Void = { _, _ in }
        private var onHoverChanged: (Bool) -> Void = { _ in }

        func update(
            view: SidebarHoverTrackingView,
            hoverSession: SidebarHoverSession,
            isEnabled: Bool,
            onOpen: @escaping (NSView, CGRect) -> Void,
            onHoverChanged: @escaping (Bool) -> Void
        ) {
            self.isEnabled = isEnabled
            self.onOpen = onOpen
            self.onHoverChanged = onHoverChanged
            if !isEnabled {
                cancelHover()
            }
            hoverRegistration.update(
                view: view,
                session: hoverSession,
                isEnabled: isEnabled
            ) { [weak self, weak view] hovering, source in
                guard let self, let view else { return }
                self.setHovered(hovering, source: source, anchorView: view)
            }
        }

        func disconnect() {
            hoverRegistration.disconnect()
            cancelHover()
        }

        func setHovered(
            _ hovering: Bool,
            source: SidebarHoverChangeSource,
            anchorView: NSView
        ) {
            guard isEnabled else {
                cancelHover()
                return
            }

            guard isHovered != hovering else { return }
            isHovered = hovering
            // Hover bookkeeping takes both sources: an open panel has to keep
            // reading the anchor's state even when the report came from a
            // reconcile, or it would never learn the anchor went away.
            onHoverChanged(hovering)

            guard hovering else {
                openTask?.cancel()
                openTask = nil
                return
            }
            guard SidebarFolderPreviewHoverPolicy.allowsArmingOpen(hoverSource: source) else { return }

            scheduleOpen(anchorView: anchorView)
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
                try? await Task.sleep(
                    nanoseconds: SidebarFolderPreviewHoverPolicy.showDelayNanoseconds
                )
                guard let self,
                      let anchorView,
                      !Task.isCancelled,
                      self.isEnabled,
                      self.isHovered,
                      let anchorRect = Self.swiftUIGlobalFrame(of: anchorView)
                else { return }

                self.onOpen(anchorView, anchorRect)
            }
        }

        /// The preview is placed by a window-level SwiftUI overlay, so the anchor
        /// has to cross from AppKit's bottom-left space into SwiftUI's `.global`.
        private static func swiftUIGlobalFrame(of view: NSView) -> CGRect? {
            guard let window = view.window else { return nil }
            // `convert(_:to: nil)` already resolves any flipped ancestors, so the
            // rect's `maxY` is reliably the anchor's top edge in window space.
            let windowRect = view.convert(view.bounds, to: nil)
            let topLeading = SidebarDragLocationMapper.swiftUIGlobalPoint(
                fromWindowPoint: CGPoint(x: windowRect.minX, y: windowRect.maxY),
                in: window
            )
            return CGRect(origin: topLeading, size: windowRect.size)
        }
    }
}
