import Combine
import SumiDomain
import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class DisplayedTabShortcutBindingAggregateTransactionTests:
    XCTestCase {
    func testBindingRollbackFailureStillRestoresOtherParticipants() throws {
        let failingBinding = FailingRollbackBindingTransaction()
        let harness = try makeAggregate(binding: failingBinding)

        try harness.aggregate.stage()
        XCTAssertThrowsError(try harness.aggregate.rollback())

        XCTAssertTrue(harness.aggregate.retainsModelAfterFailedStage())
        XCTAssertEqual(
            harness.window.unpublishedShortcutMutationState,
            harness.sourceWindow
        )
        XCTAssertTrue(
            harness.tabManager.regularTabCollectionOwner.containsIdentical(
                harness.source,
                in: harness.space.id
            )
        )
        let next = try XCTUnwrap(
            harness.tabManager.structuralCollectionMutationOwner
                .prepareAggregate()
        )
        XCTAssertTrue(next.rollback())
    }

    func testClaimedTerminalDrainAbandonsWithoutPublishingCallbacks() throws {
        let binding = TerminalDrainBindingTransaction()
        let harness = try makeAggregate(binding: binding)
        var structuralEvents = 0
        let structuralCancellable = harness.tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        let counters = harness.counters
        withObservationTracking {
            _ = harness.window.currentTabId
            _ = harness.window.currentShortcutPinId
            _ = harness.window.splitSelection
        } onChange: {
            MainActor.assumeIsolated {
                counters.windowPublications += 1
            }
        }

        try harness.aggregate.stage()
        XCTAssertEqual(harness.aggregate.claimTerminalModel(), .sealed)
        XCTAssertTrue(harness.aggregate.canSettleTerminalDrain())
        XCTAssertTrue(harness.aggregate.settleTerminalDrain())
        XCTAssertTrue(harness.aggregate.settleTerminalDrain())

        XCTAssertEqual(structuralEvents, 0)
        XCTAssertEqual(harness.counters.windowPublications, 0)
        XCTAssertEqual(harness.counters.windowPersistence, 0)
        XCTAssertEqual(
            harness.window.unpublishedShortcutMutationState
                .currentShortcutPinId,
            harness.sourceWindow.currentShortcutPinId
        )
        XCTAssertFalse(
            harness.tabManager.regularTabCollectionOwner.containsIdentical(
                harness.source,
                in: harness.space.id
            )
        )
        _ = structuralCancellable
    }

    func testRolledBackTerminalDrainSkipsRollbackPublication() throws {
        let binding = RolledBackTerminalDrainBindingTransaction()
        let harness = try makeAggregate(binding: binding)
        var structuralEvents = 0
        let structuralCancellable = harness.tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        let counters = harness.counters
        withObservationTracking {
            _ = harness.window.currentTabId
            _ = harness.window.currentShortcutPinId
            _ = harness.window.splitSelection
        } onChange: {
            MainActor.assumeIsolated {
                counters.windowPublications += 1
            }
        }

        try harness.aggregate.stage()
        try harness.aggregate.rollback()
        XCTAssertTrue(harness.aggregate.canSettleTerminalDrain())
        XCTAssertTrue(harness.aggregate.settleTerminalDrain())

        XCTAssertEqual(binding.publishRollbackCount, 0)
        XCTAssertEqual(structuralEvents, 0)
        XCTAssertEqual(harness.counters.windowPublications, 0)
        XCTAssertEqual(harness.counters.windowPersistence, 0)
        XCTAssertEqual(
            harness.window.unpublishedShortcutMutationState,
            harness.sourceWindow
        )
        XCTAssertTrue(
            harness.tabManager.regularTabCollectionOwner.containsIdentical(
                harness.source,
                in: harness.space.id
            )
        )
        _ = structuralCancellable
    }

    private func makeAggregate(
        binding bindingModel: any ShortcutSplitLauncherBindingModelTransaction
    ) throws -> AggregateHarness {
        let window = BrowserWindowState()
        let counters = Counters()
        let profile = Profile(name: "Profile")
        let tabManager = BrowserManager()
        tabManager.runtimePortConnection.attach(TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            persistWindowSession: { _ in
                counters.windowPersistence += 1
            }
        ))
        tabManager.windowRegistry.register(window)
        let space = try XCTUnwrap(tabManager.sidebarSpaceLifecycle.createSpace(
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profile.id
        ))
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://aggregate-rollback.example",
            in: space,
            activate: false
        )
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: source.url,
            title: source.name
        )
        let sourceWindow = window.unpublishedShortcutMutationState
        let profileAdmission = try XCTUnwrap(
            tabManager.tabProfileTransitions.prepareShortcutAssignment(
                tab: source,
                desiredProfileID: nil,
                resolvedProfileID: profile.id,
                runtimeFallback: nil,
                using: tabManager.runtimePortConnection.captureLease()
            )
        )
        let bindingFixture = try makeDisplayedBinding(
            tab: source,
            pin: pin,
            window: window,
            space: space,
            profileID: profile.id,
            registry: tabManager.liveShortcutTabs,
            membership: tabManager.tabCollectionMembershipOwner,
            profile: profileAdmission
        )
        let membershipWitness = try XCTUnwrap(
            DisplayedTabShortcutMembershipWitness(
                membership: tabManager.tabCollectionMembershipOwner,
                source: source,
                freshTabs: []
            )
        )
        let runtime = DisplayedTabShortcutRuntimeTransaction(
            windows: .empty,
            sourceModel: DisplayedTabShortcutSourceModelTransaction(
                binding: bindingFixture.binding,
                membershipWitness: membershipWitness,
                containerRemoval: ShortcutContainerRemovalOwner(
                    pins: tabManager.shortcutPinCollectionStateOwner,
                    structuralMutations: tabManager
                        .structuralCollectionMutationOwner,
                    regularTabs: tabManager.regularTabCollectionOwner,
                    spaces: tabManager.spaceStateOwner
                ),
                regularTabs: tabManager.regularTabCollectionOwner
            ),
            structuralLookup: tabManager.structuralLookupCoordinator,
            runtimeAttachment: TabRuntimeAttachmentWitness(
                connection: tabManager.runtimePortConnection,
                lease: tabManager.runtimePortConnection.captureLease()
            )
        )
        let aggregate = DisplayedTabShortcutBindingAggregateTransaction(
            binding: DisplayedResidenceBindingTransaction(
                base: bindingModel,
                residences: bindingFixture.residences
            ),
            runtime: runtime,
            durable: RegularTabShortcutDurableStructureParticipant(
                mutations: tabManager.structuralCollectionMutationOwner,
                topology: nil
            ),
            terminal: RegularTabShortcutTerminalEffects(
                persistence: tabManager.structuralPersistence,
                folders: tabManager.folderOpenState,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: space.id,
                    folderId: nil,
                    index: 0,
                    opensFolder: false
                )
            ),
            structuralLookup: tabManager.structuralLookupCoordinator
        )
        return AggregateHarness(
            aggregate: aggregate,
            tabManager: tabManager,
            window: window,
            space: space,
            source: source,
            pin: pin,
            sourceWindow: sourceWindow,
            counters: counters
        )
    }

    private func makeDisplayedBinding(
        tab: Tab,
        pin: ShortcutPin,
        window: BrowserWindowState,
        space: Space,
        profileID: UUID,
        registry: LiveShortcutTabRegistry,
        membership: TabCollectionMembershipOwner,
        profile: ShortcutTabProfileAssignmentAdmission
    ) throws -> DisplayedBindingFixture {
        let residencePlan = try XCTUnwrap(
            registry.staging.prepareRegistration(
                tab,
                for: pin.id,
                in: window.id,
                presentationPage: LiveShortcutPresentationPageReceipt(
                    windowID: window.id,
                    spaceID: space.id,
                    profileID: profileID
                )
            )
        )
        let residences = LiveShortcutPresentationResidenceTransaction(
            pin: pin,
            admission: LiveShortcutPresentationRefreshAdmission(
                pin: pin,
                changes: []
            ),
            staging: registry.staging,
            plans: [residencePlan]
        )
        let preflight = DisplayedTabShortcutBindingPreflight(
            candidate: pin,
            registry: registry,
            membership: membership,
            profile: profile,
            planned: [],
            sourceTab: tab,
            sourceSpaceID: tab.spaceId,
            liveTabsByWindowID: [:],
            freshTabs: []
        )
        let binding = PreparedDisplayedTabShortcutBinding(
            contribution: ShortcutTabBindingBatchContribution(
                inputs: [],
                profileAdmissions: [],
                residences: []
            ),
            preflight: preflight,
            residences: residences,
            presentationContribution: try XCTUnwrap(
                DisplayedShortcutResidenceContribution(
                    pin: pin,
                    registry: registry,
                    membership: membership,
                    residences: residences,
                    entries: [.init(
                        window: window,
                        pinID: pin.id,
                        tab: tab,
                        page: LiveShortcutPresentationPageReceipt(
                            windowID: window.id,
                            spaceID: space.id,
                            profileID: profileID
                        ),
                        source: ShortcutSplitLauncherTabReceipt(tab),
                        target: ShortcutBindingIdentity(
                            pinId: pin.id,
                            role: pin.role,
                            spaceId: space.id
                        ),
                        targetFolderID: nil,
                        preparedLookup: .exactSource
                    )]
                )
            ),
            terminalIdentitiesByWindowID: [:]
        )
        return DisplayedBindingFixture(
            binding: binding,
            residences: residences
        )
    }

    private struct DisplayedBindingFixture {
        let binding: PreparedDisplayedTabShortcutBinding
        let residences: LiveShortcutPresentationResidenceTransaction
    }

    private struct AggregateHarness {
        let aggregate: DisplayedTabShortcutBindingAggregateTransaction
        let tabManager: BrowserManager
        let window: BrowserWindowState
        let space: Space
        let source: Tab
        let pin: ShortcutPin
        let sourceWindow: BrowserWindowShortcutMutationState
        let counters: Counters
    }

    @MainActor
    private final class Counters {
        var windowPersistence = 0
        var windowPublications = 0
    }
}

@MainActor
private final class DisplayedResidenceBindingTransaction:
    ShortcutSplitLauncherBindingModelTransaction {
    private enum State { case prepared, staged, rolledBack, terminal }

    private let base: any ShortcutSplitLauncherBindingModelTransaction
    private let residences: LiveShortcutPresentationResidenceTransaction
    private var state = State.prepared

    init(
        base: any ShortcutSplitLauncherBindingModelTransaction,
        residences: LiveShortcutPresentationResidenceTransaction
    ) {
        self.base = base
        self.residences = residences
    }

    var exactBindingTabs: [Tab] { base.exactBindingTabs }
    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return base.validateForStaging() && residences.validateForStaging()
    }
    func stageCatalog() -> Bool { base.stageCatalog() }
    func prepareStructuralRollbackAfterCatalogStage() -> Bool {
        base.prepareStructuralRollbackAfterCatalogStage()
    }
    func stageBinding() throws {
        try base.stageBinding()
        guard residences.stage() else { throw Failure.staleResidence }
        state = .staged
    }
    func retainsModelAfterFailedStage() -> Bool {
        base.retainsModelAfterFailedStage()
    }
    func stagedModelIsExact() -> Bool {
        base.stagedModelIsExact() && residences.stagedModelIsExact()
    }
    func canClaimTerminalModel() -> Bool {
        base.canClaimTerminalModel() && residences.stagedModelIsExact()
    }
    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        base.claimTerminalModel()
    }
    func claimedModelIsExact() -> Bool {
        base.claimedModelIsExact() && residences.stagedModelIsExact()
    }
    func publishModelCommit(beforeWindowPublication: () -> Void) {
        base.publishModelCommit {
            precondition(residences.publish())
            beforeWindowPublication()
        }
        state = .terminal
    }
    func publishTerminalEffects() { base.publishTerminalEffects() }
    func cancelPrepared() -> Bool {
        let residencesCancelled = residences.cancelPrepared()
        let cancelled = base.cancelPrepared() && residencesCancelled
        if cancelled { state = .terminal }
        return cancelled
    }
    func rollbackBinding() throws {
        guard residences.rollback() else { throw Failure.staleResidence }
        try base.rollbackBinding()
        state = .rolledBack
    }
    func confirmStructuralRollback() -> Bool {
        base.confirmStructuralRollback()
    }
    func publishRollback() { base.publishRollback() }
    func canSettleTerminalDrain() -> Bool {
        guard base.canSettleTerminalDrain() else { return false }
        if case .rolledBack = state { return true }
        return residences.canAbandonForTerminalDrain()
    }
    func settleTerminalDrain() -> Bool {
        guard canSettleTerminalDrain(),
              base.settleTerminalDrain() else { return false }
        if case .rolledBack = state {
            state = .terminal
            return true
        }
        residences.abandonForTerminalDrain()
        state = .terminal
        return true
    }

    private enum Failure: Error { case staleResidence }
}

@MainActor
private final class FailingRollbackBindingTransaction:
    ShortcutSplitLauncherBindingModelTransaction {
    private enum State { case prepared, catalogStaged, staged, conflicted }

    private var state = State.prepared

    var exactBindingTabs: [Tab] { [] }

    func validateForStaging() -> Bool {
        if case .prepared = state { return true }
        return false
    }

    func stageCatalog() -> Bool {
        state = .catalogStaged
        return true
    }

    func prepareStructuralRollbackAfterCatalogStage() -> Bool { false }

    func stageBinding() throws { state = .staged }

    func retainsModelAfterFailedStage() -> Bool {
        if case .conflicted = state { return true }
        return false
    }

    func stagedModelIsExact() -> Bool {
        if case .staged = state { return true }
        return false
    }

    func canClaimTerminalModel() -> Bool { stagedModelIsExact() }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        .terminallyDrained
    }

    func claimedModelIsExact() -> Bool { false }
    func publishModelCommit(beforeWindowPublication: () -> Void) {
        beforeWindowPublication()
    }
    func publishTerminalEffects() {}

    func cancelPrepared() -> Bool { false }

    func rollbackBinding() throws {
        state = .conflicted
        throw Failure.expected
    }

    func confirmStructuralRollback() -> Bool { false }

    func publishRollback() {}

    func canSettleTerminalDrain() -> Bool { false }

    func settleTerminalDrain() -> Bool { false }

    private enum Failure: Error { case expected }
}

@MainActor
private final class TerminalDrainBindingTransaction:
    ShortcutSplitLauncherBindingModelTransaction {
    private enum State { case prepared, catalogStaged, staged, claimed, terminal }

    private var state = State.prepared

    var exactBindingTabs: [Tab] { [] }

    func validateForStaging() -> Bool {
        if case .prepared = state { return true }
        return false
    }

    func stageCatalog() -> Bool {
        state = .catalogStaged
        return true
    }

    func prepareStructuralRollbackAfterCatalogStage() -> Bool { false }

    func stageBinding() throws { state = .staged }

    func retainsModelAfterFailedStage() -> Bool { false }

    func stagedModelIsExact() -> Bool {
        if case .staged = state { return true }
        return false
    }

    func canClaimTerminalModel() -> Bool { stagedModelIsExact() }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        guard canClaimTerminalModel() else { return .terminallyDrained }
        state = .claimed
        return .sealed
    }

    func claimedModelIsExact() -> Bool {
        if case .claimed = state { return true }
        return false
    }

    func publishModelCommit(beforeWindowPublication: () -> Void) {
        beforeWindowPublication()
    }
    func publishTerminalEffects() { state = .terminal }

    func cancelPrepared() -> Bool { false }

    func rollbackBinding() throws {}

    func confirmStructuralRollback() -> Bool { false }

    func publishRollback() {}

    func canSettleTerminalDrain() -> Bool {
        switch state {
        case .staged, .claimed, .terminal:
            return true
        case .prepared, .catalogStaged:
            return false
        }
    }

    func settleTerminalDrain() -> Bool {
        guard canSettleTerminalDrain() else { return false }
        state = .terminal
        return true
    }
}

@MainActor
private final class RolledBackTerminalDrainBindingTransaction:
    ShortcutSplitLauncherBindingModelTransaction {
    private enum State {
        case prepared, catalogStaged, staged, awaitingStructuralRollback
        case rolledBack, terminal
    }

    private var state = State.prepared
    private(set) var publishRollbackCount = 0

    var exactBindingTabs: [Tab] { [] }

    func validateForStaging() -> Bool {
        if case .prepared = state { return true }
        return false
    }

    func stageCatalog() -> Bool {
        state = .catalogStaged
        return true
    }

    func prepareStructuralRollbackAfterCatalogStage() -> Bool { false }

    func stageBinding() throws { state = .staged }

    func retainsModelAfterFailedStage() -> Bool { false }

    func stagedModelIsExact() -> Bool {
        if case .staged = state { return true }
        return false
    }

    func canClaimTerminalModel() -> Bool { stagedModelIsExact() }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        .terminallyDrained
    }

    func claimedModelIsExact() -> Bool { false }
    func publishModelCommit(beforeWindowPublication: () -> Void) {
        beforeWindowPublication()
    }
    func publishTerminalEffects() {}

    func cancelPrepared() -> Bool { false }

    func rollbackBinding() throws { state = .awaitingStructuralRollback }

    func confirmStructuralRollback() -> Bool {
        guard case .awaitingStructuralRollback = state else { return false }
        state = .rolledBack
        return true
    }

    func publishRollback() { publishRollbackCount += 1 }

    func canSettleTerminalDrain() -> Bool {
        switch state {
        case .rolledBack, .terminal:
            return true
        case .prepared, .catalogStaged, .staged, .awaitingStructuralRollback:
            return false
        }
    }

    func settleTerminalDrain() -> Bool {
        guard canSettleTerminalDrain() else { return false }
        state = .terminal
        return true
    }
}
