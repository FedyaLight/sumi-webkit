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

    func testTrackedMaterializationAndReplacementUseIndependentReplaySlots()
        async throws {
        let gate = WebsiteDataMutationGate()
        let profileID = UUID()
        let tabID = UUID()
        let windowID = UUID()
        let acquiredLease = await gate.acquire(profileIDs: [profileID])
        let lease = try XCTUnwrap(acquiredLease)
        var replayed: [String] = []

        XCTAssertTrue(gate.deferOrdinaryRuntimeAdmission(
            for: profileID,
            key: .trackedRegistration(tabID: tabID, windowID: windowID)
        ) {
            replayed.append("materialization")
        })
        XCTAssertTrue(gate.deferOrdinaryRuntimeAdmission(
            for: profileID,
            key: .trackedReplacement(tabID: tabID, windowID: windowID)
        ) {
            replayed.append("replacement")
        })

        gate.release(lease)
        await Task.yield()
        XCTAssertEqual(replayed, ["materialization", "replacement"])
    }

    func testCancellingTabAdmissionsAlsoCancelsTrackedReplacement() async throws {
        let gate = WebsiteDataMutationGate()
        let profileID = UUID()
        let tabID = UUID()
        let acquiredLease = await gate.acquire(profileIDs: [profileID])
        let lease = try XCTUnwrap(acquiredLease)
        var didReplay = false
        XCTAssertTrue(gate.deferOrdinaryRuntimeAdmission(
            for: profileID,
            key: .trackedReplacement(tabID: tabID, windowID: UUID())
        ) {
            didReplay = true
        })

        gate.cancelDeferredAdmissions(forTabID: tabID)
        gate.release(lease)
        await Task.yield()

        XCTAssertFalse(didReplay)
    }

    func testCancellationAfterReleaseStillStopsScheduledReplay() async throws {
        let gate = WebsiteDataMutationGate()
        let profileID = UUID()
        let tabID = UUID()
        let acquiredLease = await gate.acquire(profileIDs: [profileID])
        let lease = try XCTUnwrap(acquiredLease)
        var didReplay = false
        XCTAssertTrue(gate.deferOrdinaryRuntimeAdmission(
            for: profileID,
            key: .webViewMaterialization(tabID: tabID)
        ) {
            didReplay = true
        })

        gate.release(lease)
        gate.cancelDeferredAdmissions(forTabID: tabID)
        await Task.yield()

        XCTAssertFalse(didReplay)
    }

    func testScheduledReplayReentersQueueWhenProfileIsBlockedAgain() async throws {
        let gate = WebsiteDataMutationGate()
        let profileID = UUID()
        let tabID = UUID()
        let acquiredFirstLease = await gate.acquire(profileIDs: [profileID])
        let firstLease = try XCTUnwrap(acquiredFirstLease)
        var replayCount = 0
        XCTAssertTrue(gate.deferOrdinaryRuntimeAdmission(
            for: profileID,
            key: .webViewMaterialization(tabID: tabID)
        ) {
            replayCount += 1
        })

        gate.release(firstLease)
        let acquiredSecondLease = await gate.acquire(profileIDs: [profileID])
        let secondLease = try XCTUnwrap(acquiredSecondLease)
        await Task.yield()
        XCTAssertEqual(replayCount, 0)

        gate.release(secondLease)
        await Task.yield()
        XCTAssertEqual(replayCount, 1)
    }

    func testDirectSameSlotAdmissionRevokesOlderScheduledReplay() async throws {
        let gate = WebsiteDataMutationGate()
        let profileID = UUID()
        let key = WebsiteDataMutationGate.DeferredAdmissionKey
            .trackedReplacement(tabID: UUID(), windowID: UUID())
        let acquiredLease = await gate.acquire(profileIDs: [profileID])
        let lease = try XCTUnwrap(acquiredLease)
        var effects: [String] = []
        XCTAssertTrue(gate.deferOrdinaryRuntimeAdmission(
            for: profileID,
            key: key
        ) {
            effects.append("stale-A")
        })

        gate.release(lease)
        XCTAssertFalse(gate.deferOrdinaryRuntimeAdmission(
            for: profileID,
            key: key
        ) {
            XCTFail("Direct admission must not enqueue B")
        })
        effects.append("direct-B")
        await Task.yield()

        XCTAssertEqual(effects, ["direct-B"])
    }

    func testNewerSameSlotDeferralForDifferentProfileSupersedesScheduledReplay()
        async throws {
        let gate = WebsiteDataMutationGate()
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let key = WebsiteDataMutationGate.DeferredAdmissionKey
            .untrackedReplacement(tabID: UUID())
        let acquiredFirstLease = await gate.acquire(
            profileIDs: [firstProfileID]
        )
        let firstLease = try XCTUnwrap(acquiredFirstLease)
        var replayed: [String] = []
        XCTAssertTrue(gate.deferOrdinaryRuntimeAdmission(
            for: firstProfileID,
            key: key
        ) {
            replayed.append("stale-first-profile")
        })

        gate.release(firstLease)
        let acquiredSecondLease = await gate.acquire(
            profileIDs: [secondProfileID]
        )
        let secondLease = try XCTUnwrap(acquiredSecondLease)
        XCTAssertTrue(gate.deferOrdinaryRuntimeAdmission(
            for: secondProfileID,
            key: key
        ) {
            replayed.append("current-second-profile")
        })
        await Task.yield()
        XCTAssertTrue(replayed.isEmpty)

        gate.release(secondLease)
        await Task.yield()
        XCTAssertEqual(replayed, ["current-second-profile"])
    }

    func testTrackedAndUntrackedReplacementUseIndependentReplaySlots()
        async throws {
        let gate = WebsiteDataMutationGate()
        let profileID = UUID()
        let tabID = UUID()
        let acquiredLease = await gate.acquire(profileIDs: [profileID])
        let lease = try XCTUnwrap(acquiredLease)
        var replayed: [String] = []

        XCTAssertTrue(gate.deferOrdinaryRuntimeAdmission(
            for: profileID,
            key: .trackedReplacement(tabID: tabID, windowID: UUID())
        ) {
            replayed.append("tracked")
        })
        XCTAssertTrue(gate.deferOrdinaryRuntimeAdmission(
            for: profileID,
            key: .untrackedReplacement(tabID: tabID)
        ) {
            replayed.append("untracked")
        })

        gate.release(lease)
        await Task.yield()
        XCTAssertEqual(Set(replayed), Set(["tracked", "untracked"]))
    }

    func testTerminalGateRejectsAdmissionWithoutSchedulingReplay() {
        let gate = WebsiteDataMutationGate()
        var didReplay = false
        gate.resetForTerminalShutdown()

        XCTAssertEqual(
            gate.ordinaryRuntimeAdmission(
                for: UUID(),
                key: .webViewMaterialization(tabID: UUID())
            ) {
                didReplay = true
            },
            .rejectedAfterTerminalShutdown
        )
        XCTAssertFalse(didReplay)
    }

    func testTerminalCancellationRevokesRestoreSubmissionAuthority() async throws {
        let gate = WebsiteDataMutationGate()
        let profileID = UUID()
        let tabID = UUID()
        let semanticRevision: UInt64 = 42
        let acquiredLease = await gate.acquire(profileIDs: [profileID])
        let lease = try XCTUnwrap(acquiredLease)
        gate.authorizeRestoreSubmission(
            tabID: tabID,
            semanticRevision: semanticRevision
        )
        XCTAssertTrue(gate.permitsInternalSubmission(
            tabID: tabID,
            semanticRevision: semanticRevision
        ))

        gate.cancelDeferredAdmissions(forTabID: tabID)

        XCTAssertFalse(gate.permitsInternalSubmission(
            tabID: tabID,
            semanticRevision: semanticRevision
        ))
        gate.release(lease)
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
