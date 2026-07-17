import Foundation

@MainActor
final class ShortcutExecutionProfileAssignmentService {
    private let pins: ShortcutPinCollectionStateOwner
    private let mutations: ShortcutPinMetadataMutationService
    private let policy: ProfileAssignmentPolicy

    init(
        pins: ShortcutPinCollectionStateOwner,
        mutations: ShortcutPinMetadataMutationService,
        policy: ProfileAssignmentPolicy
    ) {
        self.pins = pins
        self.mutations = mutations
        self.policy = policy
    }

    @discardableResult
    func assign(
        _ pin: ShortcutPin,
        toExecutionProfile profileID: UUID
    ) -> ShortcutPin? {
        guard policy.profileExists(profileID) else {
            RuntimeDiagnostics.emit(
                "⚠️ [TabManager] Attempted to assign pinned tab to unknown profile: \(profileID)"
            )
            return nil
        }
        guard let current = pins.shortcutPin(by: pin.id),
              current === pin
        else { return nil }
        guard current.executionProfileId != profileID else { return current }
        return mutations.update(
            current,
            executionProfileId: .some(profileID)
        )
    }
}
