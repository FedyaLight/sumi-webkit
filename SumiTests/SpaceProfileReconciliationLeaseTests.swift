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
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
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
                XCTAssertTrue(tabManager.runtimePortsAttachmentOwner.detach())
                replacementOutcome = tabManager.runtimePortsAttachmentOwner
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

        let firstOutcome = tabManager.runtimePortsAttachmentOwner.attach(first)

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
}
