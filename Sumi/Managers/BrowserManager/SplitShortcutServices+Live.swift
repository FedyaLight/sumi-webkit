import Foundation

@MainActor
extension SplitShortcutServices {
    static func live(browserManager: BrowserManager) -> Self {
        let runtimeLease: () -> SplitShortcutRuntimeLease? = { [weak browserManager] in
            guard let browserManager else { return nil }
            return SplitShortcutRuntimeLease(
                tabManager: browserManager.tabManager
            )
        }
        let focus = SplitShortcutFocusService(
            runtimeLease: runtimeLease,
            browserManager: browserManager
        )
        let launcherPlacement = browserManager.splitComposition
            .launcherPlacement
        let presentations = browserManager.splitComposition.presentations
        return Self(
            focus: focus,
            memberRestoration: SplitShortcutMemberRestoreService(
                runtimeLease: runtimeLease,
                browserManager: browserManager,
                launcherPlacement: launcherPlacement,
                presentations: presentations
            ),
            hostedUnload: ShortcutHostedSplitUnloadService(
                runtimeLease: runtimeLease,
                browserManager: browserManager
            )
        )
    }
}

@MainActor
private extension SplitShortcutFocusService {
    convenience init(
        runtimeLease: @escaping () -> SplitShortcutRuntimeLease?,
        browserManager: BrowserManager
    ) {
        self.init(
            runtimeLease: runtimeLease,
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
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowVisuals
                    .refreshCompositor(for: windowState)
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence
                    .persist(windowState)
            }
        )
    }
}

@MainActor
private extension SplitShortcutMemberRestoreService {
    convenience init(
        runtimeLease: @escaping () -> SplitShortcutRuntimeLease?,
        browserManager: BrowserManager,
        launcherPlacement: ShortcutSplitLauncherPlacementService,
        presentations: WindowSplitPresentationSynchronizer
    ) {
        self.init(
            runtimeLease: runtimeLease,
            launcherPlacement: launcherPlacement,
            presentations: presentations,
            performImmediateVisualHandoff: { [weak browserManager] windowState in
                _ = browserManager?.shellRuntime.windowVisuals
                    .performImmediateVisualHandoffIfPossible(in: windowState)
            }
        )
    }
}

@MainActor
private extension ShortcutHostedSplitUnloadService {
    convenience init(
        runtimeLease: @escaping () -> SplitShortcutRuntimeLease?,
        browserManager: BrowserManager
    ) {
        self.init(
            runtimeLease: runtimeLease,
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
            showEmptyStateWithoutPersistence: { [weak browserManager] windowState in
                browserManager?.showEmptyStateWithoutPersistence(in: windowState)
            },
            performImmediateVisualHandoff: { [weak browserManager] windowState in
                _ = browserManager?.shellRuntime.windowVisuals
                    .performImmediateVisualHandoffIfPossible(in: windowState)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowVisuals
                    .refreshCompositor(for: windowState)
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence
                    .persist(windowState)
            }
        )
    }
}
