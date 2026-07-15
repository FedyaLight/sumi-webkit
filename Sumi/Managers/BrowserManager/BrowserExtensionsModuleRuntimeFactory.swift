import Foundation

@MainActor
enum BrowserExtensionsModuleRuntimeFactory {
    static func runtime(for browserManager: BrowserManager) -> SumiExtensionsModuleRuntime {
        let currentProfileAuthority = browserManager.currentProfileAuthority
        return SumiExtensionsModuleRuntime(
            currentProfile: { [currentProfileAuthority] in
                currentProfileAuthority.currentProfile
            },
            attachBrowser: { [weak browserManager] attachment in
                guard let browserManager else { return }
                attachment.attach(to: browserManager)
            },
            liveTabs: { [weak browserManager] in
                browserManager?.tabManager.tabCollectionMembershipOwner.allTabs() ?? []
            }
        )
    }
}
