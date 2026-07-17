import Foundation
import SumiDomain

@MainActor
final class SpaceCreationTransaction {
    private let transactions: TabStructuralLookupCoordinator
    private let spaces: TabSpaceCollectionStateOwner
    private let runtimeConnection: TabRuntimePortConnection
    private let profileReferenceAdmission: ProfileReferenceAdmissionLedger
    private let committer: SpaceCreationCommitter

    init(
        transactions: TabStructuralLookupCoordinator,
        spaces: TabSpaceCollectionStateOwner,
        runtimeConnection: TabRuntimePortConnection,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        committer: SpaceCreationCommitter
    ) {
        self.transactions = transactions
        self.spaces = spaces
        self.runtimeConnection = runtimeConnection
        self.profileReferenceAdmission = profileReferenceAdmission
        self.committer = committer
    }

    func create(
        name: String,
        icon: String,
        workspaceTheme: WorkspaceTheme?,
        profileID: UUID?
    ) -> Space? {
        transactions.withTransaction {
            let runtimeLease = runtimeConnection.captureLease()
            let usesRuntimeDefault = profileID == nil
            let resolvedProfileID = profileID ?? runtimeLease.defaultProfileID
            let resolvedTheme = workspaceTheme
                ?? SumiWorkspaceThemePresets.rotatingTheme(at: spaces.count)
            let profileIDs = Set([resolvedProfileID].compactMap { $0 })
            let mutationLease: ProfileReferenceMutationLease
            do {
                mutationLease = try profileReferenceAdmission
                    .beginReferenceMutation(to: profileIDs)
            } catch {
                return nil
            }
            let space = Space(
                name: name,
                icon: icon,
                workspaceTheme: resolvedTheme,
                profileId: resolvedProfileID
            )
            if resolvedProfileID == nil {
                RuntimeDiagnostics.debug(
                    "Creating space '\(name)' without a resolved profile; profile reconciliation will run later.",
                    category: "SpaceCatalog"
                )
            }

            guard !usesRuntimeDefault
                    || runtimeConnection.acceptsExactAttachment(runtimeLease),
                  profileReferenceAdmission.validate(
                mutationLease,
                covers: profileIDs
            ) else {
                precondition(
                    profileReferenceAdmission.endReferenceMutation(
                        mutationLease
                    )
                )
                return nil
            }
            committer.commit(space, to: spaces, in: transactions)
            transactions.runAfterCurrentBatch {
                precondition(
                    self.profileReferenceAdmission.endReferenceMutation(
                        mutationLease
                    ),
                    "Space creation lost its profile-reference mutation lease"
                )
            }
            return space
        }
    }
}
