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
    private let publishPreparedSelectionEffects: @MainActor (
        Tab,
        BrowserWindowState,
        UUID?,
        UUID?
    ) -> Void
    private let publishWindowChangeAction: @MainActor (UUID) -> Void
    private let refreshCompositorAction: @MainActor (
        BrowserWindowState
    ) -> Void
    private let scheduleWindowSession: @MainActor (
        BrowserWindowState
    ) -> Void
    private let persistWindowSession: @MainActor (
        BrowserWindowState
    ) -> Void

    init(
        publishPreparedSelectionEffects: @escaping @MainActor (
            Tab,
            BrowserWindowState,
            UUID?,
            UUID?
        ) -> Void,
        publishWindowChange: @escaping @MainActor (UUID) -> Void,
        refreshCompositor: @escaping @MainActor (
            BrowserWindowState
        ) -> Void,
        scheduleWindowSession: @escaping @MainActor (
            BrowserWindowState
        ) -> Void,
        persistWindowSession: @escaping @MainActor (
            BrowserWindowState
        ) -> Void
    ) {
        self.publishPreparedSelectionEffects =
            publishPreparedSelectionEffects
        publishWindowChangeAction = publishWindowChange
        refreshCompositorAction = refreshCompositor
        self.scheduleWindowSession = scheduleWindowSession
        self.persistWindowSession = persistWindowSession
    }

    func publishSynchronizedWindow(
        _ window: BrowserWindowState,
        previousState: WindowSplitPresentationPersistedState,
        urgency: WindowSplitSessionWriteUrgency
    ) {
        publishWindowChangeAction(window.id)
        refreshCompositorAction(window)
        if previousState != WindowSplitPresentationPersistedState(window) {
            writeSession(for: window, urgency: urgency)
        }
    }

    func refreshPresentation(_ window: BrowserWindowState) {
        publishWindowChangeAction(window.id)
        refreshCompositorAction(window)
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
                publishPreparedSelectionEffects(
                    activeTab,
                    windowPlan.window,
                    windowPlan.expectedWindowState.currentTabId,
                    windowPlan.expectedWindowState.currentSpaceId
                )
            }
            guard witness.isCurrent(windowPlan) else {
                continue
            }
            publishWindowChangeAction(windowPlan.window.id)
            guard witness.isCurrent(windowPlan) else {
                continue
            }
            refreshCompositorAction(windowPlan.window)
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
            scheduleWindowSession(window)
        case .immediate:
            persistWindowSession(window)
        }
    }
}
