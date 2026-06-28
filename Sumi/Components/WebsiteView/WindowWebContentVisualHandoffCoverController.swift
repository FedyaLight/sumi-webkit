import AppKit
import QuartzCore

@MainActor
protocol WindowWebContentVisualHandoffCoverContainer: AnyObject {
    func placeVisualHandoffCover(
        _ host: SumiWebViewContainerView,
        frameInContainer: NSRect
    )
    func removeVisualHandoffCover(_ host: SumiWebViewContainerView)
    func layoutSubtreeIfNeeded()
    func displayIfNeeded()
}

@MainActor
final class WindowWebContentVisualHandoffCoverController {
    private static let releaseDelay: TimeInterval = 0.1

    private let containerView: any WindowWebContentVisualHandoffCoverContainer
    private let releaseCover: (ObjectIdentifier, SumiWebViewContainerView) -> Void
    private var coverHosts: [ObjectIdentifier: SumiWebViewContainerView] = [:]
    private var releaseWorkItem: DispatchWorkItem?
    private var releaseGeneration = 0

    var hasCovers: Bool {
        !coverHosts.isEmpty
    }

    init(
        containerView: any WindowWebContentVisualHandoffCoverContainer,
        releaseCover: @escaping (ObjectIdentifier, SumiWebViewContainerView) -> Void
    ) {
        self.containerView = containerView
        self.releaseCover = releaseCover
    }

    func placeCover(
        _ host: SumiWebViewContainerView,
        frameInContainer: NSRect
    ) {
        containerView.placeVisualHandoffCover(host, frameInContainer: frameInContainer)
        coverHosts[ObjectIdentifier(host.webView)] = host
    }

    func scheduleRelease() {
        guard !coverHosts.isEmpty else { return }

        releaseWorkItem?.cancel()
        releaseGeneration &+= 1
        let generation = releaseGeneration
        CATransaction.flush()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.releaseGeneration == generation
            else {
                return
            }
            self.containerView.layoutSubtreeIfNeeded()
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

        let covers = coverHosts
        coverHosts.removeAll(keepingCapacity: true)
        for (webViewID, host) in covers {
            releaseCover(webViewID, host)
        }
    }
}
