import Foundation
import SumiDomain

actor SumiPermissionProfileAdmission {
    struct Lease: Hashable, Sendable {
        fileprivate let id: UUID
        fileprivate let profileID: String
    }

    private var retiredProfileIDs: Set<String> = []
    private var leaseIDsByProfileID: [String: Set<UUID>] = [:]
    private var drainWaitersByProfileID: [String: [CheckedContinuation<Void, Never>]] = [:]

    func admit(profilePartitionId: String) -> Lease? {
        let profileID = normalizedProfileID(profilePartitionId)
        guard retiredProfileIDs.contains(profileID) == false else {
            return nil
        }
        let lease = Lease(id: UUID(), profileID: profileID)
        leaseIDsByProfileID[profileID, default: []].insert(lease.id)
        return lease
    }

    @discardableResult
    func seal(profilePartitionId: String) -> String {
        let profileID = normalizedProfileID(profilePartitionId)
        retiredProfileIDs.insert(profileID)
        return profileID
    }

    func release(_ lease: Lease) {
        guard var leaseIDs = leaseIDsByProfileID[lease.profileID],
              leaseIDs.remove(lease.id) != nil
        else {
            return
        }
        guard leaseIDs.isEmpty else {
            leaseIDsByProfileID[lease.profileID] = leaseIDs
            return
        }

        leaseIDsByProfileID[lease.profileID] = nil
        let waiters = drainWaitersByProfileID.removeValue(
            forKey: lease.profileID
        ) ?? []
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForDrain(profilePartitionId: String) async {
        let profileID = normalizedProfileID(profilePartitionId)
        guard leaseIDsByProfileID[profileID]?.isEmpty == false else {
            return
        }
        await withCheckedContinuation { continuation in
            drainWaitersByProfileID[profileID, default: []].append(
                continuation
            )
        }
    }

    func isRetired(_ profilePartitionId: String) -> Bool {
        retiredProfileIDs.contains(normalizedProfileID(profilePartitionId))
    }

    func withLease<Result: Sendable>(
        profilePartitionId: String,
        operation: @Sendable () async throws -> Result
    ) async rethrows -> Result? {
        guard let lease = admit(profilePartitionId: profilePartitionId) else {
            return nil
        }
        do {
            let result = try await operation()
            release(lease)
            return result
        } catch {
            release(lease)
            throw error
        }
    }

    private func normalizedProfileID(_ profilePartitionId: String) -> String {
        SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
    }
}
