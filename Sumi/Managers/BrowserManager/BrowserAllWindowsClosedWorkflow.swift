import Foundation

/// Resets the global restore cycle synchronously, then lets the accepted
/// site-data cleanup finish from an immutable profile snapshot. The live
/// browser token is held across cleanup because participant discovery uses
/// runtime-backed WebView contexts.
@MainActor
final class BrowserAllWindowsClosedWorkflow {
    private weak var browserRuntime: BrowserManager?
    private weak var sessionRestore: WindowSessionRestoreService?
    private weak var siteDataPolicy: (any BrowserSiteDataPolicyEnforcing)?
    private weak var profiles: ProfileManager?

    init(
        browserRuntime: BrowserManager,
        sessionRestore: WindowSessionRestoreService,
        siteDataPolicy: any BrowserSiteDataPolicyEnforcing,
        profiles: ProfileManager
    ) {
        self.browserRuntime = browserRuntime
        self.sessionRestore = sessionRestore
        self.siteDataPolicy = siteDataPolicy
        self.profiles = profiles
    }

    func handleAllWindowsClosed() {
        guard let browserRuntime,
              let sessionRestore,
              let siteDataPolicy,
              let profiles
        else { return }

        sessionRestore.prepareForAllWindowsClosed()
        let profileSnapshot = profiles.profiles
        Task { @MainActor [browserRuntime, siteDataPolicy, profileSnapshot] in
            _ = browserRuntime
            await siteDataPolicy.performAllWindowsClosedCleanup(
                profiles: profileSnapshot
            )
        }
    }
}
