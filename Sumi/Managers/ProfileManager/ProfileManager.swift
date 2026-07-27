//
//  ProfileManager.swift
//  Sumi
//
//  Manages runtime profiles and their database persistence.
//

import Foundation
import SwiftUI
import WebKit

enum ProfileManagerMutationError: Error, Equatable {
    case profileStoreUnavailable
    case retiredReference(UUID)
    case profileIdentityMutationRequiresRetirement
    case invalidImportMutationLease
}

@MainActor
final class ProfileManager: ObservableObject {
    let database: SumiDatabase
    let profileReferenceAdmission: ProfileReferenceAdmissionLedger
    @Published var profiles: [Profile] = []
    private(set) var profileStoreIsAvailable = true
    private let faviconService: any BrowserFaviconServicing
    private let visitedLinkStore: any BrowserVisitedLinkStoreManaging

    // MARK: - Ephemeral Profiles (Incognito)
    /// Active ephemeral profiles (one per incognito window)
    private var ephemeralProfiles: [UUID: Profile] = [:] // windowId -> profile

    init(
        database: SumiDatabase,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger? = nil,
        faviconService: any BrowserFaviconServicing = TabDependencyIsolationDefaults.faviconService,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging = TabDependencyIsolationDefaults.visitedLinkStore
    ) {
        self.database = database
        if let profileReferenceAdmission {
            self.profileReferenceAdmission = profileReferenceAdmission
        } else {
            do {
                self.profileReferenceAdmission = try ProfileReferenceAdmissionLedger(
                    database: database
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
        loadProfiles()
    }

    // MARK: - Loading
    func loadProfiles() {
        do {
            let records = try database.read { try $0.profiles.all() }
            profileStoreIsAvailable = true
            let admittedRecords = records.filter {
                profileReferenceAdmission.isReferenceAllowed($0.id)
            }
            if admittedRecords.count != records.count {
                RuntimeDiagnostics.emit(
                    "[ProfileRetirement] Suppressed blocked persisted profiles"
                )
            }
            self.profiles = admittedRecords.map { record in
                Profile(id: record.id, name: record.name)
            }
            // Normalize indices if not sequential 0..n-1
            let expected = Array(0..<admittedRecords.count)
            let actual = admittedRecords.map(\.index)
            if actual != expected {
                normalizeAdmittedProfileIndices(admittedRecords)
            }
        } catch {
            RuntimeDiagnostics.emit("[ProfileManager] Failed to load profiles: \(error)")
            profileStoreIsAvailable = false
            self.profiles = []
        }
    }

    // MARK: - CRUD
    @discardableResult
    func createProfile(name: String) throws -> Profile {
        guard profileStoreIsAvailable else {
            throw ProfileManagerMutationError.profileStoreUnavailable
        }
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
        try database.transaction { transaction in
            try transaction.profiles.save(
                ProfileRecord(id: profile.id, name: name, index: nextIndex)
            )
        }
        profiles.append(profile)
        return profile
    }

    /// Deletes the canonical profile row and advances the exact retirement
    /// journal in the same transaction before publishing runtime removal.
    func beginReferenceMigration(_ token: ProfileRetirementToken) throws -> Bool {
        guard profileStoreIsAvailable,
              profiles.count > 1,
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
        guard profileStoreIsAvailable,
              profiles.isEmpty == false,
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
        _ admittedRecords: [ProfileRecord]
    ) {
        do {
            try database.transaction { transaction in
                for (index, var record) in admittedRecords.enumerated() {
                    record.index = index
                    try transaction.profiles.save(record)
                }
            }
        } catch {
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
        guard profileStoreIsAvailable else {
            throw ProfileManagerMutationError.profileStoreUnavailable
        }
        try database.transaction { transaction in
            let all = try transaction.profiles.all()
            let existingIDs = Set(all.map(\.id))
            let keep = Set(snapshot.map(\.id))
            for id in existingIDs.subtracting(keep) {
                try transaction.profiles.delete(id: id)
            }
            for (index, profile) in snapshot.enumerated() {
                try transaction.profiles.save(
                    ProfileRecord(
                        id: profile.id,
                        name: profile.name,
                        index: index
                    )
                )
            }
        }
    }

    func ensureDefaultProfile() {
        if profileStoreIsAvailable,
           profiles.isEmpty,
           profileReferenceAdmission.isAvailable {
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
