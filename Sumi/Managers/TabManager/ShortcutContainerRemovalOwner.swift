import Foundation

/// Removes a tab from whichever container currently holds it — an essentials/space-pinned
/// shortcut array, or a space's regular-tab list. This "detach from current container"
/// concern was previously a method on `ShortcutLiveTabOwner`, but its callers are broader
/// than live-shortcut management: the sidebar drag owners reached into `ShortcutLiveTabOwner`
/// solely for it. Splitting it out gives those call sites a focused collaborator and drops
/// four low-level dependencies (pinned-array read/write, regular-tab removal, current space)
/// from `ShortcutLiveTabOwner`'s surface.
@MainActor
final class ShortcutContainerRemovalOwner {
    private let pinnedByProfile: @MainActor () -> [UUID: [ShortcutPin]]
    private let setPinnedTabs: @MainActor ([ShortcutPin], UUID) -> Void
    private let removeRegularTab: @MainActor (UUID, UUID, UUID?) -> Void
    private let currentSpaceId: @MainActor () -> UUID?

    init(
        pinnedByProfile: @escaping @MainActor () -> [UUID: [ShortcutPin]],
        setPinnedTabs: @escaping @MainActor ([ShortcutPin], UUID) -> Void,
        removeRegularTab: @escaping @MainActor (UUID, UUID, UUID?) -> Void,
        currentSpaceId: @escaping @MainActor () -> UUID?
    ) {
        self.pinnedByProfile = pinnedByProfile
        self.setPinnedTabs = setPinnedTabs
        self.removeRegularTab = removeRegularTab
        self.currentSpaceId = currentSpaceId
    }

    func removeFromCurrentContainer(_ tab: Tab) {
        for (profileId, pins) in pinnedByProfile() {
            if let index = pins.firstIndex(where: { $0.id == tab.id }) {
                var copy = pins
                if index < copy.count { copy.remove(at: index) }
                setPinnedTabs(copy, profileId)
                return
            }
        }

        if let spaceId = tab.spaceId {
            removeRegularTab(
                tab.id,
                spaceId,
                currentSpaceId()
            )
        }
    }
}
