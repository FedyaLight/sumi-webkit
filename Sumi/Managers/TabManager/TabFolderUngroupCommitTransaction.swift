import AppKit
import Foundation

@MainActor
final class TabFolderUngroupCommitTransaction {
    private let hierarchy: TabFolderHierarchyMutationService
    private let runtimeConnection: TabRuntimePortConnection
    private let persistence: TabStructuralPersistenceService

    init(
        hierarchy: TabFolderHierarchyMutationService,
        runtimeConnection: TabRuntimePortConnection,
        persistence: TabStructuralPersistenceService
    ) {
        self.hierarchy = hierarchy
        self.runtimeConnection = runtimeConnection
        self.persistence = persistence
    }

    func commit(_ prepared: TabFolderUngroupPreparation) {
        hierarchy.replaceFolders(
            prepared.remainingFolders,
            in: prepared.spaceID
        )
        hierarchy.applyChildItems(
            prepared.liftedParentItems,
            in: prepared.parentFolderID,
            spaceID: prepared.spaceID
        )
        for tab in prepared.liveTabs {
            tab.folderId = prepared.parentFolderID
            tab.isSpacePinned = true
        }
        if prepared.liveTabs.isEmpty == false {
            persistence.markRegularTabsStructurallyDirty(
                for: prepared.spaceID
            )
        }
        if prepared.isLiveFolder {
            runtimeConnection.current?.deleteLiveFolderState(
                forFolderIds: [prepared.folderID]
            )
        }
        persistence.scheduleStructuralPersistence()
    }
}
