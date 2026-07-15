import Foundation
import SumiDomain

/// Immutable source and target pages for one same-ID launcher refresh.
/// The complete set is admitted before durable launcher placement changes.
@MainActor
struct LiveShortcutPresentationRefreshAdmission {
    struct Change {
        let tab: Tab
        let windowID: UUID
        let sourcePage: LiveShortcutPresentationPageReceipt
        let targetPage: LiveShortcutPresentationPageReceipt
    }

    let pinID: UUID
    let role: ShortcutPinRole
    let profileID: UUID?
    let executionProfileID: UUID?
    let spaceID: UUID?
    let changes: [Change]

    init(pin: ShortcutPin, changes: [Change]) {
        pinID = pin.id
        role = pin.role
        profileID = pin.profileId
        executionProfileID = pin.executionProfileId
        spaceID = pin.spaceId
        self.changes = changes
    }

    func accepts(_ pin: ShortcutPin) -> Bool {
        pin.id == pinID
            && pin.role == role
            && pin.profileId == profileID
            && pin.executionProfileId == executionProfileID
            && pin.spaceId == spaceID
    }
}
