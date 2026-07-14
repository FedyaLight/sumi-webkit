import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionContextRetentionOwner {
    private let profileRuntime: ExtensionProfileRuntime
    private let runtimeResidency: ExtensionRuntimeResidencyAuthority
    private let extensionLoadRevisions: ExtensionLoadRevisionAuthority
    private let loadRegistry: ExtensionContextLoadRegistry
    private let retirement: ExtensionContextRetirement
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        profileRuntime: ExtensionProfileRuntime,
        runtimeResidency: ExtensionRuntimeResidencyAuthority,
        extensionLoadRevisions: ExtensionLoadRevisionAuthority,
        loadRegistry: ExtensionContextLoadRegistry,
        retirement: ExtensionContextRetirement,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.profileRuntime = profileRuntime
        self.runtimeResidency = runtimeResidency
        self.extensionLoadRevisions = extensionLoadRevisions
        self.loadRegistry = loadRegistry
        self.retirement = retirement
        self.diagnostics = diagnostics
    }

    func touch(extensionID: String, profileID: UUID) {
        runtimeResidency.touch(extensionID: extensionID, profileID: profileID)
    }

    func enforceLimit(keepingProfileID: UUID, keepingExtensionID: String) {
        let candidates = runtimeResidency.evictionCandidates(
            loadedContextCount: profileRuntime.countLoadedExtensionContexts(),
            limit: ExtensionManager.maxLiveExtensionContexts,
            keepingExtensionID: keepingExtensionID,
            keepingProfileID: keepingProfileID
        )
        for candidate in candidates {
            unloadIfLoaded(
                extensionID: candidate.extensionId,
                profileID: candidate.profileId
            )
        }
    }

    func unloadInactiveProfiles(keepingProfileID: UUID) {
        for identity in profileRuntime.inactiveLoadedContextIdentities(
            keepingProfileId: keepingProfileID
        ) {
            unloadIfLoaded(
                extensionID: identity.extensionId,
                profileID: identity.profileId
            )
        }
    }

    func unloadIfLoaded(extensionID: String, profileID: UUID) {
        _ = unload(extensionID: extensionID, profileID: profileID)
    }

    func quiesce(profileIDs: Set<UUID>) -> Bool {
        guard profileIDs.isEmpty == false else { return true }
        extensionLoadRevisions.advance()
        loadRegistry.invalidate(profileIDs: profileIDs)
        let identities = profileIDs.flatMap { profileID in
            profileRuntime.contexts(for: profileID).keys.map {
                (extensionID: $0, profileID: profileID)
            }
        }
        return identities.reduce(into: true) { didUnloadAll, identity in
            if unload(
                extensionID: identity.extensionID,
                profileID: identity.profileID
            ) == false {
                didUnloadAll = false
            }
        }
    }

    @discardableResult
    private func unload(extensionID: String, profileID: UUID) -> Bool {
        let key = ExtensionRuntimeResidencyState.ScopedKey(
            profileId: profileID,
            extensionId: extensionID
        )
        loadRegistry.invalidate(key)
        let outcome = retirement.retireCurrent(
            extensionId: extensionID,
            profileId: profileID
        )
        diagnostics.trace(
            "unloadExtensionContext extensionId=\(extensionID) "
                + "profileId=\(profileID.uuidString) "
                + "outcome=\(String(describing: outcome)) "
                + "remainingContexts=\(profileRuntime.countLoadedExtensionContexts())"
        )
        switch outcome {
        case .retired, .notBound:
            return true
        case .controllerUnavailable, .unloadFailed, .superseded,
             .retirementInProgress:
            return false
        }
    }
}
