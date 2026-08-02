import AppKit
import Foundation
import SumiWebRuntime
import WebKit

/// Owns the window/compositor presentation capability for browser WebViews.
/// It does not own navigation, profile transitions, or canonical placement.
@MainActor
final class WebViewCompositorRuntime {
    private let visibleRuntime: VisibleWebViewRuntimeOwner
    private let pageActivationPerformance: PageActivationPerformanceMonitor
    private let scheduleProtectedCommand: (
        DeferredWebViewCommand,
        WKWebView,
        String
    ) -> DeferredProtectedCommandSchedulingOutcome
    private let pruneInvalidProtectedCommands: (String) -> Void

    init(
        visibleRuntime: VisibleWebViewRuntimeOwner,
        pageActivationPerformance: PageActivationPerformanceMonitor,
        scheduleProtectedCommand: @escaping (
            DeferredWebViewCommand,
            WKWebView,
            String
        ) -> DeferredProtectedCommandSchedulingOutcome,
        pruneInvalidProtectedCommands: @escaping (String) -> Void
    ) {
        self.visibleRuntime = visibleRuntime
        self.pageActivationPerformance = pageActivationPerformance
        self.scheduleProtectedCommand = scheduleProtectedCommand
        self.pruneInvalidProtectedCommands = pruneInvalidProtectedCommands
    }

    @discardableResult
    func registerContainer(
        _ view: NSView,
        for windowID: UUID,
        immediateVisualHandoffHandler: (@MainActor () -> Bool)? = nil
    ) -> WebViewCompositorContainerRegistration {
        visibleRuntime.registerCompositorContainerView(
            view,
            for: windowID,
            immediateVisualHandoffHandler: immediateVisualHandoffHandler
        )
    }

    @discardableResult
    func performImmediateVisualHandoffIfPossible(in windowID: UUID) -> Bool {
        visibleRuntime.performImmediateVisualHandoffIfPossible(in: windowID)
    }

    func containerView(for windowID: UUID) -> NSView? {
        visibleRuntime.compositorContainerView(for: windowID)
    }

    func owns(
        _ registration: WebViewCompositorContainerRegistration
    ) -> Bool {
        visibleRuntime.isCurrentCompositorContainerRegistration(registration)
    }

    func removeContainer(for windowID: UUID) {
        visibleRuntime.removeCompositorContainerView(
            for: windowID,
            pruneInvalidDeferredCommands: pruneInvalidProtectedCommands
        )
    }

    @discardableResult
    func removeContainer(
        _ registration: WebViewCompositorContainerRegistration
    ) -> Bool {
        visibleRuntime.removeCompositorContainerView(
            registration,
            pruneInvalidDeferredCommands: pruneInvalidProtectedCommands
        )
    }

    @discardableResult
    func tearDownContainer(
        _ registration: WebViewCompositorContainerRegistration,
        teardown: () -> Void
    ) -> Bool {
        visibleRuntime.tearDownCompositorContainerView(
            registration,
            teardown: teardown,
            pruneInvalidDeferredCommands: pruneInvalidProtectedCommands
        )
    }

    func containers() -> [(UUID, NSView)] {
        visibleRuntime.compositorContainers()
    }

    @discardableResult
    func registerPromotedHost(
        _ host: any WebRuntimePromotedHost,
        for tabID: UUID,
        in windowID: UUID,
        attachmentCompletion: PromotedHostAttachmentCompletion? = nil
    ) -> Bool {
        visibleRuntime.registerPromotedHost(
            host,
            for: tabID,
            in: windowID,
            attachmentCompletion: attachmentCompletion
        )
    }

    func takePromotedHost(
        for tabID: UUID,
        in windowID: UUID,
        containerRegistration: WebViewCompositorContainerRegistration,
        expectedWebView: WKWebView
    ) -> (any WebRuntimePromotedHost)? {
        visibleRuntime.takePromotedHost(
            for: tabID,
            in: windowID,
            containerRegistration: containerRegistration,
            expectedWebView: expectedWebView
        )
    }

    func hasPendingPromotedHost(
        for tabID: UUID,
        in windowID: UUID,
        containerRegistration: WebViewCompositorContainerRegistration
    ) -> Bool {
        visibleRuntime.hasPendingPromotedHost(
            for: tabID,
            in: windowID,
            containerRegistration: containerRegistration
        )
    }

    func completePromotedHostAttachment(
        for tabID: UUID,
        in windowID: UUID,
        containerRegistration: WebViewCompositorContainerRegistration
    ) {
        visibleRuntime.completePromotedHostAttachment(
            for: tabID,
            in: windowID,
            containerRegistration: containerRegistration
        )
    }

    func pageHostDidAttach(
        tabID: UUID,
        in windowID: UUID,
        window: NSWindow?
    ) {
        pageActivationPerformance.hostDidAttach(
            tabID: tabID,
            in: windowID,
            window: window
        )
    }

    func removeWebViewFromContainers(_ webView: WKWebView) {
        if scheduleProtectedCommand(
            .removeWebViewFromContainers(webViewID: ObjectIdentifier(webView)),
            webView,
            "WebViewCompositorRuntime.removeWebViewFromContainers"
        ).wasScheduled {
            return
        }

        for (_, container) in containers() {
            removeMatchingWebView(webView, from: container)
        }
    }

    private func removeMatchingWebView(_ webView: WKWebView, from root: NSView) {
        for subview in Array(root.subviews) {
            if let host = subview as? SumiWebViewContainerView,
               host.webView === webView {
                host.evictFromRuntime()
            } else if subview === webView {
                subview.removeFromSuperview()
            } else {
                removeMatchingWebView(webView, from: subview)
            }
        }
    }
}
