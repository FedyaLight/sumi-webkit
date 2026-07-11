import Foundation

/// Acquires every fallible conversion dependency before a shortcut pin is
/// inserted or a regular tab leaves its structural container.
@MainActor
final class RegularTabShortcutConversionPlanner {
    private let windows: ShortcutTabWindowQuery
    private let structureTransition: RegularTabShortcutStructureTransition
    private let runtimePorts: () -> RuntimePortRegistry?

    init(
        windows: ShortcutTabWindowQuery,
        structureTransition: RegularTabShortcutStructureTransition,
        runtimePorts: @escaping () -> RuntimePortRegistry?
    ) {
        self.windows = windows
        self.structureTransition = structureTransition
        self.runtimePorts = runtimePorts
    }

    func prepareConversion(
        _ tab: Tab,
        preferredWindowId: UUID?
    ) -> TabShortcutConversionPreparation {
        guard let structure = structureTransition.prepare(tab) else {
            return .rejected
        }
        guard let runtime = runtimePorts() else {
            return tab.hasBrowserRuntime
                || structure.sourceSplitGroupSnapshot != nil
                ? .rejected
                : .detached(DetachedTabShortcutConversionPlan(
                    sourceTabId: tab.id,
                    runtime: nil,
                    structure: structure
                ))
        }
        let primaryWindowId = runtime.webViewLifecycle
            .primaryTrackedWindowId(for: tab.id)
        let selectedWindowIds = windows.windowIdsSelecting(
            tabId: tab.id,
            preferredWindowId: preferredWindowId,
            using: runtime
        )
        let displayingWindowIds = windows.windowIdsDisplaying(
            tabId: tab.id,
            preferredWindowId: preferredWindowId,
            using: runtime
        )
        guard let firstWindowId = selectedWindowIds.first
                ?? displayingWindowIds.first else {
            return structure.sourceSplitGroupSnapshot == nil
                ? .detached(DetachedTabShortcutConversionPlan(
                    sourceTabId: tab.id,
                    runtime: runtime,
                    structure: structure
                ))
                : .rejected
        }
        guard primaryWindowId == nil || primaryWindowId == firstWindowId else {
            return .rejected
        }
        guard let firstWindow = runtime.windowState(for: firstWindowId) else {
            return .rejected
        }
        guard structure.acceptsRuntimeExposure(
            of: tab.id,
            in: displayingWindowIds,
            using: runtime
        ) else {
            return .rejected
        }
        return .displayed(DisplayedTabShortcutConversionPlan(
            sourceTabId: tab.id,
            runtime: runtime,
            structure: structure,
            selectedWindowIds: selectedWindowIds,
            displayingWindowIds: displayingWindowIds,
            primaryWindowId: primaryWindowId,
            firstWindowId: firstWindowId,
            firstWindow: firstWindow
        ))
    }
}
