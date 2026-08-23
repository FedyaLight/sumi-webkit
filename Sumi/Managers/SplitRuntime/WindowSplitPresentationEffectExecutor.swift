import Foundation

/// Executes complete outward window effects in their required order. Every reentrant
/// callback is followed by a fresh exact-witness check before the next effect.
@MainActor
final class WindowSplitPresentationEffectExecutor {
    private let selection: BrowserTabSelectionOwner
    private let updates: SplitWindowUpdateStream.Channel
    private let visuals: BrowserWindowVisualCoordinator
    private let persistence: WindowSessionPersistenceCoordinator

    init(
        selection: BrowserTabSelectionOwner,
        updates: SplitWindowUpdateStream.Channel,
        visuals: BrowserWindowVisualCoordinator,
        persistence: WindowSessionPersistenceCoordinator
    ) {
        self.selection = selection
        self.updates = updates
        self.visuals = visuals
        self.persistence = persistence
    }

    func selectWithoutPersistence(
        _ tab: Tab,
        in window: BrowserWindowState
    ) {
        _ = selection.applyTabSelection(
            tab,
            in: window,
            updateSpaceFromTab: true,
            updateTheme: true,
            rememberSelection: true,
            persistSelection: false,
            loadPolicy: .immediate
        )
    }

    func publishSynchronizedWindow(
        _ window: BrowserWindowState,
        previousState: WindowSplitPresentationPersistedState,
        urgency: WindowSplitSessionWriteUrgency
    ) {
        updates.publish(windowID: window.id)
        visuals.refreshCompositor(for: window)
        if previousState != WindowSplitPresentationPersistedState(window) {
            writeSession(for: window, urgency: urgency)
        }
    }

    func refreshPresentation(_ window: BrowserWindowState) {
        updates.publish(windowID: window.id)
        visuals.refreshCompositor(for: window)
    }

    func publishTerminalEffects(
        witness: WindowSplitPresentationTerminalWitness
    ) {
        let plan = witness.plan
        for windowPlan in plan.windows {
            guard witness.isCurrent(windowPlan) else {
                continue
            }
            if let activeTab = windowPlan.activeTab {
                _ = selection.publishPreparedSelectionEffects(
                    activeTab,
                    in: windowPlan.window,
                    previousTabID: windowPlan.expectedWindowState.currentTabId,
                    previousSpaceID: windowPlan.expectedWindowState.currentSpaceId
                )
            }
            guard witness.isCurrent(windowPlan) else {
                continue
            }
            updates.publish(windowID: windowPlan.window.id)
            guard witness.isCurrent(windowPlan) else {
                continue
            }
            visuals.refreshCompositor(for: windowPlan.window)
            guard witness.isCurrent(windowPlan) else {
                continue
            }
            if windowPlan.before
                != WindowSplitPresentationPersistedState(windowPlan.window) {
                writeSession(
                    for: windowPlan.window,
                    urgency: plan.sessionWriteUrgency
                )
            }
        }
    }

    private func writeSession(
        for window: BrowserWindowState,
        urgency: WindowSplitSessionWriteUrgency
    ) {
        switch urgency {
        case .scheduled:
            persistence.schedule(window)
        case .immediate:
            persistence.persist(window)
        }
    }
}
