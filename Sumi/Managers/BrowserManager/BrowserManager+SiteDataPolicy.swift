import Foundation

extension BrowserManager {
    func enforceSiteDataPolicyAfterNavigation(for tab: Tab) {
        SumiSiteDataPolicyEnforcementService.shared
            .enforceBlockStorageIfNeeded(
                for: tab.url,
                profile: tab.resolveProfile()
            )
    }

    func performSiteDataPolicyAllWindowsClosedCleanup() async {
        await SumiSiteDataPolicyEnforcementService.shared
            .performAllWindowsClosedCleanup(profiles: profileManager.profiles)
    }
}
