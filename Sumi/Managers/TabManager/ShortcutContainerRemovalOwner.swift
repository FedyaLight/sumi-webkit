import Foundation

/// Removes a tab from whichever structural container currently holds it: an
/// essentials/space-pinned shortcut array or a space's regular-tab list.
@MainActor
final class ShortcutContainerRemovalOwner {
    private let pinnedByProfile: @MainActor () -> [UUID: [ShortcutPin]]
    private let setPinnedTabs: @MainActor ([ShortcutPin], UUID) -> Void
    private let removeRegularTab: @MainActor (UUID, UUID, UUID?) -> Void
    private let containsRegularTab: @MainActor (Tab, UUID) -> Bool
    private let currentSpaceId: @MainActor () -> UUID?

    init(
        pinnedByProfile: @escaping @MainActor () -> [UUID: [ShortcutPin]],
        setPinnedTabs: @escaping @MainActor ([ShortcutPin], UUID) -> Void,
        removeRegularTab: @escaping @MainActor (UUID, UUID, UUID?) -> Void,
        containsRegularTab: @escaping @MainActor (Tab, UUID) -> Bool,
        currentSpaceId: @escaping @MainActor () -> UUID?
    ) {
        self.pinnedByProfile = pinnedByProfile
        self.setPinnedTabs = setPinnedTabs
        self.removeRegularTab = removeRegularTab
        self.containsRegularTab = containsRegularTab
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

    func containsIdenticalRegularTab(_ tab: Tab, in spaceID: UUID) -> Bool {
        containsRegularTab(tab, spaceID)
    }
}
