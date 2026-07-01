import Foundation
import OSLog

enum WindowSessionSnapshotSource: Equatable, Sendable {
    case userDefaultsKey(String)
    case overrideFile(URL)

    var description: String {
        switch self {
        case .userDefaultsKey(let key):
            return "UserDefaults(\(key))"
        case .overrideFile(let url):
            return url.path
        }
    }
}

struct WindowSessionSnapshotLoadFailure: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case readFailed
        case decodeFailed
    }

    var source: WindowSessionSnapshotSource
    var reason: Reason
    var message: String
}

enum WindowSessionSnapshotLoadResult {
    case missing
    case loaded(snapshot: WindowSessionSnapshot, data: Data)
    case failed(WindowSessionSnapshotLoadFailure)
}

enum WindowSessionBootstrapOverride {
    private static let log = Logger.sumi(category: "WindowSessionBootstrap")
    static let environmentPathKey = "SUMI_WINDOW_SESSION_OVERRIDE_PATH"

    static func resolvedSnapshot(
        userDefaults: UserDefaults = .standard,
        lastWindowSessionKey: String
    ) -> (snapshot: WindowSessionSnapshot, data: Data)? {
        guard case .loaded(let snapshot, let data) = resolvedSnapshotResult(
            userDefaults: userDefaults,
            lastWindowSessionKey: lastWindowSessionKey
        ) else { return nil }

        return (snapshot, data)
    }

    static func resolvedSnapshotResult(
        userDefaults: UserDefaults = .standard,
        lastWindowSessionKey: String
    ) -> WindowSessionSnapshotLoadResult {
        if let override = overrideSnapshotResult() {
            return override
        }

        guard let data = userDefaults.data(forKey: lastWindowSessionKey) else {
            return .missing
        }

        return decodeSnapshot(
            data,
            source: .userDefaultsKey(lastWindowSessionKey)
        )
    }

    private static func overrideSnapshotResult() -> WindowSessionSnapshotLoadResult? {
        guard let path = ProcessInfo.processInfo.environment[environmentPathKey],
              !path.isEmpty
        else {
            return nil
        }

        let url = URL(fileURLWithPath: path, isDirectory: false)

        do {
            return decodeSnapshot(
                try Data(contentsOf: url),
                source: .overrideFile(url)
            )
        } catch {
            log.error(
                "Failed to read window session override at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return .failed(
                WindowSessionSnapshotLoadFailure(
                    source: .overrideFile(url),
                    reason: .readFailed,
                    message: error.localizedDescription
                )
            )
        }
    }

    private static func decodeSnapshot(
        _ data: Data,
        source: WindowSessionSnapshotSource
    ) -> WindowSessionSnapshotLoadResult {
        do {
            return .loaded(
                snapshot: try JSONDecoder().decode(WindowSessionSnapshot.self, from: data),
                data: data
            )
        } catch {
            log.error(
                "Failed to decode window session from \(source.description, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return .failed(
                WindowSessionSnapshotLoadFailure(
                    source: source,
                    reason: .decodeFailed,
                    message: error.localizedDescription
                )
            )
        }
    }
}

enum SidebarUITestShortcutDriftOverride {
    static let pinIDEnvironmentKey = "SUMI_SIDEBAR_DRIFT_SHORTCUT_PIN_ID"
    static let urlEnvironmentKey = "SUMI_SIDEBAR_DRIFT_URL"

    @MainActor
    static func applyIfNeeded(
        to windowState: BrowserWindowState,
        runtime: WindowSessionRuntime
    ) {
        guard let pinIDRaw = ProcessInfo.processInfo.environment[pinIDEnvironmentKey],
              let urlRaw = ProcessInfo.processInfo.environment[urlEnvironmentKey],
              let pinID = UUID(uuidString: pinIDRaw),
              let driftURL = URL(string: urlRaw),
              let pin = runtime.tabManager.shortcutPin(by: pinID)
        else {
            return
        }

        let liveTab = runtime.tabManager.shortcutLiveTab(for: pin.id, in: windowState.id)
            ?? runtime.tabManager.activateShortcutPin(
                pin,
                in: windowState.id,
                currentSpaceId: pin.spaceId ?? windowState.currentSpaceId
            )
        liveTab.url = driftURL

        if let spaceId = pin.spaceId {
            windowState.currentSpaceId = spaceId
            windowState.selectedShortcutPinForSpace[spaceId] = pin.id
        }
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role
    }
}

@MainActor
struct WindowSessionRuntime {
    let tabManager: TabManager
    let splitManager: SplitViewManager
    let glanceManager: GlanceManager
    let shellSelectionService: ShellSelectionService

    private let currentProfileProvider: @MainActor () -> Profile?
    private let windowRegistryProvider: @MainActor () -> WindowRegistry?
    private let hasValidCurrentSelectionHandler: @MainActor (BrowserWindowState) -> Bool
    private let applyTabSelectionHandler: @MainActor (
        Tab,
        BrowserWindowState,
        Bool,
        Bool,
        Bool,
        Bool
    ) -> Void
    private let showEmptyStateHandler: @MainActor (BrowserWindowState) -> Void
    private let sanitizeFloatingBarStateHandler: @MainActor (BrowserWindowState) -> Void
    private let syncShortcutSelectionStateHandler: @MainActor (BrowserWindowState) -> Void
    private let commitWorkspaceThemeHandler: @MainActor (WorkspaceTheme, BrowserWindowState) -> Void
    private let spaceProvider: @MainActor (UUID?) -> Space?
    private let syncSidebarPresentationStateHandler: @MainActor (BrowserWindowState) -> Void
    private let focusSplitGroupHandler: @MainActor (SplitGroup, BrowserWindowState) -> Void

    init(
        currentProfile: @escaping @MainActor () -> Profile?,
        tabManager: TabManager,
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        splitManager: SplitViewManager,
        glanceManager: GlanceManager,
        shellSelectionService: ShellSelectionService,
        hasValidCurrentSelection: @escaping @MainActor (BrowserWindowState) -> Bool,
        applyTabSelection: @escaping @MainActor (
            Tab,
            BrowserWindowState,
            Bool,
            Bool,
            Bool,
            Bool
        ) -> Void,
        showEmptyState: @escaping @MainActor (BrowserWindowState) -> Void,
        sanitizeFloatingBarState: @escaping @MainActor (BrowserWindowState) -> Void,
        syncShortcutSelectionState: @escaping @MainActor (BrowserWindowState) -> Void,
        commitWorkspaceTheme: @escaping @MainActor (WorkspaceTheme, BrowserWindowState) -> Void,
        space: @escaping @MainActor (UUID?) -> Space?,
        syncSidebarPresentationState: @escaping @MainActor (BrowserWindowState) -> Void,
        focusSplitGroup: @escaping @MainActor (SplitGroup, BrowserWindowState) -> Void
    ) {
        self.currentProfileProvider = currentProfile
        self.tabManager = tabManager
        self.windowRegistryProvider = windowRegistry
        self.splitManager = splitManager
        self.glanceManager = glanceManager
        self.shellSelectionService = shellSelectionService
        self.hasValidCurrentSelectionHandler = hasValidCurrentSelection
        self.applyTabSelectionHandler = applyTabSelection
        self.showEmptyStateHandler = showEmptyState
        self.sanitizeFloatingBarStateHandler = sanitizeFloatingBarState
        self.syncShortcutSelectionStateHandler = syncShortcutSelectionState
        self.commitWorkspaceThemeHandler = commitWorkspaceTheme
        self.spaceProvider = space
        self.syncSidebarPresentationStateHandler = syncSidebarPresentationState
        self.focusSplitGroupHandler = focusSplitGroup
    }

    var currentProfile: Profile? {
        currentProfileProvider()
    }

    var windowRegistry: WindowRegistry? {
        windowRegistryProvider()
    }

    func hasValidCurrentSelection(in windowState: BrowserWindowState) -> Bool {
        hasValidCurrentSelectionHandler(windowState)
    }

    func applyTabSelection(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        updateSpaceFromTab: Bool,
        updateTheme: Bool,
        rememberSelection: Bool,
        persistSelection: Bool
    ) {
        applyTabSelectionHandler(
            tab,
            windowState,
            updateSpaceFromTab,
            updateTheme,
            rememberSelection,
            persistSelection
        )
    }

    func showEmptyState(in windowState: BrowserWindowState) {
        showEmptyStateHandler(windowState)
    }

    func sanitizeFloatingBarState(in windowState: BrowserWindowState) {
        sanitizeFloatingBarStateHandler(windowState)
    }

    func syncShortcutSelectionState(for windowState: BrowserWindowState) {
        syncShortcutSelectionStateHandler(windowState)
    }

    func commitWorkspaceTheme(_ theme: WorkspaceTheme, for windowState: BrowserWindowState) {
        commitWorkspaceThemeHandler(theme, windowState)
    }

    func space(for spaceId: UUID?) -> Space? {
        spaceProvider(spaceId)
    }

    func syncSidebarPresentationState(from windowState: BrowserWindowState) {
        syncSidebarPresentationStateHandler(windowState)
    }

    func focusSplitGroup(_ group: SplitGroup, in windowState: BrowserWindowState) {
        focusSplitGroupHandler(group, windowState)
    }
}

@MainActor
private enum WindowSessionSnapshotApplier {
    static func apply(
        _ snapshot: WindowSessionSnapshot,
        to windowState: BrowserWindowState,
        runtime: WindowSessionRuntime
    ) {
        windowState.currentTabId = snapshot.currentTabId
        windowState.currentSpaceId = snapshot.currentSpaceId
        windowState.currentProfileId = snapshot.currentProfileId
        windowState.currentShortcutPinId = snapshot.activeShortcutPinId
        windowState.currentShortcutPinRole = snapshot.activeShortcutPinRole
        windowState.isShowingEmptyState = snapshot.isShowingEmptyState
        windowState.floatingBarPresentationReason =
            snapshot.isShowingEmptyState
            ? (snapshot.floatingBarReason ?? .emptySpace)
            : .none
        windowState.activeTabForSpace = Dictionary(
            uniqueKeysWithValues: snapshot.activeTabsBySpace.map { ($0.spaceId, $0.tabId) }
        )
        windowState.selectedShortcutPinForSpace = Dictionary(
            uniqueKeysWithValues: (snapshot.activeShortcutsBySpace ?? []).map { ($0.spaceId, $0.shortcutPinId) }
        )
        let restoredSidebarWidth = BrowserWindowState.clampedSidebarWidth(CGFloat(snapshot.sidebarWidth))
        let restoredSavedSidebarWidth = BrowserWindowState.clampedSidebarWidth(CGFloat(snapshot.savedSidebarWidth))
        windowState.sidebarWidth = restoredSidebarWidth
        windowState.savedSidebarWidth = restoredSavedSidebarWidth
        windowState.sidebarContentWidth = BrowserWindowState.sidebarContentWidth(for: restoredSidebarWidth)
        windowState.isSidebarVisible = snapshot.isSidebarVisible
        windowState.isDownloadsPopoverPresented = false
        windowState.floatingBarDraftText = snapshot.floatingBarDraft.text
        windowState.floatingBarDraftNavigatesCurrentTab = snapshot.floatingBarDraft.navigateCurrentTab
        if snapshot.activeSplitGroupId == nil,
           let legacyGroup = snapshot.legacySplitSessionForMigration?.makeSplitGroup(spaceId: snapshot.currentSpaceId) {
            windowState.pendingSessionLegacySplitGroup = legacyGroup
            windowState.pendingSessionSplitGroupId = legacyGroup.id
        } else {
            windowState.pendingSessionLegacySplitGroup = nil
            windowState.pendingSessionSplitGroupId = snapshot.activeSplitGroupId
        }
        runtime.glanceManager.restoreSession(snapshot.glanceSession, in: windowState)
        runtime.sanitizeFloatingBarState(in: windowState)
    }
}

@MainActor
final class WindowSessionService {
    private static let log = Logger.sumi(category: "WindowSessionService")

    private let lastWindowSessionKey: String
    private var lastPersistedWindowSessionData: Data?
    private var pendingPersistTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingPersistStates: [UUID: BrowserWindowState] = [:]
    /// The global session JSON is applied to at most one non-incognito window per "cycle"
    /// (after all windows close, `prepareForAllWindowsClosed()` clears this).
    private var didRestoreGlobalWindowSessionThisCycle = false
    private(set) var lastRestoreFailure: WindowSessionSnapshotLoadFailure?
    private(set) var lastPersistFailure: String?

    init(lastWindowSessionKey: String) {
        self.lastWindowSessionKey = lastWindowSessionKey
    }

    isolated deinit {
        pendingPersistTasks.values.forEach { $0.cancel() }
    }

    /// Call when the last browser window unregisters so the next window may restore persisted UI again.
    func prepareForAllWindowsClosed() {
        didRestoreGlobalWindowSessionThisCycle = false
        lastPersistedWindowSessionData = nil
    }

    func handleTabManagerDataLoaded(runtime: WindowSessionRuntime) {
        let startupTrace = StartupPerformanceTrace.sessionRestoreStarted()
        defer {
            StartupPerformanceTrace.sessionRestoreFinished(startupTrace)
        }

        RuntimeDiagnostics.debug(
            "TabManager finished loading persisted data; reconciling window state.",
            category: "WindowSessionService"
        )

        guard let windowRegistry = runtime.windowRegistry else { return }

        for (_, windowState) in windowRegistry.windows {
            if windowState.currentSpaceId == nil
                || runtime.tabManager.spaces.first(where: { $0.id == windowState.currentSpaceId }) == nil {
                windowState.currentSpaceId = resolvedFallbackSpaceId(
                    for: windowState,
                    runtime: runtime
                )
            }

            if let shortcutPinId = windowState.currentShortcutPinId,
               let pin = runtime.tabManager.shortcutPin(by: shortcutPinId) {
                materializeShortcutSelection(pin, in: windowState, runtime: runtime)
            } else if materializeRememberedSpaceShortcut(in: windowState, runtime: runtime) {
                // Restored from the per-space launcher selection snapshot.
            } else if let currentTabId = windowState.currentTabId,
                      runtime.tabManager.allTabs().contains(where: { $0.id == currentTabId }) == false {
                windowState.currentTabId = nil
            }

            SidebarUITestShortcutDriftOverride.applyIfNeeded(
                to: windowState,
                runtime: runtime
            )

            if windowState.currentTabId == nil && !windowState.isShowingEmptyState {
                let restoredTab = runtime.shellSelectionService.preferredTabForWindow(
                    windowState,
                    tabStore: runtime.tabManager.runtimeStore
                )
                if let restoredTab {
                    windowState.currentTabId = restoredTab.id
                } else {
                    runtime.showEmptyState(in: windowState)
                }
            }

            runtime.syncShortcutSelectionState(for: windowState)
            restorePendingSplitGroupSelectionIfNeeded(in: windowState, runtime: runtime)
            runtime.glanceManager.restorePendingSessionIfPossible(in: windowState)

            syncWorkspaceThemeAfterSessionRestore(
                windowState,
                runtime: runtime,
                source: "tabManagerDataLoaded"
            )

            windowState.isAwaitingInitialSessionResolution = false
            StartupPerformanceTrace.firstSelectedTabResolved()
            StartupPerformanceTrace.firstTabsClickable()
            windowState.refreshCompositor()
            persistWindowSession(for: windowState, runtime: runtime)
        }

        RuntimeDiagnostics.debug(
            "Window state reconciliation completed after TabManager load.",
            category: "WindowSessionService"
        )
    }

    func setupWindowState(
        _ windowState: BrowserWindowState,
        runtime: WindowSessionRuntime
    ) {
        windowState.tabManager = runtime.tabManager

        let restored = restoreWindowSession(into: windowState, runtime: runtime)
        if !restored {
            let activeProfileId = runtime.currentProfile?.id
            windowState.currentProfileId = activeProfileId
            windowState.currentSpaceId = resolvedFallbackSpaceId(
                for: windowState,
                runtime: runtime,
                seededProfileId: activeProfileId
            )
        }

        if restored && !runtime.tabManager.hasLoadedInitialData {
            syncWorkspaceThemeAfterSessionRestore(
                windowState,
                runtime: runtime,
                source: "setupWindowState.preInitialTabManagerLoad"
            )
            return
        }

        finalizeWindowStateRestore(windowState, runtime: runtime, source: "setupWindowState")
    }

    private func resolvedFallbackSpaceId(
        for windowState: BrowserWindowState,
        runtime: WindowSessionRuntime,
        seededProfileId: UUID? = nil
    ) -> UUID? {
        if let windowSpaceId = windowState.currentSpaceId,
           runtime.tabManager.spaces.contains(where: { $0.id == windowSpaceId }) {
            return windowSpaceId
        }

        if let tabSpaceId = currentTabSpaceId(for: windowState, runtime: runtime) {
            return tabSpaceId
        }

        if let profileId = windowState.currentProfileId,
           let profileSpaceId = firstSpaceId(for: profileId, runtime: runtime) {
            return profileSpaceId
        }
        windowState.currentProfileId = nil

        if let profileId = seededProfileId,
           let profileSpaceId = firstSpaceId(for: profileId, runtime: runtime) {
            return profileSpaceId
        }

        return nil
    }

    private func currentTabSpaceId(
        for windowState: BrowserWindowState,
        runtime: WindowSessionRuntime
    ) -> UUID? {
        guard let currentTabId = windowState.currentTabId,
              let spaceId = runtime.tabManager.tab(for: currentTabId)?.spaceId,
              runtime.tabManager.spaces.contains(where: { $0.id == spaceId })
        else {
            return nil
        }

        return spaceId
    }

    private func firstSpaceId(
        for profileId: UUID,
        runtime: WindowSessionRuntime
    ) -> UUID? {
        runtime.tabManager.spaces.first(where: { $0.profileId == profileId })?.id
    }

    func applyWindowSessionSnapshot(
        _ snapshot: WindowSessionSnapshot,
        to windowState: BrowserWindowState,
        runtime: WindowSessionRuntime
    ) {
        windowState.tabManager = runtime.tabManager
        WindowSessionSnapshotApplier.apply(snapshot, to: windowState, runtime: runtime)
        finalizeWindowStateRestore(windowState, runtime: runtime, source: "applyWindowSessionSnapshot")
    }

    private func finalizeWindowStateRestore(
        _ windowState: BrowserWindowState,
        runtime: WindowSessionRuntime,
        source: String
    ) {
        materializeShortcutSelectionIfNeeded(in: windowState, runtime: runtime)
        restorePendingSplitGroupSelectionIfNeeded(in: windowState, runtime: runtime)
        runtime.glanceManager.restorePendingSessionIfPossible(in: windowState)

        if !windowState.isShowingEmptyState,
           !runtime.hasValidCurrentSelection(in: windowState) {
            if let currentSpace = runtime.space(for: windowState.currentSpaceId),
               let preferred = runtime.shellSelectionService.preferredTabForSpace(
                    currentSpace,
                    in: windowState,
                    tabStore: runtime.tabManager.runtimeStore
               ) {
                runtime.applyTabSelection(
                    preferred,
                    in: windowState,
                    updateSpaceFromTab: false,
                    updateTheme: false,
                    rememberSelection: false,
                    persistSelection: false
                )
            } else if let preferred = runtime.shellSelectionService.preferredTabForWindow(
                windowState,
                tabStore: runtime.tabManager.runtimeStore
            ) {
                runtime.applyTabSelection(
                    preferred,
                    in: windowState,
                    updateSpaceFromTab: false,
                    updateTheme: false,
                    rememberSelection: false,
                    persistSelection: false
                )
            }
        }

        if windowState.isShowingEmptyState,
           let currentSpace = runtime.space(for: windowState.currentSpaceId),
           let preferred = runtime.shellSelectionService.preferredTabForSpace(
                currentSpace,
                in: windowState,
                tabStore: runtime.tabManager.runtimeStore
           ) {
            runtime.applyTabSelection(
                preferred,
                in: windowState,
                updateSpaceFromTab: false,
                updateTheme: false,
                rememberSelection: false,
                persistSelection: false
            )
        }

        if windowState.currentTabId == nil
            && runtime.shellSelectionService.preferredTabForWindow(
                windowState,
                tabStore: runtime.tabManager.runtimeStore
            ) == nil {
            windowState.isShowingEmptyState = true
        }

        runtime.sanitizeFloatingBarState(in: windowState)
        runtime.syncShortcutSelectionState(for: windowState)
        restorePendingSplitGroupSelectionIfNeeded(in: windowState, runtime: runtime)

        syncWorkspaceThemeAfterSessionRestore(
            windowState,
            runtime: runtime,
            source: source
        )

        windowState.isAwaitingInitialSessionResolution = false
        StartupPerformanceTrace.firstSelectedTabResolved()
        StartupPerformanceTrace.firstTabsClickable()
        RuntimeDiagnostics.debug(
            "Setup window state \(windowState.id.uuidString) currentTab=\(windowState.currentTabId?.uuidString ?? "none") currentSpace=\(windowState.currentSpaceId?.uuidString ?? "none")",
            category: "WindowSessionService"
        )
        persistWindowSession(for: windowState, runtime: runtime)
    }

    @discardableResult
    private func materializeShortcutSelectionIfNeeded(
        in windowState: BrowserWindowState,
        runtime: WindowSessionRuntime
    ) -> Bool {
        if let shortcutPinId = windowState.currentShortcutPinId,
           let pin = runtime.tabManager.shortcutPin(by: shortcutPinId) {
            materializeShortcutSelection(pin, in: windowState, runtime: runtime)
            return true
        }

        return materializeRememberedSpaceShortcut(in: windowState, runtime: runtime)
    }

    @discardableResult
    private func materializeRememberedSpaceShortcut(
        in windowState: BrowserWindowState,
        runtime: WindowSessionRuntime
    ) -> Bool {
        guard let currentSpaceId = windowState.currentSpaceId,
              let shortcutPinId = windowState.selectedShortcutPinForSpace[currentSpaceId],
              let pin = runtime.tabManager.shortcutPin(by: shortcutPinId)
        else {
            return false
        }

        materializeShortcutSelection(pin, in: windowState, runtime: runtime)
        return true
    }

    private func materializeShortcutSelection(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        runtime: WindowSessionRuntime
    ) {
        let liveTab = runtime.tabManager.shortcutLiveTab(for: pin.id, in: windowState.id)
            ?? runtime.tabManager.activateShortcutPin(
                pin,
                in: windowState.id,
                currentSpaceId: windowState.currentSpaceId
            )

        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = pin.role
        windowState.isShowingEmptyState = false

        if let spaceId = pin.spaceId {
            windowState.currentSpaceId = spaceId
            windowState.selectedShortcutPinForSpace[spaceId] = pin.id
        }
    }

    private func syncWorkspaceThemeAfterSessionRestore(
        _ windowState: BrowserWindowState,
        runtime: WindowSessionRuntime,
        source: String
    ) {
        if let spaceId = windowState.currentSpaceId,
           let space = runtime.tabManager.spaces.first(where: { $0.id == spaceId }) {
            windowState.currentProfileId = space.profileId
            runtime.commitWorkspaceTheme(space.workspaceTheme, for: windowState)
            return
        }

        if let spaceId = windowState.currentSpaceId,
           !runtime.tabManager.hasLoadedInitialData {
            RuntimeDiagnostics.debug(
                "Preserving bootstrap workspace theme for window \(windowState.id.uuidString) while waiting for initial TabManager data; source=\(source) currentSpace=\(spaceId.uuidString)",
                category: "WindowSessionService"
            )
            return
        }

        if let spaceId = windowState.currentSpaceId {
            RuntimeDiagnostics.debug(
                "Applying default workspace theme fallback for window \(windowState.id.uuidString); source=\(source) missingSpace=\(spaceId.uuidString)",
                category: "WindowSessionService"
            )
        }
        runtime.commitWorkspaceTheme(.default, for: windowState)
    }

    func setActiveWindowState(
        _ windowState: BrowserWindowState,
        runtime: WindowSessionRuntime
    ) {
        runtime.syncSidebarPresentationState(from: windowState)
        persistWindowSession(for: windowState, runtime: runtime)
    }

    func persistWindowSession(
        for windowState: BrowserWindowState,
        runtime: WindowSessionRuntime
    ) {
        cancelPendingPersistence(for: windowState.id)
        guard !windowState.isIncognito else { return }
        let snapshot = makeWindowSessionSnapshot(for: windowState, runtime: runtime)
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
            lastPersistFailure = nil
        } catch {
            lastPersistFailure = error.localizedDescription
            Self.log.error(
                "Failed to encode window session snapshot: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        let previousData =
            lastPersistedWindowSessionData
            ?? UserDefaults.standard.data(forKey: lastWindowSessionKey)
        guard previousData != data else { return }

        UserDefaults.standard.set(data, forKey: lastWindowSessionKey)
        lastPersistedWindowSessionData = data
    }

    func schedulePersistWindowSession(
        for windowState: BrowserWindowState,
        delayNanoseconds: UInt64 = 450_000_000,
        persist: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        guard !windowState.isIncognito else { return }

        let windowId = windowState.id
        cancelPendingPersistence(for: windowId)
        pendingPersistStates[windowId] = windowState
        pendingPersistTasks[windowId] = Task { @MainActor [weak self, weak windowState] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled,
                  let self,
                  let windowState
            else {
                return
            }

            self.pendingPersistTasks.removeValue(forKey: windowId)
            self.pendingPersistStates.removeValue(forKey: windowId)
            persist(windowState)
        }
    }

    func flushPendingWindowSessionPersistence(
        persist: @MainActor (BrowserWindowState) -> Void
    ) {
        guard !pendingPersistStates.isEmpty else { return }

        let pendingStates = pendingPersistStates.values.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        cancelPendingWindowSessionPersistence()

        let signpostState = PerformanceTrace.beginInterval("WindowSession.flushPendingPersistence")
        defer {
            PerformanceTrace.endInterval("WindowSession.flushPendingPersistence", signpostState)
        }

        for windowState in pendingStates {
            persist(windowState)
        }
    }

    func cancelPendingWindowSessionPersistence() {
        pendingPersistTasks.values.forEach { $0.cancel() }
        pendingPersistTasks.removeAll()
        pendingPersistStates.removeAll()
    }

    private func cancelPendingPersistence(for windowId: UUID) {
        pendingPersistTasks[windowId]?.cancel()
        pendingPersistTasks.removeValue(forKey: windowId)
        pendingPersistStates.removeValue(forKey: windowId)
    }

    @discardableResult
    func restoreWindowSession(
        into windowState: BrowserWindowState,
        runtime: WindowSessionRuntime
    ) -> Bool {
        guard !windowState.isIncognito else { return false }
        if didRestoreGlobalWindowSessionThisCycle {
            return false
        }

        switch WindowSessionBootstrapOverride.resolvedSnapshotResult(lastWindowSessionKey: lastWindowSessionKey) {
        case .missing:
            lastRestoreFailure = nil
            return false
        case .failed(let failure):
            lastRestoreFailure = failure
            Self.log.error(
                "Failed to restore window session from \(failure.source.description, privacy: .public): \(failure.message, privacy: .public)"
            )
            return false
        case .loaded(let snapshot, let data):
            didRestoreGlobalWindowSessionThisCycle = true
            lastPersistedWindowSessionData = data

            WindowSessionSnapshotApplier.apply(snapshot, to: windowState, runtime: runtime)
            return true
        }
    }

    private func restorePendingSplitGroupSelectionIfNeeded(
        in windowState: BrowserWindowState,
        runtime: WindowSessionRuntime
    ) {
        restorePendingLegacySplitGroupIfNeeded(in: windowState, runtime: runtime)
        guard let groupId = windowState.pendingSessionSplitGroupId else { return }
        guard let group = runtime.tabManager.splitGroup(with: groupId) else {
            if runtime.tabManager.hasLoadedInitialData {
                windowState.pendingSessionSplitGroupId = nil
            }
            return
        }

        windowState.pendingSessionSplitGroupId = nil
        runtime.focusSplitGroup(group, in: windowState)
    }

    private func restorePendingLegacySplitGroupIfNeeded(
        in windowState: BrowserWindowState,
        runtime: WindowSessionRuntime
    ) {
        guard let group = windowState.pendingSessionLegacySplitGroup else { return }
        guard runtime.tabManager.hasLoadedInitialData else { return }

        guard group.tabIds.allSatisfy({ runtime.tabManager.tab(for: $0) != nil }) else {
            windowState.pendingSessionLegacySplitGroup = nil
            if windowState.pendingSessionSplitGroupId == group.id {
                windowState.pendingSessionSplitGroupId = nil
            }
            return
        }

        runtime.tabManager.upsertSplitGroup(group)
        windowState.pendingSessionLegacySplitGroup = nil
    }

    func makeWindowSessionSnapshot(
        for windowState: BrowserWindowState,
        runtime: WindowSessionRuntime
    ) -> WindowSessionSnapshot {
        WindowSessionSnapshot(
            currentTabId: windowState.currentTabId,
            currentSpaceId: windowState.currentSpaceId,
            currentProfileId: windowState.currentProfileId,
            activeShortcutPinId: windowState.currentShortcutPinId,
            activeShortcutPinRole: windowState.currentShortcutPinRole,
            isShowingEmptyState: windowState.isShowingEmptyState,
            floatingBarReason: windowState.floatingBarPresentationReason,
            activeTabsBySpace: windowState.activeTabForSpace.map {
                SpaceTabSelectionSnapshot(spaceId: $0.key, tabId: $0.value)
            },
            activeShortcutsBySpace: windowState.selectedShortcutPinForSpace.map {
                SpaceShortcutSelectionSnapshot(spaceId: $0.key, shortcutPinId: $0.value)
            },
            sidebarWidth: Double(windowState.sidebarWidth),
            savedSidebarWidth: Double(windowState.savedSidebarWidth),
            sidebarContentWidth: Double(windowState.sidebarContentWidth),
            isSidebarVisible: windowState.isSidebarVisible,
            floatingBarDraft: FloatingBarDraftState(
                text: windowState.floatingBarDraftText,
                navigateCurrentTab: windowState.floatingBarDraftNavigatesCurrentTab
            ),
            activeSplitGroupId: runtime.splitManager.splitGroup(for: windowState.id)?.id,
            glanceSession: runtime.glanceManager.makeSessionSnapshot(for: windowState)
        )
    }
}
