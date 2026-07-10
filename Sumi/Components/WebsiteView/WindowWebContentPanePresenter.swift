import Foundation
import SumiWebRuntime

@MainActor
final class WindowWebContentPanePresenter {
    private let browserContext: any WindowWebContentBrowserContext
    private let windowState: BrowserWindowState
    private let containerView: WindowWebContentSplitHostLayoutView
    private let compositorRuntime: WebViewCompositorRuntime
    private let hostRegistry: WindowWebContentHostRegistry
    private let hostResolver: WindowWebContentHostResolver
    private let hostAttachments: WindowWebContentHostAttachmentService

    init(
        browserContext: any WindowWebContentBrowserContext,
        windowState: BrowserWindowState,
        containerView: WindowWebContentSplitHostLayoutView,
        compositorRuntime: WebViewCompositorRuntime,
        hostRegistry: WindowWebContentHostRegistry,
        hostResolver: WindowWebContentHostResolver,
        hostAttachments: WindowWebContentHostAttachmentService
    ) {
        self.browserContext = browserContext
        self.windowState = windowState
        self.containerView = containerView
        self.compositorRuntime = compositorRuntime
        self.hostRegistry = hostRegistry
        self.hostResolver = hostResolver
        self.hostAttachments = hostAttachments
    }

    @discardableResult
    func presentSinglePane(
        tab: Tab?,
        containerRegistration: WebViewCompositorContainerRegistration
    ) -> Bool {
        guard compositorRuntime.owns(containerRegistration) else { return false }
        containerView.setPaneLayout(.single)
        containerView.layoutSubtreeIfNeeded()
        containerView.singlePaneView.isHidden = false

        if let tab,
           let host = hostResolver.resolveHost(
               for: tab,
               slot: .single,
               containerRegistration: containerRegistration
           ) {
            guard compositorRuntime.owns(containerRegistration) else { return false }
            hostAttachments.attach(
                host,
                to: containerView.singlePaneView,
                containerRegistration: containerRegistration
            )
            guard compositorRuntime.owns(containerRegistration) else { return false }
            containerView.singlePaneView.removeHostedSubviews(
                keeping: host,
                shouldRemove: hostAttachments.shouldRemoveHostedSubview
            )
        } else {
            guard compositorRuntime.owns(containerRegistration) else { return false }
            hostAttachments.clearSinglePane()
        }

        guard compositorRuntime.owns(containerRegistration) else { return false }
        hostAttachments.clearAllSplitPaneHosts()
        return compositorRuntime.owns(containerRegistration)
    }

    @discardableResult
    func presentSplitGroup(
        _ group: SplitGroup,
        tabs: [Tab],
        containerRegistration: WebViewCompositorContainerRegistration
    ) -> Bool {
        guard compositorRuntime.owns(containerRegistration) else { return false }
        containerView.setPaneLayout(.split(group))
        containerView.layoutSubtreeIfNeeded()

        let visibleTabIDs = Set(group.tabIds)
        for tabID in hostRegistry.splitPaneTabIds where !visibleTabIDs.contains(tabID) {
            guard compositorRuntime.owns(containerRegistration) else { return false }
            hostAttachments.clearSplitPaneHost(tabID)
        }

        for tab in tabs {
            guard compositorRuntime.owns(containerRegistration) else { return false }
            guard let paneView = containerView.paneView(for: tab.id) else {
                hostAttachments.clearSplitPaneHost(tab.id)
                continue
            }
            if let host = hostResolver.resolveHost(
                for: tab,
                slot: .split(tab.id),
                containerRegistration: containerRegistration
            ) {
                guard compositorRuntime.owns(containerRegistration) else { return false }
                paneView.configureSplitControls(
                    tab: tab,
                    browserContext: browserContext,
                    windowState: windowState
                )
                hostAttachments.attach(
                    host,
                    to: paneView,
                    containerRegistration: containerRegistration
                )
                guard compositorRuntime.owns(containerRegistration) else { return false }
                paneView.removeHostedSubviews(
                    keeping: host,
                    shouldRemove: hostAttachments.shouldRemoveHostedSubview
                )
            } else {
                guard compositorRuntime.owns(containerRegistration) else { return false }
                paneView.clearSplitControls()
                hostAttachments.clearSplitPaneHost(tab.id)
            }
        }

        guard compositorRuntime.owns(containerRegistration) else { return false }
        hostAttachments.clearSinglePane()
        return compositorRuntime.owns(containerRegistration)
    }
}
