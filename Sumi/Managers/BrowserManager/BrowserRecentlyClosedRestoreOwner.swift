import AppKit
import Foundation

@MainActor
final class BrowserRecentlyClosedRestoreOwner {
    private let recentlyClosedManager: @MainActor () -> RecentlyClosedManager
    private let startupRestore: any BrowserStartupSessionRestoreProviding
    private let lastSessionWindowsStore: @MainActor () -> LastSessionWindowsStore
    private let currentRegularWindowSnapshots: @MainActor (UUID?) -> [LastSessionWindowSnapshot]
    private let refreshLastSessionWindowsStore: @MainActor (UUID?) -> Void
    private let reopenWindow: @MainActor (WindowSessionSnapshot) async -> Void
    private let mergeSnapshotForLastSessionRestore: @MainActor (TabSnapshotRepository.Snapshot) -> Void
    private let activeWindow: @MainActor () -> BrowserWindowState?
    private let windowState: @MainActor (UUID) -> BrowserWindowState?
    private let tabManager: @MainActor () -> TabManager
    private let profileManager: @MainActor () -> ProfileManager
    private let space: @MainActor (UUID) -> Space?
    private let selectTab: @MainActor (Tab, BrowserWindowState) -> Void

    init(
        recentlyClosedManager: @escaping @MainActor () -> RecentlyClosedManager,
        startupRestore: any BrowserStartupSessionRestoreProviding,
        lastSessionWindowsStore: @escaping @MainActor () -> LastSessionWindowsStore,
        currentRegularWindowSnapshots: @escaping @MainActor (UUID?) -> [LastSessionWindowSnapshot],
        refreshLastSessionWindowsStore: @escaping @MainActor (UUID?) -> Void,
        reopenWindow: @escaping @MainActor (WindowSessionSnapshot) async -> Void,
        mergeSnapshotForLastSessionRestore: @escaping @MainActor (TabSnapshotRepository.Snapshot) -> Void,
        activeWindow: @escaping @MainActor () -> BrowserWindowState?,
        windowState: @escaping @MainActor (UUID) -> BrowserWindowState?,
        tabManager: @escaping @MainActor () -> TabManager,
        profileManager: @escaping @MainActor () -> ProfileManager,
        space: @escaping @MainActor (UUID) -> Space?,
        selectTab: @escaping @MainActor (Tab, BrowserWindowState) -> Void
    ) {
        self.recentlyClosedManager = recentlyClosedManager
        self.startupRestore = startupRestore
        self.lastSessionWindowsStore = lastSessionWindowsStore
        self.currentRegularWindowSnapshots = currentRegularWindowSnapshots
        self.refreshLastSessionWindowsStore = refreshLastSessionWindowsStore
        self.reopenWindow = reopenWindow
        self.mergeSnapshotForLastSessionRestore = mergeSnapshotForLastSessionRestore
        self.activeWindow = activeWindow
        self.windowState = windowState
        self.tabManager = tabManager
        self.profileManager = profileManager
        self.space = space
        self.selectTab = selectTab
    }

    var canOfferStartupSessionRestoreShortcut: Bool {
        startupRestore.canOfferRestoreShortcut
    }

    var canRestoreAnyLastSession: Bool {
        canOfferStartupSessionRestoreShortcut || lastSessionWindowsStore().canRestoreLastSession
    }

    func reopenMostRecentClosedItem() {
        guard let item = recentlyClosedManager().mostRecentItem else { return }
        reopenRecentlyClosedItem(item)
    }

    func reopenRecentlyClosedItem(_ item: RecentlyClosedItem) {
        let didRestore: Bool
        switch item {
        case .tab(let tabState):
            didRestore = reopenClosedTab(tabState)
        case .shortcutLiveInstance(let shortcutState):
            didRestore = reopenClosedShortcutLiveInstance(shortcutState)
        case .shortcutLauncher(let launcherState):
            didRestore = restoreShortcutLauncher(from: launcherState.pin) != nil
        case .window(let windowState):
            didRestore = true
            Task { @MainActor [reopenWindow] in
                await reopenWindow(windowState.session)
            }
        }
        guard didRestore else { return }
        recentlyClosedManager().remove(item)
        startupRestore.markRestoreOfferConsumed()
    }

    func reopenAllWindowsFromLastSession() {
        let startupRestore = startupRestore
        let lastSessionWindowsStore = lastSessionWindowsStore()
        let useStartupArchive = startupRestore.canOfferRestoreShortcut
        let sourceSnapshots = useStartupArchive
            ? startupRestore.windowSnapshots
            : lastSessionWindowsStore.snapshots
        let sourceTabSnapshot = useStartupArchive
            ? (startupRestore.tabSnapshot ?? lastSessionWindowsStore.tabSnapshot)
            : lastSessionWindowsStore.tabSnapshot
        let existingSessions = Set(
            currentRegularWindowSnapshots(nil).map(\.session)
        )
        let snapshotsToRestore = sourceSnapshots.filter { !existingSessions.contains($0.session) }
        guard !snapshotsToRestore.isEmpty else { return }

        startupRestore.markRestoreOfferConsumed()
        Task { @MainActor [reopenWindow, mergeSnapshotForLastSessionRestore, refreshLastSessionWindowsStore] in
            if let sourceTabSnapshot {
                mergeSnapshotForLastSessionRestore(sourceTabSnapshot)
            }
            for snapshot in snapshotsToRestore {
                await reopenWindow(snapshot.session)
            }
            refreshLastSessionWindowsStore(nil)
        }
    }

    private func reopenClosedTab(_ tabState: RecentlyClosedTabState) -> Bool {
        let tabManager = tabManager()
        let targetWindow = activeWindow()
        guard let targetSpace = restoredSpace(
            sourceSpaceId: tabState.sourceSpaceId,
            sourceProfileId: tabState.profileId,
            fallbackWindow: targetWindow
        ) else {
            return false
        }

        let restoredTab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: (tabState.currentURL ?? tabState.url).absoluteString,
            in: targetSpace,
            activate: false
        )
        restoredTab.name = tabState.title
        restoredTab.restoredCanGoBack = tabState.canGoBack
        restoredTab.restoredCanGoForward = tabState.canGoForward
        restoredTab.applyRestoredNavigationPresentation()

        if let targetWindow {
            selectTab(restoredTab, targetWindow)
        } else {
            tabManager.activeSelectionOwner.setActiveTab(restoredTab)
        }
        return true
    }

    private func reopenClosedShortcutLiveInstance(_ shortcutState: RecentlyClosedShortcutLiveState) -> Bool {
        let tabManager = tabManager()
        guard let targetWindow = targetWindowForClosedShortcut(shortcutState) else {
            if tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: shortcutState.pin.id) == nil {
                return restoreShortcutLauncher(from: shortcutState.pin) != nil
            }
            return false
        }

        guard let pin = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: shortcutState.pin.id) else {
            return restoreShortcutLauncher(from: shortcutState.pin, fallbackWindow: targetWindow) != nil
        }

        let restoredTab = tabManager.shortcutLiveTabOwner.activateShortcutPin(
            pin,
            in: targetWindow.id,
            currentSpaceId: targetWindow.currentSpaceId
        )
        applyShortcutLiveState(shortcutState, to: restoredTab)
        selectTab(restoredTab, targetWindow)
        return true
    }

    private func targetWindowForClosedShortcut(_ shortcutState: RecentlyClosedShortcutLiveState) -> BrowserWindowState? {
        if let sourceWindowId = shortcutState.sourceWindowId,
           let sourceWindow = windowState(sourceWindowId) {
            return sourceWindow
        }
        return activeWindow()
    }

    private func applyShortcutLiveState(
        _ shortcutState: RecentlyClosedShortcutLiveState,
        to tab: Tab
    ) {
        tab.name = shortcutState.title
        tab.url = shortcutState.url
        tab.restoredCanGoBack = shortcutState.canGoBack
        tab.restoredCanGoForward = shortcutState.canGoForward
        tab.applyRestoredNavigationPresentation()
        _ = tab.applyCachedFaviconOrPlaceholder(for: shortcutState.url)

        if tab.hasCurrentWebView {
            tab.loadURL(shortcutState.url)
        }
    }

    @discardableResult
    private func restoreShortcutLauncher(
        from pinState: RecentlyClosedShortcutPinState,
        fallbackWindow: BrowserWindowState? = nil
    ) -> ShortcutPin? {
        let tabManager = tabManager()
        if let existing = tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pinState.id) {
            return existing
        }

        let restoredPin: ShortcutPin?
        switch pinState.role {
        case .essential:
            guard let profileId = restoredEssentialProfileId(
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
            guard let spaceId = restoredSpacePinnedSpaceId(
                from: pinState,
                fallbackWindow: fallbackWindow
            ) else {
                return nil
            }
            let folderId = pinState.folderId.flatMap { folderId in
                tabManager.folderCollectionStateOwner.spaceId(for: folderId) == spaceId ? folderId : nil
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
        tabManager.scheduleStructuralPersistence()
        return inserted
    }

    private func restoredEssentialProfileId(
        from pinState: RecentlyClosedShortcutPinState,
        fallbackWindow: BrowserWindowState?
    ) -> UUID? {
        let profileManager = profileManager()
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

    private func restoredSpacePinnedSpaceId(
        from pinState: RecentlyClosedShortcutPinState,
        fallbackWindow: BrowserWindowState?
    ) -> UUID? {
        let tabManager = tabManager()
        if let spaceId = pinState.spaceId,
           tabManager.spaceStateOwner.spaces.contains(where: { $0.id == spaceId }) {
            return spaceId
        }
        if let spaceId = fallbackWindow?.currentSpaceId,
           tabManager.spaceStateOwner.spaces.contains(where: { $0.id == spaceId }) {
            return spaceId
        }
        if let profileId = fallbackWindow?.currentProfileId,
           let profileSpaceId = firstSpaceId(for: profileId, tabManager: tabManager) {
            return profileSpaceId
        }
        return nil
    }

    private func restoredSpace(
        sourceSpaceId: UUID?,
        sourceProfileId: UUID?,
        fallbackWindow: BrowserWindowState?
    ) -> Space? {
        let tabManager = tabManager()
        if let sourceSpaceId,
           let sourceSpace = space(sourceSpaceId) {
            return sourceSpace
        }
        if let spaceId = fallbackWindow?.currentSpaceId,
           let windowSpace = space(spaceId) {
            return windowSpace
        }
        if let sourceProfileId,
           let profileSpace = firstSpace(for: sourceProfileId, tabManager: tabManager) {
            return profileSpace
        }
        if let profileId = fallbackWindow?.currentProfileId,
           let profileSpace = firstSpace(for: profileId, tabManager: tabManager) {
            return profileSpace
        }
        return nil
    }

    private func firstSpaceId(
        for profileId: UUID,
        tabManager: TabManager
    ) -> UUID? {
        firstSpace(for: profileId, tabManager: tabManager)?.id
    }

    private func firstSpace(
        for profileId: UUID,
        tabManager: TabManager
    ) -> Space? {
        tabManager.spaceStateOwner.spaces.first(where: { $0.profileId == profileId })
    }
}
