import AppKit
import WebKit

struct GlanceOverlayConfiguration {
    let isSidebarVisible: Bool
    let sidebarWidth: CGFloat
    let sidebarPosition: SidebarPosition
    let cornerRadius: CGFloat
    let accentColor: NSColor
    let surfaceColor: NSColor
    let reduceMotion: Bool
}

final class GlanceOverlayRootView: NSView {
    var onLayout: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hitView = super.hitTest(point) else { return nil }
        return hitView === self ? nil : hitView
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
    private var closeConfirmationWorkItem: DispatchWorkItem?

    private let backdropView = GlanceBackdropView()
    private let contentShadowView = NSView(frame: .zero)
    private let webClipView = NSView(frame: .zero)
    private let buttonStack = NSStackView(frame: .zero)
    private let closeButton = GlanceActionButton(symbolName: "xmark", toolTip: "Close Glance")
    private let openButton = GlanceActionButton(symbolName: "plus.square.on.square", toolTip: "Open in Tab")
    private let splitButton = GlanceActionButton(symbolName: "square.split.2x1", toolTip: "Open in Split View")

    private enum Metrics {
        static let webAreaHorizontalInset: CGFloat = BrowserChromeGeometry.elementSeparation
        static let webAreaVerticalInset: CGFloat = 12
        static let minimumContentWidth: CGFloat = 320
        static let contentWidthFraction: CGFloat = 0.8
        static let actionButtonSize: CGFloat = 34
        static let actionStackWidth: CGFloat = 44
        static let actionStackTopInset: CGFloat = 16
        static let actionStackSideGap: CGFloat = 12
    }

    init(rootView: GlanceOverlayRootView) {
        self.rootView = rootView
        super.init()
        rootView.onLayout = { [weak self] in
            self?.layoutForCurrentBounds(animated: false)
        }
        configureViews()
    }

    func update(
        manager: GlanceManager,
        session: GlanceSession?,
        phase: GlancePresentationPhase,
        configuration: GlanceOverlayConfiguration
    ) {
        self.manager = manager
        self.configuration = configuration
        apply(configuration: configuration)
        splitButton.isEnabled = manager.canEnterSplitView

        guard let session else {
            uninstallKeyMonitor()
            tearDownPresentedViews()
            self.session = nil
            displayedSessionID = nil
            return
        }

        if displayedSessionID != session.id {
            self.session = session
            displayedSessionID = session.id
            present(session: session, configuration: configuration)
            return
        }

        self.session = session
        if phase == .closing, !isAnimatingClose {
            animateClose(session: session, configuration: configuration)
        } else {
            layoutForCurrentBounds(animated: phase == .open && !configuration.reduceMotion)
        }
    }

    func tearDown() {
        closeConfirmationWorkItem?.cancel()
        closeConfirmationWorkItem = nil
        uninstallKeyMonitor()
        tearDownPresentedViews()
        rootView?.onLayout = nil
    }

    private func configureViews() {
        backdropView.onMouseDown = { [weak self] in
            self?.closeFromBackdrop()
        }

        contentShadowView.wantsLayer = true
        contentShadowView.layer?.shadowColor = NSColor.black.cgColor
        contentShadowView.layer?.shadowOpacity = 0.22
        contentShadowView.layer?.shadowRadius = 24
        contentShadowView.layer?.shadowOffset = CGSize(width: 0, height: -6)

        webClipView.wantsLayer = true
        webClipView.layer?.masksToBounds = true
        webClipView.autoresizingMask = [.width, .height]

        buttonStack.orientation = .vertical
        buttonStack.spacing = 12
        buttonStack.alignment = .centerX
        buttonStack.distribution = .fill
        [closeButton, openButton, splitButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                $0.widthAnchor.constraint(equalToConstant: Metrics.actionButtonSize),
                $0.heightAnchor.constraint(equalToConstant: Metrics.actionButtonSize),
            ])
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
        backdropView.layer?.backgroundColor = NSColor.clear.cgColor
        contentShadowView.layer?.backgroundColor = configuration.surfaceColor.cgColor
        webClipView.layer?.backgroundColor = configuration.surfaceColor.cgColor
        webClipView.layer?.cornerRadius = configuration.cornerRadius
        contentShadowView.layer?.cornerRadius = configuration.cornerRadius
        [closeButton, openButton, splitButton].forEach {
            $0.apply(accentColor: configuration.accentColor)
        }
    }

    private func present(
        session: GlanceSession,
        configuration: GlanceOverlayConfiguration
    ) {
        guard let rootView else { return }

        installViewsIfNeeded()
        installKeyMonitorIfNeeded()
        resetCloseConfirmation()
        attachPreviewWebViewIfAvailable(for: session)

        let targetFrame = targetContentFrame(in: rootView.bounds, configuration: configuration)
        let startFrame = startContentFrame(
            for: session,
            in: rootView,
            targetFrame: targetFrame
        )

        contentShadowView.frame = configuration.reduceMotion ? targetFrame : startFrame
        webClipView.frame = contentShadowView.bounds
        backdropView.alphaValue = 0
        contentShadowView.alphaValue = configuration.reduceMotion ? 0 : 1
        buttonStack.alphaValue = 0
        layoutButtons(for: targetFrame, configuration: configuration)
        layoutBackdrop(in: rootView.bounds, configuration: configuration)

        let duration = configuration.reduceMotion ? 0.08 : 0.35
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            backdropView.animator().alphaValue = 1
            contentShadowView.animator().frame = targetFrame
            contentShadowView.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.contentShadowView.frame = targetFrame
                self.webClipView.frame = self.contentShadowView.bounds
                self.manager?.markOpened(sessionID: session.id)
                self.animateButtonsIn(configuration: configuration)
            }
        }
    }

    private func animateButtonsIn(configuration: GlanceOverlayConfiguration) {
        let duration = configuration.reduceMotion ? 0.08 : 0.2
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
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
        isAnimatingClose = true
        resetCloseConfirmation()

        let targetFrame = targetContentFrame(in: rootView.bounds, configuration: configuration)
        let endFrame = startContentFrame(
            for: session,
            in: rootView,
            targetFrame: targetFrame
        )
        let duration = configuration.reduceMotion ? 0.08 : 0.28
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            backdropView.animator().alphaValue = 0
            buttonStack.animator().alphaValue = 0
            contentShadowView.animator().alphaValue = configuration.reduceMotion ? 0 : 1
            contentShadowView.animator().frame = configuration.reduceMotion ? targetFrame : endFrame
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAnimatingClose = false
                self.tearDownPresentedViews()
                self.manager?.finishAnimatedDismissal(sessionID: session.id)
            }
        }
    }

    private func installViewsIfNeeded() {
        guard let rootView else { return }
        rootView.wantsLayer = true

        if backdropView.superview == nil {
            rootView.addSubview(backdropView)
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

    private func tearDownPresentedViews() {
        resetCloseConfirmation()
        webClipView.subviews.forEach { $0.removeFromSuperview() }
        buttonStack.removeFromSuperview()
        contentShadowView.removeFromSuperview()
        backdropView.removeFromSuperview()
    }

    private func attachPreviewWebViewIfAvailable(for session: GlanceSession?) {
        guard let session,
              let webView = session.previewTab.existingWebView,
              webView.superview !== webClipView
        else { return }

        webView.removeFromSuperview()
        webClipView.addSubview(webView)
        webView.frame = webClipView.bounds
        webView.autoresizingMask = [.width, .height]
    }

    private func layoutForCurrentBounds(animated: Bool) {
        guard let rootView,
              let configuration,
              session != nil,
              !isAnimatingClose
        else { return }

        let targetFrame = targetContentFrame(in: rootView.bounds, configuration: configuration)
        let updates = {
            self.attachPreviewWebViewIfAvailable(for: self.session)
            self.contentShadowView.frame = targetFrame
            self.webClipView.frame = self.contentShadowView.bounds
            self.layoutButtons(for: targetFrame, configuration: configuration)
            self.layoutBackdrop(in: rootView.bounds, configuration: configuration)
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
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

    private func startContentFrame(
        for session: GlanceSession,
        in rootView: NSView,
        targetFrame: CGRect
    ) -> CGRect {
        let converted = rootView.convert(session.originRectInWindow, from: nil)
        guard converted.width > 0,
              converted.height > 0,
              rootView.bounds.intersects(converted)
        else {
            return CGRect(
                x: targetFrame.midX - 22,
                y: targetFrame.midY - 22,
                width: 44,
                height: 44
            )
        }
        return converted
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
    }

    private func layoutBackdrop(
        in bounds: CGRect,
        configuration: GlanceOverlayConfiguration
    ) {
        backdropView.frame = webAreaFrame(in: bounds, configuration: configuration)
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.session != nil,
                  let rootWindow = self.rootView?.window,
                  event.window === rootWindow,
                  event.keyCode == 53
            else { return event }

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
        guard let session = manager?.beginAnimatedDismissal(reason: .close),
              let configuration
        else { return }
        animateClose(session: session, configuration: configuration)
    }

    @objc private func closeButtonPressed() {
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

        guard manager.beginAnimatedDismissal(reason: .close) != nil else { return }
        animateClose(session: session, configuration: configuration)
    }

    @objc private func openButtonPressed() {
        manager?.moveToNewTab()
    }

    @objc private func splitButtonPressed() {
        guard splitButton.isEnabled else { return }
        manager?.moveToSplitView()
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

private final class GlanceBackdropView: NSView {
    var onMouseDown: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
    }
}

private final class GlanceActionButton: NSButton {
    private let symbolName: String
    private var accentColor: NSColor = .controlAccentColor
    var requiresSecondPress: Bool = false {
        didSet { updateAppearance() }
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
        self.accentColor = accentColor
        updateAppearance()
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override func updateLayer() {
        super.updateLayer()
        updateAppearance()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    private func updateImage() {
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
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
        } else {
            background = NSColor.textColor.withAlphaComponent(0.92)
            foreground = accentColor
        }

        layer?.backgroundColor = background.cgColor
        contentTintColor = foreground
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
