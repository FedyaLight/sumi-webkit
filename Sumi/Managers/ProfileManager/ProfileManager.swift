//
//  ProfileManager.swift
//  Sumi
//
//  Manages runtime profiles and their SwiftData persistence.
//

import Foundation
import SwiftData
import SwiftUI
import WebKit

enum ProfileManagerMutationError: Error, Equatable {
    case retiredReference(UUID)
    case profileIdentityMutationRequiresRetirement
    case invalidImportMutationLease
}

@MainActor
final class ProfileManager: ObservableObject {
    let context: ModelContext
    let profileReferenceAdmission: ProfileReferenceAdmissionLedger
    @Published var profiles: [Profile] = []
    private let faviconService: any BrowserFaviconServicing
    private let visitedLinkStore: any BrowserVisitedLinkStoreManaging
    private let saveContext: @MainActor (ModelContext) throws -> Void

    // MARK: - Ephemeral Profiles (Incognito)
    /// Active ephemeral profiles (one per incognito window)
    private var ephemeralProfiles: [UUID: Profile] = [:] // windowId -> profile

    init(
        context: ModelContext,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger? = nil,
        faviconService: any BrowserFaviconServicing = TabDependencyIsolationDefaults.faviconService,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging = TabDependencyIsolationDefaults.visitedLinkStore,
        saveContext: @escaping @MainActor (ModelContext) throws -> Void = {
            try $0.save()
        }
    ) {
        self.context = context
        if let profileReferenceAdmission {
            self.profileReferenceAdmission = profileReferenceAdmission
        } else {
            do {
                self.profileReferenceAdmission = try ProfileReferenceAdmissionLedger(
                    context: context
                )
            } catch {
                RuntimeDiagnostics.emit(
                    "[ProfileRetirement] Profile admission unavailable: \(error)"
                )
                self.profileReferenceAdmission = .failClosed()
            }
        }
        self.faviconService = faviconService
        self.visitedLinkStore = visitedLinkStore
        self.saveContext = saveContext
        loadProfiles()
    }

    // MARK: - Loading
    func loadProfiles() {
        do {
            let descriptor = FetchDescriptor<ProfileEntity>(
                sortBy: [SortDescriptor(\.index, order: .forward)]
            )
            let entities = try context.fetch(descriptor)
            let admittedEntities = entities.filter {
                profileReferenceAdmission.isReferenceAllowed($0.id)
            }
            if admittedEntities.count != entities.count {
                RuntimeDiagnostics.emit(
                    "[ProfileRetirement] Suppressed blocked persisted profiles"
                )
            }
            self.profiles = admittedEntities.map { e in
                Profile(id: e.id, name: e.name)
            }
            // Normalize indices if not sequential 0..n-1
            let expected = Array(0..<admittedEntities.count)
            let actual = admittedEntities.map { $0.index }
            if actual != expected {
                normalizeAdmittedProfileIndices(admittedEntities)
            }
        } catch {
            RuntimeDiagnostics.emit("[ProfileManager] Failed to load profiles: \(error)")
            self.profiles = []
        }
    }

    // MARK: - CRUD
    @discardableResult
    func createProfile(name: String) throws -> Profile {
        precondition(
            profileReferenceAdmission.isAvailable,
            "Profile creation requires durable reference admission"
        )
        // Next index is current count (append to end)
        let nextIndex = profiles.count
        let profile = Profile(name: name)
        let mutationLease = try profileReferenceAdmission
            .beginReferenceMutation(to: [profile.id])
        defer {
            precondition(
                profileReferenceAdmission.endReferenceMutation(mutationLease),
                "Profile creation lost its reference mutation lease"
            )
        }
        let entity = ProfileEntity(id: profile.id, name: name, index: nextIndex)
        context.insert(entity)
        do {
            try saveContext(context)
        } catch {
            context.rollback()
            throw error
        }
        profiles.append(profile)
        return profile
    }

    /// Deletes the canonical profile row and advances the exact retirement
    /// journal in the same SwiftData save before publishing runtime removal.
    func beginReferenceMigration(_ token: ProfileRetirementToken) throws -> Bool {
        guard profiles.count > 1,
              let record = profileReferenceAdmission.record(for: token),
              record.phase == .reserved,
              profiles.contains(where: { $0.id == token.profileID }),
              profiles.contains(where: { $0.id == record.fallbackProfileID }),
              try profileReferenceAdmission.beginReferenceMigration(token)
        else {
            return false
        }
        profiles.removeAll { $0.id == token.profileID }
        return true
    }

    func commitLogicalDeletion(_ token: ProfileRetirementToken) throws -> Bool {
        guard profiles.isEmpty == false,
              let record = profileReferenceAdmission.record(for: token),
              record.phase == .migratingReferences,
              profiles.contains(where: { $0.id == token.profileID }) == false,
              profiles.contains(where: { $0.id == record.fallbackProfileID })
        else {
            return false
        }

        let committed = try profileReferenceAdmission.commitLogicalDeletion(token)
        guard committed else { return false }
        return true
    }

    func persistProfiles() {
        do {
            try persistProfileSnapshot(profiles)
        } catch {
            RuntimeDiagnostics.emit("[ProfileManager] Persist failed: \(error)")
        }
    }

    private func normalizeAdmittedProfileIndices(
        _ admittedEntities: [ProfileEntity]
    ) {
        do {
            for (index, entity) in admittedEntities.enumerated() {
                entity.index = index
            }
            try saveContext(context)
        } catch {
            context.rollback()
            RuntimeDiagnostics.emit(
                "[ProfileManager] Failed to normalize admitted profile indices: \(error)"
            )
        }
    }

    /// Atomically persists a complete profile snapshot before publishing it to runtime readers.
    /// Import rollback uses the same operation, so a failed save never exposes an unpersisted list.
    func replaceProfiles(with replacement: [Profile]) throws {
        let currentIDs = profiles.map(\.id)
        let replacementIDs = replacement.map(\.id)
        guard currentIDs.count == replacementIDs.count,
              Set(currentIDs) == Set(replacementIDs)
        else {
            throw ProfileManagerMutationError
                .profileIdentityMutationRequiresRetirement
        }
        if let rejected = replacement.first(where: {
            profileReferenceAdmission.isReferenceAllowed($0.id) == false
        }) {
            throw ProfileManagerMutationError.retiredReference(rejected.id)
        }
        try persistProfileSnapshot(replacement)
        profiles = replacement
    }

    /// Import may publish new profile identities while holding the same
    /// reference-admission lease as the structural install. Existing identities
    /// are never removed here; removal remains owned by durable retirement.
    func applyImportProfiles(
        _ replacement: [Profile],
        mutationLease: ProfileReferenceMutationLease
    ) throws {
        let currentIDs = Set(profiles.map(\.id))
        let replacementIDs = Set(replacement.map(\.id))
        guard replacementIDs.isSuperset(of: currentIDs),
              profileReferenceAdmission.validate(
                  mutationLease,
                  covers: replacementIDs
              )
        else {
            throw ProfileManagerMutationError.invalidImportMutationLease
        }
        if let rejected = replacement.first(where: {
            profileReferenceAdmission.isReferenceAllowed($0.id) == false
        }) {
            throw ProfileManagerMutationError.retiredReference(rejected.id)
        }
        try persistProfileSnapshot(replacement)
        profiles = replacement
    }

    private func persistProfileSnapshot(_ snapshot: [Profile]) throws {
        do {
            let all = try context.fetch(FetchDescriptor<ProfileEntity>())
            var byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            for (index, profile) in snapshot.enumerated() {
                if let entity = byId[profile.id] {
                    entity.name = profile.name
                    entity.index = index
                } else {
                    let entity = ProfileEntity(
                        id: profile.id,
                        name: profile.name,
                        index: index
                    )
                    context.insert(entity)
                    byId[profile.id] = entity
                }
            }
            let keep = Set(snapshot.map(\.id))
            for (id, entity) in byId where !keep.contains(id) {
                context.delete(entity)
            }
            try saveContext(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func ensureDefaultProfile() {
        if profiles.isEmpty, profileReferenceAdmission.isAvailable {
            do {
                try createProfile(name: "Default")
            } catch {
                RuntimeDiagnostics.emit(
                    "[ProfileManager] Failed to create default profile: \(error)"
                )
            }
        }
    }

    // MARK: - Ephemeral Profile Management

    /// Create a new ephemeral profile for an incognito window
    func createEphemeralProfile(for windowId: UUID) -> Profile {
        if ephemeralProfiles.isEmpty {
            _ = BasicAuthCredentialStore().deleteCredentials(
                profilePartitionId: nil,
                isEphemeralProfile: true
            )
        }
        let profile = Profile.createEphemeral()
        ephemeralProfiles[windowId] = profile
        RuntimeDiagnostics.emit("🔒 [ProfileManager] Created ephemeral profile for window: \(windowId)")
        return profile
    }

    /// Gives a browser-created child window the exact private partition of its
    /// physical opener. WebKit child configurations retain the opener's data
    /// store, so manufacturing a second profile here would make model identity
    /// disagree with the actual `WKWebsiteDataStore`.
    func shareEphemeralProfile(
        from sourceWindowId: UUID,
        with childWindowId: UUID
    ) -> Profile? {
        guard sourceWindowId != childWindowId,
              ephemeralProfiles[childWindowId] == nil,
              let profile = ephemeralProfiles[sourceWindowId],
              profile.isEphemeral
        else {
            return nil
        }
        ephemeralProfiles[childWindowId] = profile
        return profile
    }

    func ephemeralProfile(withID profileID: UUID) -> Profile? {
        ephemeralProfiles.values.first { $0.id == profileID }
    }

    /// Proves that one exact private window owns a lease on one exact
    /// non-persistent profile. Finding the profile under another window is not
    /// sufficient: shared private partitions must be leased explicitly.
    func hasEphemeralProfileLease(
        _ profile: Profile,
        forWindowID windowID: UUID
    ) -> Bool {
        ephemeralProfiles[windowID] === profile
            && profile.isEphemeral
            && profile.dataStore.isPersistent == false
    }

    /// Cancels a share that never reached window publication. Destruction is
    /// intentionally impossible here because the source window still owns the
    /// same partition.
    @discardableResult
    func cancelEphemeralProfileShare(
        for childWindowId: UUID,
        expected profile: Profile
    ) -> Bool {
        guard ephemeralProfiles[childWindowId] === profile,
              ephemeralProfiles.contains(where: {
                  $0.key != childWindowId && $0.value === profile
              })
        else {
            return false
        }
        ephemeralProfiles.removeValue(forKey: childWindowId)
        return true
    }

    /// Rolls back a private partition that was created for a window which was
    /// never published. A shared partition must instead release only its
    /// child-window lease through `cancelEphemeralProfileShare`.
    @discardableResult
    func cancelEphemeralProfileCreation(
        for windowId: UUID,
        expected profile: Profile
    ) -> Bool {
        guard ephemeralProfiles[windowId] === profile,
              ephemeralProfiles.contains(where: {
                  $0.key != windowId && $0.value === profile
              }) == false
        else {
            return false
        }
        ephemeralProfiles.removeValue(forKey: windowId)
        destroyEphemeralPartition(profile)
        return true
    }

    /// Releases one private-window reference. The partition is destroyed only
    /// after its final browser window closes.
    func releaseEphemeralProfile(for windowId: UUID) async -> UUID? {
        guard let profile = ephemeralProfiles[windowId] else { return nil }

        RuntimeDiagnostics.emit("🔒 [ProfileManager] Removing ephemeral profile: \(profile.id) for window: \(windowId)")

        // Remove from tracking immediately to stop tracking
        ephemeralProfiles.removeValue(forKey: windowId)
        if ephemeralProfiles.values.contains(where: { $0 === profile }) {
            RuntimeDiagnostics.emit(
                "🔒 [ProfileManager] Retained shared ephemeral profile: \(profile.id)"
            )
            return nil
        }
        destroyEphemeralPartition(profile)

        RuntimeDiagnostics.emit("🔒 [ProfileManager] Ephemeral profile removed: \(profile.id) for window: \(windowId)")
        return profile.id
    }

    private func destroyEphemeralPartition(_ profile: Profile) {
        visitedLinkStore.discardStore(for: profile.id)
        _ = BasicAuthCredentialStore().deleteCredentials(
            profilePartitionId: profile.id,
            isEphemeralProfile: true
        )
        do {
            try faviconService.clearFaviconPartition(for: profile)
        } catch {
            RuntimeDiagnostics.emit(
                "[ProfileManager] Failed to clear ephemeral favicon partition: \(error)"
            )
        }
        profile.destroyEphemeralDataStore()
    }
}
