import AppKit
import Foundation
import WebKit

@MainActor
final class SumiDownloadsNavigationResponder: SumiNavigationActionResponding, SumiNavigationResponseResponding, SumiNavigationDownloadResponding {
    private weak var tab: Tab?
    private weak var downloadManager: DownloadManager?
    private var isRestoringSessionState = false
    private var pendingOpenIntents: [SumiDownloadIntentKey: SumiDownloadOpenIntent] = [:]
    private var pendingPromptRequests: [SumiDownloadIntentKey: SumiDownloadPromptRequest] = [:]

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
        let optionGlanceRequested = tab?.isGlanceTriggerActive(modifierFlags) == true
        let optionDownloadRequested = navigationAction.navigationType.isLinkActivated
            && modifierFlags.contains(.option)
            && !modifierFlags.contains(.command)
            && !optionGlanceRequested

        if optionDownloadRequested {
            return await policyForDownloadAction(navigationAction, origin: .explicitUserSave)
        }

        if navigationAction.shouldDownload && !isRestoringSessionState && !optionGlanceRequested {
            return await policyForDownloadAction(navigationAction, origin: .actionRequestedDownload)
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

        let explicitUserSave = (response.mainFrameNavigation?.redirectHistory.last
            ?? response.mainFrameNavigation?.navigationAction)?.navigationType == .custom(.userRequestedPageDownload)
        guard response.isHTTPStatusSuccessful != false,
              !response.url.hasDirectoryPath,
              !response.canShowMIMEType || response.shouldDownload || explicitUserSave
        else {
            return .next
        }

        guard firstNavigationAction?.request.cachePolicy != .returnCacheDataElseLoad,
              !isRestoringSessionState
        else {
            return .cancel
        }

        let origin: SumiDownloadOrigin
        if explicitUserSave {
            origin = .explicitUserSave
        } else if response.shouldDownload {
            origin = .responseForcedDownload
        } else {
            origin = .unshowableResponse
        }
        return await policyForDownloadResponse(response, origin: origin)
    }

    func navigationAction(_ navigationAction: SumiNavigationAction, didBecome download: SumiNavigationDownload) {
        guard let originalURL = navigationAction.url else { return }
        let suggestedFilename = navigationAction.request.url?.sumiSuggestedDownloadFilename
        enqueueDownload(
            download,
            originalURL: originalURL,
            response: nil,
            requestURL: navigationAction.request.url,
            openIntent: removePendingOpenIntent(for: intentKey(
                url: navigationAction.request.url ?? originalURL,
                suggestedFilename: suggestedFilename,
                origin: navigationAction.shouldDownload ? .actionRequestedDownload : .explicitUserSave
            )),
            promptRequest: removePendingPromptRequest(for: intentKey(
                url: navigationAction.request.url ?? originalURL,
                suggestedFilename: suggestedFilename,
                origin: navigationAction.shouldDownload ? .actionRequestedDownload : .explicitUserSave
            ))
        )
    }

    func navigationResponse(_ navigationResponse: SumiNavigationResponse, didBecome download: SumiNavigationDownload) {
        enqueueDownload(
            download,
            originalURL: navigationResponse.url,
            response: download.response,
            requestURL: download.response?.url,
            openIntent: removePendingOpenIntent(for: intentKey(
                url: download.response?.url ?? navigationResponse.url,
                suggestedFilename: DownloadFileUtilities.suggestedFilename(
                    response: download.response,
                    requestURL: download.response?.url,
                    fallback: "download"
                ),
                origin: navigationResponse.shouldDownload ? .responseForcedDownload : .unshowableResponse
            )),
            promptRequest: removePendingPromptRequest(for: intentKey(
                url: download.response?.url ?? navigationResponse.url,
                suggestedFilename: DownloadFileUtilities.suggestedFilename(
                    response: download.response,
                    requestURL: download.response?.url,
                    fallback: "download"
                ),
                origin: navigationResponse.shouldDownload ? .responseForcedDownload : .unshowableResponse
            ))
        )
    }

    private func enqueueDownload(
        _ download: SumiNavigationDownload,
        originalURL: URL,
        response: URLResponse?,
        requestURL: URL?,
        openIntent: SumiDownloadOpenIntent?,
        promptRequest: SumiDownloadPromptRequest?
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
            openIntent: openIntent,
            promptRequest: promptRequest,
            flyAnimationOriginalRect: fileIconFlyAnimationOriginalRect(in: download.targetWebView ?? download.originatingWebView)
        )
    }

    private func policyForDownloadAction(
        _ action: SumiNavigationAction,
        origin: SumiDownloadOrigin
    ) async -> SumiNavigationActionPolicy? {
        let filename = action.request.url?.sumiSuggestedDownloadFilename
        let identity = SumiDownloadContentIdentity.resolve(mimeType: nil, filename: filename)
        let resolved = resolvedAction(origin: origin, identity: identity)
        return applyResolvedAction(
            resolved,
            key: intentKey(url: action.request.url, suggestedFilename: filename, origin: origin),
            identity: identity
        )
    }

    private func policyForDownloadResponse(
        _ response: SumiNavigationResponse,
        origin: SumiDownloadOrigin
    ) async -> SumiNavigationResponsePolicy? {
        let filename = DownloadFileUtilities.suggestedFilename(
            response: response.httpResponse,
            requestURL: response.url,
            fallback: "download"
        )
        let identity = SumiDownloadContentIdentity.resolve(mimeType: response.mimeType, filename: filename)
        let resolved = resolvedAction(origin: origin, identity: identity)
        switch applyResolvedAction(
            resolved,
            key: intentKey(url: response.url, suggestedFilename: filename, origin: origin),
            identity: identity
        ) {
        case .allow:
            return .allow
        case .cancel:
            return .cancel
        case .download:
            return .download
        case nil:
            return nil
        }
    }

    private func resolvedAction(
        origin: SumiDownloadOrigin,
        identity: SumiDownloadContentIdentity
    ) -> SumiDownloadResolvedAction {
        guard let settings = downloadManager?.settings else {
            return origin == .normalNavigation ? .navigate : .saveFile
        }
        let handler = settings.downloadApplicationsStore.record(for: identity.contentType)
        let resolved = SumiDownloadPolicyResolver.resolve(
            origin: origin,
            identity: identity,
            handler: handler,
            fallback: settings.downloadsFallbackAction
        )
        return resolved
    }

    private func applyResolvedAction(
        _ action: SumiDownloadResolvedAction,
        key: SumiDownloadIntentKey?,
        identity: SumiDownloadContentIdentity
    ) -> SumiNavigationActionPolicy? {
        switch action {
        case .navigate:
            return .next
        case .saveFile:
            return .download
        case .downloadThenOpen(let intent):
            if let key {
                pendingOpenIntents[key] = intent
            }
            return .download
        case .cancel:
            return .cancel
        case .prompt(let canPersistChoice):
            if let key {
                pendingPromptRequests[key] = SumiDownloadPromptRequest(
                    identity: identity,
                    canPersistChoice: canPersistChoice
                )
            }
            return .download
        }
    }

    private func intentKey(url: URL?, suggestedFilename: String?, origin: SumiDownloadOrigin) -> SumiDownloadIntentKey? {
        guard let url else { return nil }
        return SumiDownloadIntentKey(url: url, suggestedFilename: suggestedFilename, origin: origin)
    }

    private func removePendingOpenIntent(for key: SumiDownloadIntentKey?) -> SumiDownloadOpenIntent? {
        guard let key else { return nil }
        return pendingOpenIntents.removeValue(forKey: key)
    }

    private func removePendingPromptRequest(for key: SumiDownloadIntentKey?) -> SumiDownloadPromptRequest? {
        guard let key else { return nil }
        return pendingPromptRequests.removeValue(forKey: key)
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

private struct SumiDownloadIntentKey: Hashable {
    let url: URL
    let suggestedFilename: String?
    let origin: SumiDownloadOrigin
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
