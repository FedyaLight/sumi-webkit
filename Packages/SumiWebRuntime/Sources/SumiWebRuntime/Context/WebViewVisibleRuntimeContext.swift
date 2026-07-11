import Foundation

@MainActor
public struct WebViewVisibleRuntimeContext {
    public let windowState: (UUID) -> (any WebRuntimeWindowHandle)?
    public let currentTabId: (any WebRuntimeWindowHandle) -> UUID?
    public let splitVisibleTabIds: (UUID) -> [UUID]
    public let resolveTab: (UUID, any WebRuntimeWindowHandle) -> (any WebRuntimeTabHandle)?
    public let canMaterializeWebViewDuringStartup: (any WebRuntimeTabHandle) -> Bool
    public let markTabAccessed: (UUID) -> Void
    public let globallyVisibleTabIDs: @MainActor @Sendable () -> Set<UUID>
    public let scheduleTabSuspensionReconcile: (String) -> Void
    public let scheduleBackgroundMediaReconcile: (String) -> Void
    /// Compositor refresh is UUID-keyed so package owners need not see BrowserWindowState.
    public let refreshCompositor: (UUID) -> Void

    public init(
        windowState: @escaping (UUID) -> (any WebRuntimeWindowHandle)?,
        currentTabId: @escaping (any WebRuntimeWindowHandle) -> UUID?,
        splitVisibleTabIds: @escaping (UUID) -> [UUID],
        resolveTab: @escaping (UUID, any WebRuntimeWindowHandle) -> (any WebRuntimeTabHandle)?,
        canMaterializeWebViewDuringStartup: @escaping (any WebRuntimeTabHandle) -> Bool,
        markTabAccessed: @escaping (UUID) -> Void,
        globallyVisibleTabIDs: @escaping @MainActor @Sendable () -> Set<UUID>,
        scheduleTabSuspensionReconcile: @escaping (String) -> Void,
        scheduleBackgroundMediaReconcile: @escaping (String) -> Void,
        refreshCompositor: @escaping (UUID) -> Void
    ) {
        self.windowState = windowState
        self.currentTabId = currentTabId
        self.splitVisibleTabIds = splitVisibleTabIds
        self.resolveTab = resolveTab
        self.canMaterializeWebViewDuringStartup = canMaterializeWebViewDuringStartup
        self.markTabAccessed = markTabAccessed
        self.globallyVisibleTabIDs = globallyVisibleTabIDs
        self.scheduleTabSuspensionReconcile = scheduleTabSuspensionReconcile
        self.scheduleBackgroundMediaReconcile = scheduleBackgroundMediaReconcile
        self.refreshCompositor = refreshCompositor
    }
}
