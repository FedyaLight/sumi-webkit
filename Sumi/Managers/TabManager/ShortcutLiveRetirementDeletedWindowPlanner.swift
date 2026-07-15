import Foundation

@MainActor
final class ShortcutLiveRetirementDeletedWindowPlanner {
    struct Result {
        let windows: [ShortcutLiveRetirementBatchWindowEntry]
        let didClearCurrentSelection: Bool
    }

    private let registry: LiveShortcutTabRegistry

    init(registry: LiveShortcutTabRegistry) {
        self.registry = registry
    }

    func prepare(
        pinIDs: Set<UUID>,
        entries: [LiveShortcutTabEntry],
        attachment: TabRuntimeAttachmentWitness,
        split: ShortcutLiveRetirementSplitPlanner.Plan,
        targetStates: [UUID: BrowserWindowShortcutMutationState]
    ) -> Result? {
        var windows: [ShortcutLiveRetirementBatchWindowEntry] = []
        var visitedWindowIDs = Set<UUID>()
        var didClear = false
        let tabIDs = Set(entries.map(\.tab.id))
        attachment.lease.registry?.forEachWindowState { window in
            let source = window.unpublishedShortcutMutationState
            visitedWindowIDs.insert(window.id)
            var update = ShortcutLiveRetirementWindowProjection.removingDeletedPins(
                pinIDs,
                entries: entries,
                from: targetStates[window.id] ?? source
            )
            update = ShortcutLiveRetirementSplitWindowProjection.reconcile(
                update,
                windowID: window.id,
                sourceGroups: split.source,
                replacementGroups: split.replacement,
                deletedPinIDs: pinIDs,
                registry: registry
            )
            didClear = didClear
                || ShortcutLiveRetirementWindowPostcondition
                    .referencesCurrentSelection(
                        pinIDs: pinIDs, tabIDs: tabIDs, in: source
                    )
            guard update.target != source else { return }
            windows.append(.init(
                window: window,
                source: source,
                target: update.target,
                requiresPersistence: update.requiresPersistence
                    || update.target != source
            ))
        }
        guard Set(targetStates.keys).isSubset(of: visitedWindowIDs),
              windows.allSatisfy({ entry in
                  ShortcutLiveRetirementWindowPostcondition
                    .excludesDeletedReferences(
                        pinIDs: pinIDs, tabIDs: tabIDs, from: entry.target
                    )
                  && ShortcutLiveRetirementSplitWindowProjection.targetIsValid(
                      entry.target,
                      replacementGroups: split.replacement,
                      deletedPinIDs: pinIDs
                  )
              }) else { return nil }
        return Result(
            windows: windows,
            didClearCurrentSelection: didClear
        )
    }
}
