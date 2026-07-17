import Foundation

@MainActor
extension GlanceManager {
    func containsProfileReference(to profileID: UUID) -> Bool {
        guard let currentSession else { return false }
        return ProfileReferenceInventory(glanceSession: currentSession)
            .contains(profileID)
    }

    @discardableResult
    func retireProfileReference(to profileID: UUID) -> Bool {
        if containsProfileReference(to: profileID) {
            dismissGlance(persistsWindowSession: false)
        }
        return containsProfileReference(to: profileID) == false
    }
}
