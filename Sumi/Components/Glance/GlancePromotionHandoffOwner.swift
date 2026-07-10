import Foundation
import SumiWebRuntime

@MainActor
final class GlancePromotionHandoffOwner {
    private(set) var isAnimating = false
    private var isCompletingHandoff = false

    var blocksPresentationUpdates: Bool {
        isAnimating || isCompletingHandoff
    }

    var preservesPresentedHostDuringTeardown: Bool {
        isCompletingHandoff
    }

    @discardableResult
    func beginAnimation() -> Bool {
        guard !isAnimating else { return false }
        isAnimating = true
        return true
    }

    func cancelAnimation() {
        isAnimating = false
    }

    func beginCompositorHandoff() {
        isCompletingHandoff = true
        isAnimating = false
    }

    func cancelCompositorHandoff() {
        isCompletingHandoff = false
        isAnimating = false
    }

    func reset() {
        isAnimating = false
        isCompletingHandoff = false
    }

    func registerPreviewHost(
        _ previewHostView: SumiWebViewContainerView?,
        for session: GlanceSession,
        manager: GlanceManager?,
        attachmentCompletion: @escaping PromotedHostAttachmentCompletion
    ) -> Bool {
        guard canRegisterPreviewHost(previewHostView, for: session, manager: manager),
              let previewHostView,
              manager?.registerPromotedHost(
                  previewHostView,
                  for: session,
                  attachmentCompletion: attachmentCompletion
              ) == true
        else { return false }

        previewHostView.prepareForSuperviewTransferPreservingDisplayedContent()
        return true
    }

    private func canRegisterPreviewHost(
        _ previewHostView: SumiWebViewContainerView?,
        for session: GlanceSession,
        manager: GlanceManager?
    ) -> Bool {
        guard let previewHostView,
              let webView = manager?.runtime?.previewWebView(session.previewTab),
              previewHostView.webView === webView
        else { return false }

        return true
    }
}
