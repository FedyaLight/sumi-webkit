@MainActor
final class ShortcutLiveRetirementScopedPortEffect {
    enum TabClosurePublicationIntent {
        case publishExactTabs
        case terminalDrainAlreadyPublished
    }

    private let attachment: TabRuntimeAttachmentWitness
    private let tabsRequiringClosurePublication: [Tab]
    private let windows: [ShortcutLiveRetirementBatchWindowEntry]
    private let validatesWindowState: Bool

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
        validatesWindowState = plan.result.didClearCurrentSelection
    }

    func publish() {
        guard attachment.isCurrent(),
              let runtime = attachment.lease.registry else { return }
        for tab in tabsRequiringClosurePublication {
            guard attachment.isCurrent() else { return }
            tab.mediaRuntime.callbacks.notifyNowPlayingTabUnloaded(tab.id)
            guard attachment.isCurrent() else { return }
            runtime.notifyTabClosedIfLoaded(tab)
            guard attachment.isCurrent() else { return }
        }

        var validatedWindowIDs = Set<UUID>()
        if validatesWindowState {
            validatedWindowIDs = runtime.validateWindowStates()
            guard attachment.isCurrent() else { return }
        }
        for entry in windows
        where validatedWindowIDs.contains(entry.window.id) == false {
            guard attachment.isCurrent() else { return }
            guard runtime.windowState(for: entry.window.id) === entry.window else {
                guard attachment.isCurrent() else { return }
                continue
            }
            guard attachment.isCurrent() else { return }
            runtime.persistWindowSession(for: entry.window)
            guard attachment.isCurrent() else { return }
        }
    }
}
