import Foundation
import Navigation
import WebKit

@MainActor
final class SumiAutoplayPolicyNavigationResponder: NavigationResponder {
    private weak var tab: Tab?
    private let autoplayPolicyStore: SumiAutoplayPolicyStoreAdapter
    private let profileProvider: @MainActor (Tab) -> Profile?

    init(
        tab: Tab,
        autoplayPolicyStore: SumiAutoplayPolicyStoreAdapter? = nil,
        profileProvider: (@MainActor (Tab) -> Profile?)? = nil
    ) {
        self.tab = tab
        self.autoplayPolicyStore = autoplayPolicyStore ?? .shared
        self.profileProvider = profileProvider ?? { $0.resolveProfile() }
    }

    func decidePolicy(
        for navigationAction: NavigationAction,
        preferences: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        guard navigationAction.isForMainFrame,
              navigationAction.url.isSumiAutoplayPolicyEligibleWebURL,
              let tab,
              let profile = profileProvider(tab)
        else { return .next }

        let policy = autoplayPolicyStore.effectivePolicy(
            for: navigationAction.url,
            profile: profile
        )
        preferences.mustApplyAutoplayPolicy = true
        preferences.autoplayPolicy = policy.navigationAutoplayPolicy

        return .next
    }
}

extension SumiAutoplayPolicy {
    var navigationAutoplayPolicy: _WKWebsiteAutoplayPolicy {
        switch self {
        case .default, .allowAll:
            return .allow
        case .blockAudible:
            return .allowWithoutSound
        case .blockAll:
            return .deny
        }
    }
}

private extension URL {
    var isSumiAutoplayPolicyEligibleWebURL: Bool {
        switch scheme?.lowercased() {
        case "http", "https":
            return true
        default:
            return false
        }
    }
}
