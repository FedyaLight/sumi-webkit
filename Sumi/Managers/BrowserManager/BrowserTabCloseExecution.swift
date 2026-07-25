import Foundation

/// Executes resolved tab closes: validates window residence, lets Glance
/// intercept the source tab, routes the close, and folds a split group into a
/// single aggregate closure notification.
@MainActor
final class BrowserTabCloseExecution {
    private let residences: BrowserTabResidenceAuthority
    private let glanceInterception: GlanceTabCloseInterception
    private let routing: BrowserTabCloseRouting
    private let notifications: any BrowserNotificationPresenting

    init(
        residences: BrowserTabResidenceAuthority,
        glanceInterception: GlanceTabCloseInterception,
        routing: BrowserTabCloseRouting,
        notifications: any BrowserNotificationPresenting
    ) {
        self.residences = residences
        self.glanceInterception = glanceInterception
        self.routing = routing
        self.notifications = notifications
    }

    @discardableResult
    func closeTab(_ tab: Tab, in windowState: BrowserWindowState) -> Bool {
        guard residences.containsExact(tab, in: windowState) else {
            return false
        }
        glanceInterception.interceptSourceClose(tab)
        return routing.close(tab, in: windowState)
    }

    func closeSplitGroup(
        _ tabs: [Tab],
        in windowState: BrowserWindowState
    ) {
        guard tabs.count > 1 else {
            tabs.forEach { closeTab($0, in: windowState) }
            return
        }
        if tabs.contains(where: \.isShortcutLiveInstance) {
            tabs.forEach { closeTab($0, in: windowState) }
            return
        }
        let closedCount = tabs.reduce(into: 0) { count, tab in
            guard residences.containsExact(tab, in: windowState) else { return }
            glanceInterception.interceptSourceClose(tab)
            if routing.close(
                tab,
                in: windowState,
                presentNotification: false
            ) {
                count += 1
            }
        }
        if closedCount > 0 {
            notifications.presentSplitViewClosureNotification(
                tabCount: closedCount,
                in: windowState
            )
        }
    }
}
