import Foundation

@MainActor
final class TabRuntimeContextAttachmentOwner {
    struct Dependencies {
        let setRuntimeContext: @MainActor (TabManagerRuntimeContext) -> Void
        let allTabs: @MainActor () -> [Tab]
        let prepareTabForRuntime: @MainActor (Tab) -> Void
        let pendingPinnedWithoutProfileSnapshot: @MainActor () -> [ShortcutPin]
        let drainPendingPinnedWithoutProfile: @MainActor () -> [ShortcutPin]
        let appendPinnedPins: @MainActor (UUID, [ShortcutPin]) -> Void
        let sendObjectWillChange: @MainActor () -> Void
        let scheduleStructuralPersistence: @MainActor () -> Void
        let currentTab: @MainActor () -> Tab?
        let replaceCurrentTab: @MainActor (Tab?) -> Void
        let currentSpace: @MainActor () -> Space?
        let reconcileSpaceProfilesIfNeeded: @MainActor () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func attach(_ context: TabManagerRuntimeContext) {
        dependencies.setRuntimeContext(context)

        let knownTabs = dependencies.allTabs()
        for tab in knownTabs {
            dependencies.prepareTabForRuntime(tab)
        }

        let pendingPins = dependencies.pendingPinnedWithoutProfileSnapshot()
        if let currentProfileId = context.currentProfileId,
           !pendingPins.isEmpty {
            dependencies.sendObjectWillChange()
            let drainedPins = dependencies.drainPendingPinnedWithoutProfile()
            dependencies.appendPinnedPins(currentProfileId, drainedPins)
            dependencies.scheduleStructuralPersistence()
        }

        if let current = dependencies.currentTab(),
           let match = knownTabs.first(where: { $0.id == current.id }) {
            dependencies.replaceCurrentTab(match)
        }

        if let space = dependencies.currentSpace() {
            context.syncWorkspaceThemeAcrossWindows(for: space, animate: false)
        }

        dependencies.reconcileSpaceProfilesIfNeeded()
    }
}

extension TabRuntimeContextAttachmentOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            setRuntimeContext: { [weak tabManager] context in
                tabManager?.installRuntimeContext(context)
            },
            allTabs: { [weak tabManager] in
                tabManager?.tabCollectionMembershipOwner.allTabs() ?? []
            },
            prepareTabForRuntime: { [weak tabManager] tab in
                tabManager?.runtimePreparationOwner.prepare(tab)
            },
            pendingPinnedWithoutProfileSnapshot: { [weak tabManager] in
                tabManager?.shortcutPinCollectionStateOwner.pendingPinnedWithoutProfileSnapshot() ?? []
            },
            drainPendingPinnedWithoutProfile: { [weak tabManager] in
                tabManager?.shortcutPinCollectionStateOwner.drainPendingPinnedWithoutProfile() ?? []
            },
            appendPinnedPins: { [weak tabManager] profileId, pins in
                tabManager?.shortcutPinStoreOwner.withPinnedArray(for: profileId) { arr in
                    arr.append(contentsOf: pins)
                }
            },
            sendObjectWillChange: { [weak tabManager] in
                tabManager?.objectWillChange.send()
            },
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.scheduleStructuralPersistence()
            },
            currentTab: { [weak tabManager] in
                tabManager?.selectionStateOwner.currentTab
            },
            replaceCurrentTab: { [weak tabManager] tab in
                tabManager?.selectionStateOwner.replaceCurrentTab(tab)
            },
            currentSpace: { [weak tabManager] in
                tabManager?.spaceStateOwner.currentSpace
            },
            reconcileSpaceProfilesIfNeeded: { [weak tabManager] in
                tabManager?.profileAssignmentOwner.reconcileSpaceProfilesIfNeeded()
            }
        )
    }
}
