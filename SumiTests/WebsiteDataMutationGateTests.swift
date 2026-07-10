import XCTest

@testable import Sumi

@MainActor
final class WebsiteDataMutationGateTests: XCTestCase {
    func testExclusiveLeaseBlocksOnlyTargetProfilesAndHandsOffInOrder() async throws {
        let gate = WebsiteDataMutationGate()
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let acquiredFirstLease = await gate.acquire(profileIDs: [firstProfileID])
        let firstLease = try XCTUnwrap(acquiredFirstLease)

        XCTAssertTrue(gate.blocksOrdinaryRuntimeAdmission(for: firstProfileID))
        XCTAssertFalse(gate.blocksOrdinaryRuntimeAdmission(for: secondProfileID))

        var secondLease: WebsiteDataMutationGate.Lease?
        let waiter = Task { @MainActor in
            secondLease = await gate.acquire(profileIDs: [secondProfileID])
        }
        await Task.yield()
        XCTAssertNil(secondLease)

        gate.release(firstLease)
        await waiter.value
        let resolvedSecondLease = try XCTUnwrap(secondLease)
        XCTAssertFalse(gate.blocksOrdinaryRuntimeAdmission(for: firstProfileID))
        XCTAssertTrue(gate.blocksOrdinaryRuntimeAdmission(for: secondProfileID))
        gate.release(resolvedSecondLease)
    }

    func testCancelledWaiterDoesNotAcquireAfterCurrentLeaseReleases() async throws {
        let gate = WebsiteDataMutationGate()
        let acquiredFirstLease = await gate.acquire(profileIDs: [UUID()])
        let firstLease = try XCTUnwrap(acquiredFirstLease)
        let waiter = Task { @MainActor in
            await gate.acquire(profileIDs: [UUID()])
        }
        await Task.yield()
        waiter.cancel()
        let cancelledResult = await waiter.value
        XCTAssertNil(cancelledResult)

        gate.release(firstLease)
        let replacement = await gate.acquire(profileIDs: [UUID()])
        XCTAssertNotNil(replacement)
        if let replacement {
            gate.release(replacement)
        }
    }

    func testDeferredAdmissionReplaysOnlyLatestWorkForExactSlot() async throws {
        let gate = WebsiteDataMutationGate()
        let profileID = UUID()
        let tabID = UUID()
        let webViewID = ObjectIdentifier(NSObject())
        let acquiredLease = await gate.acquire(profileIDs: [profileID])
        let lease = try XCTUnwrap(acquiredLease)
        var replayed: [Int] = []

        XCTAssertTrue(
            gate.deferOrdinaryRuntimeAdmission(
                for: profileID,
                key: .mainFrameSubmission(
                    tabID: tabID,
                    webViewID: webViewID
                )
            ) {
                replayed.append(1)
            }
        )
        XCTAssertTrue(
            gate.deferOrdinaryRuntimeAdmission(
                for: profileID,
                key: .mainFrameSubmission(
                    tabID: tabID,
                    webViewID: webViewID
                )
            ) {
                replayed.append(2)
            }
        )

        gate.release(lease)
        await Task.yield()
        XCTAssertEqual(replayed, [2])
    }

    func testDeferredAdmissionReplaysResidenceBeforeMainFrameSubmission() async throws {
        let gate = WebsiteDataMutationGate()
        let profileID = UUID()
        let tabID = UUID()
        let windowID = UUID()
        let webViewID = ObjectIdentifier(NSObject())
        let acquiredLease = await gate.acquire(profileIDs: [profileID])
        let lease = try XCTUnwrap(acquiredLease)
        var replayed: [String] = []

        XCTAssertTrue(
            gate.deferOrdinaryRuntimeAdmission(
                for: profileID,
                key: .mainFrameSubmission(tabID: tabID, webViewID: webViewID)
            ) {
                replayed.append("submission")
            }
        )
        XCTAssertTrue(
            gate.deferOrdinaryRuntimeAdmission(
                for: profileID,
                key: .trackedRegistration(tabID: tabID, windowID: windowID)
            ) {
                replayed.append("registration")
            }
        )
        XCTAssertTrue(
            gate.deferOrdinaryRuntimeAdmission(
                for: profileID,
                key: .webViewMaterialization(tabID: tabID)
            ) {
                replayed.append("materialization")
            }
        )

        gate.release(lease)
        await Task.yield()
        XCTAssertEqual(
            replayed,
            ["materialization", "registration", "submission"]
        )
    }

    func testProfileAndSemanticRebuildCannotBeOverwrittenByPlainMaterialization() async throws {
        let gate = WebsiteDataMutationGate()
        let profileID = UUID()
        let tabID = UUID()
        let acquiredLease = await gate.acquire(profileIDs: [profileID])
        let lease = try XCTUnwrap(acquiredLease)
        var replayed: [String] = []

        XCTAssertTrue(
            gate.deferOrdinaryRuntimeAdmission(
                for: profileID,
                key: .webViewMaterialization(tabID: tabID)
            ) {
                replayed.append("materialization")
            }
        )
        XCTAssertTrue(
            gate.deferOrdinaryRuntimeAdmission(
                for: profileID,
                key: .webViewRebuild(tabID: tabID)
            ) {
                replayed.append("rebuild")
            }
        )
        XCTAssertTrue(
            gate.deferOrdinaryRuntimeAdmission(
                for: profileID,
                key: .profileAssignment(tabID: tabID)
            ) {
                replayed.append("profile")
            }
        )

        gate.release(lease)
        await Task.yield()
        XCTAssertEqual(replayed, ["profile", "rebuild", "materialization"])
    }

    func testAsynchronousProfileWorkWaitsUntilTheProfileLeavesTheLease() async throws {
        let gate = WebsiteDataMutationGate()
        let profileID = UUID()
        let acquiredLease = await gate.acquire(profileIDs: [profileID])
        let lease = try XCTUnwrap(acquiredLease)
        var admissionResult: Bool?
        let waiter = Task { @MainActor in
            admissionResult = await gate.waitForOrdinaryRuntimeAdmission(
                for: profileID
            )
        }
        await Task.yield()
        XCTAssertNil(admissionResult)

        gate.release(lease)
        await waiter.value
        XCTAssertEqual(admissionResult, true)
    }
}
