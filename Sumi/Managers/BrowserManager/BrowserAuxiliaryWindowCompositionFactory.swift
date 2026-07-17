import Foundation

@MainActor
enum BrowserAuxiliaryWindowCompositionFactory {
    static func make(
        windows: WindowRegistry,
        currentProfile: BrowserCurrentProfileAuthority,
        spaces: TabSpaceCollectionStateOwner,
        tabContext: BrowserWindowTabContext,
        auxiliaryTabs: AuxiliaryMiniWindowTabLifecycleTransaction,
        untrackedWebViewInstallation: UntrackedWebViewInstallationService,
        extensions: SumiExtensionsModule,
        popupPermissions: SumiPopupPermissionBridge,
        filePickerPermissions: SumiFilePickerPermissionBridge,
        mutationAdmission: WebsiteDataCleanupService,
        profileAdmissions: ProfileReferenceAdmissionLedger,
        teardownRegistry: AuxiliaryWindowTeardownRegistry
    ) -> BrowserAuxiliaryWindowComposition {
        let composition = BrowserAuxiliaryWindowComposition(
            windowRegistry: { [windows] in windows },
            currentProfile: { [currentProfile] in currentProfile.currentProfile?.id },
            spaces: spaces,
            tabContext: tabContext,
            auxiliaryTabs: auxiliaryTabs,
            untrackedWebViewInstallation: untrackedWebViewInstallation,
            extensions: extensions,
            popupPermissions: popupPermissions,
            filePickerPermissions: filePickerPermissions,
            mutationAdmission: mutationAdmission,
            profileAdmissions: profileAdmissions
        )
        teardownRegistry.register(composition.teardown)
        return composition
    }
}
