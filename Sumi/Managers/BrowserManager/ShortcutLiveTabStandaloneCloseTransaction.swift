import Foundation

/// Commits a non-split live shortcut retirement. History publication runs
/// only after exact retirement preparation and before visible handoff.
@MainActor
final class ShortcutLiveTabStandaloneCloseTransaction {
    private let tabStore: any ShellSelectionTabStore
    private let structuralLookup: TabStructuralLookupCoordinator
    private let retirement: ShortcutLiveTabRetirementService
    private let selectionTarget: ShortcutLiveTabCloseSelectionTarget
    private let visuals: BrowserWindowVisualCoordinator

    init(
        tabStore: any ShellSelectionTabStore,
        structuralLookup: TabStructuralLookupCoordinator,
        retirement: ShortcutLiveTabRetirementService,
        selectionTarget: ShortcutLiveTabCloseSelectionTarget,
        visuals: BrowserWindowVisualCoordinator
    ) {
        self.tabStore = tabStore
        self.structuralLookup = structuralLookup
        self.retirement = retirement
        self.selectionTarget = selectionTarget
        self.visuals = visuals
    }

    func close(
        _ tab: Tab,
        pinID: UUID,
        in windowState: BrowserWindowState,
        publishingHistory: @MainActor () -> Void
    ) -> Bool {
        guard tabStore.liveShortcutTabs(in: windowState.id).contains(where: {
            $0 === tab && $0.shortcutPinId == pinID
        }) else { return false }
        let wasCurrent = ShortcutSelectionIdentity.isSelected(
            tabId: tab.id,
            pinId: pinID,
            in: windowState
        )
        let target = selectionTarget.target(
            afterClosing: tab,
            in: windowState,
            wasCurrent: wasCurrent
        )
        let preparedRetirement = structuralLookup.withTransaction {
            retirement.prepareRetirement(
                pinId: pinID,
                in: windowState.id,
                targetWindowState: target
            )
        }
        guard let preparedRetirement,
              preparedRetirement.result.didRetire else { return false }

        publishingHistory()
        if wasCurrent {
            _ = visuals.performImmediateVisualHandoffIfPossible(
                in: windowState
            )
        }
        _ = retirement.finish(preparedRetirement)
        return true
    }
}
