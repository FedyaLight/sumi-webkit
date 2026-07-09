import Combine
import Foundation

@MainActor
extension WindowViewBrowserContext {
    static func make(
        browserManager: BrowserManager,
        updaterService: SumiUpdaterService,
        defaultBrowserService: SumiDefaultBrowserService
    ) -> WindowViewBrowserContext {
        WindowViewBrowserContext(
            splitManager: browserManager.splitManager,
            findManager: browserManager.findManager,
            floatingBarBrowserContext: browserManager.floatingBarBrowserContextOwner.context,
            sidebarBrowserContext: SidebarBrowserContext.live(browserManager: browserManager),
            sidebarHostActions: sidebarHostActions(browserManager: browserManager),
            sidebarStructuralInvalidation: sidebarStructuralInvalidation(browserManager: browserManager),
            sidebarHostRecoveryCoordinator: browserManager.sidebarHostRecoveryCoordinator,
            nativeModalPresentation: { [weak browserManager] in
                browserManager?.nativeModalPresentation
            },
            browsingDataDialogContext: browsingDataDialogContext(browserManager: browserManager),
            hasCurrentSpace: { [weak browserManager] in
                browserManager?.tabManager.spaceStateOwner.currentSpace != nil
            },
            showGradientEditor: { [weak browserManager] source in
                browserManager?.workspaceThemeEditorOwner.showGradientEditor(source: source)
            },
            currentProfileID: { [weak browserManager] in
                browserManager?.currentProfile?.id
            },
            essentialPins: { [weak browserManager] profileId in
                browserManager?.tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId) ?? []
            },
            attachHoverSidebarManager: { [weak browserManager] hoverSidebarManager, windowState in
                guard let browserManager else { return }
                hoverSidebarManager.attach(
                    runtime: BrowserHoverSidebarRuntimeFactory.runtime(for: browserManager),
                    windowState: windowState
                )
            },
            websiteViewBrowserContext: { [browserManager] sidebarDragState in
                WebsiteViewContextFactory.websiteViewBrowserContext(for: browserManager, sidebarDragState: sidebarDragState)
            },
            websiteNativeSurfaceRootBuilders: { [browserManager] in
                WebsiteViewContextFactory.nativeSurfaceRootBuilders(
                    for: browserManager,
                    updaterService: updaterService,
                    defaultBrowserService: defaultBrowserService
                )
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.windowTabContextOwner.currentTab(for: windowState)
            },
            workspaceTheme: { [weak browserManager] spaceId in
                guard let spaceId else { return nil }
                return browserManager?.windowSpaceStateOwner.space(for: spaceId)?.workspaceTheme
            },
            isNativeModalPresented: { [weak browserManager] windowId in
                browserManager?.nativeDialogPresentationOwner.isNativeModalPresented(in: windowId) ?? false
            },
            nativeModalPresentationBindingDismissed: { [weak browserManager] windowId in
                browserManager?.nativeDialogPresentationOwner.nativeModalPresentationBindingDismissed(for: windowId)
            },
            dismissNativeModalPresentation: { [weak browserManager] in
                browserManager?.nativeDialogPresentationOwner.dismissNativeModalPresentation()
            },
            findCurrentTabId: { [weak browserManager] in
                browserManager?.findManager.currentTab?.id
            }
        )
    }

    private static func sidebarHostActions(browserManager: BrowserManager) -> SidebarHostActions {
        SidebarHostActions(
            updateSidebarWidth: { [weak browserManager] width, windowState, persist in
                browserManager?.sidebarPresentationOwner.updateSidebarWidth(width, for: windowState, persist: persist)
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionActivationOwner.persistWindowSession(for: windowState)
            },
            dismissThemePickerCommittingIfNeeded: { [weak browserManager] in
                browserManager?.workspaceThemeEditorOwner.dismissThemePickerCommittingIfNeeded()
            }
        )
    }

    private static func sidebarStructuralInvalidation(
        browserManager: BrowserManager
    ) -> AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            browserManager.$tabStructuralRevision.map { _ in () }.eraseToAnyPublisher(),
            browserManager.$currentProfile.map { _ in () }.eraseToAnyPublisher(),
            browserManager.$isTransitioningProfile.map { _ in () }.eraseToAnyPublisher()
        )
        .eraseToAnyPublisher()
    }

    private static func browsingDataDialogContext(
        browserManager: BrowserManager
    ) -> () -> SumiBrowsingDataDialogContext {
        { [browserManager, cleanupService = browserManager.browsingDataCleanupService] in
            SumiBrowsingDataDialogContext(
                cleanupService: cleanupService,
                profileSnapshot: { [weak browserManager] in
                    browserManager?.profileManager.profiles ?? []
                },
                activeCleanupDependencies: {
                    activeCleanupDependencies(browserManager: browserManager)
                },
                dismissNativeModalPresentation: { [weak browserManager] in
                    browserManager?.nativeDialogPresentationOwner.dismissNativeModalPresentation()
                }
            )
        }
    }

    private static func activeCleanupDependencies(
        browserManager: BrowserManager?
    ) -> BrowsingDataDialogCleanupDependencies? {
        guard let browserManager,
              browserManager.currentProfile != nil
        else {
            return nil
        }
        return BrowsingDataDialogCleanupDependencies(
            historyManager: browserManager.historyManager,
            profiles: browserManager.profileManager.profiles,
            websiteDataCleanupService: browserManager.dataServices.websiteDataCleanupService
        )
    }
}
