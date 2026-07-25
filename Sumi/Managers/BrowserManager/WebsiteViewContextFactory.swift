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
                usage: { profileID in
                    let spaceIDs = Set(
                        spaces.spaces.lazy.filter {
                            $0.profileId == profileID
                        }.map(\.id)
                    )
                    let tabs = membership.allTabs().lazy.filter {
                        $0.spaceId.map(spaceIDs.contains) == true
                    }.count
                    return ProfileUsage(spaces: spaceIDs.count, tabs: tabs)
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
                    let report = try await SumiImportTransaction(
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

                    // Bulk data is applied only after the structural import has
                    // committed: it is keyed to the profiles that import just
                    // created, and none of it is worth writing if the structure
                    // it belongs to rolled back.
                    let bulkWarnings = await Self.applyBulkImport(
                        request: request,
                        transition: plan.profileTransition,
                        browserManager: browserManager
                    )
                    guard bulkWarnings.isEmpty else {
                        return SumiImportReport(
                            warnings: report.warnings + bulkWarnings,
                            preRestoreBackupURL: report.preRestoreBackupURL,
                            appliedCategories: report.appliedCategories,
                            bookmarkSummary: report.bookmarkSummary
                        )
                    }
                    return report
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

    /// Applies staged history, site icons, and cookies onto the profiles the
    /// structural import just created. Returns warnings; a bulk failure is
    /// reported but never undoes the structure the user already has.
    private static func applyBulkImport(
        request: SumiImportRequest,
        transition: SumiImportProfileTransition,
        browserManager: BrowserManager
    ) async -> [String] {
        guard let manifest = request.bulkStaging,
              request.bulkKinds.isEmpty == false
        else {
            return []
        }

        let staging = SumiImportBulkStagingStore()
        defer { staging.discard(manifest.stagingID) }

        // Bulk payloads are keyed by the source browser's profile directory;
        // resolve each to the Sumi profile the plan mapped it onto.
        var profileIDsBySourceKey: [String: UUID] = [:]
        for profile in request.data.profiles {
            guard let key = profile.sourceDirectoryKey else { continue }
            let target = transition.sourceToTargetProfileID[profile.id]
                .flatMap(UUID.init(uuidString:))
                ?? browserManager.currentProfile?.id
            guard let target else { continue }
            profileIDsBySourceKey[key] = target
        }

        let installer = SumiImportBulkInstaller(
            historyStore: browserManager.historyManager.store,
            refreshHistory: { [weak browserManager] in
                await browserManager?.historyManager.refreshAfterExternalMutation()
            },
            faviconIngestion: browserManager.dataServices.faviconCapabilities.localIconIngestion,
            cookieInstaller: SumiProfileCookieInstallationService(
                dataStoreProvider: { [weak browserManager] profileId in
                    browserManager?.profileManager.profiles
                        .first { $0.id == profileId }?
                        .dataStore
                }
            ),
            // Replace is the only mode where the user asked for the imported
            // session to win over one already in Sumi.
            overwriteExistingCookies: request.mode == .replace
        )

        let coordinator = SumiImportBulkApplyCoordinator(staging: staging, installer: installer)
        var receipt = SumiImportBulkReceipt()
        do {
            try await coordinator.apply(
                manifest: manifest,
                kinds: request.bulkKinds,
                profileIDsBySourceKey: profileIDsBySourceKey,
                into: &receipt
            )
            return []
        } catch {
            let rollbackErrors = await coordinator.rollback(
                receipt,
                profileIDsBySourceKey: profileIDsBySourceKey
            )
            var warnings = [
                "Browsing data could not be imported: \(error.localizedDescription). "
                    + "Spaces, tabs, and bookmarks were imported successfully."
            ]
            if rollbackErrors.isEmpty == false {
                warnings.append("Some partially imported browsing data could not be removed.")
            }
            return warnings
        }
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
