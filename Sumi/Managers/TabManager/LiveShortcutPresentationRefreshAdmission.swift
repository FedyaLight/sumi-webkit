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

    private init(
        pinID: UUID,
        role: ShortcutPinRole,
        profileID: UUID?,
        executionProfileID: UUID?,
        spaceID: UUID?,
        changes: [Change]
    ) {
        self.pinID = pinID
        self.role = role
        self.profileID = profileID
        self.executionProfileID = executionProfileID
        self.spaceID = spaceID
        self.changes = changes
    }

    func consuming(
        _ exclusion: ShortcutLiveRetirementBindingExclusion,
        for pin: ShortcutPin
    ) -> Self? {
        guard accepts(pin), exclusion.belongs(to: pin) else { return nil }
        let matches = changes.filter {
            exclusion.matches(pin: pin, change: $0)
        }
        guard matches.count == 1 else { return nil }
        return Self(
            pinID: pinID,
            role: role,
            profileID: profileID,
            executionProfileID: executionProfileID,
            spaceID: spaceID,
            changes: changes.filter {
                exclusion.matches(pin: pin, change: $0) == false
            }
        )
    }

    func accepts(_ pin: ShortcutPin) -> Bool {
        pin.id == pinID
            && pin.role == role
            && pin.profileId == profileID
            && pin.executionProfileId == executionProfileID
            && pin.spaceId == spaceID
    }
}
