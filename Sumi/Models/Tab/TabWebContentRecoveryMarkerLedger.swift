import SumiWebRuntime
import WebKit

/// Event-bounded process-recovery state for one logical committed-document
/// lineage. Entries are exact-WebView witnesses; no clock or retry task can
/// replenish the single automatic recovery allowance.
@MainActor
final class TabWebContentRecoveryMarkerLedger {
    private typealias WeakWebViewReference = WebViewIdentityWitness

    private struct Entry {
        let webView: WeakWebViewReference
        var state: PageRecoveryResidenceState
    }

    enum Admission: Equatable {
        case duplicate
        case admitted
        case failed
    }

    private var entriesByWebViewID: [ObjectIdentifier: Entry] = [:]
    private var authorizedResetWebViewsByID: [
        ObjectIdentifier: WeakWebViewReference
    ] = [:]
    private var automaticRecoveryConsumed = false

    /// Narrow compatibility seam for identity-ledger tests. Production callers
    /// use `begin(on:destination:snapshot:)` so failure presentation is exact.
    func markRequired(on webView: WKWebView) -> Bool {
        begin(
            on: webView,
            destination: URL(string: "about:blank")!,
            snapshot: nil
        ) == .admitted
    }

    func begin(
        on webView: WKWebView,
        destination: URL,
        snapshot: PageRecoverySessionSnapshot?
    ) -> Admission {
        let webViewID = ObjectIdentifier(webView)
        if let existing = exactEntry(on: webView) {
            switch existing.state.phase {
            case .pendingActivation, .waitingForOwner:
                return .duplicate
            case .recovering:
                entriesByWebViewID[webViewID] = Entry(
                    webView: WeakWebViewReference(webView),
                    state: PageRecoveryResidenceState(
                        phase: .failed,
                        destination: destination,
                        snapshot: snapshot ?? existing.state.snapshot
                    )
                )
                return .failed
            case .failed:
                return .duplicate
            }
        }
        let phase: PageRecoveryResidencePhase
        let admission: Admission
        if automaticRecoveryConsumed {
            phase = .failed
            admission = .failed
        } else {
            automaticRecoveryConsumed = true
            phase = .pendingActivation
            admission = .admitted
        }
        entriesByWebViewID[webViewID] = Entry(
            webView: WeakWebViewReference(webView),
            state: PageRecoveryResidenceState(
                phase: phase,
                destination: destination,
                snapshot: snapshot
            )
        )
        return admission
    }

    func isRecoveryRequired(on webView: WKWebView) -> Bool {
        guard let entry = exactEntry(on: webView) else { return false }
        switch entry.state.phase {
        case .pendingActivation, .waitingForOwner:
            return true
        case .recovering, .failed:
            return false
        }
    }

    func state(on webView: WKWebView) -> PageRecoveryResidenceState? {
        exactEntry(on: webView)?.state
    }

    func activate(on webView: WKWebView) -> Bool {
        mutateExactEntry(on: webView) { entry in
            guard entry.state.phase == .pendingActivation else { return false }
            entry.state = PageRecoveryResidenceState(
                phase: .waitingForOwner,
                destination: entry.state.destination,
                snapshot: entry.state.snapshot
            )
            return true
        }
    }

    func noteWaitingForOwner(on webView: WKWebView) {
        _ = mutateExactEntry(on: webView) { entry in
            switch entry.state.phase {
            case .pendingActivation, .waitingForOwner:
                entry.state = PageRecoveryResidenceState(
                    phase: .waitingForOwner,
                    destination: entry.state.destination,
                    snapshot: entry.state.snapshot
                )
                return true
            case .recovering, .failed:
                return false
            }
        }
    }

    func bind(
        on webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool {
        mutateExactEntry(on: webView) { entry in
            switch entry.state.phase {
            case .pendingActivation, .waitingForOwner:
                entry.state = PageRecoveryResidenceState(
                    phase: .recovering(navigationID: navigationID),
                    destination: entry.state.destination,
                    snapshot: entry.state.snapshot
                )
                return true
            case .recovering, .failed:
                return false
            }
        }
    }

    func failDelivery(on webView: WKWebView) {
        _ = mutateExactEntry(on: webView) { entry in
            guard entry.state.phase != .failed else { return false }
            entry.state = PageRecoveryResidenceState(
                phase: .failed,
                destination: entry.state.destination,
                snapshot: entry.state.snapshot
            )
            return true
        }
    }

    func failBoundNavigation(
        on webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool {
        mutateExactEntry(on: webView) { entry in
            guard entry.state.phase == .recovering(navigationID: navigationID)
            else { return false }
            entry.state = PageRecoveryResidenceState(
                phase: .failed,
                destination: entry.state.destination,
                snapshot: entry.state.snapshot
            )
            return true
        }
    }

    func settleCommit(
        on webView: WKWebView,
        navigationID: ObjectIdentifier
    ) {
        let webViewID = ObjectIdentifier(webView)
        if exactEntry(on: webView)?.state.phase
            == .recovering(navigationID: navigationID) {
            entriesByWebViewID.removeValue(forKey: webViewID)
        }
        guard authorizedResetWebViewsByID[webViewID]?.matches(webView) == true
        else { return }
        authorizedResetWebViewsByID.removeValue(forKey: webViewID)
        if entriesByWebViewID[webViewID]?.webView.matches(webView) == true {
            entriesByWebViewID.removeValue(forKey: webViewID)
        }
        automaticRecoveryConsumed = false
    }

    func authorizeReset(onCommitFrom webView: WKWebView) {
        authorizedResetWebViewsByID[ObjectIdentifier(webView)] =
            WeakWebViewReference(webView)
    }

    func clear(on webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        if entriesByWebViewID[webViewID]?.webView.matches(webView) == true {
            entriesByWebViewID.removeValue(forKey: webViewID)
        }
        if authorizedResetWebViewsByID[webViewID]?.matches(webView) == true {
            authorizedResetWebViewsByID.removeValue(forKey: webViewID)
        }
    }

    private func exactEntry(on webView: WKWebView) -> Entry? {
        let webViewID = ObjectIdentifier(webView)
        guard let entry = entriesByWebViewID[webViewID] else { return nil }
        guard entry.webView.matches(webView) else {
            entriesByWebViewID.removeValue(forKey: webViewID)
            return nil
        }
        return entry
    }

    private func mutateExactEntry(
        on webView: WKWebView,
        _ mutation: (inout Entry) -> Bool
    ) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        guard var entry = exactEntry(on: webView), mutation(&entry) else {
            return false
        }
        entriesByWebViewID[webViewID] = entry
        return true
    }
}
