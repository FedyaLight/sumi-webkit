import Foundation
import ObjectiveC
import WebKit

private enum TabWebViewProcessPrewarmingAssociatedKeys {
    private static let stateStorage = StaticString(
        "Sumi.TabWebViewProcessPrewarming.state"
    )

    static var state: UnsafeRawPointer {
        UnsafeRawPointer(stateStorage.utf8Start)
    }
}

private enum TabWebViewProcessPrewarmingState: Int {
    case inFlight = 1
    case ready = 2
    case failed = 3
}

@MainActor
private extension WKWebView {
    var sumiProcessPrewarmingState: TabWebViewProcessPrewarmingState? {
        get {
            guard let rawValue = objc_getAssociatedObject(
                self,
                TabWebViewProcessPrewarmingAssociatedKeys.state
            ) as? Int else {
                return nil
            }
            return TabWebViewProcessPrewarmingState(rawValue: rawValue)
        }
        set {
            objc_setAssociatedObject(
                self,
                TabWebViewProcessPrewarmingAssociatedKeys.state,
                newValue?.rawValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

/// Starts WebContent for an exact, fully provisioned future tab WebView before
/// the tab-selection path needs it. The same canonical untracked instance is
/// later adopted by `TabWebViewMaterializationService`.
@MainActor
final class TabWebViewProcessPrewarmingService {
    typealias CandidateProvider = @MainActor (Tab) -> WKWebView?
    typealias ProcessLauncher = @MainActor (
        WKWebView,
        @escaping @MainActor (Error?) -> Void
    ) -> Void
    typealias CandidateRelease = @MainActor (Tab, WKWebView) -> Void

    private static let expirationNanoseconds: UInt64 = 2_000_000_000

    private let provideCandidate: CandidateProvider
    private let launchProcess: ProcessLauncher
    private let releaseCandidate: CandidateRelease
    private let expirationNanoseconds: UInt64

    static func live(
        releaseCandidate: @escaping CandidateRelease
    ) -> TabWebViewProcessPrewarmingService {
        TabWebViewProcessPrewarmingService(
            candidate: { tab in
                tab.ensureUntrackedNormalWebViewOutcome(
                    reason: "TabWebViewProcessPrewarmingService.prepare",
                    initialLoadPolicy: .deferUntilTracked
                ).webView
            },
            launchProcess: { webView, completion in
                webView.evaluateJavaScript("void 0") { _, error in
                    MainActor.assumeIsolated {
                        completion(error)
                    }
                }
            },
            releaseCandidate: releaseCandidate
        )
    }

    init(
        candidate: @escaping CandidateProvider,
        launchProcess: @escaping ProcessLauncher,
        releaseCandidate: @escaping CandidateRelease = { _, _ in },
        expirationNanoseconds: UInt64 =
            TabWebViewProcessPrewarmingService.expirationNanoseconds
    ) {
        provideCandidate = candidate
        self.launchProcess = launchProcess
        self.releaseCandidate = releaseCandidate
        self.expirationNanoseconds = expirationNanoseconds
    }

    func prepare(_ tab: Tab) {
        guard Self.supportsProcessPrewarming(tab.url),
              tab.hasCurrentWebView == false,
              let webView = provideCandidate(tab),
              webView.configuration.sumiIsNormalTabWebViewConfiguration,
              webView.sumiProcessPrewarmingState == nil
        else {
            return
        }

        webView.sumiProcessPrewarmingState = .inFlight
        let interval = PerformanceTrace.beginInterval(
            "TabWebViewProcessPrewarming.launch"
        )
        scheduleExpiration(of: webView, for: tab)
        launchProcess(webView) { [weak webView] error in
            PerformanceTrace.endInterval(
                "TabWebViewProcessPrewarming.launch",
                interval
            )
            guard let webView,
                  webView.sumiProcessPrewarmingState == .inFlight
            else {
                return
            }
            webView.sumiProcessPrewarmingState =
                error == nil ? .ready : .failed
            RuntimeDiagnostics.debug(category: "WebViewProcessPrewarming") {
                error == nil
                    ? "Exact tab WebContent process is ready"
                    : "Exact tab WebContent process launch failed"
            }
        }
    }

    private func scheduleExpiration(
        of webView: WKWebView,
        for tab: Tab
    ) {
        let expirationNanoseconds = expirationNanoseconds
        Task { @MainActor [weak self, weak tab, weak webView] in
            try? await Task.sleep(nanoseconds: expirationNanoseconds)
            guard let self,
                  let tab,
                  let webView,
                  webView.sumiProcessPrewarmingState != nil,
                  tab.webViewSession.untrackedWebView === webView
            else {
                return
            }
            webView.sumiProcessPrewarmingState = nil
            self.releaseCandidate(tab, webView)
            RuntimeDiagnostics.debug(
                "Released an unclaimed exact tab WebView",
                category: "WebViewProcessPrewarming"
            )
        }
    }

    static func checkOut(_ webView: WKWebView) {
        guard let state = webView.sumiProcessPrewarmingState else { return }
        RuntimeDiagnostics.debug(category: "WebViewProcessPrewarming") {
            "Exact tab WebView checked out state=\(state)"
        }
        webView.sumiProcessPrewarmingState = nil
    }

    private static func supportsProcessPrewarming(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    #if DEBUG
    static func stateForTesting(
        _ webView: WKWebView
    ) -> String? {
        webView.sumiProcessPrewarmingState.map(String.init(describing:))
    }
    #endif
}
