import Foundation

@MainActor
final class BrowserProfileSwitchCleanup {
    private let permissionCleanup: BrowserAutomaticPermissionCleanup
    private let browsingDataCleanup: BrowserAutomaticBrowsingDataCleanup

    init(
        permissionCleanup: BrowserAutomaticPermissionCleanup,
        browsingDataCleanup: BrowserAutomaticBrowsingDataCleanup
    ) {
        self.permissionCleanup = permissionCleanup
        self.browsingDataCleanup = browsingDataCleanup
    }

    func run(for profile: Profile) async {
        _ = await permissionCleanup.runIfNeeded(for: profile)
        browsingDataCleanup.schedule(reason: "profile-switch")
    }
}
