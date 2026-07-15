import Foundation
import SumiWebRuntime

@MainActor
private enum WebViewReplacementAppModelError: Error {
    case stale
}

/// Exact URL/rebuild-epoch model half of a live Tab generation replacement.
@MainActor
final class TabWebViewRebuildModelTransaction:
    WebViewReplacementModelTransaction {
    private enum State { case prepared, staged, committed, rolledBack }

    private let tab: Tab
    private let intentRevision: UInt64
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
        self.sourceURL = sourceURL
        self.targetURL = targetURL
    }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return tab.webViewRebuildEpoch.isCurrent(intentRevision)
            && tab.url == sourceURL
    }

    func stage() throws {
        guard validateForStaging() else {
            throw WebViewReplacementAppModelError.stale
        }
        tab.cancelPendingMainFrameNavigation()
        tab.url = targetURL
        state = .staged
    }

    func stagedModelIsExact() -> Bool {
        guard case .staged = state else { return false }
        return tab.webViewRebuildEpoch.isCurrent(intentRevision)
            && tab.url == targetURL
    }

    func canClaimTerminalModel() -> Bool { stagedModelIsExact() }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        guard stagedModelIsExact() else { return .terminallyDrained }
        state = .committed
        return .sealed
    }

    func publishCommit() {}

    func rollback() throws {
        guard stagedModelIsExact() else {
            throw WebViewReplacementAppModelError.stale
        }
        tab.url = sourceURL
        state = .rolledBack
    }

    func publishRollback() {}

    func settleTerminalDrain() {
        switch state {
        case .staged:
            state = .committed
        case .prepared:
            state = .rolledBack
        case .committed, .rolledBack:
            break
        }
    }
}
