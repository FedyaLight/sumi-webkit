import Foundation

/// Commits one same-identity shortcut metadata replacement together with its
/// live presentation update. Structural state is restored when live bindings
/// cannot accept the prepared target.
@MainActor
final class ShortcutPinMetadataMutationService {
    private let pins: ShortcutPinCollectionStateOwner
    private let bindings: ShortcutTabBindingSynchronizer
    private let profileAdmissions: ProfileReferenceAdmissionLedger
    private let persistence: TabStructuralPersistenceService
    private let commitTransaction: ShortcutPinMetadataCommitTransaction

    init(
        pins: ShortcutPinCollectionStateOwner,
        bindings: ShortcutTabBindingSynchronizer,
        profileAdmissions: ProfileReferenceAdmissionLedger,
        persistence: TabStructuralPersistenceService,
        commitTransaction: ShortcutPinMetadataCommitTransaction
    ) {
        self.pins = pins
        self.bindings = bindings
        self.profileAdmissions = profileAdmissions
        self.persistence = persistence
        self.commitTransaction = commitTransaction
    }

    @discardableResult
    func update(
        _ source: ShortcutPin,
        title: String? = nil,
        launchURL: URL? = nil,
        iconAsset: String?? = nil,
        executionProfileId: UUID?? = nil,
        titleIsCustom: Bool? = nil
    ) -> ShortcutPin? {
        guard let current = pins.shortcutPin(by: source.id),
              current === source
        else { return nil }
        let target = current.updated(
            title: title,
            launchURL: launchURL,
            iconAsset: iconAsset,
            executionProfileId: executionProfileId,
            titleIsCustom: titleIsCustom
        )
        let lease: ProfileReferenceMutationLease
        do {
            lease = try profileAdmissions.beginReferenceMutation(
                to: current.profileReferenceIDs.union(target.profileReferenceIDs)
            )
        } catch {
            return nil
        }
        defer {
            precondition(profileAdmissions.endReferenceMutation(lease))
        }
        guard let presentation = bindings.refreshAdmission(for: target),
              let accepted = commitTransaction.commit(
                replacing: current,
                with: target,
                presentation: presentation
              )
        else { return nil }
        persistence.scheduleStructuralPersistence()
        return accepted
    }
}
