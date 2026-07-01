import AppKit
import Foundation

@MainActor
final class BrowserRecentlyClosedRestoreOwner {
    struct Dependencies {
        let recentlyClosedManager: @MainActor () -> RecentlyClosedManager
        let startupRestore: any BrowserStartupSessionRestoreProviding
        let lastSessionWindowsStore: @MainActor () -> LastSessionWindowsStore
        let currentRegularWindowSnapshots: @MainActor (UUID?) -> [LastSessionWindowSnapshot]
        let refreshLastSessionWindowsStore: @MainActor (UUID?) -> Void
        let reopenWindow: @MainActor (WindowSessionSnapshot) async -> Void
        let mergeSnapshotForLastSessionRestore: @MainActor (TabSnapshotRepository.Snapshot) -> Void
        let activeWindow: @MainActor () -> BrowserWindowState?
        let windowState: @MainActor (UUID) -> BrowserWindowState?
        let tabManager: @MainActor () -> TabManager
        let profileManager: @MainActor () -> ProfileManager
        let space: @MainActor (UUID) -> Space?
        let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var canOfferStartupLastSessionRestoreShortcut: Bool {
        dependencies.startupRestore.canOfferRestoreShortcut
    }

    var canRestoreAnyLastSession: Bool {
        canOfferStartupLastSessionRestoreShortcut || dependencies.lastSessionWindowsStore().canRestoreLastSession
    }

    func reopenMostRecentClosedItem() {
        guard let item = dependencies.recentlyClosedManager().mostRecentItem else { return }
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
            Task { @MainActor [dependencies] in
                await dependencies.reopenWindow(windowState.session)
            }
        }
        guard didRestore else { return }
        dependencies.recentlyClosedManager().remove(item)
        dependencies.startupRestore.markRestoreOfferConsumed()
    }

    func reopenAllWindowsFromLastSession() {
        let startupRestore = dependencies.startupRestore
        let lastSessionWindowsStore = dependencies.lastSessionWindowsStore()
        let useStartupArchive = startupRestore.canOfferRestoreShortcut
        let sourceSnapshots = useStartupArchive
            ? startupRestore.windowSnapshots
            : lastSessionWindowsStore.snapshots
        let sourceTabSnapshot = useStartupArchive
            ? (startupRestore.tabSnapshot ?? lastSessionWindowsStore.tabSnapshot)
            : lastSessionWindowsStore.tabSnapshot
        let existingSessions = Set(
            dependencies.currentRegularWindowSnapshots(nil).map(\.session)
        )
        let snapshotsToRestore = sourceSnapshots.filter { !existingSessions.contains($0.session) }
        guard !snapshotsToRestore.isEmpty else { return }

        startupRestore.markRestoreOfferConsumed()
        Task { @MainActor [dependencies] in
            if let sourceTabSnapshot {
                dependencies.mergeSnapshotForLastSessionRestore(sourceTabSnapshot)
            }
            for snapshot in snapshotsToRestore {
                await dependencies.reopenWindow(snapshot.session)
            }
            dependencies.refreshLastSessionWindowsStore(nil)
        }
    }

    private func reopenClosedTab(_ tabState: RecentlyClosedTabState) -> Bool {
        let tabManager = dependencies.tabManager()
        let targetWindow = dependencies.activeWindow()
        guard let targetSpace = restoredSpace(
            sourceSpaceId: tabState.sourceSpaceId,
            sourceProfileId: tabState.profileId,
            fallbackWindow: targetWindow
        ) else {
            return false
        }

        let restoredTab = tabManager.createNewTab(
            url: (tabState.currentURL ?? tabState.url).absoluteString,
            in: targetSpace,
            activate: false
        )
        restoredTab.name = tabState.title
        restoredTab.restoredCanGoBack = tabState.canGoBack
        restoredTab.restoredCanGoForward = tabState.canGoForward

        if let targetWindow {
            dependencies.selectTab(restoredTab, targetWindow)
        } else {
            tabManager.setActiveTab(restoredTab)
        }
        return true
    }

    private func reopenClosedShortcutLiveInstance(_ shortcutState: RecentlyClosedShortcutLiveState) -> Bool {
        let tabManager = dependencies.tabManager()
        guard let targetWindow = targetWindowForClosedShortcut(shortcutState) else {
            if tabManager.shortcutPin(by: shortcutState.pin.id) == nil {
                return restoreShortcutLauncher(from: shortcutState.pin) != nil
            }
            return false
        }

        guard let pin = tabManager.shortcutPin(by: shortcutState.pin.id) else {
            return restoreShortcutLauncher(from: shortcutState.pin, fallbackWindow: targetWindow) != nil
        }

        let restoredTab = tabManager.activateShortcutPin(
            pin,
            in: targetWindow.id,
            currentSpaceId: targetWindow.currentSpaceId
        )
        applyShortcutLiveState(shortcutState, to: restoredTab)
        dependencies.selectTab(restoredTab, targetWindow)
        return true
    }

    private func targetWindowForClosedShortcut(_ shortcutState: RecentlyClosedShortcutLiveState) -> BrowserWindowState? {
        if let sourceWindowId = shortcutState.sourceWindowId,
           let sourceWindow = dependencies.windowState(sourceWindowId) {
            return sourceWindow
        }
        return dependencies.activeWindow()
    }

    private func applyShortcutLiveState(
        _ shortcutState: RecentlyClosedShortcutLiveState,
        to tab: Tab
    ) {
        tab.name = shortcutState.title
        tab.url = shortcutState.url
        tab.restoredCanGoBack = shortcutState.canGoBack
        tab.restoredCanGoForward = shortcutState.canGoForward
        _ = tab.applyCachedFaviconOrPlaceholder(for: shortcutState.url)

        if tab.existingWebView != nil {
            tab.loadURL(shortcutState.url)
        }
    }

    @discardableResult
    private func restoreShortcutLauncher(
        from pinState: RecentlyClosedShortcutPinState,
        fallbackWindow: BrowserWindowState? = nil
    ) -> ShortcutPin? {
        let tabManager = dependencies.tabManager()
        if let existing = tabManager.shortcutPin(by: pinState.id) {
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
                tabManager.folderSpaceId(for: folderId) == spaceId ? folderId : nil
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
              let inserted = tabManager.insertShortcutPin(restoredPin, at: pinState.index)
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
        let profileManager = dependencies.profileManager()
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
        let tabManager = dependencies.tabManager()
        if let spaceId = pinState.spaceId,
           tabManager.spaces.contains(where: { $0.id == spaceId }) {
            return spaceId
        }
        if let spaceId = fallbackWindow?.currentSpaceId,
           tabManager.spaces.contains(where: { $0.id == spaceId }) {
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
        let tabManager = dependencies.tabManager()
        if let sourceSpaceId,
           let sourceSpace = dependencies.space(sourceSpaceId) {
            return sourceSpace
        }
        if let spaceId = fallbackWindow?.currentSpaceId,
           let windowSpace = dependencies.space(spaceId) {
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
        tabManager.spaces.first(where: { $0.profileId == profileId })
    }
}

extension BrowserRecentlyClosedRestoreOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let startupRestoreOwner = browserManager.startupSessionRestoreOwner
        return Self(
            recentlyClosedManager: {
                [weak browserManager, recentlyClosedManager = browserManager.recentlyClosedManager] in
                browserManager?.recentlyClosedManager ?? recentlyClosedManager
            },
            startupRestore: startupRestoreOwner,
            lastSessionWindowsStore: {
                [weak browserManager, lastSessionWindowsStore = browserManager.lastSessionWindowsStore] in
                browserManager?.lastSessionWindowsStore ?? lastSessionWindowsStore
            },
            currentRegularWindowSnapshots: { [weak browserManager] excludedWindowId in
                browserManager?.currentRegularWindowSnapshots(excludingWindowID: excludedWindowId) ?? []
            },
            refreshLastSessionWindowsStore: { [weak browserManager] excludedWindowId in
                browserManager?.refreshLastSessionWindowsStore(excludingWindowID: excludedWindowId)
            },
            reopenWindow: { [weak browserManager] snapshot in
                await browserManager?.reopenWindow(from: snapshot)
            },
            mergeSnapshotForLastSessionRestore: { [weak browserManager] snapshot in
                browserManager?.tabManager.mergeSnapshotForLastSessionRestore(snapshot)
            },
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            tabManager: { [weak browserManager, tabManager = browserManager.tabManager] in
                browserManager?.tabManager ?? tabManager
            },
            profileManager: { [weak browserManager, profileManager = browserManager.profileManager] in
                browserManager?.profileManager ?? profileManager
            },
            space: { [weak browserManager] spaceId in
                browserManager?.space(for: spaceId)
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            }
        )
    }
}
