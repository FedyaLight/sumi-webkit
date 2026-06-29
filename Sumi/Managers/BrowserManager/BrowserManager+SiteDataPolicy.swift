import Foundation

extension BrowserManager {
    func enforceSiteDataPolicyAfterNavigation(for tab: Tab) {
        dataServices.siteDataPolicyEnforcementService
            .enforceBlockStorageIfNeeded(
                for: tab.url,
                profile: tab.resolveProfile()
            )
    }

    func performSiteDataPolicyAllWindowsClosedCleanup() async {
        await dataServices.siteDataPolicyEnforcementService
            .performAllWindowsClosedCleanup(profiles: profileManager.profiles)
    }
}
