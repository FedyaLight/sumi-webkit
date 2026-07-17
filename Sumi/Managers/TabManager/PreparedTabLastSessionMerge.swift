import Foundation

struct PreparedTabLastSessionMerge {
    let plan: TabLastSessionMergePlan
    let existingSpaces: [UUID: Space]
    let existingFolders: [TabLastSessionFolderKey: TabFolder]
    let existingTabs: [TabLastSessionRegularTabKey: Tab]
}
