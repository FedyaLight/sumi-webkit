import Foundation
import SumiDomain
import WebKit

@MainActor
final class SumiTabAuthenticationNavigationResponder:
    SumiNavigationAuthChallengeResponding {
    private weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
    }

    func didReceive(
        _ authenticationChallenge: URLAuthenticationChallenge,
        context: SumiNavigationContext?
    ) async -> SumiAuthChallengeDisposition? {
        guard let tab else { return .next }
        return await tab.navigationRuntime.lifecycleNavigationRuntime
            .resolveAuthenticationChallenge(
                authenticationChallenge,
                tab,
                context?.webView
            )
    }

    func didReceive(
        _ authenticationChallenge: URLAuthenticationChallenge
    ) async -> SumiAuthChallengeDisposition? {
        await didReceive(authenticationChallenge, context: nil)
    }
}
