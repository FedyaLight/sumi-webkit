import Foundation

@MainActor
final class TabLastSessionMergeCommitTransaction {
    private let spaces: TabLastSessionSpaceMaterializer
    private let folders: TabLastSessionFolderMaterializer
    private let shortcuts: TabLastSessionShortcutMaterializer
    private let regularTabs: TabLastSessionRegularTabMaterializer
    private let selection: TabLastSessionSelectionMaterializer

    init(
        spaces: TabLastSessionSpaceMaterializer,
        folders: TabLastSessionFolderMaterializer,
        shortcuts: TabLastSessionShortcutMaterializer,
        regularTabs: TabLastSessionRegularTabMaterializer,
        selection: TabLastSessionSelectionMaterializer
    ) {
        self.spaces = spaces
        self.folders = folders
        self.shortcuts = shortcuts
        self.regularTabs = regularTabs
        self.selection = selection
    }

    func commit(_ prepared: PreparedTabLastSessionMerge) {
        let plan = prepared.plan
        let spacesByID = spaces.materialize(
            plan,
            existing: prepared.existingSpaces
        )
        folders.materialize(plan, existing: prepared.existingFolders)
        shortcuts.materialize(plan)
        let regularTabsByID = regularTabs.materialize(
            plan,
            existing: prepared.existingTabs
        )
        selection.materialize(
            plan,
            spacesByID: spacesByID,
            regularTabsByID: regularTabsByID
        )
    }
}
