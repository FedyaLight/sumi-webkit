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
            splitUpdates: browserManager.splitComposition.updates,
            splitQuery: browserManager.splitComposition.query,
            splitPreviews: browserManager.splitComposition.previews,
            splitLayout: browserManager.splitComposition.layout,
            splitDrops: browserManager.splitComposition.drops,
            splitDropTargets: browserManager.splitComposition.dropTargets,
            webViewOwnershipQuery: browserManager.webViewRuntime.ownershipQuery,
            trackedWebViewAdmission: browserManager.webViewRuntime
                .trackedWebViewAdmission,
            webViewCompositorRuntime: browserManager.webViewRuntime.compositorRuntime,
            webViewProtectionRuntime: browserManager.webViewRuntime.protectionRuntime,
            findManager: browserManager.findManager,
            floatingBarBrowserContext: browserManager.urlBarBundle
                .floatingBar.browserContext.context,
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
                browserManager?.chromeBundle.workspaceThemeEditorOwner.showGradientEditor(source: source)
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
            websiteViewBrowserContext: { [browserManager] in
                WebsiteViewContextFactory.websiteViewBrowserContext(
                    for: browserManager
                )
            },
            websiteNativeSurfaceRootBuilders: { [browserManager] in
                WebsiteViewContextFactory.nativeSurfaceRootBuilders(
                    for: browserManager,
                    updaterService: updaterService,
                    defaultBrowserService: defaultBrowserService
                )
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
            },
            workspaceTheme: { [weak browserManager] spaceId in
                guard let spaceId else { return nil }
                return browserManager?.tabManager.spaceStateOwner.space(with: spaceId)?
                    .workspaceTheme
            },
            isNativeModalPresented: { [weak browserManager] windowId in
                browserManager?.chromeBundle.nativeDialogPresentationOwner.isNativeModalPresented(in: windowId) ?? false
            },
            nativeModalPresentationBindingDismissed: { [weak browserManager] windowId in
                browserManager?.chromeBundle.nativeDialogPresentationOwner.nativeModalPresentationBindingDismissed(for: windowId)
            },
            dismissNativeModalPresentation: { [weak browserManager] in
                browserManager?.chromeBundle.nativeDialogPresentationOwner.dismissNativeModalPresentation()
            },
            findCurrentTabId: { [weak browserManager] in
                browserManager?.findManager.currentTab?.id
            }
        )
    }

    private static func sidebarHostActions(browserManager: BrowserManager) -> SidebarHostActions {
        SidebarHostActions(
            updateSidebarWidth: { [weak browserManager] width, windowState, persist in
                browserManager?.chromeBundle.sidebarPresentationOwner.updateSidebarWidth(width, for: windowState, persist: persist)
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence.persist(windowState)
            },
            dismissThemePickerCommittingIfNeeded: { [weak browserManager] in
                browserManager?.chromeBundle.workspaceThemeEditorOwner.dismissThemePickerCommittingIfNeeded()
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
                    browserManager?.chromeBundle.nativeDialogPresentationOwner.dismissNativeModalPresentation()
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
