import Foundation

/// Restores recently closed shortcut state: re-activates the live instance of
/// a still-existing shortcut pin (preferring its source window), and
/// re-inserts a deleted launcher pin from its captured snapshot after
/// resolving the essential profile or the space-pinned space and folder.
@MainActor
final class ClosedShortcutRestoreService {
    private let tabManager: @MainActor () -> TabManager?
    private let profileManager: @MainActor () -> ProfileManager?
    private let activeWindow: @MainActor () -> BrowserWindowState?
    private let windowState: @MainActor (UUID) -> BrowserWindowState?
    private let selectRestoredTab: @MainActor (Tab, BrowserWindowState) -> Void

    init(
        tabManager: @escaping @MainActor () -> TabManager?,
        profileManager: @escaping @MainActor () -> ProfileManager?,
        activeWindow: @escaping @MainActor () -> BrowserWindowState?,
        windowState: @escaping @MainActor (UUID) -> BrowserWindowState?,
        selectRestoredTab: @escaping @MainActor (Tab, BrowserWindowState) -> Void
    ) {
        self.tabManager = tabManager
        self.profileManager = profileManager
        self.activeWindow = activeWindow
        self.windowState = windowState
        self.selectRestoredTab = selectRestoredTab
    }

    /// Returns `false` when neither the live instance nor its launcher could
    /// be restored; the caller must then keep the recently-closed item.
    func restoreLiveInstance(_ shortcutState: RecentlyClosedShortcutLiveState) -> Bool {
        guard let tabManager = tabManager() else { return false }
        guard let targetWindow = targetWindow(for: shortcutState) else {
            if tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: shortcutState.pin.id) == nil {
                return restoreLauncher(from: shortcutState.pin, fallbackWindow: nil) != nil
            }
            return false
        }

        guard let pin = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: shortcutState.pin.id) else {
            return restoreLauncher(from: shortcutState.pin, fallbackWindow: targetWindow) != nil
        }

        let restoredTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: targetWindow.id,
            currentSpaceId: targetWindow.currentSpaceId
        )
        applyLiveState(shortcutState, to: restoredTab)
        selectRestoredTab(restoredTab, targetWindow)
        return true
    }

    /// Returns `false` when the launcher's profile or space cannot be
    /// resolved; the caller must then keep the recently-closed item.
    /// A deleted-launcher item restores strictly from its captured snapshot —
    /// no fallback to the active window's profile or space.
    func restoreLauncher(from pinState: RecentlyClosedShortcutPinState) -> Bool {
        restoreLauncher(from: pinState, fallbackWindow: nil) != nil
    }

    private func targetWindow(
        for shortcutState: RecentlyClosedShortcutLiveState
    ) -> BrowserWindowState? {
        if let sourceWindowId = shortcutState.sourceWindowId,
           let sourceWindow = windowState(sourceWindowId) {
            return sourceWindow
        }
        return activeWindow()
    }

    private func applyLiveState(
        _ shortcutState: RecentlyClosedShortcutLiveState,
        to tab: Tab
    ) {
        tab.name = shortcutState.title
        tab.loadURL(shortcutState.url)
        tab.restoredCanGoBack = shortcutState.canGoBack
        tab.restoredCanGoForward = shortcutState.canGoForward
        tab.applyRestoredNavigationPresentation()
        _ = tab.applyCachedFaviconOrPlaceholder(for: shortcutState.url)
    }

    private func restoreLauncher(
        from pinState: RecentlyClosedShortcutPinState,
        fallbackWindow: BrowserWindowState?
    ) -> ShortcutPin? {
        guard let tabManager = tabManager() else { return nil }
        if let existing = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pinState.id) {
            return existing
        }

        let restoredPin: ShortcutPin?
        switch pinState.role {
        case .essential:
            guard let profileId = resolvedEssentialProfileId(
                from: pinState,
                fallbackWindow: fallbackWindow
            ) else {
                return nil
            }
            restoredPin = ShortcutPin(
                id: pinState.id,
                role: .essential,
                profileId: profileId,
                executionProfileId: pinState.executionProfileId,
                spaceId: nil,
                index: pinState.index,
                folderId: nil,
                launchURL: pinState.launchURL,
                title: pinState.title,
                iconAsset: pinState.iconAsset
            )
        case .spacePinned:
            guard let spaceId = resolvedSpacePinnedSpaceId(
                from: pinState,
                fallbackWindow: fallbackWindow
            ) else {
                return nil
            }
            let folderId: UUID? = pinState.folderId.flatMap { folderId in
                guard tabManager.folderCollectionStateOwner.spaceId(for: folderId) == spaceId,
                      tabManager.runtimePorts?.isLiveFolder(folderId) != true else { return nil }
                return folderId
            }
            restoredPin = ShortcutPin(
                id: pinState.id,
                role: .spacePinned,
                profileId: nil,
                executionProfileId: pinState.executionProfileId,
                spaceId: spaceId,
                index: pinState.index,
                folderId: folderId,
                launchURL: pinState.launchURL,
                title: pinState.title,
                iconAsset: pinState.iconAsset
            )
        }

        guard let restoredPin,
              let inserted = tabManager.shortcutPinStoreOwner.insert(restoredPin, at: pinState.index)
        else {
            return nil
        }
        tabManager.structuralPersistence.scheduleStructuralPersistence()
        return inserted
    }

    private func resolvedEssentialProfileId(
        from pinState: RecentlyClosedShortcutPinState,
        fallbackWindow: BrowserWindowState?
    ) -> UUID? {
        guard let profileManager = profileManager() else { return nil }
        if let profileId = pinState.profileId,
           profileManager.profiles.contains(where: { $0.id == profileId }) {
            return profileId
        }
        if let profileId = fallbackWindow?.currentProfileId,
           profileManager.profiles.contains(where: { $0.id == profileId }) {
            return profileId
        }
        return nil
    }

    private func resolvedSpacePinnedSpaceId(
        from pinState: RecentlyClosedShortcutPinState,
        fallbackWindow: BrowserWindowState?
    ) -> UUID? {
        guard let tabManager = tabManager() else { return nil }
        if let spaceId = pinState.spaceId,
           tabManager.spaceStateOwner.spaces.contains(where: { $0.id == spaceId }) {
            return spaceId
        }
        if let spaceId = fallbackWindow?.currentSpaceId,
           tabManager.spaceStateOwner.spaces.contains(where: { $0.id == spaceId }) {
            return spaceId
        }
        if let profileId = fallbackWindow?.currentProfileId,
           let profileSpaceId = tabManager.spaceStateOwner.spaces
               .first(where: { $0.profileId == profileId })?.id {
            return profileSpaceId
        }
        return nil
    }
}
