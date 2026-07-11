import Combine
import SumiDomain
import SwiftUI

/// Builds the browser contexts consumed by website/native-surface root views
/// (web content, history page, bookmarks page) from browser subsystems.
@MainActor
enum WebsiteViewContextFactory {
    static func websiteViewBrowserContext(
        for browserManager: BrowserManager
    ) -> WebsiteViewBrowserContext {
        let webContentContext = BrowserManagerWindowWebContentContext(
            browserManager: browserManager
        )
        return WebsiteViewBrowserContext(
            currentTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
            },
            workspaceTheme: { [weak browserManager] spaceId in
                spaceId.flatMap {
                    browserManager?.tabManager.spaceStateOwner.space(with: $0)?
                        .workspaceTheme
                }
            },
            resolveDragTab: { [weak browserManager] item in
                browserManager?.tabManager.sidebarDragRouter
                    .resolveDragTab(for: item)
            },
            makeWebContentContext: { webContentContext }
        )
    }

    static func nativeSurfaceRootBuilders(
        for browserManager: BrowserManager,
        updaterService: SumiUpdaterService,
        defaultBrowserService: SumiDefaultBrowserService
    ) -> WebsiteNativeSurfaceRootBuilders {
        WebsiteNativeSurfaceRootBuilders(
            history: { [weak browserManager] windowState in
                guard let browserManager else { return AnyView(EmptyView()) }
                return AnyView(
                    SumiHistoryTabRootView(
                        browserContext: historyPageBrowserContext(for: browserManager),
                        windowState: windowState
                    )
                )
            },
            bookmarks: { [weak browserManager] windowState in
                guard let browserManager else { return AnyView(EmptyView()) }
                return AnyView(
                    SumiBookmarksTabRootView(
                        browserContext: bookmarksPageBrowserContext(for: browserManager),
                        windowState: windowState
                    )
                )
            },
            settings: { [weak browserManager] windowState in
                guard let browserManager else { return AnyView(EmptyView()) }
                let browserContext = settingsPageBrowserContext(for: browserManager)
                return AnyView(
                    SumiSettingsTabRootView(
                        browserContext: browserContext,
                        updaterService: updaterService,
                        defaultBrowserService: defaultBrowserService,
                        windowState: windowState
                    )
                    .environmentObject(browserContext.extensionSurfaceStore)
                )
            }
        )
    }

    static func settingsPageBrowserContext(
        for browserManager: BrowserManager
    ) -> SettingsBrowserContext {
        SettingsBrowserContext(
            profileManager: browserManager.profileManager,
            tabManager: browserManager.tabManager,
            extensionsModule: browserManager.optionalModules.extensions,
            userscriptsModule: browserManager.optionalModules.userscripts,
            extensionSurfaceStore: browserManager.optionalModules.extensions.surfaceStore,
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            currentProfileUpdates: browserManager.$currentProfile.eraseToAnyPublisher(),
            currentTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
            },
            deleteProfile: { [weak browserManager] profile in
                guard let browserManager else { return }
                BrowserProfileDeletionWorkflow.delete(
                    profile,
                    from: browserManager
                )
            },
            scheduleRuntimeStatePersistence: { [weak browserManager] tab in
                browserManager?.tabManager.structuralPersistence.scheduleRuntimeStatePersistence(for: tab)
            },
            makePermissionRepository: { [weak browserManager] in
                guard let browserManager else {
                    preconditionFailure("SettingsBrowserContext used after BrowserManager deallocation")
                }
                return SumiPermissionSettingsRepository(
                    permissionRuntime: browserManager.permissionRuntime,
                    dataServices: browserManager.dataServices,
                    autoplayStore: browserManager.permissionRuntime.autoplayStore
                )
            },
            dataRecoveryActions: SumiDataRecoveryActions(
                importBookmarksFromMenu: { [weak browserManager] in
                    browserManager?.bookmarkBundle.bookmarkCommandOwner.importBookmarksFromMenu()
                },
                exportBrowser2ZenDocument: { [weak browserManager] in
                    guard let browserManager else {
                        throw SumiImportExportError.browserUnavailable
                    }
                    return try SumiTransferExportService()
                        .exportBrowser2ZenDocument(from: browserManager)
                },
                writeBackup: { [weak browserManager] url in
                    guard let browserManager else {
                        throw SumiImportExportError.browserUnavailable
                    }
                    try SumiBackupService().writeBackup(from: browserManager, to: url)
                },
                applyImport: { [weak browserManager] request in
                    guard let browserManager else {
                        throw SumiImportExportError.browserUnavailable
                    }
                    let plan = SumiImportPlanBuilder().makePlan(
                        request: request,
                        baseline: SumiImportExportSnapshot.makeData(from: browserManager)
                    )
                    let runtime = SumiImportRuntimeStore(
                        profileManager: browserManager.profileManager,
                        tabManager: browserManager.tabManager,
                        profileSelection: browserManager
                    )
                    let materializer = SumiImportRuntimeMaterializer(
                        tabFactory: browserManager.tabManager.tabFactory,
                        tabBrowserRuntime: TabBrowserRuntimeFactory.make(for: browserManager)
                    )
                    return try await SumiImportTransaction(
                        materializer: materializer,
                        runtime: runtime,
                        bookmarks: SumiImportBookmarkStore(
                            bookmarkManager: browserManager.bookmarkManager
                        ),
                        backupWriter: SumiBackupService()
                    ).commit(
                        plan
                    )
                }
            )
        )
    }

    static func historyPageBrowserContext(
        for browserManager: BrowserManager
    ) -> HistoryPageBrowserContext {
        HistoryPageBrowserContext(
            historyManager: browserManager.historyManager,
            faviconService: browserManager.dataServices.faviconService,
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            currentProfileUpdates: browserManager.$currentProfile.eraseToAnyPublisher(),
            nativeModalPresentationUpdates: browserManager.$nativeModalPresentation
                .map { _ in () }
                .eraseToAnyPublisher(),
            isNativeModalPresented: { [weak browserManager] windowId in
                guard let windowId else { return false }
                return browserManager?.chromeBundle.nativeDialogPresentationOwner
                    .isNativeModalPresented(in: windowId) ?? false
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
            },
            openHistoryURL: { [weak browserManager] url, windowState, preferredOpenMode in
                browserManager?.historyBundle.historyNavigationOwner.openHistoryURL(
                    url,
                    in: windowState,
                    preferredOpenMode: preferredOpenMode
                )
            },
            openHistoryURLsInNewTabs: { [weak browserManager] urls, windowState in
                browserManager?.historyBundle.historyNavigationOwner.openHistoryURLsInNewTabs(
                    urls,
                    in: windowState
                )
            },
            presentBrowsingDataSheet: { [weak browserManager] windowState in
                browserManager?.chromeBundle.nativeDialogPresentationOwner.presentBrowsingDataSheet(
                    windowState: windowState
                )
            },
            scheduleRuntimeStatePersistence: { [weak browserManager] tab in
                browserManager?.tabManager.structuralPersistence.scheduleRuntimeStatePersistence(for: tab)
            },
            sumiSettings: { [weak browserManager] in
                browserManager?.sumiSettings
            }
        )
    }

    static func bookmarksPageBrowserContext(
        for browserManager: BrowserManager
    ) -> BookmarksPageBrowserContext {
        BookmarksPageBrowserContext(
            bookmarkManager: browserManager.bookmarkManager,
            faviconService: browserManager.dataServices.faviconService,
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            currentProfileUpdates: browserManager.$currentProfile.eraseToAnyPublisher(),
            currentTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
            },
            openHistoryURLsInNewTabs: { [weak browserManager] urls, windowState in
                browserManager?.historyBundle.historyNavigationOwner.openHistoryURLsInNewTabs(
                    urls,
                    in: windowState
                )
            },
            openHistoryURLsInNewWindow: { [weak browserManager] urls in
                browserManager?.historyBundle.historyNavigationOwner.openHistoryURLsInNewWindow(urls)
            },
            openBookmarkURL: { [weak browserManager] url, windowState, preferredOpenMode in
                browserManager?.bookmarkBundle.bookmarkCommandOwner.openBookmarkURL(
                    url,
                    in: windowState,
                    preferredOpenMode: preferredOpenMode
                )
            },
            importBookmarksFromMenu: { [weak browserManager] in
                browserManager?.bookmarkBundle.bookmarkCommandOwner.importBookmarksFromMenu()
            },
            exportBookmarksFromMenu: { [weak browserManager] in
                browserManager?.bookmarkBundle.bookmarkCommandOwner.exportBookmarksFromMenu()
            },
            scheduleRuntimeStatePersistence: { [weak browserManager] tab in
                browserManager?.tabManager.structuralPersistence.scheduleRuntimeStatePersistence(for: tab)
            },
            sumiSettings: { [weak browserManager] in
                browserManager?.sumiSettings
            }
        )
    }
}

extension BrowserManager: SumiImportProfileSelection {}
