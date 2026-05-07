import Navigation

@MainActor
final class SumiNavigationResponderAdapter: NavigationResponder {
    private weak var target: AnyObject?

    init(target: AnyObject) {
        self.target = target
    }

    func decidePolicy(
        for navigationAction: NavigationAction,
        preferences: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        guard let responder = target as? any SumiNavigationActionResponding else { return .next }
        var sumiPreferences = SumiNavigationPreferences(preferences)
        let decision = await responder.decidePolicy(
            for: SumiNavigationAction(navigationAction),
            preferences: &sumiPreferences
        )
        preferences.apply(sumiPreferences)
        return decision?.navigationActionPolicy
    }

    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? {
        guard let responder = target as? any SumiNavigationResponseResponding else { return .next }
        let decision = await responder.decidePolicy(for: SumiNavigationResponse(navigationResponse))
        return decision?.navigationResponsePolicy
    }
}

private extension SumiNavigationPreferences {
    init(_ preferences: NavigationPreferences) {
        self.init(
            userAgent: preferences.userAgent,
            contentMode: preferences.contentMode,
            javaScriptEnabled: preferences.javaScriptEnabled,
            autoplayPolicy: preferences.autoplayPolicy.flatMap { SumiWebsiteAutoplayPolicy(rawValue: $0.rawValue) },
            mustApplyAutoplayPolicy: preferences.mustApplyAutoplayPolicy
        )
    }
}

private extension NavigationPreferences {
    mutating func apply(_ preferences: SumiNavigationPreferences) {
        userAgent = preferences.userAgent
        contentMode = preferences.contentMode
        javaScriptEnabled = preferences.javaScriptEnabled
        autoplayPolicy = preferences.autoplayPolicy.flatMap { _WKWebsiteAutoplayPolicy(rawValue: $0.rawValue) }
        mustApplyAutoplayPolicy = preferences.mustApplyAutoplayPolicy
    }
}
