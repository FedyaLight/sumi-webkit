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

    private func removeHostingControllerIfNeeded() {
        guard let hostingController else { return }
        hostingController.view.removeFromSuperview()
        hostingController.removeFromParent()
        self.hostingController = nil
    }
}
