import Foundation
import OSLog
import SwiftData

enum TabStoreWrite: Sendable {
    case reconcile(TabPersistenceSnapshot, validating: Bool)
    case incremental(TabStructuralPersistenceDelta)
    case selection(TabPersistenceSelection)
    case runtimeState([TabRuntimeStateUpdate])
}

actor TabStoreWriteExecutor {
    private static let log = Logger.sumi(category: "TabPersistence")
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func execute(_ write: TabStoreWrite) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        do {
            let validatesAfterSave: Bool
            switch write {
            case .reconcile(let snapshot, let validating):
                try TabStructuralStoreMutation.reconcile(
                    snapshot,
                    validating: validating,
                    in: context
                )
                validatesAfterSave = validating
            case .incremental(let delta):
                try TabStructuralStoreMutation.apply(delta, in: context)
                validatesAfterSave = false
            case .selection(let selection):
                try TabStoreRecordMutation.upsertSelection(selection, in: context)
                validatesAfterSave = false
            case .runtimeState(let updates):
                try applyRuntimeState(updates, in: context)
                validatesAfterSave = false
            }

            if context.hasChanges {
                try context.save()
            }
            if validatesAfterSave {
                do {
                    try TabStoreIntegrityValidator.validate(in: context)
                } catch {
                    Self.log.error(
                        "Post-save tab integrity validation reported an issue: \(String(describing: error), privacy: .public)"
                    )
                }
            }
        } catch {
            throw TabPersistenceErrorClassifier.classify(error)
        }
    }

    private func applyRuntimeState(
        _ updates: [TabRuntimeStateUpdate],
        in context: ModelContext
    ) throws {
        var latestByTabId: [UUID: TabRuntimeStateUpdate] = [:]
        latestByTabId.reserveCapacity(updates.count)
        for update in updates {
            latestByTabId[update.id] = update
        }
        guard latestByTabId.isEmpty == false else { return }

        let tabsById = try TabStoreRecordQueries.tabs(
            in: context,
            ids: Set(latestByTabId.keys)
        )
        for (tabId, update) in latestByTabId {
            guard let tab = tabsById[tabId] else { continue }
            TabStoreRecordMutation.apply(update, to: tab)
        }
    }
}
