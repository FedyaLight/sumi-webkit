import Foundation

@MainActor
final class ShortcutExecutionProfileAssignmentService {
    private unowned let tabManager: TabManager
    private let policy: ProfileAssignmentPolicy

    init(tabManager: TabManager, policy: ProfileAssignmentPolicy) {
        self.tabManager = tabManager
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
        let current = tabManager.shortcutPinCollectionStateOwner.shortcutPin(
            by: pin.id
        ) ?? pin
        guard current.executionProfileId != profileID else { return current }
        return tabManager.shortcutPinCommandOwner.updateShortcutPin(
            current,
            executionProfileId: .some(profileID)
        )
    }
}
