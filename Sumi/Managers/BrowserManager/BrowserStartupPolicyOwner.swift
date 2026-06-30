import Foundation

@MainActor
final class BrowserStartupPolicyOwner {
    struct Dependencies {
        let regularWindows: @MainActor () -> [BrowserWindowState]
        let startupRestoreOwner: @MainActor () -> BrowserStartupSessionRestoreOwner
        let tabManager: @MainActor () -> TabManager
        let currentProfile: @MainActor () -> Profile?
        let startupPageURL: @MainActor () -> URL?
        let space: @MainActor (UUID?) -> Space?
        let splitManager: @MainActor () -> SplitViewManager
        let glanceManager: @MainActor () -> GlanceManager
        let selectTab: @MainActor (Tab, BrowserWindowState, TabSelectionLoadPolicy) -> Void
        let showEmptyState: @MainActor (BrowserWindowState) -> Void
        let currentRegularWindowSnapshots: @MainActor (UUID?) -> [LastSessionWindowSnapshot]
        let currentTabSnapshot: @MainActor () -> TabSnapshotRepository.Snapshot
        let applyWindowSessionSnapshot: @MainActor (WindowSessionSnapshot, BrowserWindowState) -> Void
        let reopenWindow: @MainActor (WindowSessionSnapshot) async -> Void
        let refreshLastSessionWindowsStore: @MainActor (UUID?) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var firstRegularWindowForStartupPolicy: BrowserWindowState? {
        dependencies.regularWindows()
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .first
    }

    func applyStartupPolicy(_ mode: SumiStartupMode) {
        switch mode {
        case .restorePreviousSession:
            restoreAdditionalStartupWindowsIfNeeded()
        case .nothing:
            applyCleanStartupPolicy(opening: nil)
        case .specificPage:
            applyCleanStartupPolicy(opening: dependencies.startupPageURL() ?? SumiSurface.emptyTabURL)
        }
    }

    private func applyCleanStartupPolicy(opening startupURL: URL?) {
        archiveLoadedStartupSessionForManualRestore()

        let tabManager = dependencies.tabManager()
        tabManager.resetRegularTabsAndShortcutLiveInstancesForStartup()

        guard let windowState = firstRegularWindowForStartupPolicy else { return }
        resetWindowStatesForCleanStartup(selectedWindow: windowState)

        if let startupURL {
            let targetSpace = dependencies.space(windowState.currentSpaceId)
                ?? tabManager.currentSpace
                ?? tabManager.spaces.first
            let tab = tabManager.createNewTab(
                url: startupURL.absoluteString,
                in: targetSpace,
                activate: false
            )
            dependencies.selectTab(tab, windowState, .deferred)
        } else {
            dependencies.showEmptyState(windowState)
        }

        Task { [weak self] in
            _ = await self?.dependencies.tabManager().persistFullReconcileAwaitingResult(
                reason: "startup clean policy"
            )
        }
    }

    private func archiveLoadedStartupSessionForManualRestore() {
        dependencies.startupRestoreOwner().archiveLoadedSessionForManualRestore(
            currentWindowSnapshots: {
                dependencies.currentRegularWindowSnapshots(nil)
            },
            currentTabSnapshot: {
                dependencies.currentTabSnapshot()
            }
        )
    }

    private func resetWindowStatesForCleanStartup(selectedWindow: BrowserWindowState) {
        let tabManager = dependencies.tabManager()
        for windowState in dependencies.regularWindows() {
            let fallbackSpaceId = windowState.currentSpaceId
                ?? tabManager.currentSpace?.id
                ?? tabManager.spaces.first?.id

            windowState.currentTabId = nil
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
            windowState.activeTabForSpace.removeAll()
            windowState.recentRegularTabIdsBySpace.removeAll()
            windowState.selectedShortcutPinForSpace.removeAll()
            windowState.recentSelectionItemsBySpace.removeAll()
            windowState.pendingSessionSplitGroupId = nil
            windowState.isShowingEmptyState = windowState.id == selectedWindow.id
            windowState.floatingBarPresentationReason =
                windowState.id == selectedWindow.id ? .emptySpace : .none
            windowState.currentSpaceId = fallbackSpaceId
            windowState.currentProfileId = fallbackSpaceId.flatMap { dependencies.space($0)?.profileId }
                ?? dependencies.currentProfile()?.id
            windowState.isAwaitingInitialSessionResolution = false
            dependencies.glanceManager().restoreSession(nil, in: windowState)
            windowState.refreshCompositor()
        }
    }

    private func restoreAdditionalStartupWindowsIfNeeded() {
        let startupRestoreOwner = dependencies.startupRestoreOwner()
        guard !startupRestoreOwner.windowSnapshots.isEmpty else { return }

        startupRestoreOwner.markRestoreOfferConsumed()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let existingSessions = Set(
                self.dependencies.currentRegularWindowSnapshots(nil).map(\.session)
            )
            let startupWindow = self.firstRegularWindowForStartupPolicy
            let restorationPlan = StartupWindowRestorationPlanner.plan(
                archivedSnapshots: self.dependencies.startupRestoreOwner().windowSnapshots,
                existingSessions: existingSessions,
                hasStartupWindow: startupWindow != nil
            )

            if let startupWindow,
               let primarySnapshot = restorationPlan.primarySnapshotForStartupWindow {
                self.dependencies.applyWindowSessionSnapshot(
                    primarySnapshot.session,
                    startupWindow
                )
            }

            let refreshedExistingSessions = Set(
                self.dependencies.currentRegularWindowSnapshots(nil).map(\.session)
            )
            let unresolvedSnapshotsToRestore = restorationPlan.additionalSnapshots.filter {
                !refreshedExistingSessions.contains($0.session)
            }
            for snapshot in unresolvedSnapshotsToRestore {
                await self.dependencies.reopenWindow(snapshot.session)
            }
            self.dependencies.refreshLastSessionWindowsStore(nil)
        }
    }
}

extension BrowserStartupPolicyOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            regularWindows: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows
                    .filter { !$0.isIncognito } ?? []
            },
            startupRestoreOwner: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure("BrowserStartupPolicyOwner used after BrowserManager deallocation")
                }
                return browserManager.startupSessionRestoreOwner
            },
            tabManager: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure("BrowserStartupPolicyOwner used after BrowserManager deallocation")
                }
                return browserManager.tabManager
            },
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            startupPageURL: { [weak browserManager] in
                browserManager?.sumiSettings?.resolvedStartupPageURL
            },
            space: { [weak browserManager] spaceId in
                browserManager?.space(for: spaceId)
            },
            splitManager: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure("BrowserStartupPolicyOwner used after BrowserManager deallocation")
                }
                return browserManager.splitManager
            },
            glanceManager: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure("BrowserStartupPolicyOwner used after BrowserManager deallocation")
                }
                return browserManager.glanceManager
            },
            selectTab: { [weak browserManager] tab, windowState, loadPolicy in
                browserManager?.selectTab(tab, in: windowState, loadPolicy: loadPolicy)
            },
            showEmptyState: { [weak browserManager] windowState in
                browserManager?.showEmptyState(in: windowState)
            },
            currentRegularWindowSnapshots: { [weak browserManager] excludingWindowId in
                browserManager?.currentRegularWindowSnapshots(excludingWindowID: excludingWindowId) ?? []
            },
            currentTabSnapshot: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure("BrowserStartupPolicyOwner used after BrowserManager deallocation")
                }
                return browserManager.tabManager._buildSnapshot()
            },
            applyWindowSessionSnapshot: { [weak browserManager] snapshot, windowState in
                guard let browserManager else { return }
                browserManager.windowSessionService.applyWindowSessionSnapshot(
                    snapshot,
                    to: windowState,
                    runtime: browserManager.makeWindowSessionRuntime()
                )
            },
            reopenWindow: { [weak browserManager] snapshot in
                await browserManager?.reopenWindow(from: snapshot)
            },
            refreshLastSessionWindowsStore: { [weak browserManager] excludingWindowId in
                browserManager?.refreshLastSessionWindowsStore(excludingWindowID: excludingWindowId)
            }
        )
    }
}
