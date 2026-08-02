import AppKit
import SumiWebRuntime

@MainActor
final class WindowWebContentVisualHandoffSession {
    private let containerView: WindowWebContentSplitHostLayoutView
    private let hostRegistry: WindowWebContentHostRegistry
    private let hostAttachments: WindowWebContentHostAttachmentService
    private let compositorRuntime: WebViewCompositorRuntime
    private let protectionRuntime: WebViewProtectionRuntime

    private lazy var covers = WindowWebContentVisualHandoffCoverController(
        containerView: containerView,
        releaseCover: { [weak self] webViewID, host, protectionLease in
            guard let self else { return }
            self.containerView.removeVisualHandoffCover(host)
            self.hostRegistry.parkHost(host)
            self.hostRegistry.removeParkedProtectedHost(for: webViewID)
            self.protectionRuntime.finishVisualHandoff(protectionLease)
        }
    )

    init(
        containerView: WindowWebContentSplitHostLayoutView,
        hostRegistry: WindowWebContentHostRegistry,
        hostAttachments: WindowWebContentHostAttachmentService,
        compositorRuntime: WebViewCompositorRuntime,
        protectionRuntime: WebViewProtectionRuntime
    ) {
        self.containerView = containerView
        self.hostRegistry = hostRegistry
        self.hostAttachments = hostAttachments
        self.compositorRuntime = compositorRuntime
        self.protectionRuntime = protectionRuntime
    }

    @discardableResult
    func begin(
        excluding incomingTabIDs: Set<UUID>,
        containerRegistration: WebViewCompositorContainerRegistration
    ) -> Bool {
        guard compositorRuntime.owns(containerRegistration) else { return false }
        var seenWebViewIDs = Set<ObjectIdentifier>()
        let outgoingHosts = hostRegistry.displayedHosts(excluding: incomingTabIDs)
        guard !outgoingHosts.isEmpty else { return false }

        covers.releaseCovers()
        let usesPromotedHostHandoff = incomingTabIDs.count == 1
            && incomingTabIDs.contains { tabID in
                compositorRuntime.hasPendingPromotedHost(
                    for: tabID,
                    in: containerRegistration.windowID,
                    containerRegistration: containerRegistration
                )
            }
        guard !usesPromotedHostHandoff else { return false }

        for host in outgoingHosts {
            guard compositorRuntime.owns(containerRegistration) else { break }
            let webViewID = ObjectIdentifier(host.webView)
            guard seenWebViewIDs.insert(webViewID).inserted else { continue }

            let frameInContainer = host.convert(host.bounds, to: containerView)
            guard let protectionLease = protectionRuntime.beginVisualHandoff(
                for: host.webView,
                containerRegistration: containerRegistration
            ) else {
                continue
            }
            guard compositorRuntime.owns(containerRegistration) else {
                protectionRuntime.finishVisualHandoff(protectionLease)
                break
            }
            hostAttachments.prepareForVisualHandoff(host)
            covers.placeCover(
                host,
                frameInContainer: frameInContainer,
                protectionLease: protectionLease
            )
        }

        return covers.hasCovers
    }

    func scheduleRelease() {
        covers.scheduleRelease()
    }

    func release() {
        covers.releaseCovers()
    }
}
