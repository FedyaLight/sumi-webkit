import Combine
import SumiDomain
import SwiftUI

/// Builds the browser contexts consumed by website/native-surface root views
/// (web content, history page, bookmarks page) from browser subsystems.
@MainActor
enum WebsiteViewContextFactory {
    static func websiteViewBrowserContext(
        windowTabs: BrowserWindowTabContext,
        membership: TabCollectionMembershipOwner,
        windowVisuals: BrowserWindowVisualCoordinator,
        spaces: TabSpaceCollectionStateOwner,
        dragOperations: SidebarDragOperationRouter
    ) -> WebsiteViewBrowserContext {
        let webContentContext = BrowserManagerWindowWebContentContext(
            windowTabs: windowTabs,
            membership: membership,
            windowVisuals: windowVisuals
        )
        return WebsiteViewBrowserContext(
            currentTab: { [windowTabs] windowState in
                windowTabs.currentTab(for: windowState)
            },
            workspaceTheme: { [spaces] spaceId in
                spaceId.flatMap { spaces.space(with: $0)?.workspaceTheme }
            },
            resolveDragTab: { [dragOperations] item in
                dragOperations.resolveDragTab(for: item)
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
                )
            }
        )
    }

    static func settingsPageBrowserContext(
        for browserManager: BrowserManager
    ) -> SettingsBrowserContext {
        let currentProfileAuthority = browserManager.currentProfileAuthority
        let spaces = browserManager.spaceStateOwner
        let membership = browserManager
            .tabCollectionMembershipOwner
        let profileDeletion = browserManager.profileLifecycleBundle
            .deletionWorkflow
        return SettingsBrowserContext(
            profileManager: browserManager.profileManager,
            profileInventory: ProfileSettingsInventory(
                spacesCount: { profileID in
                    spaces.spaces.lazy.filter {
                        $0.profileId == profileID
                    }.count
                },
                tabsCount: { profileID in
                    let spaceIDs = Set(
                        spaces.spaces.lazy.filter {
                            $0.profileId == profileID
                        }.map(\.id)
                    )
                    return membership.allTabs().lazy.filter {
                        $0.spaceId.map(spaceIDs.contains) == true
                    }.count
                },
                updates: browserManager.tabStructureEventBus
                    .structureChangedPublisher
            ),
            extensionsModule: browserManager.optionalModules.extensions,
            extensionSurfaceStore: browserManager.optionalModules.extensions.surfaceStore,
            currentProfile: { [currentProfileAuthority] in
                currentProfileAuthority.currentProfile
            },
            currentProfileUpdates: currentProfileAuthority.$currentProfile
                .eraseToAnyPublisher(),
            currentTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
            },
            deleteProfile: { [profileDeletion] profile in
                profileDeletion.delete(profile)
            },
            scheduleRuntimeStatePersistence: { [weak browserManager] tab in
                browserManager?.structuralPersistence.scheduleRuntimeStatePersistence(for: tab)
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
                    let data = SumiImportExportSnapshot.makeData(
                        profiles: browserManager.profileManager.profiles,
                        state: browserManager.tabStateStore,
                        bookmarks: browserManager.bookmarkManager.snapshot(
                            sortMode: .manual
                        ).root.children
                    )
                    return try SumiTransferExportService()
                        .exportBrowser2ZenDocument(from: data)
                },
                writeBackup: { [weak browserManager] url in
                    guard let browserManager else {
                        throw SumiImportExportError.browserUnavailable
                    }
                    let data = SumiImportExportSnapshot.makeData(
                        profiles: browserManager.profileManager.profiles,
                        state: browserManager.tabStateStore,
                        bookmarks: browserManager.bookmarkManager.snapshot(
                            sortMode: .manual
                        ).root.children
                    )
                    try SumiBackupService().writeBackup(data: data, to: url)
                },
                applyImport: { [weak browserManager] request in
                    guard let browserManager else {
                        throw SumiImportExportError.browserUnavailable
                    }
                    let plan = SumiImportPlanBuilder(
                        isProfileIdentityAllowed: { [admission = browserManager.profileReferenceAdmission] id in
                            admission.isReferenceAllowed(id)
                        }
                    ).makePlan(
                        request: request,
                        baseline: SumiImportExportSnapshot.makeData(
                            profiles: browserManager.profileManager.profiles,
                            state: browserManager.tabStateStore,
                            bookmarks: browserManager.bookmarkManager.snapshot(
                                sortMode: .manual
                            ).root.children
                        )
                    )
                    let runtime = SumiImportRuntimeStore(
                        profileManager: browserManager.profileManager,
                        profileSelection: browserManager,
                        profileReferenceAdmission: browserManager
                            .profileReferenceAdmission,
                        state: browserManager.tabStateStore,
                        structuralInstaller: browserManager
                            .structuralInstallOwner,
                        persistence: browserManager
                            .structuralPersistence
                    )
                    let materializer = SumiImportRuntimeMaterializer(
                        tabFactory: browserManager.tabFactory,
                        tabBrowserRuntime: TabBrowserRuntimeFactory.make(for: browserManager)
                    )
                    return try await SumiImportTransaction(
                        materializer: materializer,
                        runtime: runtime,
                        bookmarks: SumiImportBookmarkStore(
                            bookmarkManager: browserManager.bookmarkManager
                        ),
                        backupWriter: SumiBackupService(),
                        profileRetirement: browserManager.profileLifecycleBundle
                            .importRetirement
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
        let currentProfileAuthority = browserManager.currentProfileAuthority
        return HistoryPageBrowserContext(
            historyManager: browserManager.historyManager,
            faviconService: browserManager.dataServices.faviconService,
            faviconImageReader: browserManager.dataServices.faviconCapabilities.images,
            currentProfile: { [currentProfileAuthority] in
                currentProfileAuthority.currentProfile
            },
            currentProfileUpdates: currentProfileAuthority.$currentProfile
                .eraseToAnyPublisher(),
            nativeModalPresentationUpdates: browserManager
                .nativeModalPresentationState.$presentation
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
                browserManager?.structuralPersistence.scheduleRuntimeStatePersistence(for: tab)
            },
            sumiSettings: { [weak browserManager] in
                browserManager?.sumiSettings
            }
        )
    }

    static func bookmarksPageBrowserContext(
        for browserManager: BrowserManager
    ) -> BookmarksPageBrowserContext {
        let currentProfileAuthority = browserManager.currentProfileAuthority
        return BookmarksPageBrowserContext(
            bookmarkManager: browserManager.bookmarkManager,
            faviconService: browserManager.dataServices.faviconService,
            faviconImageReader: browserManager.dataServices.faviconCapabilities.images,
            currentProfile: { [currentProfileAuthority] in
                currentProfileAuthority.currentProfile
            },
            currentProfileUpdates: currentProfileAuthority.$currentProfile
                .eraseToAnyPublisher(),
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
                browserManager?.structuralPersistence.scheduleRuntimeStatePersistence(for: tab)
            },
            sumiSettings: { [weak browserManager] in
                browserManager?.sumiSettings
            }
        )
    }
}

extension BrowserManager: SumiImportProfileSelection {
    func applyImportProfileSelection(_ profile: Profile?) {
        currentProfile = profile
        historyManager.switchProfile(profile?.id)
        bookmarkManager.setFaviconPrefetchPartition(
            dataServices.faviconService.partition(profile: profile)
        )
        if let profile {
            optionalModules.extensions.switchProfileIfLoaded(profile)
        }
    }
}
