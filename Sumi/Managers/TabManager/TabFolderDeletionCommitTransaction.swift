import AppKit
import Foundation

@MainActor
final class TabFolderDeletionCommitTransaction {
    private let hierarchy: TabFolderHierarchyMutationService
    private let shortcutRetirement: ShortcutLiveTabRetirementService
    private let tabClosure: TabClosureService
    private let runtimeConnection: TabRuntimePortConnection
    private let persistence: TabStructuralPersistenceService

    init(
        hierarchy: TabFolderHierarchyMutationService,
        shortcutRetirement: ShortcutLiveTabRetirementService,
        tabClosure: TabClosureService,
        runtimeConnection: TabRuntimePortConnection,
        persistence: TabStructuralPersistenceService
    ) {
        self.hierarchy = hierarchy
        self.shortcutRetirement = shortcutRetirement
        self.tabClosure = tabClosure
        self.runtimeConnection = runtimeConnection
        self.persistence = persistence
    }

    func commit(_ prepared: TabFolderDeletionPreparation) -> Bool {
        guard let retirement = shortcutRetirement
            .prepareDeletedPinRetirements(prepared.deletedPinIDs) else {
            return false
        }
        hierarchy.replaceFolders(
            prepared.remainingFolders,
            in: prepared.spaceID
        )
        hierarchy.applyChildItems(
            prepared.remainingParentItems,
            in: prepared.parentFolderID,
            spaceID: prepared.spaceID
        )
        hierarchy.replaceSpacePinnedShortcuts(
            prepared.remainingPins,
            in: prepared.spaceID
        )

        let runtime = runtimeConnection.current
        prepared.deletedPins.forEach {
            runtime?.captureDeletedShortcutLauncher($0)
        }
        tabClosure.removeTabs(prepared.liveTabIDs)
        shortcutRetirement.finishAfterCurrentBatch(retirement)
        runtime?.deleteLiveFolderState(
            forFolderIds: prepared.deletedFolderIDs
        )
        persistence.scheduleStructuralPersistence()
        if prepared.deletedPins.isEmpty == false {
            runtime?.notifications()?.presentSavedTabDeletionNotification(
                tabCount: prepared.deletedPins.count,
                in: nil
            )
        }
        return true
    }
}
