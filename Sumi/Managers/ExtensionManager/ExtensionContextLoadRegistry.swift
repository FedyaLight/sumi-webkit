import Foundation

struct ExtensionContextLoadClaimToken: Equatable {
    fileprivate let sequence: UInt64
}

struct ExtensionContextLoadClaim: Equatable {
    let key: ExtensionRuntimeResidencyState.ScopedKey
    let token: ExtensionContextLoadClaimToken
}

@MainActor
final class ExtensionContextLoadRegistry {
    private var currentClaims:
        [ExtensionRuntimeResidencyState.ScopedKey: ExtensionContextLoadClaim] = [:]
    private var nextSequence: UInt64 = 0

    func begin(
        for key: ExtensionRuntimeResidencyState.ScopedKey
    ) -> ExtensionContextLoadClaim {
        nextSequence &+= 1
        let claim = ExtensionContextLoadClaim(
            key: key,
            token: ExtensionContextLoadClaimToken(sequence: nextSequence)
        )
        currentClaims[key] = claim
        return claim
    }

    func beginIfIdle(
        for key: ExtensionRuntimeResidencyState.ScopedKey
    ) -> ExtensionContextLoadClaim? {
        guard currentClaims[key] == nil else { return nil }
        return begin(for: key)
    }

    func isCurrent(_ claim: ExtensionContextLoadClaim) -> Bool {
        currentClaims[claim.key] == claim
    }

    /// Rollback cleanup is safe while its claim is still current or after it
    /// was cancelled without a replacement. A different current claim owns
    /// the scoped runtime state and must not be erased by the older load.
    func isCurrentOrUnclaimed(_ claim: ExtensionContextLoadClaim) -> Bool {
        currentClaims[claim.key].map { $0 == claim } ?? true
    }

    /// Extension-global rollback cleanup must not run while another profile
    /// is preparing the same extension. That load may not have published a
    /// context binding yet, but already owns any cache or action state it
    /// creates after its claim.
    func admitsExtensionGlobalRollback(
        _ claim: ExtensionContextLoadClaim
    ) -> Bool {
        guard isCurrentOrUnclaimed(claim) else { return false }
        return hasCompetingClaim(for: claim) == false
    }

    func hasCompetingClaim(for claim: ExtensionContextLoadClaim) -> Bool {
        currentClaims.values.contains { current in
            current.key.extensionId == claim.key.extensionId
                && current != claim
        }
    }

    @discardableResult
    func finishIfCurrent(_ claim: ExtensionContextLoadClaim) -> Bool {
        guard isCurrent(claim) else {
            return false
        }

        currentClaims.removeValue(forKey: claim.key)
        return true
    }

    func invalidate(extensionId: String) {
        currentClaims = currentClaims.filter {
            $0.key.extensionId != extensionId
        }
    }

    func invalidate(_ key: ExtensionRuntimeResidencyState.ScopedKey) {
        currentClaims.removeValue(forKey: key)
    }

    func invalidate(profileIDs: Set<UUID>) {
        currentClaims = currentClaims.filter {
            profileIDs.contains($0.key.profileId) == false
        }
    }

    func invalidateAll() {
        currentClaims.removeAll()
    }
}
