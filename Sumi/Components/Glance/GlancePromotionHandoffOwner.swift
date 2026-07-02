import Foundation

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

    func reset() {
        isAnimating = false
        isCompletingHandoff = false
    }

    func registerPreviewHost(
        _ previewHostView: SumiWebViewContainerView?,
        for session: GlanceSession,
        manager: GlanceManager?,
        attachmentCompletion: @escaping @MainActor () -> Void
    ) -> Bool {
        guard canRegisterPreviewHost(previewHostView, for: session),
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
        for session: GlanceSession
    ) -> Bool {
        guard let previewHostView,
              let webView = session.previewTab.existingWebView,
              previewHostView.webView === webView
        else { return false }

        return true
    }
}
