import Foundation

/// Replaces the loaded browser session with an intentionally clean startup
/// while preserving the displaced session as a manual restore branch.
@MainActor
final class CleanStartupWorkflow {
    private let regularWindows: @MainActor () -> [BrowserWindowState]
    private let startupRestore: BrowserStartupSessionRestoreOwner
    private let tabManager: TabManager
    private let glanceManager: GlanceManager
    private let openWindows: OpenWindowSessionCatalog
    private let selectTab: @MainActor (
        Tab,
        BrowserWindowState,
        TabSelectionLoadPolicy
    ) -> Void
    private let showEmptyState: @MainActor (BrowserWindowState, Bool) -> Void

    var firstRegularWindow: BrowserWindowState? {
        regularWindows().min { $0.id.uuidString < $1.id.uuidString }
    }

    init(
        regularWindows: @escaping @MainActor () -> [BrowserWindowState],
        startupRestore: BrowserStartupSessionRestoreOwner,
        tabManager: TabManager,
        glanceManager: GlanceManager,
        openWindows: OpenWindowSessionCatalog,
        selectTab: @escaping @MainActor (
            Tab,
            BrowserWindowState,
            TabSelectionLoadPolicy
        ) -> Void,
        showEmptyState: @escaping @MainActor (BrowserWindowState, Bool) -> Void
    ) {
        self.regularWindows = regularWindows
        self.startupRestore = startupRestore
        self.tabManager = tabManager
        self.glanceManager = glanceManager
        self.openWindows = openWindows
        self.selectTab = selectTab
        self.showEmptyState = showEmptyState
    }

    func apply(opening startupURL: URL?) {
        archiveLoadedSessionForManualRestore()
        tabManager.startupStateReset.resetRegularTabsAndShortcutLiveInstances()

        guard let selectedWindow = firstRegularWindow else { return }
        resetWindowStates(selectedWindow: selectedWindow)

        if let startupURL {
            openStartupPage(startupURL, in: selectedWindow)
        } else {
            showEmptyState(selectedWindow, true)
        }

        Task { @MainActor [weak tabManager] in
            _ = await tabManager?.structuralPersistence
                .persistFullReconcileAwaitingResult(reason: "startup clean policy")
        }
    }

    private func archiveLoadedSessionForManualRestore() {
        startupRestore.archiveLoadedSessionForManualRestore(
            currentWindowSnapshots: {
                self.openWindows.regularWindowSnapshots(excludingWindowID: nil)
            },
            currentTabSnapshot: {
                self.tabManager.structuralPersistence.buildSnapshot()
            }
        )
    }

    private func resetWindowStates(selectedWindow: BrowserWindowState) {
        for windowState in regularWindows() {
            let fallbackSpaceId = resolvedStartupSpace(for: windowState)?.id

            windowState.currentTabId = nil
            windowState.restorationState.restoredSessionWindowID = nil
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
            windowState.activeTabForSpace.removeAll()
            windowState.selectionHistory.recentRegularTabIdsBySpace.removeAll()
            windowState.selectedShortcutPinForSpace.removeAll()
            windowState.selectionHistory.recentSelectionItemsBySpace.removeAll()
            windowState.splitSelection = nil
            windowState.restorationState.pendingSplitSelection = nil
            windowState.restorationState.pendingLegacySplitGroup = nil
            windowState.isShowingEmptyState = windowState.id == selectedWindow.id
            windowState.floatingBarPresentationReason = .none
            windowState.presentationState.isFloatingBarVisible = false
            windowState.floatingBarDraftText = ""
            windowState.floatingBarDraftNavigatesCurrentTab = false
            windowState.currentSpaceId = fallbackSpaceId
            windowState.currentProfileId = fallbackSpaceId.flatMap {
                tabManager.spaceStateOwner.space(with: $0)?.profileId
            }
            windowState.restorationState.isAwaitingInitialResolution = false
            glanceManager.restoreSession(nil, in: windowState)
            windowState.compositorInvalidation.refresh()
        }
    }

    private func openStartupPage(
        _ startupURL: URL,
        in windowState: BrowserWindowState
    ) {
        guard let targetSpace = resolvedStartupSpace(for: windowState) else {
            showEmptyState(windowState, true)
            return
        }
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: startupURL.absoluteString,
            in: targetSpace,
            activate: false
        )
        selectTab(tab, windowState, .deferred)
    }

    private func resolvedStartupSpace(
        for windowState: BrowserWindowState
    ) -> Space? {
        if let currentSpaceId = windowState.currentSpaceId,
           let currentSpace = tabManager.spaceStateOwner.space(with: currentSpaceId) {
            return currentSpace
        }
        guard let profileId = windowState.currentProfileId else { return nil }
        return tabManager.spaceStateOwner.spaces.first {
            $0.profileId == profileId
        }
    }
}
