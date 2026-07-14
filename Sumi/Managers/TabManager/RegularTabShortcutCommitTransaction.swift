import Foundation
import SumiDomain

/// Owns the single structural batch that inserts a pin, replaces durable split
/// values and transitions every affected window/runtime instance.
@MainActor
final class RegularTabShortcutCommitTransaction {
    private let schedulePersistence: () -> Void
    private let insertPin: (ShortcutPin, Int, Bool) -> ShortcutPin?
    private let removePin: (ShortcutPin) -> Void
    private let splitMutations: SplitGroupMutationService
    private let structuralLookup: TabStructuralLookupCoordinator
    private let displayedTransition: DisplayedTabShortcutConversionCommitter
    private let detachedTransition: DetachedTabShortcutConverter

    init(
        schedulePersistence: @escaping () -> Void,
        insertPin: @escaping (ShortcutPin, Int, Bool) -> ShortcutPin?,
        removePin: @escaping (ShortcutPin) -> Void,
        splitMutations: SplitGroupMutationService,
        structuralLookup: TabStructuralLookupCoordinator,
        displayedTransition: DisplayedTabShortcutConversionCommitter,
        detachedTransition: DetachedTabShortcutConverter
    ) {
        self.schedulePersistence = schedulePersistence
        self.insertPin = insertPin
        self.removePin = removePin
        self.splitMutations = splitMutations
        self.structuralLookup = structuralLookup
        self.displayedTransition = displayedTransition
        self.detachedTransition = detachedTransition
    }

    func commit(
        _ candidate: PreparedRegularTabShortcutConversion,
        authorization: AuthorizedTabShortcutConversion
    ) -> ShortcutPin? {
        var result: ShortcutPin?
        structuralLookup.withTransaction {
            guard let pin = insert(candidate) else { return }
            guard let member = shortcutMember(for: pin),
                  let replacement = candidate.structure.replacingSource(
                      with: member
                  ) else {
                removePin(pin)
                return
            }
            let committed: Bool
            if replacement == candidate.structure.expectedSplitGroups {
                committed = applyRuntime(
                    pin,
                    transition: .replacingSource(
                        groupID: candidate.structure.sourceSplitGroupID,
                        memberID: member.memberID
                    ),
                    authorization
                )
            } else {
                committed = splitMutations.replaceAllAtomically(
                    expected: candidate.structure.expectedSplitGroups,
                    with: replacement,
                    persist: false,
                    applying: { [self] in
                        applyRuntime(
                            pin,
                            transition: .replacingSource(
                                groupID: candidate.structure.sourceSplitGroupID,
                                memberID: member.memberID
                            ),
                            authorization
                        )
                    }
                )
            }
            guard committed else {
                removePin(pin)
                return
            }
            result = pin
        }
        return finish(result)
    }

    func commit(
        _ prepared: PreparedRegularTabShortcutSidebarDrop,
        replacement: [SumiDomain.SplitGroup],
        authorization: AuthorizedTabShortcutConversion,
        applyingSplitSideEffect: @escaping @MainActor () -> Bool
    ) -> ShortcutPin? {
        var result: ShortcutPin?
        structuralLookup.withTransaction {
            guard let pin = insert(prepared.conversion) else { return }
            let committed = splitMutations.replaceAllAtomically(
                expected: prepared.expectedSplitGroups,
                with: replacement,
                persist: false,
                applying: { [self] in
                    guard applyingSplitSideEffect() else { return false }
                    return applyRuntime(
                        pin,
                        transition: .movingToShortcutSidebar(
                            sourceGroupID: prepared.conversion.structure
                                .sourceSplitGroupID,
                            targetGroupID: prepared.targetGroup.id,
                            memberID: prepared.member.memberID
                        ),
                        authorization
                    )
                }
            )
            guard committed else {
                removePin(pin)
                return
            }
            result = pin
        }
        return finish(result)
    }

    private func insert(
        _ candidate: PreparedRegularTabShortcutConversion
    ) -> ShortcutPin? {
        guard let pin = insertPin(
            candidate.candidatePin,
            candidate.destination.index,
            candidate.destination.opensFolder
        ) else { return nil }
        guard pin.id == candidate.candidatePin.id else {
            removePin(pin)
            return nil
        }
        return pin
    }

    private func finish(_ pin: ShortcutPin?) -> ShortcutPin? {
        guard let pin else { return nil }
        schedulePersistence()
        return pin
    }

    private func applyRuntime(
        _ pin: ShortcutPin,
        transition: RegularTabShortcutWindowTransitionPlan,
        _ authorization: AuthorizedTabShortcutConversion
    ) -> Bool {
        switch authorization {
        case .displayed(let value):
            displayedTransition.apply(
                to: pin,
                transition: transition,
                using: value
            )
            return true
        case .detached(let value):
            return detachedTransition.apply(
                to: pin,
                transition: transition,
                using: value
            )
        }
    }

    private func shortcutMember(for pin: ShortcutPin) -> SplitMember? {
        switch pin.role {
        case .essential:
            return .shortcutPin(
                pin.id,
                returnPlacement: .essential(
                    profileId: pin.profileId,
                    index: pin.index
                )
            )
        case .spacePinned:
            guard let spaceID = pin.spaceId else { return nil }
            return .shortcutPin(
                pin.id,
                returnPlacement: .spacePinned(
                    spaceId: spaceID,
                    folderId: pin.folderId,
                    index: pin.index
                )
            )
        }
    }
}
