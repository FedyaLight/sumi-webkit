import Foundation
import SumiWebRuntime

@MainActor
private enum WebViewReplacementAppModelError: Error {
    case stale
}

/// Exact intent/rebuild-epoch model half of a live Tab generation replacement.
/// Replacement admission never publishes its provisional destination; the
/// authoritative WebKit commit remains the only writer of `Tab.url`.
@MainActor
final class TabWebViewRebuildModelTransaction:
    WebViewReplacementModelTransaction {
    private enum State { case prepared, staged, committed, rolledBack }

    private let tab: Tab
    private let intentRevision: UInt64
    private let semanticRevision: UInt64
    private let sourceURL: URL
    private let targetURL: URL
    private var state = State.prepared

    init(
        tab: Tab,
        intentRevision: UInt64,
        sourceURL: URL,
        targetURL: URL
    ) {
        self.tab = tab
        self.intentRevision = intentRevision
        self.semanticRevision = tab.mainFrameLoads.currentIntent.revision
        self.sourceURL = sourceURL
        self.targetURL = targetURL
    }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return tab.webViewRebuildEpoch.isCurrent(intentRevision)
            && tab.url == sourceURL
            && currentIntentIsExact()
    }

    func stage() throws {
        guard validateForStaging() else {
            throw WebViewReplacementAppModelError.stale
        }
        tab.cancelPendingMainFrameNavigation()
        state = .staged
    }

    func retainsModelAfterFailedStage() -> Bool { false }

    func stagedModelIsExact() -> Bool {
        guard case .staged = state else { return false }
        return tab.webViewRebuildEpoch.isCurrent(intentRevision)
            && tab.url == sourceURL
            && currentIntentIsExact()
    }

    func canClaimTerminalModel() -> Bool { stagedModelIsExact() }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        guard stagedModelIsExact() else { return .terminallyDrained }
        state = .committed
        return .sealed
    }

    func claimedModelIsExact() -> Bool {
        guard case .committed = state else { return false }
        return tab.webViewRebuildEpoch.isCurrent(intentRevision)
            && tab.url == sourceURL
            && currentIntentIsExact()
    }

    func publishCommit() {}

    func rollback() throws {
        guard stagedModelIsExact() else {
            throw WebViewReplacementAppModelError.stale
        }
        state = .rolledBack
    }

    func publishRollback() {}

    func canSettleTerminalDrain() -> Bool { true }

    func settleTerminalDrain() -> Bool {
        switch state {
        case .staged:
            state = .committed
        case .prepared:
            state = .rolledBack
        case .committed, .rolledBack:
            break
        }
        return true
    }

    private func currentIntentIsExact() -> Bool {
        let intent = tab.mainFrameLoads.currentIntent
        return intent.revision == semanticRevision
            && WebRuntimeNavigationIdentity(intent.targetURL)
                == WebRuntimeNavigationIdentity(targetURL)
    }
}
