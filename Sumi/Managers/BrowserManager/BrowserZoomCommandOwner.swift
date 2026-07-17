import Foundation
import WebKit

@MainActor
final class BrowserZoomCommandOwner {
    private let windows: WindowRegistry
    private let targets: BrowserZoomTargetResolver
    private let policy: BrowserZoomPolicy
    private let publication: BrowserZoomPublication

    init(
        windows: WindowRegistry,
        targets: BrowserZoomTargetResolver,
        policy: BrowserZoomPolicy,
        publication: BrowserZoomPublication
    ) {
        self.windows = windows
        self.targets = targets
        self.policy = policy
        self.publication = publication
    }

    func zoomInCurrentTab() {
        guard let window = windows.activeWindow else { return }
        zoomInCurrentTab(in: window)
    }

    func zoomInCurrentTab(in window: BrowserWindowState) {
        apply(.up, in: window)
    }

    func zoomOutCurrentTab() {
        guard let window = windows.activeWindow else { return }
        zoomOutCurrentTab(in: window)
    }

    func zoomOutCurrentTab(in window: BrowserWindowState) {
        apply(.down, in: window)
    }

    func resetZoomCurrentTab() {
        guard let window = windows.activeWindow else { return }
        resetZoomCurrentTab(in: window)
    }

    func resetZoomCurrentTab(in window: BrowserWindowState) {
        guard let target = targets.activeTarget(in: window) else { return }
        policy.reset(target)
        publish(target, in: window, showNotification: true)
    }

    func loadZoomForTab(_ tabID: UUID) {
        guard let target = targets.target(
            for: tabID,
            activeWindow: windows.activeWindow
        ) else { return }
        policy.apply(to: target)
        guard let window = targets.windowState(for: target.tab) ?? windows.activeWindow else {
            return
        }
        publish(target, in: window, showNotification: false)
    }

    func loadZoomForTab(_ tabID: UUID, on webView: WKWebView) {
        guard let tab = targets.tab(tabID) else { return }
        let previous = webView.pageZoom
        policy.apply(to: targets.makeTarget(tab: tab, webView: webView))
        if webView.pageZoom != previous {
            publication.publishChange()
        }
    }

    func cleanupZoomForTab(_ tabID: UUID) {
        policy.removeTab(tabID)
        publication.publishChange()
    }

    func applyBoostAwareZoom(for tab: Tab, webView: WKWebView) {
        policy.apply(to: targets.makeTarget(tab: tab, webView: webView))
    }

    private func apply(_ direction: ZoomStepDirection, in window: BrowserWindowState) {
        guard let target = targets.activeTarget(in: window) else { return }
        policy.step(direction, target: target)
        publish(target, in: window, showNotification: true)
    }

    private func publish(
        _ target: BrowserZoomTarget,
        in window: BrowserWindowState,
        showNotification: Bool
    ) {
        publication.publish(
            tabID: target.tab.id,
            in: window,
            manager: policy.manager,
            showNotification: showNotification,
            commands: self
        )
    }
}
