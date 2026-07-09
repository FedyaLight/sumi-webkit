import Foundation

@MainActor
enum BrowserExtensionsModuleRuntimeFactory {
    static func runtime(for browserManager: BrowserManager) -> SumiExtensionsModuleRuntime {
        SumiExtensionsModuleRuntime(
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            attachManager: { [weak browserManager] manager in
                guard let browserManager else { return }
                manager.attach(browserManager: browserManager)
            },
            liveTabs: { [weak browserManager] in
                browserManager?.tabManager.tabCollectionMembershipOwner.allTabs() ?? []
            },
            invalidateTabStructuralRevision: { [weak browserManager] in
                browserManager?.tabStructuralRevision &+= 1
            }
        )
    }
}
