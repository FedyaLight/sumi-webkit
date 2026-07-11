import Foundation

@MainActor
enum BrowserSplitViewRuntimeFactory {
    static func runtime(for browserManager: BrowserManager) -> SplitViewRuntime {
        SplitViewRuntime(
            tabManager: { [weak browserManager] in
                browserManager?.tabManager
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
            },
            selectTabWithoutPersistence: { [weak browserManager] tab, windowState in
                browserManager?.applyTabSelection(
                    tab,
                    in: windowState,
                    updateSpaceFromTab: true,
                    updateTheme: true,
                    rememberSelection: true,
                    persistSelection: false
                )
            },
            restoreShortcutMember: {
                [weak browserManager]
                memberID,
                group,
                windowState in
                browserManager?.sidebarCommandService.splitShortcuts
                    .memberRestoration.restoreShortcutSplitMember(
                        memberID,
                        from: group,
                        in: windowState
                    ) == true
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowVisuals.refreshCompositor(for: windowState)
            },
            schedulePersistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence.schedule(windowState)
            },
            focusFloatingBar: { [weak browserManager] windowState, reason in
                browserManager?.urlBarBundle.floatingBar.presentation.focus(
                    in: windowState,
                    prefill: "",
                    navigateCurrentTab: true,
                    reason: reason
                )
            },
            notifications: { [weak browserManager] in
                browserManager?.notificationPresenter
            }
        )
    }
}
