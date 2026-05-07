import WebKit

enum SumiWebsiteAutoplayPolicy: UInt, Equatable {
    case `default`
    case allow
    case allowWithoutSound
    case deny
}

struct SumiNavigationPreferences: Equatable {
    var userAgent: String?
    var contentMode: WKWebpagePreferences.ContentMode
    var javaScriptEnabled: Bool
    var autoplayPolicy: SumiWebsiteAutoplayPolicy?
    var mustApplyAutoplayPolicy: Bool
}

@MainActor
protocol SumiNavigationActionResponding: AnyObject {
    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        preferences: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy?
}

@MainActor
protocol SumiNavigationResponseResponding: AnyObject {
    func decidePolicy(for navigationResponse: SumiNavigationResponse) async -> SumiNavigationResponsePolicy?
}
