import Foundation

/// Exact physical registry residence and its mounted-sidebar page scope.
@MainActor
struct LiveShortcutTabEntry {
    let windowId: UUID
    let pinId: UUID
    let tab: Tab

    var pageScope: TabStructureChangeScope {
        .liveShortcut(
            windowID: windowId,
            spaceID: tab.spaceId,
            profileID: tab.profileId
        )
    }
}
