import Foundation

/// Window-level browser boundary handed to `WindowView`: typed feature
/// contexts plus narrow closures over browser state, so the window shell never
/// sees `BrowserManager` directly.
@MainActor
final class WindowViewBrowserContext {
    let splitUpdates: SplitWindowUpdateStream
    let splitQuery: WindowSplitQuery
    let splitPreviews: SplitPreviewSession
    let splitLayout: SplitLayoutService
    let splitDrops: SplitDropService
    let splitDropTargets: SplitDropTargetService
    let webViewOwnershipQuery: WebViewOwnershipQuery
    let trackedWebViewAdmission: TrackedWebViewAdmissionService
    let webViewCompositorRuntime: WebViewCompositorRuntime
    let webViewProtectionRuntime: WebViewProtectionRuntime
    let findManager: FindManager
    let floatingBarBrowserContext: FloatingBarBrowserContext
    let sidebarBrowserContext: SidebarBrowserContext
    let sidebarInventory: SidebarInventoryProjection
    let sidebarSelection: SidebarWindowSelectionQuery
    let sidebarPinProjection: SidebarPinFolderProjection
    let sidebarPinCommands: SidebarPinFolderCommands
    let sidebarSpaceLifecycle: SidebarSpaceLifecycle
    let sidebarRegularTabs: any SidebarRegularTabsControlling
    let sidebarDragTransactions: SidebarDragTransactionPort
    let sidebarUpdates: SidebarUpdateStreams
    let sidebarHostActions: SidebarHostActions

    private let _nativeModalPresentation: () -> BrowserNativeModalPresentation?
    private let _browsingDataDialogContext: () -> SumiBrowsingDataDialogContext
    private let _hasCurrentSpace: () -> Bool
    private let _showGradientEditor: (SidebarTransientPresentationSource) -> Void
    private let _currentProfileID: () -> UUID?
    private let _essentialPins: (UUID?) -> [ShortcutPin]
    private let _attachHoverSidebarManager: (HoverSidebarManager, BrowserWindowState) -> Void
    private let _websiteViewBrowserContext: () -> WebsiteViewBrowserContext
    private let _websiteNativeSurfaceRootBuilders: () -> WebsiteNativeSurfaceRootBuilders
    private let _currentTab: (BrowserWindowState) -> Tab?
    private let _workspaceTheme: (UUID?) -> WorkspaceTheme?
    private let _isNativeModalPresented: (UUID) -> Bool
    private let _nativeModalPresentationBindingDismissed: (UUID) -> Void
    private let _dismissNativeModalPresentation: () -> Void
    private let _findCurrentTabId: () -> UUID?
    let sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling

    init(
        splitUpdates: SplitWindowUpdateStream,
        splitQuery: WindowSplitQuery,
        splitPreviews: SplitPreviewSession,
        splitLayout: SplitLayoutService,
        splitDrops: SplitDropService,
        splitDropTargets: SplitDropTargetService,
        webViewOwnershipQuery: WebViewOwnershipQuery,
        trackedWebViewAdmission: TrackedWebViewAdmissionService,
        webViewCompositorRuntime: WebViewCompositorRuntime,
        webViewProtectionRuntime: WebViewProtectionRuntime,
        findManager: FindManager,
        floatingBarBrowserContext: FloatingBarBrowserContext,
        sidebarBrowserContext: SidebarBrowserContext,
        sidebarInventory: SidebarInventoryProjection,
        sidebarSelection: SidebarWindowSelectionQuery,
        sidebarPinProjection: SidebarPinFolderProjection,
        sidebarPinCommands: SidebarPinFolderCommands,
        sidebarSpaceLifecycle: SidebarSpaceLifecycle,
        sidebarRegularTabs: any SidebarRegularTabsControlling,
        sidebarDragTransactions: SidebarDragTransactionPort,
        sidebarUpdates: SidebarUpdateStreams,
        sidebarHostActions: SidebarHostActions,
        sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling,
        nativeModalPresentation: @escaping () -> BrowserNativeModalPresentation?,
        browsingDataDialogContext: @escaping () -> SumiBrowsingDataDialogContext,
        hasCurrentSpace: @escaping () -> Bool,
        showGradientEditor: @escaping (SidebarTransientPresentationSource) -> Void,
        currentProfileID: @escaping () -> UUID?,
        essentialPins: @escaping (UUID?) -> [ShortcutPin],
        attachHoverSidebarManager: @escaping (HoverSidebarManager, BrowserWindowState) -> Void,
        websiteViewBrowserContext: @escaping () -> WebsiteViewBrowserContext,
        websiteNativeSurfaceRootBuilders: @escaping () -> WebsiteNativeSurfaceRootBuilders,
        currentTab: @escaping (BrowserWindowState) -> Tab?,
        workspaceTheme: @escaping (UUID?) -> WorkspaceTheme?,
        isNativeModalPresented: @escaping (UUID) -> Bool,
        nativeModalPresentationBindingDismissed: @escaping (UUID) -> Void,
        dismissNativeModalPresentation: @escaping () -> Void,
        findCurrentTabId: @escaping () -> UUID?
    ) {
        self.splitUpdates = splitUpdates
        self.splitQuery = splitQuery
        self.splitPreviews = splitPreviews
        self.splitLayout = splitLayout
        self.splitDrops = splitDrops
        self.splitDropTargets = splitDropTargets
        self.webViewOwnershipQuery = webViewOwnershipQuery
        self.trackedWebViewAdmission = trackedWebViewAdmission
        self.webViewCompositorRuntime = webViewCompositorRuntime
        self.webViewProtectionRuntime = webViewProtectionRuntime
        self.findManager = findManager
        self.floatingBarBrowserContext = floatingBarBrowserContext
        self.sidebarBrowserContext = sidebarBrowserContext
        self.sidebarInventory = sidebarInventory
        self.sidebarSelection = sidebarSelection
        self.sidebarPinProjection = sidebarPinProjection
        self.sidebarPinCommands = sidebarPinCommands
        self.sidebarSpaceLifecycle = sidebarSpaceLifecycle
        self.sidebarRegularTabs = sidebarRegularTabs
        self.sidebarDragTransactions = sidebarDragTransactions
        self.sidebarUpdates = sidebarUpdates
        self.sidebarHostActions = sidebarHostActions
        self.sidebarHostRecoveryCoordinator = sidebarHostRecoveryCoordinator
        self._nativeModalPresentation = nativeModalPresentation
        self._browsingDataDialogContext = browsingDataDialogContext
        self._hasCurrentSpace = hasCurrentSpace
        self._showGradientEditor = showGradientEditor
        self._currentProfileID = currentProfileID
        self._essentialPins = essentialPins
        self._attachHoverSidebarManager = attachHoverSidebarManager
        self._websiteViewBrowserContext = websiteViewBrowserContext
        self._websiteNativeSurfaceRootBuilders = websiteNativeSurfaceRootBuilders
        self._currentTab = currentTab
        self._workspaceTheme = workspaceTheme
        self._isNativeModalPresented = isNativeModalPresented
        self._nativeModalPresentationBindingDismissed = nativeModalPresentationBindingDismissed
        self._dismissNativeModalPresentation = dismissNativeModalPresentation
        self._findCurrentTabId = findCurrentTabId
    }

    var nativeModalPresentation: BrowserNativeModalPresentation? {
        _nativeModalPresentation()
    }

    var browsingDataDialogContext: SumiBrowsingDataDialogContext {
        _browsingDataDialogContext()
    }

    var hasCurrentSpace: Bool {
        _hasCurrentSpace()
    }

    func showGradientEditor(source: SidebarTransientPresentationSource) {
        _showGradientEditor(source)
    }

    func currentProfileID() -> UUID? {
        _currentProfileID()
    }

    func essentialPins(profileId: UUID?) -> [ShortcutPin] {
        _essentialPins(profileId)
    }

    func attachHoverSidebarManager(
        _ hoverSidebarManager: HoverSidebarManager,
        windowState: BrowserWindowState
    ) {
        _attachHoverSidebarManager(hoverSidebarManager, windowState)
    }

    func websiteViewBrowserContext() -> WebsiteViewBrowserContext {
        _websiteViewBrowserContext()
    }

    var websiteNativeSurfaceRootBuilders: WebsiteNativeSurfaceRootBuilders {
        _websiteNativeSurfaceRootBuilders()
    }

    func currentTab(for windowState: BrowserWindowState) -> Tab? {
        _currentTab(windowState)
    }

    func workspaceTheme(for spaceId: UUID?) -> WorkspaceTheme? {
        _workspaceTheme(spaceId)
    }

    func isNativeModalPresented(in windowId: UUID) -> Bool {
        _isNativeModalPresented(windowId)
    }

    func nativeModalPresentationBindingDismissed(for windowId: UUID) {
        _nativeModalPresentationBindingDismissed(windowId)
    }

    func dismissNativeModalPresentation() {
        _dismissNativeModalPresentation()
    }

    func findCurrentTabId() -> UUID? {
        _findCurrentTabId()
    }
}
