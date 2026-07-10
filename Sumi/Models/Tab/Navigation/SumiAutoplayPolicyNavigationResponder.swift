import Foundation
import SumiDomain

@MainActor
final class SumiAutoplayPolicyNavigationResponder: SumiNavigationActionResponding {
    private weak var tab: Tab?
    private let autoplayPolicy: @MainActor (URL?, Profile?) -> SumiAutoplayPolicy
    private let profileProvider: @MainActor (Tab) -> Profile?

    convenience init(
        tab: Tab,
        autoplayPolicyStore: SumiAutoplayPolicyStoreAdapter,
        profileProvider: (@MainActor (Tab) -> Profile?)? = nil
    ) {
        self.init(
            tab: tab,
            autoplayPolicy: { url, profile in
                autoplayPolicyStore.effectivePolicy(for: url, profile: profile)
            },
            profileProvider: profileProvider
        )
    }

    init(
        tab: Tab,
        autoplayPolicy: @escaping @MainActor (URL?, Profile?) -> SumiAutoplayPolicy,
        profileProvider: (@MainActor (Tab) -> Profile?)? = nil
    ) {
        self.tab = tab
        self.autoplayPolicy = autoplayPolicy
        self.profileProvider = profileProvider ?? { $0.resolveProfile() }
    }

    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        preferences: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        guard navigationAction.isForMainFrame,
              let url = navigationAction.url,
              url.isSumiAutoplayPolicyEligibleWebURL,
              let tab,
              let profile = profileProvider(tab)
        else { return .next }

        let policy = autoplayPolicy(url, profile)
        preferences.mustApplyAutoplayPolicy = true
        preferences.autoplayPolicy = policy.navigationAutoplayPolicy

        return .next
    }
}

extension SumiAutoplayPolicy {
    var navigationAutoplayPolicy: SumiWebsiteAutoplayPolicy {
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
