import Foundation
import SumiDomain

struct ShortcutProfileReferenceMutationPlan {
    struct SplitReplacement {
        let expected: [SplitGroup]
        let replacement: [SplitGroup]
    }

    let deletedProfileID: UUID
    let fallbackProfileID: UUID
    let removedProfilePins: [ShortcutPin]?
    let profilePinReplacements: [UUID: [ShortcutPin]]
    let spacePinReplacements: [UUID: [ShortcutPin]]
    let pendingPinsToAdopt: [ShortcutPin]
    let splitReplacement: SplitReplacement?
    let requiresFallbackAdmission: Bool

    var isEmpty: Bool {
        removedProfilePins == nil
            && profilePinReplacements.isEmpty
            && spacePinReplacements.isEmpty
            && pendingPinsToAdopt.isEmpty
            && splitReplacement == nil
    }
}
