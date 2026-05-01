import AppKit

@MainActor
final class CollapsedSidebarPointerSuppressionController {
    static let monitoredEventTypes: NSEvent.EventTypeMask = [.mouseMoved, .cursorUpdate]

    var isMonitorInstalledForTesting: Bool {
        false
    }

    var currentPanelRectForTesting: NSRect? {
        nil
    }

    func update(
        window: NSWindow?,
        panelView: NSView?,
        hostedSidebarView: NSView?,
        isCollapsedVisible: Bool,
        isSidebarCollapsed: Bool,
        isBrowserWindowActive: Bool
    ) {
        _ = window
        _ = panelView
        _ = hostedSidebarView
        _ = isCollapsedVisible
        _ = isSidebarCollapsed
        _ = isBrowserWindowActive
    }

    func refreshPanelRect() {}

    func teardown() {}
}
