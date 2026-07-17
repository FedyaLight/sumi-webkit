import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class SpaceProfileReconciliationLeaseTests: XCTestCase {
    func testProfileQueryReentryCannotSwitchReconciliationRuntime() throws {
        let firstProfileID = UUID()
        let replacementProfileID = UUID()
        let firstProfile = Profile(id: firstProfileID, name: "First")
        let replacementProfile = Profile(
            id: replacementProfileID,
            name: "Replacement"
        )
        let tabManager = BrowserManager()
        tabManager.tabRuntimeLifecycle.shutdown()
        let attachment = makeRuntimeAttachment(for: tabManager)
        let space = Space(name: "Current", profileId: nil)
        tabManager.spaceStateOwner.replaceSpaces([space])

        var replacementTransitionCount = 0
        let replacementTransitions = TestTabWebViewProfileTransitionParticipant(
            executeTab: { tab, _, intent, _ in
                tab.profileAssignment.commit(intent) ? .committed : .stale
            },
            executeSpace: { _, _, _, model, settlement in
                replacementTransitionCount += 1
                guard model.validateForStaging() else {
                    settlement(.rejected(.stale))
                    return .stale
                }
                let result = ProfileTransitionModelOnlySettlement.execute(
                    .transaction(model)
                )
                settlement(result.settlement)
                return result.tabExecution
            },
            executePrepared: { _, _, _ in .rejectedUnstaged(.failed) }
        )
        let replacement = TestRuntimePorts.make(
            currentProfileId: { replacementProfileID },
            defaultProfileId: { replacementProfileID },
            profile: {
                $0 == replacementProfileID ? replacementProfile : nil
            },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                profileTransitions: replacementTransitions
            )
        )

        var didReenter = false
        var replacementOutcome: TabRuntimePortsAttachmentOwner.Outcome?
        var firstProfileLookupCount = 0
        var firstTransitionCount = 0
        let firstTransitions = TestTabWebViewProfileTransitionParticipant(
            executeTab: { tab, _, intent, _ in
                tab.profileAssignment.commit(intent) ? .committed : .stale
            },
            executeSpace: { _, _, _, _, _ in
                firstTransitionCount += 1
                return .failed
            },
            executePrepared: { _, _, _ in .rejectedUnstaged(.failed) }
        )
        let first = TestRuntimePorts.make(
            currentProfileId: { firstProfileID },
            defaultProfileId: { firstProfileID },
            profileExists: { profileID in
                guard didReenter == false else {
                    return profileID == firstProfileID
                }
                didReenter = true
                XCTAssertTrue(attachment.detach())
                replacementOutcome = attachment
                    .attach(replacement)
                return profileID == firstProfileID
            },
            profile: { profileID in
                firstProfileLookupCount += 1
                return profileID == firstProfileID ? firstProfile : nil
            },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                profileTransitions: firstTransitions
            )
        )

        let firstOutcome = attachment.attach(first)

        XCTAssertEqual(firstOutcome, .superseded)
        XCTAssertEqual(replacementOutcome, .attached)
        XCTAssertEqual(firstProfileLookupCount, 0)
        XCTAssertEqual(firstTransitionCount, 0)
        XCTAssertEqual(replacementTransitionCount, 1)
        XCTAssertEqual(space.profileId, replacementProfileID)
        XCTAssertIdentical(
            tabManager.runtimePortConnection.current?.profile(
                with: replacementProfileID
            ),
            replacementProfile
        )
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    private func makeRuntimeAttachment(
        for browser: BrowserManager
    ) -> TabRuntimePortsAttachmentOwner {
        let runtimeTeardown = TabRuntimeTeardownService(
            persistence: browser.structuralPersistence,
            membership: browser.tabCollectionMembershipOwner,
            webViewSessions: browser.webViewSessions
        )
        let profileGraph = SpaceProfileTransitionService.compose(
            spaces: browser.spaceStateOwner,
            pins: browser.shortcutPinCollectionStateOwner,
            registry: browser.liveShortcutTabs,
            runtimeConnection: browser.runtimePortConnection,
            runtimeTeardown: runtimeTeardown,
            structuralLookup: browser.structuralLookupCoordinator,
            membership: browser.tabCollectionMembershipOwner,
            persistence: browser.structuralPersistence,
            pendingInheritance: PendingTabProfileInheritance(),
            changes: browser.objectWillChange
        )
        let deferredWork = TabRuntimeAttachmentDeferredWorkOwner(
            connection: browser.runtimePortConnection,
            spaceProfiles: SpaceProfileReconciliationService(
                spaces: browser.spaceStateOwner,
                runtimeConnection: browser.runtimePortConnection,
                spaceTransitions: profileGraph.service,
                transitionLifecycle: profileGraph.lifecycle
            ),
            spaceAvailability: profileGraph.availability,
            pendingPins: PendingShortcutPinAdopter(
                pins: browser.shortcutPinCollectionStateOwner,
                structuralMutations: browser.structuralCollectionMutationOwner,
                profileReferenceAdmission: browser.profileReferenceAdmission
            )
        )
        return TabRuntimePortsAttachmentOwner(
            connection: browser.runtimePortConnection,
            bootstrap: TabRuntimeAttachmentBootstrap(
                connection: browser.runtimePortConnection,
                membership: browser.tabCollectionMembershipOwner,
                runtimePreparation: TabRuntimePreparationOwner(
                    runtimeConnection: browser.runtimePortConnection
                ),
                selection: browser.tabStateStore.selection
            ),
            settlement: TabRuntimeAttachmentSettlement(
                connection: browser.runtimePortConnection,
                spaces: browser.spaceStateOwner,
                deferredWork: deferredWork,
                restoreStarter: nil
            )
        )
    }
}
