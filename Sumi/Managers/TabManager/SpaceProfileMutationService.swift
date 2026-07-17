import Combine
import Foundation
import SumiWebRuntime

/// The only production boundary that mutates an existing Space profile. It
/// couples the model value to every exact live shortcut presentation page.
@MainActor
final class SpaceProfileMutationService {
    private let spaces: TabSpaceCollectionStateOwner
    private let runtimeConnection: TabRuntimePortConnection
    private let transitions: SpaceProfilePresentationTransitionFactory
    private let changes: ObservableObjectPublisher

    init(
        spaces: TabSpaceCollectionStateOwner,
        runtimeConnection: TabRuntimePortConnection,
        transitions: SpaceProfilePresentationTransitionFactory,
        changes: ObservableObjectPublisher
    ) {
        self.spaces = spaces
        self.runtimeConnection = runtimeConnection
        self.transitions = transitions
        self.changes = changes
    }

    func transaction(
        space: Space,
        expectedProfileID: UUID?,
        targetProfileID: UUID?,
        using runtimeLease: TabRuntimePortLease
    ) -> SpaceProfileMutationTransaction? {
        guard runtimeConnection.accepts(runtimeLease) else { return nil }
        let selectedSpace = spaces.currentSpace.flatMap {
            $0.id == space.id ? $0 : nil
        }
        let selectedSpaceIsExpected = selectedSpace.map {
            $0.profileId == expectedProfileID
        } ?? true
        guard expectedProfileID != targetProfileID,
              spaces.profileMutationResidenceIsExact(
                  space: space,
                  selectedSpace: selectedSpace
              ),
              space.profileId == expectedProfileID,
              selectedSpaceIsExpected,
              let presentation = transitions.make(
                  spaceID: space.id,
                  expectedProfileID: expectedProfileID,
                  targetProfileID: targetProfileID,
                  using: runtimeLease
              ), runtimeConnection.accepts(runtimeLease) else { return nil }
        return SpaceProfileMutationTransaction(
            space: space,
            selectedSpace: selectedSpace,
            expectedProfileID: expectedProfileID,
            targetProfileID: targetProfileID,
            spaces: spaces,
            presentation: presentation,
            changes: changes
        )
    }
}

/// Exact staged model mutation retained until WebView settlement.
@MainActor
final class SpaceProfileMutationTransaction {
    private enum State: Equatable { case pending, staged, terminal }

    let spaceID: UUID
    let expectedProfileID: UUID?
    let targetProfileID: UUID?
    private let space: Space
    private let selectedSpace: Space?
    private let spaces: TabSpaceCollectionStateOwner
    private let presentation: SpaceProfilePresentationTransition
    private let changes: ObservableObjectPublisher
    private var state: State = .pending

    init(
        space: Space,
        selectedSpace: Space?,
        expectedProfileID: UUID?,
        targetProfileID: UUID?,
        spaces: TabSpaceCollectionStateOwner,
        presentation: SpaceProfilePresentationTransition,
        changes: ObservableObjectPublisher
    ) {
        spaceID = space.id
        self.space = space
        self.selectedSpace = selectedSpace
        self.expectedProfileID = expectedProfileID
        self.targetProfileID = targetProfileID
        self.spaces = spaces
        self.presentation = presentation
        self.changes = changes
    }

    func isCurrentPending() -> Bool {
        state == .pending && currentResidenceHasProfile(expectedProfileID)
    }

    func prepare() -> Bool {
        guard isCurrentPending() else { return false }
        return presentation.canStage() || presentation.prepare()
    }

    var requiresRetirementBatch: Bool {
        presentation.requiresRetirementBatch
    }

    func beginRetirement(
        modelTransaction: WebViewRetirementModelTransactionReceipt
    ) -> SpaceProfileRetirementBeginOutcome {
        presentation.beginRetirement(modelTransaction: modelTransaction)
    }

    func settleCompensatedRetirementModelConflict(
        _ batch: TabRuntimeRetirementBatch
    ) -> SpaceProfileRetirementModelConflictOutcome {
        presentation.settleCompensatedModelConflict(batch)
    }

    func settleRetainedRetirementModelConflict(
        _ batch: TabRuntimeRetirementBatch
    ) -> SpaceProfileRetirementModelConflictOutcome {
        presentation.settleRetainedModelConflict(batch)
    }

    @discardableResult
    func stageModel() -> Bool {
        guard prepare() else { return false }
        guard isCurrentPending(), presentation.canStage() else { return false }
        guard spaces.assignProfileWithoutObservation(
            space: space,
            selectedSpace: selectedSpace,
            profileId: targetProfileID
        ) else { return false }
        guard presentation.stageModel() else {
            _ = spaces.assignProfileWithoutObservation(
                space: space,
                selectedSpace: selectedSpace,
                profileId: expectedProfileID
            )
            return false
        }
        state = .staged
        return true
    }

    func publishStagedModel() {
        precondition(state == .staged)
        publishProfileMutation()
        presentation.publishStagedModel()
    }

    func stagedModelIsExact() -> Bool {
        state == .staged
            && currentResidenceHasProfile(targetProfileID)
            && presentation.stagedModelIsExact()
    }

    func canCommitRetirement() -> Bool {
        stagedModelIsExact() && presentation.canCommitRetirement()
    }

    func claimTerminalModel() -> Bool {
        state == .staged && presentation.claimTerminalModel()
    }

    func commitSilentTerminalModel() -> Bool {
        state == .staged && presentation.commitSilentTerminalModel()
    }

    func cancelTerminalModelClaim() {
        presentation.cancelTerminalModelClaim()
    }

    func commitRetirement() -> SpaceProfileRetirementCommitOutcome {
        guard state == .staged,
              currentResidenceHasProfile(targetProfileID) else {
            return .conflict
        }
        return presentation.commitRetirement()
    }

    func canFinishModel() -> Bool {
        state == .staged
            && witnessesHaveProfile(targetProfileID)
            && presentation.canFinishModel()
    }

    func finishPrevalidatedModel() {
        precondition(canFinishModel())
        presentation.finishPrevalidatedModel()
        state = .terminal
    }

    func claimedModelIsExact() -> Bool {
        state == .terminal
            && currentResidenceHasProfile(targetProfileID)
            && presentation.claimedModelIsExact()
    }

    func settleTerminalModelAfterDrain() {
        presentation.settleTerminalModelAfterDrain()
        state = .terminal
    }

    func publishTerminalEffects(
        _ receipt: SpaceProfilePresentationTerminalEffectReceipt
    ) {
        precondition(state == .terminal)
        presentation.publishTerminalEffects(receipt)
    }

    func settleTerminalDrain(
        _ receipt: SpaceProfilePresentationTerminalEffectReceipt
    ) {
        precondition(state == .terminal)
        presentation.settleTerminalDrain(receipt)
    }

    func canRollbackModel() -> Bool {
        state == .staged
            && witnessesHaveProfile(targetProfileID)
            && presentation.canRollbackModel()
    }

    @discardableResult
    func rollbackModel() -> Bool {
        guard canRollbackModel(), presentation.rollbackModel() else {
            return false
        }
        guard spaces.assignProfileWithoutObservation(
            space: space,
            selectedSpace: selectedSpace,
            profileId: expectedProfileID
        ) else { return false }
        state = .terminal
        return true
    }

    func publishRolledBackModel() {
        precondition(state == .terminal)
        publishProfileMutation()
        presentation.publishRolledBackModel()
    }

    func rollbackRetirement() -> TabRuntimeRetirementRollbackOutcome? {
        presentation.rollbackRetirement()
    }

    private func publishProfileMutation() {
        guard spaces.publishProfileMutation(
            space: space,
            selectedSpace: selectedSpace
        ) else { return }
        changes.send()
    }

    private func currentResidenceHasProfile(_ profileID: UUID?) -> Bool {
        spaces.profileMutationResidenceIsExact(
            space: space,
            selectedSpace: selectedSpace
        ) && witnessesHaveProfile(profileID)
    }

    private func witnessesHaveProfile(_ profileID: UUID?) -> Bool {
        guard space.profileId == profileID else { return false }
        guard let selectedSpace, selectedSpace !== space else { return true }
        return selectedSpace.profileId == profileID
    }
}
