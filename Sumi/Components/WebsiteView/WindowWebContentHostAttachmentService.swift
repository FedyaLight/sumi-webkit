import AppKit
import QuartzCore
import SwiftUI
import SumiWebRuntime

@MainActor
final class WindowWebContentHostAttachmentService {
    private let containerView: WindowWebContentSplitHostLayoutView
    private let hostRegistry: WindowWebContentHostRegistry
    private let compositorRuntime: WebViewCompositorRuntime
    private let protectionRuntime: WebViewProtectionRuntime
    private let backgroundTransitions: WindowWebContentBackgroundTransitionSession
    private let windowID: UUID
    private var chromeGeometry: BrowserChromeGeometry
    private var contentBackgroundColor: Color

    init(
        containerView: WindowWebContentSplitHostLayoutView,
        hostRegistry: WindowWebContentHostRegistry,
        compositorRuntime: WebViewCompositorRuntime,
        protectionRuntime: WebViewProtectionRuntime,
        backgroundTransitions: WindowWebContentBackgroundTransitionSession,
        windowID: UUID,
        chromeGeometry: BrowserChromeGeometry,
        contentBackgroundColor: Color
    ) {
        self.containerView = containerView
        self.hostRegistry = hostRegistry
        self.compositorRuntime = compositorRuntime
        self.protectionRuntime = protectionRuntime
        self.backgroundTransitions = backgroundTransitions
        self.windowID = windowID
        self.chromeGeometry = chromeGeometry
        self.contentBackgroundColor = contentBackgroundColor
    }

    func replaceHost(_ host: SumiWebViewContainerView, in slot: WindowWebContentPaneSlot) {
        clearPaneHost(slot)
        configureViewportStyle(on: host)
        hostRegistry.setHost(host, for: slot)
    }

    func moveDisplayedHost(
        _ host: SumiWebViewContainerView,
        to slot: WindowWebContentPaneSlot
    ) {
        clearPaneHost(slot)
        configureViewportStyle(on: host)
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
        let needsInsertion = host.superview == nil
        let needsPaneMove = host.superview != nil && host.superview !== paneView
        let needsReveal = host.isHidden
        let needsTransitionGate = needsInsertion || needsPaneMove || needsReveal
        let isStableAttach = host.superview === paneView
            && !host.isHidden
            && host.frame == paneView.bounds

        if isStableAttach {
            backgroundTransitions.settle(host.webView)
            performWithoutImplicitAnimations {
                guard self.compositorRuntime.owns(containerRegistration) else { return }
                self.hostRegistry.removeParkedProtectedHost(for: host.webView)
                host.autoresizingMask = [.width, .height]
                self.configureViewportStyle(on: host)
                host.attachDisplayedContentIfNeeded()
            }

            guard compositorRuntime.owns(containerRegistration) else { return }
            if isProtected {
                hostRegistry.parkProtectedHost(host)
            }
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
                host.prepareForSuperviewTransferPreservingDisplayedContent()
                host.removeFromSuperview()
            }
            if host.superview == nil || host.superview === paneView {
                paneView.placeContentHostAboveChromeShadow(host)
            }
            host.frame = paneView.bounds
            host.autoresizingMask = [.width, .height]
            self.configureViewportStyle(on: host)

            if needsTransitionGate {
                self.backgroundTransitions.begin(for: host.webView)
                host.webView.sumiSetDrawsBackground(false)
            }

            host.attachDisplayedContentIfNeeded()
            host.isHidden = false
            paneView.layoutSubtreeIfNeeded()
            host.layoutSubtreeIfNeeded()
        }

        guard compositorRuntime.owns(containerRegistration) else { return }
        if needsTransitionGate {
            backgroundTransitions.scheduleRestore(
                for: host.webView,
                containerRegistration: containerRegistration
            )
        } else {
            backgroundTransitions.settle(host.webView)
        }

        guard compositorRuntime.owns(containerRegistration) else { return }
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

    func updateViewportStyle(
        chromeGeometry: BrowserChromeGeometry,
        contentBackgroundColor: Color
    ) {
        self.chromeGeometry = chromeGeometry
        self.contentBackgroundColor = contentBackgroundColor
        for host in hostRegistry.displayedHosts {
            configureViewportStyle(on: host)
        }
    }

    private func removeHostFromDisplay(_ host: SumiWebViewContainerView) {
        backgroundTransitions.finish(for: host.webView)
        if protectionRuntime.isProtected(host.webView) {
            parkProtectedHost(host)
        } else {
            hostRegistry.removeParkedProtectedHost(for: host.webView)
            host.removeFromSuperview()
        }
    }

    private func parkProtectedHost(_ host: SumiWebViewContainerView) {
        hostRegistry.parkProtectedHost(host)
        host.isHidden = true
    }

    private func configureViewportStyle(on host: SumiWebViewContainerView) {
        host.setBrowserContentViewport(geometry: chromeGeometry)
        let backgroundColor = NSColor(contentBackgroundColor)
        host.webView.underPageBackgroundColor = backgroundColor
        host.webView.layer?.backgroundColor = backgroundColor.cgColor
        host.layer?.backgroundColor = backgroundColor.cgColor
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
