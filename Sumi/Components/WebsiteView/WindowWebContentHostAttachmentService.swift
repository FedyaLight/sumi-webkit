import AppKit
import QuartzCore
import SumiWebRuntime
import WebKit

@MainActor
final class WindowWebContentHostAttachmentService {
    private let containerView: WindowWebContentSplitHostLayoutView
    private let hostRegistry: WindowWebContentHostRegistry
    private let compositorRuntime: WebViewCompositorRuntime
    private let protectionRuntime: WebViewProtectionRuntime
    private let windowID: UUID
    private var surfaceStyle: BrowserContentSurfaceStyle

    init(
        containerView: WindowWebContentSplitHostLayoutView,
        hostRegistry: WindowWebContentHostRegistry,
        compositorRuntime: WebViewCompositorRuntime,
        protectionRuntime: WebViewProtectionRuntime,
        windowID: UUID,
        surfaceStyle: BrowserContentSurfaceStyle
    ) {
        self.containerView = containerView
        self.hostRegistry = hostRegistry
        self.compositorRuntime = compositorRuntime
        self.protectionRuntime = protectionRuntime
        self.windowID = windowID
        self.surfaceStyle = surfaceStyle
    }

    func replaceHost(_ host: SumiWebViewContainerView, in slot: WindowWebContentPaneSlot) {
        clearPaneHost(slot)
        hostRegistry.setHost(host, for: slot)
    }

    func parkedHost(
        for tabID: UUID,
        webView: WKWebView
    ) -> SumiWebViewContainerView? {
        hostRegistry.parkedHost(for: tabID, webView: webView)
    }

    func moveDisplayedHost(
        _ host: SumiWebViewContainerView,
        to slot: WindowWebContentPaneSlot
    ) {
        clearPaneHost(slot)
        hostRegistry.clearReferences(to: host)
        hostRegistry.setHost(host, for: slot)
    }

    func attach(
        _ host: SumiWebViewContainerView,
        to paneView: PaneContainerView,
        containerRegistration: WebViewCompositorContainerRegistration
    ) {
        guard compositorRuntime.owns(containerRegistration) else { return }
        let isProtected = protectionRuntime.isProtected(host.webView)
        let isStableAttach = host.superview === paneView
            && !host.isHidden
            && host.frame == paneView.bounds

        if isStableAttach {
            performWithoutImplicitAnimations {
                guard self.compositorRuntime.owns(containerRegistration) else { return }
                self.hostRegistry.removeParkedProtectedHost(for: host.webView)
                host.autoresizingMask = [.width, .height]
                self.applySurfaceBackground(to: host.webView)
                host.attachDisplayedContentIfNeeded()
            }

            guard compositorRuntime.owns(containerRegistration) else { return }
            if isProtected {
                hostRegistry.parkProtectedHost(host)
            }
            containerView.contentVisibilityDidChange()
            compositorRuntime.pageHostDidAttach(
                tabID: host.tabID,
                in: windowID,
                window: paneView.window
            )
            compositorRuntime.completePromotedHostAttachment(
                for: host.tabID,
                in: windowID,
                containerRegistration: containerRegistration
            )
            return
        }

        performWithoutImplicitAnimations {
            guard self.compositorRuntime.owns(containerRegistration) else { return }
            self.hostRegistry.removeParkedProtectedHost(for: host.webView)
            if host.superview != nil && host.superview !== paneView {
                host.removeFromSuperview()
            }
            if host.superview == nil {
                paneView.placeContentHost(host)
            }
            host.frame = paneView.bounds
            host.autoresizingMask = [.width, .height]
            self.applySurfaceBackground(to: host.webView)

            host.attachDisplayedContentIfNeeded()
            host.isHidden = false
        }
        containerView.contentVisibilityDidChange()

        guard compositorRuntime.owns(containerRegistration) else { return }
        compositorRuntime.pageHostDidAttach(
            tabID: host.tabID,
            in: windowID,
            window: paneView.window
        )
        if isProtected {
            hostRegistry.parkProtectedHost(host)
        }
        compositorRuntime.completePromotedHostAttachment(
            for: host.tabID,
            in: windowID,
            containerRegistration: containerRegistration
        )
    }

    func clearPaneHost(_ slot: WindowWebContentPaneSlot) {
        switch slot {
        case .single:
            clearSinglePane()
        case .split(let tabID):
            clearSplitPaneHost(tabID)
        }
    }

    func clearSinglePane() {
        if let host = hostRegistry.removeSinglePaneHost() {
            removeHostFromDisplay(host)
        }
        containerView.singlePaneView.removeHostedSubviews(
            keeping: nil,
            shouldRemove: shouldRemoveHostedSubview
        )
        containerView.contentVisibilityDidChange()
    }

    func clearSplitPaneHost(_ tabID: UUID) {
        if let host = hostRegistry.removeSplitPaneHost(for: tabID) {
            removeHostFromDisplay(host)
        }
        if let paneView = containerView.paneView(for: tabID) {
            paneView.clearSplitControls()
            paneView.removeHostedSubviews(
                keeping: nil,
                shouldRemove: shouldRemoveHostedSubview
            )
        }
        containerView.contentVisibilityDidChange()
    }

    func clearAllSplitPaneHosts() {
        for tabID in hostRegistry.splitPaneTabIds {
            clearSplitPaneHost(tabID)
        }
        containerView.clearSplitTree()
    }

    func prepareForVisualHandoff(_ host: SumiWebViewContainerView) {
        hostRegistry.clearReferences(to: host)
        hostRegistry.parkProtectedHost(host)
    }

    func shouldRemoveHostedSubview(_ subview: NSView) -> Bool {
        guard let host = subview as? SumiWebViewContainerView else {
            return true
        }
        if protectionRuntime.isProtected(host.webView) {
            parkProtectedHost(host)
            return false
        }
        hostRegistry.removeParkedProtectedHost(for: host.webView)
        return true
    }

    func updateSurfaceStyle(_ style: BrowserContentSurfaceStyle) {
        guard surfaceStyle != style else { return }
        surfaceStyle = style
        containerView.setSurfaceStyle(style)
        for host in hostRegistry.displayedHosts {
            applySurfaceBackground(to: host.webView)
        }
    }

    private func removeHostFromDisplay(_ host: SumiWebViewContainerView) {
        if protectionRuntime.isProtected(host.webView) {
            parkProtectedHost(host)
        } else {
            hostRegistry.removeParkedProtectedHost(for: host.webView)
            hostRegistry.parkHost(host)
            containerView.parkHost(host)
        }
    }

    private func parkProtectedHost(_ host: SumiWebViewContainerView) {
        hostRegistry.parkProtectedHost(host)
        host.isHidden = true
    }

    private func applySurfaceBackground(to webView: WKWebView) {
        webView.underPageBackgroundColor = surfaceStyle.backgroundColor
    }

    private func performWithoutImplicitAnimations(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            updates()
        }
        CATransaction.commit()
    }
}
