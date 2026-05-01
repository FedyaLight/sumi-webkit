import AppKit
import SwiftUI

/// Owns a single `NSHostingController` for the SwiftUI sidebar so the column is not re-hosted by incidental
/// `WindowView` body recomputations (see APPLE_BRIDGING: stable owner at the framework boundary).
@MainActor
final class SidebarColumnViewController: NSViewController {
    var sidebarRecoveryCoordinator: SidebarHostRecoveryHandling = SidebarHostRecoveryCoordinator.shared

    private var hostingController: NSViewController?
    private var widthConstraint: NSLayoutConstraint?
    private weak var registeredRecoveryAnchor: NSView?
    private var webContentExclusionPresentationContext: SidebarPresentationContext?
    private weak var webContentExclusionWindowState: BrowserWindowState?

    override func loadView() {
        let containerView = SidebarColumnContainerView()
        containerView.onWindowChanged = { [weak self] window in
            Task { @MainActor [weak self] in
                self?.syncRecoveryAnchor(window: window)
                self?.syncWebContentInputExclusion()
            }
        }
        containerView.onGeometryChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncWebContentInputExclusion()
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
        capturesPanelBackgroundPointerEvents: Bool = false
    ) {
        let previousHostedSidebarView = hostingController?.view
        if let containerView = view as? SidebarColumnContainerView {
            containerView.contextMenuController = contextMenuController
            containerView.capturesPanelBackgroundPointerEvents = capturesPanelBackgroundPointerEvents
        }

        if let hostingController = hostingController as? SidebarHostingController<Content> {
            hostingController.rootView = root
            SidebarColumnPaintlessChrome.configure(hostingController.view)
            widthConstraint?.constant = width
        } else {
            removeHostingControllerIfNeeded()

            let nextHostingController = SidebarHostingController(rootView: root)
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

        (view as? SidebarColumnContainerView)?.hostedSidebarView = hostingController?.view
        SidebarUITestDragMarker.recordEvent(
            "hostedSidebarUpdate",
            dragItemID: nil,
            ownerDescription: "nil",
            viewDescription: sidebarViewDebugDescription(hostingController?.view),
            details: "reusedHostedRoot=\(previousHostedSidebarView === hostingController?.view) previousHostedRoot=\(sidebarViewDebugDescription(previousHostedSidebarView)) hostedRoot=\(sidebarViewDebugDescription(hostingController?.view)) controller=\(sidebarObjectDebugDescription(hostingController)) width=\(Int(width))"
        )

        syncRecoveryAnchor(window: view.window)
        syncWebContentInputExclusion()
    }

    func updateWebContentInputExclusion(
        presentationContext: SidebarPresentationContext,
        windowState: BrowserWindowState
    ) {
        webContentExclusionPresentationContext = presentationContext
        webContentExclusionWindowState = windowState
        syncWebContentInputExclusion()
    }

    func teardownSidebarHosting() {
        clearWebContentInputExclusion()
        webContentExclusionPresentationContext = nil
        webContentExclusionWindowState = nil
        unregisterRecoveryAnchor()
        if let containerView = view as? SidebarColumnContainerView {
            containerView.hostedSidebarView = nil
            containerView.contextMenuController = nil
            containerView.capturesPanelBackgroundPointerEvents = false
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
           registeredRecoveryAnchor !== anchor
        {
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

    private func syncWebContentInputExclusion() {
        guard let presentationContext = webContentExclusionPresentationContext,
              let windowState = webContentExclusionWindowState
        else {
            clearWebContentInputExclusion()
            return
        }

        let region = CollapsedSidebarWebContentInputExclusion.region(
            panelView: view,
            presentationContext: presentationContext,
            isSidebarCollapsed: !windowState.isSidebarVisible
        )
        windowState.updateWebContentInputExclusionRegion(region)
    }

    private func clearWebContentInputExclusion() {
        webContentExclusionWindowState?.updateWebContentInputExclusionRegion(.empty)
    }

    private func removeHostingControllerIfNeeded() {
        guard let hostingController else { return }
        hostingController.view.removeFromSuperview()
        hostingController.removeFromParent()
        self.hostingController = nil
    }
}
