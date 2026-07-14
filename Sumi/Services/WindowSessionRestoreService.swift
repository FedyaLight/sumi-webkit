import Foundation

/// Orchestrates window-session restoration. Durable I/O, restore-cycle state,
/// selection reconciliation, shortcuts, splits, themes, and snapshot mutation
/// are implemented by separate collaborators.
@MainActor
final class WindowSessionRestoreService {
    private enum PreparedRegistrationKind {
        case archived(glanceSession: GlanceSessionSnapshot?)
        case contextualWindowWithInitialTab(executionProfileID: UUID)
    }

    private struct PreparedRegistration {
        let windowIdentity: ObjectIdentifier
        let kind: PreparedRegistrationKind
    }

    private let snapshotStore: WindowSessionSnapshotStore
    private let persistence: WindowSessionPersistenceCoordinator
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
    private var preparedRegistrationsByWindowID: [UUID: PreparedRegistration] = [:]

    init(
        snapshotStore: WindowSessionSnapshotStore,
        persistence: WindowSessionPersistenceCoordinator,
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
            glanceManager: glanceManager
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

        let durableWindows = windows.filter { $0.isIncognito == false }
        guard durableWindows.isEmpty == false else { return }
        let selection = requiredSelection()
        let selectionReconciler = makeSelectionReconciler(selection: selection)
        for windowState in durableWindows {
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
        }
        persistence.persist(durableWindows)

        RuntimeDiagnostics.debug(
            "Window state reconciliation completed after TabManager load.",
            category: "WindowSessionRestore"
        )
    }

    func setupWindowState(
        _ windowState: BrowserWindowState,
        currentProfile: Profile?,
        persistsWindowSession: Bool = true
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
            windowState.restorationState.isAwaitingInitialResolution = true
            floatingBarSanitizer.sanitize(in: windowState)
            themeRestorer.restore(
                for: windowState,
                source: "setupWindowState.preInitialTabManagerLoad"
            )
            return
        }

        finalizeWindowStateRestore(
            windowState,
            source: "setupWindowState",
            persistsWindowSession: persistsWindowSession
        )
    }

    /// Stamps an archived identity and its persisted fields before the shell
    /// can register, activate, notify extensions, or become visible.
    func prepareArchivedWindow(
        _ snapshot: LastSessionWindowSnapshot,
        forRegistration windowState: BrowserWindowState
    ) {
        precondition(
            preparedRegistrationsByWindowID[windowState.id] == nil,
            "A browser window cannot prepare two archived sessions"
        )
        windowState.tabManager = tabManager
        windowState.restorationState.restoredSessionWindowID = snapshot.id
        windowState.restorationState.isAwaitingInitialResolution = true
        preparedRegistrationsByWindowID[windowState.id] = PreparedRegistration(
            windowIdentity: ObjectIdentifier(windowState),
            kind: .archived(glanceSession: snapshot.session.glanceSession)
        )
        snapshotApplier.prepareForRegistration(
            snapshot.session,
            to: windowState
        )
    }

    /// A WebKit child window arrives with a concrete configuration that must
    /// be installed before the shell can become observable. This preparation
    /// records that the exact initial Tab will already exist at registration.
    @discardableResult
    func prepareContextualWindowWithInitialTab(
        profileID: UUID,
        spaceID: UUID,
        initialTabExecutionProfileID: UUID,
        forRegistration windowState: BrowserWindowState
    ) -> Bool {
        precondition(
            preparedRegistrationsByWindowID[windowState.id] == nil,
            "A browser window cannot prepare two registration contexts"
        )
        guard let space = spaceResolver.space(for: spaceID),
              space.profileId == profileID
        else {
            return false
        }
        windowState.tabManager = tabManager
        windowState.restorationState.isAwaitingInitialResolution = true
        windowState.currentProfileId = profileID
        windowState.currentSpaceId = space.id
        preparedRegistrationsByWindowID[windowState.id] = PreparedRegistration(
            windowIdentity: ObjectIdentifier(windowState),
            kind: .contextualWindowWithInitialTab(
                executionProfileID: initialTabExecutionProfileID
            )
        )
        return true
    }

    /// Discards an unconsumed preparation when shell publication is rejected.
    /// UUID equality is insufficient: only the exact prepared runtime object
    /// may cancel its registration transaction.
    @discardableResult
    func cancelPreparedWindowRegistration(
        _ windowState: BrowserWindowState
    ) -> Bool {
        guard let prepared = preparedRegistrationsByWindowID[windowState.id],
              prepared.windowIdentity == ObjectIdentifier(windowState) else {
            return false
        }
        preparedRegistrationsByWindowID.removeValue(forKey: windowState.id)
        return true
    }

    /// Completes either a prepared archived restore or the ordinary global
    /// startup/default restore after WindowRegistry has published the state.
    func restoreRegisteredWindow(
        _ windowState: BrowserWindowState,
        currentProfile: Profile?
    ) {
        guard let prepared = preparedRegistrationsByWindowID
            .removeValue(forKey: windowState.id) else {
            setupWindowState(
                windowState,
                currentProfile: currentProfile,
                persistsWindowSession: false
            )
            return
        }
        precondition(
            prepared.windowIdentity == ObjectIdentifier(windowState),
            "A different window object attempted to consume a prepared session"
        )
        switch prepared.kind {
        case .archived(let glanceSession):
            precondition(
                windowState.restorationState.restoredSessionWindowID != nil,
                "Prepared archived window lost its stable session identity"
            )
            glanceManager.restoreSession(
                glanceSession,
                in: windowState
            )
            finalizeWindowStateRestore(
                windowState,
                source: "preparedArchivedWindow",
                persistsWindowSession: false
            )
        case .contextualWindowWithInitialTab(let executionProfileID):
            guard windowState.restorationState.restoredSessionWindowID == nil,
                  finalizeContextualWindowWithInitialTab(
                      windowState,
                      executionProfileID: executionProfileID
                  )
            else {
                RuntimeDiagnostics.emit(
                    "[WindowSessionRestore] Rejected inconsistent contextual WebKit child window \(windowState.id)"
                )
                return
            }
        }
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
        source: String,
        persistsWindowSession: Bool = true
    ) {
        let selection = requiredSelection()
        shortcutRestorer.materializeSelectionIfNeeded(in: windowState)
        splitRestorer.restorePendingSelectionIfNeeded(in: windowState)
        glanceManager.restorePendingSessionIfPossible(in: windowState)
        makeSelectionReconciler(selection: selection)
            .reconcileFinalSelection(windowState)

        floatingBarSanitizer.sanitize(in: windowState)
        selection.syncShortcutSelectionState(for: windowState)
        themeRestorer.restore(for: windowState, source: source)

        completeInitialResolution(for: windowState)
        RuntimeDiagnostics.debug(
            "Setup window state \(windowState.id.uuidString) currentTab=\(windowState.currentTabId?.uuidString ?? "none") currentSpace=\(windowState.currentSpaceId?.uuidString ?? "none")",
            category: "WindowSessionRestore"
        )
        if persistsWindowSession {
            persistence.persist(windowState)
        }
    }

    private func finalizeContextualWindowWithInitialTab(
        _ windowState: BrowserWindowState,
        executionProfileID: UUID
    ) -> Bool {
        guard let tabID = windowState.currentTabId,
              let tab = tabManager.tabCollectionMembershipOwner.tab(for: tabID)
        else {
            return false
        }
        guard let spaceID = windowState.currentSpaceId,
              tab.spaceId == spaceID,
              let spaceProfileID = tabManager.spaceStateOwner.profileId(
                  for: spaceID
              ),
              spaceProfileID == windowState.currentProfileId,
              (tab.profileId ?? spaceProfileID) == executionProfileID
        else {
            return false
        }
        windowState.isShowingEmptyState = false
        floatingBarSanitizer.sanitize(in: windowState)
        requiredSelection().syncShortcutSelectionState(for: windowState)
        themeRestorer.restore(
            for: windowState,
            source: "preparedContextualWindowWithInitialTab"
        )
        completeInitialResolution(for: windowState)
        return true
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
        windowState.restorationState.isAwaitingInitialResolution = false
        StartupPerformanceTrace.firstSelectedTabResolved()
        StartupPerformanceTrace.firstTabsClickable()
    }
}
