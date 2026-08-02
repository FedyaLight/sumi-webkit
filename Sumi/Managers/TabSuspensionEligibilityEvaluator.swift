import Foundation
import WebKit

struct TabSuspensionWebViewState: Equatable {
    let isLoading: Bool
    let isPlayingAudio: Bool
    let isCapturingCamera: Bool
    let isCapturingMicrophone: Bool
    let isFullscreen: Bool
    let isProtectedFromCompositorMutation: Bool

    init(
        isLoading: Bool = false,
        isPlayingAudio: Bool = false,
        isCapturingCamera: Bool = false,
        isCapturingMicrophone: Bool = false,
        isFullscreen: Bool = false,
        isProtectedFromCompositorMutation: Bool = false
    ) {
        self.isLoading = isLoading
        self.isPlayingAudio = isPlayingAudio
        self.isCapturingCamera = isCapturingCamera
        self.isCapturingMicrophone = isCapturingMicrophone
        self.isFullscreen = isFullscreen
        self.isProtectedFromCompositorMutation = isProtectedFromCompositorMutation
    }

    @MainActor
    init(
        webView: WKWebView,
        isProtectedFromCompositorMutation: (WKWebView) -> Bool
    ) {
        self.init(
            isLoading: webView.isLoading,
            isPlayingAudio: webView.sumiAudioIsPlayingAudio,
            isCapturingCamera: webView.cameraCaptureState != .none,
            isCapturingMicrophone: webView.microphoneCaptureState != .none,
            isFullscreen: webView.sumiIsInFullscreenElementPresentation,
            isProtectedFromCompositorMutation: isProtectedFromCompositorMutation(webView)
        )
    }
}

@MainActor
final class TabSuspensionEligibilityEvaluator {
    func evaluateWebViews(
        liveWebViews: [WKWebView],
        isProtectedFromCompositorMutation: (WKWebView) -> Bool
    ) -> TabSuspensionEligibility {
        webViewEligibility(
            liveWebViews.map {
                TabSuspensionWebViewState(
                    webView: $0,
                    isProtectedFromCompositorMutation: isProtectedFromCompositorMutation
                )
            }
        )
    }

    func evaluate(
        tab: Tab,
        webViewStates: [TabSuspensionWebViewState],
        context: TabSuspensionEvaluationContext
    ) -> TabSuspensionEligibility {
        if let ineligibility = tabIneligibility(for: tab, context: context) {
            return ineligibility
        }

        return webViewEligibility(webViewStates)
    }

    private func webViewEligibility(
        _ webViewStates: [TabSuspensionWebViewState]
    ) -> TabSuspensionEligibility {
        guard !webViewStates.isEmpty else {
            return .ineligible(reason: .noLiveWebView)
        }
        for state in webViewStates {
            guard !state.isProtectedFromCompositorMutation else {
                return .ineligible(reason: .compositorProtected)
            }
            guard !state.isLoading else { return .ineligible(reason: .loading) }
            guard !state.isPlayingAudio else { return .ineligible(reason: .playingAudio) }
            guard !state.isCapturingCamera else { return .ineligible(reason: .cameraCapture) }
            guard !state.isCapturingMicrophone else {
                return .ineligible(reason: .microphoneCapture)
            }
            guard !state.isFullscreen else { return .ineligible(reason: .fullscreen) }
        }
        return .eligible
    }

    func tabIneligibility(
        for tab: Tab,
        context: TabSuspensionEvaluationContext
    ) -> TabSuspensionEligibility? {
        guard !context.selectedTabIDs.contains(tab.id) else {
            return .ineligible(reason: .selected)
        }
        guard !context.visibleTabIDs.contains(tab.id) else {
            return .ineligible(reason: .visible)
        }
        guard tab.requiresPrimaryWebView else { return .ineligible(reason: .noPrimaryWebView) }
        guard isSuspensibleContentURL(tab.url) else {
            return .ineligible(reason: .unsupportedURLScheme)
        }
        guard !tab.isPopupHost else { return .ineligible(reason: .popupHost) }
        guard !tab.suspensionState.isSuspended else {
            return .ineligible(reason: .alreadySuspended)
        }
        guard !tab.isLoading else { return .ineligible(reason: .loading) }
        guard !tab.audioState.isPlayingAudio else { return .ineligible(reason: .playingAudio) }
        guard !tab.mediaRuntime.hasActivePictureInPicture else {
            return .ineligible(reason: .pictureInPicture)
        }
        switch tab.committedDocumentRuntime.suspensionDecision {
        case .awaitingEvidence:
            return .ineligible(reason: .documentEvidencePending)
        case .allowed:
            break
        case .vetoed(.pageReportedUnableToSuspend):
            return .ineligible(reason: .pageVeto)
        case .vetoed(.pdfDocument):
            return .ineligible(reason: .pdfDocument)
        }
        return nil
    }

    private func isSuspensibleContentURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
