import Foundation
import SumiWebRuntime
import WebKit

enum CanonicalWebViewPlacementRejection: Equatable {
    case wrongSurfaceFamily
    case mixedSurfaceGeneration
    case foreignOrTransitionResidence
    case trackedRegistration(WebViewTrackedRegistrationRejection)
    case unexpectedPolicyEvidence
    case missingPolicyAdmission
    case existingGenerationRequiresReplacement
}

enum CanonicalWebViewPlacementOutcome: Equatable {
    case committed
    case unchanged
    case rejected(CanonicalWebViewPlacementRejection)

    var isAccepted: Bool {
        switch self {
        case .committed, .unchanged:
            return true
        case .rejected:
            return false
        }
    }
}

/// Commits one physical WebView into canonical tracked or untracked residence.
///
/// Normal WebViews carry a one-shot policy admission from preflight through the
/// exact repository CAS. Auxiliary WebViews use a separate capability and may
/// never smuggle normal policy evidence into an auxiliary generation.
@MainActor
final class CanonicalWebViewPlacementService {
    private let webViewSessions: WebViewSessionRepository
    private let trackedRegistration: WebViewTrackedRegistrationOwner

    init(
        webViewSessions: WebViewSessionRepository,
        trackedRegistration: WebViewTrackedRegistrationOwner
    ) {
        self.webViewSessions = webViewSessions
        self.trackedRegistration = trackedRegistration
    }

    func placeNormalTracked(
        _ webView: WKWebView,
        for tab: Tab,
        in windowID: UUID,
        promoteToPrimary: Bool
    ) -> CanonicalWebViewPlacementOutcome {
        guard webView.configuration.sumiIsNormalTabWebViewConfiguration else {
            return .rejected(.wrongSurfaceFamily)
        }
        return placeTracked(
            webView,
            for: tab,
            in: windowID,
            isNormal: true,
            promoteToPrimary: promoteToPrimary
        )
    }

    func placeAuxiliaryTracked(
        _ webView: WKWebView,
        for tab: Tab,
        in windowID: UUID,
        promoteToPrimary: Bool
    ) -> CanonicalWebViewPlacementOutcome {
        guard webView.configuration.sumiIsNormalTabWebViewConfiguration
                == false else {
            return .rejected(.wrongSurfaceFamily)
        }
        if webView.sumiPreparedConfigurationPolicyChange != nil {
            tab.configurationPolicyTransaction.cancel([webView])
            return .rejected(.unexpectedPolicyEvidence)
        }
        return placeTracked(
            webView,
            for: tab,
            in: windowID,
            isNormal: false,
            promoteToPrimary: promoteToPrimary
        )
    }

    func placeNormalUntracked(
        _ webView: WKWebView,
        for tab: Tab
    ) -> CanonicalWebViewPlacementOutcome {
        guard webView.configuration.sumiIsNormalTabWebViewConfiguration else {
            return .rejected(.wrongSurfaceFamily)
        }
        return placeUntracked(webView, for: tab, isNormal: true)
    }

    func placeAuxiliaryUntracked(
        _ webView: WKWebView,
        for tab: Tab
    ) -> CanonicalWebViewPlacementOutcome {
        guard webView.configuration.sumiIsNormalTabWebViewConfiguration
                == false else {
            return .rejected(.wrongSurfaceFamily)
        }
        if webView.sumiPreparedConfigurationPolicyChange != nil {
            tab.configurationPolicyTransaction.cancel([webView])
            return .rejected(.unexpectedPolicyEvidence)
        }
        return placeUntracked(webView, for: tab, isNormal: false)
    }

    private func placeTracked(
        _ webView: WKWebView,
        for tab: Tab,
        in windowID: UUID,
        isNormal: Bool,
        promoteToPrimary: Bool
    ) -> CanonicalWebViewPlacementOutcome {
        tab.webViewSession.requireBacking(by: webViewSessions)
        guard residenceIsEligible(webView, for: tab.id) else {
            return .rejected(.foreignOrTransitionResidence)
        }

        let snapshot = webViewSessions.snapshot(for: tab.id)
        let candidateWasCanonical = tab.webViewSession.owns(webView)
        guard snapshot.allKnownWebViews
            .filter({ $0 !== webView })
            .allSatisfy({
                $0.configuration.sumiIsNormalTabWebViewConfiguration
                    == isNormal
            }) else {
            return .rejected(.mixedSurfaceGeneration)
        }

        let owner = TrackedWebViewOwner(
            tabID: tab.id,
            windowID: windowID
        )
        let targetOccupant = snapshot.windowWebViews[windowID]
        let untrackedOccupant = snapshot.untrackedWebView
        var expectedWebViewIDs = Set(
            snapshot.allKnownWebViews.map(ObjectIdentifier.init)
        )
        if let targetOccupant, targetOccupant !== webView {
            expectedWebViewIDs.remove(ObjectIdentifier(targetOccupant))
        }
        if let untrackedOccupant, untrackedOccupant !== webView {
            expectedWebViewIDs.remove(ObjectIdentifier(untrackedOccupant))
        }
        expectedWebViewIDs.insert(ObjectIdentifier(webView))

        let admission: TabConfigurationPolicyPlacementAdmission?
        if isNormal, candidateWasCanonical == false {
            let survivingCanonicalIDs = expectedWebViewIDs.subtracting([
                ObjectIdentifier(webView),
            ])
            let activeCanonicalIDs = survivingCanonicalIDs.subtracting(
                snapshot.parkedWebView.map { [ObjectIdentifier($0)] } ?? []
            )
            let role: TabConfigurationPolicyLedger.CommitRole =
                activeCanonicalIDs.isEmpty
                    ? .canonicalGeneration
                    : .additionalClone
            guard let prepared = tab.configurationPolicyTransaction
                .preparePlacementAdmission([webView], as: role) else {
                return .rejected(.missingPolicyAdmission)
            }
            admission = prepared
        } else {
            admission = nil
        }

        var policyDidCommit = admission == nil
        let registration = trackedRegistration.register(
            webView,
            for: tab.id,
            in: windowID,
            didCommitPlacement: {
                precondition(
                    self.hasExactPlacement(
                        webView,
                        residence: .window(owner),
                        expectedWebViewIDs: expectedWebViewIDs,
                        tab: tab
                    ),
                    "Tracked placement must publish the exact canonical identity"
                )
                if let admission {
                    precondition(
                        tab.configurationPolicyTransaction.commit(admission),
                        "Normal WebView policy must commit immediately after canonical placement"
                    )
                    policyDidCommit = true
                }
            }
        )

        switch registration {
        case .rejected(let rejection):
            if let admission {
                tab.configurationPolicyTransaction.cancel(admission)
            }
            return .rejected(.trackedRegistration(rejection))
        case .unchanged:
            precondition(
                admission == nil && candidateWasCanonical,
                "Unchanged placement cannot consume provisional policy evidence"
            )
        case .committed:
            precondition(policyDidCommit)
        }

        precondition(
            hasExactPlacement(
                webView,
                residence: .window(owner),
                expectedWebViewIDs: expectedWebViewIDs,
                tab: tab
            ),
            "Tracked placement changed during registration side effects"
        )
        if promoteToPrimary {
            precondition(
                trackedRegistration.promotePrimary(webView, owner: owner),
                "Canonical tracked WebView could not become primary"
            )
        }
        return registration == .unchanged ? .unchanged : .committed
    }

    private func placeUntracked(
        _ webView: WKWebView,
        for tab: Tab,
        isNormal: Bool
    ) -> CanonicalWebViewPlacementOutcome {
        tab.webViewSession.requireBacking(by: webViewSessions)
        guard residenceIsEligible(webView, for: tab.id) else {
            return .rejected(.foreignOrTransitionResidence)
        }
        let snapshot = webViewSessions.snapshot(for: tab.id)
        guard snapshot.windowWebViews.isEmpty else {
            return .rejected(.existingGenerationRequiresReplacement)
        }
        if snapshot.untrackedWebView === webView {
            return .unchanged
        }

        let candidateWasCanonical = tab.webViewSession.owns(webView)
        if candidateWasCanonical {
            guard snapshot.parkedWebView === webView,
                  snapshot.allKnownWebViews.count == 1,
                  tab.webViewSession.adoptParkedAsUntracked(webView),
                  tab.webViewSession.untrackedWebView === webView else {
                return .rejected(.existingGenerationRequiresReplacement)
            }
            return .committed
        }
        guard snapshot.allKnownWebViews.isEmpty else {
            return .rejected(.existingGenerationRequiresReplacement)
        }
        let admission: TabConfigurationPolicyPlacementAdmission?
        if isNormal {
            guard let prepared = tab.configurationPolicyTransaction
                .preparePlacementAdmission(
                    [webView],
                    as: .canonicalGeneration
                ) else {
                return .rejected(.missingPolicyAdmission)
            }
            admission = prepared
        } else {
            admission = nil
        }

        tab.webViewSession.replaceUntracked(with: webView)
        precondition(
            hasExactPlacement(
                webView,
                residence: .untracked(tabID: tab.id),
                expectedWebViewIDs: [ObjectIdentifier(webView)],
                tab: tab
            ),
            "Untracked placement must publish the exact canonical identity"
        )
        if let admission {
            precondition(
                tab.configurationPolicyTransaction.commit(admission),
                "Normal WebView policy must commit after untracked placement"
            )
        }
        return .committed
    }

    private func hasExactPlacement(
        _ webView: WKWebView,
        residence: WebViewResidence,
        expectedWebViewIDs: Set<ObjectIdentifier>,
        tab: Tab
    ) -> Bool {
        webViewSessions.residence(of: webView) == residence
            && Set(
                tab.webViewSession.allKnownWebViews.map(ObjectIdentifier.init)
            ) == expectedWebViewIDs
    }

    private func residenceIsEligible(
        _ webView: WKWebView,
        for tabID: UUID
    ) -> Bool {
        switch webViewSessions.residence(of: webView) {
        case .parked(let ownerTabID), .untracked(let ownerTabID):
            return ownerTabID == tabID
        case .window(let owner):
            return owner.tabID == tabID
        case .retiring, .pendingCleanup:
            return false
        case nil:
            return true
        }
    }

}
