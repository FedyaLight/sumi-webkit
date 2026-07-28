import Foundation
import WebKit

@MainActor
final class BrowserProfileWebKitBootstrap {
    private struct PreparedProfile {
        let generation: UInt64
        let profile: Profile
        let dataStoreIdentity: ObjectIdentifier
    }

    private let profiles: @MainActor () -> [Profile]
    private var generation: UInt64 = 0
    private var preparedByProfileID: [UUID: PreparedProfile] = [:]
    private var pendingProfileIDs: Set<UUID> = []
    private var backgroundPreparation: Task<Void, Never>?

    init(profiles: @escaping @MainActor () -> [Profile]) {
        self.profiles = profiles
    }

    func prepareForeground(_ profile: Profile?) {
        guard let profile else { return }
        prepare(profile, generation: generation)
    }

    func prepareAfterFirstPaint(profileIDs: Set<UUID>) {
        let scheduledGeneration = generation
        pendingProfileIDs.formUnion(profileIDs)
        guard backgroundPreparation == nil else { return }
        backgroundPreparation = Task { @MainActor [weak self] in
            guard let self else { return }
            while let profileID = pendingProfileIDs.first {
                pendingProfileIDs.remove(profileID)
                await Task.yield()
                guard Task.isCancelled == false,
                      generation == scheduledGeneration,
                      let profile = profiles().first(where: {
                          $0.id == profileID
                      })
                else {
                    continue
                }
                prepare(profile, generation: scheduledGeneration)
            }
            backgroundPreparation = nil
        }
    }

    func invalidate(profileID: UUID? = nil) {
        generation &+= 1
        backgroundPreparation?.cancel()
        backgroundPreparation = nil
        pendingProfileIDs.removeAll(keepingCapacity: true)
        if let profileID {
            preparedByProfileID[profileID] = nil
        } else {
            preparedByProfileID.removeAll(keepingCapacity: true)
        }
    }

    func isPrepared(_ profile: Profile) -> Bool {
        guard let prepared = preparedByProfileID[profile.id] else {
            return false
        }
        return prepared.generation == generation
            && prepared.profile === profile
            && prepared.dataStoreIdentity == ObjectIdentifier(profile.dataStore)
    }

    private func prepare(_ profile: Profile, generation: UInt64) {
        if let prepared = preparedByProfileID[profile.id],
           prepared.generation == generation,
           prepared.profile === profile {
            return
        }
        profile.prepareWebKitRuntime()
        preparedByProfileID[profile.id] = PreparedProfile(
            generation: generation,
            profile: profile,
            dataStoreIdentity: ObjectIdentifier(profile.dataStore)
        )
    }
}
