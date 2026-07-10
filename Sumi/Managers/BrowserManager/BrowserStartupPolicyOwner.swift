import Foundation
import SumiDomain

@MainActor
final class BrowserStartupPolicyOwner {
    private let regularWindows: @MainActor () -> [BrowserWindowState]
    private let startupRestoreOwner: @MainActor () -> BrowserStartupSessionRestoreOwner
    private let tabManager: @MainActor () -> TabManager
    private let startupPageURL: @MainActor () -> URL?
    private let space: @MainActor (UUID?) -> Space?
    private let splitManager: @MainActor () -> SplitViewManager
    private let glanceManager: @MainActor () -> GlanceManager
    private let selectTab: @MainActor (Tab, BrowserWindowState, TabSelectionLoadPolicy) -> Void
    private let showEmptyState: @MainActor (BrowserWindowState, Bool) -> Void
    private let currentRegularWindowSnapshots: @MainActor (UUID?) -> [LastSessionWindowSnapshot]
    private let currentTabSnapshot: @MainActor () -> TabPersistenceSnapshot
    private let applyWindowSessionSnapshot: @MainActor (WindowSessionSnapshot, BrowserWindowState) -> Void
    private let reopenWindow: @MainActor (WindowSessionSnapshot) async -> Void
    private let refreshLastSessionWindowsStore: @MainActor (UUID?) -> Void

    init(
        regularWindows: @escaping @MainActor () -> [BrowserWindowState],
        startupRestoreOwner: @escaping @MainActor () -> BrowserStartupSessionRestoreOwner,
        tabManager: @escaping @MainActor () -> TabManager,
        startupPageURL: @escaping @MainActor () -> URL?,
        space: @escaping @MainActor (UUID?) -> Space?,
        splitManager: @escaping @MainActor () -> SplitViewManager,
        glanceManager: @escaping @MainActor () -> GlanceManager,
        selectTab: @escaping @MainActor (Tab, BrowserWindowState, TabSelectionLoadPolicy) -> Void,
        showEmptyState: @escaping @MainActor (BrowserWindowState, Bool) -> Void,
        currentRegularWindowSnapshots: @escaping @MainActor (UUID?) -> [LastSessionWindowSnapshot],
        currentTabSnapshot: @escaping @MainActor () -> TabPersistenceSnapshot,
        applyWindowSessionSnapshot: @escaping @MainActor (WindowSessionSnapshot, BrowserWindowState) -> Void,
        reopenWindow: @escaping @MainActor (WindowSessionSnapshot) async -> Void,
        refreshLastSessionWindowsStore: @escaping @MainActor (UUID?) -> Void
    ) {
        self.regularWindows = regularWindows
        self.startupRestoreOwner = startupRestoreOwner
        self.tabManager = tabManager
        self.startupPageURL = startupPageURL
        self.space = space
        self.splitManager = splitManager
        self.glanceManager = glanceManager
        self.selectTab = selectTab
        self.showEmptyState = showEmptyState
        self.currentRegularWindowSnapshots = currentRegularWindowSnapshots
        self.currentTabSnapshot = currentTabSnapshot
        self.applyWindowSessionSnapshot = applyWindowSessionSnapshot
        self.reopenWindow = reopenWindow
        self.refreshLastSessionWindowsStore = refreshLastSessionWindowsStore
    }

    var firstRegularWindowForStartupPolicy: BrowserWindowState? {
        regularWindows()
            .min { $0.id.uuidString < $1.id.uuidString }
    }

    func applyStartupPolicy(_ mode: SumiStartupMode) {
        switch mode {
        case .restorePreviousSession:
            restoreAdditionalStartupWindowsIfNeeded()
        case .nothing:
            applyCleanStartupPolicy(opening: nil)
        case .specificPage:
            applyCleanStartupPolicy(opening: startupPageURL() ?? SumiSurface.emptyTabURL)
        }
    }

    private func applyCleanStartupPolicy(opening startupURL: URL?) {
        archiveLoadedStartupSessionForManualRestore()

        let tabManager = tabManager()
        tabManager.startupStateReset.resetRegularTabsAndShortcutLiveInstances()

        guard let windowState = firstRegularWindowForStartupPolicy else { return }
        resetWindowStatesForCleanStartup(selectedWindow: windowState)

        if let startupURL {
            guard let targetSpace = resolvedStartupSpace(
                tabManager: tabManager,
                windowState: windowState
            ) else {
                showEmptyState(windowState, true)
                return
            }
            let tab = tabManager.regularTabLifecycleOwner.createNewTab(
                url: startupURL.absoluteString,
                in: targetSpace,
                activate: false
            )
            selectTab(tab, windowState, .deferred)
        } else {
            showEmptyState(windowState, true)
        }

        Task { [weak self] in
            _ = await self?.tabManager().persistFullReconcileAwaitingResult(
                reason: "startup clean policy"
            )
        }
    }

    private func archiveLoadedStartupSessionForManualRestore() {
        startupRestoreOwner().archiveLoadedSessionForManualRestore(
            currentWindowSnapshots: {
                self.currentRegularWindowSnapshots(nil)
            },
            currentTabSnapshot: {
                self.currentTabSnapshot()
            }
        )
    }

    private func resetWindowStatesForCleanStartup(selectedWindow: BrowserWindowState) {
        let tabManager = tabManager()
        for windowState in regularWindows() {
            let fallbackSpaceId = resolvedStartupSpace(
                tabManager: tabManager,
                windowState: windowState
            )?.id

            windowState.currentTabId = nil
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
            windowState.activeTabForSpace.removeAll()
            windowState.selectionHistory.recentRegularTabIdsBySpace.removeAll()
            windowState.selectedShortcutPinForSpace.removeAll()
            windowState.selectionHistory.recentSelectionItemsBySpace.removeAll()
            windowState.pendingSessionSplitGroupId = nil
            windowState.isShowingEmptyState = windowState.id == selectedWindow.id
            windowState.floatingBarPresentationReason = .none
            windowState.isFloatingBarVisible = false
            windowState.floatingBarDraftText = ""
            windowState.floatingBarDraftNavigatesCurrentTab = false
            windowState.currentSpaceId = fallbackSpaceId
            windowState.currentProfileId = fallbackSpaceId.flatMap { space($0)?.profileId }
            windowState.isAwaitingInitialSessionResolution = false
            glanceManager().restoreSession(nil, in: windowState)
            windowState.compositorInvalidation.refresh()
        }
    }

    private func resolvedStartupSpace(
        tabManager: TabManager,
        windowState: BrowserWindowState
    ) -> Space? {
        if let currentSpace = space(windowState.currentSpaceId) {
            return currentSpace
        }

        if let profileId = windowState.currentProfileId,
           let profileSpace = firstSpace(for: profileId, tabManager: tabManager) {
            return profileSpace
        }

        return nil
    }

    private func firstSpace(
        for profileId: UUID,
        tabManager: TabManager
    ) -> Space? {
        tabManager.spaceStateOwner.spaces.first(where: { $0.profileId == profileId })
    }

    private func restoreAdditionalStartupWindowsIfNeeded() {
        let startupRestoreOwner = startupRestoreOwner()
        guard !startupRestoreOwner.windowSnapshots.isEmpty else { return }

        startupRestoreOwner.markRestoreOfferConsumed()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let existingSessions = Set(
                self.currentRegularWindowSnapshots(nil).map(\.session)
            )
            let startupWindow = self.firstRegularWindowForStartupPolicy
            let restorationPlan = StartupWindowRestorationPlanner.plan(
                archivedSnapshots: self.startupRestoreOwner().windowSnapshots,
                existingSessions: existingSessions,
                hasStartupWindow: startupWindow != nil
            )

            if let startupWindow,
               let primarySnapshot = restorationPlan.primarySnapshotForStartupWindow {
                self.applyWindowSessionSnapshot(
                    primarySnapshot.session,
                    startupWindow
                )
            }

            let refreshedExistingSessions = Set(
                self.currentRegularWindowSnapshots(nil).map(\.session)
            )
            let unresolvedSnapshotsToRestore = restorationPlan.additionalSnapshots.filter {
                !refreshedExistingSessions.contains($0.session)
            }
            for snapshot in unresolvedSnapshotsToRestore {
                await self.reopenWindow(snapshot.session)
            }
            self.refreshLastSessionWindowsStore(nil)
        }
    }
}
