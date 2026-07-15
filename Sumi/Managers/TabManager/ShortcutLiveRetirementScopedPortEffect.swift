@MainActor
final class ShortcutLiveRetirementScopedPortEffect {
    enum TabClosurePublicationIntent {
        case publishExactTabs
        case terminalDrainAlreadyPublished
    }

    private let attachment: TabRuntimeAttachmentWitness
    private let tabsRequiringClosurePublication: [Tab]
    private let windows: [ShortcutLiveRetirementBatchWindowEntry]

    init(
        plan: ShortcutLiveRetirementBatchPlan,
        tabClosure: TabClosurePublicationIntent
    ) {
        attachment = plan.attachment
        switch tabClosure {
        case .publishExactTabs:
            tabsRequiringClosurePublication = plan.tabs
        case .terminalDrainAlreadyPublished:
            tabsRequiringClosurePublication = []
        }
        windows = plan.windows.filter(\.requiresPersistence)
    }

    func publish() {
        guard attachment.isCurrent(),
              let runtime = attachment.lease.registry else { return }
        tabsRequiringClosurePublication.forEach(
            runtime.notifyTabClosedIfLoaded
        )
        for entry in windows
        where runtime.windowState(for: entry.window.id) === entry.window {
            runtime.persistWindowSession(for: entry.window)
        }
    }
}
