import Foundation

@MainActor
final class SumiInstallNavigationResponder: SumiNavigationActionResponding, SumiNavigationResponseResponding {
    private weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
    }

    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        preferences _: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.installResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.installResponder", signpostState)
        }

        guard let url = navigationAction.url,
              navigationAction.isForMainFrame,
              tab?.browserManager?.userscriptsModule.interceptInstallNavigationIfNeeded(url) == true
        else { return .next }

        return .cancel
    }

    func decidePolicy(for navigationResponse: SumiNavigationResponse) async -> SumiNavigationResponsePolicy? {
        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.installResponseResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.installResponseResponder", signpostState)
        }

        guard navigationResponse.isForMainFrame,
              tab?.browserManager?.userscriptsModule.interceptInstallNavigationIfNeeded(navigationResponse.url) == true
        else { return .next }

        return .cancel
    }
}
