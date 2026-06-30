import Combine
import Foundation

@MainActor
extension WindowViewBrowserRuntime {
    static func live(browserManager: BrowserManager) -> WindowViewBrowserRuntime {
        WindowViewBrowserRuntime(
            splitManager: browserManager.splitManager,
            findManager: browserManager.findManager,
            floatingBarBrowserContext: browserManager.floatingBarBrowserContext,
            sidebarBrowserContext: SidebarBrowserContext.live(browserManager: browserManager),
            sidebarHostActions: SidebarHostActions(
                updateSidebarWidth: { [weak browserManager] width, windowState, persist in
                    browserManager?.updateSidebarWidth(width, for: windowState, persist: persist)
                },
                persistWindowSession: { [weak browserManager] windowState in
                    browserManager?.persistWindowSession(for: windowState)
                },
                dismissWorkspaceThemePickerIfNeededCommitting: { [weak browserManager] in
                    browserManager?.dismissWorkspaceThemePickerIfNeededCommitting()
                }
            ),
            sidebarStructuralInvalidation: Publishers.MergeMany(
                browserManager.$tabStructuralRevision.map { _ in () }.eraseToAnyPublisher(),
                browserManager.$currentProfile.map { _ in () }.eraseToAnyPublisher(),
                browserManager.$isTransitioningProfile.map { _ in () }.eraseToAnyPublisher()
            )
            .eraseToAnyPublisher(),
            nativeModalPresentation: { [weak browserManager] in
                browserManager?.nativeModalPresentation
            },
            browsingDataDialogContext: { [browserManager, cleanupService = browserManager.browsingDataCleanupService] in
                SumiBrowsingDataDialogContext(
                    cleanupService: cleanupService,
                    profileSnapshot: { [weak browserManager] in
                        browserManager?.profileManager.profiles ?? []
                    },
                    activeCleanupDependencies: { [weak browserManager] in
                        guard let browserManager,
                              browserManager.currentProfile != nil
                        else {
                            return nil
                        }
                        return SumiBrowsingDataDialogCleanupDependencies(
                            historyManager: browserManager.historyManager,
                            profiles: browserManager.profileManager.profiles,
                            websiteDataCleanupService: browserManager.dataServices.websiteDataCleanupService
                        )
                    },
                    dismissNativeModalPresentation: { [weak browserManager] in
                        browserManager?.dismissNativeModalPresentation()
                    }
                )
            },
            hasCurrentSpace: { [weak browserManager] in
                browserManager?.tabManager.currentSpace != nil
            },
            showGradientEditor: { [weak browserManager] source in
                browserManager?.showGradientEditor(source: source)
            },
            currentProfileID: { [weak browserManager] in
                browserManager?.currentProfile?.id
            },
            essentialPins: { [weak browserManager] profileId in
                browserManager?.tabManager.essentialPins(for: profileId) ?? []
            },
            attachHoverSidebarManager: { [weak browserManager] hoverSidebarManager, windowState in
                guard let browserManager else { return }
                hoverSidebarManager.attach(
                    runtime: .live(browserManager: browserManager),
                    windowState: windowState
                )
            },
            websiteViewBrowserContext: { [browserManager] sidebarDragState in
                browserManager.websiteViewBrowserContext(sidebarDragState: sidebarDragState)
            },
            websiteNativeSurfaceRootBuilders: { [browserManager] in
                browserManager.websiteNativeSurfaceRootBuilders
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            workspaceTheme: { [weak browserManager] spaceId in
                guard let spaceId else { return nil }
                return browserManager?.space(for: spaceId)?.workspaceTheme
            },
            isNativeModalPresented: { [weak browserManager] windowId in
                browserManager?.isNativeModalPresented(in: windowId) ?? false
            },
            nativeModalPresentationBindingDismissed: { [weak browserManager] windowId in
                browserManager?.nativeModalPresentationBindingDismissed(for: windowId)
            },
            dismissNativeModalPresentation: { [weak browserManager] in
                browserManager?.dismissNativeModalPresentation()
            },
            findCurrentTabId: { [weak browserManager] in
                browserManager?.findManager.currentTab?.id
            }
        )
    }
}

extension WindowViewBrowserContext {
    static func live(browserManager: BrowserManager) -> WindowViewBrowserContext {
        WindowViewBrowserContext(runtime: .live(browserManager: browserManager))
    }
}
