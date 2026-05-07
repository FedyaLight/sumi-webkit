import WebKit

struct SumiNavigationPreferences: Equatable {
    var userAgent: String?
    var contentMode: WKWebpagePreferences.ContentMode
    var javaScriptEnabled: Bool
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
