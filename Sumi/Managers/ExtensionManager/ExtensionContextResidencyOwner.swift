//
//  ExtensionContextResidencyOwner.swift
//  Sumi
//
//  Owns extension context residency: lazy per-extension context loading,
//  bounded live-context eviction, inactive-profile unloads, and profile
//  runtime readiness bookkeeping.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionContextResidencyOwner {
    struct Dependencies {
        let profileRuntime: ExtensionProfileRuntime
        let runtimeResidency: ExtensionRuntimeResidencyAuthority
        let runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
        let extensionLoadRevisions: ExtensionLoadRevisionAuthority
        let installedExtensions: InstalledExtensionCollection
        let contextLoadRegistry: ExtensionContextLoadRegistry
        let contextRetirement: ExtensionContextRetirement
        let isExtensionSupportAvailable: @MainActor () -> Bool
        let extensionsModuleEnabledForRuntimeBoundary: @MainActor () -> Bool
        let ensureExtensionController: @MainActor (UUID) -> Void
        let getExtensionContext: @MainActor (String, UUID) -> WKWebExtensionContext?
        let countLoadedContexts: @MainActor () -> Int
        let extensionEntity: @MainActor (String) throws -> ExtensionEntity?
        let loadEnabledExtension: @MainActor (ExtensionEntity, UUID) async throws -> Void
        let markRuntimePublicationReady: @MainActor () -> Void
        let trace: @MainActor (() -> String) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func touchLiveExtensionContext(extensionId: String, profileId: UUID) {
        dependencies.runtimeResidency.touch(
            extensionID: extensionId,
            profileID: profileId
        )
    }

    func enforceBoundedLiveExtensionContexts(
        keepingProfileId: UUID,
        keepingExtensionId: String
    ) {
        let evictionCandidates =
            dependencies.runtimeResidency
                .evictionCandidates(
                    loadedContextCount: dependencies.countLoadedContexts(),
                    limit: ExtensionManager.maxLiveExtensionContexts,
                    keepingExtensionID: keepingExtensionId,
                    keepingProfileID: keepingProfileId
                )

        for evictionCandidate in evictionCandidates {
            unloadExtensionContextIfLoaded(
                extensionId: evictionCandidate.extensionId,
                profileId: evictionCandidate.profileId
            )
        }
    }

    func unloadExtensionContextsForInactiveProfiles(keepingProfileId: UUID) {
        for identity in dependencies.profileRuntime.inactiveLoadedContextIdentities(
            keepingProfileId: keepingProfileId
        ) {
            unloadExtensionContextIfLoaded(
                extensionId: identity.extensionId,
                profileId: identity.profileId
            )
        }
    }

    func unloadExtensionContextIfLoaded(
        extensionId: String,
        profileId: UUID
    ) {
        _ = unloadExtensionContext(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    /// Invalidates in-flight lazy loads and synchronously unloads every
    /// context backed by a profile whose website data is about to mutate.
    /// A failed WebKit unload aborts deletion instead of pretending the
    /// profile store is quiescent.
    func quiesceForWebsiteDataMutation(profileIDs: Set<UUID>) -> Bool {
        guard profileIDs.isEmpty == false else { return true }
        dependencies.extensionLoadRevisions.advance()
        dependencies.contextLoadRegistry.invalidate(profileIDs: profileIDs)

        let identities = profileIDs.flatMap { profileID in
            dependencies.profileRuntime.contexts(for: profileID).keys.map {
                (extensionID: $0, profileID: profileID)
            }
        }
        var didUnloadAll = true
        for identity in identities {
            if unloadExtensionContext(
                extensionId: identity.extensionID,
                profileId: identity.profileID
            ) == false {
                didUnloadAll = false
            }
        }
        return didUnloadAll
    }

    @discardableResult
    private func unloadExtensionContext(
        extensionId: String,
        profileId: UUID
    ) -> Bool {
        let key = ExtensionRuntimeResidencyState.ScopedKey(
            profileId: profileId,
            extensionId: extensionId
        )
        dependencies.contextLoadRegistry.invalidate(key)
        let outcome = dependencies.contextRetirement.retireCurrent(
            extensionId: extensionId,
            profileId: profileId
        )

        dependencies.trace {
            "unloadExtensionContext extensionId=\(extensionId) profileId=\(profileId.uuidString) outcome=\(String(describing: outcome)) remainingContexts=\(self.dependencies.countLoadedContexts())"
        }
        switch outcome {
        case .retired, .notBound:
            return true
        case .controllerUnavailable, .unloadFailed, .superseded,
             .retirementInProgress:
            return false
        }
    }

    @discardableResult
    func ensureExtensionLoaded(
        extensionId: String,
        profileId: UUID
    ) async throws -> WKWebExtensionContext? {
        guard dependencies.isExtensionSupportAvailable() else { return nil }
        guard dependencies.extensionsModuleEnabledForRuntimeBoundary() else {
            dependencies.trace {
                "ensureExtensionLoaded skip extensionId=\(extensionId) profileId=\(profileId.uuidString) because=extensionsModuleDisabled"
            }
            return nil
        }

        dependencies.ensureExtensionController(profileId)

        if let context = dependencies.getExtensionContext(extensionId, profileId),
           context.isLoaded {
            touchLiveExtensionContext(extensionId: extensionId, profileId: profileId)
            enforceBoundedLiveExtensionContexts(
                keepingProfileId: profileId,
                keepingExtensionId: extensionId
            )
            return context
        }

        guard let entity = try dependencies.extensionEntity(extensionId),
              entity.isEnabled
        else {
            return nil
        }

        try await dependencies.loadEnabledExtension(
            entity,
            profileId
        )
        touchLiveExtensionContext(extensionId: extensionId, profileId: profileId)
        enforceBoundedLiveExtensionContexts(
            keepingProfileId: profileId,
            keepingExtensionId: extensionId
        )
        return dependencies.getExtensionContext(extensionId, profileId)
    }

    /// Loads every enabled extension for a profile. Prefer `ensureExtensionLoaded` for lazy paths.
    func ensureEnabledExtensionsLoaded(for profileId: UUID) async {
        guard dependencies.isExtensionSupportAvailable() else { return }

        dependencies.ensureExtensionController(profileId)
        let catalogSnapshot = dependencies.installedExtensions.records
        let enabledRecords = catalogSnapshot.filter(\.isEnabled)
        guard enabledRecords.isEmpty == false else { return }

        for record in enabledRecords {
            let extensionID = record.id
            guard dependencies.getExtensionContext(extensionID, profileId) == nil else {
                continue
            }

            do {
                guard let entity = try dependencies.extensionEntity(extensionID),
                      entity.isEnabled
                else {
                    continue
                }
                try await dependencies.loadEnabledExtension(
                    entity,
                    profileId
                )
            } catch {
                ExtensionManager.logger.error(
                    "Failed to load enabled extension \(extensionID, privacy: .public) for profile \(profileId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    @discardableResult
    func settleLoadedContext(
        _ loadedContext: ExtensionLoadedContext
    ) -> Bool {
        let receipt = loadedContext.bindingReceipt
        let profileId = receipt.key.profileId
        guard dependencies.profileRuntime.context(ifCurrent: receipt)
                === loadedContext.context,
              dependencies.profileRuntime.controller(ifCurrent: receipt)
                === loadedContext.controller,
              loadedContext.context.isLoaded
        else { return false }

        let catalogSnapshot = dependencies.installedExtensions.records
        guard catalogSnapshot.contains(where: {
            $0.id == receipt.key.extensionId && $0.isEnabled
        }) else { return false }
        let enabledExtensionIDs = Set(
            catalogSnapshot.lazy.filter(\.isEnabled).map(\.id)
        )
        let readiness = dependencies.profileRuntime.readinessContext(
            for: profileId,
            hasEnabledExtensionDemand: enabledExtensionIDs.isEmpty == false,
            enabledExtensionIDs: enabledExtensionIDs,
            globalRuntimeReady: dependencies.runtimeLifecycle.isReady
        )
        dependencies.runtimeLifecycle.updateReadiness(
            isReady: readiness.isProfileReady
        )
        dependencies.markRuntimePublicationReady()
        dependencies.trace {
            "markExtensionRuntimeReady profile=\(profileId.uuidString) loadedContexts=\(self.dependencies.profileRuntime.contexts(for: profileId).count) allEnabledLoaded=\(readiness.isProfileReady) unloadedEnabledExtensionIDs=\(readiness.unloadedEnabledExtensionIDs.joined(separator: ","))"
        }
        return true
    }
}

@available(macOS 15.5, *)
extension ExtensionContextResidencyOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            profileRuntime: manager.profileRuntime,
            runtimeResidency: manager.runtimeResidency,
            runtimeLifecycle: manager.runtimeLifecycle,
            extensionLoadRevisions: manager.extensionLoadRevisions,
            installedExtensions: manager.installedExtensionCollection,
            contextLoadRegistry: manager.contextLoadRegistry,
            contextRetirement: manager.contextRetirement,
            isExtensionSupportAvailable: { [weak manager] in
                manager?.isExtensionSupportAvailable ?? false
            },
            extensionsModuleEnabledForRuntimeBoundary: { [weak manager] in
                manager?.extensionsModuleEnabledForRuntimeBoundary() ?? false
            },
            ensureExtensionController: { [weak manager] profileId in
                _ = manager?.ensureExtensionController(for: profileId)
            },
            getExtensionContext: { [weak manager] extensionId, profileId in
                manager?.getExtensionContext(for: extensionId, profileId: profileId)
            },
            countLoadedContexts: { [weak manager] in
                manager?.countLoadedExtensionContexts() ?? 0
            },
            extensionEntity: { [weak manager] extensionId in
                try manager?.extensionEntity(for: extensionId)
            },
            loadEnabledExtension: { [weak manager] entity, profileId in
                _ = try await manager?.extensionRuntimeLoader.loadEnabled(
                    from: entity,
                    profileID: profileId
                )
            },
            markRuntimePublicationReady: { [weak manager] in
                manager?.markExtensionRuntimePublicationReady()
            },
            trace: { [weak manager] message in
                manager?.runtimeDiagnostics.trace(message())
            }
        )
    }
}

@available(macOS 15.5, *)
extension ExtensionContextResidencyOwner:
    ExtensionInactiveProfileContextRetiring {}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func touchLiveExtensionContext(extensionId: String, profileId: UUID) {
        contextResidencyOwner.touchLiveExtensionContext(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func enforceBoundedLiveExtensionContexts(
        keepingProfileId: UUID,
        keepingExtensionId: String
    ) {
        contextResidencyOwner.enforceBoundedLiveExtensionContexts(
            keepingProfileId: keepingProfileId,
            keepingExtensionId: keepingExtensionId
        )
    }

    func unloadExtensionContextsForInactiveProfiles(keepingProfileId: UUID) {
        contextResidencyOwner.unloadExtensionContextsForInactiveProfiles(
            keepingProfileId: keepingProfileId
        )
    }

    func unloadExtensionContextIfLoaded(
        extensionId: String,
        profileId: UUID
    ) {
        contextResidencyOwner.unloadExtensionContextIfLoaded(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func quiesceForWebsiteDataMutation(profileIDs: Set<UUID>) -> Bool {
        optionsWindows.closeWindows(backedBy: profileIDs)
        actionPopupRetirement.closePopup(backedBy: profileIDs)
        return contextResidencyOwner.quiesceForWebsiteDataMutation(
            profileIDs: profileIDs
        )
    }

    @discardableResult
    func ensureExtensionLoaded(
        extensionId: String,
        profileId: UUID
    ) async throws -> WKWebExtensionContext? {
        try await contextResidencyOwner.ensureExtensionLoaded(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func ensureEnabledExtensionsLoaded(for profileId: UUID) async {
        await contextResidencyOwner.ensureEnabledExtensionsLoaded(for: profileId)
    }
}
