import Foundation

@MainActor
enum BrowserExtensionsModuleRuntimeFactory {
    static func runtime(for browserManager: BrowserManager) -> SumiExtensionsModuleRuntime {
        let currentProfileAuthority = browserManager.currentProfileAuthority
        let membership = browserManager
            .tabCollectionMembershipOwner
        return SumiExtensionsModuleRuntime(
            currentProfile: { [currentProfileAuthority] in
                currentProfileAuthority.currentProfile
            },
            attachBrowser: { [weak browserManager] attachment in
                guard let browserManager else { return }
                attachment.attach(to: browserManager)
            },
            liveTabs: { [membership] in
                membership.allTabs()
            }
        )
    }
}
