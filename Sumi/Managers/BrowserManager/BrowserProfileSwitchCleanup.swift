import Foundation

@MainActor
final class BrowserProfileSwitchCleanup {
    private let permissionCleanup: BrowserAutomaticPermissionCleanup
    private let browsingDataCleanup: BrowserAutomaticBrowsingDataCleanup
    private let profileActivated: (Profile) -> Void

    init(
        permissionCleanup: BrowserAutomaticPermissionCleanup,
        browsingDataCleanup: BrowserAutomaticBrowsingDataCleanup,
        profileActivated: @escaping (Profile) -> Void = { _ in }
    ) {
        self.permissionCleanup = permissionCleanup
        self.browsingDataCleanup = browsingDataCleanup
        self.profileActivated = profileActivated
    }

    func run(for profile: Profile) async {
        profileActivated(profile)
        _ = await permissionCleanup.runIfNeeded(for: profile)
        browsingDataCleanup.schedule(reason: "profile-switch")
    }
}
