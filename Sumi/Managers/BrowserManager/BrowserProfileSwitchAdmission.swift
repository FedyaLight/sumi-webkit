import Foundation

@MainActor
final class BrowserProfileSwitchAdmission {
    struct PreparedTransition {
        let targetWindow: BrowserWindowState?
        let mutationLease: ProfileReferenceMutationLease
    }

    private let windows: WindowRegistry
    private let profileAdmissions: ProfileReferenceAdmissionLedger

    init(
        windows: WindowRegistry,
        profileAdmissions: ProfileReferenceAdmissionLedger
    ) {
        self.windows = windows
        self.profileAdmissions = profileAdmissions
    }

    func admitReference(
        to profileID: UUID
    ) -> ProfileReferenceAdmissionReceipt? {
        profileAdmissions.admitReference(to: profileID)
    }

    func prepare(
        profileID: UUID,
        receipt: ProfileReferenceAdmissionReceipt,
        context: BrowserProfileSwitchContext,
        requestedWindow: BrowserWindowState?
    ) -> PreparedTransition? {
        let targetWindow = requestedWindow ?? windows.activeWindow
        guard profileAdmissions.validate(receipt),
              canApply(context: context, targetWindow: targetWindow),
              let mutationLease = beginMutationLease(
                  to: profileID,
                  context: context
              )
        else { return nil }
        return PreparedTransition(
            targetWindow: targetWindow,
            mutationLease: mutationLease
        )
    }

    func finish(_ transition: PreparedTransition) {
        precondition(
            profileAdmissions.endReferenceMutation(
                transition.mutationLease
            ),
            "Profile switch mutation lease ownership was lost"
        )
    }

    private func canApply(
        context: BrowserProfileSwitchContext,
        targetWindow: BrowserWindowState?
    ) -> Bool {
        switch context {
        case .userInitiated, .recovery, .profileRetirement:
            return true
        case .windowActivation, .spaceChange:
            guard let targetWindow,
                  windows.windows[targetWindow.id] === targetWindow,
                  windows.activeWindow === targetWindow
            else {
                RuntimeDiagnostics.emit {
                    let targetID = targetWindow?.id.uuidString ?? "nil"
                    return "⏳ [BrowserManager] Ignoring stale profile switch for \(context): targetWindow=\(targetID)"
                }
                return false
            }
            return true
        }
    }

    private func beginMutationLease(
        to profileID: UUID,
        context: BrowserProfileSwitchContext
    ) -> ProfileReferenceMutationLease? {
        do {
            switch context {
            case .profileRetirement:
                return try profileAdmissions
                    .beginRetirementReferenceMigration(to: [profileID])
            case .userInitiated, .spaceChange, .windowActivation, .recovery:
                return try profileAdmissions
                    .beginReferenceMutation(to: [profileID])
            }
        } catch {
            return nil
        }
    }
}
