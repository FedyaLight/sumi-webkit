import AppKit
import SwiftUI
import SumiWebRuntime

@MainActor
final class WindowWebContentCompositorMutationGate {
    private let isCurrentRegistration: (WebViewCompositorContainerRegistration) -> Bool
    private var registration: WebViewCompositorContainerRegistration?

    init(
        isCurrentRegistration: @escaping (WebViewCompositorContainerRegistration) -> Bool
    ) {
        self.isCurrentRegistration = isCurrentRegistration
    }

    func activate(_ registration: WebViewCompositorContainerRegistration) {
        self.registration = registration
    }

    var currentRegistration: WebViewCompositorContainerRegistration? {
        guard let registration,
              isCurrentRegistration(registration) else { return nil }
        return registration
    }

    func owns(_ registration: WebViewCompositorContainerRegistration) -> Bool {
        self.registration == registration && isCurrentRegistration(registration)
    }

    @discardableResult
    func invalidate() -> WebViewCompositorContainerRegistration? {
        defer { registration = nil }
        return registration
    }
}

@MainActor
final class WindowWebContentController: NSViewController {
    private let browserContext: any WindowWebContentBrowserContext
    private let splitQuery: WindowSplitQuery
    private let webViewOwnershipQuery: WebViewOwnershipQuery
    private let trackedWebViewAdmission: TrackedWebViewAdmissionService
    private let webViewCompositorRuntime: WebViewCompositorRuntime
    private let webViewProtectionRuntime: WebViewProtectionRuntime
    private let windowState: BrowserWindowState
    private var chromeGeometry: BrowserChromeGeometry
    private let hostRegistry = WindowWebContentHostRegistry()
    private let containerView: WindowWebContentSplitHostLayoutView

    private var pendingDisplayState: WebsiteDisplayState?
    private var appliedDisplayState: WebsiteDisplayState?
    private var isDisplayStateApplyScheduled = false
    private var hoveredLinkHandler: ((String?) -> Void)?
    private var contentBackgroundColor: Color = .white
    private lazy var compositorMutationGate = WindowWebContentCompositorMutationGate(
        isCurrentRegistration: { [weak self] registration in
            self?.webViewCompositorRuntime.owns(registration)
                ?? false
        }
    )
    private lazy var hoverSession = WindowWebContentHoverSession(
        mutationGate: compositorMutationGate,
        isDisplayed: { [weak self] webView in
            self?.hostRegistry.displayedHosts.contains {
                $0.activePresentationWebView === webView
            } == true
        }
    )
    private lazy var backgroundTransitions = WindowWebContentBackgroundTransitionSession(
        compositorRuntime: webViewCompositorRuntime
    )
    private lazy var hostAttachments = WindowWebContentHostAttachmentService(
        containerView: containerView,
        hostRegistry: hostRegistry,
        compositorRuntime: webViewCompositorRuntime,
        protectionRuntime: webViewProtectionRuntime,
        backgroundTransitions: backgroundTransitions,
        windowID: windowState.id,
        chromeGeometry: chromeGeometry,
        contentBackgroundColor: contentBackgroundColor
    )
    private lazy var hostResolver = WindowWebContentHostResolver(
        ownershipQuery: webViewOwnershipQuery,
        trackedAdmission: trackedWebViewAdmission,
        compositorRuntime: webViewCompositorRuntime,
        protectionRuntime: webViewProtectionRuntime,
        hostRegistry: hostRegistry,
        hostAttachments: hostAttachments,
        windowID: windowState.id
    )
    private lazy var panePresenter = WindowWebContentPanePresenter(
        windowState: windowState,
        containerView: containerView,
        compositorRuntime: webViewCompositorRuntime,
        hostRegistry: hostRegistry,
        hostResolver: hostResolver,
        hostAttachments: hostAttachments
    )
    private lazy var presentationPlanner = WindowWebContentPresentationPlanner(
        browserContext: browserContext,
        splitQuery: splitQuery,
        windowState: windowState,
        containerView: containerView,
        hostRegistry: hostRegistry,
        protectionRuntime: webViewProtectionRuntime
    )
    private lazy var visualHandoffSession = WindowWebContentVisualHandoffSession(
        containerView: containerView,
        hostRegistry: hostRegistry,
        hostAttachments: hostAttachments,
        compositorRuntime: webViewCompositorRuntime,
        protectionRuntime: webViewProtectionRuntime
    )
    private lazy var mediaTouchBarRestoration = WindowMediaTouchBarRestorationService(
        windowID: windowState.id,
        windowState: windowState,
        browserContext: browserContext,
        hostRegistry: hostRegistry,
        mutationGate: compositorMutationGate,
        protectionRuntime: webViewProtectionRuntime,
        window: { [weak self] in
            guard let self, self.isViewLoaded else { return nil }
            return self.view.window
        },
        restoreDisplayedHost: { [weak self] currentTab, registration in
            self?.restoreDisplayedHostForMediaTouchBar(
                currentTab: currentTab,
                containerRegistration: registration
            ) ?? false
        }
    )
    private lazy var mediaTouchBarRecoveryScheduler =
        WindowMediaTouchBarRecoveryScheduler(
            windowID: windowState.id,
            recover: { [weak self] tabID, webView in
                self?.mediaTouchBarRestoration.recover(
                    tabID: tabID,
                    webView: webView
                )
            }
        )

    init(
        browserContext: any WindowWebContentBrowserContext,
        splitQuery: WindowSplitQuery,
        webViewOwnershipQuery: WebViewOwnershipQuery,
        trackedWebViewAdmission: TrackedWebViewAdmissionService,
        webViewCompositorRuntime: WebViewCompositorRuntime,
        webViewProtectionRuntime: WebViewProtectionRuntime,
        chromeGeometry: BrowserChromeGeometry,
        windowState: BrowserWindowState,
        containerView: WindowWebContentSplitHostLayoutView
    ) {
        self.browserContext = browserContext
        self.splitQuery = splitQuery
        self.webViewOwnershipQuery = webViewOwnershipQuery
        self.trackedWebViewAdmission = trackedWebViewAdmission
        self.webViewCompositorRuntime = webViewCompositorRuntime
        self.webViewProtectionRuntime = webViewProtectionRuntime
        self.chromeGeometry = chromeGeometry
        self.windowState = windowState
        self.containerView = containerView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = containerView
        let registration = webViewCompositorRuntime.registerContainer(
            containerView,
            for: windowState.id,
            immediateVisualHandoffHandler: { [weak self] in
                self?.performImmediateVisualHandoffIfPossible() ?? false
            }
        )
        compositorMutationGate.activate(registration)
        mediaTouchBarRecoveryScheduler.start()

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.compositorMutationGate.owns(registration) else { return }
            self.browserContext.schedulePrepareVisibleWebViews(for: self.windowState)
        }
    }

    func tearDownController() {
        containerView.setSplitDropCaptureActive(false)
        let registration = compositorMutationGate.invalidate()
        pendingDisplayState = nil
        appliedDisplayState = nil
        isDisplayStateApplyScheduled = false
        hoveredLinkHandler = nil
        hoverSession.invalidate()
        mediaTouchBarRecoveryScheduler.stop()
        visualHandoffSession.release()
        guard let registration else { return }

        _ = webViewCompositorRuntime.tearDownContainer(
            registration
        ) { [self] in
            if webViewProtectionRuntime.hasActiveFullscreen(in: windowState.id) {
                webViewProtectionRuntime.closeActiveFullscreenMedia(in: windowState.id)
            }
            hostAttachments.clearSinglePane()
            hostAttachments.clearAllSplitPaneHosts()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard compositorMutationGate.currentRegistration != nil else { return }

        if webViewProtectionRuntime.hasActiveHistorySwipe(in: windowState.id) {
            browserContext.enqueueWindowMutationDuringHistorySwipe(
                .refreshCompositor,
                for: windowState
            )
            view.layoutSubtreeIfNeeded()
        }
    }

    func update(
        displayState: WebsiteDisplayState,
        hoveredLinkHandler: @escaping (String?) -> Void,
        chromeGeometry: BrowserChromeGeometry,
        contentBackgroundColor: Color
    ) {
        guard let registration = compositorMutationGate.currentRegistration else { return }
        let currentTab = browserContext.currentTab(for: windowState)
        let needsDisplayStateApply = presentationPlanner.needsDisplayStateApply(
            appliedDisplayState: appliedDisplayState,
            displayState: displayState,
            currentTab: currentTab
        )

        let previousBg = self.contentBackgroundColor
        self.contentBackgroundColor = contentBackgroundColor
        let bgChanged = previousBg != contentBackgroundColor

        if self.chromeGeometry != chromeGeometry || bgChanged {
            self.chromeGeometry = chromeGeometry
            containerView.setChromeGeometry(chromeGeometry)
            hostAttachments.updateViewportStyle(
                chromeGeometry: chromeGeometry,
                contentBackgroundColor: contentBackgroundColor
            )
        }

        pendingDisplayState = displayState
        self.hoveredLinkHandler = hoveredLinkHandler
        if needsDisplayStateApply {
            hoverSession.reconcile(
                hosts: [],
                registration: registration,
                deliver: hoveredLinkHandler
            )
        } else {
            refreshHoverSession(
                containerRegistration: registration
            )
        }

        if !displayState.visibleTabIDs.isEmpty
            && hasMissingPreparedWebViews(for: displayState.visibleTabIDs) {
            browserContext.schedulePrepareVisibleWebViews(for: windowState)
        }

        guard needsDisplayStateApply else { return }
        scheduleDisplayStateApply()
    }

    private func scheduleDisplayStateApply() {
        guard let registration = compositorMutationGate.currentRegistration else { return }
        guard !isDisplayStateApplyScheduled else { return }
        isDisplayStateApplyScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.applyPendingDisplayStateIfNeeded(
                containerRegistration: registration
            )
        }
    }

    private func applyPendingDisplayStateIfNeeded(
        containerRegistration registration: WebViewCompositorContainerRegistration
    ) {
        isDisplayStateApplyScheduled = false
        guard compositorMutationGate.owns(registration),
              let displayState = pendingDisplayState else { return }

        if webViewProtectionRuntime.hasActiveHistorySwipe(in: windowState.id) {
            browserContext.enqueueWindowMutationDuringHistorySwipe(
                .refreshCompositor,
                for: windowState
            )
            return
        }

        let currentTab = browserContext.currentTab(for: windowState)
        guard presentationPlanner.needsDisplayStateApply(
            appliedDisplayState: appliedDisplayState,
            displayState: displayState,
            currentTab: currentTab
        ) else { return }

        let previousCurrentId = appliedDisplayState?.currentId
        guard apply(
            displayState: displayState,
            currentTab: currentTab,
            containerRegistration: registration
        ), compositorMutationGate.owns(registration) else { return }
        appliedDisplayState = displayState
        refreshHoverSession(
            containerRegistration: registration
        )

        if previousCurrentId != displayState.currentId {
            restoreFocusIfNeeded(
                for: displayState.currentId,
                containerRegistration: registration
            )
        }
    }

    @discardableResult
    private func apply(
        displayState: WebsiteDisplayState,
        currentTab: Tab?,
        containerRegistration: WebViewCompositorContainerRegistration
    ) -> Bool {
        guard compositorMutationGate.owns(containerRegistration) else { return false }
        containerView.setSplitDropCaptureActive(displayState.isSplitDropCaptureActive)
        return apply(
            presentationPlanner.presentationDecision(
                for: displayState,
                currentTab: currentTab
            ),
            containerRegistration: containerRegistration
        )
    }

    @discardableResult
    private func apply(
        _ decision: WindowWebContentPresentationDecision,
        containerRegistration: WebViewCompositorContainerRegistration
    ) -> Bool {
        guard compositorMutationGate.owns(containerRegistration) else { return false }
        let didBeginVisualHandoff: Bool
        if let incomingTabIDs = presentationPlanner
            .incomingTabIDsForVisualHandoff(decision) {
            didBeginVisualHandoff = visualHandoffSession.begin(
                excluding: incomingTabIDs,
                containerRegistration: containerRegistration
            )
        } else {
            didBeginVisualHandoff = false
        }
        defer {
            if didBeginVisualHandoff {
                visualHandoffSession.scheduleRelease()
            }
        }

        switch decision {
        case .single(let tab):
            return panePresenter.presentSinglePane(
                tab: tab,
                containerRegistration: containerRegistration
            )
        case .split(let presentation, let tabs):
            return panePresenter.presentSplitGroup(
                presentation,
                tabs: tabs,
                containerRegistration: containerRegistration
            )
        }
    }

    private func performImmediateVisualHandoffIfPossible() -> Bool {
        guard let registration = compositorMutationGate.currentRegistration else {
            return false
        }
        let currentTab = browserContext.currentTab(for: windowState)
        guard let decision = presentationPlanner
            .immediatePresentationDecision(currentTab: currentTab)
        else {
            return false
        }

        guard apply(decision, containerRegistration: registration),
              compositorMutationGate.owns(registration) else { return false }
        refreshHoverSession(containerRegistration: registration)

        guard let currentTab else { return false }
        return hostRegistry.displayedHost(for: currentTab.id) != nil
    }

    private func restoreFocusIfNeeded(
        for tabId: UUID?,
        containerRegistration: WebViewCompositorContainerRegistration
    ) {
        guard compositorMutationGate.owns(containerRegistration) else { return }
        guard webViewProtectionRuntime.hasActiveHistorySwipe(in: windowState.id) == false else { return }
        guard let tabId,
              let window = view.window,
              let host = hostRegistry.displayedHost(for: tabId),
              host.window === window
        else {
            return
        }
        let focusTarget = host.activePresentationWebView
        guard focusTarget.window === window,
              !focusTarget.isHidden
        else {
            return
        }
        guard !host.activePresentationWebView.sumiIsInFullscreenElementPresentation else { return }
        guard window.firstResponder !== focusTarget else { return }
        guard compositorMutationGate.owns(containerRegistration) else { return }
        window.makeFirstResponder(focusTarget)
    }

    private func restoreDisplayedHostForMediaTouchBar(
        currentTab: Tab,
        containerRegistration: WebViewCompositorContainerRegistration
    ) -> Bool {
        guard let displayState = pendingDisplayState ?? appliedDisplayState else {
            return false
        }
        guard apply(
            displayState: displayState,
            currentTab: currentTab,
            containerRegistration: containerRegistration
        ), compositorMutationGate.owns(containerRegistration) else {
            return false
        }
        appliedDisplayState = displayState
        refreshHoverSession(
            containerRegistration: containerRegistration
        )
        return hostRegistry.displayedHost(for: currentTab.id) != nil
    }

    private func refreshHoverSession(
        containerRegistration: WebViewCompositorContainerRegistration
    ) {
        guard compositorMutationGate.owns(containerRegistration),
              let hoveredLinkHandler
        else { return }

        hoverSession.reconcile(
            hosts: hostRegistry.displayedHosts,
            registration: containerRegistration,
            deliver: hoveredLinkHandler
        )
    }

    private func hasMissingPreparedWebViews(for visibleTabIDs: Set<UUID>) -> Bool {
        visibleTabIDs.contains { tabID in
            if let tab = browserContext.tab(for: tabID),
               !tab.requiresPrimaryWebView {
                return false
            }
            return webViewOwnershipQuery.webView(for: tabID, in: windowState.id) == nil
        }
    }

}
