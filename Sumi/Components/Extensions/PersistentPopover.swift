import SwiftUI
import AppKit

// Presents content in an NSPopover and keeps SwiftUI state in sync
// when the popover closes itself.
struct PersistentPopover<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    @Binding var contentSize: CGSize
    let preferredEdge: NSRectEdge
    let behavior: NSPopover.Behavior
    let onClose: (() -> Void)?
    let content: () -> Content

    init(
        isPresented: Binding<Bool>,
        contentSize: Binding<CGSize>,
        preferredEdge: NSRectEdge = .maxY,
        behavior: NSPopover.Behavior = .applicationDefined,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        self._contentSize = contentSize
        self.preferredEdge = preferredEdge
        self.behavior = behavior
        self.onClose = onClose
        self.content = content
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onClose = onClose

        if isPresented {
            if coordinator.popover == nil || coordinator.popover?.isShown == false {
                let popover = NSPopover()
                popover.behavior = behavior
                popover.delegate = coordinator
                let hosting = NSHostingController(rootView: content())
                coordinator.hostingController = hosting
                popover.contentViewController = hosting
                popover.contentSize = contentSize
                coordinator.popover = popover
                if let anchor = coordinator.anchorView {
                    // Present on next runloop to avoid starting a CA transaction during commit
                    DispatchQueue.main.async {
                        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: preferredEdge)
                    }
                }
            } else {
                // Update content and size when already shown
                if let hosting = coordinator.hostingController {
                    // Avoid re-entrant layout by scheduling updates on next runloop
                    DispatchQueue.main.async {
                        hosting.rootView = content()
                    }
                }
                if coordinator.popover?.contentSize != contentSize {
                    let newSize = contentSize
                    DispatchQueue.main.async {
                        coordinator.popover?.contentSize = newSize
                    }
                }
            }
        } else {
            // Close asynchronously to avoid interfering with current commit transactions
            if let pop = coordinator.popover {
                DispatchQueue.main.async {
                    pop.performClose(nil)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        private var isPresented: Binding<Bool>
        var popover: NSPopover?
        weak var anchorView: NSView?
        var hostingController: NSHostingController<Content>?
        var onClose: (() -> Void)?

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        func popoverDidClose(_ notification: Notification) {
            popover = nil
            hostingController = nil
            if isPresented.wrappedValue {
                isPresented.wrappedValue = false
            }
            onClose?()
        }
    }
}
