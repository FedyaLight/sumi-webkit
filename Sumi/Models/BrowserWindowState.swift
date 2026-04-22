//
//  BrowserWindowState.swift
//  Sumi
//
//  Created by Jonathan Caudill on 12/09/2024.
//

import SwiftUI
import Foundation

struct SidebarFolderProjectionState: Equatable {
    var projectedChildIDs: [UUID] = []
    var hasActiveProjection: Bool = false

    static let empty = SidebarFolderProjectionState()
}

struct SidebarFolderProjectionStore: Equatable {
    fileprivate var projectionsByFolderID: [UUID: SidebarFolderProjectionState] = [:]

    func projection(for folderID: UUID) -> SidebarFolderProjectionState {
        projectionsByFolderID[folderID] ?? .empty
    }

    mutating func setProjection(
        _ projection: SidebarFolderProjectionState,
        for folderID: UUID
    ) {
        if projection == .empty {
            projectionsByFolderID.removeValue(forKey: folderID)
            return
        }
        projectionsByFolderID[folderID] = projection
    }
}

/// Represents the state of a single browser window, allowing multiple windows
/// to have independent tab selections and UI states while sharing the same tab data.
@MainActor
@Observable
class BrowserWindowState {
    nonisolated static let sidebarMinimumWidth: CGFloat = 240
    nonisolated static let sidebarDefaultWidth: CGFloat = 250
    nonisolated static let sidebarMaximumWidth: CGFloat = 520
    nonisolated static let sidebarHorizontalPadding: CGFloat = 16

    nonisolated static func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        max(sidebarMinimumWidth, min(sidebarMaximumWidth, width))
    }

    nonisolated static func sidebarContentWidth(for sidebarWidth: CGFloat) -> CGFloat {
        max(sidebarWidth - sidebarHorizontalPadding, 0)
    }

    /// Unique identifier for this window instance
    let id: UUID

    /// Currently active tab in this window
    var currentTabId: UUID?

    /// Currently active space in this window
    var currentSpaceId: UUID?

    /// Currently active profile in this window
    var currentProfileId: UUID?

    /// Currently active shortcut pin in this window, if the current tab is a transient pin-backed page
    var currentShortcutPinId: UUID?

    /// Role of the currently active shortcut pin
    var currentShortcutPinRole: ShortcutPinRole?

    /// Whether this window is intentionally showing an empty page state instead of a live tab
    var isShowingEmptyState: Bool = false

    /// Why the floating command palette / URL bar is currently being presented.
    var commandPalettePresentationReason: CommandPalettePresentationReason = .none

    /// Unified owner for all window-local chrome theme state.
    var windowThemeState: WindowThemeState = .init()

    /// Window-scoped interaction state for sidebar menus/drag affordances.
    var sidebarInteractionState: SidebarInteractionState

    /// Window-scoped owner for sidebar-originated transient UI sessions.
    let sidebarTransientSessionCoordinator: SidebarTransientSessionCoordinator

    /// Bumped after sidebar-originated transient UI finishes so the AppKit-backed sidebar input graph remounts.
    var sidebarInputRecoveryGeneration: UInt64 = 0

    /// Window-local sidebar projection state that must not publish through shared models.
    var sidebarFolderProjectionStore: SidebarFolderProjectionStore = .init()

    /// Window-scoped AppKit coordinator for sidebar context menus.
    @ObservationIgnored
    let sidebarContextMenuController: SidebarContextMenuController

    /// Active tab for each space in this window (spaceId -> tabId)
    var activeTabForSpace: [UUID: UUID] = [:]

    /// Most recently selected regular tabs for each space (most recent first)
    var recentRegularTabIdsBySpace: [UUID: [UUID]] = [:]

    /// Most recently selected non-essential live shortcut for each space in this window.
    var selectedShortcutPinForSpace: [UUID: UUID] = [:]

    /// Sidebar width for this window
    var sidebarWidth: CGFloat = BrowserWindowState.sidebarDefaultWidth

    /// Last non-zero sidebar width so we can restore when toggling visibility
    var savedSidebarWidth: CGFloat = BrowserWindowState.sidebarDefaultWidth

    /// Usable width for sidebar content (excludes padding)
    var sidebarContentWidth: CGFloat = BrowserWindowState.sidebarDefaultWidth - BrowserWindowState.sidebarHorizontalPadding

    /// Whether the sidebar is visible in this window
    var isSidebarVisible: Bool = true

    /// Whether the sidebar menu is visible in this window
    var isSidebarMenuVisible: Bool = false

    /// Selected section inside the sidebar utility menu
    var selectedSidebarMenuSection: WindowSidebarMenuSection = .history

    /// Whether the command palette is visible in this window
    var isCommandPaletteVisible: Bool = false

    /// Preserved text draft for the floating URL bar / command palette
    var commandPaletteDraftText: String = ""

    /// Whether the preserved draft targets the current tab on submit
    var commandPaletteDraftNavigatesCurrentTab: Bool = false

    /// Frame of the URL bar within this window
    var urlBarFrame: CGRect = .zero

    /// Profile switch toast payload for this window
    var profileSwitchToast: BrowserManager.ProfileSwitchToast?

    /// Presentation flag for the profile switch toast
    var isShowingProfileSwitchToast: Bool = false
    
    /// Presentation flag for the copy URL toast
    var isShowingCopyURLToast: Bool = false
    
    /// Compositor version counter for this window (incremented when tab ownership changes)
    var compositorVersion: Int = 0
    @ObservationIgnored private var isCompositorRefreshScheduled: Bool = false
    @ObservationIgnored private var isSidebarInputRecoveryScheduled: Bool = false
    @ObservationIgnored private var pendingSidebarInputRecoveryReasons: [String] = []
    @ObservationIgnored private var isSidebarFolderProjectionFlushScheduled: Bool = false
    @ObservationIgnored private var pendingSidebarFolderProjectionUpdates: [UUID: SidebarFolderProjectionState] = [:]

    /// Reference to the actual NSWindow for this window state
    var window: NSWindow?

    /// Reference to TabManager for computed properties
    /// Set by BrowserManager during window registration
    weak var tabManager: TabManager?

    /// Reference to this window's CommandPalette for global shortcuts
    weak var commandPalette: CommandPalette?

    // MARK: - Incognito/Ephemeral State
    
    /// Whether this window is an incognito/private browsing window
    var isIncognito: Bool = false
    
    /// The ephemeral profile associated with this incognito window
    /// Only set when isIncognito is true
    var ephemeralProfile: Profile?
    
    /// Ephemeral spaces created in this incognito session
    var ephemeralSpaces: [Space] = []
    
    /// Ephemeral tabs created in this incognito session
    var ephemeralTabs: [Tab] = []
    
    /// Whether the download warning has been shown in this incognito session
    var hasShownDownloadWarning: Bool = false
    
    init(id: UUID = UUID(), initialWorkspaceTheme: WorkspaceTheme? = nil) {
        self.id = id
        var initialThemeState = WindowThemeState()
        if let initialWorkspaceTheme {
            initialThemeState.restore(initialWorkspaceTheme)
        }
        let sidebarInteractionState = SidebarInteractionState()
        let sidebarTransientSessionCoordinator = SidebarTransientSessionCoordinator(
            windowID: id,
            interactionState: sidebarInteractionState
        )
        self.sidebarInteractionState = sidebarInteractionState
        self.sidebarTransientSessionCoordinator = sidebarTransientSessionCoordinator
        self.sidebarContextMenuController = SidebarContextMenuController(
            interactionState: sidebarInteractionState,
            transientSessionCoordinator: sidebarTransientSessionCoordinator
        )
        self.windowThemeState = initialThemeState
        sidebarTransientSessionCoordinator.scheduleSidebarInputRehydrate = { [weak self] reason in
            self?.scheduleSidebarInputRehydrate(reason: reason)
        }
        sidebarTransientSessionCoordinator.recoverSidebarInteractiveOwners = { [weak self] window, source in
            self?.sidebarContextMenuController.recoverInteractiveOwners(
                in: window,
                source: source
            ) ?? .none
        }
    }

    func resolveSidebarPresentationSource(ownerView: NSView? = nil) -> SidebarTransientPresentationSource {
        sidebarTransientSessionCoordinator.consumePresentationSource(
            window: window,
            ownerView: ownerView
        )
    }

    func scheduleSidebarInputRehydrate(reason: String) {
        pendingSidebarInputRecoveryReasons.append(reason)
        guard !isSidebarInputRecoveryScheduled else { return }

        isSidebarInputRecoveryScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isSidebarInputRecoveryScheduled = false

            let reasons = self.pendingSidebarInputRecoveryReasons
            self.pendingSidebarInputRecoveryReasons.removeAll()
            self.sidebarInputRecoveryGeneration &+= 1

            RuntimeDiagnostics.emit(
                "🧭 Sidebar input recovery generation=\(self.sidebarInputRecoveryGeneration) window=\(self.id.uuidString) reason=\(reasons.joined(separator: ","))"
            )
        }
    }

    func sidebarFolderProjection(for folderID: UUID) -> SidebarFolderProjectionState {
        sidebarFolderProjectionStore.projection(for: folderID)
    }

    func scheduleSidebarFolderProjectionUpdate(
        for folderID: UUID,
        projectedChildIDs: [UUID],
        hasActiveProjection: Bool
    ) {
        let projection = SidebarFolderProjectionState(
            projectedChildIDs: projectedChildIDs,
            hasActiveProjection: hasActiveProjection
        )

        if sidebarFolderProjectionStore.projection(for: folderID) == projection,
           pendingSidebarFolderProjectionUpdates[folderID] == nil
        {
            return
        }

        pendingSidebarFolderProjectionUpdates[folderID] = projection
        guard !isSidebarFolderProjectionFlushScheduled else { return }

        isSidebarFolderProjectionFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isSidebarFolderProjectionFlushScheduled = false

            let updates = self.pendingSidebarFolderProjectionUpdates
            self.pendingSidebarFolderProjectionUpdates.removeAll()

            guard updates.isEmpty == false else { return }

            var nextStore = self.sidebarFolderProjectionStore
            var didChange = false

            for (folderID, projection) in updates {
                if nextStore.projection(for: folderID) == projection {
                    continue
                }
                nextStore.setProjection(projection, for: folderID)
                didChange = true
            }

            guard didChange else { return }
            self.sidebarFolderProjectionStore = nextStore
        }
    }
    
    /// Coalesce compositor invalidations so repeated same-turn calls trigger one UI update.
    func refreshCompositor() {
        guard !isCompositorRefreshScheduled else { return }
        isCompositorRefreshScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isCompositorRefreshScheduled = false
            self.compositorVersion += 1
        }
    }

    func recordRegularTabSelection(_ tabId: UUID, in spaceId: UUID) {
        var history = recentRegularTabIdsBySpace[spaceId] ?? []
        history.removeAll { $0 == tabId }
        history.insert(tabId, at: 0)
        if history.count > 20 {
            history = Array(history.prefix(20))
        }
        recentRegularTabIdsBySpace[spaceId] = history
    }

    func removeFromRegularTabHistory(_ tabId: UUID) {
        for (spaceId, history) in recentRegularTabIdsBySpace {
            recentRegularTabIdsBySpace[spaceId] = history.filter { $0 != tabId }
        }
    }

}
