import Foundation

/// Owns phase ordering for one regular-tab publication: structural residence
/// commits before any visible runtime materialization.
@MainActor
final class RegularTabPublicationTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let residence: RegularTabResidencePublication
    private let visibleRuntime: RegularTabVisibleRuntimeEffects

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        residence: RegularTabResidencePublication,
        visibleRuntime: RegularTabVisibleRuntimeEffects
    ) {
        self.structuralLookup = structuralLookup
        self.residence = residence
        self.visibleRuntime = visibleRuntime
    }

    func add(
        _ tab: Tab,
        regularInsertionIndex: Int?,
        admissionProfileIDs: Set<UUID>?
    ) -> Bool {
        structuralLookup.withTransaction {
            guard residence.publish(
                tab,
                regularInsertionIndex: regularInsertionIndex,
                admissionProfileIDs: admissionProfileIDs
            ) else { return false }
            visibleRuntime.materializeIfVisible(tab)
            RuntimeDiagnostics.debug(
                "Added regular tab '\(tab.name)' to space \(tab.spaceId?.uuidString ?? "unknown").",
                category: "TabManager"
            )
            return true
        }
    }
}
