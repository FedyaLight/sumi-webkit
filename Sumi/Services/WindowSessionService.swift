import Foundation

enum WindowSessionBootstrapOverride {
    static let environmentPathKey = "SUMI_WINDOW_SESSION_OVERRIDE_PATH"

    static func resolvedSnapshot(
        userDefaults: UserDefaults = .standard,
        lastWindowSessionKey: String
    ) -> (snapshot: WindowSessionSnapshot, data: Data)? {
        if let override = overrideSnapshot() {
            return override
        }

        guard let data = userDefaults.data(forKey: lastWindowSessionKey),
              let snapshot = try? JSONDecoder().decode(WindowSessionSnapshot.self, from: data)
        else {
            return nil
        }

        return (snapshot, data)
    }

    private static func overrideSnapshot() -> (snapshot: WindowSessionSnapshot, data: Data)? {
        guard let path = ProcessInfo.processInfo.environment[environmentPathKey],
              !path.isEmpty
        else {
            return nil
        }

        let url = URL(fileURLWithPath: path, isDirectory: false)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WindowSessionSnapshot.self, from: data)
        else {
            return nil
        }

        return (snapshot, data)
    }
}

enum SidebarUITestShortcutDriftOverride {
    static let pinIDEnvironmentKey = "SUMI_SIDEBAR_DRIFT_SHORTCUT_PIN_ID"
    static let urlEnvironmentKey = "SUMI_SIDEBAR_DRIFT_URL"

    @MainActor
    static func applyIfNeeded(
        to windowState: BrowserWindowState,
        delegate: WindowSessionServiceDelegate
    ) {
        guard let pinIDRaw = ProcessInfo.processInfo.environment[pinIDEnvironmentKey],
              let urlRaw = ProcessInfo.processInfo.environment[urlEnvironmentKey],
              let pinID = UUID(uuidString: pinIDRaw),
              let driftURL = URL(string: urlRaw),
              let pin = delegate.tabManager.shortcutPin(by: pinID)
        else {
            return
        }

        let liveTab = delegate.tabManager.shortcutLiveTab(for: pin.id, in: windowState.id)
            ?? delegate.tabManager.activateShortcutPin(
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
protocol WindowSessionServiceDelegate: AnyObject {
    var currentProfile: Profile? { get }
    var tabManager: TabManager { get }
    var windowRegistry: WindowRegistry? { get }
    var splitManager: SplitViewManager { get }
    var shellSelectionService: ShellSelectionService { get }

    func hasValidCurrentSelection(in windowState: BrowserWindowState) -> Bool
    func applyTabSelection(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        updateSpaceFromTab: Bool,
        updateTheme: Bool,
        rememberSelection: Bool,
        persistSelection: Bool
    )
    func showEmptyState(in windowState: BrowserWindowState)
    func sanitizeCommandPaletteState(in windowState: BrowserWindowState)
    func syncShortcutSelectionState(for windowState: BrowserWindowState)
    func commitWorkspaceTheme(_ theme: WorkspaceTheme, for windowState: BrowserWindowState)
    func space(for spaceId: UUID?) -> Space?
    func syncBrowserManagerSidebarCachesFromWindow(_ windowState: BrowserWindowState)
}

@MainActor
final class WindowSessionService {
    private let lastWindowSessionKey: String
    private var lastPersistedWindowSessionData: Data?
    /// The global session JSON is applied to at most one non-incognito window per "cycle"
    /// (after all windows close, `prepareForAllWindowsClosed()` clears this).
    private var didRestoreGlobalWindowSessionThisCycle = false

    init(lastWindowSessionKey: String) {
        self.lastWindowSessionKey = lastWindowSessionKey
    }

    /// Call when the last browser window unregisters so the next window may restore persisted UI again.
    func prepareForAllWindowsClosed() {
        didRestoreGlobalWindowSessionThisCycle = false
        lastPersistedWindowSessionData = nil
    }

    func handleTabManagerDataLoaded(delegate: WindowSessionServiceDelegate) {
        RuntimeDiagnostics.debug(
            "TabManager finished loading persisted data; reconciling window state.",
            category: "WindowSessionService"
        )

        guard let windowRegistry = delegate.windowRegistry else { return }

        for (_, windowState) in windowRegistry.windows {
            if windowState.currentSpaceId == nil
                || delegate.tabManager.spaces.first(where: { $0.id == windowState.currentSpaceId }) == nil
            {
                windowState.currentSpaceId = delegate.tabManager.currentSpace?.id
                    ?? delegate.tabManager.spaces.first?.id
            }

            if let shortcutPinId = windowState.currentShortcutPinId,
               let pin = delegate.tabManager.shortcutPin(by: shortcutPinId)
            {
                let liveTab =
                    delegate.tabManager.activeShortcutTab(for: windowState.id)
                    ?? delegate.tabManager.activateShortcutPin(
                        pin,
                        in: windowState.id,
                        currentSpaceId: windowState.currentSpaceId
                    )
                windowState.currentTabId = liveTab.id
            } else if let currentTabId = windowState.currentTabId,
                      delegate.tabManager.allTabs().contains(where: { $0.id == currentTabId }) == false
            {
                windowState.currentTabId = nil
            }

            SidebarUITestShortcutDriftOverride.applyIfNeeded(
                to: windowState,
                delegate: delegate
            )

            if windowState.currentTabId == nil && !windowState.isShowingEmptyState {
                let restoredTab = delegate.shellSelectionService.preferredTabForWindow(
                    windowState,
                    tabStore: delegate.tabManager.runtimeStore
                )
                if let restoredTab {
                    windowState.currentTabId = restoredTab.id
                } else {
                    delegate.showEmptyState(in: windowState)
                }
            }

            delegate.syncShortcutSelectionState(for: windowState)

            syncWorkspaceThemeAfterSessionRestore(
                windowState,
                delegate: delegate,
                source: "tabManagerDataLoaded"
            )

            windowState.refreshCompositor()
            persistWindowSession(for: windowState, delegate: delegate)
        }

        RuntimeDiagnostics.debug(
            "Window state reconciliation completed after TabManager load.",
            category: "WindowSessionService"
        )
    }

    func setupWindowState(
        _ windowState: BrowserWindowState,
        delegate: WindowSessionServiceDelegate
    ) {
        windowState.tabManager = delegate.tabManager

        let restored = restoreWindowSession(into: windowState, delegate: delegate)
        if !restored {
            windowState.currentProfileId = delegate.currentProfile?.id
            windowState.currentSpaceId = delegate.tabManager.currentSpace?.id
            windowState.currentTabId = delegate.tabManager.currentTab?.id
        }

        finalizeWindowStateRestore(windowState, delegate: delegate, source: "setupWindowState")
    }

    func applyWindowSessionSnapshot(
        _ snapshot: WindowSessionSnapshot,
        to windowState: BrowserWindowState,
        delegate: WindowSessionServiceDelegate
    ) {
        windowState.tabManager = delegate.tabManager
        apply(snapshot: snapshot, to: windowState, delegate: delegate)
        finalizeWindowStateRestore(windowState, delegate: delegate, source: "applyWindowSessionSnapshot")
    }

    private func finalizeWindowStateRestore(
        _ windowState: BrowserWindowState,
        delegate: WindowSessionServiceDelegate,
        source: String
    ) {

        if !windowState.isShowingEmptyState,
           !delegate.hasValidCurrentSelection(in: windowState)
        {
            if let currentSpace = delegate.space(for: windowState.currentSpaceId),
               let preferred = delegate.shellSelectionService.preferredTabForSpace(
                    currentSpace,
                    in: windowState,
                    tabStore: delegate.tabManager.runtimeStore
               )
            {
                delegate.applyTabSelection(
                    preferred,
                    in: windowState,
                    updateSpaceFromTab: false,
                    updateTheme: false,
                    rememberSelection: false,
                    persistSelection: false
                )
            } else if let preferred = delegate.shellSelectionService.preferredTabForWindow(
                windowState,
                tabStore: delegate.tabManager.runtimeStore
            ) {
                delegate.applyTabSelection(
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
           let currentSpace = delegate.space(for: windowState.currentSpaceId),
           let preferred = delegate.shellSelectionService.preferredTabForSpace(
                currentSpace,
                in: windowState,
                tabStore: delegate.tabManager.runtimeStore
           ) {
            delegate.applyTabSelection(
                preferred,
                in: windowState,
                updateSpaceFromTab: false,
                updateTheme: false,
                rememberSelection: false,
                persistSelection: false
            )
        }

        if windowState.currentTabId == nil
            && delegate.shellSelectionService.preferredTabForWindow(
                windowState,
                tabStore: delegate.tabManager.runtimeStore
            ) == nil
        {
            windowState.isShowingEmptyState = true
        }

        delegate.sanitizeCommandPaletteState(in: windowState)
        delegate.syncShortcutSelectionState(for: windowState)

        syncWorkspaceThemeAfterSessionRestore(
            windowState,
            delegate: delegate,
            source: source
        )

        RuntimeDiagnostics.debug(
            "Setup window state \(windowState.id.uuidString) currentTab=\(windowState.currentTabId?.uuidString ?? "none") currentSpace=\(windowState.currentSpaceId?.uuidString ?? "none")",
            category: "WindowSessionService"
        )
        persistWindowSession(for: windowState, delegate: delegate)
    }

    private func syncWorkspaceThemeAfterSessionRestore(
        _ windowState: BrowserWindowState,
        delegate: WindowSessionServiceDelegate,
        source: String
    ) {
        if let spaceId = windowState.currentSpaceId,
           let space = delegate.tabManager.spaces.first(where: { $0.id == spaceId })
        {
            windowState.currentProfileId = space.profileId ?? delegate.currentProfile?.id
            delegate.commitWorkspaceTheme(space.workspaceTheme, for: windowState)
            return
        }

        if let spaceId = windowState.currentSpaceId,
           !delegate.tabManager.hasLoadedInitialData
        {
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
        delegate.commitWorkspaceTheme(.default, for: windowState)
    }

    func setActiveWindowState(
        _ windowState: BrowserWindowState,
        delegate: WindowSessionServiceDelegate
    ) {
        if windowState.currentProfileId == nil {
            windowState.currentProfileId = delegate.currentProfile?.id
        }
        delegate.syncBrowserManagerSidebarCachesFromWindow(windowState)
        persistWindowSession(for: windowState, delegate: delegate)
    }

    func persistWindowSession(
        for windowState: BrowserWindowState,
        delegate: WindowSessionServiceDelegate
    ) {
        guard !windowState.isIncognito else { return }
        let snapshot = makeWindowSessionSnapshot(for: windowState, delegate: delegate)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let previousData =
            lastPersistedWindowSessionData
            ?? UserDefaults.standard.data(forKey: lastWindowSessionKey)
        guard previousData != data else { return }

        UserDefaults.standard.set(data, forKey: lastWindowSessionKey)
        lastPersistedWindowSessionData = data
    }

    @discardableResult
    func restoreWindowSession(
        into windowState: BrowserWindowState,
        delegate: WindowSessionServiceDelegate
    ) -> Bool {
        guard !windowState.isIncognito else { return false }
        if didRestoreGlobalWindowSessionThisCycle {
            return false
        }
        guard let resolvedSnapshot = WindowSessionBootstrapOverride.resolvedSnapshot(
            lastWindowSessionKey: lastWindowSessionKey
        ) else {
            return false
        }
        let data = resolvedSnapshot.data
        let snapshot = resolvedSnapshot.snapshot

        didRestoreGlobalWindowSessionThisCycle = true
        lastPersistedWindowSessionData = data

        apply(snapshot: snapshot, to: windowState, delegate: delegate)
        SidebarUITestDragMarker.recordEvent(
            "startupSessionRestore",
            dragItemID: nil,
            ownerDescription: "WindowSessionService.restoreWindowSession",
            details: "window=\(windowState.id.uuidString) currentSpace=\(snapshot.currentSpaceId?.uuidString ?? "nil") currentProfile=\(snapshot.currentProfileId?.uuidString ?? "nil") currentTab=\(snapshot.currentTabId?.uuidString ?? "nil") emptyState=\(snapshot.isShowingEmptyState) sidebarVisible=\(snapshot.isSidebarVisible) sidebarMenuVisible=\(snapshot.isSidebarMenuVisible)"
        )
        return true
    }

    private func apply(
        snapshot: WindowSessionSnapshot,
        to windowState: BrowserWindowState,
        delegate: WindowSessionServiceDelegate
    ) {
        windowState.currentTabId = snapshot.currentTabId
        windowState.currentSpaceId = snapshot.currentSpaceId
        windowState.currentProfileId = snapshot.currentProfileId
        windowState.currentShortcutPinId = snapshot.activeShortcutPinId
        windowState.currentShortcutPinRole = snapshot.activeShortcutPinRole
        windowState.isShowingEmptyState = snapshot.isShowingEmptyState
        windowState.commandPalettePresentationReason =
            snapshot.isShowingEmptyState
            ? (snapshot.commandPaletteReason ?? .emptySpace)
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
        windowState.isSidebarMenuVisible = snapshot.isSidebarMenuVisible
        windowState.selectedSidebarMenuSection = snapshot.selectedSidebarMenuSection
        windowState.commandPaletteDraftText = snapshot.urlBarDraft.text
        windowState.commandPaletteDraftNavigatesCurrentTab = snapshot.urlBarDraft.navigateCurrentTab
        delegate.splitManager.restoreSession(snapshot.splitSession, for: windowState.id)
        delegate.sanitizeCommandPaletteState(in: windowState)
    }

    func makeWindowSessionSnapshot(
        for windowState: BrowserWindowState,
        delegate: WindowSessionServiceDelegate
    ) -> WindowSessionSnapshot {
        WindowSessionSnapshot(
            currentTabId: windowState.currentTabId,
            currentSpaceId: windowState.currentSpaceId,
            currentProfileId: windowState.currentProfileId,
            activeShortcutPinId: windowState.currentShortcutPinId,
            activeShortcutPinRole: windowState.currentShortcutPinRole,
            isShowingEmptyState: windowState.isShowingEmptyState,
            commandPaletteReason: windowState.commandPalettePresentationReason,
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
            isSidebarMenuVisible: windowState.isSidebarMenuVisible,
            selectedSidebarMenuSection: windowState.selectedSidebarMenuSection,
            urlBarDraft: URLBarDraftState(
                text: windowState.commandPaletteDraftText,
                navigateCurrentTab: windowState.commandPaletteDraftNavigatesCurrentTab
            ),
            splitSession: delegate.splitManager.snapshot(for: windowState.id)
        )
    }
}
