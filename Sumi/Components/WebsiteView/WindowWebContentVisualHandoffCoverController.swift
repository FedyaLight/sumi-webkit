import AppKit
import SumiWebRuntime

@MainActor
protocol WindowWebContentVisualHandoffCoverContainer: AnyObject {
    func placeVisualHandoffCover(
        _ host: SumiWebViewContainerView,
        frameInContainer: NSRect
    )
    func removeVisualHandoffCover(_ host: SumiWebViewContainerView)
    func displayIfNeeded()
}

@MainActor
final class WindowWebContentVisualHandoffCoverController {
    private struct Cover {
        let host: SumiWebViewContainerView
        let protectionLease: WebViewVisualHandoffProtectionLease
    }

    private static let releaseDelay: TimeInterval = 0.1

    private let containerView: any WindowWebContentVisualHandoffCoverContainer
    private let releaseCover: (
        ObjectIdentifier,
        SumiWebViewContainerView,
        WebViewVisualHandoffProtectionLease
    ) -> Void
    private var coversByWebViewID: [ObjectIdentifier: Cover] = [:]
    private var releaseWorkItem: DispatchWorkItem?
    private var releaseGeneration = 0

    var hasCovers: Bool {
        !coversByWebViewID.isEmpty
    }

    init(
        containerView: any WindowWebContentVisualHandoffCoverContainer,
        releaseCover: @escaping (
            ObjectIdentifier,
            SumiWebViewContainerView,
            WebViewVisualHandoffProtectionLease
        ) -> Void
    ) {
        self.containerView = containerView
        self.releaseCover = releaseCover
    }

    func placeCover(
        _ host: SumiWebViewContainerView,
        frameInContainer: NSRect,
        protectionLease: WebViewVisualHandoffProtectionLease
    ) {
        let webViewID = ObjectIdentifier(host.webView)
        precondition(
            coversByWebViewID[webViewID] == nil,
            "A visual handoff cover must release its existing protection lease before replacement"
        )
        containerView.placeVisualHandoffCover(host, frameInContainer: frameInContainer)
        coversByWebViewID[webViewID] = Cover(
            host: host,
            protectionLease: protectionLease
        )
    }

    func scheduleRelease() {
        guard !coversByWebViewID.isEmpty else { return }

        releaseWorkItem?.cancel()
        releaseGeneration &+= 1
        let generation = releaseGeneration

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.releaseGeneration == generation
            else {
                return
            }
            self.containerView.displayIfNeeded()
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.releaseGeneration == generation
                else {
                    return
                }
                self.releaseCovers()
            }
        }
        releaseWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.releaseDelay,
            execute: workItem
        )
    }

    func releaseCovers() {
        releaseGeneration &+= 1
        releaseWorkItem?.cancel()
        releaseWorkItem = nil

        let covers = coversByWebViewID
        coversByWebViewID.removeAll(keepingCapacity: true)
        for (webViewID, cover) in covers {
            releaseCover(webViewID, cover.host, cover.protectionLease)
        }
    }
}
