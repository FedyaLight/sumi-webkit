import Foundation
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class DisplayedShortcutResidenceContributionTests: XCTestCase {
    func testPresentationSettlementNeverOwnsContributedInsertionResidence()
        throws {
        for settlement in [Settlement.rollback, .forfeit] {
            let fixture = try makeFixture()

            try fixture.stagePresentationThenBinding()
            XCTAssertTrue(fixture.presentation.acceptBoundIdentity())
            XCTAssertTrue(
                fixture.tabManager.tabCollectionMembershipOwner
                    .lookupContainsNone(of: [fixture.contributedTab.id])
            )
            XCTAssertTrue(fixture.presentation.canPublish())

            settlement.apply(to: fixture.presentation)

            fixture.assertBindingStillOwnsExactResidence()
            try fixture.bindingModel.rollback()
            fixture.assertContributedResidenceRemoved()
        }
    }

    func testContributedInsertionRejectsSameIDForeignLookupWithoutDeletingIt()
        throws {
        let fixture = try makeFixture()
        try fixture.stagePresentationThenBinding()
        let foreign = fixture.tabManager.tabFactory.makeTab(
            id: fixture.contributedTab.id,
            url: URL(string: "https://foreign-contributed-residence.example")!,
            loadsCachedFaviconOnInit: false
        )
        fixture.tabManager.tabCollectionMembershipOwner.attach(foreign)

        XCTAssertFalse(fixture.presentation.acceptBoundIdentity())
        XCTAssertFalse(fixture.presentation.canPublish())
        fixture.presentation.rollback()

        fixture.assertBindingStillOwnsExactResidence()
        XCTAssertIdentical(
            fixture.tabManager.tabCollectionMembershipOwner.tab(
                for: foreign.id
            ),
            foreign
        )
        try fixture.bindingModel.rollback()
        fixture.assertContributedResidenceRemoved()
        XCTAssertIdentical(
            fixture.tabManager.tabCollectionMembershipOwner.tab(
                for: foreign.id
            ),
            foreign
        )
    }

    func testSplitDropProjectionIncludesOnlyWindowsOnTheMovingMember() throws {
        let tabManager = BrowserManager()
        let caller = BrowserWindowState()
        let matching = BrowserWindowState()
        let otherMember = BrowserWindowState()
        let otherGroup = BrowserWindowState()
        let movingTabID = UUID()
        let companionTabID = UUID()
        let activatedPinID = UUID()
        let spaceID = UUID()
        let movingID = SplitMemberID.regularTab(movingTabID)
        let companionID = SplitMemberID.regularTab(companionTabID)
        let activatedID = SplitMemberID.shortcutPin(activatedPinID)
        let source = try XCTUnwrap(SplitGroup.make(
            members: [
                .regularTab(movingTabID),
                .regularTab(companionTabID),
            ],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: spaceID)
        ))
        let target = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(activatedPinID),
                .shortcutPin(UUID()),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: spaceID,
                profileId: nil,
                folderId: nil,
                index: 0
            )
        ))
        matching.splitSelection = WindowSplitSelection(
            groupID: source.id,
            activeMemberID: movingID
        )
        otherMember.splitSelection = WindowSplitSelection(
            groupID: source.id,
            activeMemberID: companionID
        )
        otherGroup.splitSelection = WindowSplitSelection(
            groupID: target.id,
            activeMemberID: activatedID
        )
        let windows = [caller, matching, otherMember, otherGroup]
        windows.forEach { XCTAssertEqual(
            tabManager.windowRegistry.register($0),
            .registered
        ) }
        let synchronizer = tabManager.splitPresentations
        let effect = SplitDropCommitEffect.resolving(
            callerWindowID: caller.id,
            sourceGroup: source,
            targetGroup: target,
            committedTargetGroupID: target.id,
            movingMemberID: movingID,
            activatedMemberID: activatedID,
            replacementGroups: [target]
        )

        let projection = try XCTUnwrap(
            synchronizer.splitDropPresentationProjection(
                effect,
                caller: caller
            )
        )

        XCTAssertEqual(
            Set(projection.requiredWindows.keys),
            Set([caller.id, matching.id])
        )
        XCTAssertIdentical(projection.requiredWindows[caller.id], caller)
        XCTAssertIdentical(projection.requiredWindows[matching.id], matching)
        XCTAssertEqual(
            Set(projection.preferredSelections.values),
            [WindowSplitSelection(
                groupID: target.id,
                activeMemberID: activatedID
            )]
        )
    }

    private func makeFixture() throws -> Fixture {
        let primary = BrowserWindowState()
        let secondary = BrowserWindowState()
        let profile = Profile(name: "Runtime")
        let windows = [primary.id: primary, secondary.id: secondary]
        let tabManager = BrowserManager(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { windows[$0] },
            windows: { windows.map { ($0.key, $0.value) } },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                primaryTrackedWindowId: { _ in primary.id }
            )
        ))
        let space = try XCTUnwrap(
            tabManager.sidebarSpaceLifecycle.createSpace(
                name: "Space",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                profileID: profile.id
            )
        )
        let source = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://contributed-residence.example/source",
            in: space,
            activate: false
        )
        for window in [primary, secondary] {
            window.currentSpaceId = space.id
            window.currentTabId = source.id
        }
        guard case .displayed(let plan) = tabManager
            .regularTabShortcutConversion.prepare(
                source,
                preferredWindowId: secondary.id
            ) else {
            throw FixtureError.notDisplayed
        }
        let authorization = try XCTUnwrap(
            TabShortcutConversionAuthorizer(
                windows: ShortcutTabWindowQuery(
                    runtimeConnection: tabManager.runtimePortConnection
                )
            ).authorize(plan, for: source)
        )
        let candidate = tabManager.shortcutPinRuntimeResolutionOwner
            .makeShortcutPin(
                from: source,
                role: .spacePinned,
                spaceId: space.id,
                index: 0
            )
        let catalog = ShortcutSplitLauncherCatalogTransaction(
            pinStore: tabManager.shortcutPinStoreOwner,
            pins: tabManager.shortcutPinCollectionStateOwner
        )
        let insertion = try XCTUnwrap(catalog.prepareInsertion(candidate, at: 0))
        let builder = ShortcutTabBindingBatchBuilder(
            runtimeConnection: tabManager.runtimePortConnection,
            runtimeAttachment: plan.runtimeAttachment,
            windowMutations: tabManager.shortcutWindowMutationOwner,
            profiles: tabManager.tabProfileTransitions,
            persistence: ShortcutSplitLauncherWindowPersistence(
                structuralLookup: tabManager.structuralLookupCoordinator
            ),
            structuralLookup: tabManager.structuralLookupCoordinator
        )
        let bindingTargets = ShortcutTabBindingTargetMutationService(
            resolution: tabManager.shortcutPinRuntimeResolutionOwner,
            profiles: tabManager.tabProfileTransitions
        )
        let bindings = ShortcutTabBindingSynchronizer(
            presentationRefreshes: tabManager.liveShortcutPresentationRefreshes,
            runtimeMutations: ShortcutTabBindingRuntimeMutation(
                registry: tabManager.liveShortcutTabs,
                targets: bindingTargets,
                runtimeConnection: tabManager.runtimePortConnection,
                windowMutations: tabManager.shortcutWindowMutationOwner,
                structuralLookup: tabManager.structuralLookupCoordinator
            ),
            targets: bindingTargets
        )
        let preflight = try XCTUnwrap(
            DisplayedTabShortcutBindingPreparer(
                registry: tabManager.liveShortcutTabs,
                membership: tabManager.tabCollectionMembershipOwner,
                resolution: tabManager.shortcutPinRuntimeResolutionOwner,
                freshTabs: ShortcutFreshTabFactory(
                    tabFactory: tabManager.tabFactory,
                    bindings: bindings
                )
            ).preflight(
                pin: insertion.insertedPin,
                authorization: authorization,
                builder: builder
            )
        )
        let binding = try XCTUnwrap(
            preflight.prepareResidences(for: insertion.insertedPin)
        )
        let contributedTab = try XCTUnwrap(
            binding.liveTabsByWindowID[secondary.id]
        )
        let presentation = try XCTUnwrap(
            WindowSplitPresentationResidencePreparer().prepare(
                source: .displayedBinding(
                    insertion.presentationPreview,
                    binding.presentationContribution
                ),
                requests: [.init(
                    pinID: insertion.insertedPin.id,
                    windowID: secondary.id,
                    presentationSpaceID: space.id
                )],
                activation: tabManager.shortcutPresentationActivation
            )
        )
        let bindingModel = try XCTUnwrap(
            builder.makeTransaction(from: binding.contribution)?.0
        )
        return Fixture(
            tabManager: tabManager,
            windowID: secondary.id,
            pinID: insertion.insertedPin.id,
            contributedTab: contributedTab,
            presentation: presentation,
            bindingModel: bindingModel
        )
    }
}

@MainActor
private struct Fixture {
    let tabManager: BrowserManager
    let windowID: UUID
    let pinID: UUID
    let contributedTab: Tab
    let presentation: WindowSplitPresentationResidenceTransaction
    let bindingModel: ShortcutTabBindingModelTransaction

    func stagePresentationThenBinding() throws {
        XCTAssertNil(tabManager.liveShortcutTabs.tab(for: pinID, in: windowID))
        XCTAssertTrue(
            tabManager.tabCollectionMembershipOwner.lookupContainsNone(
                of: [contributedTab.id]
            )
        )

        XCTAssertTrue(presentation.stagePrepared())

        XCTAssertNil(tabManager.liveShortcutTabs.tab(for: pinID, in: windowID))
        XCTAssertTrue(
            tabManager.tabCollectionMembershipOwner.lookupContainsNone(
                of: [contributedTab.id]
            )
        )
        try bindingModel.stage()
        XCTAssertTrue(bindingModel.stagedModelIsExact())
        assertBindingStillOwnsExactResidence()
    }

    func assertBindingStillOwnsExactResidence() {
        let entry = tabManager.liveShortcutTabs.entry(containing: contributedTab)
        XCTAssertEqual(entry?.windowId, windowID)
        XCTAssertEqual(entry?.pinId, pinID)
        XCTAssertIdentical(entry?.tab, contributedTab)
    }

    func assertContributedResidenceRemoved() {
        XCTAssertNil(tabManager.liveShortcutTabs.entry(containing: contributedTab))
        XCTAssertNil(tabManager.liveShortcutTabs.tab(for: pinID, in: windowID))
    }
}

@MainActor
private enum Settlement {
    case rollback, forfeit

    func apply(to transaction: WindowSplitPresentationResidenceTransaction) {
        switch self {
        case .rollback: transaction.rollback()
        case .forfeit: transaction.forfeitPreservingCurrent()
        }
    }
}

private enum FixtureError: Error {
    case notDisplayed
}
