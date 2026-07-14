import SwiftUI
import SumiWebRuntime

struct TabCompositorWrapper: NSViewControllerRepresentable {
    private let makeBrowserContext: () -> any WindowWebContentBrowserContext
    private let currentTabForDisplayState: (BrowserWindowState) -> Tab?
    private let resolveDragTab: (SumiDragItem) -> Tab?
    private let splitQuery: WindowSplitQuery
    private let splitPreviews: SplitPreviewSession
    private let splitLayout: SplitLayoutService
    private let splitDrops: SplitDropService
    private let splitDropTargets: SplitDropTargetService
    private let sidebarDragState: SidebarDragState
    let webViewOwnershipQuery: WebViewOwnershipQuery
    let trackedWebViewAdmission: TrackedWebViewAdmissionService
    let webViewCompositorRuntime: WebViewCompositorRuntime
    let webViewProtectionRuntime: WebViewProtectionRuntime
    @Binding var hoveredLink: String?
    var splitPresentation: WindowSplitPresentation?
    var isSplitDropCaptureActive: Bool
    var chromeGeometry: BrowserChromeGeometry
    let windowState: BrowserWindowState
    var contentBackgroundColor: Color

    init(
        browserContext: any WindowWebContentBrowserContext,
        resolveDragTab: @escaping (SumiDragItem) -> Tab?,
        splitQuery: WindowSplitQuery,
        splitPreviews: SplitPreviewSession,
        splitLayout: SplitLayoutService,
        splitDrops: SplitDropService,
        splitDropTargets: SplitDropTargetService,
        sidebarDragState: SidebarDragState,
        webViewOwnershipQuery: WebViewOwnershipQuery,
        trackedWebViewAdmission: TrackedWebViewAdmissionService,
        webViewCompositorRuntime: WebViewCompositorRuntime,
        webViewProtectionRuntime: WebViewProtectionRuntime,
        hoveredLink: Binding<String?>,
        splitPresentation: WindowSplitPresentation?,
        isSplitDropCaptureActive: Bool,
        chromeGeometry: BrowserChromeGeometry,
        windowState: BrowserWindowState,
        contentBackgroundColor: Color
    ) {
        self.makeBrowserContext = { browserContext }
        self.resolveDragTab = resolveDragTab
        self.splitQuery = splitQuery
        self.splitPreviews = splitPreviews
        self.splitLayout = splitLayout
        self.splitDrops = splitDrops
        self.splitDropTargets = splitDropTargets
        self.sidebarDragState = sidebarDragState
        self.currentTabForDisplayState = { windowState in
            browserContext.currentTab(for: windowState)
        }
        self.webViewOwnershipQuery = webViewOwnershipQuery
        self.trackedWebViewAdmission = trackedWebViewAdmission
        self.webViewCompositorRuntime = webViewCompositorRuntime
        self.webViewProtectionRuntime = webViewProtectionRuntime
        self._hoveredLink = hoveredLink
        self.splitPresentation = splitPresentation
        self.isSplitDropCaptureActive = isSplitDropCaptureActive
        self.chromeGeometry = chromeGeometry
        self.windowState = windowState
        self.contentBackgroundColor = contentBackgroundColor
    }

    final class Coordinator {
        var hoveredLink: Binding<String?>

        private var pendingHoveredLink: String?
        private var hasPendingHoveredLink = false
        private var isHoveredLinkUpdateScheduled = false

        init(hoveredLink: Binding<String?>) {
            self.hoveredLink = hoveredLink
        }

        @MainActor
        func setHoveredLink(_ link: String?) {
            guard hoveredLink.wrappedValue != link || hasPendingHoveredLink else { return }

            pendingHoveredLink = link
            hasPendingHoveredLink = true

            guard !isHoveredLinkUpdateScheduled else { return }
            isHoveredLinkUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.flushPendingHoveredLink()
            }
        }

        @MainActor
        private func flushPendingHoveredLink() {
            isHoveredLinkUpdateScheduled = false
            guard hasPendingHoveredLink else { return }

            let link = pendingHoveredLink
            pendingHoveredLink = nil
            hasPendingHoveredLink = false

            guard hoveredLink.wrappedValue != link else { return }
            hoveredLink.wrappedValue = link
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(hoveredLink: $hoveredLink)
    }

    func makeNSViewController(context: Context) -> WindowWebContentController {
        let containerView = WindowWebContentSplitHostLayoutView(
            splitLayout: splitLayout,
            splitDrops: splitDrops,
            splitDropTargets: splitDropTargets,
            splitPreviews: splitPreviews,
            sidebarDragState: sidebarDragState,
            windowState: windowState,
            resolveDragTab: resolveDragTab,
            chromeGeometry: chromeGeometry
        )
        return WindowWebContentController(
            browserContext: makeBrowserContext(),
            splitQuery: splitQuery,
            webViewOwnershipQuery: webViewOwnershipQuery,
            trackedWebViewAdmission: trackedWebViewAdmission,
            webViewCompositorRuntime: webViewCompositorRuntime,
            webViewProtectionRuntime: webViewProtectionRuntime,
            chromeGeometry: chromeGeometry,
            windowState: windowState,
            containerView: containerView
        )
    }

    func updateNSViewController(_ controller: WindowWebContentController, context: Context) {
        context.coordinator.hoveredLink = $hoveredLink
        controller.update(
            displayState: makeDisplayState(),
            hoveredLinkHandler: { context.coordinator.setHoveredLink($0) },
            chromeGeometry: chromeGeometry,
            contentBackgroundColor: contentBackgroundColor
        )
    }

    static func dismantleNSViewController(_ controller: WindowWebContentController, coordinator: Coordinator) {
        controller.tearDownController()
    }

    private func makeDisplayState() -> WebsiteDisplayState {
        let currentTab = currentTabForDisplayState(windowState)
        let currentId = currentTab?.id
        return WebsiteDisplayState(
            splitPresentation: splitPresentation,
            currentId: currentId,
            compositorVersion: windowState.compositorInvalidation.compositorVersion,
            currentTabUnloaded: currentTab?.isUnloaded ?? true,
            isSplitDropCaptureActive: isSplitDropCaptureActive
        )
    }
}
