import Foundation

/// Pure derivation and validation of the windows that must receive a live
/// shortcut instance during conversion.
@MainActor
struct ShortcutConversionWindowSnapshotResolver {
    func presentationWindowIDs(
        structure: RegularTabShortcutStructurePlan,
        selected: [UUID],
        displaying: [UUID],
        runtime: RuntimePortRegistry
    ) -> [UUID] {
        var ids = Set(selected + displaying)
        if let groupID = structure.presentationSourceSplitGroupID {
            runtime.forEachWindow { id, state in
                if state.splitSelection?.groupID == groupID { ids.insert(id) }
            }
        }
        return ids.sorted { $0.uuidString < $1.uuidString }
    }

    func runtimeExposureIsValid(
        tabID: UUID,
        structure: RegularTabShortcutStructurePlan,
        presentationWindowIDs: [UUID],
        runtime: RuntimePortRegistry
    ) -> Bool {
        if structure.presentationSourceSplitGroupID == nil {
            return presentationWindowIDs.allSatisfy {
                !runtime.visibleSplitTabIds(for: $0).contains(tabID)
            }
        }
        guard let primary = runtime.webViewLifecycle
            .primaryTrackedWindowId(for: tabID) else { return true }
        return presentationWindowIDs.contains(primary)
    }
}
