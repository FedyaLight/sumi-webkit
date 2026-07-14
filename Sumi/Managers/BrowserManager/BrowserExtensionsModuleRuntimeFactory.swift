import Foundation

@MainActor
enum BrowserExtensionsModuleRuntimeFactory {
    static func runtime(for browserManager: BrowserManager) -> SumiExtensionsModuleRuntime {
        let currentProfileAuthority = browserManager.currentProfileAuthority
        return SumiExtensionsModuleRuntime(
            currentProfile: { [currentProfileAuthority] in
                currentProfileAuthority.currentProfile
            },
            attachManager: { [weak browserManager] manager in
                guard let browserManager else { return }
                manager.attach(browserManager: browserManager)
            },
            liveTabs: { [weak browserManager] in
                browserManager?.tabManager.tabCollectionMembershipOwner.allTabs() ?? []
            }
        )
    }
}
