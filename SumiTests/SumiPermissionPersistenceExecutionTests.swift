import Darwin
import Foundation
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionPersistenceExecutionTests: XCTestCase {
    func testMainActorBootstrapAndPublicationUsePurposeSpecificQoS() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SumiPermissionPersistenceExecutionTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = PermissionPersistenceExecutionRecorder()

        let authority = SumiPermissionPersistenceAuthority(
            storageDirectory: directory,
            publishingFaultInjector: { stage, _ in
                recorder.recordPublication(stage: stage)
            }
        )

        let origin = SumiPermissionOrigin(string: "https://example.com")
        let key = SumiPermissionKey(
            requestingOrigin: origin,
            topOrigin: origin,
            permissionType: .camera,
            profilePartitionId: "profile-a"
        )
        authority.mutateAntiAbuseEvents {
            $0.append(
                SumiPermissionAntiAbuseEvent(
                    type: .promptShown,
                    key: key,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000)
                )
            )
        }

        let didFlush = await authority.flushPendingWrites()
        XCTAssertTrue(didFlush)
        let publicationObservations = recorder.publicationObservations
        for stage in SumiPermissionCanonicalSnapshotPublisher.Stage.allCases {
            let stageObservations = publicationObservations.filter { $0.stage == stage }
            XCTAssertFalse(stageObservations.isEmpty, "Missing publication stage \(stage)")
            XCTAssertTrue(stageObservations.allSatisfy { !$0.execution.ranOnMainThread })
            XCTAssertTrue(
                stageObservations.allSatisfy { $0.execution.qosClass == QOS_CLASS_UTILITY },
                "Publication stage \(stage) must stay at utility QoS"
            )
        }

        // Construction is deliberately synchronous on MainActor and loads the
        // published JSON. Returning proves the dependency cannot deadlock main.
        let reloadedAuthority = SumiPermissionPersistenceAuthority(
            storageDirectory: directory,
            bootstrapLoadObserver: { recorder.recordBootstrapLoad() }
        )
        XCTAssertEqual(reloadedAuthority.persistenceDiagnostics.loadOutcome, .loadedFile)
        let bootstrap = try XCTUnwrap(recorder.bootstrapObservation)
        XCTAssertFalse(bootstrap.ranOnMainThread)
        XCTAssertTrue(
            bootstrap.qosClass == QOS_CLASS_USER_INITIATED
                || bootstrap.qosClass == QOS_CLASS_USER_INTERACTIVE,
            "A synchronous user-interactive waiter may donate its QoS to the user-initiated work item"
        )
    }

    func testMemoryOnlyInitializationDoesNotScheduleBootstrapWork() {
        let recorder = PermissionPersistenceExecutionRecorder()

        _ = SumiPermissionPersistenceAuthority(
            bootstrapLoadObserver: { recorder.recordBootstrapLoad() }
        )

        XCTAssertNil(recorder.bootstrapObservation)
    }
}

private struct PermissionPersistenceExecutionObservation {
    let ranOnMainThread: Bool
    let qosClass: qos_class_t
}

private struct PermissionPersistencePublicationObservation {
    let stage: SumiPermissionCanonicalSnapshotPublisher.Stage
    let execution: PermissionPersistenceExecutionObservation
}

private final class PermissionPersistenceExecutionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var bootstrap: PermissionPersistenceExecutionObservation?
    private var publications: [PermissionPersistencePublicationObservation] = []

    var bootstrapObservation: PermissionPersistenceExecutionObservation? {
        lock.withLock { bootstrap }
    }

    var publicationObservations: [PermissionPersistencePublicationObservation] {
        lock.withLock { publications }
    }

    func recordBootstrapLoad() {
        lock.withLock {
            bootstrap = currentExecution()
        }
    }

    func recordPublication(stage: SumiPermissionCanonicalSnapshotPublisher.Stage) {
        lock.withLock {
            publications.append(
                PermissionPersistencePublicationObservation(
                    stage: stage,
                    execution: currentExecution()
                )
            )
        }
    }

    private func currentExecution() -> PermissionPersistenceExecutionObservation {
        PermissionPersistenceExecutionObservation(
            ranOnMainThread: Thread.isMainThread,
            qosClass: qos_class_self()
        )
    }
}
