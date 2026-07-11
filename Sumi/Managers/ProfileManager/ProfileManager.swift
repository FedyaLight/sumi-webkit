//
//  ProfileManager.swift
//  Sumi
//
//  Manages runtime profiles and their SwiftData persistence.
//

import Foundation
import SumiDomain
import SwiftData
import SwiftUI
import WebKit

@MainActor
final class ProfileManager: ObservableObject {
    let context: ModelContext
    @Published var profiles: [Profile] = []
    private let faviconService: any BrowserFaviconServicing
    private let visitedLinkStore: any BrowserVisitedLinkStoreManaging

    // MARK: - Ephemeral Profiles (Incognito)
    /// Active ephemeral profiles (one per incognito window)
    private var ephemeralProfiles: [UUID: Profile] = [:] // windowId -> profile

    init(
        context: ModelContext,
        faviconService: any BrowserFaviconServicing = TabDependencyIsolationDefaults.faviconService,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging = TabDependencyIsolationDefaults.visitedLinkStore
    ) {
        self.context = context
        self.faviconService = faviconService
        self.visitedLinkStore = visitedLinkStore
        loadProfiles()
    }

    // MARK: - Loading
    func loadProfiles() {
        do {
            let descriptor = FetchDescriptor<ProfileEntity>(
                sortBy: [SortDescriptor(\.index, order: .forward)]
            )
            let entities = try context.fetch(descriptor)
            self.profiles = entities.map { e in
                Profile(id: e.id, name: e.name, icon: e.icon)
            }
            // Normalize indices if not sequential 0..n-1
            let expected = Array(0..<entities.count)
            let actual = entities.map { $0.index }
            if actual != expected { persistProfiles() }
        } catch {
            RuntimeDiagnostics.emit("[ProfileManager] Failed to load profiles: \(error)")
            self.profiles = []
        }
    }

    // MARK: - CRUD
    @discardableResult
    func createProfile(name: String, icon: String = SumiProfileIcon.defaultIcon) -> Profile {
        // Next index is current count (append to end)
        let nextIndex = profiles.count
        let profile = Profile(name: name, icon: icon)
        let entity = ProfileEntity(id: profile.id, name: name, icon: profile.icon, index: nextIndex)
        context.insert(entity)
        do { try context.save() } catch { RuntimeDiagnostics.emit("[ProfileManager] Save failed during create: \(error)") }
        profiles.append(profile)
        return profile
    }

    /// Persists profile-entity removal only.
    /// Full deletion cleanup (browsing data, favicons, permissions) runs through
    /// `ProfileDeletionCleanupOrchestrator` in `SumiProfileMaintenanceService.deleteProfile`.
    func deleteProfile(_ profile: Profile) -> Bool {
        guard profiles.count > 1 else { return false } // prevent deleting last profile
        // Remove from SwiftData first; if persistence fails, do not mutate runtime state
        do {
            let pid = profile.id
            let predicate = #Predicate<ProfileEntity> { $0.id == pid }
            if let entity = try context.fetch(FetchDescriptor<ProfileEntity>(predicate: predicate)).first {
                context.delete(entity)
            }
            try context.save()
        } catch {
            RuntimeDiagnostics.emit("[ProfileManager] Delete failed: \(error)")
            return false
        }
        // Remove from runtime and reindex
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles.remove(at: idx)
        }
        persistProfiles()
        return true
    }

    func persistProfiles() {
        do {
            try persistProfileSnapshot(profiles)
        } catch {
            RuntimeDiagnostics.emit("[ProfileManager] Persist failed: \(error)")
        }
    }

    /// Atomically persists a complete profile snapshot before publishing it to runtime readers.
    /// Import rollback uses the same operation, so a failed save never exposes an unpersisted list.
    func replaceProfiles(with replacement: [Profile]) throws {
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
                    entity.icon = profile.icon
                    entity.index = index
                } else {
                    let entity = ProfileEntity(
                        id: profile.id,
                        name: profile.name,
                        icon: profile.icon,
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
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func ensureDefaultProfile() {
        if profiles.isEmpty {
            _ = createProfile(name: "Default", icon: SumiProfileIcon.defaultIcon)
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
        faviconService.clearFaviconPartition(for: profile)
        profile.destroyEphemeralDataStore()
    }
}
