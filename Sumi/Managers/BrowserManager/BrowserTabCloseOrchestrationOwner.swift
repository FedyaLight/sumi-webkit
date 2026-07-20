import Foundation

@MainActor
final class BrowserTabCloseOrchestrationOwner {
    private let context: BrowserCurrentTabCloseContext
    private let glanceInterception: GlanceTabCloseInterception
    private let routing: BrowserTabCloseRouting
    private let residences: BrowserTabResidenceAuthority

    init(
        context: BrowserCurrentTabCloseContext,
        glanceInterception: GlanceTabCloseInterception,
        routing: BrowserTabCloseRouting,
        residences: BrowserTabResidenceAuthority
    ) {
        self.context = context
        self.glanceInterception = glanceInterception
        self.routing = routing
        self.residences = residences
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

        closeTargets.forEach { closeTab($0, in: windowState) }
    }

    func closeTab(_ tab: Tab, in windowState: BrowserWindowState) {
        guard residences.containsExact(tab, in: windowState) else {
            return
        }
        glanceInterception.interceptSourceClose(tab)
        routing.close(tab, in: windowState)
    }
}
