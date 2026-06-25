import Foundation

@MainActor
final class SumiInternalSurfaceNavigationResponder: SumiNavigationActionResponding {
    init(tab _: Tab) {}

    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        preferences _: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        guard let url = navigationAction.url,
              SumiSurface.isNativeSurfaceURL(url)
        else { return .next }

        if navigationAction.isUserEnteredURL || navigationAction.isCustom {
            return .next
        }

        if let sourceURL = navigationAction.sourceURL,
           SumiSurface.isNativeSurfaceURL(sourceURL) {
            return .next
        }

        if navigationAction.sourceFrame?.securityOrigin.permissionOrigin(missingReason: "missing-source-origin").isWebOrigin == true {
            return .cancel
        }

        if SumiPermissionOrigin(url: navigationAction.sourceURL).isWebOrigin {
            return .cancel
        }

        return .next
    }
}
