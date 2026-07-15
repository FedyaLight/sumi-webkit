import Foundation

@MainActor
struct ShortcutTabBindingWindowContribution {
    struct Entry {
        let window: BrowserWindowState
        let source: BrowserWindowShortcutMutationState
        let target: BrowserWindowShortcutMutationState
        let requiresPersistence: Bool
    }

    static let empty = ShortcutTabBindingWindowContribution(entries: [])
    let entries: [Entry]
}

@MainActor
struct ShortcutTabBindingBatchContribution {
    let inputs: [ShortcutTabBindingModelTransaction.Input]
    let profileAdmissions: [ShortcutTabProfileAssignmentAdmission]
    let residences: [any ShortcutTabBindingResidenceTransaction]

    static func combining(
        _ contributions: [ShortcutTabBindingBatchContribution]
    ) -> ShortcutTabBindingBatchContribution {
        ShortcutTabBindingBatchContribution(
            inputs: contributions.flatMap(\.inputs),
            profileAdmissions: contributions.flatMap(\.profileAdmissions),
            residences: contributions.flatMap(\.residences)
        )
    }
}

@MainActor
struct ShortcutTabResolvedProfileTarget {
    let profileID: UUID
    let runtimeFallback: TabRuntimeFallbackProfileWitness?
}

@MainActor
final class ShortcutTabBindingBatchBuilder {
    private let runtimeAttachment: TabRuntimeAttachmentWitness
    private let windowMutations: BrowserWindowShortcutMutationOwner
    private let profiles: TabProfileTransitionService
    private let persistence: ShortcutSplitLauncherWindowPersistence
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        runtimeConnection: TabRuntimePortConnection,
        runtimeAttachment: TabRuntimeAttachmentWitness? = nil,
        windowMutations: BrowserWindowShortcutMutationOwner,
        profiles: TabProfileTransitionService,
        persistence: ShortcutSplitLauncherWindowPersistence,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.runtimeAttachment = runtimeAttachment
            ?? TabRuntimeAttachmentWitness(
                connection: runtimeConnection,
                lease: runtimeConnection.captureLease()
            )
        self.windowMutations = windowMutations
        self.profiles = profiles
        self.persistence = persistence
        self.structuralLookup = structuralLookup
    }

    func isCurrent() -> Bool {
        runtimeAttachment.isCurrent()
    }

    func matches(_ attachment: TabRuntimeAttachmentWitness) -> Bool {
        runtimeAttachment.matches(attachment)
    }

    func windowState(for windowID: UUID) -> BrowserWindowState? {
        runtimeAttachment.lease.windowState(for: windowID)
    }

    func resolvedProfileTarget(
        _ candidate: UUID?
    ) -> ShortcutTabResolvedProfileTarget? {
        if let candidate {
            return ShortcutTabResolvedProfileTarget(
                profileID: candidate,
                runtimeFallback: nil
            )
        }
        guard let fallback = runtimeAttachment.lease
            .captureFallbackProfileWitness() else {
            return nil
        }
        return ShortcutTabResolvedProfileTarget(
            profileID: fallback.profileID,
            runtimeFallback: fallback
        )
    }

    func prepareProfileAdmission(
        tab: Tab,
        target: ShortcutSplitLauncherBindingTarget
    ) -> ShortcutTabProfileAssignmentAdmission? {
        guard isCurrent() else { return nil }
        return profiles.prepareShortcutAssignment(
            tab: tab,
            desiredProfileID: target.desiredProfileID,
            resolvedProfileID: target.resolvedProfileID,
            runtimeFallback: target.runtimeFallback,
            using: runtimeAttachment.lease
        )
    }

    func makeTransaction(
        from contribution: ShortcutTabBindingBatchContribution,
        windows windowContribution: ShortcutTabBindingWindowContribution = .empty
    ) -> (
        ShortcutTabBindingModelTransaction,
        ShortcutTabProfileAssignmentBatch
    )? {
        guard let composed = makeComposedTransaction(
            from: contribution,
            windows: [windowContribution]
        ) else { return nil }
        return (composed.model, composed.profiles)
    }

    func makeComposedTransaction(
        from contribution: ShortcutTabBindingBatchContribution,
        windows windowContributions: [ShortcutTabBindingWindowContribution]
    ) -> (
        model: ShortcutTabBindingModelTransaction,
        profiles: ShortcutTabProfileAssignmentBatch,
        targetWindowStates: [UUID: BrowserWindowShortcutMutationState]
    )? {
        let plannedTabs = contribution.inputs.flatMap(\.plans).map(\.tab)
        let admittedTabs = contribution.profileAdmissions.map(
            \.assignment.tab
        )
        guard plannedTabs.count == admittedTabs.count,
              Set(plannedTabs.map(ObjectIdentifier.init)).count
                == plannedTabs.count,
              zip(plannedTabs, admittedTabs).allSatisfy({
                  ObjectIdentifier($0.0) == ObjectIdentifier($0.1)
              }),
              isCurrent(),
              let windowBatch = ShortcutTabBindingWindowBatchPreparer.prepare(
                    inputs: contribution.inputs,
                    contributions: windowContributions,
                    using: windowMutations
                ) else { return nil }
        let model = ShortcutTabBindingModelTransaction(
                  inputs: contribution.inputs,
                  residences: ShortcutTabBindingResidenceCompositeTransaction(
                      contribution.residences
                  ),
                  windowBatch: windowBatch,
                  persistence: persistence,
                  runtimeConnection: runtimeAttachment.connection,
                  runtimeLease: runtimeAttachment.lease,
                  profiles: profiles,
                  structuralLookup: structuralLookup
              )
        return (
            model: model,
            profiles: ShortcutTabProfileAssignmentBatch(
                connection: runtimeAttachment.connection,
                lease: runtimeAttachment.lease,
                admissions: contribution.profileAdmissions
            ),
            targetWindowStates: windowBatch.targetStates
        )
    }
}
