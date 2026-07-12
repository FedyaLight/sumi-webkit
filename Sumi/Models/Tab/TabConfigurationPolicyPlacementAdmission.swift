import SumiWebRuntime
import WebKit

/// One-shot evidence connecting policy preflight to an exact physical session
/// mutation. The transaction, session handle, base generation, WebView
/// identities, and receipt set must all still agree at settlement.
@MainActor
final class TabConfigurationPolicyPlacementAdmission {
    fileprivate let transaction: TabConfigurationPolicyTransaction
    fileprivate let webViewSession: WebViewSessionHandle
    fileprivate let baseGeneration: UInt64
    fileprivate let baseWebViewIDs: Set<ObjectIdentifier>
    fileprivate let candidates: [WKWebView]
    fileprivate let candidateIDs: Set<ObjectIdentifier>
    fileprivate let role: TabConfigurationPolicyLedger.CommitRole
    fileprivate let changeSet: PreparedConfigurationPolicyChangeSet
    fileprivate var didSettle = false

    fileprivate init(
        transaction: TabConfigurationPolicyTransaction,
        webViewSession: WebViewSessionHandle,
        baseGeneration: UInt64,
        baseWebViewIDs: Set<ObjectIdentifier>,
        candidates: [WKWebView],
        role: TabConfigurationPolicyLedger.CommitRole,
        changeSet: PreparedConfigurationPolicyChangeSet
    ) {
        self.transaction = transaction
        self.webViewSession = webViewSession
        self.baseGeneration = baseGeneration
        self.baseWebViewIDs = baseWebViewIDs
        self.candidates = candidates
        candidateIDs = Set(candidates.map(ObjectIdentifier.init))
        self.role = role
        self.changeSet = changeSet
    }
}

@MainActor
extension TabConfigurationPolicyTransaction {
    func preparePlacementAdmission(
        _ webViews: [WKWebView],
        as role: TabConfigurationPolicyLedger.CommitRole
    ) -> TabConfigurationPolicyPlacementAdmission? {
        let baseGeneration = webViewSession.generation
        let candidateIDs = webViews.map(ObjectIdentifier.init)
        guard webViews.isEmpty == false,
              Set(candidateIDs).count == candidateIDs.count,
              webViews.allSatisfy({ webViewSession.owns($0) == false }),
              let changeSet = preparedChangeSet(for: webViews),
              changeSet.expectedSessionGeneration == baseGeneration,
              changeSet.canCommit(for: webViews, as: role) else {
            return nil
        }
        return TabConfigurationPolicyPlacementAdmission(
            transaction: self,
            webViewSession: webViewSession,
            baseGeneration: baseGeneration,
            baseWebViewIDs: Set(
                webViewSession.allKnownWebViews.map(ObjectIdentifier.init)
            ),
            candidates: webViews,
            role: role,
            changeSet: changeSet
        )
    }

    @discardableResult
    func commit(
        _ admission: TabConfigurationPolicyPlacementAdmission
    ) -> Bool {
        guard admission.transaction === self,
              admission.webViewSession === webViewSession,
              admission.didSettle == false,
              admission.changeSet.expectedSessionGeneration
                == admission.baseGeneration,
              webViewSession.generation > admission.baseGeneration,
              admission.candidates.allSatisfy(webViewSession.owns),
              admission.changeSet.canCommit(
                  for: admission.candidates,
                  as: admission.role
              ) else {
            return false
        }

        let currentWebViewIDs = Set(
            webViewSession.allKnownWebViews.map(ObjectIdentifier.init)
        )
        switch admission.role {
        case .canonicalGeneration:
            let activeWebViewIDs = currentWebViewIDs.subtracting(
                webViewSession.parkedWebView
                    .map { [ObjectIdentifier($0)] } ?? []
            )
            guard activeWebViewIDs == admission.candidateIDs else {
                return false
            }
        case .additionalClone:
            guard admission.candidateIDs.isDisjoint(
                with: admission.baseWebViewIDs
            ), currentWebViewIDs.subtracting(admission.baseWebViewIDs)
                == admission.candidateIDs else {
                return false
            }
        }

        admission.didSettle = true
        return admission.changeSet.commit(as: admission.role)
    }

    func cancel(
        _ admission: TabConfigurationPolicyPlacementAdmission
    ) {
        guard admission.transaction === self,
              admission.webViewSession === webViewSession,
              admission.didSettle == false else {
            return
        }
        admission.didSettle = true
        admission.changeSet.cancel()
    }
}
