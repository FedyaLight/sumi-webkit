import Foundation
import WebKit

@MainActor
protocol TabNavigationStateControllerDelegate: AnyObject {
    func tabNavigationStateControllerDidObserveNavigationStateChange(
        _ controller: TabNavigationStateController
    )

    func tabNavigationStateController(
        _ controller: TabNavigationStateController,
        didObserveTitleChangeFor webView: WKWebView
    )
}

@MainActor
final class TabNavigationStateController {
    private struct WebViewObservation {
        var observations: [NSKeyValueObservation] = []
    }

    private var observations: [ObjectIdentifier: WebViewObservation] = [:]
    weak var delegate: (any TabNavigationStateControllerDelegate)?

    func observe(_ webView: WKWebView) {
        let identifier = ObjectIdentifier(webView)
        guard observations[identifier] == nil else { return }

        var observation = WebViewObservation()
        installNavigationObserver(for: webView, keyPath: \.canGoBack, storingIn: &observation)
        installNavigationObserver(for: webView, keyPath: \.canGoForward, storingIn: &observation)
        installTitleObserver(for: webView, storingIn: &observation)
        observations[identifier] = observation
    }

    func remove(_ webView: WKWebView) {
        observations.removeValue(forKey: ObjectIdentifier(webView))
    }

    private func installNavigationObserver<Value>(
        for webView: WKWebView,
        keyPath: KeyPath<WKWebView, Value>,
        storingIn observation: inout WebViewObservation
    ) {
        let obs = webView.observe(keyPath, options: [.new]) { [weak self, weak webView] _, _ in
            guard let self, let webView else { return }
            MainActor.assumeIsolated {
                self.emitNavigationStateChange(for: webView)
            }
        }
        observation.observations.append(obs)
    }

    private func installTitleObserver(
        for webView: WKWebView,
        storingIn observation: inout WebViewObservation
    ) {
        let obs = webView.observe(\.title, options: [.new]) { [weak self, weak webView] _, _ in
            guard let self, let webView else { return }
            MainActor.assumeIsolated {
                self.emitTitleChange(for: webView)
            }
        }
        observation.observations.append(obs)
    }

    private func emitNavigationStateChange(for webView: WKWebView) {
        guard observations[ObjectIdentifier(webView)] != nil else { return }
        delegate?.tabNavigationStateControllerDidObserveNavigationStateChange(self)
    }

    private func emitTitleChange(for webView: WKWebView) {
        guard observations[ObjectIdentifier(webView)] != nil else { return }
        delegate?.tabNavigationStateController(self, didObserveTitleChangeFor: webView)
    }
}

extension Tab: TabNavigationStateControllerDelegate {
    func tabNavigationStateControllerDidObserveNavigationStateChange(
        _ controller: TabNavigationStateController
    ) {
        updateNavigationState()
    }

    func tabNavigationStateController(
        _ controller: TabNavigationStateController,
        didObserveTitleChangeFor webView: WKWebView
    ) {
        updateTitle(from: webView)
    }
}
