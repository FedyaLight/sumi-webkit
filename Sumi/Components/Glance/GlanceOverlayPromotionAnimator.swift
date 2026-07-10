import AppKit
import QuartzCore
import SumiWebRuntime
import WebKit

@MainActor
final class GlanceOverlayPromotionAnimator {
    private let contentShadowView: NSView
    private let webClipView: NSView
    private let actionChrome: GlanceOverlayActionChrome
    private let contentVisualStyleOwner: GlanceOverlayContentVisualStyleOwner
    private let motion: GlanceOverlayMotionController
    private let viewHierarchy: GlanceOverlayViewHierarchyOwner
    private let promotionHandoff: GlancePromotionHandoffOwner
    private let previewHostAttachment: GlancePreviewHostAttachmentOwner
    private let overlayLayout: GlanceOverlayLayout
    private let resetCloseConfirmation: () -> Void
    private let rootViewProvider: () -> GlanceOverlayRootView?
    private let configurationProvider: () -> GlanceOverlayConfiguration?
    private let sessionProvider: () -> GlanceSession?
    private let managerProvider: () -> GlanceManager?
    private let previewWebView: (GlanceSession) -> WKWebView?

    init(
        contentShadowView: NSView,
        webClipView: NSView,
        actionChrome: GlanceOverlayActionChrome,
        contentVisualStyleOwner: GlanceOverlayContentVisualStyleOwner,
        motion: GlanceOverlayMotionController,
        viewHierarchy: GlanceOverlayViewHierarchyOwner,
        promotionHandoff: GlancePromotionHandoffOwner,
        previewHostAttachment: GlancePreviewHostAttachmentOwner,
        overlayLayout: GlanceOverlayLayout,
        resetCloseConfirmation: @escaping () -> Void,
        rootViewProvider: @escaping () -> GlanceOverlayRootView?,
        configurationProvider: @escaping () -> GlanceOverlayConfiguration?,
        sessionProvider: @escaping () -> GlanceSession?,
        managerProvider: @escaping () -> GlanceManager?,
        previewWebView: @escaping (GlanceSession) -> WKWebView?
    ) {
        self.contentShadowView = contentShadowView
        self.webClipView = webClipView
        self.actionChrome = actionChrome
        self.contentVisualStyleOwner = contentVisualStyleOwner
        self.motion = motion
        self.viewHierarchy = viewHierarchy
        self.promotionHandoff = promotionHandoff
        self.previewHostAttachment = previewHostAttachment
        self.overlayLayout = overlayLayout
        self.resetCloseConfirmation = resetCloseConfirmation
        self.rootViewProvider = rootViewProvider
        self.configurationProvider = configurationProvider
        self.sessionProvider = sessionProvider
        self.managerProvider = managerProvider
        self.previewWebView = previewWebView
    }

    func animatePromotionToRegularTab() {
        guard let manager = managerProvider(),
              let session = sessionProvider(),
              let configuration = configurationProvider(),
              let rootView = rootViewProvider()
        else { return }
        guard promotionHandoff.beginAnimation() else { return }

        resetCloseConfirmation()
        rootView.acceptsBackgroundMouseEvents = false
        actionChrome.setButtonsEnabled(false)

        previewHostAttachment.attachIfAvailable(
            for: session,
            webView: previewWebView(session)
        )

        let targetFrame = overlayLayout.promotionContentFrame(
            in: rootView.bounds,
            configuration: configuration
        )
        viewHierarchy.publishContentFrame(targetFrame, in: rootView)
        viewHierarchy.layoutInteractionShield(
            in: rootView.bounds,
            contentFrame: targetFrame
        )

        let duration = motion.promotionDuration(reduceMotion: configuration.reduceMotion)
        let promotionTimingFunction = motion.promotionTimingFunction
        contentVisualStyleOwner.animateToBrowserViewportStyle(
            for: configuration,
            duration: duration,
            timingFunction: promotionTimingFunction
        )
        motion.fadeOutActionChrome(
            actionChrome: actionChrome,
            duration: duration,
            timingFunction: promotionTimingFunction
        )

        motion.animateContentFrame(
            from: contentShadowView.frame,
            to: targetFrame,
            direction: .opening,
            duration: duration
        ) { [weak self, weak manager, sessionID = session.id] in
            guard let self else { return }
            guard self.sessionProvider()?.id == sessionID else {
                self.promotionHandoff.cancelAnimation()
                self.contentVisualStyleOwner.removeAnimations()
                return
            }
            self.contentShadowView.frame = targetFrame
            self.webClipView.frame = self.contentShadowView.bounds
            self.contentVisualStyleOwner.applyBrowserViewportStyle(for: configuration)
            self.contentVisualStyleOwner.removeAnimations()
            self.completePromotionHandoff(
                sessionID: sessionID,
                manager: manager
            )
        }
    }

    private func completePromotionHandoff(
        sessionID: UUID,
        manager: GlanceManager?
    ) {
        guard sessionProvider()?.id == sessionID else {
            promotionHandoff.cancelAnimation()
            return
        }

        finishPromotionHandoff(sessionID: sessionID, manager: manager)
    }

    private func finishPromotionHandoff(
        sessionID: UUID,
        manager: GlanceManager?
    ) {
        guard let session = sessionProvider(),
              session.id == sessionID
        else {
            promotionHandoff.cancelAnimation()
            return
        }

        guard promotionHandoff.registerPreviewHost(
            previewHostAttachment.promotedHostCandidate,
            for: session,
            manager: managerProvider(),
            attachmentCompletion: { [weak self, weak manager, sessionID = session.id] outcome in
                guard let self else {
                    manager?.finishPromotedSession(sessionID: sessionID)
                    return
                }
                self.completePromotionHandoff(
                    outcome: outcome,
                    sessionID: sessionID,
                    manager: manager
                )
            }
        ) else {
            promotionHandoff.cancelAnimation()
            actionChrome.setButtonsEnabled(true)
            actionChrome.setAnimatedAlphaValue(1)
            if let configuration = configurationProvider() {
                contentVisualStyleOwner.removeAnimations()
                contentVisualStyleOwner.applyGlanceStyle(for: configuration)
            }
            return
        }

        promotionHandoff.beginCompositorHandoff()
        manager?.moveToNewTab(finishesAfterDisplayUpdate: true)
    }

    private func completePromotionHandoff(
        outcome: PromotedHostAttachmentOutcome,
        sessionID: UUID,
        manager: GlanceManager?
    ) {
        switch outcome {
        case .attached:
            completePromotionAfterCompositorAttachment(
                sessionID: sessionID,
                manager: manager
            )
        case .cancelled:
            promotionHandoff.cancelCompositorHandoff()
            manager?.finishPromotedSession(sessionID: sessionID)
        }
    }

    private func completePromotionAfterCompositorAttachment(
        sessionID: UUID,
        manager: GlanceManager?
    ) {
        guard sessionProvider()?.id == sessionID else {
            manager?.finishPromotedSession(sessionID: sessionID)
            return
        }

        viewHierarchy.hideViewsForPromotionCompletion()
        manager?.finishPromotedSession(sessionID: sessionID)
    }
}
