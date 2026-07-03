//
//  BrowserWindowState.swift
//  Sumi
//
//

import Foundation
import SwiftUI

struct SplitGroupFocusRequest: Equatable {
    let id = UUID()
    let groupId: UUID
    let targetSpaceId: UUID
}

enum BrowserWindowSelectionHistoryItem: Equatable {
    case regularTab(UUID)
    case shortcutPin(UUID)
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

    /// Suppresses global selection fallbacks until this window's persisted startup selection is resolved.
    var isAwaitingInitialSessionResolution: Bool

    /// Why the floating bar is currently being presented.
    var floatingBarPresentationReason: FloatingBarPresentationReason = .none

    /// Unified owner for all window-local chrome theme state.
    var windowThemeState: WindowThemeState = .init()

    /// Window-scoped interaction state for sidebar menus/drag affordances.
    var sidebarInteractionState: SidebarInteractionState

    /// Window-scoped owner for sidebar-originated transient UI sessions.
    let sidebarTransientSessionCoordinator: SidebarTransientSessionCoordinator

    /// Window-scoped owner for sidebar input-graph recovery generation bumps.
    let sidebarInputRecovery: SidebarInputRecoveryOwner

    /// Window-local sidebar projection state that must not publish through shared models.
    let sidebarFolderProjections = SidebarFolderProjectionCoalescer()

    /// Window-local draft for the Zen-style in-sidebar space creation flow.
    var activeSpaceCreationSession: SpaceCreationSession?

    /// Deferred split focus request used when a sidebar placeholder targets a split in another space.
    var pendingSplitGroupFocusRequest: SplitGroupFocusRequest?

    /// Split group from the persisted window session, resolved after tab data finishes loading.
    @ObservationIgnored
    var pendingSessionSplitGroupId: UUID?

    /// Decode-only migrated split group from older window-session snapshots.
    @ObservationIgnored
    var pendingSessionLegacySplitGroup: SplitGroup?

    /// Window-scoped AppKit coordinator for sidebar context menus.
    @ObservationIgnored
    let sidebarContextMenuController: SidebarContextMenuController

    /// Active tab for each space in this window (spaceId -> tabId)
    var activeTabForSpace: [UUID: UUID] = [:]

    /// Most recently selected non-essential live shortcut for each space in this window.
    var selectedShortcutPinForSpace: [UUID: UUID] = [:]

    /// Window-scoped owner for regular-tab and shortcut selection history.
    let selectionHistory = WindowSelectionHistoryOwner()

    /// Sidebar width for this window
    var sidebarWidth: CGFloat = BrowserWindowState.sidebarDefaultWidth

    /// Last non-zero sidebar width so we can restore when toggling visibility
    var savedSidebarWidth: CGFloat = BrowserWindowState.sidebarDefaultWidth

    /// Usable width for sidebar content (excludes padding)
    var sidebarContentWidth: CGFloat = BrowserWindowState.sidebarDefaultWidth - BrowserWindowState.sidebarHorizontalPadding

    /// Whether the sidebar is visible in this window
    var isSidebarVisible: Bool = true

    /// Whether the downloads popover is visible in this window.
    var isDownloadsPopoverPresented: Bool = false

    /// Whether the floating bar is visible in this window
    var isFloatingBarVisible: Bool = false

    /// Preserved text draft for the floating bar.
    var floatingBarDraftText: String = ""

    /// Whether the preserved draft targets the current tab on submit
    var floatingBarDraftNavigatesCurrentTab: Bool = false

    /// Frame of the URL bar within this window
    var urlBarFrame: CGRect = .zero

    /// Window-scoped owner for the single chrome toast and its dismiss timer.
    let toastPresentation = WindowToastPresentationOwner()

    /// Window-scoped owner for compositor/native-surface invalidation counters.
    let compositorInvalidation = WindowCompositorInvalidationOwner()

    /// Reference to the actual NSWindow for this window state
    var window: NSWindow?

    /// Physical AppKit visibility used by background media optimization.
    var windowVisibilityState: SumiWindowVisibilityState = .unknown

    /// Reference to TabManager for computed properties
    /// Set by BrowserManager during window registration
    weak var tabManager: TabManager?

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

    init(
        id: UUID = UUID(),
        initialWorkspaceTheme: WorkspaceTheme? = nil,
        awaitsInitialSessionResolution: Bool = false
    ) {
        self.id = id
        self.isAwaitingInitialSessionResolution = awaitsInitialSessionResolution
        self.sidebarInputRecovery = SidebarInputRecoveryOwner(windowID: id)
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
        self.sidebarContextMenuController.windowState = self
        self.windowThemeState = initialThemeState
        sidebarTransientSessionCoordinator.scheduleSidebarInputRehydrate = { [weak self] reason in
            self?.sidebarInputRecovery.scheduleRehydrate(reason: reason)
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

    @discardableResult
    func beginSpaceCreationSession(
        source: SidebarTransientPresentationSource,
        defaultProfileID: UUID?
    ) -> SpaceCreationSession {
        if let activeSpaceCreationSession {
            return activeSpaceCreationSession
        }

        let token = source.coordinator?.beginSession(
            kind: .spaceCreation,
            source: source,
            path: "BrowserWindowState.beginSpaceCreationSession"
        )
        let session = SpaceCreationSession(
            previousSpaceID: currentSpaceId,
            source: source,
            transientSessionToken: token,
            profileID: defaultProfileID
        )
        activeSpaceCreationSession = session
        return session
    }

    func finishSpaceCreationSession(
        _ session: SpaceCreationSession,
        reason: String
    ) {
        guard activeSpaceCreationSession === session else { return }
        activeSpaceCreationSession = nil
        session.source.coordinator?.finishSession(
            session.transientSessionToken,
            reason: reason
        )
    }
}
