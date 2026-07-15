import Combine
import Foundation
import SumiWebRuntime

/// The only production boundary that mutates an existing Space profile. It
/// couples the model value to every exact live shortcut presentation page.
@MainActor
final class SpaceProfileMutationService {
    private let spaces: TabSpaceCollectionStateOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let registry: LiveShortcutTabRegistry
    private let runtimeConnection: TabRuntimePortConnection
    private let runtimeTeardown: TabRuntimeTeardownService
    private let terminalPublisher: SpaceProfilePresentationTerminalEffectPublisher
    private let changes: ObservableObjectPublisher

    init(
        spaces: TabSpaceCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner,
        registry: LiveShortcutTabRegistry,
        runtimeConnection: TabRuntimePortConnection,
        runtimeTeardown: TabRuntimeTeardownService,
        terminalPublisher: SpaceProfilePresentationTerminalEffectPublisher,
        changes: ObservableObjectPublisher
    ) {
        self.spaces = spaces
        self.pins = pins
        self.registry = registry
        self.runtimeConnection = runtimeConnection
        self.runtimeTeardown = runtimeTeardown
        self.terminalPublisher = terminalPublisher
        self.changes = changes
    }

    convenience init(tabManager: TabManager) {
        self.init(
            spaces: tabManager.spaceStateOwner,
            pins: tabManager.shortcutPinCollectionStateOwner,
            registry: tabManager.liveShortcutTabs,
            runtimeConnection: tabManager.runtimePortConnection,
            runtimeTeardown: tabManager.runtimeTeardown,
            terminalPublisher: SpaceProfilePresentationTerminalEffectPublisher(
                structuralLookup: tabManager.structuralLookupCoordinator,
                runtimeTeardown: tabManager.runtimeTeardown
            ),
            changes: tabManager.objectWillChange
        )
    }

    func transaction(
        space: Space,
        expectedProfileID: UUID?,
        targetProfileID: UUID?
    ) -> SpaceProfileMutationTransaction? {
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
              let presentation = presentationTransition(
                  spaceID: space.id,
                  expectedProfileID: expectedProfileID,
                  targetProfileID: targetProfileID
              ) else { return nil }
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

    private func presentationTransition(
        spaceID: UUID,
        expectedProfileID: UUID?,
        targetProfileID: UUID?
    ) -> SpaceProfilePresentationTransition? {
        var relocations: [SpaceProfilePresentationTransition.Relocation] = []
        var retirements: [SpaceProfilePresentationTransition.Retirement] = []
        let runtimeLease = runtimeConnection.captureLease()
        for entry in registry.entries(presentedInSpace: spaceID) {
            let expectedPage = LiveShortcutPresentationPageReceipt(
                windowID: entry.windowId,
                spaceID: spaceID,
                profileID: expectedProfileID
            )
            guard entry.presentationPage == expectedPage,
                  entry.tab.shortcutPinId == entry.pinId,
                  let pin = pins.shortcutPin(by: entry.pinId),
                  pin.role == entry.tab.shortcutPinRole else { return nil }
            switch pin.role {
            case .spacePinned:
                guard pin.spaceId == spaceID,
                      entry.tab.spaceId == spaceID else { return nil }
                relocations.append(.init(
                    entry: entry,
                    targetPage: LiveShortcutPresentationPageReceipt(
                        windowID: entry.windowId,
                        spaceID: spaceID,
                        profileID: targetProfileID
                    )
                ))
            case .essential:
                guard let profileID = pin.profileId,
                      profileID == expectedProfileID,
                      entry.tab.spaceId == nil,
                      let runtime = runtimeLease.registry,
                      let window = runtime.windowState(for: entry.windowId)
                else { return nil }
                retirements.append(.init(entry: entry, window: window))
            }
        }
        return SpaceProfilePresentationTransition(
            relocations: relocations,
            retirements: retirements,
            registry: registry,
            runtimeConnection: runtimeConnection,
            runtimeLease: runtimeLease,
            runtimeTeardown: runtimeTeardown,
            terminalPublisher: terminalPublisher
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
