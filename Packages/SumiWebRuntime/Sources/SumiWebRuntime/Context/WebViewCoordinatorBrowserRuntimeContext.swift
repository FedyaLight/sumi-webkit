import Foundation
import WebKit

@MainActor
public struct WebViewCoordinatorBrowserRuntimeContext {
    public let tab: (UUID) -> (any WebRuntimeTabHandle)?
    public let regularTabs: () -> [any WebRuntimeTabHandle]
    public let pinnedTabs: () -> [any WebRuntimeTabHandle]
    public let allWindows: () -> [any WebRuntimeWindowHandle]
    public let window: (UUID) -> (any WebRuntimeWindowHandle)?
    public let windowContaining: (any WebRuntimeTabHandle) -> (any WebRuntimeWindowHandle)?
    public let currentTab: (any WebRuntimeWindowHandle) -> (any WebRuntimeTabHandle)?
    public let selectTab: (_ tabID: UUID, _ windowID: UUID) -> Void
    public let handleUnprotectedWebViewDidClose: (WKWebView) -> Bool
    /// Compositor refresh is UUID-keyed so package owners need not see BrowserWindowState.
    public let refreshCompositor: (UUID) -> Void
    public let notifyTabActivatedIfLoaded: (any WebRuntimeTabHandle) -> Void
    /// Re-enters the TabManager-owned profile transaction when compositor
    /// protection releases a deferred immutable assignment intent.
    public let executeDeferredProfileAssignment: (
        UUID,
        UUID?,
        DeferredWebViewProfileAssignmentIntent
    ) -> Bool
    public let validateDeferredSpaceProfileAssignment: (
        DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool
    public let executeDeferredSpaceProfileAssignment: (
        DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool
    public let globallyVisibleTabIDs: @MainActor @Sendable () -> Set<UUID>

    public init(
        tab: @escaping (UUID) -> (any WebRuntimeTabHandle)?,
        regularTabs: @escaping () -> [any WebRuntimeTabHandle],
        pinnedTabs: @escaping () -> [any WebRuntimeTabHandle],
        allWindows: @escaping () -> [any WebRuntimeWindowHandle],
        window: @escaping (UUID) -> (any WebRuntimeWindowHandle)?,
        windowContaining: @escaping (any WebRuntimeTabHandle) -> (any WebRuntimeWindowHandle)?,
        currentTab: @escaping (any WebRuntimeWindowHandle) -> (any WebRuntimeTabHandle)?,
        selectTab: @escaping (_ tabID: UUID, _ windowID: UUID) -> Void,
        handleUnprotectedWebViewDidClose: @escaping (WKWebView) -> Bool,
        refreshCompositor: @escaping (UUID) -> Void,
        notifyTabActivatedIfLoaded: @escaping (any WebRuntimeTabHandle) -> Void,
        executeDeferredProfileAssignment: @escaping (
            UUID,
            UUID?,
            DeferredWebViewProfileAssignmentIntent
        ) -> Bool = { _, _, _ in false },
        validateDeferredSpaceProfileAssignment: @escaping (
            DeferredWebViewSpaceProfileAssignmentIntent
        ) -> Bool = { _ in false },
        executeDeferredSpaceProfileAssignment: @escaping (
            DeferredWebViewSpaceProfileAssignmentIntent
        ) -> Bool = { _ in false },
        globallyVisibleTabIDs: @escaping @MainActor @Sendable () -> Set<UUID>
    ) {
        self.tab = tab
        self.regularTabs = regularTabs
        self.pinnedTabs = pinnedTabs
        self.allWindows = allWindows
        self.window = window
        self.windowContaining = windowContaining
        self.currentTab = currentTab
        self.selectTab = selectTab
        self.handleUnprotectedWebViewDidClose = handleUnprotectedWebViewDidClose
        self.refreshCompositor = refreshCompositor
        self.notifyTabActivatedIfLoaded = notifyTabActivatedIfLoaded
        self.executeDeferredProfileAssignment = executeDeferredProfileAssignment
        self.validateDeferredSpaceProfileAssignment =
            validateDeferredSpaceProfileAssignment
        self.executeDeferredSpaceProfileAssignment =
            executeDeferredSpaceProfileAssignment
        self.globallyVisibleTabIDs = globallyVisibleTabIDs
    }
}

extension WebViewCoordinatorBrowserRuntimeContext: WebRuntimeTabResolving {
    public func resolveWebRuntimeTab(_ id: UUID) -> (any WebRuntimeTabHandle)? {
        if let tab = tab(id) {
            return tab
        }
        for window in allWindows() {
            if let ephemeral = window.ephemeralTabHandles.first(where: { $0.id == id }) {
                return ephemeral
            }
        }
        return nil
    }
}
