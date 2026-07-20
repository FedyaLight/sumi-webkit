import Foundation

@MainActor
final class BrowserTabCloseOrchestrationOwner {
    private let context: BrowserCurrentTabCloseContext
    private let glanceInterception: GlanceTabCloseInterception
    private let routing: BrowserTabCloseRouting
    private let residences: BrowserTabResidenceAuthority
    private let notifications: any BrowserNotificationPresenting

    init(
        context: BrowserCurrentTabCloseContext,
        glanceInterception: GlanceTabCloseInterception,
        routing: BrowserTabCloseRouting,
        residences: BrowserTabResidenceAuthority,
        notifications: any BrowserNotificationPresenting
    ) {
        self.context = context
        self.glanceInterception = glanceInterception
        self.routing = routing
        self.residences = residences
        self.notifications = notifications
    }

    func closeCurrentTab() {
        guard let activeWindow = context.activeWindow else {
            return
        }

        closeCurrentTab(in: activeWindow)
    }

    func closeCurrentTab(in windowState: BrowserWindowState) {
        if windowState.presentationState.isFloatingBarVisible {
            return
        }

        if glanceInterception.interceptCurrentClose(in: windowState) {
            return
        }

        let closeTargets = context.currentCloseTargets(in: windowState)
        guard closeTargets.isEmpty == false else {
            routing.showEmptyState(in: windowState)
            return
        }

        if closeTargets.count > 1 {
            closeSplitGroup(closeTargets, in: windowState)
        } else {
            closeTargets.forEach { closeTab($0, in: windowState) }
        }
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
