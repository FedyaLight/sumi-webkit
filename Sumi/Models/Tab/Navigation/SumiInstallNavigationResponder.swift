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
        guard let url = navigationAction.url,
              navigationAction.isForMainFrame
        else { return .next }

        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.installResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.installResponder", signpostState)
        }

        return tab?.browserManager?.userscriptsModule.interceptInstallNavigationIfNeeded(url) == true
            ? .cancel
            : .next
    }

    func decidePolicy(for navigationResponse: SumiNavigationResponse) async -> SumiNavigationResponsePolicy? {
        guard navigationResponse.isForMainFrame else { return .next }

        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.installResponseResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.installResponseResponder", signpostState)
        }

        return tab?.browserManager?.userscriptsModule.interceptInstallNavigationIfNeeded(navigationResponse.url) == true
            ? .cancel
            : .next
    }
}
