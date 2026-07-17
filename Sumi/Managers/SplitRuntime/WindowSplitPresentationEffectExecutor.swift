import Foundation

/// Unforgeable outside the terminal executor. A downstream prepared effect may
/// publish only when its exact window completed every base presentation effect.
@MainActor
struct WindowSplitPresentationTerminalWindowReceipt {
    fileprivate let window: BrowserWindowState

    fileprivate init(window: BrowserWindowState) {
        self.window = window
    }

    func matches(_ candidate: BrowserWindowState) -> Bool {
        window === candidate
    }
}

/// Prepared, exact-window terminal effect. The settlement owns participants
/// from admission through publication; callers cannot inject a late callback.
@MainActor
protocol WindowSplitPresentationTerminalParticipant: AnyObject {
    var targetWindow: BrowserWindowState { get }
    func publish(after receipt: WindowSplitPresentationTerminalWindowReceipt)
}

typealias WindowSplitPresentationTerminalParticipants = [
    any WindowSplitPresentationTerminalParticipant
]

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
        witness: WindowSplitPresentationTerminalWitness,
        participants: WindowSplitPresentationTerminalParticipants
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
            guard witness.isCurrent(windowPlan) else {
                continue
            }
            let receipt = WindowSplitPresentationTerminalWindowReceipt(
                window: windowPlan.window
            )
            for participant in participants
                where participant.targetWindow === windowPlan.window {
                guard witness.isCurrent(windowPlan) else {
                    break
                }
                participant.publish(after: receipt)
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
