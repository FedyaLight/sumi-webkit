import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionContextErrorObservationTests: XCTestCase {
    func testSameExtensionObservationsRemainIndependentAcrossProfiles()
        async throws {
        let contexts = try await makeContexts()
        let profileA = UUID()
        let profileB = UUID()
        let extensionID = "shared-extension"
        let recorder = ErrorObservationRecorder()
        let observation = recorder.makeObservation()
        defer { observation.removeAllObservations() }
        observation.seedLoggedErrorFingerprintForTesting(
            "profile-a",
            extensionId: extensionID,
            profileId: profileA
        )
        observation.seedLoggedErrorFingerprintForTesting(
            "profile-b",
            extensionId: extensionID,
            profileId: profileB
        )

        observation.observe(
            contexts.first,
            extensionId: extensionID,
            profileId: profileA
        )
        observation.observe(
            contexts.second,
            extensionId: extensionID,
            profileId: profileB
        )
        XCTAssertEqual(observation.observedExtensionIDs, [extensionID])

        observation.removeObservation(
            ifObserving: contexts.first,
            extensionId: extensionID,
            profileId: profileA
        )
        XCTAssertEqual(observation.observedExtensionIDs, [extensionID])

        observation.removeObservation(
            ifObserving: contexts.second,
            extensionId: extensionID,
            profileId: profileB
        )
        XCTAssertTrue(observation.observedExtensionIDs.isEmpty)
    }

    func testReplacementDoesNotInheritFingerprintAndOldCallbackIsRetired()
        async throws {
        let contexts = try await makeContexts()
        let profileID = UUID()
        let extensionID = "replacement-extension"
        let recorder = ErrorObservationRecorder()
        let observation = recorder.makeObservation()
        defer { observation.removeAllObservations() }
        observation.observe(
            contexts.first,
            extensionId: extensionID,
            profileId: profileID
        )
        observation.seedLoggedErrorFingerprintForTesting(
            "",
            extensionId: extensionID,
            profileId: profileID
        )
        let metricUpdatesBeforeReplacement = recorder.metricUpdateCount

        observation.observe(
            contexts.second,
            extensionId: extensionID,
            profileId: profileID
        )

        XCTAssertEqual(
            recorder.metricUpdateCount,
            metricUpdatesBeforeReplacement + 1,
            "replacement must evaluate its own initial error state"
        )

        let metricUpdatesAfterReplacement = recorder.metricUpdateCount
        let tracesAfterReplacement = recorder.traces
        NotificationCenter.default.post(
            name: WKWebExtensionContext.errorsDidUpdateNotification,
            object: contexts.first
        )
        await drainMainActorTasks()

        XCTAssertEqual(
            recorder.metricUpdateCount,
            metricUpdatesAfterReplacement
        )
        XCTAssertEqual(recorder.traces, tracesAfterReplacement)
    }

    func testExactOldRemovalDoesNotRemoveReplacementObservation()
        async throws {
        let contexts = try await makeContexts()
        let profileID = UUID()
        let extensionID = "exact-removal-extension"
        let recorder = ErrorObservationRecorder()
        let observation = recorder.makeObservation()
        defer { observation.removeAllObservations() }
        observation.observe(
            contexts.first,
            extensionId: extensionID,
            profileId: profileID
        )
        observation.observe(
            contexts.second,
            extensionId: extensionID,
            profileId: profileID
        )

        observation.removeObservation(
            ifObserving: contexts.first,
            extensionId: extensionID,
            profileId: profileID
        )

        XCTAssertEqual(observation.observedExtensionIDs, [extensionID])
        let metricUpdatesBeforeReplacementCallback =
            recorder.metricUpdateCount
        NotificationCenter.default.post(
            name: WKWebExtensionContext.errorsDidUpdateNotification,
            object: contexts.second
        )
        await drainMainActorTasks()
        XCTAssertEqual(
            recorder.metricUpdateCount,
            metricUpdatesBeforeReplacementCallback + 1
        )

        observation.removeObservation(
            ifObserving: contexts.second,
            extensionId: extensionID,
            profileId: profileID
        )
        XCTAssertTrue(observation.observedExtensionIDs.isEmpty)
        let metricUpdatesAfterExactRemoval = recorder.metricUpdateCount
        NotificationCenter.default.post(
            name: WKWebExtensionContext.errorsDidUpdateNotification,
            object: contexts.second
        )
        await drainMainActorTasks()
        XCTAssertEqual(
            recorder.metricUpdateCount,
            metricUpdatesAfterExactRemoval
        )
    }

    private func drainMainActorTasks() async {
        for _ in 0..<4 {
            await Task.yield()
        }
    }

    private func makeContexts() async throws -> (
        first: WKWebExtensionContext,
        second: WKWebExtensionContext
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 3,
                "name": "Context Error Observation",
                "version": "1.0",
            ],
            options: [.sortedKeys]
        ).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        let extensionRuntime = try await WKWebExtension(
            resourceBaseURL: directory
        )
        return (
            WKWebExtensionContext(for: extensionRuntime),
            WKWebExtensionContext(for: extensionRuntime)
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ErrorObservationRecorder {
    private(set) var metricUpdateCount = 0
    private(set) var traces: [String] = []
    private(set) var lastDuration: TimeInterval?

    func makeObservation() -> ExtensionContextErrorObservation {
        ExtensionContextErrorObservation(
            recordErrorUpdateDuration: { [weak self] _, duration in
                guard let self else { return }
                self.metricUpdateCount += 1
                self.lastDuration = duration
            },
            trace: { [weak self] message in
                self?.traces.append(message)
            },
            isEnabled: { true }
        )
    }
}
