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
        guard navigationAction.isForMainFrame,
              tab?.browserManager?.sumiScriptsManager.interceptInstallNavigationIfNeeded(navigationAction.url) == true
        else { return .next }

        return .cancel
    }

    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? {
        guard navigationResponse.isForMainFrame,
              tab?.browserManager?.sumiScriptsManager.interceptInstallNavigationIfNeeded(navigationResponse.url) == true
        else { return .next }

        return .cancel
    }
}
