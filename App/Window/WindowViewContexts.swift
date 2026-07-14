import Foundation
import SumiDomain

/// Stable web-content capabilities consumed by the window's website host.
@MainActor
final class WindowWebContentContext {
    let browserContext: WebsiteViewBrowserContext
    let nativeSurfaceRootBuilders: WebsiteNativeSurfaceRootBuilders
    let webViewOwnershipQuery: WebViewOwnershipQuery
    let trackedWebViewAdmission: TrackedWebViewAdmissionService
    let webViewCompositorRuntime: WebViewCompositorRuntime
    let webViewProtectionRuntime: WebViewProtectionRuntime

    init(
        browserContext: WebsiteViewBrowserContext,
        nativeSurfaceRootBuilders: WebsiteNativeSurfaceRootBuilders,
        webViewOwnershipQuery: WebViewOwnershipQuery,
        trackedWebViewAdmission: TrackedWebViewAdmissionService,
        webViewCompositorRuntime: WebViewCompositorRuntime,
        webViewProtectionRuntime: WebViewProtectionRuntime
    ) {
        self.browserContext = browserContext
        self.nativeSurfaceRootBuilders = nativeSurfaceRootBuilders
        self.webViewOwnershipQuery = webViewOwnershipQuery
        self.trackedWebViewAdmission = trackedWebViewAdmission
        self.webViewCompositorRuntime = webViewCompositorRuntime
        self.webViewProtectionRuntime = webViewProtectionRuntime
    }
}

/// Stable split-layout capabilities consumed by `WebsiteView`.
@MainActor
final class WindowSplitContext {
    let updates: SplitWindowUpdateStream
    let query: WindowSplitQuery
    let previews: SplitPreviewSession
    let layout: SplitLayoutService
    let drops: SplitDropService
    let dropTargets: SplitDropTargetService

    init(
        updates: SplitWindowUpdateStream,
        query: WindowSplitQuery,
        previews: SplitPreviewSession,
        layout: SplitLayoutService,
        drops: SplitDropService,
        dropTargets: SplitDropTargetService
    ) {
        self.updates = updates
        self.query = query
        self.previews = previews
        self.layout = layout
        self.drops = drops
        self.dropTargets = dropTargets
    }
}

/// Stable sidebar capabilities shared by docked and collapsed presentations.
@MainActor
final class WindowSidebarContext {
    let browserContext: SidebarBrowserContext
    let inventory: SidebarInventoryProjection
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let regularTabs: any SidebarRegularTabsControlling
    let dragTransactions: SidebarDragTransactionPort
    let updates: SidebarUpdateStreams
    let hostActions: SidebarHostActions
    let hostRecoveryCoordinator: SidebarHostRecoveryHandling
    let updaterService: SumiUpdaterService

    private let currentProfileIDQuery: () -> UUID?
    private let essentialPins: ShortcutPinCollectionStateOwner
    private let hoverSidebarRuntime: HoverSidebarRuntime

    init(
        browserContext: SidebarBrowserContext,
        inventory: SidebarInventoryProjection,
        selection: SidebarWindowSelectionQuery,
        pinProjection: SidebarPinFolderProjection,
        pinCommands: SidebarPinFolderCommands,
        spaceLifecycle: SidebarSpaceLifecycle,
        regularTabs: any SidebarRegularTabsControlling,
        dragTransactions: SidebarDragTransactionPort,
        updates: SidebarUpdateStreams,
        hostActions: SidebarHostActions,
        hostRecoveryCoordinator: SidebarHostRecoveryHandling,
        updaterService: SumiUpdaterService,
        currentProfileID: @escaping () -> UUID?,
        essentialPins: ShortcutPinCollectionStateOwner,
        hoverSidebarRuntime: HoverSidebarRuntime
    ) {
        self.browserContext = browserContext
        self.inventory = inventory
        self.selection = selection
        self.pinProjection = pinProjection
        self.pinCommands = pinCommands
        self.spaceLifecycle = spaceLifecycle
        self.regularTabs = regularTabs
        self.dragTransactions = dragTransactions
        self.updates = updates
        self.hostActions = hostActions
        self.hostRecoveryCoordinator = hostRecoveryCoordinator
        self.updaterService = updaterService
        self.currentProfileIDQuery = currentProfileID
        self.essentialPins = essentialPins
        self.hoverSidebarRuntime = hoverSidebarRuntime
    }

    func currentProfileID() -> UUID? {
        currentProfileIDQuery()
    }

    func essentialPins(profileID: UUID?) -> [ShortcutPin] {
        essentialPins.essentialPins(for: profileID)
    }

    func attachHoverSidebar(
        _ hoverSidebarManager: HoverSidebarManager,
        to windowState: BrowserWindowState
    ) {
        hoverSidebarManager.attach(
            runtime: hoverSidebarRuntime,
            windowState: windowState
        )
    }
}

/// Stable native-modal presentation boundary for one window shell.
@MainActor
final class WindowNativeModalContext {
    private let presentationOwner: BrowserNativeDialogPresentationOwner
    let browsingDataDialogContext: SumiBrowsingDataDialogContext

    init(
        presentationOwner: BrowserNativeDialogPresentationOwner,
        browsingDataDialogContext: SumiBrowsingDataDialogContext
    ) {
        self.presentationOwner = presentationOwner
        self.browsingDataDialogContext = browsingDataDialogContext
    }

    var presentation: BrowserNativeModalPresentation? {
        presentationOwner.currentPresentation
    }

    func isPresented(in windowID: UUID) -> Bool {
        presentationOwner.isNativeModalPresented(in: windowID)
    }

    func bindingDismissed(for windowID: UUID) {
        presentationOwner.nativeModalPresentationBindingDismissed(for: windowID)
    }

    func dismiss() {
        presentationOwner.dismissNativeModalPresentation()
    }
}

/// Stable find-in-page boundary used by both normal and Glance chrome.
@MainActor
final class WindowFindContext {
    let manager: FindManager

    init(manager: FindManager) {
        self.manager = manager
    }

    func currentTabID() -> UUID? {
        manager.currentTab?.id
    }
}

/// Stable theme and window-chrome queries/actions.
@MainActor
final class WindowThemeChromeContext {
    private let spaces: TabSpaceCollectionStateOwner
    private let themeEditor: BrowserWorkspaceThemeEditorOwner
    private let windowTabs: BrowserWindowTabContext

    init(
        spaces: TabSpaceCollectionStateOwner,
        themeEditor: BrowserWorkspaceThemeEditorOwner,
        windowTabs: BrowserWindowTabContext
    ) {
        self.spaces = spaces
        self.themeEditor = themeEditor
        self.windowTabs = windowTabs
    }

    var hasCurrentSpace: Bool {
        spaces.currentSpace != nil
    }

    func showGradientEditor(source: SidebarTransientPresentationSource) {
        themeEditor.showGradientEditor(source: source)
    }

    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        windowTabs.currentTab(for: windowState)
    }

    func workspaceTheme(for spaceID: UUID?) -> WorkspaceTheme? {
        guard let spaceID else { return nil }
        return spaces.space(with: spaceID)?.workspaceTheme
    }
}
