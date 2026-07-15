@MainActor
enum RegularTabShortcutSidebarBindingPreflight {
    case noChange
    case launcher(
        PreparedShortcutSplitLauncherRestorationBatch,
        ShortcutSplitLauncherBindingPreflight
    )

    var builder: ShortcutTabBindingBatchBuilder? {
        guard case .launcher(_, let preflight) = self else { return nil }
        return preflight.builder
    }

    func prepareContribution(
        after insertion: ShortcutSplitLauncherCatalogInsertionPlan,
        catalog: ShortcutSplitLauncherCatalogTransaction,
        builder: ShortcutTabBindingBatchBuilder
    ) -> RegularTabShortcutSidebarBindingContribution? {
        switch self {
        case .noChange:
            return ShortcutSplitLauncherBindingContribution.insertionOnly(
                insertion,
                catalog: catalog,
                builder: builder
            ).map(RegularTabShortcutSidebarBindingContribution.launcher)
        case .launcher(let restorations, let preflight):
            return restorations.prepareBindingContribution(
                preflight,
                after: insertion
            ).map(RegularTabShortcutSidebarBindingContribution.launcher)
        }
    }
}

@MainActor
enum RegularTabShortcutSidebarBindingContribution {
    case noChange
    case launcher(ShortcutSplitLauncherBindingContribution)

    var binding: ShortcutTabBindingBatchContribution? {
        guard case .launcher(let contribution) = self else { return nil }
        return contribution.binding
    }

    func prepareComposedTransaction(
        additional: ShortcutTabBindingBatchContribution?,
        windows: [ShortcutTabBindingWindowContribution]
    ) -> ShortcutSplitLauncherBindingContribution.ComposedPreparationOutcome {
        switch self {
        case .noChange:
            return .conflicted
        case .launcher(let contribution):
            return contribution.prepareComposedTransaction(
                additional: additional,
                windows: windows
            )
        }
    }

    func admitPresentationIdentity(
        to presentation: PreparedWindowSplitPresentationSettlement
    ) -> Bool {
        guard case .launcher(let contribution) = self,
              let handoff = contribution
                  .preparePresentationIdentityHandoff() else { return false }
        return presentation.admitCatalogIdentityHandoff(handoff)
    }

    func requestTerminalFolderCommit(
        using folderOpenState: TabFolderOpenStateService
    ) {
        guard case .launcher(let contribution) = self else { return }
        contribution.folders.requestCommit(openingFoldersWith: folderOpenState)
    }

    func rollbackBeforeExecution() -> Bool {
        switch self {
        case .noChange:
            return true
        case .launcher(let contribution):
            return contribution.rollbackBeforeExecution()
        }
    }
}
