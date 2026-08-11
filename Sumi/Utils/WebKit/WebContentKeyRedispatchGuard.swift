import AppKit
import WebKit

/// Prevents an unhandled WebKit key event from reaching AppKit twice and
/// terminating in `noResponder(for:)` on its second delivery.
@MainActor
final class WebContentKeyRedispatchGuard {
    private final class EventMonitorHandle {
        private let monitor: Any

        init(_ monitor: Any) {
            self.monitor = monitor
        }

        deinit {
            NSEvent.removeMonitor(monitor)
        }
    }

    private let deliveredWebContentEvents = NSHashTable<NSEvent>(
        options: [.weakMemory, .objectPointerPersonality]
    )
    private var eventMonitor: EventMonitorHandle?

    init(installEventMonitor: Bool = true) {
        guard installEventMonitor,
              let monitor = NSEvent.addLocalMonitorForEvents(
                matching: .keyDown,
                handler: { [weak self] event in
                    self?.route(event) ?? event
                }
              ) else { return }
        eventMonitor = EventMonitorHandle(monitor)
    }

    func route(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown else { return event }
        if deliveredWebContentEvents.contains(event) {
            deliveredWebContentEvents.remove(event)
            return nil
        }
        guard Self.isWebContentFirstResponder(in: event.window) else {
            return event
        }
        deliveredWebContentEvents.add(event)
        return event
    }

    private static func isWebContentFirstResponder(
        in window: NSWindow?
    ) -> Bool {
        var view = window?.firstResponder as? NSView
        while let current = view {
            if current is WKWebView { return true }
            view = current.superview
        }
        return false
    }
}
