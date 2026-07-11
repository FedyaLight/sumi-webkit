import Foundation

enum BrowserWindowSourceResidence: Equatable {
    case regularSpaceTab
    case windowShortcut
}

struct BrowserWindowSourceContext: Equatable {
    let profileID: UUID
    let spaceID: UUID
    let residence: BrowserWindowSourceResidence

    init(
        profileID: UUID,
        spaceID: UUID,
        residence: BrowserWindowSourceResidence = .regularSpaceTab
    ) {
        self.profileID = profileID
        self.spaceID = spaceID
        self.residence = residence
    }
}

/// Resolves the one profile/space pair shared by the physical source Tab and
/// window. Conflicting logical fallbacks fail instead of crossing partitions.
@MainActor
enum BrowserWindowSourceContextResolver {
    static func resolve(
        tab: Tab,
        window: BrowserWindowState,
        tabs: TabManager
    ) -> BrowserWindowSourceContext? {
        guard window.isIncognito == false,
              let windowSpaceID = window.currentSpaceId,
              let space = tabs.spaceStateOwner.space(with: windowSpaceID),
              let windowProfileID = window.currentProfileId,
              let spaceProfileID = space.profileId,
              windowProfileID == spaceProfileID
        else {
            return nil
        }

        let residence: BrowserWindowSourceResidence
        if tab.spaceId == windowSpaceID,
           tab.isShortcutLiveInstance == false,
           tabs.regularTabCollectionOwner.tabs(in: windowSpaceID)
            .contains(where: { $0 === tab }) {
            residence = .regularSpaceTab
        } else if tab.isShortcutLiveInstance,
                  let pinID = tab.shortcutPinId,
                  let role = tab.shortcutPinRole,
                  let entry = tabs.liveShortcutTabs.entry(containing: tab),
                  entry.windowId == window.id,
                  entry.pinId == pinID,
                  tabs.liveShortcutTabs.tab(
                      for: pinID,
                      in: window.id
                  ) === tab,
                  role == .essential
                    ? tab.spaceId == nil
                    : tab.spaceId == windowSpaceID {
            residence = .windowShortcut
        } else {
            return nil
        }
        return BrowserWindowSourceContext(
            profileID: spaceProfileID,
            spaceID: windowSpaceID,
            residence: residence
        )
    }
}
