import Foundation

@available(macOS 15.5, *)
struct ExtensionOptionsWindowPresentationClaim: Hashable, Sendable {
    let extensionID: String
    let profileID: UUID?
    let revision: UInt64
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowPresentationClaimLedger {
    private var revisionsByExtensionID: [String: UInt64] = [:]
    private var activeClaimsByExtensionID:
        [String: ExtensionOptionsWindowPresentationClaim] = [:]

    func issue(
        for extensionID: String,
        profileID: UUID?
    ) -> ExtensionOptionsWindowPresentationClaim {
        let revision = nextRevision(for: extensionID)
        let claim = ExtensionOptionsWindowPresentationClaim(
            extensionID: extensionID,
            profileID: profileID,
            revision: revision
        )
        activeClaimsByExtensionID[extensionID] = claim
        return claim
    }

    func isCurrent(
        _ claim: ExtensionOptionsWindowPresentationClaim
    ) -> Bool {
        activeClaimsByExtensionID[claim.extensionID] == claim
            && revisionsByExtensionID[claim.extensionID] == claim.revision
    }

    func invalidate(for extensionID: String) {
        _ = nextRevision(for: extensionID)
        activeClaimsByExtensionID.removeValue(forKey: extensionID)
    }

    func invalidate(backedBy profileIDs: Set<UUID>) {
        activeClaimsByExtensionID.values.compactMap { claim in
            claim.profileID.map(profileIDs.contains) == true
                ? claim.extensionID
                : nil
        }.forEach(invalidate(for:))
    }

    func invalidateAll() {
        Array(activeClaimsByExtensionID.keys).forEach(invalidate(for:))
    }

    private func nextRevision(for extensionID: String) -> UInt64 {
        let current = revisionsByExtensionID[extensionID] ?? 0
        precondition(
            current < UInt64.max,
            "Extension options presentation revision exhausted"
        )
        let next = current + 1
        revisionsByExtensionID[extensionID] = next
        return next
    }
}
