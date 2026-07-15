import Foundation

/// Resolves displayed versus detached runtime work after the durable snapshot
/// has been captured.
@MainActor
final class RegularTabShortcutWindowPlanResolver {
    private let windows: ShortcutTabWindowQuery
    private let runtimeConnection: TabRuntimePortConnection
    private let snapshots = ShortcutConversionWindowSnapshotResolver()

    init(
        windows: ShortcutTabWindowQuery,
        runtimeConnection: TabRuntimePortConnection
    ) {
        self.windows = windows
        self.runtimeConnection = runtimeConnection
    }

    func resolve(
        tab: Tab,
        structure: RegularTabShortcutStructurePlan,
        preferredWindowID: UUID?
    ) -> TabShortcutConversionPreparation {
        guard let runtime = runtimeConnection.captureLease().registry else {
            return tab.hasBrowserRuntime ? .rejected : .detached(
                DetachedTabShortcutConversionPlan(
                    sourceTabId: tab.id,
                    runtime: nil,
                    structure: structure
                )
            )
        }
        let primary = runtime.webViewLifecycle.primaryTrackedWindowId(for: tab.id)
        let selected = windows.windowIdsSelecting(
            tabId: tab.id,
            preferredWindowId: preferredWindowID,
            using: runtime
        )
        let displaying = windows.windowIdsDisplaying(
            tabId: tab.id,
            preferredWindowId: preferredWindowID,
            using: runtime
        )
        let presentation = snapshots.presentationWindowIDs(
            structure: structure,
            selected: selected,
            displaying: displaying,
            runtime: runtime
        )
        guard let firstID = selected.first ?? displaying.first
                ?? presentation.first else {
            return .detached(DetachedTabShortcutConversionPlan(
                sourceTabId: tab.id,
                runtime: runtime,
                structure: structure
            ))
        }
        guard primary == nil || primary == firstID,
              let firstWindow = runtime.windowState(for: firstID),
              snapshots.runtimeExposureIsValid(
                  tabID: tab.id,
                  structure: structure,
                  presentationWindowIDs: presentation,
                  runtime: runtime
              ) else { return .rejected }

        return .displayed(DisplayedTabShortcutConversionPlan(
            sourceTabId: tab.id,
            runtime: runtime,
            structure: structure,
            selectedWindowIds: selected,
            displayingWindowIds: displaying,
            presentationWindowIds: presentation,
            primaryWindowId: primary,
            firstWindowId: firstID,
            firstWindow: firstWindow
        ))
    }
}
