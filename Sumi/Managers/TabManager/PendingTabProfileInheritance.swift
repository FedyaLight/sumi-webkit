import Foundation
import SumiWebRuntime

/// Remembers why a Tab temporarily carries its Space's pending profile.
/// The provenance survives either transaction settling first, so a rejected
/// Tab override can safely return to canonical Space inheritance.
@MainActor
final class PendingTabProfileInheritance {
    private struct Provenance {
        weak var tab: Tab?
        let spaceID: UUID
        let spaceRevision: UInt64
        let inheritedProfileID: UUID
        var spaceCommitted = false
    }

    private var provenanceByTabID: [UUID: Provenance] = [:]

    func record(
        tab: Tab,
        spaceID: UUID,
        spaceRevision: UInt64,
        inheritedProfileID: UUID
    ) {
        removeReleasedTabs()
        provenanceByTabID[tab.id] = Provenance(
            tab: tab,
            spaceID: spaceID,
            spaceRevision: spaceRevision,
            inheritedProfileID: inheritedProfileID
        )
    }

    func discard(spaceIntent: DeferredWebViewSpaceProfileAssignmentIntent) {
        removeProvenance(matching: spaceIntent)
    }

    func spaceTransitionCommitted(
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        canonicalProfileID: UUID?,
        isTabStillInSpace: (Tab, UUID) -> Bool
    ) {
        removeReleasedTabs()
        reconcileCommittedSpace(
            intent: intent,
            canonicalProfileID: canonicalProfileID,
            isTabStillInSpace: isTabStillInSpace
        )
    }

    func tabTransitionSettled(
        _ settlement: ProfileTransitionSettlement,
        tab: Tab,
        intent: DeferredWebViewProfileAssignmentIntent,
        canonicalProfileID: UUID?,
        isTabStillInSpace: Bool
    ) -> Bool {
        removeReleasedTabs()
        guard let provenance = provenanceByTabID[tab.id],
              provenance.tab === tab else { return false }

        switch settlement {
        case .committed:
            provenanceByTabID.removeValue(forKey: tab.id)
            return false
        case .rejected, .rolledBack:
            guard provenance.spaceCommitted,
                  tab.profileAssignment.hasUnsettledAssignment == false else {
                return false
            }
            provenanceByTabID.removeValue(forKey: tab.id)
            guard intent.expectedProfileID == provenance.inheritedProfileID else {
                return false
            }
            return normalizeIfCanonical(
                tab,
                provenance: provenance,
                canonicalProfileID: canonicalProfileID,
                isTabStillInSpace: isTabStillInSpace
            )
        case .conflicted, .leaseLost, .terminalShutdown:
            return false
        }
    }

    func tabBecameStable(
        _ tab: Tab,
        canonicalProfileID: UUID?,
        isTabStillInSpace: Bool
    ) -> Bool {
        removeReleasedTabs()
        guard let provenance = provenanceByTabID[tab.id],
              provenance.tab === tab,
              provenance.spaceCommitted,
              tab.profileAssignment.hasUnsettledAssignment == false else {
            return false
        }
        provenanceByTabID.removeValue(forKey: tab.id)
        return normalizeIfCanonical(
            tab,
            provenance: provenance,
            canonicalProfileID: canonicalProfileID,
            isTabStillInSpace: isTabStillInSpace
        )
    }

    func tabLeftSourceSpace(_ tab: Tab) {
        guard provenanceByTabID[tab.id]?.tab === tab else { return }
        provenanceByTabID.removeValue(forKey: tab.id)
    }

    private func reconcileCommittedSpace(
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        canonicalProfileID: UUID?,
        isTabStillInSpace: (Tab, UUID) -> Bool
    ) {
        for (tabID, var provenance) in provenanceByTabID
        where matches(provenance, intent: intent) {
            guard let tab = provenance.tab,
                  provenance.inheritedProfileID == intent.desiredProfileID,
                  canonicalProfileID == provenance.inheritedProfileID,
                  tab.spaceId == provenance.spaceID,
                  isTabStillInSpace(tab, provenance.spaceID) else {
                provenanceByTabID.removeValue(forKey: tabID)
                continue
            }

            provenance.spaceCommitted = true
            if tab.profileAssignment.hasUnsettledAssignment {
                provenanceByTabID[tabID] = provenance
            } else {
                provenanceByTabID.removeValue(forKey: tabID)
                _ = normalizeIfCanonical(
                    tab,
                    provenance: provenance,
                    canonicalProfileID: canonicalProfileID,
                    isTabStillInSpace: true
                )
            }
        }
    }

    private func normalizeIfCanonical(
        _ tab: Tab,
        provenance: Provenance,
        canonicalProfileID: UUID?,
        isTabStillInSpace: Bool
    ) -> Bool {
        guard canonicalProfileID == provenance.inheritedProfileID,
              tab.profileId == provenance.inheritedProfileID,
              tab.spaceId == provenance.spaceID,
              isTabStillInSpace else { return false }
        tab.profileId = nil
        return true
    }

    private func removeProvenance(
        matching intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) {
        provenanceByTabID = provenanceByTabID.filter { _, provenance in
            !matches(provenance, intent: intent) && provenance.tab != nil
        }
    }

    private func matches(
        _ provenance: Provenance,
        intent: DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool {
        provenance.spaceID == intent.spaceID
            && provenance.spaceRevision == intent.revision
    }

    private func removeReleasedTabs() {
        provenanceByTabID = provenanceByTabID.filter { $0.value.tab != nil }
    }
}
