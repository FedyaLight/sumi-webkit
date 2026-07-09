import AppKit

@MainActor
final class GlanceOverlayKeyCommandOwner {
    private enum KeyCode {
        static let escape: UInt16 = 53
    }

    private let rootWindow: () -> NSWindow?
    private let activeWindowID: () -> UUID?
    private let dismissFloatingBarIfVisible: (UUID) -> Bool
    private let isFindBarVisible: () -> Bool
    private let hideFindBar: () -> Void
    private let closeOverlay: () -> Void
    private var keyMonitor: Any?

    init(
        rootWindow: @escaping () -> NSWindow?,
        activeWindowID: @escaping () -> UUID?,
        dismissFloatingBarIfVisible: @escaping (UUID) -> Bool,
        isFindBarVisible: @escaping () -> Bool,
        hideFindBar: @escaping () -> Void,
        closeOverlay: @escaping () -> Void
    ) {
        self.rootWindow = rootWindow
        self.activeWindowID = activeWindowID
        self.dismissFloatingBarIfVisible = dismissFloatingBarIfVisible
        self.isFindBarVisible = isFindBarVisible
        self.hideFindBar = hideFindBar
        self.closeOverlay = closeOverlay
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
              let rootWindow = rootWindow(),
              event.window === rootWindow
        else { return event }

        return handleEscapeKeyForActiveOverlay() ? nil : event
    }

    @discardableResult
    func handleEscapeKeyForActiveOverlay() -> Bool {
        guard let windowID = activeWindowID() else { return false }

        if dismissFloatingBarIfVisible(windowID) {
            return true
        }

        if isFindBarVisible() {
            hideFindBar()
            return true
        }

        closeOverlay()
        return true
    }
}
