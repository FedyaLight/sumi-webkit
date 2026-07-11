import Foundation

/// Revalidates the window/runtime half of a prepared conversion.
@MainActor
final class TabShortcutConversionAuthorizer {
    private let windows: ShortcutTabWindowQuery

    init(windows: ShortcutTabWindowQuery) {
        self.windows = windows
    }

    func authorize(
        _ preparation: TabShortcutConversionPreparation,
        for tab: Tab
    ) -> AuthorizedTabShortcutConversion? {
        switch preparation {
        case .displayed(let plan):
            return authorize(plan, for: tab).map {
                .displayed($0)
            }
        case .detached(let plan):
            return authorize(plan, for: tab).map {
                .detached($0)
            }
        case .rejected:
            return nil
        }
    }

    func authorize(
        _ plan: DisplayedTabShortcutConversionPlan,
        for tab: Tab
    ) -> AuthorizedDisplayedTabShortcutConversion? {
        guard plan.sourceTabId == tab.id else { return nil }
        let selectedWindowIds = windows.windowIdsSelecting(
            tabId: tab.id,
            preferredWindowId: plan.firstWindowId,
            using: plan.runtime
        )
        let displayingWindowIds = windows.windowIdsDisplaying(
            tabId: tab.id,
            preferredWindowId: plan.firstWindowId,
            using: plan.runtime
        )
        let snapshots = ShortcutConversionWindowSnapshotResolver()
        let presentationWindowIds = snapshots.presentationWindowIDs(
            structure: plan.structure,
            selected: selectedWindowIds,
            displaying: displayingWindowIds,
            runtime: plan.runtime
        )
        guard plan.runtime.webViewLifecycle.primaryTrackedWindowId(
                  for: tab.id
              ) == plan.primaryWindowId,
              Set(selectedWindowIds) == Set(plan.selectedWindowIds),
              Set(displayingWindowIds) == Set(plan.displayingWindowIds),
              Set(presentationWindowIds) == Set(plan.presentationWindowIds),
              plan.runtime.windowState(for: plan.firstWindowId)
                === plan.firstWindow,
              snapshots.runtimeExposureIsValid(
                  tabID: tab.id,
                  structure: plan.structure,
                  presentationWindowIDs: presentationWindowIds,
                  runtime: plan.runtime
              ) else {
            return nil
        }
        let presentationWindows = plan.presentationWindowIds.compactMap {
            plan.runtime.windowState(for: $0)
        }
        guard presentationWindows.count == plan.presentationWindowIds.count else {
            return nil
        }
        return AuthorizedDisplayedTabShortcutConversion(
            tab: tab,
            plan: plan,
            structure: plan.structure,
            presentationWindows: presentationWindows
        )
    }

    private func authorize(
        _ plan: DetachedTabShortcutConversionPlan,
        for tab: Tab
    ) -> AuthorizedDetachedTabShortcutConversion? {
        guard plan.sourceTabId == tab.id else { return nil }
        if let runtime = plan.runtime {
            guard windows.windowIdsDisplaying(
                tabId: tab.id,
                preferredWindowId: nil,
                using: runtime
            ).isEmpty else { return nil }
        } else if tab.hasBrowserRuntime {
            return nil
        }
        return AuthorizedDetachedTabShortcutConversion(
            tab: tab,
            runtime: plan.runtime,
            structure: plan.structure
        )
    }

}
