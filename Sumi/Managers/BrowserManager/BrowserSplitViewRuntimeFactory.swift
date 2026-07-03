import Foundation

@MainActor
enum BrowserSplitViewRuntimeFactory {
    static func runtime(for browserManager: BrowserManager) -> SplitViewRuntime {
        let fallbackTabManager = browserManager.tabManager
        return SplitViewRuntime(
            tabManager: { [weak browserManager] in
                browserManager?.tabManager ?? fallbackTabManager
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.windowTabContextOwner.currentTab(for: windowState)
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.windowVisualMutationOwner.refreshCompositor(for: windowState)
            },
            schedulePersistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionActivationOwner.schedulePersistWindowSession(for: windowState)
            },
            focusFloatingBar: { [weak browserManager] windowState, reason in
                browserManager?.floatingBarRoutingOwner.focusFloatingBar(
                    in: windowState,
                    prefill: "",
                    navigateCurrentTab: true,
                    presentationReason: reason
                )
            }
        )
    }
}
