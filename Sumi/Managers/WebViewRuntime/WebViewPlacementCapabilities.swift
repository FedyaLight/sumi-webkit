import Foundation
import WebKit

enum UntrackedWebViewInstallationRejection: Equatable {
    case trackedResidenceExists
    case canonicalPlacement(CanonicalWebViewPlacementRejection)
    case detachedReplacementRejected
}

enum RejectedWebViewDisposition: Equatable {
    case callerMustDestroy
    case remainsCanonical
}

enum UntrackedWebViewInstallationOutcome: Equatable {
    case committed
    case unchanged
    case rejected(
        UntrackedWebViewInstallationRejection,
        webViewDisposition: RejectedWebViewDisposition
    )
    case consumedByFailedReplacement

    var isAccepted: Bool {
        switch self {
        case .committed, .unchanged:
            return true
        case .rejected, .consumedByFailedReplacement:
            return false
        }
    }

    /// A failed replacement transaction owns destruction of its candidate.
    /// Every other rejected installation leaves that exact WebView with the
    /// caller, which must destroy it while rolling back its model object.
    var callerRetainsWebView: Bool {
        switch self {
        case .rejected(_, let disposition):
            return disposition == .callerMustDestroy
        case .committed, .unchanged, .consumedByFailedReplacement:
            return false
        }
    }
}

@MainActor
protocol AuxiliaryTrackedWebViewPlacing: AnyObject {
    func registerAuxiliaryTrackedWebView(
        _ webView: WKWebView,
        for tab: Tab,
        in windowID: UUID
    ) -> CanonicalWebViewPlacementOutcome
}

@MainActor
protocol UntrackedWebViewInstalling: AnyObject {
    func installUntracked(
        _ webView: WKWebView,
        for tab: Tab
    ) -> UntrackedWebViewInstallationOutcome
}
