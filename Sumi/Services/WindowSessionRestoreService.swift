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
        let profileReferenceMutationLease: ProfileReferenceMutationLease
        let coveredProfileIDs: Set<UUID>
    }

    private let snapshotStore: WindowSessionSnapshotStore
    private let profileReferenceAdmission: ProfileReferenceAdmissionLedger
    private let persistence: WindowSessionPersistenceCoordinator
    private let membership: TabCollectionMembershipOwner
    private let startupRestore: TabStartupRestoreLifecycle
    private let tabStore: any ShellSelectionTabStore
    private let glanceManager: GlanceManager
    private let cycle: WindowSessionRestoreCycle
    private let spaceResolver: WindowSessionSpaceResolver
    private let shortcutRestorer: WindowSessionShortcutRestorer
    private let splitRestorer: WindowSessionSplitRestorer
    private let themeRestorer: WindowSessionThemeRestorer
    private let snapshotApplier: WindowSessionSnapshotApplier
    private let selectionService: ShellSelectionService
    private let commandPaletteSanitizer: any WindowSessionCommandPaletteSanitizing
    private weak var selection: (any WindowSessionSelectionApplying)?
    private var preparedRegistrationsByWindowID: [UUID: PreparedRegistration] = [:]

    init(
        snapshotStore: WindowSessionSnapshotStore,
        persistence: WindowSessionPersistenceCoordinator,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        membership: TabCollectionMembershipOwner,
        startupRestore: TabStartupRestoreLifecycle,
        tabStore: any ShellSelectionTabStore,
        glanceManager: GlanceManager,
        spaceResolver: WindowSessionSpaceResolver,
        shortcutRestorer: WindowSessionShortcutRestorer,
        splitRestorer: WindowSessionSplitRestorer,
        themeRestorer: WindowSessionThemeRestorer,
        selectionService: ShellSelectionService,
        selection: any WindowSessionSelectionApplying,
        commandPaletteSanitizer: any WindowSessionCommandPaletteSanitizing,
        cycle: WindowSessionRestoreCycle = WindowSessionRestoreCycle()
    ) {
        self.snapshotStore = snapshotStore
        self.profileReferenceAdmission = profileReferenceAdmission
        self.persistence = persistence
        self.membership = membership
        self.startupRestore = startupRestore
        self.tabStore = tabStore
        self.glanceManager = glanceManager
        self.cycle = cycle
        self.spaceResolver = spaceResolver
        self.shortcutRestorer = shortcutRestorer
        self.splitRestorer = splitRestorer
        self.themeRestorer = themeRestorer
        self.snapshotApplier = WindowSessionSnapshotApplier(
            glanceManager: glanceManager
        )
        self.selectionService = selectionService
        self.commandPaletteSanitizer = commandPaletteSanitizer
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

            shortcutRestorer.materializeRestoredLiveSessions(
                in: windowState
            )
            if shortcutRestorer.materializeSelectionIfNeeded(
                in: windowState
            ) == false {
                selectionReconciler.discardMissingTabAfterInitialDataLoad(
                    windowState
                )
            }

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
        let restored: Bool
        if let snapshot = cycle.claimSnapshot(
            from: snapshotStore,
            for: windowState
        ) {
            restored = withProfileReferenceMutation(for: snapshot) {
                snapshotApplier.apply(snapshot, to: windowState)
            }
        } else {
            restored = false
        }

        if restored == false {
            let activeProfileId = currentProfile?.id
            let didSeedFallback = withProfileReferenceMutation(
                to: Set(optional: activeProfileId)
            ) {
                windowState.currentProfileId = activeProfileId
                windowState.currentSpaceId = spaceResolver.resolve(
                    for: windowState,
                    seededProfileId: activeProfileId
                )
            }
            if didSeedFallback == false {
                windowState.currentProfileId = nil
                windowState.currentSpaceId = nil
            }
        }

        if restored && startupRestore.hasLoadedInitialData == false {
            windowState.restorationState.isAwaitingInitialResolution = true
            commandPaletteSanitizer.sanitize(in: windowState)
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
    @discardableResult
    func prepareArchivedWindow(
        _ snapshot: LastSessionWindowSnapshot,
        forRegistration windowState: BrowserWindowState
    ) -> Bool {
        precondition(
            preparedRegistrationsByWindowID[windowState.id] == nil,
            "A browser window cannot prepare two archived sessions"
        )
        let coveredProfileIDs = profileIDs(in: snapshot.session)
        let lease: ProfileReferenceMutationLease
        do {
            lease = try profileReferenceAdmission.beginReferenceMutation(
                to: coveredProfileIDs
            )
        } catch {
            return false
        }
        windowState.restorationState.restoredSessionWindowID = snapshot.id
        windowState.restorationState.isAwaitingInitialResolution = true
        snapshotApplier.prepareForRegistration(
            snapshot.session,
            to: windowState
        )
        guard profileReferenceAdmission.validate(
            lease,
            covers: coveredProfileIDs
        ) else {
            precondition(
                profileReferenceAdmission.endReferenceMutation(lease),
                "Archived window preparation lost its profile-reference mutation lease"
            )
            return false
        }
        preparedRegistrationsByWindowID[windowState.id] = PreparedRegistration(
            windowIdentity: ObjectIdentifier(windowState),
            kind: .archived(glanceSession: snapshot.session.glanceSession),
            profileReferenceMutationLease: lease,
            coveredProfileIDs: coveredProfileIDs
        )
        return true
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
        let coveredProfileIDs = Set([profileID, initialTabExecutionProfileID])
        let lease: ProfileReferenceMutationLease
        do {
            lease = try profileReferenceAdmission.beginReferenceMutation(
                to: coveredProfileIDs
            )
        } catch {
            return false
        }
        windowState.restorationState.isAwaitingInitialResolution = true
        windowState.currentProfileId = profileID
        windowState.currentSpaceId = space.id
        guard profileReferenceAdmission.validate(
            lease,
            covers: coveredProfileIDs
        ) else {
            precondition(
                profileReferenceAdmission.endReferenceMutation(lease),
                "Contextual window preparation lost its profile-reference mutation lease"
            )
            return false
        }
        preparedRegistrationsByWindowID[windowState.id] = PreparedRegistration(
            windowIdentity: ObjectIdentifier(windowState),
            kind: .contextualWindowWithInitialTab(
                executionProfileID: initialTabExecutionProfileID
            ),
            profileReferenceMutationLease: lease,
            coveredProfileIDs: coveredProfileIDs
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
        precondition(
            profileReferenceAdmission.endReferenceMutation(
                prepared.profileReferenceMutationLease
            ),
            "Prepared window cancellation lost its profile-reference mutation lease"
        )
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
        guard profileReferenceAdmission.validate(
            prepared.profileReferenceMutationLease,
            covers: prepared.coveredProfileIDs
        ) else {
            precondition(
                profileReferenceAdmission.endReferenceMutation(
                    prepared.profileReferenceMutationLease
                ),
                "Prepared window restore lost its profile-reference mutation lease"
            )
            return
        }
        defer {
            precondition(
                profileReferenceAdmission.endReferenceMutation(
                    prepared.profileReferenceMutationLease
                ),
                "Prepared window restore lost its profile-reference mutation lease"
            )
        }
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

    @discardableResult
    func applyWindowSessionSnapshot(
        _ snapshot: WindowSessionSnapshot,
        to windowState: BrowserWindowState
    ) -> Bool {
        withProfileReferenceMutation(for: snapshot) {
            snapshotApplier.apply(snapshot, to: windowState)
            finalizeWindowStateRestore(
                windowState,
                source: "applyWindowSessionSnapshot"
            )
        }
    }

    private func finalizeWindowStateRestore(
        _ windowState: BrowserWindowState,
        source: String,
        persistsWindowSession: Bool = true
    ) {
        let selection = requiredSelection()
        shortcutRestorer.materializeRestoredLiveSessions(in: windowState)
        shortcutRestorer.materializeSelectionIfNeeded(in: windowState)
        splitRestorer.restorePendingSelectionIfNeeded(in: windowState)
        glanceManager.restorePendingSessionIfPossible(in: windowState)
        makeSelectionReconciler(selection: selection)
            .reconcileFinalSelection(windowState)

        commandPaletteSanitizer.sanitize(in: windowState)
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
              let tab = membership.tab(for: tabID)
        else {
            return false
        }
        guard let spaceID = windowState.currentSpaceId,
              tab.spaceId == spaceID,
              let spaceProfileID = spaceResolver.space(for: spaceID)?.profileId,
              spaceProfileID == windowState.currentProfileId,
              (tab.profileId ?? spaceProfileID) == executionProfileID
        else {
            return false
        }
        windowState.isShowingEmptyState = false
        commandPaletteSanitizer.sanitize(in: windowState)
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
            membership: membership,
            tabStore: tabStore,
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

    private func withProfileReferenceMutation(
        for snapshot: WindowSessionSnapshot,
        _ mutation: () -> Void
    ) -> Bool {
        withProfileReferenceMutation(
            to: profileIDs(in: snapshot),
            mutation
        )
    }

    private func withProfileReferenceMutation(
        to coveredProfileIDs: Set<UUID>,
        _ mutation: () -> Void
    ) -> Bool {
        let lease: ProfileReferenceMutationLease
        do {
            lease = try profileReferenceAdmission.beginReferenceMutation(
                to: coveredProfileIDs
            )
        } catch {
            return false
        }
        defer {
            precondition(
                profileReferenceAdmission.endReferenceMutation(lease),
                "Window snapshot restore lost its profile-reference mutation lease"
            )
        }
        guard profileReferenceAdmission.validate(
            lease,
            covers: coveredProfileIDs
        ) else {
            return false
        }
        mutation()
        return profileReferenceAdmission.validate(
            lease,
            covers: coveredProfileIDs
        )
    }

    private func profileIDs(
        in snapshot: WindowSessionSnapshot
    ) -> Set<UUID> {
        ProfileReferenceInventory(windowSnapshot: snapshot).profileIDs
    }

    private func completeInitialResolution(
        for windowState: BrowserWindowState
    ) {
        windowState.restorationState.isAwaitingInitialResolution = false
        StartupPerformanceTrace.firstSelectedTabResolved()
        StartupPerformanceTrace.firstTabsClickable()
    }
}

private extension Set where Element == UUID {
    init(optional element: UUID?) {
        self = element.map { [$0] } ?? []
    }
}
