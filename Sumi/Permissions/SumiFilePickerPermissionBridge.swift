import Foundation
import WebKit

@MainActor
final class SumiFilePickerCompletionHandler {
    private var completionHandler: (([URL]?) -> Void)?

    init(_ completionHandler: @escaping ([URL]?) -> Void) {
        self.completionHandler = completionHandler
    }

    func resolve(_ urls: [URL]?) {
        guard let handler = completionHandler else { return }
        completionHandler = nil
        handler(urls)
    }
}

@MainActor
final class SumiFilePickerPermissionBridge {
    private struct PendingFilePicker {
        let requestId: String
        let tabId: String
        let pageId: String
        let navigationOrPageGeneration: String?
        let indicatorEventId: String?
        let completionHandler: SumiFilePickerCompletionHandler
    }

    private let coordinator: any SumiPermissionCoordinating
    private let panelPresenter: any SumiFilePickerPanelPresenting
    private let now: @Sendable () -> Date
    private let indicatorEventStore: SumiPermissionIndicatorEventStore?
    private var pendingByRequestId: [String: PendingFilePicker] = [:]

    init(
        coordinator: any SumiPermissionCoordinating,
        panelPresenter: any SumiFilePickerPanelPresenting,
        now: @escaping @Sendable () -> Date = { Date() },
        indicatorEventStore: SumiPermissionIndicatorEventStore? = nil
    ) {
        self.coordinator = coordinator
        self.panelPresenter = panelPresenter
        self.now = now
        self.indicatorEventStore = indicatorEventStore
    }

    func handleOpenPanel(
        _ request: SumiFilePickerPermissionRequest,
        tabContext: SumiFilePickerPermissionTabContext,
        webView: WKWebView?,
        currentPageId: @escaping @MainActor () -> String?,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let once = SumiFilePickerCompletionHandler(completionHandler)
        guard webView != nil else {
            once.resolve(nil)
            return
        }

        let context = securityContext(for: request, tabContext: tabContext)
        Task { @MainActor [weak self, weak webView] in
            guard let self else {
                once.resolve(nil)
                return
            }

            let decision = await self.coordinator.queryPermissionState(context)
            switch SumiFilePickerDecisionMapper.action(for: decision) {
            case .presentPanel:
                guard webView != nil,
                      currentPageId() == tabContext.pageId
                else {
                    once.resolve(nil)
                    return
                }
                self.presentPanel(
                    for: request,
                    tabContext: tabContext,
                    webView: webView,
                    currentPageId: currentPageId,
                    completionHandler: once
                )
            case .deny:
                once.resolve(nil)
            }
        }
    }

    func securityContext(
        for request: SumiFilePickerPermissionRequest,
        tabContext: SumiFilePickerPermissionTabContext
    ) -> SumiPermissionSecurityContext {
        let topOrigin = SumiPermissionOrigin(
            url: tabContext.committedURL ?? tabContext.mainFrameURL ?? tabContext.visibleURL
        )
        let permissionRequest = SumiPermissionRequest(
            id: request.id,
            tabId: tabContext.tabId,
            pageId: tabContext.pageId,
            frameId: nil,
            requestingOrigin: request.requestingOrigin,
            topOrigin: topOrigin,
            displayDomain: request.requestingOrigin.displayDomain,
            permissionTypes: [.filePicker],
            hasUserGesture: request.isUserActivated,
            requestedAt: now(),
            isEphemeralProfile: tabContext.isEphemeralProfile,
            profilePartitionId: tabContext.profilePartitionId
        )

        return SumiPermissionSecurityContext(
            request: permissionRequest,
            requestingOrigin: request.requestingOrigin,
            topOrigin: topOrigin,
            committedURL: tabContext.committedURL,
            visibleURL: tabContext.visibleURL,
            mainFrameURL: tabContext.mainFrameURL,
            isMainFrame: request.isMainFrame,
            isActiveTab: tabContext.isActiveTab,
            isVisibleTab: tabContext.isVisibleTab,
            hasUserGesture: request.isUserActivated,
            isEphemeralProfile: tabContext.isEphemeralProfile,
            profilePartitionId: tabContext.profilePartitionId,
            transientPageId: tabContext.pageId,
            surface: .normalTab,
            navigationOrPageGeneration: tabContext.navigationOrPageGeneration,
            now: permissionRequest.requestedAt
        )
    }

    func cancel(pageId: String, reason _: String = "file-picker-page-cancelled") {
        let normalizedPageId = pageId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let requestIds = pendingByRequestId.values
            .filter { $0.pageId == normalizedPageId }
            .map(\.requestId)
        resolvePending(requestIds: requestIds, result: .cancelled)
    }

    func cancel(tabId: String, reason _: String = "file-picker-tab-cancelled") {
        let normalizedTabId = tabId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let requestIds = pendingByRequestId.values
            .filter { $0.tabId == normalizedTabId }
            .map(\.requestId)
        resolvePending(requestIds: requestIds, result: .cancelled)
    }

    private func presentPanel(
        for request: SumiFilePickerPermissionRequest,
        tabContext: SumiFilePickerPermissionTabContext,
        webView: WKWebView?,
        currentPageId: @escaping @MainActor () -> String?,
        completionHandler: SumiFilePickerCompletionHandler
    ) {
        let indicatorEventId = "file-picker-\(request.id)"
        indicatorEventStore?.record(
            SumiPermissionIndicatorEventRecord(
                id: indicatorEventId,
                tabId: tabContext.tabId,
                pageId: tabContext.pageId,
                displayDomain: request.requestingOrigin.displayDomain,
                permissionTypes: [.filePicker],
                category: .pendingRequest,
                visualStyle: .attention,
                priority: .filePickerCurrentEvent,
                reason: "file-picker-current-event",
                createdAt: now()
            )
        )

        pendingByRequestId[request.id] = PendingFilePicker(
            requestId: request.id,
            tabId: tabContext.tabId,
            pageId: tabContext.pageId,
            navigationOrPageGeneration: tabContext.navigationOrPageGeneration,
            indicatorEventId: indicatorEventId,
            completionHandler: completionHandler
        )

        let presentationRequest = SumiFilePickerPanelPresentationRequest(
            id: request.id,
            tabId: tabContext.tabId,
            pageId: tabContext.pageId,
            allowsMultipleSelection: request.allowsMultipleSelection,
            allowsDirectories: request.allowsDirectories,
            allowedContentTypeIdentifiers: request.allowedContentTypeIdentifiers,
            allowedFileExtensions: request.allowedFileExtensions
        )

        panelPresenter.presentFilePicker(presentationRequest, for: webView) { [weak self, weak webView] result in
            guard let self else { return }
            guard webView != nil,
                  currentPageId() == tabContext.pageId
            else {
                self.resolvePending(requestIds: [request.id], result: .cancelled)
                return
            }
            self.resolvePending(requestIds: [request.id], result: result)
        }
    }

    private func resolvePending(
        requestIds: [String],
        result: SumiFilePickerPanelResult
    ) {
        for requestId in requestIds {
            guard let pending = pendingByRequestId.removeValue(forKey: requestId) else {
                continue
            }
            if let indicatorEventId = pending.indicatorEventId {
                indicatorEventStore?.clear(eventId: indicatorEventId, pageId: pending.pageId)
            }
            pending.completionHandler.resolve(result.webKitURLs)
        }
    }
}
