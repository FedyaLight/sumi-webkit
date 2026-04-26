import Foundation
import Navigation

@MainActor
final class SumiInstallNavigationResponder: NavigationResponder {
    private weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
    }

    func decidePolicy(
        for navigationAction: NavigationAction,
        preferences _: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.installResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.installResponder", signpostState)
        }

        guard navigationAction.isForMainFrame,
              tab?.browserManager?.userscriptsModule.interceptInstallNavigationIfNeeded(navigationAction.url) == true
        else { return .next }

        return .cancel
    }

    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? {
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
