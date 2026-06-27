import AppKit
import QuartzCore
import WebKit

struct GlanceOverlayConfiguration {
    let isVisible: Bool
    let isSidebarVisible: Bool
    let sidebarWidth: CGFloat
    let sidebarPosition: SidebarPosition
    let cornerRadius: CGFloat
    let browserContentCornerRadius: CGFloat
    let accentColor: NSColor
    let surfaceColor: NSColor
    let reduceMotion: Bool
}

extension GlanceOverlayConfiguration: Equatable {
    static func == (lhs: GlanceOverlayConfiguration, rhs: GlanceOverlayConfiguration) -> Bool {
        lhs.isVisible == rhs.isVisible
            && lhs.isSidebarVisible == rhs.isSidebarVisible
            && lhs.sidebarWidth == rhs.sidebarWidth
            && lhs.sidebarPosition == rhs.sidebarPosition
            && lhs.cornerRadius == rhs.cornerRadius
            && lhs.browserContentCornerRadius == rhs.browserContentCornerRadius
            && lhs.accentColor.isEqual(rhs.accentColor)
            && lhs.surfaceColor.isEqual(rhs.surfaceColor)
            && lhs.reduceMotion == rhs.reduceMotion
    }
}

enum GlancePromotionTargetLayout {
    static func contentFrame(
        in bounds: CGRect,
        isSidebarVisible: Bool,
        sidebarWidth: CGFloat,
        sidebarPosition: SidebarPosition,
        elementSeparation: CGFloat = BrowserChromeGeometry.elementSeparation
    ) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        let inset = max(0, elementSeparation)
        let hasLeftSidebar = isSidebarVisible && sidebarPosition == .left
        let hasRightSidebar = isSidebarVisible && sidebarPosition == .right
        let leadingInset = hasLeftSidebar ? CGFloat.zero : inset
        let trailingInset = hasRightSidebar ? CGFloat.zero : inset

        var contentFrame = bounds
        contentFrame.origin.x += leadingInset
        contentFrame.origin.y += inset
        contentFrame.size.width -= leadingInset + trailingInset
        contentFrame.size.height -= inset * 2

        if isSidebarVisible {
            let sidebarWidth = min(max(0, sidebarWidth), max(0, contentFrame.width))
            if sidebarPosition == .left {
                contentFrame.origin.x += sidebarWidth
                contentFrame.size.width -= sidebarWidth
            } else {
                contentFrame.size.width -= sidebarWidth
            }
        }

        contentFrame.size.width = max(0, contentFrame.width)
        contentFrame.size.height = max(0, contentFrame.height)
        return contentFrame
            .standardized
            .integral
    }
}

final class GlanceOverlayRootView: NSView {
    var onLayout: (() -> Void)?
    var onBackgroundMouseDown: (() -> Void)?
    var onActionChromeMouseDown: ((CGPoint) -> Bool)?
    var acceptsBackgroundMouseEvents = false
    var sidebarPassthroughRect: CGRect? {
        didSet {
            guard sidebarPassthroughRect != oldValue else { return }
            window?.invalidateCursorRects(for: self)
        }
    }
    var webContentCursorExclusionRect: CGRect? {
        didSet {
            guard webContentCursorExclusionRect != oldValue else { return }
            window?.invalidateCursorRects(for: self)
        }
    }
    var chromeCursorExclusionRect: CGRect? {
        didSet {
            guard chromeCursorExclusionRect != oldValue else { return }
            window?.invalidateCursorRects(for: self)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard acceptsBackgroundMouseEvents, bounds.contains(point) else { return nil }

        if let hitView = super.hitTest(point), hitView !== self {
            return hitView
        }

        if sidebarPassthroughRect?.contains(point) == true {
            return nil
        }

        return self
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if onActionChromeMouseDown?(point) == true {
            return
        }
        onBackgroundMouseDown?()
    }

    override func rightMouseDown(with event: NSEvent) {}

    override func otherMouseDown(with event: NSEvent) {}

    override func scrollWheel(with event: NSEvent) {}

    override func resetCursorRects() {
        super.resetCursorRects()
        for rect in backgroundCursorRects {
            addCursorRect(rect, cursor: .arrow)
        }
    }

    private var backgroundCursorRects: [CGRect] {
        var rects = [bounds]
        var exclusionCandidates: [CGRect] = []
        if let webContentCursorExclusionRect {
            exclusionCandidates.append(webContentCursorExclusionRect.standardized)
        }
        if let chromeCursorExclusionRect {
            exclusionCandidates.append(chromeCursorExclusionRect.standardized)
        }
        if let sidebarPassthroughRect {
            exclusionCandidates.append(sidebarPassthroughRect.standardized)
        }

        let exclusions = exclusionCandidates
            .map { $0.intersection(bounds) }
            .filter { !$0.isNull && $0.width > 0 && $0.height > 0 }

        for exclusion in exclusions {
            rects = rects.flatMap { $0.subtracting(exclusion) }
        }
        return rects.filter { $0.width > 0 && $0.height > 0 }
    }

    override func layout() {
        super.layout()
        onLayout?()
    }
}

@MainActor
final class GlanceOverlayController: NSObject {
    private weak var rootView: GlanceOverlayRootView?
    private weak var manager: GlanceManager?
    private var session: GlanceSession?
    private var configuration: GlanceOverlayConfiguration?
    private var keyMonitor: Any?
    private var displayedSessionID: UUID?
    private var isAnimatingClose = false
    private let promotionHandoff = GlancePromotionHandoffOwner()
    private var isPresentationVisible = false
    private var closeConfirmationWorkItem: DispatchWorkItem?
    private var postAnimationCompletionTask: Task<Void, Never>?
    private var pendingPresentation: (session: GlanceSession, configuration: GlanceOverlayConfiguration)?
    private weak var previewWebView: FocusableWKWebView?
    private var previewHostView: SumiWebViewContainerView?

    private let webContentShieldAnchorView = GlanceWebContentShieldAnchorView(frame: .zero)
    private let contentShadowView = NSView(frame: .zero)
    private let webClipView = NSView(frame: .zero)
    private let buttonStack = GlanceActionButtonStack(
        buttonSize: Metrics.actionButtonSize,
        spacing: Metrics.actionButtonSpacing,
        hitOutset: Metrics.actionButtonHitOutset
    )
    private let closeButton = GlanceActionButton(symbolName: "xmark", toolTip: "Close Glance")
    private let openButton = GlanceActionButton(symbolName: "arrow.up.left.and.arrow.down.right", toolTip: "Open in Tab")
    private let splitButton = GlanceActionButton(symbolName: "square.split.2x1", toolTip: "Open in Split View")

    private enum Metrics {
        static let webAreaHorizontalInset: CGFloat = BrowserChromeGeometry.elementSeparation
        static let webAreaVerticalInset: CGFloat = 12
        static let minimumContentWidth: CGFloat = 320
        static let contentWidthFraction: CGFloat = 0.8
        static let glanceShadowOpacity: Float = 0.22
        static let glanceShadowRadius: CGFloat = 24
        static let glanceShadowOffset = CGSize(width: 0, height: -6)
        static let actionButtonSize: CGFloat = 32
        static let actionButtonSpacing: CGFloat = 12
        static let actionStackWidth: CGFloat = 44
        static let actionButtonHitOutset: CGFloat = 6
        static let actionStackTopInset: CGFloat = 15
        static let actionStackSideGap: CGFloat = 12
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

    private struct ContentVisualStyle {
        let cornerRadius: CGFloat
        let shadowOpacity: Float
        let shadowRadius: CGFloat
        let shadowOffset: CGSize
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
            self?.handleActionChromeMouseDown(at: point) == true
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
        splitButton.isEnabled = manager.canEnterSplitView

        guard let session else {
            cancelPostAnimationCompletion()
            pendingPresentation = nil
            isAnimatingClose = false
            isPresentationVisible = false
            uninstallKeyMonitor()
            tearDownPresentedViews(
                preservingPromotionHandoff: promotionHandoff.preservesPresentedHostDuringTeardown
            )
            promotionHandoff.reset()
            self.session = nil
            displayedSessionID = nil
            return
        }

        if displayedSessionID != session.id {
            self.session = session
            displayedSessionID = session.id
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
            pendingPresentation = nil
            setPresentationVisible(false)
            return
        }

        if !isPresentationVisible {
            setPresentationVisible(true)
            layoutForCurrentBounds(animated: false)
            return
        }

        if phase == .closing, !isAnimatingClose {
            pendingPresentation = nil
            animateClose(session: session, configuration: configuration)
        } else if pendingPresentation?.session.id == session.id {
            pendingPresentation = (session, configuration)
            _ = presentPendingIfPossible()
        } else if phase == .opening {
            attachPreviewWebViewIfAvailable(for: session)
        } else {
            layoutForCurrentBounds(animated: phase == .open && !configuration.reduceMotion)
        }
    }

    func tearDown() {
        cancelPostAnimationCompletion()
        closeConfirmationWorkItem?.cancel()
        closeConfirmationWorkItem = nil
        pendingPresentation = nil
        isAnimatingClose = false
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
        pendingPresentation = (session, configuration)
        guard !presentPendingIfPossible() else { return }
        rootView?.needsLayout = true
    }

    @discardableResult
    private func presentPendingIfPossible() -> Bool {
        guard let rootView,
              rootView.bounds.width > 1,
              rootView.bounds.height > 1,
              let pendingPresentation
        else { return false }

        self.pendingPresentation = nil
        present(
            session: pendingPresentation.session,
            configuration: pendingPresentation.configuration
        )
        return true
    }

    private func configureViews() {
        contentShadowView.wantsLayer = true
        contentShadowView.layer?.shadowColor = NSColor.black.cgColor
        contentShadowView.layer?.shadowOpacity = Metrics.glanceShadowOpacity
        contentShadowView.layer?.shadowRadius = Metrics.glanceShadowRadius
        contentShadowView.layer?.shadowOffset = Metrics.glanceShadowOffset
        if #available(macOS 10.15, *) {
            contentShadowView.layer?.cornerCurve = .continuous
        }

        webClipView.wantsLayer = true
        webClipView.layer?.masksToBounds = true
        webClipView.autoresizingMask = [.width, .height]
        if #available(macOS 10.15, *) {
            webClipView.layer?.cornerCurve = .continuous
        }

        [closeButton, openButton, splitButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = true
            buttonStack.addArrangedSubview($0)
        }

        closeButton.target = self
        closeButton.action = #selector(closeButtonPressed)
        openButton.target = self
        openButton.action = #selector(openButtonPressed)
        splitButton.target = self
        splitButton.action = #selector(splitButtonPressed)
    }

    private func apply(configuration: GlanceOverlayConfiguration) {
        contentShadowView.layer?.backgroundColor = configuration.surfaceColor.cgColor
        webClipView.layer?.backgroundColor = configuration.surfaceColor.cgColor
        if !promotionHandoff.blocksPresentationUpdates {
            applyContentVisualStyle(glanceContentVisualStyle(for: configuration))
        }
        [closeButton, openButton, splitButton].forEach {
            $0.apply(accentColor: configuration.accentColor)
        }
    }

    private func glanceContentVisualStyle(
        for configuration: GlanceOverlayConfiguration
    ) -> ContentVisualStyle {
        ContentVisualStyle(
            cornerRadius: configuration.cornerRadius,
            shadowOpacity: Metrics.glanceShadowOpacity,
            shadowRadius: Metrics.glanceShadowRadius,
            shadowOffset: Metrics.glanceShadowOffset
        )
    }

    private func browserViewportContentVisualStyle(
        for configuration: GlanceOverlayConfiguration
    ) -> ContentVisualStyle {
        ContentVisualStyle(
            cornerRadius: configuration.browserContentCornerRadius,
            shadowOpacity: Float(BrowserContentViewportVisuals.shadowOpacity),
            shadowRadius: BrowserContentViewportVisuals.shadowRadius,
            shadowOffset: CGSize(
                width: BrowserContentViewportVisuals.shadowX,
                height: BrowserContentViewportVisuals.shadowY
            )
        )
    }

    private func applyContentVisualStyle(_ style: ContentVisualStyle) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentShadowView.layer?.cornerRadius = style.cornerRadius
        contentShadowView.layer?.shadowOpacity = style.shadowOpacity
        contentShadowView.layer?.shadowRadius = style.shadowRadius
        contentShadowView.layer?.shadowOffset = style.shadowOffset
        webClipView.layer?.cornerRadius = style.cornerRadius
        CATransaction.commit()
    }

    private func animateContentVisualStyle(
        to style: ContentVisualStyle,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        guard duration > 0,
              let shadowLayer = contentShadowView.layer,
              let clipLayer = webClipView.layer
        else {
            applyContentVisualStyle(style)
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

    private func removeContentVisualStyleAnimations() {
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

    private func present(
        session: GlanceSession,
        configuration: GlanceOverlayConfiguration
    ) {
        guard let rootView else { return }

        cancelPostAnimationCompletion()
        isAnimatingClose = false
        installViewsIfNeeded()
        isPresentationVisible = true
        rootView.acceptsBackgroundMouseEvents = true
        contentShadowView.isHidden = false
        buttonStack.isHidden = false
        webContentShieldAnchorView.isHidden = false
        installKeyMonitorIfNeeded()
        resetCloseConfirmation()
        attachPreviewWebViewIfAvailable(for: session)

        let targetFrame = targetContentFrame(in: rootView.bounds, configuration: configuration)
        let startFrame = startContentFrame(
            for: session,
            in: rootView,
            targetFrame: targetFrame
        )
        publishContentFrame(targetFrame, in: rootView)

        contentShadowView.frame = configuration.reduceMotion ? targetFrame : startFrame
        webClipView.frame = contentShadowView.bounds
        contentShadowView.alphaValue = configuration.reduceMotion ? 0 : 1
        buttonStack.alphaValue = 0
        layoutButtons(for: targetFrame, configuration: configuration)
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
        guard isPresentationVisible,
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
        let finalFrame = buttonStack.frame
        if !configuration.reduceMotion {
            let xOffset = configuration.sidebarPosition == .right
                ? Motion.buttonOffset
                : -Motion.buttonOffset
            buttonStack.frame = finalFrame.offsetBy(dx: xOffset, dy: 0)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            buttonStack.animator().frame = finalFrame
            buttonStack.animator().alphaValue = 1
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
        cancelPostAnimationCompletion()
        isAnimatingClose = true
        resetCloseConfirmation()

        let targetFrame = targetContentFrame(in: rootView.bounds, configuration: configuration)
        let endFrame = startContentFrame(
            for: session,
            in: rootView,
            targetFrame: targetFrame
        )
        let duration = configuration.reduceMotion ? Motion.reducedMotionDuration : Motion.glanceDuration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            buttonStack.animator().alphaValue = 0
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
        isAnimatingClose = false
        tearDownPresentedViews()
        manager?.finishAnimatedDismissal(sessionID: sessionID)
    }

    private func scheduleOpeningCompletion(
        sessionID: UUID,
        targetFrame: CGRect,
        configuration: GlanceOverlayConfiguration,
        after duration: TimeInterval
    ) {
        cancelPostAnimationCompletion()
        postAnimationCompletionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: duration))
            guard !Task.isCancelled,
                  let self,
                  self.session?.id == sessionID
            else { return }

            self.finishOpening(
                sessionID: sessionID,
                targetFrame: targetFrame,
                configuration: configuration
            )
            self.postAnimationCompletionTask = nil
        }
    }

    private func scheduleClosingCompletion(sessionID: UUID, after duration: TimeInterval) {
        cancelPostAnimationCompletion()
        postAnimationCompletionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: duration))
            guard !Task.isCancelled,
                  let self,
                  self.session?.id == sessionID
            else { return }

            self.finishClosing(sessionID: sessionID)
            self.postAnimationCompletionTask = nil
        }
    }

    private func cancelPostAnimationCompletion() {
        postAnimationCompletionTask?.cancel()
        postAnimationCompletionTask = nil
    }

    private static func nanoseconds(for duration: TimeInterval) -> UInt64 {
        UInt64(max(0, duration) * 1_000_000_000)
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
        if buttonStack.superview == nil {
            rootView.addSubview(buttonStack)
        }
    }

    private func tearDownPresentedViews(preservingPromotionHandoff: Bool = false) {
        resetCloseConfirmation()
        isPresentationVisible = false
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
        buttonStack.removeFromSuperview()
        contentShadowView.removeFromSuperview()
    }

    private func setPresentationVisible(_ isVisible: Bool) {
        isPresentationVisible = isVisible
        rootView?.acceptsBackgroundMouseEvents = isVisible
        contentShadowView.isHidden = !isVisible
        buttonStack.isHidden = !isVisible
        webContentShieldAnchorView.isHidden = !isVisible

        if isVisible {
            installKeyMonitorIfNeeded()
            contentShadowView.alphaValue = 1
            buttonStack.alphaValue = 1
        } else {
            cancelPostAnimationCompletion()
            isAnimatingClose = false
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
              !isAnimatingClose,
              !promotionHandoff.blocksPresentationUpdates
        else { return }

        let targetFrame = targetContentFrame(in: rootView.bounds, configuration: configuration)
        let updates = {
            self.attachPreviewWebViewIfAvailable(for: self.session)
            self.contentShadowView.frame = targetFrame
            self.webClipView.frame = self.contentShadowView.bounds
            self.publishContentFrame(targetFrame, in: rootView)
            self.layoutButtons(for: targetFrame, configuration: configuration)
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

    private func targetContentFrame(
        in bounds: CGRect,
        configuration: GlanceOverlayConfiguration
    ) -> CGRect {
        let webArea = webAreaFrame(in: bounds, configuration: configuration)
        guard webArea.width > 0, webArea.height > 0 else { return .zero }

        let width = max(Metrics.minimumContentWidth, webArea.width * Metrics.contentWidthFraction)
        let x = webArea.midX - width / 2
        return CGRect(
            x: x.rounded(.toNearestOrAwayFromZero),
            y: webArea.minY.rounded(.toNearestOrAwayFromZero),
            width: min(width, webArea.width).rounded(.toNearestOrAwayFromZero),
            height: webArea.height.rounded(.toNearestOrAwayFromZero)
        )
    }

    private func webAreaFrame(
        in bounds: CGRect,
        configuration: GlanceOverlayConfiguration
    ) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }

        var webArea = bounds.insetBy(
            dx: Metrics.webAreaHorizontalInset,
            dy: Metrics.webAreaVerticalInset
        )
        if configuration.isSidebarVisible {
            let sidebarWidth = min(configuration.sidebarWidth, max(0, webArea.width - 160))
            if configuration.sidebarPosition == .left {
                webArea.origin.x += sidebarWidth
                webArea.size.width -= sidebarWidth
            } else {
                webArea.size.width -= sidebarWidth
            }
        }
        return webArea
    }

    private func promotionContentFrame(
        in bounds: CGRect,
        configuration: GlanceOverlayConfiguration
    ) -> CGRect {
        // Match the browser viewport, not the full window: keep the visual chrome gutters
        // during promotion while avoiding an extra side gutter beside a docked sidebar.
        GlancePromotionTargetLayout.contentFrame(
            in: bounds,
            isSidebarVisible: configuration.isSidebarVisible,
            sidebarWidth: configuration.sidebarWidth,
            sidebarPosition: configuration.sidebarPosition
        )
    }

    private func startContentFrame(
        for session: GlanceSession,
        in rootView: NSView,
        targetFrame: CGRect
    ) -> CGRect {
        let converted = rootView.convert(session.originRectInWindow, from: nil).standardized
        guard converted.width > 0,
              converted.height > 0,
              rootView.bounds.intersects(converted)
        else {
            return clampedOriginFrame(converted, in: rootView, fallback: targetFrame)
        }
        return converted
    }

    private func clampedOriginFrame(
        _ frame: CGRect,
        in rootView: NSView,
        fallback: CGRect
    ) -> CGRect {
        let sourcePoint = CGPoint(
            x: frame.midX.isFinite ? frame.midX : fallback.midX,
            y: frame.midY.isFinite ? frame.midY : fallback.midY
        )
        let clampedPoint = CGPoint(
            x: min(max(sourcePoint.x, rootView.bounds.minX + 22), rootView.bounds.maxX - 22),
            y: min(max(sourcePoint.y, rootView.bounds.minY + 22), rootView.bounds.maxY - 22)
        )
        return CGRect(
            x: clampedPoint.x - 22,
            y: clampedPoint.y - 22,
            width: 44,
            height: 44
        )
    }

    private func layoutButtons(
        for contentFrame: CGRect,
        configuration: GlanceOverlayConfiguration
    ) {
        let buttonStackHeight = CGFloat(buttonStack.arrangedSubviews.count) * Metrics.actionButtonSize
            + CGFloat(max(0, buttonStack.arrangedSubviews.count - 1)) * buttonStack.spacing
        let buttonSize = CGSize(width: Metrics.actionStackWidth, height: buttonStackHeight)
        let x: CGFloat
        if configuration.sidebarPosition == .right {
            x = max(8, contentFrame.minX - buttonSize.width - Metrics.actionStackSideGap)
        } else {
            x = min(
                (rootView?.bounds.maxX ?? contentFrame.maxX) - buttonSize.width - 8,
                contentFrame.maxX + Metrics.actionStackSideGap
            )
        }
        let y = contentFrame.maxY - buttonSize.height - Metrics.actionStackTopInset
        buttonStack.frame = CGRect(
            x: x.rounded(.toNearestOrAwayFromZero),
            y: max(16, y).rounded(.toNearestOrAwayFromZero),
            width: buttonSize.width,
            height: buttonSize.height
        )
        buttonStack.needsLayout = true
        buttonStack.layoutSubtreeIfNeeded()
        rootView?.chromeCursorExclusionRect = buttonStack.frame.insetBy(dx: -6, dy: -6)
    }

    private func layoutInteractionShield(
        in bounds: CGRect,
        contentFrame: CGRect
    ) {
        webContentShieldAnchorView.frame = bounds
        rootView?.sidebarPassthroughRect = sidebarPassthroughRect(in: bounds)
        rootView?.webContentCursorExclusionRect = contentFrame
        WebContentMouseTrackingShield.setActive(
            bounds.width > 0 && bounds.height > 0,
            for: webContentShieldAnchorView,
            excludingWebContentIn: webClipView,
            coversAllWebContent: true
        )
    }

    private func sidebarPassthroughRect(in bounds: CGRect) -> CGRect? {
        guard let configuration,
              configuration.isSidebarVisible,
              configuration.sidebarWidth > 0,
              bounds.width > 0,
              bounds.height > 0
        else { return nil }

        let width = min(configuration.sidebarWidth, bounds.width)
        let x = configuration.sidebarPosition == .left
            ? bounds.minX
            : bounds.maxX - width
        return CGRect(
            x: x,
            y: bounds.minY,
            width: width,
            height: bounds.height
        )
    }

    private func publishContentFrame(_ frame: CGRect?, in rootView: NSView?) {
        guard let manager,
              let session
        else { return }

        guard let frame,
              let rootView
        else {
            manager.updateContentFrameInWindowSpace(nil, sessionID: session.id)
            return
        }

        let swiftUIFrame: CGRect
        if rootView.isFlipped {
            swiftUIFrame = frame
        } else {
            swiftUIFrame = CGRect(
                x: frame.minX,
                y: rootView.bounds.height - frame.maxY,
                width: frame.width,
                height: frame.height
            )
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

    private func handleActionChromeMouseDown(at point: CGPoint) -> Bool {
        guard buttonStack.superview != nil,
              !buttonStack.isHidden
        else { return false }

        let localPoint = buttonStack.convert(point, from: rootView)
        let stackHitFrame = buttonStack.bounds.insetBy(
            dx: -Metrics.actionButtonHitOutset,
            dy: -Metrics.actionButtonHitOutset
        )
        guard stackHitFrame.contains(localPoint) else { return false }

        if handleActionButtonHit(splitButton, at: localPoint) {
            return true
        }
        if handleActionButtonHit(openButton, at: localPoint) {
            return true
        }
        if handleActionButtonHit(closeButton, at: localPoint) {
            return true
        }

        return true
    }

    private func handleActionButtonHit(_ button: GlanceActionButton, at localPoint: CGPoint) -> Bool {
        let expandedFrame = button.frame.insetBy(
            dx: -Metrics.actionButtonHitOutset,
            dy: -Metrics.actionButtonHitOutset
        )
        guard expandedFrame.contains(localPoint) else { return false }
        guard button.isEnabled else { return true }

        if button === splitButton {
            splitButtonPressed()
        } else if button === openButton {
            openButtonPressed()
        } else {
            closeButtonPressed()
        }
        return true
    }

    @objc private func closeButtonPressed() {
        guard !promotionHandoff.isAnimating else { return }
        guard let manager,
              let session,
              let configuration
        else { return }

        if closeButton.requiresSecondPress == false,
           webContentIsFocused() {
            closeButton.requiresSecondPress = true
            scheduleCloseConfirmationReset()
            return
        }

        guard manager.beginAnimatedDismissal() != nil else { return }
        animateClose(session: session, configuration: configuration)
    }

    @objc private func openButtonPressed() {
        animatePromotionToRegularTab()
    }

    @objc private func splitButtonPressed() {
        guard !promotionHandoff.isAnimating else { return }
        guard splitButton.isEnabled else { return }
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
        [closeButton, openButton, splitButton].forEach { $0.isEnabled = false }

        attachPreviewWebViewIfAvailable(for: session)

        let targetFrame = promotionContentFrame(in: rootView.bounds, configuration: configuration)
        publishContentFrame(targetFrame, in: rootView)
        layoutInteractionShield(in: rootView.bounds, contentFrame: targetFrame)

        let duration = min(
            configuration.reduceMotion ? Motion.reducedMotionDuration : Motion.glanceDuration,
            0.28
        )
        let promotionTimingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        animateContentVisualStyle(
            to: browserViewportContentVisualStyle(for: configuration),
            duration: duration,
            timingFunction: promotionTimingFunction
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = promotionTimingFunction
            buttonStack.animator().alphaValue = 0
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
                self.removeContentVisualStyleAnimations()
                return
            }
            self.contentShadowView.frame = targetFrame
            self.webClipView.frame = self.contentShadowView.bounds
            self.applyContentVisualStyle(
                self.browserViewportContentVisualStyle(for: configuration)
            )
            self.removeContentVisualStyleAnimations()
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
            [closeButton, openButton, splitButton].forEach { $0.isEnabled = true }
            buttonStack.animator().alphaValue = 1
            if let configuration {
                removeContentVisualStyleAnimations()
                applyContentVisualStyle(glanceContentVisualStyle(for: configuration))
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
        buttonStack.isHidden = true
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
        closeConfirmationWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.resetCloseConfirmation()
        }
        closeConfirmationWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    private func resetCloseConfirmation() {
        closeConfirmationWorkItem?.cancel()
        closeConfirmationWorkItem = nil
        closeButton.requiresSecondPress = false
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

private final class GlanceActionButtonStack: NSView {
    let spacing: CGFloat
    private let buttonSize: CGFloat
    private let hitOutset: CGFloat
    private(set) var arrangedSubviews: [NSView] = []

    init(buttonSize: CGFloat, spacing: CGFloat, hitOutset: CGFloat) {
        self.buttonSize = buttonSize
        self.spacing = spacing
        self.hitOutset = hitOutset
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addArrangedSubview(_ view: NSView) {
        arrangedSubviews.append(view)
        addSubview(view)
    }

    override func layout() {
        super.layout()

        let x = ((bounds.width - buttonSize) / 2).rounded(.toNearestOrAwayFromZero)
        var y = bounds.maxY - buttonSize
        for view in arrangedSubviews {
            view.frame = CGRect(
                x: x,
                y: y.rounded(.toNearestOrAwayFromZero),
                width: buttonSize,
                height: buttonSize
            )
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            y -= buttonSize + spacing
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        for subview in subviews.reversed() {
            let convertedPoint = subview.convert(point, from: self)
            if let hitView = subview.hitTest(convertedPoint) {
                return hitView
            }
            let expandedFrame = subview.frame.insetBy(
                dx: -hitOutset,
                dy: -hitOutset
            )
            if expandedFrame.contains(point) {
                return subview
            }
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func resetCursorRects() {}
}

private final class GlanceActionButton: NSButton {
    private let symbolName: String
    private var accentColor: NSColor = .controlAccentColor
    private var trackingArea: NSTrackingArea?
    private var currentScale: CGFloat = 1
    private var cursorInvalidationBounds: CGRect = .null
    private var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            updateAppearance()
            updateScale()
        }
    }
    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            updateScale()
        }
    }
    var requiresSecondPress: Bool = false {
        didSet {
            guard requiresSecondPress != oldValue else { return }
            updateAppearance()
        }
    }

    init(symbolName: String, toolTip: String) {
        self.symbolName = symbolName
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        refusesFirstResponder = true
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.10
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        self.toolTip = toolTip
        setButtonType(.momentaryChange)
        updateImage()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(accentColor: NSColor) {
        guard !self.accentColor.isEqual(accentColor) else { return }
        self.accentColor = accentColor
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        self.trackingArea = trackingArea
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        setPointingHandCursorIfNeeded()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        isPressed = false
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        setPointingHandCursorIfNeeded()
    }

    override func cursorUpdate(with event: NSEvent) {
        guard isEnabled else {
            super.cursorUpdate(with: event)
            return
        }
        setPointingHandCursorIfNeeded()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            super.mouseDown(with: event)
            return
        }
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
    }

    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            updateAppearance()
            window?.invalidateCursorRects(for: self)
            setPointingHandCursorIfNeeded()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isEnabled else { return }
        sumi_chromeAddCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateLayer() {
        super.updateLayer()
        updateAppearance()
    }

    override func layout() {
        super.layout()
        let cornerRadius = min(bounds.width, bounds.height) / 2
        if layer?.cornerRadius != cornerRadius {
            layer?.cornerRadius = cornerRadius
        }
        if cursorInvalidationBounds != bounds {
            cursorInvalidationBounds = bounds
            window?.invalidateCursorRects(for: self)
        }
    }

    private func updateImage() {
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(symbolConfiguration)
    }

    private func updateAppearance() {
        let background: NSColor
        let foreground: NSColor
        if !isEnabled {
            background = NSColor.controlBackgroundColor.withAlphaComponent(0.74)
            foreground = .tertiaryLabelColor
        } else if requiresSecondPress {
            background = NSColor.systemRed
            foreground = .white
        } else if isHovered {
            background = NSColor.textColor.withAlphaComponent(0.84)
            foreground = accentColor
        } else {
            background = NSColor.textColor.withAlphaComponent(0.92)
            foreground = accentColor
        }

        layer?.backgroundColor = background.cgColor
        contentTintColor = foreground
    }

    private func updateScale() {
        let scale: CGFloat
        if !isEnabled {
            scale = 1
        } else if isPressed {
            scale = 0.95
        } else if isHovered {
            scale = 1.05
        } else {
            scale = 1
        }

        guard let layer else { return }
        guard currentScale != scale else { return }
        currentScale = scale
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.05)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }

    private func setPointingHandCursorIfNeeded() {
        guard isEnabled else { return }
        sumi_chromeSetCursorIfMouseInside(.pointingHand)
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

private extension CGRect {
    func subtracting(_ excludedRect: CGRect) -> [CGRect] {
        let excludedRect = excludedRect.intersection(self)
        guard !excludedRect.isNull,
              excludedRect.width > 0,
              excludedRect.height > 0
        else { return [self] }

        return [
            CGRect(x: minX, y: minY, width: width, height: max(0, excludedRect.minY - minY)),
            CGRect(x: minX, y: excludedRect.maxY, width: width, height: max(0, maxY - excludedRect.maxY)),
            CGRect(x: minX, y: excludedRect.minY, width: max(0, excludedRect.minX - minX), height: excludedRect.height),
            CGRect(x: excludedRect.maxX, y: excludedRect.minY, width: max(0, maxX - excludedRect.maxX), height: excludedRect.height),
        ].filter { $0.width > 0 && $0.height > 0 }
    }
}
