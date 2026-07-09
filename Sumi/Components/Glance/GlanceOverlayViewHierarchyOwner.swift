import AppKit

@MainActor
final class GlanceOverlayViewHierarchyOwner {
    private weak var rootView: GlanceOverlayRootView?
    private let webContentShieldAnchorView: GlanceWebContentShieldAnchorView
    private let contentShadowView: NSView
    private let webClipView: NSView
    private let actionChrome: GlanceOverlayActionChrome
    private let keyCommands: GlanceOverlayKeyCommandOwner
    private let presentationState: GlanceOverlayPresentationStateOwner
    private let previewHostAttachment: GlancePreviewHostAttachmentOwner
    private let overlayLayout: GlanceOverlayLayout
    private let resetCloseConfirmation: () -> Void
    private let configurationProvider: () -> GlanceOverlayConfiguration?
    private let managerProvider: () -> GlanceManager?
    private let sessionProvider: () -> GlanceSession?

    init(
        rootView: GlanceOverlayRootView?,
        webContentShieldAnchorView: GlanceWebContentShieldAnchorView,
        contentShadowView: NSView,
        webClipView: NSView,
        actionChrome: GlanceOverlayActionChrome,
        keyCommands: GlanceOverlayKeyCommandOwner,
        presentationState: GlanceOverlayPresentationStateOwner,
        previewHostAttachment: GlancePreviewHostAttachmentOwner,
        overlayLayout: GlanceOverlayLayout,
        resetCloseConfirmation: @escaping () -> Void,
        configurationProvider: @escaping () -> GlanceOverlayConfiguration?,
        managerProvider: @escaping () -> GlanceManager?,
        sessionProvider: @escaping () -> GlanceSession?
    ) {
        self.rootView = rootView
        self.webContentShieldAnchorView = webContentShieldAnchorView
        self.contentShadowView = contentShadowView
        self.webClipView = webClipView
        self.actionChrome = actionChrome
        self.keyCommands = keyCommands
        self.presentationState = presentationState
        self.previewHostAttachment = previewHostAttachment
        self.overlayLayout = overlayLayout
        self.resetCloseConfirmation = resetCloseConfirmation
        self.configurationProvider = configurationProvider
        self.managerProvider = managerProvider
        self.sessionProvider = sessionProvider
    }

    func installViewsIfNeeded() {
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

    func tearDownPresentedViews(preservingPromotionHandoff: Bool = false) {
        resetCloseConfirmation()
        presentationState.setPresentationVisible(false)
        publishContentFrame(nil, in: rootView)
        WebContentMouseTrackingShield.unregister(webContentShieldAnchorView)
        rootView?.acceptsBackgroundMouseEvents = false
        rootView?.sidebarPassthroughRect = nil
        rootView?.webContentCursorExclusionRect = nil
        rootView?.chromeCursorExclusionRect = nil
        previewHostAttachment.clear(preservingDisplayedContent: preservingPromotionHandoff)
        webContentShieldAnchorView.removeFromSuperview()
        actionChrome.removeFromSuperview()
        contentShadowView.removeFromSuperview()
    }

    func setPresentationVisible(_ isVisible: Bool) {
        presentationState.setPresentationVisible(isVisible)
        rootView?.acceptsBackgroundMouseEvents = isVisible
        contentShadowView.isHidden = !isVisible
        actionChrome.isHidden = !isVisible
        webContentShieldAnchorView.isHidden = !isVisible

        if isVisible {
            keyCommands.installIfNeeded()
            contentShadowView.alphaValue = 1
            actionChrome.alphaValue = 1
        } else {
            keyCommands.uninstall()
            publishContentFrame(nil, in: rootView)
            WebContentMouseTrackingShield.unregister(webContentShieldAnchorView)
            rootView?.sidebarPassthroughRect = nil
            rootView?.webContentCursorExclusionRect = nil
            rootView?.chromeCursorExclusionRect = nil
            resetCloseConfirmation()
        }
    }

    func layoutActionChrome(
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

    func layoutInteractionShield(
        in bounds: CGRect,
        contentFrame: CGRect
    ) {
        webContentShieldAnchorView.frame = bounds
        rootView?.sidebarPassthroughRect = configurationProvider().flatMap {
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

    func publishContentFrame(_ frame: CGRect?, in rootView: NSView?) {
        guard let manager = managerProvider(),
              let session = sessionProvider()
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

    func hideViewsForPromotionCompletion() {
        rootView?.acceptsBackgroundMouseEvents = false
        contentShadowView.isHidden = true
        actionChrome.isHidden = true
        webContentShieldAnchorView.isHidden = true
    }

    func preparePresentSurface() {
        guard let rootView else { return }
        rootView.acceptsBackgroundMouseEvents = true
        contentShadowView.isHidden = false
        actionChrome.isHidden = false
        webContentShieldAnchorView.isHidden = false
        keyCommands.installIfNeeded()
    }
}
