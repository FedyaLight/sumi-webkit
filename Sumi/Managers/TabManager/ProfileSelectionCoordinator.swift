import Foundation

/// Reconciles visible selection and nil Space profile references. It owns no
/// WebView replacement or profile-assignment transaction state.
@MainActor
final class ProfileSelectionCoordinator {
    private unowned let tabManager: TabManager
    private let spaceActivation: SpaceActivationService

    init(
        tabManager: TabManager,
        spaceActivation: SpaceActivationService
    ) {
        self.tabManager = tabManager
        self.spaceActivation = spaceActivation
    }

    func handleProfileSwitch(contextWindowID: UUID? = nil) {
        if let pendingSpaceID = tabManager.pendingSpaceActivation {
            tabManager.pendingSpaceActivation = nil
            if let target = tabManager.spaceStateOwner.space(
                with: pendingSpaceID
            ) {
                spaceActivation.setActiveSpace(
                    target,
                    contextWindowId: contextWindowID
                )
            }
        }

        let visible = tabManager.activeSelectionOwner
            .selectionTabsForCurrentContext(in: contextWindowID)
        let current = tabManager.selectionStateOwner.currentTab
        if contextWindowID == nil,
           shouldPreserveContextlessShortcutLiveTab(current) {
            tabManager.runtimePorts?.updateTabVisibility()
            return
        }

        let currentIsVisible = current.map { current in
            visible.contains(where: { $0.id == current.id })
        } ?? false
        if !currentIsVisible {
            tabManager.selectionStateOwner.replaceCurrentTab(visible.first)
            tabManager.runtimePorts?.updateTabVisibility()
            tabManager.structuralPersistence.persistSelection()
        } else {
            tabManager.runtimePorts?.updateTabVisibility()
        }
    }

    func reconcileSpaceProfilesIfNeeded() {
        guard let profileID = tabManager.runtimePorts?.defaultProfileId else {
            RuntimeDiagnostics.debug(
                "No profiles available for space reconciliation yet.",
                category: "TabManager"
            )
            return
        }

        var didAssign = false
        for space in tabManager.spaceStateOwner.spaces
            where space.profileId == nil {
            tabManager.objectWillChange.send()
            _ = tabManager.spaceStateOwner.assignProfile(
                spaceId: space.id,
                profileId: profileID
            )
            didAssign = true
        }
        guard didAssign else { return }
        tabManager.structuralPersistence.markAllSpacesStructurallyDirty()
        tabManager.structuralPersistence.scheduleStructuralPersistence()
    }

    private func shouldPreserveContextlessShortcutLiveTab(
        _ tab: Tab?
    ) -> Bool {
        guard let tab,
              tab.isShortcutLiveInstance,
              tab.shortcutPinRole != .essential,
              let shortcutPinID = tab.shortcutPinId,
              tabManager.shortcutPinCollectionStateOwner.shortcutPin(
                  by: shortcutPinID
              ) != nil else {
            return false
        }
        return true
    }
}
