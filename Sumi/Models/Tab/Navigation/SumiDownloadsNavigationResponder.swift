import AppKit
import Foundation
import Navigation
import WebKit

@MainActor
final class SumiDownloadsNavigationResponder: NavigationResponder {
    private weak var tab: Tab?
    private weak var downloadManager: DownloadManager?
    private var isRestoringSessionState = false

    init(tab: Tab, downloadManager: DownloadManager?) {
        self.tab = tab
        self.downloadManager = downloadManager
    }

    func decidePolicy(
        for navigationAction: NavigationAction,
        preferences _: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        if case .sessionRestoration = navigationAction.navigationType {
            isRestoringSessionState = true
        } else if isRestoringSessionState,
                  navigationAction.isUserInitiated
                    || navigationAction.sumiIsCustom
                    || navigationAction.sumiIsUserEnteredURL
                    || [.reload, .formSubmitted, .formResubmitted, .alternateHtmlLoad].contains(navigationAction.navigationType)
                    || navigationAction.navigationType.isBackForward {
            isRestoringSessionState = false
        }

        let optionDownloadRequested = navigationAction.navigationType.isLinkActivated
            && navigationAction.modifierFlags.contains(.option)
            && !navigationAction.modifierFlags.contains(.command)

        if (navigationAction.shouldDownload && !isRestoringSessionState) || optionDownloadRequested {
            return .download
        }

        return .next
    }

    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? {
        let firstNavigationAction = navigationResponse.mainFrameNavigation?.redirectHistory.first
            ?? navigationResponse.mainFrameNavigation?.navigationAction

        guard navigationResponse.httpResponse?.isSuccessful != false,
              !navigationResponse.url.hasDirectoryPath,
              !navigationResponse.canShowMIMEType || navigationResponse.shouldDownload
                || (navigationResponse.mainFrameNavigation?.redirectHistory.last
                    ?? navigationResponse.mainFrameNavigation?.navigationAction)?.navigationType == .custom(.sumiUserRequestedPageDownload)
        else {
            return .next
        }

        guard firstNavigationAction?.request.cachePolicy != .returnCacheDataElseLoad,
              !isRestoringSessionState
        else {
            return .cancel
        }

        return .download
    }

    func navigationAction(_ navigationAction: NavigationAction, didBecome download: WebKitDownload) {
        enqueueDownload(download, originalURL: navigationAction.url, response: nil, requestURL: navigationAction.request.url)
    }

    func navigationResponse(_ navigationResponse: NavigationResponse, didBecome download: WebKitDownload) {
        enqueueDownload(
            download,
            originalURL: navigationResponse.url,
            response: navigationResponse.response,
            requestURL: navigationResponse.response.url
        )
    }

    private func enqueueDownload(
        _ download: WebKitDownload,
        originalURL: URL,
        response: URLResponse?,
        requestURL: URL?
    ) {
        guard let wkDownload = download as? WKDownload,
              let downloadManager
        else { return }

        let suggestedFilename = DownloadFileUtilities.suggestedFilename(
            response: response,
            requestURL: requestURL,
            fallback: "download"
        )

        _ = downloadManager.addDownload(
            wkDownload,
            originalURL: originalURL,
            suggestedFilename: suggestedFilename,
            flyAnimationOriginalRect: fileIconFlyAnimationOriginalRect(in: download.targetWebView ?? download.originatingWebView)
        )
    }

    private func fileIconFlyAnimationOriginalRect(in webView: WKWebView?) -> NSRect? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let webView,
              let window = webView.window,
              let dockScreen = NSScreen.dockScreen
        else { return nil }

        let size = webView.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }

        let sourceRect = NSRect(
            x: size.width / 2 - 32,
            y: size.height / 2 - 32,
            width: 64,
            height: 64
        )
        let windowRect = webView.convert(sourceRect, to: nil)
        let globalRect = window.convertToScreen(windowRect)
        return dockScreen.convertFromGlobalScreenCoordinates(globalRect)
    }
}
