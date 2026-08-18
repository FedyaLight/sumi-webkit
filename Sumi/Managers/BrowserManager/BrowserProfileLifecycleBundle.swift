//
//  BrowserProfileLifecycleBundle.swift
//  Sumi
//
//  Profile switch, startup, deletion, and recovery composition.
//

import Foundation

extension BrowserManager {
    var profileReferenceAdmission: ProfileReferenceAdmissionLedger {
        profileManager.profileReferenceAdmission
    }
}

/// Stable profile-lifecycle feature graph. Every child is fully assembled;
/// consumers never recover the browser or tab composition roots from it.
@MainActor
final class BrowserProfileLifecycleBundle {
    let profileSwitchTransition: BrowserProfileSwitchTransitionOwner
    let startupPolicy: BrowserStartupPolicy
    let deletionWorkflow: BrowserProfileDeletionWorkflow
    let retirementStartupRecovery: ProfileRetirementStartupRecovery
    let importRetirement: SumiImportProfileRetirementCoordinator

    init(
        profileSwitchTransition: BrowserProfileSwitchTransitionOwner,
        startupPolicy: BrowserStartupPolicy,
        deletionWorkflow: BrowserProfileDeletionWorkflow,
        retirementStartupRecovery: ProfileRetirementStartupRecovery,
        importRetirement: SumiImportProfileRetirementCoordinator
    ) {
        self.profileSwitchTransition = profileSwitchTransition
        self.startupPolicy = startupPolicy
        self.deletionWorkflow = deletionWorkflow
        self.retirementStartupRecovery = retirementStartupRecovery
        self.importRetirement = importRetirement
    }
}

extension BrowserManager {
    func composeProfileLifecycleBundle() -> BrowserProfileLifecycleBundle {
        let currentProfileAuthority = currentProfileAuthority
        let shellRuntime = shellRuntime
        let windowRegistry = windowRegistry
        let profileChanges = objectWillChange
        let profileSelection = self.profileSelection
        let profileDeletion = self.profileDeletion
        let tabPersistence = structuralPersistence
        let privacy = privacyBundle
        let adBlockingModule = adBlockingModule
        let notificationPresenter = notificationPresenter
        let profileSwitch = BrowserProfileSwitchTransitionOwner(
            admission: BrowserProfileSwitchAdmission(
                windows: windowRegistry,
                profileAdmissions: profileReferenceAdmission
            ),
            application: BrowserProfileSwitchApplication(
                identity: BrowserProfileSwitchIdentityPublication(
                    currentProfile: currentProfileAuthority,
                    profileChanges: profileChanges,
                    auxiliaryWindows: auxiliaryWindows.teardown
                ),
                dataScope: BrowserProfileDataScopeTransition(
                    bookmarks: bookmarkManager,
                    extensions: optionalModules.extensions,
                    favicons: dataServices.faviconService,
                    history: historyManager
                ),
                tabSelection: BrowserProfileTabSelectionTransition(
                    selection: profileSelection
                )
            ),
            feedback: BrowserProfileSwitchFeedback(
                notifications: notificationPresenter
            ),
            cleanup: BrowserProfileSwitchCleanup(
                permissionCleanup: privacy.automaticPermissionCleanup,
                browsingDataCleanup: privacy.automaticBrowsingDataCleanup,
                profileActivated: { [database] profile in
                    SumiHTTPDiskCacheBudget.recordActivation(
                        profileID: profile.id,
                        database: database
                    )
                }
            )
        )

        let liveWindows: @MainActor () -> [BrowserWindowState]? = {
            [windowRegistry] in
            windowRegistry.allWindows
        }
        let referenceInventory = BrowserProfileReferenceInventory(
            currentProfile: { [currentProfileAuthority] in
                currentProfileAuthority.currentProfile
            },
            liveWindows: liveWindows,
            hasTabReference: { [profileDeletion] profileID in
                profileDeletion.containsReference(to: profileID)
            },
            primaryWindowSnapshotStore: windowSessionPersistence.snapshotStore,
            lastSessionWindowsStore: lastSessionWindowsStore,
            startupRestore: startupSessionRestoreOwner,
            recentlyClosedManager: recentlyClosedManager,
            glanceManager: glanceManager,
            extensionRuntimeContainsReference: {
                [extensions = optionalModules.extensions] profileID in
                extensions.containsProfileRuntimeReference(to: profileID)
            }
        )
        let referenceRetirement = BrowserProfileReferenceRetirementCoordinator(
            preflight: BrowserProfileRetirementPreflight(
                currentProfile: { [currentProfileAuthority] in
                    currentProfileAuthority.currentProfile
                },
                switchToProfile: { [profileSwitch] profile in
                    await profileSwitch.switchToProfile(
                        profile,
                        context: .profileRetirement,
                        in: nil
                    )
                },
                prepareLiveFolderReferences: {
                    [liveFolderManager] in
                    await liveFolderManager.prepareForProfileRetirement()
                },
                retireExtensionRuntimeProfile: {
                    [extensions = optionalModules.extensions]
                    profileID,
                    fallbackProfileID in
                    let retired = extensions.retireProfileRuntimeIfLoaded(
                        profileID: profileID,
                        fallbackProfileID: fallbackProfileID
                    )
                    if retired {
                        adBlockingModule.forgetURLCleaningProfile(profileID)
                    }
                    return retired
                }
            ),
            migration: BrowserProfileReferenceMigrationTransaction(
                liveWindows: liveWindows,
                primaryWindowSnapshotStore: windowSessionPersistence.snapshotStore,
                lastSessionWindowsStore: lastSessionWindowsStore,
                startupRestore: startupSessionRestoreOwner,
                profileReferenceAdmission: profileReferenceAdmission,
                recentlyClosedManager: recentlyClosedManager,
                glanceManager: glanceManager,
                inventory: referenceInventory
            ),
            inventory: referenceInventory
        )

        let applicationDataCleanup = ProfileApplicationDataCleanupComposition.make(
            browsingDataCleanupService: browsingDataCleanupService,
            siteDataPolicyStore: dataServices.siteDataPolicyStore,
            zoomManager: zoomManager,
            boostsModule: optionalModules.boosts,
            adblockZapperStore: adblockZapperStore,
            database: database
        )
        profileManager.privatePartitionResidueCleanup =
            PrivatePartitionResidueCleanupComposition.make(
                siteDataPolicyStore: dataServices.siteDataPolicyStore,
                zoomManager: zoomManager,
                adblockZapperStore: adblockZapperStore,
                database: database
            )
        let cleanupDependencies = ProfileRetirementCleanupDependencies(
            websiteDataCleanupService: dataServices.websiteDataCleanupService,
            faviconService: dataServices.faviconService,
            visitedLinkStore: dataServices.visitedLinkStore,
            permissionCleanupService: permissionRuntime.permissionCleanupService,
            applicationDataCleanupService: applicationDataCleanup
        )
        let noticePresenter = chromeBundle.nativeDialogPresentationOwner
        let referenceMigration = BrowserProfileReferenceRetirementRuntime(
            tabs: profileDeletion,
            persistence: tabPersistence,
            browserReferences: referenceRetirement,
            structuralStateIsSettled: {
                [startupRestoreLifecycle, tabRuntimeLifecycle] in
                await startupRestoreLifecycle.waitUntilInitialDataLoaded {
                    tabRuntimeLifecycle.startPersistedStateRestoreIfNeeded()
                }
            }
        )
        let maintenanceContext = SumiProfileMaintenanceService.Context(
                profileManager: profileManager,
                migrateReferences: {
                    [referenceMigration] deleted, fallback in
                    await referenceMigration.migrateReferences(
                        from: deleted,
                        to: fallback
                    )
                },
                sealProfileRuntime: {
                    [historyManager, permissionRuntime] profileID in
                    await historyManager.flushPendingChanges()
                    return await permissionRuntime.prepareForProfileRetirement(
                        profilePartitionId: profileID.uuidString
                    )
                },
                cleanupDependencies: cleanupDependencies,
                invalidateDeferredAdmissions: {
                    [cleanup = webViewRuntime.websiteDataCleanupService]
                    profileID in
                    cleanup.cancelDeferredAdmissions(
                        forProfileID: profileID
                    )
                }
            )
        let deletionWorkflow = BrowserProfileDeletionWorkflow(
            maintenanceContext: maintenanceContext,
            presenter: noticePresenter
        )

        return BrowserProfileLifecycleBundle(
            profileSwitchTransition: profileSwitch,
            startupPolicy: composeProfileStartupPolicy(shellRuntime: shellRuntime),
            deletionWorkflow: deletionWorkflow,
            retirementStartupRecovery:
                BrowserProfileRetirementStartupRecovery.make(
                    profileManager: profileManager,
                    referenceMigration: referenceMigration,
                    permissionRuntime: permissionRuntime,
                    cleanupDependencies: cleanupDependencies
                ),
            importRetirement: SumiImportProfileRetirementCoordinator(
                context: maintenanceContext
            )
        )
    }

    private func composeProfileStartupPolicy(
        shellRuntime: BrowserShellRuntime
    ) -> BrowserStartupPolicy {
        let windowSessions = windowSessionBundle
        let openWindows = windowSessions.history.catalog
        let sessionRestore = windowSessions.restoreService
        let sessionRecovery = windowSessions.sessionRecovery
        let windowRegistry = windowRegistry
        let cleanStartupWindowReset = CleanStartupWindowResetTransaction(
            windows: windowRegistry,
            spaces: spaceStateOwner,
            glance: glanceManager,
            currentProfileID: { [currentProfileAuthority] in
                currentProfileAuthority.currentProfile?.id
            }
        )
        let cleanStartup = CleanStartupWorkflow(
            archive: CleanStartupSessionArchiveTransaction(
                startupRestore: startupSessionRestoreOwner,
                persistence: structuralPersistence,
                openWindows: openWindows
            ),
            stateReset: startupStateReset,
            windows: cleanStartupWindowReset,
            page: CleanStartupPageTransaction(
                regularLifecycle: regularTabLifecycleOwner,
                windowReset: cleanStartupWindowReset,
                selection: browserTabSelection,
                commandPalette: urlBarBundle.commandPalettePresentation
            )
        )
        let windowRestore = StartupWindowRestoreService(
            startupRestore: startupSessionRestoreOwner,
            archive: windowSessions.history.archive,
            openWindows: openWindows,
            restoration: sessionRestore,
            windowReopen: sessionRecovery.windowReopen
        )
        return BrowserStartupPolicy(
            cleanStartup: cleanStartup,
            windowRestore: windowRestore,
            settings: settingsState
        )
    }
}
