import AppKit
import WebKit

@MainActor
final class GlancePreviewHostAttachmentOwner {
    private let webClipView: NSView
    private let webContentShieldAnchorView: NSView
    private weak var previewWebView: FocusableWKWebView?
    private var previewHostView: SumiWebViewContainerView?

    var promotedHostCandidate: SumiWebViewContainerView? {
        previewHostView
    }

    init(
        webClipView: NSView,
        webContentShieldAnchorView: NSView
    ) {
        self.webClipView = webClipView
        self.webContentShieldAnchorView = webContentShieldAnchorView
    }

    func attachIfAvailable(for session: GlanceSession?) {
        guard let session,
              let webView = session.previewTab.existingWebView
        else { return }

        markPreviewWebView(webView)
        let hostView: SumiWebViewContainerView
        if let existingHost = previewHostView,
           existingHost.tabID == session.previewTab.id,
           existingHost.webView === webView {
            hostView = existingHost
        } else {
            webClipView.subviews.forEach { $0.removeFromSuperview() }
            hostView = SumiWebViewContainerView(tab: session.previewTab, webView: webView)
            previewHostView = hostView
        }

        guard hostView.superview !== webClipView else {
            hostView.frame = webClipView.bounds
            hostView.attachDisplayedContentIfNeeded()
            return
        }

        hostView.prepareForSuperviewTransferPreservingDisplayedContent()
        hostView.removeFromSuperview()
        webClipView.addSubview(hostView)
        hostView.frame = webClipView.bounds
        hostView.autoresizingMask = [.width, .height]
        hostView.attachDisplayedContentIfNeeded()
        WebContentMouseTrackingShield.refresh(for: webContentShieldAnchorView)
    }

    func clear(preservingDisplayedContent: Bool) {
        clearPreviewWebViewFlags()
        if preservingDisplayedContent {
            previewHostView?.prepareForSuperviewTransferPreservingDisplayedContent()
        } else {
            webClipView.subviews.forEach { $0.removeFromSuperview() }
        }
        previewHostView = nil
    }

    private func markPreviewWebView(_ webView: WKWebView) {
        guard let focusableWebView = webView as? FocusableWKWebView else { return }
        let alreadyPrepared = previewWebView === focusableWebView
            && focusableWebView.isTransientChromeMouseTrackingSuppressionExempt
            && focusableWebView.keepsWebKitMouseTrackingDuringLoad
            && focusableWebView.stabilizesCursorDuringGlancePresentation
        guard !alreadyPrepared else {
            return
        }

        if previewWebView !== focusableWebView {
            clearPreviewWebViewFlags()
            previewWebView = focusableWebView
        }

        let needsManualRefresh = focusableWebView.stabilizesCursorDuringGlancePresentation
        focusableWebView.isTransientChromeMouseTrackingSuppressionExempt = true
        focusableWebView.keepsWebKitMouseTrackingDuringLoad = true
        focusableWebView.stabilizesCursorDuringGlancePresentation = true
        if needsManualRefresh {
            focusableWebView.refreshMouseTrackingForGlancePresentation()
        }
    }

    private func clearPreviewWebViewFlags() {
        guard let previewWebView else { return }
        self.previewWebView = nil
        previewWebView.stabilizesCursorDuringGlancePresentation = false
        previewWebView.isTransientChromeMouseTrackingSuppressionExempt = false
        previewWebView.keepsWebKitMouseTrackingDuringLoad = false
    }
}
