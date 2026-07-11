import Foundation

/// Revalidates prepared conversion facts before shortcut insertion can open a
/// folder, publish structure, or mutate any window state.
@MainActor
final class TabShortcutConversionAuthorizer {
    private let windows: ShortcutTabWindowQuery

    init(windows: ShortcutTabWindowQuery) {
        self.windows = windows
    }

    func authorize(
        _ preparation: TabShortcutConversionPreparation,
        for tab: Tab,
        candidatePin: ShortcutPin
    ) -> AuthorizedTabShortcutConversion? {
        switch preparation {
        case .displayed(let plan):
            return authorize(plan, for: tab, candidatePin: candidatePin).map {
                .displayed($0)
            }
        case .detached(let plan):
            return authorize(plan, for: tab, candidatePin: candidatePin).map {
                .detached($0)
            }
        case .rejected:
            return nil
        }
    }

    func authorize(
        _ plan: DisplayedTabShortcutConversionPlan,
        for tab: Tab,
        candidatePin: ShortcutPin
    ) -> AuthorizedDisplayedTabShortcutConversion? {
        guard plan.sourceTabId == tab.id,
              let structure = plan.structure.authorize(
                  candidatePin,
                  for: tab
              ) else { return nil }
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
        guard plan.runtime.webViewLifecycle.primaryTrackedWindowId(
                  for: tab.id
              ) == plan.primaryWindowId,
              Set(selectedWindowIds) == Set(plan.selectedWindowIds),
              Set(displayingWindowIds) == Set(plan.displayingWindowIds),
              plan.runtime.windowState(for: plan.firstWindowId)
                === plan.firstWindow,
              plan.structure.acceptsRuntimeExposure(
                  of: tab.id,
                  in: displayingWindowIds,
                  using: plan.runtime
              ) else {
            return nil
        }
        let selectedWindows = plan.selectedWindowIds.compactMap {
            plan.runtime.windowState(for: $0)
        }
        guard selectedWindows.count == plan.selectedWindowIds.count else {
            return nil
        }
        return AuthorizedDisplayedTabShortcutConversion(
            tab: tab,
            plan: plan,
            structure: structure,
            selectedWindows: selectedWindows
        )
    }

    private func authorize(
        _ plan: DetachedTabShortcutConversionPlan,
        for tab: Tab,
        candidatePin: ShortcutPin
    ) -> AuthorizedDetachedTabShortcutConversion? {
        guard plan.sourceTabId == tab.id,
              plan.structure.authorize(
                  candidatePin,
                  for: tab
              ) != nil else { return nil }
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
            runtime: plan.runtime
        )
    }
}
