import Combine
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
        var cancellables: Set<AnyCancellable> = []
    }

    private var observations: [ObjectIdentifier: WebViewObservation] = [:]
    weak var delegate: (any TabNavigationStateControllerDelegate)?

    func observe(_ webView: WKWebView) {
        let identifier = ObjectIdentifier(webView)
        guard observations[identifier] == nil else { return }

        var observation = WebViewObservation()
        installNavigationPublisher(for: webView, keyPath: \.canGoBack, storingIn: &observation)
        installNavigationPublisher(for: webView, keyPath: \.canGoForward, storingIn: &observation)
        installTitlePublisher(for: webView, storingIn: &observation)
        observations[identifier] = observation
    }

    func remove(_ webView: WKWebView) {
        observations.removeValue(forKey: ObjectIdentifier(webView))
    }

    private func installNavigationPublisher<Value>(
        for webView: WKWebView,
        keyPath: KeyPath<WKWebView, Value>,
        storingIn observation: inout WebViewObservation
    ) {
        webView.publisher(for: keyPath, options: [.new])
            .sink { [weak self, weak webView] _ in
                precondition(
                    Thread.isMainThread,
                    "WKWebView back/forward KVO must be delivered on the main thread"
                )
                guard let self, let webView else { return }
                self.emitNavigationStateChange(for: webView)
            }
            .store(in: &observation.cancellables)
    }

    private func installTitlePublisher(
        for webView: WKWebView,
        storingIn observation: inout WebViewObservation
    ) {
        webView.publisher(for: \.title, options: [.new])
            .sink { [weak self, weak webView] _ in
                precondition(
                    Thread.isMainThread,
                    "WKWebView title KVO must be delivered on the main thread"
                )
                guard let self, let webView else { return }
                self.emitTitleChange(for: webView)
            }
            .store(in: &observation.cancellables)
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
