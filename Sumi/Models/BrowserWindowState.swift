//
//  BrowserWindowState.swift
//  Sumi
//
//

import Combine
import Foundation
import SumiDomain
import SwiftUI

struct SplitGroupFocusRequest: Equatable {
    let id = UUID()
    let groupID: UUID
    let preferredMemberID: SplitMemberID?
    let targetSpaceID: UUID
}

/// Durable split selection for this exact browser window. The selected member
/// is a regular-tab or shortcut-pin identity, never a window-local live tab ID.
struct WindowSplitSelection: Codable, Equatable, Hashable, Sendable {
    let groupID: UUID
    let activeMemberID: SplitMemberID
}

/// Split selection awaiting structural restore. Legacy sessions know the
/// group but may not have recorded a stable active member.
struct PendingWindowSplitSelection: Equatable, Sendable {
    let groupID: UUID
    let preferredMemberID: SplitMemberID?
}

/// Provenance for a native shell created to host one WebKit top-level child.
/// The tab identity lets close routing preserve user-added tabs while still
/// closing a shell that contains only its original script-created context.
struct WebKitChildWindowIdentity: Equatable, Sendable {
    let initialTabID: UUID
}

/// Exact, window-local publication boundary for private-browsing inventory.
///
/// Private tabs and spaces never enter the shared model store, so shared tab
/// structure events cannot describe their mutations. Sidebar consumers use
/// these two role-specific streams while mounted and take a fresh snapshot
/// when remounted.
@MainActor
final class BrowserWindowEphemeralInventoryAuthority {
    private let tabInventoryChanged = PassthroughSubject<Void, Never>()
    private let spaceCatalogChanged = PassthroughSubject<Void, Never>()

    var tabInventoryChanges: AnyPublisher<Void, Never> {
        tabInventoryChanged.eraseToAnyPublisher()
    }

    var spaceCatalogChanges: AnyPublisher<Void, Never> {
        spaceCatalogChanged.eraseToAnyPublisher()
    }

    fileprivate func publishTabInventoryChanged() {
        tabInventoryChanged.send()
    }

    fileprivate func publishSpaceCatalogChanged() {
        spaceCatalogChanged.send()
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

    /// Runtime-only presentation, restoration and split-focus authorities.
    /// Durable selection/sidebar/split values remain the session state below.
    let presentationState = WindowPresentationState()
    let restorationState: WindowRestorationState

    /// Present only for a shell created from WebKit's `createWebViewWith`
    /// callback. Ordinary browser windows never infer this role from shape.
    @ObservationIgnored
    var webKitChildWindowIdentity: WebKitChildWindowIdentity?

    /// Once another Tab is intentionally introduced into a WebKit-child
    /// shell, that shell becomes an ordinary browser window and must no longer
    /// disappear when its original script-created page calls `window.close()`.
    func markWebKitChildWindowAdopted(by tabID: UUID) {
        guard webKitChildWindowIdentity?.initialTabID != tabID else { return }
        webKitChildWindowIdentity = nil
    }

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

    /// Durable restoration intent for the floating bar. Physical visibility
    /// remains runtime-only in `presentationState`.
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

    /// Window-local owner for the Zen-style in-sidebar space creation flow.
    let spaceCreationSession = WindowSpaceCreationSessionOwner()

    /// Split group and pane selected in this window. Runtime presentation maps
    /// the durable member identity to this window's exact live tab.
    var splitSelection: WindowSplitSelection?

    /// Window-scoped AppKit coordinator for sidebar context menus.
    @ObservationIgnored
    let sidebarContextMenuController: SidebarContextMenuController

    /// Active tab for each space in this window (spaceId -> tabId)
    var activeTabForSpace: [UUID: UUID] = [:]

    /// Most recently selected non-essential live shortcut for each space in this window.
    var selectedShortcutPinForSpace: [UUID: UUID] = [:]

    /// Window-scoped regular-tab and shortcut selection history.
    var selectionHistory = WindowSelectionHistory()

    /// Sidebar width for this window
    var sidebarWidth: CGFloat = BrowserWindowState.sidebarDefaultWidth

    /// Last non-zero sidebar width so we can restore when toggling visibility
    var savedSidebarWidth: CGFloat = BrowserWindowState.sidebarDefaultWidth

    /// Usable width for sidebar content (excludes padding)
    var sidebarContentWidth: CGFloat = BrowserWindowState.sidebarDefaultWidth - BrowserWindowState.sidebarHorizontalPadding

    /// Whether the sidebar is visible in this window
    var isSidebarVisible: Bool = true

    /// Preserved text draft for the floating bar.
    var floatingBarDraftText: String = ""

    /// Whether the preserved draft targets the current tab on submit
    var floatingBarDraftNavigatesCurrentTab: Bool = false

    /// Window-scoped owner for stacked in-app notifications and their dismiss timers.
    let inAppNotifications = BrowserNotificationCenter()

    /// Window-scoped owner for compositor/native-surface invalidation counters.
    let compositorInvalidation = WindowCompositorInvalidationOwner()

    /// Resolves the AppKit window from the `WindowRegistry` shell map.
    func shellWindow(in registry: WindowRegistry?) -> NSWindow? {
        registry?.appKitWindow(for: self)
    }

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
    @ObservationIgnored
    private(set) var ephemeralSpaces: [Space] = [] {
        didSet {
            guard oldValue.elementsEqual(
                ephemeralSpaces,
                by: { $0 === $1 }
            ) == false else { return }
            publishEphemeralSpaceCatalogChanged()
        }
    }

    /// Ephemeral tabs created in this incognito session
    @ObservationIgnored
    private(set) var ephemeralTabs: [Tab] = [] {
        didSet {
            guard oldValue.elementsEqual(
                ephemeralTabs,
                by: { $0 === $1 }
            ) == false else { return }
            publishEphemeralTabInventoryChanged()
        }
    }

    /// Private inventory is intentionally absent from this window's broad
    /// Observation graph. Consumers opt into the exact role they render.
    @ObservationIgnored
    let ephemeralInventoryAuthority = BrowserWindowEphemeralInventoryAuthority()

    @ObservationIgnored
    private var defersEphemeralInventoryPublication = false

    @ObservationIgnored
    private var deferredEphemeralTabInventoryChange = false

    @ObservationIgnored
    private var deferredEphemeralSpaceCatalogChange = false

    func appendEphemeralSpace(_ space: Space) {
        guard ephemeralSpaces.contains(where: { $0.id == space.id }) == false else { return }
        ephemeralSpaces.append(space)
    }

    func replaceEphemeralSpaces(_ spaces: [Space]) {
        ephemeralSpaces = spaces
    }

    func removeAllEphemeralSpaces() {
        guard ephemeralSpaces.isEmpty == false else { return }
        ephemeralSpaces.removeAll()
    }

    @discardableResult
    func removeEphemeralSpace(ifIdentical space: Space) -> Bool {
        guard let index = ephemeralSpaces.firstIndex(where: { $0 === space })
        else { return false }
        ephemeralSpaces.remove(at: index)
        return true
    }

    func appendEphemeralTab(_ tab: Tab) {
        guard ephemeralTabs.contains(where: { $0.id == tab.id }) == false else { return }
        ephemeralTabs.append(tab)
    }

    func replaceEphemeralTabs(_ tabs: [Tab]) {
        ephemeralTabs = tabs
    }

    @discardableResult
    func removeEphemeralTab(id: UUID) -> Tab? {
        guard let index = ephemeralTabs.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return ephemeralTabs.remove(at: index)
    }

    func containsEphemeralTab(ifIdentical tab: Tab) -> Bool {
        ephemeralTabs.contains { $0 === tab }
    }

    /// Rollback-only removal receipt. A stale transaction must not remove a
    /// newer tab that reused the same UUID after the transaction began.
    @discardableResult
    func removeEphemeralTab(ifIdentical tab: Tab) -> Bool {
        guard let index = ephemeralTabs.firstIndex(where: { $0 === tab }) else {
            return false
        }
        ephemeralTabs.remove(at: index)
        return true
    }

    func removeAllEphemeralTabs() {
        guard ephemeralTabs.isEmpty == false else { return }
        ephemeralTabs.removeAll()
    }

    /// Commits the complete unpublished private-window aggregate before either
    /// inventory stream can re-enter. Every guard runs before the first write;
    /// after mutation begins there is no failing tail and no window write after
    /// deferred publication starts.
    @discardableResult
    func rollbackUnpublishedPrivateAggregate(
        expectedProfile: Profile,
        expectedSpace: Space,
        expectedTab: Tab,
        expectedTabManager: TabManager,
        expectedChildWindowIdentity: WebKitChildWindowIdentity?
    ) -> Bool {
        guard isIncognito,
              tabManager === expectedTabManager,
              ephemeralProfile === expectedProfile,
              currentProfileId == expectedProfile.id,
              currentSpaceId == expectedSpace.id,
              currentTabId == expectedTab.id,
              webKitChildWindowIdentity == expectedChildWindowIdentity,
              ephemeralSpaces.count == 1,
              ephemeralSpaces.first === expectedSpace,
              ephemeralTabs.count == 1,
              ephemeralTabs.first === expectedTab,
              expectedSpace.isEphemeral,
              expectedSpace.profileId == expectedProfile.id,
              expectedTab.spaceId == nil,
              expectedTab.profileId == expectedProfile.id
        else { return false }

        defersEphemeralInventoryPublication = true
        currentTabId = nil
        currentSpaceId = nil
        currentProfileId = nil
        ephemeralProfile = nil
        ephemeralTabs.removeAll()
        ephemeralSpaces.removeAll()
        defersEphemeralInventoryPublication = false
        flushDeferredEphemeralInventoryPublication()
        return true
    }

    private func publishEphemeralTabInventoryChanged() {
        guard defersEphemeralInventoryPublication == false else {
            deferredEphemeralTabInventoryChange = true
            return
        }
        ephemeralInventoryAuthority.publishTabInventoryChanged()
    }

    private func publishEphemeralSpaceCatalogChanged() {
        guard defersEphemeralInventoryPublication == false else {
            deferredEphemeralSpaceCatalogChange = true
            return
        }
        ephemeralInventoryAuthority.publishSpaceCatalogChanged()
    }

    private func flushDeferredEphemeralInventoryPublication() {
        let publishesTabs = deferredEphemeralTabInventoryChange
        let publishesSpaces = deferredEphemeralSpaceCatalogChange
        deferredEphemeralTabInventoryChange = false
        deferredEphemeralSpaceCatalogChange = false
        if publishesTabs {
            ephemeralInventoryAuthority.publishTabInventoryChanged()
        }
        if publishesSpaces {
            ephemeralInventoryAuthority.publishSpaceCatalogChanged()
        }
    }

    init(
        id: UUID = UUID(),
        initialWorkspaceTheme: WorkspaceTheme? = nil,
        awaitsInitialSessionResolution: Bool = false,
        sidebarRecoveryCoordinator: SidebarHostRecoveryHandling = SidebarHostRecoveryCoordinator()
    ) {
        self.id = id
        self.restorationState = WindowRestorationState(
            isAwaitingInitialResolution: awaitsInitialSessionResolution
        )
        self.sidebarInputRecovery = SidebarInputRecoveryOwner(windowID: id)
        var initialThemeState = WindowThemeState()
        if let initialWorkspaceTheme {
            initialThemeState.restore(initialWorkspaceTheme)
        }
        let sidebarInteractionState = SidebarInteractionState()
        let sidebarTransientSessionCoordinator = SidebarTransientSessionCoordinator(
            windowID: id,
            interactionState: sidebarInteractionState,
            sidebarRecoveryCoordinator: sidebarRecoveryCoordinator
        )
        self.sidebarInteractionState = sidebarInteractionState
        self.sidebarTransientSessionCoordinator = sidebarTransientSessionCoordinator
        self.sidebarContextMenuController = SidebarContextMenuController(
            interactionState: sidebarInteractionState,
            transientSessionCoordinator: sidebarTransientSessionCoordinator,
            sidebarRecoveryCoordinator: sidebarRecoveryCoordinator
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

    func resolveSidebarPresentationSource(
        ownerView: NSView? = nil,
        in registry: WindowRegistry?
    ) -> SidebarTransientPresentationSource {
        sidebarTransientSessionCoordinator.consumePresentationSource(
            window: shellWindow(in: registry),
            ownerView: ownerView
        )
    }
}
