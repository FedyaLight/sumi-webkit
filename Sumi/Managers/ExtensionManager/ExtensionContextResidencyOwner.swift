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
        let runtimeSession: ExtensionRuntimeSession
        let backgroundRuntimeStateOwner: ExtensionBackgroundRuntimeStateOwner
        let isExtensionSupportAvailable: @MainActor () -> Bool
        let extensionsModuleEnabledForRuntimeBoundary: @MainActor () -> Bool
        let ensureExtensionController: @MainActor (UUID) -> Void
        let getExtensionContext: @MainActor (String, UUID) -> WKWebExtensionContext?
        let countLoadedContexts: @MainActor () -> Int
        let readinessContext: @MainActor (UUID) -> ExtensionRuntimeReadinessContext?
        let extensionEntity: @MainActor (String) throws -> ExtensionEntity?
        let enabledPersistedExtensionEntities: @MainActor () -> [ExtensionEntity]
        let loadEnabledExtension: @MainActor (ExtensionEntity, UUID, UInt64) async throws -> Void
        let setExtensionsLoaded: @MainActor (Bool) -> Void
        let trace: @MainActor (() -> String) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func touchLiveExtensionContext(extensionId: String, profileId: UUID) {
        dependencies.runtimeSession.extensionRuntimeResidencyState.touch(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    func enforceBoundedLiveExtensionContexts(
        keepingProfileId: UUID,
        keepingExtensionId: String
    ) {
        let evictionCandidates =
            dependencies.runtimeSession.extensionRuntimeResidencyState
                .touchAndEvictionCandidates(
                    loadedContextCount: dependencies.countLoadedContexts(),
                    limit: ExtensionManager.maxLiveExtensionContexts,
                    keepingExtensionId: keepingExtensionId,
                    keepingProfileId: keepingProfileId
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
        dependencies.runtimeSession.extensionLoadGeneration &+= 1

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
        guard let context = dependencies.getExtensionContext(extensionId, profileId) else {
            return true
        }

        let wakeKey = ExtensionRuntimeResidencyState.scopedKey(
            extensionId: extensionId,
            profileId: profileId
        )
        dependencies.backgroundRuntimeStateOwner.cancelAndRemoveRuntime(for: wakeKey)
        guard let controller = dependencies.profileRuntime.controller(for: profileId) else {
            dependencies.trace {
                "Unable to unload extension \(extensionId) for profile \(profileId.uuidString): missing controller"
            }
            return false
        }
        do {
            try controller.unload(context)
        } catch {
            dependencies.trace {
                "Failed to unload extension \(extensionId) profile \(profileId.uuidString): \(error.localizedDescription)"
            }
            return false
        }

        dependencies.runtimeSession.extensionRuntimeResidencyState.remove(
            extensionId: extensionId,
            profileId: profileId
        )
        _ = dependencies.profileRuntime.removeContext(
            extensionId: extensionId,
            profileId: profileId
        )

        dependencies.trace {
            "unloadExtensionContext extensionId=\(extensionId) profileId=\(profileId.uuidString) remainingContexts=\(self.dependencies.countLoadedContexts())"
        }
        return true
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
            profileId,
            dependencies.runtimeSession.extensionLoadGeneration
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
        let enabledEntities = dependencies.enabledPersistedExtensionEntities()
        guard enabledEntities.isEmpty == false else { return }

        for entity in enabledEntities {
            guard dependencies.getExtensionContext(entity.id, profileId) == nil else {
                continue
            }

            do {
                try await dependencies.loadEnabledExtension(
                    entity,
                    profileId,
                    dependencies.runtimeSession.extensionLoadGeneration
                )
            } catch {
                ExtensionManager.logger.error(
                    "Failed to load enabled extension \(entity.name, privacy: .public) for profile \(profileId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        markExtensionRuntimeReadyIfProfileContextsLoaded(for: profileId)
    }

    func markExtensionRuntimeReadyIfProfileContextsLoaded(for profileId: UUID) {
        guard dependencies.profileRuntime.controller(for: profileId) != nil else { return }
        guard let readiness = dependencies.readinessContext(profileId) else { return }
        dependencies.setExtensionsLoaded(true)
        if readiness.isProfileReady {
            dependencies.runtimeSession.runtimeState = .ready
        } else if dependencies.runtimeSession.runtimeState != .failed {
            dependencies.runtimeSession.runtimeState = .loading
        }
        dependencies.trace {
            "markExtensionRuntimeReady profile=\(profileId.uuidString) loadedContexts=\(self.dependencies.profileRuntime.contexts(for: profileId).count) allEnabledLoaded=\(readiness.isProfileReady) unloadedEnabledExtensionIDs=\(readiness.unloadedEnabledExtensionIDs.joined(separator: ","))"
        }
    }
}

@available(macOS 15.5, *)
extension ExtensionContextResidencyOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            profileRuntime: manager.profileRuntime,
            runtimeSession: manager.runtimeSession,
            backgroundRuntimeStateOwner: manager.backgroundRuntimeStateOwner,
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
            readinessContext: { [weak manager] profileId in
                manager?.extensionRuntimeReadinessContext(for: profileId)
            },
            extensionEntity: { [weak manager] extensionId in
                try manager?.extensionEntity(for: extensionId)
            },
            enabledPersistedExtensionEntities: { [weak manager] in
                manager?.enabledPersistedExtensionEntities() ?? []
            },
            loadEnabledExtension: { [weak manager] entity, profileId, generation in
                _ = try await manager?.extensionRuntimeLoader.loadEnabled(
                    from: entity,
                    profileID: profileId,
                    expectedLoadGeneration: generation
                )
            },
            setExtensionsLoaded: { [weak manager] loaded in
                manager?.extensionsLoaded = loaded
            },
            trace: { [weak manager] message in
                manager?.runtimeDiagnostics.trace(message())
            }
        )
    }
}

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
        actionPopupSessionOwner.closePopup(backedBy: profileIDs)
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

    func markExtensionRuntimeReadyIfProfileContextsLoaded(for profileId: UUID) {
        contextResidencyOwner.markExtensionRuntimeReadyIfProfileContextsLoaded(
            for: profileId
        )
    }
}
