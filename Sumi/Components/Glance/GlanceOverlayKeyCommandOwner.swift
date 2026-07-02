import AppKit

@MainActor
final class GlanceOverlayKeyCommandOwner {
    struct Dependencies {
        let rootWindow: () -> NSWindow?
        let activeWindowID: () -> UUID?
        let dismissFloatingBarIfVisible: (UUID) -> Bool
        let isFindBarVisible: () -> Bool
        let hideFindBar: () -> Void
        let closeOverlay: () -> Void
    }

    private enum KeyCode {
        static let escape: UInt16 = 53
    }

    private let dependencies: Dependencies
    private var keyMonitor: Any?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func installIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    func uninstall() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == KeyCode.escape,
              let rootWindow = dependencies.rootWindow(),
              event.window === rootWindow
        else { return event }

        return handleEscapeKeyForActiveOverlay() ? nil : event
    }

    @discardableResult
    func handleEscapeKeyForActiveOverlay() -> Bool {
        guard let windowID = dependencies.activeWindowID() else { return false }

        if dependencies.dismissFloatingBarIfVisible(windowID) {
            return true
        }

        if dependencies.isFindBarVisible() {
            dependencies.hideFindBar()
            return true
        }

        dependencies.closeOverlay()
        return true
    }
}
