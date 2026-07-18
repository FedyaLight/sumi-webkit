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

    init(
        profileSwitchTransition: BrowserProfileSwitchTransitionOwner,
        startupPolicy: BrowserStartupPolicy,
        deletionWorkflow: BrowserProfileDeletionWorkflow,
        retirementStartupRecovery: ProfileRetirementStartupRecovery
    ) {
        self.profileSwitchTransition = profileSwitchTransition
        self.startupPolicy = startupPolicy
        self.deletionWorkflow = deletionWorkflow
        self.retirementStartupRecovery = retirementStartupRecovery
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
                browsingDataCleanup: privacy.automaticBrowsingDataCleanup
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
                    extensions.retireProfileRuntimeIfLoaded(
                        profileID: profileID,
                        fallbackProfileID: fallbackProfileID
                    )
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
            historyManager: historyManager,
            browsingDataCleanupService: browsingDataCleanupService,
            siteDataPolicyStore: dataServices.siteDataPolicyStore,
            zoomManager: zoomManager,
            boostsModule: optionalModules.boosts,
            adblockZapperStore: adblockZapperStore,
            extensionPreferences: moduleRegistry.userDefaults
        )
        let cleanupDependencies = ProfileRetirementCleanupDependencies(
            browsingDataCleanupService: browsingDataCleanupService,
            websiteDataCleanupService: dataServices.websiteDataCleanupService,
            faviconService: dataServices.faviconService,
            visitedLinkStore: dataServices.visitedLinkStore,
            permissionCleanupService: permissionRuntime.permissionCleanupService,
            applicationDataCleanupService: applicationDataCleanup
        )
        let noticePresenter = chromeBundle.nativeDialogPresentationOwner
        let deletionWorkflow = BrowserProfileDeletionWorkflow(
            maintenanceContext: SumiProfileMaintenanceService.Context(
                currentProfile: { [currentProfileAuthority] in
                    currentProfileAuthority.currentProfile
                },
                profileManager: profileManager,
                migrateProfileReferences: { [profileDeletion] deleted, fallback in
                    await profileDeletion.migrate(
                        deletedProfileID: deleted,
                        fallbackProfileID: fallback
                    )
                },
                persistProfileReferences: { [tabPersistence] in
                    await tabPersistence.persistFullReconcileAwaitingResult(
                        reason: "profile retirement"
                    )
                },
                migrateBrowserProfileReferences: {
                    [referenceRetirement] deleted,
                    fallback in
                    await referenceRetirement.migrateReferences(
                        from: deleted,
                        to: fallback
                    )
                },
                hasProfileReferences: { [referenceRetirement] profileID in
                    referenceRetirement.containsReference(to: profileID)
                },
                sealProfileRuntime: { [permissionRuntime] profileID in
                    await permissionRuntime.prepareForProfileRetirement(
                        profilePartitionId: profileID.uuidString
                    )
                },
                browsingDataCleanupService: cleanupDependencies
                    .browsingDataCleanupService,
                websiteDataCleanupService: cleanupDependencies
                    .websiteDataCleanupService,
                faviconService: cleanupDependencies.faviconService,
                visitedLinkStore: cleanupDependencies.visitedLinkStore,
                permissionCleanupService: cleanupDependencies
                    .permissionCleanupService,
                applicationDataCleanupService: cleanupDependencies
                    .applicationDataCleanupService,
                showNotice: { [weak noticePresenter] notice in
                    noticePresenter?.presentNoticeSheet(
                        BrowserNoticeSheetModel(
                            title: notice.title,
                            subtitle: notice.subtitle,
                            message: notice.message
                        ),
                        source: nil
                    )
                }
            )
        )

        return BrowserProfileLifecycleBundle(
            profileSwitchTransition: profileSwitch,
            startupPolicy: composeProfileStartupPolicy(shellRuntime: shellRuntime),
            deletionWorkflow: deletionWorkflow,
            retirementStartupRecovery:
                BrowserProfileRetirementStartupRecovery.make(
                    profileManager: profileManager,
                    profileDeletion: profileDeletion,
                    tabPersistence: tabPersistence,
                    referenceRetirement: referenceRetirement,
                    permissionRuntime: permissionRuntime,
                    browsingDataCleanupService: browsingDataCleanupService,
                    cleanupDependencies: cleanupDependencies
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
                floatingBar: urlBarBundle.floatingBar.presentation
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
