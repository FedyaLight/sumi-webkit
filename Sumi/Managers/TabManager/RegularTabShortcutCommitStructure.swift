import SumiDomain

@MainActor
enum RegularTabShortcutCommitStructure {
    case sourceReplacement
    case sidebar(
        PreparedRegularTabShortcutSidebarDrop,
        [SumiDomain.SplitGroup],
        RegularTabShortcutSidebarMutationPreparation
    )

    var sidebarPreparation: RegularTabShortcutSidebarMutationPreparation {
        switch self {
        case .sourceReplacement: return .noChange
        case .sidebar(_, _, let preparation): return preparation
        }
    }
}

@MainActor
struct PreparedRegularTabShortcutCommitStructure {
    let insertion: ShortcutSplitLauncherCatalogInsertionPlan
    let transition: RegularTabShortcutWindowTransitionPlan
    let durable: RegularTabShortcutDurableStructureParticipant
}

@MainActor
final class RegularTabShortcutCommitStructurePreparer {
    private let catalog: ShortcutSplitLauncherCatalogTransaction
    private let topology: SplitGroupMutationService
    private let structural: TabStructuralCollectionMutationOwner

    init(
        catalog: ShortcutSplitLauncherCatalogTransaction,
        topology: SplitGroupMutationService,
        structural: TabStructuralCollectionMutationOwner
    ) {
        self.catalog = catalog
        self.topology = topology
        self.structural = structural
    }

    func prepare(
        _ candidate: PreparedRegularTabShortcutConversion,
        structure: RegularTabShortcutCommitStructure
    ) -> PreparedRegularTabShortcutCommitStructure? {
        guard let insertion = catalog.prepareInsertion(
            candidate.candidatePin,
            at: candidate.destination.index,
            sidebarVisualMembership: structure.sidebarVisualMembership
        ), insertion.insertion.target.accepts(insertion.insertedPin),
           let resolved = resolve(
               structure,
               candidate: candidate,
               pin: insertion.insertedPin
           ) else { return nil }
        let receipt: SplitGroupReplacementReceipt?
        if resolved.expected == resolved.replacement {
            receipt = nil
        } else {
            receipt = topology.prepareReplaceAll(
                expected: resolved.expected,
                with: resolved.replacement,
                persist: false
            )
        }
        guard resolved.expected == resolved.replacement || receipt != nil else {
            return nil
        }
        return PreparedRegularTabShortcutCommitStructure(
            insertion: insertion,
            transition: resolved.transition,
            durable: RegularTabShortcutDurableStructureParticipant(
                mutations: structural,
                topology: receipt
            )
        )
    }

    func prepareSidebar(
        _ preflight: RegularTabShortcutSidebarBindingPreflight,
        insertion: ShortcutSplitLauncherCatalogInsertionPlan,
        builder: ShortcutTabBindingBatchBuilder
    ) -> RegularTabShortcutSidebarBindingContribution? {
        preflight.prepareContribution(
            after: insertion,
            catalog: catalog,
            builder: builder
        )
    }

    func committedPin(
        for prepared: PreparedRegularTabShortcutCommitStructure
    ) -> ShortcutPin? {
        guard let pin = catalog.currentPin(
            withID: prepared.insertion.insertedPin.id
        ), prepared.insertion.insertion.target.accepts(pin) else { return nil }
        return pin
    }

    private func resolve(
        _ structure: RegularTabShortcutCommitStructure,
        candidate: PreparedRegularTabShortcutConversion,
        pin: ShortcutPin
    ) -> (
        expected: [SumiDomain.SplitGroup],
        replacement: [SumiDomain.SplitGroup],
        transition: RegularTabShortcutWindowTransitionPlan
    )? {
        switch structure {
        case .sourceReplacement:
            guard let member = shortcutMember(for: pin),
                  let replacement = candidate.structure.replacingSource(
                      with: member
                  ) else { return nil }
            return (
                candidate.structure.expectedSplitGroups,
                replacement,
                .replacingSource(
                    groupID: candidate.structure
                        .presentationSourceSplitGroupID,
                    memberID: member.memberID
                )
            )
        case .sidebar(let prepared, let replacement, _):
            return (
                prepared.expectedSplitGroups,
                replacement,
                .movingToShortcutSidebar(
                    sourceGroupID: candidate.structure.sourceSplitGroupID,
                    targetGroupID: prepared.targetGroup.id,
                    memberID: prepared.member.memberID
                )
            )
        }
    }

    private func shortcutMember(for pin: ShortcutPin) -> SplitMember? {
        .shortcutPin(pin.id)
    }
}

private extension RegularTabShortcutCommitStructure {
    var sidebarVisualMembership: ShortcutPinSidebarVisualMembership {
        switch self {
        case .sourceReplacement:
            return .standalone
        case .sidebar:
            return .splitMember
        }
    }
}
