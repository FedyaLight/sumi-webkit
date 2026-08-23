import AppKit
import QuartzCore
import WebKit

@MainActor
final class GlanceOverlayController: NSObject {
    private weak var rootView: GlanceOverlayRootView?
    private weak var manager: GlanceManager?
    private var session: GlanceSession?
    private var configuration: GlanceOverlayConfiguration?
    private let presentationState = GlanceOverlayPresentationStateOwner()
    private let promotionHandoff = GlancePromotionHandoffOwner()
    private let overlayLayout = GlanceOverlayLayout()

    private let webContentShieldAnchorView = GlanceWebContentShieldAnchorView(frame: .zero)
    private let contentShadowView = NSView(frame: .zero)
    private let webClipView = NSView(frame: .zero)
    private lazy var contentVisualStyleOwner = GlanceOverlayContentVisualStyleOwner(
        contentShadowView: contentShadowView,
        webClipView: webClipView
    )
    private lazy var previewHostAttachment = GlancePreviewHostAttachmentOwner(
        webClipView: webClipView,
        webContentShieldAnchorView: webContentShieldAnchorView
    )
    private lazy var actionChrome = GlanceOverlayActionChrome { [weak self] action in
        self?.handleActionChromeAction(action)
    }
    private lazy var motion = GlanceOverlayMotionController(
        contentShadowView: contentShadowView,
        webClipView: webClipView
    )
    private lazy var viewHierarchy = GlanceOverlayViewHierarchyOwner(
        rootView: rootView,
        webContentShieldAnchorView: webContentShieldAnchorView,
        contentShadowView: contentShadowView,
        webClipView: webClipView,
        actionChrome: actionChrome,
        presentationState: presentationState,
        previewHostAttachment: previewHostAttachment,
        overlayLayout: overlayLayout,
        resetCloseConfirmation: { [weak self] in self?.resetCloseConfirmation() },
        configurationProvider: { [weak self] in self?.configuration },
        managerProvider: { [weak self] in self?.manager },
        sessionProvider: { [weak self] in self?.session }
    )
    private lazy var promotionAnimator = GlanceOverlayPromotionAnimator(
        contentShadowView: contentShadowView,
        webClipView: webClipView,
        actionChrome: actionChrome,
        contentVisualStyleOwner: contentVisualStyleOwner,
        motion: motion,
        viewHierarchy: viewHierarchy,
        promotionHandoff: promotionHandoff,
        previewHostAttachment: previewHostAttachment,
        overlayLayout: overlayLayout,
        resetCloseConfirmation: { [weak self] in self?.resetCloseConfirmation() },
        rootViewProvider: { [weak self] in self?.rootView },
        configurationProvider: { [weak self] in self?.configuration },
        sessionProvider: { [weak self] in self?.session },
        managerProvider: { [weak self] in self?.manager },
        previewWebView: { [weak self] session in self?.previewWebView(for: session) }
    )

    init(rootView: GlanceOverlayRootView) {
        self.rootView = rootView
        super.init()
        rootView.onLayout = { [weak self] in
            self?.rootViewDidLayout()
        }
        rootView.onBackgroundMouseDown = { [weak self] in
            self?.closeFromBackdrop()
        }
        rootView.onActionChromeMouseDown = { [weak self] point in
            self?.actionChrome.handleMouseDown(at: point, from: self?.rootView) == true
        }
        rootView.onCancelOperation = { [weak self] in
            guard self?.session != nil else { return false }
            self?.closeFromBackdrop()
            return true
        }
        configureViews()
    }

    func update(
        manager: GlanceManager,
        session: GlanceSession?,
        phase: GlancePresentationPhase,
        configuration: GlanceOverlayConfiguration
    ) {
        let previousConfiguration = self.configuration
        self.manager = manager
        self.configuration = configuration
        if previousConfiguration != configuration {
            apply(configuration: configuration)
        }
        actionChrome.isSplitEnabled = manager.canEnterSplitView

        guard let session else {
            presentationState.resetForMissingSession()
            viewHierarchy.tearDownPresentedViews(
                preservingPromotionHandoff: promotionHandoff.preservesPresentedHostDuringTeardown
            )
            promotionHandoff.reset()
            self.session = nil
            return
        }

        if presentationState.displayedSessionID != session.id {
            self.session = session
            presentationState.display(sessionID: session.id)
            if configuration.isVisible {
                presentWhenReady(session: session, configuration: configuration)
            } else {
                viewHierarchy.installViewsIfNeeded()
                previewHostAttachment.attachIfAvailable(
                    for: session,
                    webView: previewWebView(for: session)
                )
                viewHierarchy.setPresentationVisible(false)
            }
            return
        }

        self.session = session
        if !configuration.isVisible {
            presentationState.clearPendingPresentation()
            viewHierarchy.setPresentationVisible(false)
            return
        }

        if !presentationState.isPresentationVisible {
            viewHierarchy.setPresentationVisible(true)
            layoutForCurrentBounds(animated: false)
            return
        }

        if phase == .closing, !presentationState.isAnimatingClose {
            presentationState.clearPendingPresentation()
            animateClose(session: session, configuration: configuration)
        } else if presentationState.pendingPresentationSessionID == session.id {
            presentationState.queuePendingPresentation(session: session, configuration: configuration)
            _ = presentPendingIfPossible()
        } else if phase == .opening {
            previewHostAttachment.attachIfAvailable(
                for: session,
                webView: previewWebView(for: session)
            )
        } else {
            layoutForCurrentBounds(animated: phase == .open && !configuration.reduceMotion)
        }
    }

    func tearDown() {
        dismissSessionIfStillOwned()
        presentationState.prepareForTearDown()
        promotionHandoff.reset()
        viewHierarchy.tearDownPresentedViews()
        rootView?.onLayout = nil
        rootView?.onBackgroundMouseDown = nil
        rootView?.onActionChromeMouseDown = nil
        rootView?.onCancelOperation = nil
    }

    private func dismissSessionIfStillOwned() {
        guard let manager,
              let session,
              manager.currentSession?.id == session.id,
              manager.phase != .promoting
        else { return }

        manager.dismissGlance(persistsWindowSession: false)
    }

    private func rootViewDidLayout() {
        guard configuration?.isVisible == true,
              !promotionHandoff.blocksPresentationUpdates
        else { return }
        if presentPendingIfPossible() {
            return
        }
        if manager?.phase == .opening, let session {
            previewHostAttachment.attachIfAvailable(
                for: session,
                webView: previewWebView(for: session)
            )
            return
        }
        layoutForCurrentBounds(animated: false)
    }

    private func presentWhenReady(
        session: GlanceSession,
        configuration: GlanceOverlayConfiguration
    ) {
        presentationState.queuePendingPresentation(session: session, configuration: configuration)
        guard !presentPendingIfPossible() else { return }
        rootView?.needsLayout = true
    }

    @discardableResult
    private func presentPendingIfPossible() -> Bool {
        guard let rootView,
              rootView.bounds.width > 1,
              rootView.bounds.height > 1,
              let pendingPresentation = presentationState.takePendingPresentation()
        else { return false }

        present(
            session: pendingPresentation.session,
            configuration: pendingPresentation.configuration
        )
        return true
    }

    private func configureViews() {
        contentVisualStyleOwner.configureViews()
        _ = actionChrome
        _ = viewHierarchy
        _ = promotionAnimator
    }

    private func apply(configuration: GlanceOverlayConfiguration) {
        if !promotionHandoff.blocksPresentationUpdates {
            contentVisualStyleOwner.applyGlanceStyle(for: configuration)
        }
        actionChrome.apply(accentColor: configuration.accentColor)
    }

    private func present(
        session: GlanceSession,
        configuration: GlanceOverlayConfiguration
    ) {
        guard let rootView else { return }

        presentationState.beginOpening()
        viewHierarchy.installViewsIfNeeded()
        viewHierarchy.preparePresentSurface()
        resetCloseConfirmation()
        previewHostAttachment.attachIfAvailable(
            for: session,
            webView: previewWebView(for: session)
        )

        let targetFrame = overlayLayout.targetContentFrame(in: rootView.bounds, configuration: configuration)
        let startFrame = overlayLayout.startContentFrame(
            originFrameInRootBounds: rootView.convert(session.originRectInWindow, from: nil),
            rootBounds: rootView.bounds,
            targetFrame: targetFrame
        )
        viewHierarchy.publishContentFrame(targetFrame, in: rootView)

        contentShadowView.frame = configuration.reduceMotion ? targetFrame : startFrame
        webClipView.frame = contentShadowView.bounds
        contentShadowView.alphaValue = configuration.reduceMotion ? 0 : 1
        actionChrome.alphaValue = 0
        viewHierarchy.layoutActionChrome(for: targetFrame, configuration: configuration)
        viewHierarchy.layoutInteractionShield(in: rootView.bounds, contentFrame: targetFrame)

        let duration = motion.duration(reduceMotion: configuration.reduceMotion, kind: .glance)
        if configuration.reduceMotion {
            motion.runReducedMotionOpen(targetFrame: targetFrame, duration: duration)
            scheduleOpeningCompletion(
                sessionID: session.id,
                targetFrame: targetFrame,
                configuration: configuration,
                after: duration
            )
            return
        }

        // Match prior non-reduced open: run an empty easeInEaseOut group for duration parity.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }

        motion.animateContentFrame(
            from: startFrame,
            to: targetFrame,
            direction: .opening,
            duration: duration
        ) { [weak self] in
            guard let self else { return }
            self.finishOpening(sessionID: session.id, targetFrame: targetFrame, configuration: configuration)
        }
    }

    private func finishOpening(
        sessionID: UUID,
        targetFrame: CGRect,
        configuration: GlanceOverlayConfiguration
    ) {
        guard session?.id == sessionID else { return }
        contentShadowView.frame = targetFrame
        webClipView.frame = contentShadowView.bounds
        manager?.markOpened(sessionID: sessionID)
        guard presentationState.isPresentationVisible,
              self.configuration?.isVisible == true
        else {
            viewHierarchy.publishContentFrame(nil, in: rootView)
            return
        }

        viewHierarchy.publishContentFrame(targetFrame, in: rootView)
        motion.animateButtonsIn(actionChrome: actionChrome, configuration: configuration)
    }

    private func animateClose(
        session: GlanceSession,
        configuration: GlanceOverlayConfiguration
    ) {
        guard let rootView else {
            manager?.finishAnimatedDismissal(sessionID: session.id)
            return
        }
        presentationState.beginClosing()
        resetCloseConfirmation()

        let targetFrame = overlayLayout.targetContentFrame(in: rootView.bounds, configuration: configuration)
        let endFrame = overlayLayout.startContentFrame(
            originFrameInRootBounds: rootView.convert(session.originRectInWindow, from: nil),
            rootBounds: rootView.bounds,
            targetFrame: targetFrame
        )
        let duration = motion.duration(reduceMotion: configuration.reduceMotion, kind: .glance)

        if configuration.reduceMotion {
            motion.runReducedMotionClose(
                actionChrome: actionChrome,
                targetFrame: targetFrame,
                duration: duration
            )
            scheduleClosingCompletion(sessionID: session.id, after: duration)
            return
        }

        motion.fadeOutActionChrome(actionChrome: actionChrome, duration: duration)
        motion.animateContentFrame(
            from: targetFrame,
            to: endFrame,
            direction: .closing,
            duration: duration
        ) { [weak self] in
            self?.finishClosing(sessionID: session.id)
        }
    }

    private func finishClosing(sessionID: UUID) {
        guard session?.id == sessionID else { return }
        presentationState.finishClosing()
        viewHierarchy.tearDownPresentedViews()
        manager?.finishAnimatedDismissal(sessionID: sessionID)
    }

    private func scheduleOpeningCompletion(
        sessionID: UUID,
        targetFrame: CGRect,
        configuration: GlanceOverlayConfiguration,
        after duration: TimeInterval
    ) {
        presentationState.schedulePostAnimationCompletion(
            sessionID: sessionID,
            after: duration
        ) { [weak self] in
            self?.finishOpening(
                sessionID: sessionID,
                targetFrame: targetFrame,
                configuration: configuration
            )
        }
    }

    private func scheduleClosingCompletion(sessionID: UUID, after duration: TimeInterval) {
        presentationState.schedulePostAnimationCompletion(
            sessionID: sessionID,
            after: duration
        ) { [weak self] in
            self?.finishClosing(sessionID: sessionID)
        }
    }

    private func layoutForCurrentBounds(animated: Bool) {
        guard let rootView,
              let configuration,
              configuration.isVisible,
              session != nil,
              !presentationState.isAnimatingClose,
              !promotionHandoff.blocksPresentationUpdates
        else { return }

        let targetFrame = overlayLayout.targetContentFrame(in: rootView.bounds, configuration: configuration)
        let updates = {
            if let session = self.session {
                self.previewHostAttachment.attachIfAvailable(
                    for: session,
                    webView: self.previewWebView(for: session)
                )
            }
            self.contentShadowView.frame = targetFrame
            self.webClipView.frame = self.contentShadowView.bounds
            self.viewHierarchy.publishContentFrame(targetFrame, in: rootView)
            self.viewHierarchy.layoutActionChrome(for: targetFrame, configuration: configuration)
            self.viewHierarchy.layoutInteractionShield(in: rootView.bounds, contentFrame: targetFrame)
        }

        motion.runLayoutUpdates(animated: animated, updates: updates)
    }

    private func closeFromBackdrop() {
        guard !promotionHandoff.isAnimating else { return }
        guard let session = manager?.beginAnimatedDismissal(),
              let configuration
        else { return }
        animateClose(session: session, configuration: configuration)
    }

    private func handleActionChromeAction(_ action: GlanceOverlayActionChrome.Action) {
        switch action {
        case .close:
            closeButtonPressed()
        case .open:
            openButtonPressed()
        case .split:
            splitButtonPressed()
        }
    }

    private func closeButtonPressed() {
        guard !promotionHandoff.isAnimating else { return }
        guard let manager,
              let session,
              let configuration
        else { return }

        if actionChrome.closeRequiresSecondPress == false,
           webContentIsFocused() {
            actionChrome.closeRequiresSecondPress = true
            scheduleCloseConfirmationReset()
            return
        }

        guard manager.beginAnimatedDismissal() != nil else { return }
        animateClose(session: session, configuration: configuration)
    }

    private func openButtonPressed() {
        promotionAnimator.animatePromotionToRegularTab()
    }

    private func splitButtonPressed() {
        guard !promotionHandoff.isAnimating else { return }
        guard actionChrome.isSplitEnabled else { return }
        manager?.moveToSplitView()
    }

    private func webContentIsFocused() -> Bool {
        guard let session,
              let webView = previewWebView(for: session),
              let firstResponder = webView.window?.firstResponder
        else { return false }

        if firstResponder === webView { return true }
        if let view = firstResponder as? NSView {
            return view.isDescendant(of: webView)
        }
        return false
    }

    private func previewWebView(for session: GlanceSession) -> WKWebView? {
        manager?.runtime?.previewWebView(session.previewTab)
    }

    private func scheduleCloseConfirmationReset() {
        presentationState.cancelCloseConfirmationReset()
        let item = DispatchWorkItem { [weak self] in
            self?.resetCloseConfirmation()
        }
        presentationState.installCloseConfirmationReset(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    private func resetCloseConfirmation() {
        presentationState.cancelCloseConfirmationReset()
        actionChrome.closeRequiresSecondPress = false
    }
}
