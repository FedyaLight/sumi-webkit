import Foundation

/// Joins an exact durable snapshot with an independently resolved window plan.
@MainActor
final class RegularTabShortcutConversionPlanner {
    private let structure: RegularTabShortcutStructureTransition
    private let windows: RegularTabShortcutWindowPlanResolver

    init(
        windows: ShortcutTabWindowQuery,
        structureTransition: RegularTabShortcutStructureTransition,
        runtimeConnection: TabRuntimePortConnection
    ) {
        structure = structureTransition
        self.windows = RegularTabShortcutWindowPlanResolver(
            windows: windows,
            runtimeConnection: runtimeConnection
        )
    }

    func prepareConversion(
        _ tab: Tab,
        preferredWindowId: UUID?
    ) -> TabShortcutConversionPreparation {
        guard let durablePlan = structure.prepare(tab) else {
            return .rejected
        }
        return windows.resolve(
            tab: tab,
            structure: durablePlan,
            preferredWindowID: preferredWindowId
        )
    }

    func isStructureCurrent(
        _ preparation: TabShortcutConversionPreparation,
        for tab: Tab
    ) -> Bool {
        guard let durablePlan = preparation.structurePlan else { return false }
        return structure.isCurrent(durablePlan, for: tab)
    }
}
