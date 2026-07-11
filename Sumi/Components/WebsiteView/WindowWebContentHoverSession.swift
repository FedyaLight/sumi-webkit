import Foundation
import SumiWebRuntime

@MainActor
final class WindowWebContentHoverSession {
    private final class ObservedHost {
        weak var host: SumiWebViewContainerView?
        var observation: HostedWebViewPresentationObservation?

        init(host: SumiWebViewContainerView) {
            self.host = host
        }
    }

    private final class ObservedWebView {
        weak var webView: FocusableWKWebView?
        var observation: WebViewHoveredLinkObservation?

        init(webView: FocusableWKWebView) {
            self.webView = webView
        }
    }

    private let mutationGate: WindowWebContentCompositorMutationGate
    private let isDisplayed: (FocusableWKWebView) -> Bool
    private var hosts: [ObjectIdentifier: ObservedHost] = [:]
    private var observations: [ObjectIdentifier: ObservedWebView] = [:]
    private var activeSourceID: ObjectIdentifier?
    private var registration: WebViewCompositorContainerRegistration?
    private var deliver: ((String?) -> Void)?

    init(
        mutationGate: WindowWebContentCompositorMutationGate,
        isDisplayed: @escaping (FocusableWKWebView) -> Bool = { _ in true }
    ) {
        self.mutationGate = mutationGate
        self.isDisplayed = isDisplayed
    }

    func reconcile(
        hosts: [SumiWebViewContainerView],
        registration: WebViewCompositorContainerRegistration,
        deliver: @escaping (String?) -> Void
    ) {
        self.deliver = deliver
        self.registration = registration

        let hostsByID = Dictionary(
            hosts.map { (ObjectIdentifier($0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let staleHostIDs = self.hosts.compactMap { id, entry in
            hostsByID[id] == nil || entry.host !== hostsByID[id]
                ? id
                : nil
        }
        for id in staleHostIDs {
            self.hosts.removeValue(forKey: id)?.observation?.cancel()
        }

        for (id, host) in hostsByID where self.hosts[id]?.host !== host {
            let entry = ObservedHost(host: host)
            self.hosts[id] = entry
            entry.observation = host.observeActivePresentationWebView { [weak self, weak host] _ in
                guard let self,
                      let host,
                      self.hosts[id]?.host === host
                else { return }
                self.refreshObservedWebViewsFromHosts()
            }
        }

        refreshObservedWebViewsFromHosts()
    }

    func reconcile(
        webViews: [FocusableWKWebView],
        registration: WebViewCompositorContainerRegistration,
        deliver: @escaping (String?) -> Void
    ) {
        self.deliver = deliver
        self.registration = registration
        reconcileWebViews(webViews)
    }

    private func reconcileWebViews(_ webViews: [FocusableWKWebView]) {

        let webViewsByID = Dictionary(
            webViews.map { (ObjectIdentifier($0), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let staleIDs = observations.compactMap { id, entry in
            webViewsByID[id] == nil || entry.webView !== webViewsByID[id]
                ? id
                : nil
        }
        for id in staleIDs {
            observations.removeValue(forKey: id)?.observation?.cancel()
        }

        for (id, webView) in webViewsByID where observations[id]?.webView !== webView {
            let entry = ObservedWebView(webView: webView)
            observations[id] = entry
            entry.observation = webView.hoveredLink.observe { [weak self, weak webView] href in
                DispatchQueue.main.async { [weak self, weak webView] in
                    self?.receive(href, from: webView, id: id)
                }
            }
        }

        publishFreshestDisplayedLink()
    }

    func invalidate() {
        for entry in hosts.values {
            entry.observation?.cancel()
        }
        hosts.removeAll()
        for entry in observations.values {
            entry.observation?.cancel()
        }
        observations.removeAll()
        activeSourceID = nil
        registration = nil
        deliver = nil
    }

    private func refreshObservedWebViewsFromHosts() {
        guard let registration, mutationGate.owns(registration) else { return }
        let activeWebViews = hosts.values.compactMap {
            $0.host?.activePresentationWebView as? FocusableWKWebView
        }
        reconcileWebViews(activeWebViews)
    }

    private func receive(
        _ href: String?,
        from webView: FocusableWKWebView?,
        id: ObjectIdentifier
    ) {
        guard let webView,
              let registration,
              mutationGate.owns(registration),
              observations[id]?.webView === webView,
              isCurrentSource(webView)
        else { return }

        if let href {
            activeSourceID = id
            deliver?(href)
        } else if activeSourceID == id {
            publishFreshestDisplayedLink(excluding: id)
        }
    }

    private func publishFreshestDisplayedLink(
        excluding excludedID: ObjectIdentifier? = nil
    ) {
        guard let registration, mutationGate.owns(registration) else { return }

        let freshest = observations.compactMap { id, entry -> (
            ObjectIdentifier,
            WebViewHoveredLinkState.Snapshot
        )? in
            guard id != excludedID,
                  let webView = entry.webView,
                  isCurrentSource(webView)
            else { return nil }
            let snapshot = webView.hoveredLink.snapshot
            guard snapshot.href != nil else { return nil }
            return (id, snapshot)
        }.max { $0.1.updatedAt < $1.1.updatedAt }

        activeSourceID = freshest?.0
        deliver?(freshest?.1.href)
    }

    private func isCurrentSource(_ webView: FocusableWKWebView) -> Bool {
        guard isDisplayed(webView) else { return false }
        guard !hosts.isEmpty else { return true }
        return hosts.values.contains {
            $0.host?.activePresentationWebView === webView
        }
    }
}
