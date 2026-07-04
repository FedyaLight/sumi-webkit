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
    struct Dependencies {
        let pinnedByProfile: @MainActor () -> [UUID: [ShortcutPin]]
        let setPinnedTabs: @MainActor ([ShortcutPin], UUID) -> Void
        let removeRegularTab: @MainActor (UUID, UUID, UUID?) -> Void
        let currentSpaceId: @MainActor () -> UUID?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func removeFromCurrentContainer(_ tab: Tab) {
        for (profileId, pins) in dependencies.pinnedByProfile() {
            if let index = pins.firstIndex(where: { $0.id == tab.id }) {
                var copy = pins
                if index < copy.count { copy.remove(at: index) }
                dependencies.setPinnedTabs(copy, profileId)
                return
            }
        }

        if let spaceId = tab.spaceId {
            dependencies.removeRegularTab(
                tab.id,
                spaceId,
                dependencies.currentSpaceId()
            )
        }
    }
}

extension ShortcutContainerRemovalOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            pinnedByProfile: { [weak tabManager] in
                tabManager?.shortcutPinCollectionStateOwner.pinnedByProfileSnapshot() ?? [:]
            },
            setPinnedTabs: { [weak tabManager] pins, profileId in
                tabManager?.structuralCollectionMutationOwner.setPinnedTabs(pins, for: profileId)
            },
            removeRegularTab: { [weak tabManager] tabId, spaceId, currentSpaceId in
                _ = tabManager?.regularTabCollectionOwner.remove(
                    tabId,
                    from: spaceId,
                    currentSpaceId: currentSpaceId
                )
            },
            currentSpaceId: { [weak tabManager] in
                tabManager?.spaceStateOwner.currentSpace?.id
            }
        )
    }
}
