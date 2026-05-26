import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3ServiceWorkerLifecycleCoordinatorTests: XCTestCase {
    func testLifecycleStateModelNeverReportsRunningNow() {
        for state in ChromeMV3ServiceWorkerLifecycleState.allCases {
            let snapshot = ChromeMV3ServiceWorkerLifecycleStateSnapshot
                .diagnostic(state: state)

            XCTAssertFalse(snapshot.workerRunningNow)
            XCTAssertFalse(snapshot.contextCreated)
            XCTAssertFalse(snapshot.workerWakeAvailableNow)
            XCTAssertFalse(snapshot.runtimeLoadable)
        }
    }

    func testRuntimeMessageWakeRequestIsModeledButBlocked() {
        let request = ChromeMV3ServiceWorkerWakeRequest.make(
            extensionID: "extension-a",
            profileID: "profile-a",
            reason: .runtimeMessage,
            sourceContext: .contentScript,
            targetListenerSurface: .runtimeOnMessageServiceWorker,
            requiresPermissionOrActiveTab: true
        )
        let preflight = ChromeMV3ServiceWorkerWakePreflight.evaluate(
            request: request
        )

        XCTAssertEqual(request.reason, .runtimeMessage)
        XCTAssertFalse(request.canWakeNow)
        XCTAssertFalse(preflight.canWakeServiceWorkerNow)
        XCTAssertFalse(preflight.canDispatchEventsNow)
        XCTAssertTrue(
            preflight.blockers.contains(.listenerRegistrationUnavailable)
        )
        XCTAssertTrue(preflight.blockers.contains(.contextNotLoaded))
        XCTAssertTrue(preflight.canQueuePendingEventInModel)
    }

    func testStorageChangedWakeRequestIsModeledButBlocked() {
        let request = ChromeMV3ServiceWorkerWakeRequest.storageChanged(
            extensionID: "extension-a",
            profileID: "profile-a",
            areaName: "local",
            changedKeys: ["token"]
        )
        let preflight = ChromeMV3ServiceWorkerWakePreflight.evaluate(
            request: request
        )

        XCTAssertEqual(request.reason, .storageChanged)
        XCTAssertFalse(preflight.canWakeServiceWorkerNow)
        XCTAssertFalse(preflight.canDispatchEventsNow)
        XCTAssertEqual(
            preflight.request.targetListenerSurface,
            .serviceWorkerLifecycleEventListener
        )
    }

    func testNativeMessagingConnectWakeRequestIsModeledButBlocked() {
        let request = ChromeMV3ServiceWorkerWakeRequest
            .nativeMessagingConnect(
                extensionID: "extension-a",
                profileID: "profile-a"
            )
        let preflight = ChromeMV3ServiceWorkerWakePreflight.evaluate(
            request: request
        )

        XCTAssertEqual(request.reason, .nativeMessagingConnect)
        XCTAssertFalse(preflight.canWakeServiceWorkerNow)
        XCTAssertTrue(preflight.blockers.contains(.nativeMessagingBlocked))
    }

    func testPendingEventQueueStoresModelEventsWithoutDispatch() {
        let request = ChromeMV3ServiceWorkerWakeRequest.make(
            extensionID: "extension-a",
            profileID: "profile-a",
            reason: .testFixture,
            sourceContext: .unknown,
            targetListenerSurface: .serviceWorkerLifecycleEventListener
        )
        let preflight = ChromeMV3ServiceWorkerWakePreflight.evaluate(
            request: request
        )
        var queue = ChromeMV3ServiceWorkerPendingEventQueue.empty
        let event = queue.enqueue(
            preflight: preflight,
            payloadSummary: "test payload"
        )
        queue.markEventBlocked(eventID: event.eventID, reason: "fixture")
        queue.markEventDropped(eventID: event.eventID, reason: "fixture drop")
        let snapshot = queue.snapshot()

        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.events.first?.sequence, 1)
        XCTAssertEqual(snapshot.events.first?.status, .dropped)
        XCTAssertFalse(snapshot.dispatchAttemptedNow)
    }

    func testIdleReleasePolicyIsModeledWithoutScheduling() {
        let policy = ChromeMV3ServiceWorkerLifecyclePolicySet.modeled
            .idleRelease

        XCTAssertEqual(policy.idleAfterInactivitySeconds, 30)
        XCTAssertTrue(policy.modeledOnly)
        XCTAssertFalse(policy.schedulesDeadlineNow)
        XCTAssertFalse(policy.releasesWorkerNow)
    }

    func testHardTimeoutPolicyIsModeledWithoutScheduling() {
        let policy = ChromeMV3ServiceWorkerLifecyclePolicySet.modeled
            .hardTimeout

        XCTAssertEqual(policy.maximumSingleRequestSeconds, 300)
        XCTAssertEqual(policy.fetchResponseLimitSeconds, 30)
        XCTAssertTrue(policy.modeledOnly)
        XCTAssertFalse(policy.schedulesDeadlineNow)
        XCTAssertFalse(policy.terminatesWorkerNow)
    }

    func testRuntimePortKeepaliveSourceIsModeledButInactive() {
        let source = ChromeMV3ServiceWorkerKeepaliveSource.make(
            kind: .runtimePort,
            extensionID: "extension-a",
            profileID: "profile-a"
        )

        XCTAssertTrue(source.wouldKeepAliveInFuture)
        XCTAssertFalse(source.implementedNow)
        XCTAssertTrue(source.passwordManagerRelevance)
    }

    func testNativeMessagingPortKeepaliveSourceIsBlocked() {
        let source = ChromeMV3ServiceWorkerKeepaliveSource.make(
            kind: .nativeMessagingPort,
            extensionID: "extension-a",
            profileID: "profile-a"
        )
        let policy = ChromeMV3ServiceWorkerLifecyclePolicySet.modeled
            .nativeMessagingPort

        XCTAssertTrue(source.wouldKeepAliveInFuture)
        XCTAssertFalse(source.implementedNow)
        XCTAssertTrue(source.blockers.contains {
            $0.contains("Native messaging keepalive is blocked")
        })
        XCTAssertTrue(policy.nativeMessagingBlocked)
        XCTAssertFalse(policy.launchesHostNow)
    }

    func testPermanentBackgroundIsRejectedByCoordinatorDiagnostics() {
        let coordinator = ChromeMV3ServiceWorkerLifecycleCoordinator.blocked(
            extensionID: "extension-a",
            profileID: "profile-a"
        )

        XCTAssertTrue(
            coordinator.lifecycleState.permanentBackgroundForbidden
        )
        XCTAssertTrue(
            coordinator.diagnostics.contains {
                $0.kind == .permanentBackgroundRejected
            }
        )
    }

    func testListenerUnavailableAndContextNotLoadedMapToWakeBlocked() {
        let request = ChromeMV3ServiceWorkerWakeRequest.make(
            extensionID: "extension-a",
            profileID: "profile-a",
            reason: .runtimeMessage,
            sourceContext: .contentScript,
            targetListenerSurface: .runtimeOnMessageServiceWorker
        )
        let preflight = ChromeMV3ServiceWorkerWakePreflight.evaluate(
            request: request
        )

        XCTAssertTrue(
            preflight.blockers.contains(.listenerRegistrationUnavailable)
        )
        XCTAssertTrue(preflight.blockers.contains(.contextNotLoaded))
        XCTAssertTrue(
            preflight.blockers.contains(.serviceWorkerWakeUnavailable)
        )
    }

    func testStorageOperationOnChangedReferencesWakePreflightButDoesNotDispatch() {
        var broker = ChromeMV3StorageBroker(
            namespace: ChromeMV3StorageNamespace(
                profileID: "profile-a",
                extensionID: "extension-a",
                area: .local
            )
        )

        let result = broker.set(["token": .string("abc")])
        let payload = result.changeSet.futureOnChangedPayload

        XCTAssertTrue(payload.serviceWorkerWakeRequired)
        XCTAssertFalse(payload.wouldDispatchNow)
        XCTAssertEqual(
            payload.serviceWorkerWakePreflight?.request.reason,
            .storageChanged
        )
        XCTAssertFalse(
            payload.serviceWorkerWakePreflight?.canWakeServiceWorkerNow
                ?? true
        )
    }

    func testMessagingRouteReferencesWakePreflightButDoesNotDispatch() {
        let route = ChromeMV3RuntimeMessagingRoute.make(
            kind: .contentScriptToServiceWorker,
            extensionID: "extension-a",
            profileID: "profile-a",
            tabID: 1,
            frameID: 0,
            sourceURL: "https://example.com/login"
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(route: route)
        let evaluation = ChromeMV3RuntimeMessagingRouteEvaluator.evaluate(
            route: route,
            envelope: envelope,
            permissionSnapshot: .empty,
            readiness: .blocked
        )

        XCTAssertFalse(evaluation.canDispatchNow)
        XCTAssertFalse(evaluation.canWakeServiceWorkerNow)
        XCTAssertEqual(
            evaluation.serviceWorkerWakePreflight?.request.reason,
            .runtimeMessage
        )
        XCTAssertFalse(
            evaluation.serviceWorkerWakePreflight?.canDispatchEventsNow
                ?? true
        )
    }

    func testPortLifecycleReferencesKeepalivePolicyButDoesNotOpenPort() {
        let route = ChromeMV3RuntimeMessagingRoute.make(
            kind: .runtimeConnect,
            extensionID: "extension-a",
            profileID: "profile-a"
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(route: route)
        let contract = ChromeMV3RuntimePortContract.model(
            route: route,
            envelope: envelope,
            permissionSnapshot: .empty,
            readiness: .blocked
        )

        XCTAssertFalse(contract.canOpenPortNow)
        XCTAssertFalse(contract.portLifecycleImplemented)
        XCTAssertEqual(contract.keepaliveSource?.kind, .runtimePort)
        XCTAssertFalse(contract.keepaliveSource?.implementedNow ?? true)
    }

    func testPermissionsEventReferencesWakePreflightButDoesNotDispatch() {
        let payload = ChromeMV3PermissionsAPIContractEvaluator.eventPayload(
            kind: .onAdded,
            source: .testFixture,
            extensionID: "extension-a",
            profileID: "profile-a",
            permissions: ["storage"],
            origins: []
        )

        XCTAssertTrue(payload.serviceWorkerWakeRequired)
        XCTAssertFalse(payload.wouldDispatchNow)
        XCTAssertEqual(
            payload.serviceWorkerWakePreflight?.request.reason,
            .permissionsChanged
        )
        XCTAssertFalse(payload.canWakeServiceWorkerNow)
    }

    func testPasswordManagerFixtureReportsServiceWorkerBlockers() {
        let report = ChromeMV3ServiceWorkerLifecycleReportGenerator.makeReport(
            extensionID: "password-manager-fixture",
            profileID: "profile-a",
            serviceWorkerScriptDeclared: true,
            passwordManagerLikeFixtureDetected: true,
            storagePermissionDetected: true,
            nativeMessagingDetected: true
        )
        let password = report.passwordManagerServiceWorkerSummary

        XCTAssertFalse(password.passwordManagerServiceWorkerReady)
        XCTAssertTrue(
            password.contentScriptMessageRequiresServiceWorkerWake
        )
        XCTAssertTrue(password.popupMessageRequiresServiceWorkerWake)
        XCTAssertTrue(password.storageOnChangedMayRequireServiceWorkerWake)
        XCTAssertTrue(
            password.nativeMessagingPortWouldAffectKeepaliveButBlocked
        )
        XCTAssertFalse(password.runtimePortKeepaliveImplemented)
        XCTAssertTrue(password.idleUnloadPolicyModeledButNotActive)
    }

    func testLifecycleReportKeepsRuntimeFlagsFalse() {
        let report = ChromeMV3ServiceWorkerLifecycleReportGenerator.makeReport(
            extensionID: "extension-a",
            profileID: "profile-a"
        )

        XCTAssertEqual(
            report.reportFileName,
            ChromeMV3ServiceWorkerLifecycleReportWriter.reportFileName
        )
        XCTAssertFalse(report.canWakeServiceWorkerNow)
        XCTAssertFalse(report.canDispatchEventsNow)
        XCTAssertFalse(report.canOpenPortNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertFalse(report.summary.canWakeServiceWorkerNow)
        XCTAssertFalse(report.summary.canDispatchEventsNow)
        XCTAssertFalse(report.summary.canOpenPortNow)
        XCTAssertFalse(report.summary.canLoadContextNow)
        XCTAssertFalse(report.summary.runtimeLoadable)
    }

    func testLifecycleReportWriterWritesDeterministicJSON() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let report = ChromeMV3ServiceWorkerLifecycleReportGenerator.makeReport(
            extensionID: "extension-a",
            profileID: "profile-a"
        )

        try ChromeMV3ServiceWorkerLifecycleReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )

        let reportURL = root.appendingPathComponent(
            ChromeMV3ServiceWorkerLifecycleReportWriter.reportFileName
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        let decoded = try JSONDecoder().decode(
            ChromeMV3ServiceWorkerLifecycleReport.self,
            from: Data(contentsOf: reportURL)
        )
        XCTAssertEqual(decoded, report)
    }

    @MainActor
    func testDisabledModuleWritesNoServiceWorkerLifecycleReport() throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let reportURL = root.appendingPathComponent(
            ChromeMV3ServiceWorkerLifecycleReportWriter.reportFileName
        )
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            browserConfiguration: BrowserConfiguration()
        )

        let report = module.chromeMV3ServiceWorkerLifecycleReportIfEnabled(
            fromRewrittenBundleRoot: root,
            writeReport: true
        )

        XCTAssertNil(report)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testNoForbiddenRuntimeBoundaryCallsInChromeMV3LifecycleSources()
        throws
    {
        let root = repositoryRoot()
        let targets = [
            root.appendingPathComponent("Sumi/Models/Extension/ChromeMV3"),
            root.appendingPathComponent("SumiTests"),
        ]
        let literalPatterns = [
            "WKWebExtensionContext" + "(",
            "load" + "Extension" + "Context",
            "add" + "User" + "Script",
            "connect" + "Native",
            "Pro" + "cess" + "(",
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer",
        ]
        let regexPatterns = [
            "runtimeLoadable.*" + "tr" + "ue",
            "canCreateContextNow.*" + "tr" + "ue",
            "canLoadContextNow.*" + "tr" + "ue",
            "canWakeServiceWorkerNow.*" + "tr" + "ue",
            "canDispatchEventsNow.*" + "tr" + "ue",
            "passwordManagerServiceWorkerReady.*" + "tr" + "ue",
        ]

        let swiftFiles = try targets.flatMap(swiftFiles)
            .filter {
                $0.lastPathComponent.hasPrefix("ChromeMV3")
                    || $0.path.contains("/ChromeMV3/")
            }
        let texts = try swiftFiles.map {
            ($0.path, try String(contentsOf: $0, encoding: .utf8))
        }
        let tabsScriptingHarnessPath =
            root
            .appendingPathComponent(
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3TabsScriptingJSMVP.swift"
            )
            .path
        for pattern in literalPatterns {
            let offenders = texts
                .filter { $0.1.contains(pattern) }
                .map(\.0)
                .filter {
                    pattern == "add" + "User" + "Script"
                        ? $0 != tabsScriptingHarnessPath
                        : true
                }
            XCTAssertTrue(offenders.isEmpty, "\(pattern): \(offenders)")
        }
        for pattern in regexPatterns {
            let regex = try NSRegularExpression(pattern: pattern)
            let offenders = texts.filter { _, text in
                regex.firstMatch(
                    in: text,
                    range: NSRange(text.startIndex..., in: text)
                ) != nil
            }.map(\.0)
            XCTAssertTrue(offenders.isEmpty, "\(pattern): \(offenders)")
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return try enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension == "swift"
            else { return nil }
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey]
            )
            return values.isRegularFile == true ? url : nil
        }
    }
}
