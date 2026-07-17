import Foundation

@MainActor
final class TabLastSessionProfileAdmissionTransaction {
    private let ledger: ProfileReferenceAdmissionLedger

    init(ledger: ProfileReferenceAdmissionLedger) {
        self.ledger = ledger
    }

    func withAdmittedReferences(
        _ profileIDs: Set<UUID>,
        perform: () -> Void
    ) -> Bool {
        let lease: ProfileReferenceMutationLease
        do {
            lease = try ledger.beginReferenceMutation(to: profileIDs)
        } catch {
            return false
        }
        defer {
            precondition(
                ledger.endReferenceMutation(lease),
                "Last-session merge lost its exact profile-reference mutation lease"
            )
        }
        guard ledger.validate(lease, covers: profileIDs) else { return false }
        perform()
        return ledger.validate(lease, covers: profileIDs)
    }
}
