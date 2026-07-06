import AppKit
import SwiftUI

/// Owns a single `NSHostingController` for the SwiftUI sidebar so the column is not re-hosted by incidental
/// `WindowView` body recomputations (see APPLE_BRIDGING: stable owner at the framework boundary).
@MainActor
final class SidebarColumnViewController: NSViewController {
    private let sidebarRecoveryCoordinator: SidebarHostRecoveryHandling

    private var hostingController: NSViewController?
    private var widthConstraint: NSLayoutConstraint?
    private weak var registeredRecoveryAnchor: NSView?
    private let usesCollapsedOverlayRoot: Bool
    private let resizeGrabberView = SidebarResizeGrabberView(frame: .zero)
    private var resizeGrabberSidebarPosition: SidebarPosition = .left

    init(
        usesCollapsedOverlayRoot: Bool = false,
        sidebarRecoveryCoordinator: SidebarHostRecoveryHandling
    ) {
        self.usesCollapsedOverlayRoot = usesCollapsedOverlayRoot
        self.sidebarRecoveryCoordinator = sidebarRecoveryCoordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let containerView: SidebarColumnBaseContainerView = usesCollapsedOverlayRoot
            ? CollapsedSidebarOverlayRootView()
            : SidebarColumnContainerView()
        containerView.onWindowChanged = { [weak self] window in
            Task { @MainActor [weak self] in
                self?.syncRecoveryAnchor(window: window)
            }
        }
        containerView.onGeometryChanged = { [weak self] in
            self?.layoutResizeGrabber()
        }
        SidebarColumnPaintlessChrome.configure(containerView)
        view = containerView
        view.translatesAutoresizingMaskIntoConstraints = true
    }

    func updateHostedSidebar<Content: View>(
        root: Content,
        width: CGFloat,
        contextMenuController: SidebarContextMenuController? = nil,
        capturesOverlayBackgroundPointerEvents: Bool = false,
        isCollapsedOverlayVisible: Bool = false,
        collapsedShadowAnimationDuration: TimeInterval = 0,
        showsResizeHandle: Bool = false,
        sidebarPosition: SidebarPosition = .left,
        resizeGrabberColor: NSColor = .labelColor,
        windowState: BrowserWindowState? = nil,
        onResize: @escaping (_ width: CGFloat, _ windowState: BrowserWindowState, _ persist: Bool) -> Void = { _, _, _ in },
        onEndResize: @escaping (_ windowState: BrowserWindowState) -> Void = { _ in },
        onPointerDown: (() -> Void)? = nil
    ) {
        let containerView = view as? SidebarColumnBaseContainerView
        containerView?.contextMenuController = contextMenuController
        containerView?.onPointerDown = onPointerDown
        (view as? SidebarColumnContainerView)?
            .capturesOverlayBackgroundPointerEvents = capturesOverlayBackgroundPointerEvents
        if let collapsedRootView = view as? CollapsedSidebarOverlayRootView {
            collapsedRootView.isOverlayHitTestingEnabled = isCollapsedOverlayVisible
            collapsedRootView.setCollapsedShadowVisible(
                isCollapsedOverlayVisible,
                animationDuration: collapsedShadowAnimationDuration
            )
        }

        if let hostingController = hostingController as? SidebarHostingController<Content> {
            hostingController.rootView = root
            hostingController.onPointerDown = onPointerDown
            SidebarColumnPaintlessChrome.configure(hostingController.view)
            widthConstraint?.constant = width
        } else {
            removeHostingControllerIfNeeded()

            let nextHostingController = SidebarHostingController(rootView: root)
            nextHostingController.onPointerDown = onPointerDown
            SidebarColumnPaintlessChrome.configure(nextHostingController.view)
            hostingController = nextHostingController
            addChild(nextHostingController)
            view.addSubview(nextHostingController.view)
            nextHostingController.view.translatesAutoresizingMaskIntoConstraints = false
            let wc = nextHostingController.view.widthAnchor.constraint(equalToConstant: width)
            wc.priority = .defaultHigh
            NSLayoutConstraint.activate([
                nextHostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                nextHostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                nextHostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
                nextHostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                wc,
            ])
            widthConstraint = wc
            nextHostingController.view.layoutSubtreeIfNeeded()
        }

        containerView?.hostedSidebarView = hostingController?.view
        configureResizeGrabber(
            isVisible: showsResizeHandle,
            sidebarPosition: sidebarPosition,
            color: resizeGrabberColor,
            windowState: windowState,
            onResize: onResize,
            onEndResize: onEndResize,
            onPointerDown: onPointerDown
        )

        syncRecoveryAnchor(window: view.window)
    }

    func teardownSidebarHosting() {
        unregisterRecoveryAnchor()
        let containerView = view as? SidebarColumnBaseContainerView
        containerView?.hostedSidebarView = nil
        containerView?.contextMenuController = nil
        containerView?.onPointerDown = nil
        (view as? SidebarColumnContainerView)?.capturesOverlayBackgroundPointerEvents = false
        if let collapsedRootView = view as? CollapsedSidebarOverlayRootView {
            collapsedRootView.isOverlayHitTestingEnabled = false
            collapsedRootView.setCollapsedShadowVisible(false, animationDuration: 0)
        }
        resizeGrabberView.resetForReuse()
        resizeGrabberView.removeFromSuperview()
        widthConstraint?.isActive = false
        widthConstraint = nil
        removeHostingControllerIfNeeded()
    }

    private func syncRecoveryAnchor(window: NSWindow?) {
        guard let anchor = hostingController?.view else {
            unregisterRecoveryAnchor()
            return
        }

        if let registeredRecoveryAnchor,
           registeredRecoveryAnchor !== anchor {
            sidebarRecoveryCoordinator.unregister(anchor: registeredRecoveryAnchor)
        }

        registeredRecoveryAnchor = anchor
        sidebarRecoveryCoordinator.sync(anchor: anchor, window: window ?? anchor.window)
    }

    private func unregisterRecoveryAnchor() {
        guard let registeredRecoveryAnchor else { return }
        sidebarRecoveryCoordinator.unregister(anchor: registeredRecoveryAnchor)
        self.registeredRecoveryAnchor = nil
    }

    private func configureResizeGrabber(
        isVisible: Bool,
        sidebarPosition: SidebarPosition,
        color: NSColor,
        windowState: BrowserWindowState?,
        onResize: @escaping (_ width: CGFloat, _ windowState: BrowserWindowState, _ persist: Bool) -> Void,
        onEndResize: @escaping (_ windowState: BrowserWindowState) -> Void,
        onPointerDown: (() -> Void)?
    ) {
        guard let containerView = view as? SidebarColumnBaseContainerView else { return }

        if resizeGrabberView.superview !== containerView {
            resizeGrabberView.removeFromSuperview()
            containerView.addSubview(resizeGrabberView, positioned: .above, relativeTo: hostingController?.view)
        }

        resizeGrabberSidebarPosition = sidebarPosition
        resizeGrabberView.configure(
            isEnabled: isVisible && windowState?.isSidebarVisible == true,
            sidebarPosition: sidebarPosition,
            indicatorColor: color,
            windowState: windowState,
            onResize: onResize,
            onEndResize: onEndResize,
            onPointerDown: onPointerDown
        )
        layoutResizeGrabber()
    }

    private func layoutResizeGrabber() {
        guard let containerView = view as? SidebarColumnBaseContainerView,
              resizeGrabberView.superview === containerView else {
            return
        }

        resizeGrabberView.frame = SidebarResizeGrabberLayout.borderStripFrame(
            in: containerView.bounds,
            sidebarPosition: resizeGrabberSidebarPosition
        )
        resizeGrabberView.needsLayout = true
    }

    private func removeHostingControllerIfNeeded() {
        guard let hostingController else { return }
        hostingController.view.removeFromSuperview()
        hostingController.removeFromParent()
        self.hostingController = nil
    }
}
