import Foundation

@MainActor
final class BrowserTabCloseOrchestrationOwner {
    private let context: BrowserCurrentTabCloseContext
    private let glanceInterception: GlanceTabCloseInterception
    private let routing: BrowserTabCloseRouting
    private let execution: BrowserTabCloseExecution

    init(
        context: BrowserCurrentTabCloseContext,
        glanceInterception: GlanceTabCloseInterception,
        routing: BrowserTabCloseRouting,
        execution: BrowserTabCloseExecution
    ) {
        self.context = context
        self.glanceInterception = glanceInterception
        self.routing = routing
        self.execution = execution
    }

    func closeCurrentTab() {
        guard let activeWindow = context.activeWindow else {
            return
        }

        closeCurrentTab(in: activeWindow)
    }

    func closeCurrentTab(in windowState: BrowserWindowState) {
        if windowState.presentationState.isCommandPaletteVisible {
            return
        }
        closeResolvedCurrentTab(in: windowState)
    }

    /// Command-palette commits are already serialized by the palette's native
    /// interaction session, so the visible palette is the source of this close
    /// rather than an overlay that should intercept it.
    func closeCurrentTabFromCommandPalette(
        in windowState: BrowserWindowState
    ) {
        closeResolvedCurrentTab(in: windowState)
    }

    private func closeResolvedCurrentTab(
        in windowState: BrowserWindowState
    ) {
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
        execution.closeTab(tab, in: windowState)
    }

    func closeSplitGroup(
        _ tabs: [Tab],
        in windowState: BrowserWindowState
    ) {
        execution.closeSplitGroup(tabs, in: windowState)
    }
}
