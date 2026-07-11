import Foundation

extension BrowserWindowSpaceTransitionService {
    convenience init(browserManager: BrowserManager) {
        let selectionHandoff = BrowserWindowSpaceSelectionHandoff(
            tabContext: browserManager.shellRuntime.windowTabs,
            applyTabSelection: { [weak browserManager] tab, windowState in
                browserManager?.applyTabSelection(
                    tab,
                    in: windowState,
                    updateSpaceFromTab: false,
                    updateTheme: false,
                    rememberSelection: true,
                    persistSelection: false
                )
            },
            performImmediateVisualHandoff: { [weak browserManager] windowState in
                _ = browserManager?.shellRuntime.windowVisuals
                    .performImmediateVisualHandoffIfPossible(in: windowState)
            },
            showEmptyState: { [weak browserManager] windowState in
                browserManager?.showEmptyState(in: windowState)
            }
        )
        let contextTransition = BrowserWindowSpaceContextTransition(
            contextReconciler: BrowserWindowSpaceContextReconciler(
                browserManager: browserManager
            ),
            sanitizeFloatingBarState: { [weak browserManager] windowState in
                browserManager?.urlBarBundle.floatingBar.presentation
                    .sanitize(in: windowState)
            },
            syncShortcutSelectionState: { [weak browserManager] windowState in
                browserManager?.syncShortcutSelectionState(for: windowState)
            },
            updateWorkspaceTheme: { [weak browserManager] windowState, theme, animate in
                browserManager?.chromeBundle.workspaceThemeTransitionOwner
                    .updateWorkspaceTheme(
                        for: windowState,
                        to: theme,
                        animate: animate
                    )
            },
            finishInteractiveTransition: { [weak browserManager] space, windowState, identity in
                browserManager?.chromeBundle.workspaceThemeTransitionOwner
                    .finishInteractiveSpaceTransition(
                        to: space,
                        in: windowState,
                        identity: identity
                    )
            }
        )

        self.init(
            spaceActivation: browserManager.tabManager.spaceServices.activation,
            isActiveWindow: { [weak browserManager] windowState in
                browserManager?.windowRegistry?.activeWindow === windowState
            },
            selectionHandoff: selectionHandoff,
            contextTransition: contextTransition,
            synchronizeFocusedSpaceContext: { [weak browserManager] windowState in
                browserManager?.windowStateReconciler
                    .synchronizeFocusedSpaceContext(in: windowState)
            },
            adoptProfileForSpaceChange: { [weak browserManager] windowState in
                browserManager?.adoptProfileIfNeeded(
                    for: windowState,
                    context: .spaceChange
                )
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence.persist(windowState)
            },
            completePendingSplitGroupFocus: { [weak browserManager] windowState, spaceId in
                browserManager?.sidebarCommandService.splitShortcuts.focus
                    .completePendingSplitGroupFocusIfReady(
                        in: windowState,
                        spaceId: spaceId
                    )
            }
        )
    }
}
