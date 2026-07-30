import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionProfileRuntime {
    private var state = ExtensionProfileRuntimeState()
    private let websiteDataStoreCache: ExtensionProfileWebsiteDataStoreCache
    private let profileReferenceAdmission: ProfileReferenceAdmissionLedger
    private var knownProfilesByID: [UUID: Profile]
    /// Browser-owned profile lookup, available only while a browser runtime is
    /// attached. It is the evidence that lets store resolution distinguish a
    /// durable profile from a private partition it has not met yet.
    private var browserProfileQuery: ExtensionBrowserProfileQuery?
    var currentProfileId: UUID?

    init(
        initialProfileId: UUID?,
        initialProfile: Profile? = nil,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        websiteDataStoreCache: ExtensionProfileWebsiteDataStoreCache =
            ExtensionProfileWebsiteDataStoreCache()
    ) {
        self.profileReferenceAdmission = profileReferenceAdmission
        if let initialProfileId,
           profileReferenceAdmission.isReferenceAllowed(initialProfileId) {
            currentProfileId = initialProfileId
        } else {
            currentProfileId = nil
        }
        self.websiteDataStoreCache = websiteDataStoreCache
        if let initialProfile,
           profileReferenceAdmission.isReferenceAllowed(initialProfile.id) {
            knownProfilesByID = [initialProfile.id: initialProfile]
            websiteDataStoreCache.remember(initialProfile)
        } else {
            knownProfilesByID = [:]
        }
    }

    #if DEBUG
        convenience init(
            initialProfileId: UUID?,
            initialProfile: Profile? = nil,
            websiteDataStoreCache: ExtensionProfileWebsiteDataStoreCache =
                ExtensionProfileWebsiteDataStoreCache()
        ) {
            self.init(
                initialProfileId: initialProfileId,
                initialProfile: initialProfile,
                profileReferenceAdmission: .testingAllowingReferences(),
                websiteDataStoreCache: websiteDataStoreCache
            )
        }
    #endif

    var controllersByProfile: [UUID: WKWebExtensionController] {
        state.controllersByProfile
    }

    var contextsByProfile: [UUID: [String: WKWebExtensionContext]] {
        state.contextsByProfile
    }

    var contextBindingGenerationsByProfile: [UUID: UInt64] {
        state.contextBindingGenerationByProfile
    }

    func isProfileReferenceAllowed(_ profileID: UUID) -> Bool {
        profileReferenceAdmission.isReferenceAllowed(profileID)
    }

    func admitProfileReference(
        to profileID: UUID
    ) -> ProfileReferenceAdmissionReceipt? {
        profileReferenceAdmission.admitReference(to: profileID)
    }

    func validateProfileReference(
        _ receipt: ProfileReferenceAdmissionReceipt
    ) -> Bool {
        profileReferenceAdmission.validate(receipt)
    }

    func beginProfileReferenceMutation(
        to profileID: UUID
    ) -> ProfileReferenceMutationLease? {
        do {
            return try profileReferenceAdmission.beginReferenceMutation(
                to: [profileID]
            )
        } catch {
            return nil
        }
    }

    func beginProfileRetirementMigration(
        to fallbackProfileID: UUID
    ) -> ProfileReferenceMutationLease? {
        do {
            return try profileReferenceAdmission
                .beginRetirementReferenceMigration(to: [fallbackProfileID])
        } catch {
            return nil
        }
    }

    func validateProfileReferenceMutation(
        _ lease: ProfileReferenceMutationLease,
        profileID: UUID
    ) -> Bool {
        profileReferenceAdmission.validate(lease, covers: [profileID])
    }

    @discardableResult
    func endProfileReferenceMutation(
        _ lease: ProfileReferenceMutationLease
    ) -> Bool {
        profileReferenceAdmission.endReferenceMutation(lease)
    }

    func replaceControllers(_ controllers: [UUID: WKWebExtensionController]) {
        state.replaceControllers(controllers.filter {
            profileReferenceAdmission.isReferenceAllowed($0.key)
        })
    }

    func replaceContexts(_ contexts: [UUID: [String: WKWebExtensionContext]]) {
        state.replaceContexts(contexts.filter {
            profileReferenceAdmission.isReferenceAllowed($0.key)
        })
    }

    func replaceContextBindingGenerations(_ generations: [UUID: UInt64]) {
        state.replaceContextBindingGenerations(generations.filter {
            profileReferenceAdmission.isReferenceAllowed($0.key)
        })
    }

    func controller(for profileId: UUID) -> WKWebExtensionController? {
        state.controller(for: profileId)
    }

    func controllerBindingRevision(for profileId: UUID) -> UInt64 {
        state.controllerBindingRevision(for: profileId)
    }

    func controllerBindingSnapshot(
        for profileID: UUID
    ) -> ExtensionControllerBindingSnapshot? {
        guard let controller = state.controller(for: profileID) else {
            return nil
        }
        return ExtensionControllerBindingSnapshot(
            profileID: profileID,
            controller: controller,
            revision: state.controllerBindingRevision(for: profileID)
        )
    }

    func isCurrent(_ snapshot: ExtensionControllerBindingSnapshot) -> Bool {
        isProfileReferenceAllowed(snapshot.profileID)
            && state.controller(for: snapshot.profileID) === snapshot.controller
            && state.controllerBindingRevision(for: snapshot.profileID)
                == snapshot.revision
    }

    func controllerForCurrentProfile() -> WKWebExtensionController? {
        guard let currentProfileId else { return nil }
        return state.controller(for: currentProfileId)
    }

    @discardableResult
    func publishControllerIfAdmitted(
        _ controller: WKWebExtensionController,
        for profileId: UUID,
        mutationLease: ProfileReferenceMutationLease
    ) -> ExtensionControllerBindingSnapshot? {
        guard profileReferenceAdmission.validate(
            mutationLease,
            covers: [profileId]
        ) else {
            return nil
        }
        state.setController(controller, for: profileId)
        return ExtensionControllerBindingSnapshot(
            profileID: profileId,
            controller: controller,
            revision: state.controllerBindingRevision(for: profileId)
        )
    }

    #if DEBUG
        @discardableResult
        func setController(
            _ controller: WKWebExtensionController,
            for profileId: UUID
        ) -> ExtensionControllerBindingSnapshot {
            guard let mutationLease = beginProfileReferenceMutation(
                to: profileId
            ) else {
                preconditionFailure("Test could not admit a profile controller")
            }
            defer { _ = endProfileReferenceMutation(mutationLease) }
            guard let receipt = publishControllerIfAdmitted(
                controller,
                for: profileId,
                mutationLease: mutationLease
            ) else {
                preconditionFailure("Test published a blocked profile controller")
            }
            return receipt
        }
    #endif

    func contextsForCurrentProfile() -> [String: WKWebExtensionContext] {
        guard let currentProfileId else { return [:] }
        return state.contexts(for: currentProfileId)
    }

    func contexts(for profileId: UUID) -> [String: WKWebExtensionContext] {
        state.contexts(for: profileId)
    }

    @discardableResult
    func publishContextIfAdmitted(
        _ context: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID,
        admission: ProfileReferenceAdmissionReceipt
    ) -> ExtensionContextBindingReceipt? {
        guard admission.profileID == profileId,
              profileReferenceAdmission.validate(admission)
        else {
            return nil
        }
        return state.setContext(
            context,
            extensionId: extensionId,
            profileId: profileId
        )
    }

    #if DEBUG
        @discardableResult
        func setContext(
            _ context: WKWebExtensionContext,
            extensionId: String,
            profileId: UUID
        ) -> ExtensionContextBindingReceipt {
            guard let admission = admitProfileReference(to: profileId),
                  let receipt = publishContextIfAdmitted(
                context,
                extensionId: extensionId,
                profileId: profileId,
                admission: admission
            ) else {
                preconditionFailure("Test published a blocked profile context")
            }
            return receipt
        }
    #endif

    func removeContext(
        extensionId: String,
        profileId: UUID
    ) -> (context: WKWebExtensionContext, generation: UInt64)? {
        state.removeContext(extensionId: extensionId, profileId: profileId)
    }

    func contextBindingReceipt(
        extensionId: String,
        profileId: UUID
    ) -> ExtensionContextBindingReceipt? {
        state.contextBindingReceipt(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func isCurrent(_ receipt: ExtensionContextBindingReceipt) -> Bool {
        isProfileReferenceAllowed(receipt.key.profileId)
            && state.isCurrent(receipt)
    }

    func context(
        ifCurrent receipt: ExtensionContextBindingReceipt
    ) -> WKWebExtensionContext? {
        state.context(ifCurrent: receipt)
    }

    func controller(
        ifCurrent receipt: ExtensionContextBindingReceipt
    ) -> WKWebExtensionController? {
        state.controller(ifCurrent: receipt)
    }

    func removeContext(
        ifCurrent receipt: ExtensionContextBindingReceipt
    ) -> (context: WKWebExtensionContext, generation: UInt64)? {
        state.removeContext(ifCurrent: receipt)
    }

    func contextBindingGeneration(for profileId: UUID) -> UInt64 {
        state.contextBindingGeneration(for: profileId)
    }

    func contextBindingRevision(
        extensionId: String,
        profileId: UUID
    ) -> UInt64 {
        state.contextBindingRevision(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    @discardableResult
    func bumpContextBindingGeneration(for profileId: UUID) -> UInt64 {
        state.bumpContextBindingGeneration(for: profileId)
    }

    func allLoadedExtensionIDs() -> Set<String> {
        state.allLoadedExtensionIDs()
    }

    func extensionId(for extensionContext: WKWebExtensionContext) -> String? {
        state.extensionId(for: extensionContext)
    }

    func profileId(for extensionContext: WKWebExtensionContext) -> UUID? {
        state.profileId(for: extensionContext)
    }

    func contextIdentity(
        for extensionContext: WKWebExtensionContext
    ) -> (extensionId: String, profileId: UUID)? {
        state.contextIdentity(for: extensionContext)
    }

    func exactContextIdentity(
        for extensionContext: WKWebExtensionContext
    ) -> (extensionId: String, profileId: UUID)? {
        state.exactContextIdentity(for: extensionContext)
    }

    func profileId(for controller: WKWebExtensionController) -> UUID? {
        state.profileId(for: controller)
    }

    func countLoadedExtensionContexts() -> Int {
        state.countLoadedExtensionContexts()
    }

    func inactiveLoadedContextIdentities(
        keepingProfileId: UUID
    ) -> [(profileId: UUID, extensionId: String)] {
        state.inactiveLoadedContextIdentities(keepingProfileId: keepingProfileId)
    }

    func readinessContext(
        for profileId: UUID,
        hasEnabledExtensionDemand: Bool,
        enabledExtensionIDs: Set<String>,
        globalRuntimeReady: Bool
    ) -> ExtensionRuntimeReadinessContext {
        state.readinessContext(
            for: profileId,
            hasEnabledExtensionDemand: hasEnabledExtensionDemand,
            enabledExtensionIDs: enabledExtensionIDs,
            globalRuntimeReady: globalRuntimeReady
        )
    }

    func activateProfileIfAdmitted(
        _ profileId: UUID,
        hasExtensionDemand: Bool,
        runtimeIsReadyOrLoading: Bool,
        mutationLease: ProfileReferenceMutationLease
    ) -> Bool? {
        guard profileReferenceAdmission.validate(
            mutationLease,
            covers: [profileId]
        ) else {
            return nil
        }
        currentProfileId = profileId
        return controllersByProfile.isEmpty == false
            || hasExtensionDemand
            || runtimeIsReadyOrLoading
    }

    #if DEBUG
        @discardableResult
        func activateProfile(
            _ profileId: UUID,
            hasExtensionDemand: Bool,
            runtimeIsReadyOrLoading: Bool
        ) -> Bool {
            guard let mutationLease = beginProfileReferenceMutation(
                to: profileId
            ) else {
                preconditionFailure("Test could not admit a profile transition")
            }
            defer { _ = endProfileReferenceMutation(mutationLease) }
            guard let runtimeInitialized = activateProfileIfAdmitted(
                profileId,
                hasExtensionDemand: hasExtensionDemand,
                runtimeIsReadyOrLoading: runtimeIsReadyOrLoading,
                mutationLease: mutationLease
            ) else {
                preconditionFailure("Test activated a blocked extension profile")
            }
            return runtimeInitialized
        }
    #endif

    /// Resolves the profile's own website data store, remembering a profile the
    /// browser can still resolve. A bare identifier that the attached browser
    /// cannot resolve fails closed: it belongs to a retired profile or to a
    /// private partition whose window is gone, and minting a persistent store
    /// for either would write private browsing state to disk.
    func websiteDataStoreIfAdmitted(
        for profileId: UUID,
        mutationLease: ProfileReferenceMutationLease
    ) -> WKWebsiteDataStore? {
        guard profileReferenceAdmission.validate(
            mutationLease,
            covers: [profileId]
        ) else {
            return nil
        }
        if knownProfilesByID[profileId] == nil,
           let browserProfileQuery {
            guard let resolved = browserProfileQuery.anyProfile(profileId),
                  rememberProfile(resolved)
            else {
                RuntimeDiagnostics.emit(
                    "🔒 [ExtensionProfileRuntime] Refused website data store for unresolvable profile: \(profileId.uuidString)"
                )
                return nil
            }
        }
        return websiteDataStoreCache.store(
            for: profileId,
            activeProfile: knownProfilesByID[profileId],
            currentProfileId: currentProfileId
        )
    }

    /// Binds the browser-owned profile lookup for the lifetime of one browser
    /// attachment.
    func bindBrowserProfileQuery(_ profileQuery: ExtensionBrowserProfileQuery) {
        browserProfileQuery = profileQuery
    }

    func unbindBrowserProfileQuery() {
        browserProfileQuery = nil
    }

    @discardableResult
    func rememberProfile(_ profile: Profile) -> Bool {
        guard profileReferenceAdmission.isReferenceAllowed(profile.id) else {
            return false
        }
        knownProfilesByID[profile.id] = profile
        websiteDataStoreCache.remember(profile)
        return true
    }

    func rememberedProfile(for profileID: UUID) -> Profile? {
        knownProfilesByID[profileID]
    }

    var currentRememberedProfile: Profile? {
        currentProfileId.flatMap { knownProfilesByID[$0] }
    }

    func rememberPrivateRuntimeProfileIfNeeded(_ profile: Profile) {
        guard rememberProfile(profile) else { return }
        websiteDataStoreCache.rememberPrivateRuntimeProfileIfNeeded(profile)
    }

    func isPrivateRuntimeProfile(_ profileId: UUID?) -> Bool {
        websiteDataStoreCache.isPrivateRuntimeProfile(profileId)
    }

    func removeAllWebsiteDataStores() {
        websiteDataStoreCache.removeAll()
    }

    func canRetireProfile(
        _ profileID: UUID,
        fallbackProfileID: UUID
    ) -> Bool {
        profileID != fallbackProfileID
            && profileReferenceAdmission.isReferenceAllowed(fallbackProfileID)
    }

    @discardableResult
    func retireProfile(
        _ profileID: UUID,
        fallbackProfileID: UUID,
        mutationLease: ProfileReferenceMutationLease
    ) -> Bool {
        guard canRetireProfile(
            profileID,
            fallbackProfileID: fallbackProfileID
        ), validateProfileReferenceMutation(
            mutationLease,
            profileID: fallbackProfileID
        ), contexts(for: profileID).isEmpty
        else { return false }

        state.removeProfileBindings(for: profileID)
        knownProfilesByID.removeValue(forKey: profileID)
        websiteDataStoreCache.remove(profileID: profileID)
        if currentProfileId == profileID {
            currentProfileId = fallbackProfileID
        }
        return containsProfileReference(to: profileID) == false
    }

    func containsProfileReference(to profileID: UUID) -> Bool {
        currentProfileId == profileID
            || knownProfilesByID[profileID] != nil
            || state.containsProfileReference(to: profileID)
            || websiteDataStoreCache.containsProfileReference(to: profileID)
    }
}
