import Foundation

@MainActor
final class BrowserTabSelectionMaterializationOwner {
    private let pages: BrowserTabSelectionMaterializationQuery
    private let startupProtection: BrowserStartupProtectionRuntime
    private let compositor: TabCompositorManager
    private let trackedAdmission: TrackedWebViewAdmissionService
    private let windowVisuals: BrowserWindowVisualCoordinator

    init(
        pages: BrowserTabSelectionMaterializationQuery,
        startupProtection: BrowserStartupProtectionRuntime,
        compositor: TabCompositorManager,
        trackedAdmission: TrackedWebViewAdmissionService,
        windowVisuals: BrowserWindowVisualCoordinator
    ) {
        self.pages = pages
        self.startupProtection = startupProtection
        self.compositor = compositor
        self.trackedAdmission = trackedAdmission
        self.windowVisuals = windowVisuals
    }

    func scheduleIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        loadPolicy: TabSelectionLoadPolicy
    ) {
        let requests = windowState.pageMaterializationRequests
        var seen: Set<UUID> = []
        let candidates = pages.visibleTabs(including: tab, in: windowState).filter {
            seen.insert($0.id).inserted
        }
        let coldPages = candidates.filter {
            $0.isUnloaded && $0.requiresPrimaryWebView
        }
        let admission = requests.beginActivation(
            coldPages.map {
                PageMaterializationRequestSeed(
                    pageID: $0.id,
                    residenceGeneration: $0.webViewSession.generation,
                    destination: $0.url
                )
            },
            windowID: windowState.id
        )
        for request in admission.requests {
            guard let page = candidates.first(where: { $0.id == request.pageID })
            else {
                _ = requests.settle(request, as: .failed(.residenceUnavailable))
                continue
            }
            page.beginLoadingPresentationIfNeeded()
            guard startupProtection.canMaterializeWebViewDuringStartup(page) else {
                continue
            }
            page.resolveProfile()?.prepareWebKitRuntime()
            switch loadPolicy {
            case .immediate:
                materialize(page, in: windowState, request: request)
            case .deferred:
                Task { @MainActor [weak self, weak page, weak windowState] in
                    guard let self, let page, let windowState else { return }
                    await Task.yield()
                    guard requests.owns(request),
                          self.pages.isVisible(page, in: windowState),
                          page.webViewSession.generation
                            == request.residenceGeneration else {
                        _ = requests.settle(request, as: .superseded)
                        return
                    }
                    self.materialize(page, in: windowState, request: request)
                    self.windowVisuals.refreshCompositor(for: windowState)
                }
            }
        }
    }

    @discardableResult
    func materialize(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) -> PageMaterializationRequestSettlement? {
        let requests = windowState.pageMaterializationRequests
        guard tab.isUnloaded, tab.requiresPrimaryWebView else {
            guard let request = requests.currentRequest(
                for: tab.id,
                in: windowState.id
            ) else { return nil }
            return requests.settle(request, as: .superseded)
        }
        let request: PageMaterializationRequest
        if let current = requests.currentRequest(
            for: tab.id,
            in: windowState.id
        ),
           current.residenceGeneration == tab.webViewSession.generation,
           current.destination == tab.url {
            request = current
        } else {
            request = requests.begin(
                pageID: tab.id,
                windowID: windowState.id,
                residenceGeneration: tab.webViewSession.generation,
                destination: tab.url
            ).request
        }
        return materialize(tab, in: windowState, request: request)
    }

    func retryCurrent(in windowState: BrowserWindowState) {
        let requests = windowState.pageMaterializationRequests
        for request in requests.currentRequests(in: windowState.id) {
            guard let tab = pages.tab(request.pageID, in: windowState),
                  pages.isVisible(tab, in: windowState) else {
                _ = requests.settle(request, as: .departed)
                continue
            }
            _ = materialize(tab, in: windowState, request: request)
        }
    }

    @discardableResult
    private func materialize(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        request: PageMaterializationRequest
    ) -> PageMaterializationRequestSettlement? {
        let requests = windowState.pageMaterializationRequests
        guard requests.owns(request),
              tab.id == request.pageID,
              tab.webViewSession.generation == request.residenceGeneration else {
            return requests.settle(request, as: .superseded)
        }
        compositor.markTabAccessed(tab.id)
        guard let webView = trackedAdmission.webView(
            for: tab,
            in: windowState.id,
            replayMaterialization: { [weak self, weak tab, weak windowState] in
                guard let self, let tab, let windowState else { return }
                _ = self.materialize(tab, in: windowState, request: request)
                self.windowVisuals.refreshCompositor(for: windowState)
            }
        ) else {
            return nil
        }
        if tab.committedDocumentRuntime.lease(for: webView) != nil {
            return requests.settle(
                request,
                as: .liveExisting(webViewID: ObjectIdentifier(webView))
            )
        }
        switch tab.mainFrameLoads.attemptStatus(on: webView) {
        case .waiting(let owner), .submitted(let owner):
            return requests.settle(request, as: .transferred(owner))
        case .unsubmitted:
            tab.rollbackMainFrameNavigationAfterFailedSubmission(
                on: webView
            )
            return requests.settle(
                request,
                as: .failed(.initialSubmissionUnavailable)
            )
        }
    }
}
