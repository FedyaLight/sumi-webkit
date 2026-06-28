import AppKit
import QuartzCore
import WebKit

@MainActor
final class GlanceOverlayController: NSObject {
    private weak var rootView: GlanceOverlayRootView?
    private weak var manager: GlanceManager?
    private var session: GlanceSession?
    private var configuration: GlanceOverlayConfiguration?
    private var keyMonitor: Any?
    private let presentationState = GlanceOverlayPresentationStateOwner()
    private let promotionHandoff = GlancePromotionHandoffOwner()
    private let overlayLayout = GlanceOverlayLayout()
    private lazy var contentVisualStyleOwner = GlanceOverlayContentVisualStyleOwner(
        contentShadowView: contentShadowView,
        webClipView: webClipView
    )
    private weak var previewWebView: FocusableWKWebView?
    private var previewHostView: SumiWebViewContainerView?

    private let webContentShieldAnchorView = GlanceWebContentShieldAnchorView(frame: .zero)
    private let contentShadowView = NSView(frame: .zero)
    private let webClipView = NSView(frame: .zero)
    private lazy var actionChrome = GlanceOverlayActionChrome { [weak self] action in
        self?.handleActionChromeAction(action)
    }

    private enum Motion {
        static let glanceDuration: TimeInterval = 0.35
        static let reducedMotionDuration: TimeInterval = 0.08
        static let layoutDuration: TimeInterval = 0.16
        static let buttonDuration: TimeInterval = 0.2
        static let buttonOffset: CGFloat = 20
    }

    private enum AnimationDirection {
        case opening
        case closing
    }

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
            uninstallKeyMonitor()
            tearDownPresentedViews(
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
                installViewsIfNeeded()
                attachPreviewWebViewIfAvailable(for: session)
                setPresentationVisible(false)
            }
            return
        }

        self.session = session
        if !configuration.isVisible {
            presentationState.clearPendingPresentation()
            setPresentationVisible(false)
            return
        }

        if !presentationState.isPresentationVisible {
            setPresentationVisible(true)
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
            attachPreviewWebViewIfAvailable(for: session)
        } else {
            layoutForCurrentBounds(animated: phase == .open && !configuration.reduceMotion)
        }
    }

    func tearDown() {
        presentationState.prepareForTearDown()
        promotionHandoff.reset()
        uninstallKeyMonitor()
        tearDownPresentedViews()
        rootView?.onLayout = nil
        rootView?.onBackgroundMouseDown = nil
        rootView?.onActionChromeMouseDown = nil
    }

    private func rootViewDidLayout() {
        guard configuration?.isVisible == true,
              !promotionHandoff.blocksPresentationUpdates
        else { return }
        if presentPendingIfPossible() {
            return
        }
        if manager?.phase == .opening {
            attachPreviewWebViewIfAvailable(for: session)
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
    }

    private func apply(configuration: GlanceOverlayConfiguration) {
        contentVisualStyleOwner.applySurfaceColor(configuration.surfaceColor)
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
        installViewsIfNeeded()
        rootView.acceptsBackgroundMouseEvents = true
        contentShadowView.isHidden = false
        actionChrome.isHidden = false
        webContentShieldAnchorView.isHidden = false
        installKeyMonitorIfNeeded()
        resetCloseConfirmation()
        attachPreviewWebViewIfAvailable(for: session)

        let targetFrame = overlayLayout.targetContentFrame(in: rootView.bounds, configuration: configuration)
        let startFrame = overlayLayout.startContentFrame(
            originFrameInRootBounds: rootView.convert(session.originRectInWindow, from: nil),
            rootBounds: rootView.bounds,
            targetFrame: targetFrame
        )
        publishContentFrame(targetFrame, in: rootView)

        contentShadowView.frame = configuration.reduceMotion ? targetFrame : startFrame
        webClipView.frame = contentShadowView.bounds
        contentShadowView.alphaValue = configuration.reduceMotion ? 0 : 1
        actionChrome.alphaValue = 0
        layoutActionChrome(for: targetFrame, configuration: configuration)
        layoutInteractionShield(in: rootView.bounds, contentFrame: targetFrame)

        let duration = configuration.reduceMotion ? Motion.reducedMotionDuration : Motion.glanceDuration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if configuration.reduceMotion {
                contentShadowView.animator().frame = targetFrame
                contentShadowView.animator().alphaValue = 1
            }
        }

        guard !configuration.reduceMotion else {
            scheduleOpeningCompletion(
                sessionID: session.id,
                targetFrame: targetFrame,
                configuration: configuration,
                after: duration
            )
            return
        }

        animateContentFrame(
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
            publishContentFrame(nil, in: rootView)
            return
        }

        publishContentFrame(targetFrame, in: rootView)
        animateButtonsIn(configuration: configuration)
    }

    private func animateButtonsIn(configuration: GlanceOverlayConfiguration) {
        let duration = configuration.reduceMotion ? Motion.reducedMotionDuration : Motion.buttonDuration
        let finalFrame = actionChrome.frame
        if !configuration.reduceMotion {
            let xOffset = configuration.sidebarPosition == .right
                ? Motion.buttonOffset
                : -Motion.buttonOffset
            actionChrome.frame = finalFrame.offsetBy(dx: xOffset, dy: 0)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            actionChrome.setAnimatedFrame(finalFrame)
            actionChrome.setAnimatedAlphaValue(1)
        }
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
        let duration = configuration.reduceMotion ? Motion.reducedMotionDuration : Motion.glanceDuration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            actionChrome.setAnimatedAlphaValue(0)
            if configuration.reduceMotion {
                contentShadowView.animator().alphaValue = 0
                contentShadowView.animator().frame = targetFrame
            }
        }

        guard !configuration.reduceMotion else {
            scheduleClosingCompletion(sessionID: session.id, after: duration)
            return
        }

        animateContentFrame(
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
        tearDownPresentedViews()
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

    private func animateContentFrame(
        from startFrame: CGRect,
        to endFrame: CGRect,
        direction: AnimationDirection,
        duration: TimeInterval,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        guard startFrame != endFrame, duration > 0 else {
            contentShadowView.frame = endFrame
            webClipView.frame = contentShadowView.bounds
            completion()
            return
        }

        contentShadowView.frame = startFrame
        webClipView.frame = contentShadowView.bounds

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timingFunction(for: direction)
            contentShadowView.animator().frame = endFrame
            webClipView.animator().frame = CGRect(origin: .zero, size: endFrame.size)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.contentShadowView.frame = endFrame
                self.webClipView.frame = self.contentShadowView.bounds
                completion()
            }
        }
    }

    private func timingFunction(for direction: AnimationDirection) -> CAMediaTimingFunction {
        switch direction {
        case .opening:
            return CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        case .closing:
            return CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1)
        }
    }

    private func installViewsIfNeeded() {
        guard let rootView else { return }
        rootView.wantsLayer = true

        if webContentShieldAnchorView.superview == nil {
            rootView.addSubview(webContentShieldAnchorView)
        }
        if contentShadowView.superview == nil {
            rootView.addSubview(contentShadowView)
        }
        if webClipView.superview == nil {
            contentShadowView.addSubview(webClipView)
        }
        actionChrome.install(in: rootView)
    }

    private func tearDownPresentedViews(preservingPromotionHandoff: Bool = false) {
        resetCloseConfirmation()
        presentationState.setPresentationVisible(false)
        publishContentFrame(nil, in: rootView)
        WebContentMouseTrackingShield.unregister(webContentShieldAnchorView)
        rootView?.acceptsBackgroundMouseEvents = false
        rootView?.sidebarPassthroughRect = nil
        rootView?.webContentCursorExclusionRect = nil
        rootView?.chromeCursorExclusionRect = nil
        clearPreviewWebView()
        if preservingPromotionHandoff {
            previewHostView?.prepareForSuperviewTransferPreservingDisplayedContent()
        } else {
            webClipView.subviews.forEach { $0.removeFromSuperview() }
        }
        previewHostView = nil
        webContentShieldAnchorView.removeFromSuperview()
        actionChrome.removeFromSuperview()
        contentShadowView.removeFromSuperview()
    }

    private func setPresentationVisible(_ isVisible: Bool) {
        presentationState.setPresentationVisible(isVisible)
        rootView?.acceptsBackgroundMouseEvents = isVisible
        contentShadowView.isHidden = !isVisible
        actionChrome.isHidden = !isVisible
        webContentShieldAnchorView.isHidden = !isVisible

        if isVisible {
            installKeyMonitorIfNeeded()
            contentShadowView.alphaValue = 1
            actionChrome.alphaValue = 1
        } else {
            uninstallKeyMonitor()
            publishContentFrame(nil, in: rootView)
            WebContentMouseTrackingShield.unregister(webContentShieldAnchorView)
            rootView?.sidebarPassthroughRect = nil
            rootView?.webContentCursorExclusionRect = nil
            rootView?.chromeCursorExclusionRect = nil
            resetCloseConfirmation()
        }
    }

    private func attachPreviewWebViewIfAvailable(for session: GlanceSession?) {
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
            clearPreviewWebView()
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

    private func clearPreviewWebView() {
        guard let previewWebView else { return }
        self.previewWebView = nil
        previewWebView.stabilizesCursorDuringGlancePresentation = false
        previewWebView.isTransientChromeMouseTrackingSuppressionExempt = false
        previewWebView.keepsWebKitMouseTrackingDuringLoad = false
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
            self.attachPreviewWebViewIfAvailable(for: self.session)
            self.contentShadowView.frame = targetFrame
            self.webClipView.frame = self.contentShadowView.bounds
            self.publishContentFrame(targetFrame, in: rootView)
            self.layoutActionChrome(for: targetFrame, configuration: configuration)
            self.layoutInteractionShield(in: rootView.bounds, contentFrame: targetFrame)
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.layoutDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                updates()
            }
        } else {
            updates()
        }
    }

    private func layoutActionChrome(
        for contentFrame: CGRect,
        configuration: GlanceOverlayConfiguration
    ) {
        let exclusionRect = actionChrome.layout(
            for: contentFrame,
            in: rootView?.bounds ?? contentFrame,
            sidebarPosition: configuration.sidebarPosition,
            using: overlayLayout
        )
        rootView?.chromeCursorExclusionRect = exclusionRect
    }

    private func layoutInteractionShield(
        in bounds: CGRect,
        contentFrame: CGRect
    ) {
        webContentShieldAnchorView.frame = bounds
        rootView?.sidebarPassthroughRect = configuration.flatMap {
            overlayLayout.sidebarPassthroughRect(in: bounds, configuration: $0)
        }
        rootView?.webContentCursorExclusionRect = contentFrame
        WebContentMouseTrackingShield.setActive(
            bounds.width > 0 && bounds.height > 0,
            for: webContentShieldAnchorView,
            excludingWebContentIn: webClipView,
            coversAllWebContent: true
        )
    }

    private func publishContentFrame(_ frame: CGRect?, in rootView: NSView?) {
        guard let manager,
              let session
        else { return }

        guard let rootView,
              let swiftUIFrame = overlayLayout.swiftUIContentFrame(
                  frame,
                  rootBoundsHeight: rootView.bounds.height,
                  isRootViewFlipped: rootView.isFlipped
              )
        else {
            manager.updateContentFrameInWindowSpace(nil, sessionID: session.id)
            return
        }
        manager.updateContentFrameInWindowSpace(swiftUIFrame, sessionID: session.id)
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let session = self.session,
                  let rootWindow = self.rootView?.window,
                  event.window === rootWindow,
                  event.keyCode == 53
            else { return event }

            if self.manager?.browserManager?.dismissFloatingBarIfVisible(in: session.windowId) == true {
                return nil
            }

            if self.manager?.browserManager?.findManager.isFindBarVisible == true {
                self.manager?.browserManager?.findManager.hideFindBar()
                return nil
            }

            self.closeFromBackdrop()
            return nil
        }
    }

    private func uninstallKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
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
        animatePromotionToRegularTab()
    }

    private func splitButtonPressed() {
        guard !promotionHandoff.isAnimating else { return }
        guard actionChrome.isSplitEnabled else { return }
        manager?.moveToSplitView()
    }

    private func animatePromotionToRegularTab() {
        guard let manager,
              let session,
              let configuration,
              let rootView
        else { return }
        guard promotionHandoff.beginAnimation() else { return }

        resetCloseConfirmation()
        rootView.acceptsBackgroundMouseEvents = false
        actionChrome.setButtonsEnabled(false)

        attachPreviewWebViewIfAvailable(for: session)

        let targetFrame = overlayLayout.promotionContentFrame(in: rootView.bounds, configuration: configuration)
        publishContentFrame(targetFrame, in: rootView)
        layoutInteractionShield(in: rootView.bounds, contentFrame: targetFrame)

        let duration = min(
            configuration.reduceMotion ? Motion.reducedMotionDuration : Motion.glanceDuration,
            0.28
        )
        let promotionTimingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        contentVisualStyleOwner.animateToBrowserViewportStyle(
            for: configuration,
            duration: duration,
            timingFunction: promotionTimingFunction
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = promotionTimingFunction
            actionChrome.setAnimatedAlphaValue(0)
        }

        animateContentFrame(
            from: contentShadowView.frame,
            to: targetFrame,
            direction: .opening,
            duration: duration
        ) { [weak self, weak manager, sessionID = session.id] in
            guard let self else { return }
            guard self.session?.id == sessionID else {
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
        guard session?.id == sessionID else {
            promotionHandoff.cancelAnimation()
            return
        }

        finishPromotionHandoff(sessionID: sessionID, manager: manager)
    }

    private func finishPromotionHandoff(
        sessionID: UUID,
        manager: GlanceManager?
    ) {
        guard let session,
              session.id == sessionID
        else {
            promotionHandoff.cancelAnimation()
            return
        }

        guard promotionHandoff.registerPreviewHost(
            previewHostView,
            for: session,
            manager: self.manager,
            attachmentCompletion: { [weak self, weak manager, sessionID = session.id] in
                guard let self,
                      self.session?.id == sessionID
                else {
                    manager?.finishPromotedSession(sessionID: sessionID)
                    return
                }
                self.completePromotionAfterCompositorAttachment(sessionID: sessionID, manager: manager)
            }
        ) else {
            promotionHandoff.cancelAnimation()
            actionChrome.setButtonsEnabled(true)
            actionChrome.setAnimatedAlphaValue(1)
            if let configuration {
                contentVisualStyleOwner.removeAnimations()
                contentVisualStyleOwner.applyGlanceStyle(for: configuration)
            }
            return
        }

        promotionHandoff.beginCompositorHandoff()
        manager?.moveToNewTab(finishesAfterDisplayUpdate: true)
    }

    private func completePromotionAfterCompositorAttachment(
        sessionID: UUID,
        manager: GlanceManager?
    ) {
        guard session?.id == sessionID else {
            manager?.finishPromotedSession(sessionID: sessionID)
            return
        }

        rootView?.acceptsBackgroundMouseEvents = false
        contentShadowView.isHidden = true
        actionChrome.isHidden = true
        webContentShieldAnchorView.isHidden = true
        manager?.finishPromotedSession(sessionID: sessionID)
    }

    private func webContentIsFocused() -> Bool {
        guard let webView = session?.previewTab.existingWebView,
              let firstResponder = webView.window?.firstResponder
        else { return false }

        if firstResponder === webView { return true }
        if let view = firstResponder as? NSView {
            return view.isDescendant(of: webView)
        }
        return false
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

@MainActor
private final class GlanceOverlayContentVisualStyleOwner {
    private struct Style {
        let cornerRadius: CGFloat
        let shadowOpacity: Float
        let shadowRadius: CGFloat
        let shadowOffset: CGSize
    }

    private let contentShadowView: NSView
    private let webClipView: NSView

    init(
        contentShadowView: NSView,
        webClipView: NSView
    ) {
        self.contentShadowView = contentShadowView
        self.webClipView = webClipView
    }

    func configureViews() {
        contentShadowView.wantsLayer = true
        contentShadowView.layer?.shadowColor = NSColor.black.cgColor
        contentShadowView.layer?.shadowOpacity = GlanceOverlayLayout.Metrics.glanceShadowOpacity
        contentShadowView.layer?.shadowRadius = GlanceOverlayLayout.Metrics.glanceShadowRadius
        contentShadowView.layer?.shadowOffset = GlanceOverlayLayout.Metrics.glanceShadowOffset
        if #available(macOS 10.15, *) {
            contentShadowView.layer?.cornerCurve = .continuous
        }

        webClipView.wantsLayer = true
        webClipView.layer?.masksToBounds = true
        webClipView.autoresizingMask = [.width, .height]
        if #available(macOS 10.15, *) {
            webClipView.layer?.cornerCurve = .continuous
        }
    }

    func applySurfaceColor(_ surfaceColor: NSColor) {
        contentShadowView.layer?.backgroundColor = surfaceColor.cgColor
        webClipView.layer?.backgroundColor = surfaceColor.cgColor
    }

    func applyGlanceStyle(for configuration: GlanceOverlayConfiguration) {
        apply(style: Self.glanceStyle(for: configuration))
    }

    func applyBrowserViewportStyle(for configuration: GlanceOverlayConfiguration) {
        apply(style: Self.browserViewportStyle(for: configuration))
    }

    func animateToBrowserViewportStyle(
        for configuration: GlanceOverlayConfiguration,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        animate(
            to: Self.browserViewportStyle(for: configuration),
            duration: duration,
            timingFunction: timingFunction
        )
    }

    func removeAnimations() {
        let keys = [
            "cornerRadius",
            "shadowOpacity",
            "shadowRadius",
            "shadowOffset",
        ]
        for key in keys {
            contentShadowView.layer?.removeAnimation(forKey: "glancePromotion.\(key)")
            webClipView.layer?.removeAnimation(forKey: "glancePromotion.\(key)")
        }
    }

    private static func glanceStyle(
        for configuration: GlanceOverlayConfiguration
    ) -> Style {
        Style(
            cornerRadius: configuration.cornerRadius,
            shadowOpacity: GlanceOverlayLayout.Metrics.glanceShadowOpacity,
            shadowRadius: GlanceOverlayLayout.Metrics.glanceShadowRadius,
            shadowOffset: GlanceOverlayLayout.Metrics.glanceShadowOffset
        )
    }

    private static func browserViewportStyle(
        for configuration: GlanceOverlayConfiguration
    ) -> Style {
        Style(
            cornerRadius: configuration.browserContentCornerRadius,
            shadowOpacity: Float(BrowserContentViewportVisuals.shadowOpacity),
            shadowRadius: BrowserContentViewportVisuals.shadowRadius,
            shadowOffset: CGSize(
                width: BrowserContentViewportVisuals.shadowX,
                height: BrowserContentViewportVisuals.shadowY
            )
        )
    }

    private func apply(style: Style) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentShadowView.layer?.cornerRadius = style.cornerRadius
        contentShadowView.layer?.shadowOpacity = style.shadowOpacity
        contentShadowView.layer?.shadowRadius = style.shadowRadius
        contentShadowView.layer?.shadowOffset = style.shadowOffset
        webClipView.layer?.cornerRadius = style.cornerRadius
        CATransaction.commit()
    }

    private func animate(
        to style: Style,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        guard duration > 0,
              let shadowLayer = contentShadowView.layer,
              let clipLayer = webClipView.layer
        else {
            apply(style: style)
            return
        }

        let currentShadowLayer = shadowLayer.presentation() ?? shadowLayer
        let currentClipLayer = clipLayer.presentation() ?? clipLayer
        let fromShadowCornerRadius = currentShadowLayer.cornerRadius
        let fromClipCornerRadius = currentClipLayer.cornerRadius
        let fromShadowOpacity = currentShadowLayer.shadowOpacity
        let fromShadowRadius = currentShadowLayer.shadowRadius
        let fromShadowOffset = currentShadowLayer.shadowOffset

        addLayerAnimation(
            to: shadowLayer,
            keyPath: "cornerRadius",
            fromValue: fromShadowCornerRadius,
            toValue: style.cornerRadius,
            duration: duration,
            timingFunction: timingFunction
        )
        addLayerAnimation(
            to: clipLayer,
            keyPath: "cornerRadius",
            fromValue: fromClipCornerRadius,
            toValue: style.cornerRadius,
            duration: duration,
            timingFunction: timingFunction
        )
        addLayerAnimation(
            to: shadowLayer,
            keyPath: "shadowOpacity",
            fromValue: fromShadowOpacity,
            toValue: style.shadowOpacity,
            duration: duration,
            timingFunction: timingFunction
        )
        addLayerAnimation(
            to: shadowLayer,
            keyPath: "shadowRadius",
            fromValue: fromShadowRadius,
            toValue: style.shadowRadius,
            duration: duration,
            timingFunction: timingFunction
        )
        addLayerAnimation(
            to: shadowLayer,
            keyPath: "shadowOffset",
            fromValue: NSValue(size: fromShadowOffset),
            toValue: NSValue(size: style.shadowOffset),
            duration: duration,
            timingFunction: timingFunction
        )
    }

    private func addLayerAnimation(
        to layer: CALayer,
        keyPath: String,
        fromValue: Any,
        toValue: Any,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = fromValue
        animation.toValue = toValue
        animation.duration = duration
        animation.timingFunction = timingFunction
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "glancePromotion.\(keyPath)")
    }
}

@MainActor
private final class GlanceOverlayPresentationStateOwner {
    struct PendingPresentation {
        let session: GlanceSession
        let configuration: GlanceOverlayConfiguration
    }

    private(set) var displayedSessionID: UUID?
    private(set) var isAnimatingClose = false
    private(set) var isPresentationVisible = false
    private var pendingPresentation: PendingPresentation?
    private var closeConfirmationWorkItem: DispatchWorkItem?
    private var postAnimationCompletionTask: Task<Void, Never>?

    var pendingPresentationSessionID: UUID? {
        pendingPresentation?.session.id
    }

    func display(sessionID: UUID) {
        displayedSessionID = sessionID
    }

    func resetForMissingSession() {
        cancelPostAnimationCompletion()
        clearPendingPresentation()
        isAnimatingClose = false
        isPresentationVisible = false
        displayedSessionID = nil
    }

    func prepareForTearDown() {
        cancelPostAnimationCompletion()
        cancelCloseConfirmationReset()
        clearPendingPresentation()
        isAnimatingClose = false
    }

    func queuePendingPresentation(
        session: GlanceSession,
        configuration: GlanceOverlayConfiguration
    ) {
        pendingPresentation = PendingPresentation(session: session, configuration: configuration)
    }

    func takePendingPresentation() -> PendingPresentation? {
        defer { pendingPresentation = nil }
        return pendingPresentation
    }

    func clearPendingPresentation() {
        pendingPresentation = nil
    }

    func beginOpening() {
        cancelPostAnimationCompletion()
        isAnimatingClose = false
        isPresentationVisible = true
    }

    func beginClosing() {
        cancelPostAnimationCompletion()
        isAnimatingClose = true
    }

    func finishClosing() {
        isAnimatingClose = false
    }

    func setPresentationVisible(_ isVisible: Bool) {
        isPresentationVisible = isVisible
        if !isVisible {
            cancelPostAnimationCompletion()
            isAnimatingClose = false
        }
    }

    func schedulePostAnimationCompletion(
        sessionID: UUID,
        after duration: TimeInterval,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        cancelPostAnimationCompletion()
        postAnimationCompletionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: duration))
            guard !Task.isCancelled,
                  let self,
                  self.displayedSessionID == sessionID
            else { return }

            completion()
            self.postAnimationCompletionTask = nil
        }
    }

    func cancelPostAnimationCompletion() {
        postAnimationCompletionTask?.cancel()
        postAnimationCompletionTask = nil
    }

    func installCloseConfirmationReset(_ item: DispatchWorkItem) {
        closeConfirmationWorkItem = item
    }

    func cancelCloseConfirmationReset() {
        closeConfirmationWorkItem?.cancel()
        closeConfirmationWorkItem = nil
    }

    private static func nanoseconds(for duration: TimeInterval) -> UInt64 {
        UInt64(max(0, duration) * 1_000_000_000)
    }
}

@MainActor
private final class GlancePromotionHandoffOwner {
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
              let webViewCoordinator = manager?.browserManager?.webViewCoordinator
        else { return false }

        webViewCoordinator.registerPromotedHost(
            previewHostView,
            for: session.previewTab.id,
            in: session.windowId,
            attachmentCompletion: attachmentCompletion
        )
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

private final class GlanceWebContentShieldAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private extension NSView {
    func isDescendant(of ancestor: NSView) -> Bool {
        var current: NSView? = self
        while let view = current {
            if view === ancestor { return true }
            current = view.superview
        }
        return false
    }
}
