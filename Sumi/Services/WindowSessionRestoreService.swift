import Foundation

/// Orchestrates window-session restoration. Durable I/O, restore-cycle state,
/// selection reconciliation, shortcuts, splits, themes, and snapshot mutation
/// are implemented by separate collaborators.
@MainActor
final class WindowSessionRestoreService {
    private let snapshotStore: WindowSessionSnapshotStore
    private let persistence: WindowSessionPersistenceService
    private let tabManager: TabManager
    private let glanceManager: GlanceManager
    private let cycle: WindowSessionRestoreCycle
    private let spaceResolver: WindowSessionSpaceResolver
    private let shortcutRestorer: WindowSessionShortcutRestorer
    private let splitRestorer: WindowSessionSplitRestorer
    private let themeRestorer: WindowSessionThemeRestorer
    private let snapshotApplier: WindowSessionSnapshotApplier
    private let selectionService: ShellSelectionService
    private let floatingBarSanitizer: any WindowSessionFloatingBarSanitizing
    private weak var selection: (any WindowSessionSelectionApplying)?

    init(
        snapshotStore: WindowSessionSnapshotStore,
        persistence: WindowSessionPersistenceService,
        tabManager: TabManager,
        glanceManager: GlanceManager,
        selectionService: ShellSelectionService,
        selection: any WindowSessionSelectionApplying,
        floatingBarSanitizer: any WindowSessionFloatingBarSanitizing,
        themeCommitter: any WindowSessionThemeCommitting,
        splitFocus: any WindowSessionSplitFocusing,
        cycle: WindowSessionRestoreCycle = WindowSessionRestoreCycle()
    ) {
        let spaceResolver = WindowSessionSpaceResolver(tabManager: tabManager)
        self.snapshotStore = snapshotStore
        self.persistence = persistence
        self.tabManager = tabManager
        self.glanceManager = glanceManager
        self.cycle = cycle
        self.spaceResolver = spaceResolver
        self.shortcutRestorer = WindowSessionShortcutRestorer(
            tabManager: tabManager
        )
        self.splitRestorer = WindowSessionSplitRestorer(
            tabManager: tabManager,
            focus: splitFocus
        )
        self.themeRestorer = WindowSessionThemeRestorer(
            tabManager: tabManager,
            spaceResolver: spaceResolver,
            themeCommitter: themeCommitter
        )
        self.snapshotApplier = WindowSessionSnapshotApplier(
            glanceManager: glanceManager,
            floatingBarSanitizer: floatingBarSanitizer
        )
        self.selectionService = selectionService
        self.floatingBarSanitizer = floatingBarSanitizer
        self.selection = selection
    }

    /// Allows a new non-incognito window to claim the global snapshot after
    /// every browser window from the previous cycle has closed.
    func prepareForAllWindowsClosed() {
        cycle.reset(store: snapshotStore)
    }

    func handleTabManagerDataLoaded(windows: [BrowserWindowState]) {
        let startupTrace = StartupPerformanceTrace.sessionRestoreStarted()
        defer {
            StartupPerformanceTrace.sessionRestoreFinished(startupTrace)
        }

        RuntimeDiagnostics.debug(
            "TabManager finished loading persisted data; reconciling window state.",
            category: "WindowSessionRestore"
        )

        let selection = requiredSelection()
        let selectionReconciler = makeSelectionReconciler(selection: selection)
        for windowState in windows {
            if spaceResolver.space(for: windowState.currentSpaceId) == nil {
                windowState.currentSpaceId = spaceResolver.resolve(
                    for: windowState
                )
            }

            if shortcutRestorer.materializeSelectionIfNeeded(
                in: windowState
            ) == false {
                selectionReconciler.discardMissingTabAfterInitialDataLoad(
                    windowState
                )
            }

            SidebarUITestShortcutDriftOverride.applyIfNeeded(
                to: windowState,
                tabManager: tabManager
            )
            selectionReconciler.resolveMissingSelectionAfterInitialDataLoad(
                windowState
            )
            selection.syncShortcutSelectionState(for: windowState)
            splitRestorer.restorePendingSelectionIfNeeded(in: windowState)
            glanceManager.restorePendingSessionIfPossible(in: windowState)
            themeRestorer.restore(
                for: windowState,
                source: "tabManagerDataLoaded"
            )

            completeInitialResolution(for: windowState)
            windowState.compositorInvalidation.refresh()
            persistence.persist(windowState)
        }

        RuntimeDiagnostics.debug(
            "Window state reconciliation completed after TabManager load.",
            category: "WindowSessionRestore"
        )
    }

    func setupWindowState(
        _ windowState: BrowserWindowState,
        currentProfile: Profile?
    ) {
        windowState.tabManager = tabManager

        let restored: Bool
        if let snapshot = cycle.claimSnapshot(
            from: snapshotStore,
            for: windowState
        ) {
            snapshotApplier.apply(snapshot, to: windowState)
            restored = true
        } else {
            let activeProfileId = currentProfile?.id
            windowState.currentProfileId = activeProfileId
            windowState.currentSpaceId = spaceResolver.resolve(
                for: windowState,
                seededProfileId: activeProfileId
            )
            restored = false
        }

        if restored && tabManager.startupRestoreLifecycle.hasLoadedInitialData == false {
            themeRestorer.restore(
                for: windowState,
                source: "setupWindowState.preInitialTabManagerLoad"
            )
            return
        }

        finalizeWindowStateRestore(
            windowState,
            source: "setupWindowState"
        )
    }

    func applyWindowSessionSnapshot(
        _ snapshot: WindowSessionSnapshot,
        to windowState: BrowserWindowState
    ) {
        windowState.tabManager = tabManager
        snapshotApplier.apply(snapshot, to: windowState)
        finalizeWindowStateRestore(
            windowState,
            source: "applyWindowSessionSnapshot"
        )
    }

    private func finalizeWindowStateRestore(
        _ windowState: BrowserWindowState,
        source: String
    ) {
        let selection = requiredSelection()
        shortcutRestorer.materializeSelectionIfNeeded(in: windowState)
        splitRestorer.restorePendingSelectionIfNeeded(in: windowState)
        glanceManager.restorePendingSessionIfPossible(in: windowState)
        makeSelectionReconciler(selection: selection)
            .reconcileFinalSelection(windowState)

        floatingBarSanitizer.sanitizeFloatingBarState(in: windowState)
        selection.syncShortcutSelectionState(for: windowState)
        splitRestorer.restorePendingSelectionIfNeeded(in: windowState)
        themeRestorer.restore(for: windowState, source: source)

        completeInitialResolution(for: windowState)
        RuntimeDiagnostics.debug(
            "Setup window state \(windowState.id.uuidString) currentTab=\(windowState.currentTabId?.uuidString ?? "none") currentSpace=\(windowState.currentSpaceId?.uuidString ?? "none")",
            category: "WindowSessionRestore"
        )
        persistence.persist(windowState)
    }

    private func makeSelectionReconciler(
        selection: any WindowSessionSelectionApplying
    ) -> WindowSessionSelectionReconciler {
        WindowSessionSelectionReconciler(
            tabManager: tabManager,
            selectionService: selectionService,
            selection: selection,
            spaceResolver: spaceResolver
        )
    }

    private func requiredSelection() -> any WindowSessionSelectionApplying {
        guard let selection else {
            preconditionFailure(
                "Window session restoration outlived its selection capability"
            )
        }
        return selection
    }

    private func completeInitialResolution(
        for windowState: BrowserWindowState
    ) {
        windowState.isAwaitingInitialSessionResolution = false
        StartupPerformanceTrace.firstSelectedTabResolved()
        StartupPerformanceTrace.firstTabsClickable()
    }
}
