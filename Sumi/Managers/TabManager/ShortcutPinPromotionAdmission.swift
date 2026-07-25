import Foundation
import SumiDomain

/// Decides what may be promoted from the shortcut sidebar to a regular tab.
///
/// Admission has three parts, all resolved against live collection state: the
/// candidate pin must still be canonical, a whole group must have every member
/// still resolving to a canonical pin, and a grouped pin may only be promoted
/// when its split group has a representable transition.
@MainActor
struct ShortcutPinPromotionAdmission {
    /// Whether a pin's split group permits promotion, and how.
    enum SplitOutcome {
        /// The pin is not grouped, or its group transitions cleanly.
        case admitted(ShortcutPinRegularSplitTransition?)
        /// The pin is grouped but its group has no representable transition.
        case blocked
    }

    private let splitGroups: SplitGroupStore
    private let pins: ShortcutPinCollectionStateOwner
    private let planner = ShortcutPinRegularSplitTransitionPlanner()

    init(
        splitGroups: SplitGroupStore,
        pins: ShortcutPinCollectionStateOwner
    ) {
        self.splitGroups = splitGroups
        self.pins = pins
    }

    /// The live pin behind a caller-supplied candidate, or `nil` if it is stale.
    func canonicalPin(for candidate: ShortcutPin) -> ShortcutPin? {
        pins.shortcutPin(by: candidate.id)
    }

    func splitOutcome(
        pinID: UUID,
        promotedTabID: UUID,
        targetSpaceID: UUID
    ) -> SplitOutcome {
        guard let group = splitGroups.group(containing: .shortcutPin(pinID))
        else { return .admitted(nil) }
        guard let transition = planner.transition(
            group: group,
            pinID: pinID,
            promotedTabID: promotedTabID,
            targetSpaceID: targetSpaceID
        ) else { return .blocked }
        return .admitted(transition)
    }

    /// The group's canonical member pins, or `nil` when the group is stale, is
    /// not a shortcut-sidebar group, or has a member that no longer resolves.
    func canonicalGroupPins(for group: SplitGroup) -> [ShortcutPin]? {
        guard splitGroups.group(id: group.id) == group,
              group.container.isShortcutSidebar else { return nil }
        let groupPins = group.memberIDs.compactMap { memberID -> ShortcutPin? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return pins.shortcutPin(by: pinID)
        }
        guard groupPins.count == group.memberIDs.count else { return nil }
        return groupPins
    }
}
