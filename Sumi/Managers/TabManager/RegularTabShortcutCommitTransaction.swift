import Foundation
import SumiDomain

/// Owns one structural batch that inserts a pin, replaces durable split
/// topology, and settles the exact displayed or detached runtime participant.
@MainActor
final class RegularTabShortcutCommitTransaction {
    private enum RuntimeAdmission {
        case displayed(
            AuthorizedDisplayedTabShortcutConversion,
            DisplayedShortcutPresentationResidencePlan
        )
        case detached(AuthorizedDetachedTabShortcutConversion)
    }

    private enum Structure {
        case sourceReplacement
        case sidebar(
            PreparedRegularTabShortcutSidebarDrop,
            [SumiDomain.SplitGroup],
            RegularTabShortcutSidebarMutationPreparation
        )
    }

    private struct ResolvedStructure {
        let expected: [SumiDomain.SplitGroup]
        let replacement: [SumiDomain.SplitGroup]
        let transition: RegularTabShortcutWindowTransitionPlan
        let sidebar: RegularTabShortcutSidebarMutationPreparation
    }

    private enum CommittedRuntime {
        case displayed(RegularTabShortcutCommitParticipants)
        case detached(
            RegularTabShortcutCommitParticipants,
            DetachedTabShortcutConversionReceipt
        )

        @MainActor
        func publish() {
            switch self {
            case .displayed(let participants):
                participants.publishTopology()
            case .detached(let participants, let source):
                participants.publishTopology()
                source.publish()
            }
        }
    }

    private struct CommittedConversion {
        let pin: ShortcutPin
        let runtime: CommittedRuntime
    }

    private let persistence: TabStructuralPersistenceService
    private let pins: ShortcutPinStoreOwner
    private let folderOpenState: TabFolderOpenStateService
    private let splitMutations: SplitGroupMutationService
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let liveShortcuts: LiveShortcutTabRegistry
    private let presentationResolution: ShortcutPinRuntimeResolutionOwner
    private let windowMutations: BrowserWindowShortcutMutationOwner
    private let displayedTransition: DisplayedTabShortcutConversionCommitter
    private let detachedTransition: DetachedTabShortcutConverter

    init(
        persistence: TabStructuralPersistenceService,
        pins: ShortcutPinStoreOwner,
        folderOpenState: TabFolderOpenStateService,
        splitMutations: SplitGroupMutationService,
        structuralMutations: TabStructuralCollectionMutationOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        liveShortcuts: LiveShortcutTabRegistry,
        presentationResolution: ShortcutPinRuntimeResolutionOwner,
        windowMutations: BrowserWindowShortcutMutationOwner,
        displayedTransition: DisplayedTabShortcutConversionCommitter,
        detachedTransition: DetachedTabShortcutConverter
    ) {
        self.persistence = persistence
        self.pins = pins
        self.folderOpenState = folderOpenState
        self.splitMutations = splitMutations
        self.structuralMutations = structuralMutations
        self.structuralLookup = structuralLookup
        self.liveShortcuts = liveShortcuts
        self.presentationResolution = presentationResolution
        self.windowMutations = windowMutations
        self.displayedTransition = displayedTransition
        self.detachedTransition = detachedTransition
    }

    func commit(
        _ candidate: PreparedRegularTabShortcutConversion,
        authorization: AuthorizedTabShortcutConversion
    ) -> ShortcutPin? {
        commit(
            candidate,
            structure: .sourceReplacement,
            authorization: authorization
        )
    }

    func commit(
        _ prepared: PreparedRegularTabShortcutSidebarDrop,
        replacement: [SumiDomain.SplitGroup],
        authorization: AuthorizedTabShortcutConversion,
        sidebarMutation: RegularTabShortcutSidebarMutationPreparation
    ) -> ShortcutPin? {
        commit(
            prepared.conversion,
            structure: .sidebar(prepared, replacement, sidebarMutation),
            authorization: authorization
        )
    }

    private func commit(
        _ candidate: PreparedRegularTabShortcutConversion,
        structure: Structure,
        authorization: AuthorizedTabShortcutConversion
    ) -> ShortcutPin? {
        guard let admission = admit(
            candidate.candidatePin,
            authorization: authorization
        ) else { return nil }
        var committed: CommittedConversion?
        structuralLookup.withTransaction {
            let accepted = structuralMutations.withReversibleSideEffects {
                committed = stage(
                    candidate,
                    structure: structure,
                    admission: admission
                )
                return committed != nil
            }
            if accepted { committed?.runtime.publish() }
        }
        guard let pin = committed?.pin else { return nil }
        persistence.scheduleStructuralPersistence()
        return pin
    }

    private func stage(
        _ candidate: PreparedRegularTabShortcutConversion,
        structure: Structure,
        admission: RuntimeAdmission
    ) -> CommittedConversion? {
        guard let pin = insert(candidate),
              let resolved = resolve(structure, candidate: candidate, pin: pin)
        else { return nil }
        let topology: SplitGroupReplacementReceipt?
        if resolved.expected == resolved.replacement {
            topology = nil
        } else {
            guard let receipt = splitMutations.prepareReplaceAll(
                expected: resolved.expected,
                with: resolved.replacement,
                persist: false
            ) else { return nil }
            topology = receipt
        }
        guard let sidebar = resolved.sidebar.stage() else {
            topology?.rollback()
            return nil
        }
        let participants = RegularTabShortcutCommitParticipants(
            topology: topology,
            sidebar: sidebar,
            windowMutations: windowMutations
        )

        let runtime: CommittedRuntime
        switch admission {
        case .displayed(let authorization, let presentations):
            guard let displayed = DisplayedTabShortcutConversionReceipt(
                pin: pin,
                transition: resolved.transition,
                authorization: authorization,
                presentations: presentations,
                registry: liveShortcuts,
                resolution: presentationResolution,
                committer: displayedTransition
            ), participants.settleDisplayed(displayed) else {
                precondition(participants.rollback())
                return nil
            }
            participants.commitSidebar()
            runtime = .displayed(participants)
        case .detached(let authorization):
            guard let detached = detachedTransition.prepare(
                transition: resolved.transition,
                using: authorization,
                participants: participants
            ) else {
                precondition(participants.rollback())
                return nil
            }
            guard detached.isCurrent(), detached.sealRuntime() else {
                precondition(
                    detached.rollback(),
                    "Admitted detached retirement lost rollback"
                )
                precondition(participants.rollback())
                return nil
            }
            participants.settleDetached(detached)
            participants.commitSidebar()
            runtime = .detached(participants, detached)
        }
        commit(candidate.destination)
        return CommittedConversion(pin: pin, runtime: runtime)
    }

    private func resolve(
        _ structure: Structure,
        candidate: PreparedRegularTabShortcutConversion,
        pin: ShortcutPin
    ) -> ResolvedStructure? {
        switch structure {
        case .sourceReplacement:
            guard let member = shortcutMember(for: pin),
                  let replacement = candidate.structure.replacingSource(
                      with: member
                  ) else { return nil }
            return ResolvedStructure(
                expected: candidate.structure.expectedSplitGroups,
                replacement: replacement,
                transition: .replacingSource(
                    groupID: candidate.structure.sourceSplitGroupID,
                    memberID: member.memberID
                ),
                sidebar: .noChange
            )
        case .sidebar(let prepared, let replacement, let sidebar):
            return ResolvedStructure(
                expected: prepared.expectedSplitGroups,
                replacement: replacement,
                transition: .movingToShortcutSidebar(
                    sourceGroupID: candidate.structure.sourceSplitGroupID,
                    targetGroupID: prepared.targetGroup.id,
                    memberID: prepared.member.memberID
                ),
                sidebar: sidebar
            )
        }
    }

    private func insert(
        _ candidate: PreparedRegularTabShortcutConversion
    ) -> ShortcutPin? {
        guard let pin = pins.insert(
            candidate.candidatePin,
            at: candidate.destination.index,
            openTargetFolder: false
        ) else { return nil }
        let expected = candidate.candidatePin
        guard pin.id == expected.id,
              pin.role == expected.role,
              pin.profileId == expected.profileId,
              pin.executionProfileId == expected.executionProfileId,
              pin.spaceId == expected.spaceId,
              pin.folderId == expected.folderId,
              pin.launchURL == expected.launchURL,
              pin.iconAsset == expected.iconAsset else { return nil }
        return pin
    }

    private func commit(_ destination: TabShortcutPinDestination) {
        guard destination.opensFolder,
              let folderID = destination.folderId else { return }
        folderOpenState.openFolderIfNeeded(folderID)
    }

    private func admit(
        _ pin: ShortcutPin,
        authorization: AuthorizedTabShortcutConversion
    ) -> RuntimeAdmission? {
        switch authorization {
        case .displayed(let value):
            guard let presentations = DisplayedShortcutPresentationResidencePlan(
                pin: pin,
                authorization: value,
                registry: liveShortcuts,
                resolution: presentationResolution
            ) else { return nil }
            return .displayed(value, presentations)
        case .detached(let value):
            return .detached(value)
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
