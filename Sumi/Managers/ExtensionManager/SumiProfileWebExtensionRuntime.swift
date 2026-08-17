import Foundation
import WebKit

/// Owns the one WebExtension controller namespace shared by browser-owned
/// contributions and user-installed extensions. The shell is always present;
/// WebKit objects are created only after either kind of demand appears.
@available(macOS 15.5, *)
@MainActor
final class SumiProfileWebExtensionRuntime:
    ExtensionWebViewConfigurationProvisioning,
    ExtensionControllerProvisioning {
    private let browserConfiguration: BrowserConfiguration
    private let profileReferenceAdmission: ProfileReferenceAdmissionLedger
    private let initialProfileProvider: @MainActor () -> Profile?
    private var profileRuntimeResidence: ExtensionProfileRuntime?
    private var internalDesiredByProfile: [UUID: SumiURLCleaningContribution] = [:]
    private var extensionPageUserContentControllersByProfile:
        [UUID: WKUserContentController] = [:]
    private var userRuntimeIsResident = false
    private var internalContributions: InternalWebExtensionContributionOwner?

    init(
        browserConfiguration: BrowserConfiguration,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        initialProfileProvider: @escaping @MainActor () -> Profile?
    ) {
        self.browserConfiguration = browserConfiguration
        self.profileReferenceAdmission = profileReferenceAdmission
        self.initialProfileProvider = initialProfileProvider
    }

    var hasResidence: Bool { profileRuntimeResidence != nil }

    func profileRuntimeForUserDemand(initialProfile: Profile?)
        -> ExtensionProfileRuntime {
        userRuntimeIsResident = true
        return ensureProfileRuntime(initialProfile: initialProfile)
    }

    func setInternalContribution(
        _ contribution: SumiURLCleaningContribution?,
        profileID: UUID
    ) {
        guard let contribution else {
            internalDesiredByProfile.removeValue(forKey: profileID)
            internalContributions?.reconcile(nil, profileID: profileID)
            if internalDesiredByProfile.isEmpty {
                internalContributions = nil
            }
            releaseResidenceIfUnused()
            return
        }
        internalDesiredByProfile[profileID] = contribution
        guard profileRuntimeResidence?.controller(for: profileID) != nil else {
            return
        }
        contributionOwner().reconcile(contribution, profileID: profileID)
    }

    func suspendInternalContribution(profileID: UUID)
        -> SumiURLCleaningContribution? {
        let suspended = internalDesiredByProfile.removeValue(forKey: profileID)
        internalContributions?.reconcile(nil, profileID: profileID)
        if internalDesiredByProfile.isEmpty {
            internalContributions = nil
        }
        return suspended
    }

    func finishProfileRetirement(
        profileID: UUID,
        fallbackProfileID: UUID
    ) -> Bool {
        guard let profileRuntime = profileRuntimeResidence else { return true }
        guard profileRuntime.containsProfileReference(to: profileID) else {
            releaseResidenceIfUnused()
            return true
        }
        guard let lease = profileRuntime.beginProfileRetirementMigration(
            to: fallbackProfileID
        ) else {
            return false
        }
        let retired = profileRuntime.retireProfile(
            profileID,
            fallbackProfileID: fallbackProfileID,
            mutationLease: lease
        )
        _ = profileRuntime.endProfileReferenceMutation(lease)
        releaseResidenceIfUnused()
        return retired
    }

    func containsProfileReference(to profileID: UUID) -> Bool {
        internalDesiredByProfile[profileID] != nil
            || profileRuntimeResidence?.containsProfileReference(to: profileID)
                == true
    }

    func prepareNormalTabConfiguration(
        _ configuration: WKWebViewConfiguration,
        profileID: UUID
    ) {
        guard internalDesiredByProfile[profileID] != nil else { return }
        let profileRuntime = ensureProfileRuntime(initialProfile: nil)
        let controller: WKWebExtensionController
        if let existing = profileRuntime.controller(for: profileID) {
            controller = existing
        } else {
            guard let created = createController(
                profileID: profileID,
                websiteDataStore: configuration.websiteDataStore,
                profileRuntime: profileRuntime
            ) else {
                return
            }
            controller = created
        }
        configuration.webExtensionController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        if let desired = internalDesiredByProfile[profileID] {
            contributionOwner().reconcile(desired, profileID: profileID)
        }
    }

    func waitForInternalContribution(profileID: UUID) async
        -> PageNavigationPrerequisiteResult {
        guard internalDesiredByProfile[profileID] != nil else { return .ready }
        guard let internalContributions else { return .degraded }
        return await internalContributions.waitUntilReady(profileID: profileID)
    }

    func controllerIfAdmitted(
        for profileID: UUID,
        mutationLease suppliedLease: ProfileReferenceMutationLease?
    ) -> WKWebExtensionController? {
        let profileRuntime = ensureProfileRuntime(initialProfile: nil)
        let mutationLease: ProfileReferenceMutationLease
        let ownsLease: Bool
        if let suppliedLease {
            mutationLease = suppliedLease
            ownsLease = false
        } else {
            guard let acquired = profileRuntime.beginProfileReferenceMutation(
                to: profileID
            ) else {
                return nil
            }
            mutationLease = acquired
            ownsLease = true
        }
        defer {
            if ownsLease {
                _ = profileRuntime.endProfileReferenceMutation(mutationLease)
            }
        }
        guard profileRuntime.validateProfileReferenceMutation(
            mutationLease,
            profileID: profileID
        ) else {
            return nil
        }
        if let existing = profileRuntime.controller(for: profileID) {
            return existing
        }
        guard let dataStore = profileRuntime.websiteDataStoreIfAdmitted(
            for: profileID,
            mutationLease: mutationLease
        ) else {
            return nil
        }
        return createController(
            profileID: profileID,
            websiteDataStore: dataStore,
            profileRuntime: profileRuntime,
            mutationLease: mutationLease
        )
    }

    func websiteDataStoreIfAdmitted(
        for profileId: UUID,
        mutationLease: ProfileReferenceMutationLease?
    ) -> WKWebsiteDataStore? {
        let profileRuntime = ensureProfileRuntime(initialProfile: nil)
        let lease: ProfileReferenceMutationLease
        let ownsLease: Bool
        if let mutationLease {
            lease = mutationLease
            ownsLease = false
        } else {
            guard let acquired = profileRuntime.beginProfileReferenceMutation(
                to: profileId
            ) else {
                return nil
            }
            lease = acquired
            ownsLease = true
        }
        defer {
            if ownsLease {
                _ = profileRuntime.endProfileReferenceMutation(lease)
            }
        }
        guard profileRuntime.validateProfileReferenceMutation(
            lease,
            profileID: profileId
        ) else {
            return nil
        }
        if let controller = profileRuntime.controller(for: profileId) {
            return controller.configuration.defaultWebsiteDataStore
        }
        return profileRuntime.websiteDataStoreIfAdmitted(
            for: profileId,
            mutationLease: lease
        )
    }

    func releaseUserRuntime() {
        userRuntimeIsResident = false
        guard let profileRuntime = profileRuntimeResidence else { return }
        let demandedProfileIDs = Set(internalDesiredByProfile.keys)
        var retained: [UUID: WKWebExtensionController] = [:]
        for (profileID, controller) in profileRuntime.controllersByProfile {
            controller.delegate = nil
            if demandedProfileIDs.contains(profileID) {
                retained[profileID] = controller
            }
        }
        profileRuntime.replaceControllers(retained)
        extensionPageUserContentControllersByProfile =
            extensionPageUserContentControllersByProfile.filter {
                demandedProfileIDs.contains($0.key)
            }
        profileRuntime.unbindBrowserProfileQuery()
        releaseResidenceIfUnused()
    }

    func removeAllExtensionPageUserContentControllers() {
        extensionPageUserContentControllersByProfile.removeAll()
    }

    func retireProfileController(
        profileID: UUID,
        fallbackProfileID: UUID
    ) {
        let retired = profileRuntimeResidence?.controller(for: profileID)
        extensionPageUserContentControllersByProfile.removeValue(
            forKey: profileID
        )
        let base = browserConfiguration.webViewConfiguration
        if base.webExtensionController === retired {
            base.webExtensionController = profileRuntimeResidence?.controller(
                for: fallbackProfileID
            )
        }
    }

    func containsExtensionPageReference(to profileID: UUID) -> Bool {
        extensionPageUserContentControllersByProfile[profileID] != nil
    }

    var hasExtensionPageUserContentControllers: Bool {
        extensionPageUserContentControllersByProfile.isEmpty == false
    }

    #if DEBUG
        var profileRuntimeForTests: ExtensionProfileRuntime? {
            profileRuntimeResidence
        }

    #endif

    private func ensureProfileRuntime(initialProfile: Profile?)
        -> ExtensionProfileRuntime {
        if let profileRuntimeResidence { return profileRuntimeResidence }
        let profile = initialProfile ?? initialProfileProvider()
        let runtime = ExtensionProfileRuntime(
            initialProfileId: profile?.id,
            initialProfile: profile,
            profileReferenceAdmission: profileReferenceAdmission
        )
        profileRuntimeResidence = runtime
        return runtime
    }

    private func createController(
        profileID: UUID,
        websiteDataStore: WKWebsiteDataStore,
        profileRuntime: ExtensionProfileRuntime,
        mutationLease suppliedLease: ProfileReferenceMutationLease? = nil
    ) -> WKWebExtensionController? {
        let lease: ProfileReferenceMutationLease
        let ownsLease: Bool
        if let suppliedLease {
            lease = suppliedLease
            ownsLease = false
        } else {
            guard let acquired = profileRuntime.beginProfileReferenceMutation(
                to: profileID
            ) else {
                return nil
            }
            lease = acquired
            ownsLease = true
        }
        defer {
            if ownsLease {
                _ = profileRuntime.endProfileReferenceMutation(lease)
            }
        }
        guard profileRuntime.validateProfileReferenceMutation(
            lease,
            profileID: profileID
        ) else {
            return nil
        }
        if let existing = profileRuntime.controller(for: profileID) {
            return existing
        }

        let controllerConfiguration = websiteDataStore.isPersistent
            ? WKWebExtensionController.Configuration(
                identifier: ExtensionProfileControllerIdentity
                    .runtimeIdentifier(for: profileID)
            )
            : WKWebExtensionController.Configuration.nonPersistent()
        let extensionPageConfiguration = browserConfiguration
            .auxiliaryWebViewConfiguration(
                from: browserConfiguration.webViewConfiguration,
                surface: .extensionOptions
            )
        extensionPageConfiguration.websiteDataStore = websiteDataStore
        extensionPageConfiguration.sumiIsNormalTabWebViewConfiguration = false
        extensionPageConfiguration.defaultWebpagePreferences
            .allowsContentJavaScript = true
        controllerConfiguration.webViewConfiguration = extensionPageConfiguration
        controllerConfiguration.defaultWebsiteDataStore = websiteDataStore

        let controller = WKWebExtensionController(
            configuration: controllerConfiguration
        )
        guard profileRuntime.publishControllerIfAdmitted(
            controller,
            for: profileID,
            mutationLease: lease
        ) != nil else {
            return nil
        }
        extensionPageUserContentControllersByProfile[profileID] =
            extensionPageConfiguration.userContentController
        if profileRuntime.currentProfileId == profileID {
            browserConfiguration.webViewConfiguration.webExtensionController =
                controller
        }
        return controller
    }

    private func releaseResidenceIfUnused() {
        guard userRuntimeIsResident == false,
              internalDesiredByProfile.isEmpty
        else {
            return
        }
        internalContributions?.removeAll()
        internalContributions = nil
        if let profileRuntime = profileRuntimeResidence {
            for controller in profileRuntime.controllersByProfile.values {
                controller.delegate = nil
            }
            profileRuntime.replaceControllers([:])
            profileRuntime.removeAllWebsiteDataStores()
            profileRuntime.unbindBrowserProfileQuery()
        }
        browserConfiguration.webViewConfiguration.webExtensionController = nil
        extensionPageUserContentControllersByProfile.removeAll()
        profileRuntimeResidence = nil
    }

    private func contributionOwner()
        -> InternalWebExtensionContributionOwner {
        if let internalContributions { return internalContributions }
        let owner = InternalWebExtensionContributionOwner(
            controllerProvisioning: self
        )
        internalContributions = owner
        return owner
    }
}
