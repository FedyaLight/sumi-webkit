import WebKit
import SumiWebRuntime

@MainActor
final class WindowWebContentHostResolver {
    private let ownershipQuery: WebViewOwnershipQuery
    private let ownershipService: WebViewOwnershipService
    private let compositorRuntime: WebViewCompositorRuntime
    private let protectionRuntime: WebViewProtectionRuntime
    private let hostRegistry: WindowWebContentHostRegistry
    private let hostAttachments: WindowWebContentHostAttachmentService
    private let windowID: UUID

    init(
        ownershipQuery: WebViewOwnershipQuery,
        ownershipService: WebViewOwnershipService,
        compositorRuntime: WebViewCompositorRuntime,
        protectionRuntime: WebViewProtectionRuntime,
        hostRegistry: WindowWebContentHostRegistry,
        hostAttachments: WindowWebContentHostAttachmentService,
        windowID: UUID
    ) {
        self.ownershipQuery = ownershipQuery
        self.ownershipService = ownershipService
        self.compositorRuntime = compositorRuntime
        self.protectionRuntime = protectionRuntime
        self.hostRegistry = hostRegistry
        self.hostAttachments = hostAttachments
        self.windowID = windowID
    }

    func resolveHost(
        for tab: Tab,
        slot: WindowWebContentPaneSlot,
        containerRegistration: WebViewCompositorContainerRegistration
    ) -> SumiWebViewContainerView? {
        guard compositorRuntime.owns(containerRegistration) else { return nil }
        guard tab.requiresPrimaryWebView else {
            hostAttachments.clearPaneHost(slot)
            return nil
        }

        let webView = ownershipQuery.webView(for: tab.id, in: windowID)
            ?? ownershipService.webView(for: tab, in: windowID)
        guard let webView else {
            hostAttachments.clearPaneHost(slot)
            return nil
        }
        guard compositorRuntime.owns(containerRegistration) else { return nil }

        if let host = hostRegistry.host(for: slot),
           host.tabID == tab.id,
           host.webView === webView {
            return host
        }

        if let promotedHost = compositorRuntime.takePromotedHost(
            for: tab.id,
            in: windowID,
            containerRegistration: containerRegistration,
            expectedWebView: webView
        ) as? SumiWebViewContainerView {
            guard compositorRuntime.owns(containerRegistration) else { return nil }
            hostAttachments.replaceHost(promotedHost, in: slot)
            return promotedHost
        }

        if let displayedHost = hostRegistry.displayedHost(for: tab.id),
           displayedHost.webView === webView {
            guard compositorRuntime.owns(containerRegistration) else { return nil }
            hostAttachments.moveDisplayedHost(displayedHost, to: slot)
            return displayedHost
        }

        if protectionRuntime.isProtected(webView),
           let protectedHost = hostRegistry.protectedHost(for: webView) {
            guard compositorRuntime.owns(containerRegistration) else { return nil }
            hostAttachments.moveDisplayedHost(protectedHost, to: slot)
            return protectedHost
        }

        guard compositorRuntime.owns(containerRegistration) else { return nil }
        let host = SumiWebViewContainerView(tabID: tab.id, webView: webView)
        guard compositorRuntime.owns(containerRegistration) else { return nil }
        hostAttachments.replaceHost(host, in: slot)
        return host
    }
}
