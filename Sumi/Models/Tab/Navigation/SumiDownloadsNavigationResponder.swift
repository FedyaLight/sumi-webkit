import AppKit
import Foundation
import WebKit

@MainActor
final class SumiDownloadsNavigationResponder: SumiNavigationActionResponding, SumiNavigationResponseResponding, SumiNavigationDownloadResponding {
    private weak var tab: Tab?
    private weak var downloadManager: DownloadManager?
    private var isRestoringSessionState = false

    init(tab: Tab, downloadManager: DownloadManager?) {
        self.tab = tab
        self.downloadManager = downloadManager
    }

    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        preferences _: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.downloadActionResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.downloadActionResponder", signpostState)
        }

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

        let actionModifierFlags = navigationAction.modifierFlags.intersection([.command, .option, .control, .shift])
        let modifierFlags = tab?.resolvedNavigationModifierFlags(actionFlags: actionModifierFlags)
            ?? navigationAction.modifierFlags
        let optionDownloadRequested = navigationAction.navigationType.isLinkActivated
            && modifierFlags.contains(.option)
            && !modifierFlags.contains(.command)

        if (navigationAction.shouldDownload && !isRestoringSessionState) || optionDownloadRequested {
            return .download
        }

        return .next
    }

    func decidePolicy(for response: SumiNavigationResponse) async -> SumiNavigationResponsePolicy? {
        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.downloadResponseResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.downloadResponseResponder", signpostState)
        }

        let firstNavigationAction = response.mainFrameNavigation?.redirectHistory.first
            ?? response.mainFrameNavigation?.navigationAction

        guard response.isHTTPStatusSuccessful != false,
              !response.url.hasDirectoryPath,
              !response.canShowMIMEType || response.shouldDownload
                || (response.mainFrameNavigation?.redirectHistory.last
                    ?? response.mainFrameNavigation?.navigationAction)?.navigationType == .custom(.userRequestedPageDownload)
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

    func navigationAction(_ navigationAction: SumiNavigationAction, didBecome download: SumiNavigationDownload) {
        guard let originalURL = navigationAction.url else { return }
        enqueueDownload(download, originalURL: originalURL, response: nil, requestURL: navigationAction.request.url)
    }

    func navigationResponse(_ navigationResponse: SumiNavigationResponse, didBecome download: SumiNavigationDownload) {
        enqueueDownload(
            download,
            originalURL: navigationResponse.url,
            response: download.response,
            requestURL: download.response?.url
        )
    }

    private func enqueueDownload(
        _ download: SumiNavigationDownload,
        originalURL: URL,
        response: URLResponse?,
        requestURL: URL?
    ) {
        guard let wkDownload = download.webKitDownload,
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

private extension SumiNavigationAction {
    var sumiIsUserEnteredURL: Bool {
        if case .other = navigationType,
           case .user = request.attribution {
            return true
        } else if case .custom(.userEnteredURL) = navigationType {
            return true
        }
        return false
    }

    var sumiIsCustom: Bool {
        if case .custom = navigationType {
            return true
        }
        return false
    }
}
