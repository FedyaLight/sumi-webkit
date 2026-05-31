import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3ServiceWorkerJSExecutionHarnessTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testDisabledModuleAndExtensionBlockExecutionBeforeResourceLoad() throws {
        let fixture = try makeHarness(
            source: "chrome.runtime.onMessage.addListener(() => 'ok');\n",
            localExperimentalGateAllowed: true
        )
        let moduleDisabled = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request(moduleState: .disabled)
        )
        let extensionDisabled = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request(extensionEnabled: false)
        )

        XCTAssertEqual(moduleDisabled.start().status, .blocked)
        XCTAssertEqual(extensionDisabled.start().status, .blocked)
        XCTAssertNil(moduleDisabled.snapshot.resourceLoad)
        XCTAssertNil(extensionDisabled.snapshot.resourceLoad)
        XCTAssertNil(moduleDisabled.snapshot.lifecycleSnapshot)
        XCTAssertNil(extensionDisabled.snapshot.lifecycleSnapshot)
        XCTAssertEqual(moduleDisabled.policy.executionSurface, .none)
        XCTAssertEqual(extensionDisabled.policy.executionSurface, .none)
        XCTAssertFalse(moduleDisabled.policy.serviceWorkerJSExecutionAvailableByDefault)
    }

    func testDefaultOffGateBlocksExecutionBeforeResourceLoad() throws {
        let fixture = try makeHarness(
            source: "chrome.runtime.onMessage.addListener(() => 'ok');\n"
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )

        XCTAssertEqual(harness.start().status, .blocked)
        XCTAssertNil(harness.snapshot.resourceLoad)
        XCTAssertTrue(
            harness.policy.blockers.contains(.localExperimentalGateRequired)
        )
    }

    func testGeneratedResourceLoaderDiagnosesMissingUnsafeModuleAndImportScripts()
        throws
    {
        let missingFixture = try makeHarness(
            source: "chrome.runtime.onMessage.addListener(() => 'ok');\n",
            localExperimentalGateAllowed: true
        )
        try FileManager.default.removeItem(
            at: missingFixture.generatedRootURL
                .appendingPathComponent("background.js")
        )
        let missing = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: missingFixture.request()
        )
        XCTAssertEqual(missing.start().status, .blocked)
        XCTAssertTrue(
            missing.snapshot.resourceLoad?.blockers.contains(
                .serviceWorkerFileMissing
            ) == true
        )

        let unsafeFixture = try makeHarness(
            source: "chrome.runtime.onMessage.addListener(() => 'ok');\n",
            localExperimentalGateAllowed: true
        )
        var unsafeManifest = unsafeFixture.manifest
        unsafeManifest.background?.serviceWorker = "../background.js"
        let unsafe = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: unsafeFixture.request(manifest: unsafeManifest)
        )
        XCTAssertEqual(unsafe.start().status, .blocked)
        XCTAssertTrue(
            unsafe.snapshot.resourceLoad?.blockers.contains(
                .serviceWorkerPathUnsafe
            ) == true
        )

        let moduleFixture = try makeHarness(
            source: "chrome.runtime.onMessage.addListener(() => 'ok');\n",
            serviceWorkerType: "module",
            localExperimentalGateAllowed: true
        )
        let module = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: moduleFixture.request()
        )
        XCTAssertEqual(module.start().status, .blocked)
        XCTAssertTrue(
            module.snapshot.resourceLoad?.blockers.contains(
                .moduleWorkerUnsupported
            ) == true
        )

        let importFixture = try makeHarness(
            source: "importScripts('dependency.js');\n",
            localExperimentalGateAllowed: true
        )
        let imported = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: importFixture.request()
        )
        XCTAssertEqual(imported.start().status, .blocked)
        XCTAssertTrue(
            imported.snapshot.resourceLoad?.blockers.contains(
                .importScriptsUnsupported
            ) == true
        )
    }

    func testClassicWorkerCapturesRegistrationAndDispatchesSendResponse() throws {
        let fixture = try makeHarness(
            source: """
            chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
              sendResponse({ echo: message.value, urlRedacted: sender.urlRedacted });
            });
            chrome.storage.onChanged.addListener(() => {});
            """,
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )

        let started = harness.start()
        let result = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            arguments: [.object(["value": .string("captured")])],
            payloadSummary: "popup runtime.sendMessage"
        )

        XCTAssertEqual(started.status, .running)
        XCTAssertEqual(started.executionSurface, .javaScriptCore)
        XCTAssertTrue(harness.capturedListener(for: .runtimeOnMessage))
        XCTAssertTrue(harness.capturedListener(for: .storageOnChanged))
        XCTAssertEqual(harness.snapshot.capturedListeners.first?.registrationOrder, 1)
        XCTAssertEqual(harness.snapshot.capturedListeners.first?.listenerArity, 3)
        XCTAssertEqual(
            result.responsePayload,
            .object([
                "echo": .string("captured"),
                "urlRedacted": .bool(true),
            ])
        )
        XCTAssertEqual(result.resultKind, .delivered)
        XCTAssertEqual(result.lifecycleRoutingRecord?.resultKind, .delivered)
    }

    func testMessageNoReceiverPromiseAndListenerErrorAreDeterministic() throws {
        let noListener = try startedHarness(source: "")
        let noReceiver = noListener.dispatch(
            source: .contentScriptRuntimeMessage,
            arguments: [.object(["ping": .bool(true)])],
            payloadSummary: "content-script runtime.sendMessage"
        )
        XCTAssertEqual(noReceiver.resultKind, .noReceiver)

        let promise = try startedHarness(
            source:
                "chrome.runtime.onMessage.addListener(async () => 'later');\n"
        )
        let promiseResult = promise.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "Promise response"
        )
        XCTAssertEqual(promiseResult.resultKind, .unsupportedListenerMode)
        XCTAssertTrue(
            promiseResult.lastErrorMessage?.contains("observable but deferred")
                == true
        )

        let timedOut = try startedHarness(
            source:
                "chrome.runtime.onMessage.addListener((_m, _s, _r) => true);\n"
        )
        XCTAssertEqual(
            timedOut.dispatch(
                source: .popupOptionsRuntimeMessage,
                payloadSummary: "open sendResponse channel"
            ).resultKind,
            .sendResponseTimeoutDiagnostic
        )

        let failing = try startedHarness(
            source:
                "chrome.runtime.onMessage.addListener(() => { throw new Error('listener failed'); });\n"
        )
        let failure = failing.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "throwing listener"
        )
        XCTAssertEqual(failure.resultKind, .listenerError)
        XCTAssertEqual(failure.lastErrorMessage, "listener failed")
    }

    func testRuntimeConnectPortMessageDeliveryDisconnectAndKeepaliveRelease()
        throws
    {
        let harness = try startedHarness(
            source: """
            chrome.runtime.onConnect.addListener((port) => {
              port.onMessage.addListener((message) => {
                port.postMessage({ echo: message.value, name: port.name });
              });
              port.onDisconnect.addListener(() => {});
            });
            """
        )

        let connected = harness.connectRuntime(name: "fixture-channel")
        let portID = try XCTUnwrap(connected.portID)
        let delivered = harness.deliverPortMessage(
            portID: portID,
            message: .object(["value": .string("port-value")])
        )

        XCTAssertEqual(connected.resultKind, .delivered)
        XCTAssertTrue(harness.capturedListener(for: .runtimeOnConnect))
        XCTAssertEqual(delivered?.onMessageListenerCount, 1)
        XCTAssertEqual(delivered?.onDisconnectListenerCount, 1)
        XCTAssertEqual(
            delivered?.postedMessages,
            [
                .object([
                    "echo": .string("port-value"),
                    "name": .string("fixture-channel"),
                ]),
            ]
        )
        XCTAssertEqual(
            harness.snapshot.lifecycleSnapshot?.activeKeepaliveRecords.count,
            1
        )
        XCTAssertTrue(harness.disconnectPort(portID: portID))
        XCTAssertEqual(harness.snapshot.ports.first?.connected, false)
        XCTAssertEqual(
            harness.snapshot.lifecycleSnapshot?.activeKeepaliveRecords.count,
            0
        )
    }

    func testStoragePermissionsAlarmContextMenuAndWebNavigationDispatch()
        throws
    {
        let harness = try startedHarness(
            source: """
            chrome.storage.onChanged.addListener(() => {});
            chrome.permissions.onAdded.addListener(() => {});
            chrome.permissions.onRemoved.addListener(() => {});
            chrome.alarms.onAlarm.addListener(() => {});
            chrome.contextMenus.onClicked.addListener(() => {});
            chrome.webNavigation.onCommitted.addListener(() => {});
            """
        )
        let sources: [ChromeMV3ServiceWorkerEventSource] = [
            .storageChanged,
            .permissionsAdded,
            .permissionsRemoved,
            .alarmTriggered,
            .contextMenuClicked,
            .webNavigationSyntheticEvent,
        ]

        for source in sources {
            let result = harness.dispatch(
                source: source,
                arguments: [.object(["fixture": .bool(true)])],
                payloadSummary: source.rawValue
            )
            XCTAssertEqual(result.resultKind, .delivered, source.rawValue)
            XCTAssertEqual(
                result.lifecycleRoutingRecord?.resultKind,
                .delivered,
                source.rawValue
            )
        }
    }

    func testTrustedNativeFixturePortRequiresPolicyRoutesAndRevokes() throws {
        let harness = try startedHarness(source: "")
        let denied = harness.openTrustedNativeFixturePort(
            name: "com.sumi.fixture",
            trustedFixturePolicyAllowed: false
        )
        XCTAssertEqual(denied.resultKind, .blockedByPermission)

        let opened = harness.openTrustedNativeFixturePort(
            name: "com.sumi.fixture",
            trustedFixturePolicyAllowed: true
        )
        let portID = try XCTUnwrap(opened.portID)
        let delivered = harness.deliverTrustedNativeFixturePortMessage(
            portID: portID,
            message: .object(["fixture": .string("native")])
        )
        XCTAssertEqual(opened.resultKind, .delivered)
        XCTAssertEqual(delivered.resultKind, .delivered)
        XCTAssertEqual(
            delivered.lifecycleRoutingRecord?.resultKind,
            .delivered
        )

        harness.revokeTrustedNativeFixturePolicy()
        XCTAssertEqual(harness.snapshot.ports.first?.connected, false)
        XCTAssertEqual(
            harness.snapshot.ports.first?.disconnectReason,
            "trustedNativeFixturePolicyRevoked"
        )
    }

    func testExplicitLifecycleTeardownReleasesHarnessAndPorts() throws {
        let idle = try startedHarness(
            source: "chrome.runtime.onMessage.addListener(() => 'ok');\n"
        )
        _ = idle.dispatch(
            source: .popupOptionsRuntimeMessage,
            payloadSummary: "idle eligible"
        )
        _ = idle.triggerIdleRelease()
        XCTAssertEqual(idle.snapshot.startRecord.status, .stoppedAfterIdle)

        let hardTimeout = try startedHarness(
            source: "chrome.runtime.onConnect.addListener(() => {});\n"
        )
        _ = hardTimeout.connectRuntime(name: "hard-timeout")
        _ = hardTimeout.triggerHardTimeout()
        XCTAssertEqual(
            hardTimeout.snapshot.startRecord.status,
            .stoppedAfterHardTimeout
        )
        XCTAssertEqual(hardTimeout.snapshot.ports.first?.connected, false)

        let disabled = try startedHarness(source: "")
        disabled.tearDownForExtensionDisable()
        XCTAssertEqual(disabled.snapshot.startRecord.status, .stoppedAfterDisable)

        let uninstalled = try startedHarness(source: "")
        uninstalled.tearDownForExtensionUninstall()
        XCTAssertEqual(
            uninstalled.snapshot.startRecord.status,
            .stoppedAfterUninstall
        )

        let profileClosed = try startedHarness(source: "")
        profileClosed.tearDownForProfileClose()
        XCTAssertEqual(
            profileClosed.snapshot.startRecord.status,
            .stoppedAfterProfileClose
        )

        let reset = try startedHarness(source: "")
        reset.reset()
        XCTAssertEqual(reset.snapshot.startRecord.status, .stoppedAfterReset)
        XCTAssertTrue(reset.snapshot.ports.isEmpty)
    }

    func testPolicyKeepsPermanentRuntimeSchedulersAndHostLaunchBlocked() {
        let policy = ChromeMV3ServiceWorkerJSExecutionPolicy.evaluate(
            moduleState: .enabled,
            extensionEnabled: true,
            localExperimentalGateAllowed: true,
            generatedBundleRecordAvailable: true
        )

        XCTAssertFalse(policy.serviceWorkerJSExecutionAvailableByDefault)
        XCTAssertFalse(policy.permanentBackgroundAvailable)
        XCTAssertFalse(policy.timersAllowed)
        XCTAssertFalse(policy.pollingAllowed)
    }

    private func startedHarness(
        source: String
    ) throws -> ChromeMV3ServiceWorkerJSExecutionHarness {
        let fixture = try makeHarness(
            source: source,
            localExperimentalGateAllowed: true
        )
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: fixture.request()
        )
        XCTAssertEqual(harness.start().status, .running)
        return harness
    }

    private struct HarnessFixture {
        var manifest: ChromeMV3Manifest
        var generatedRecord: ChromeMV3GeneratedBundleRecord
        var generatedRootURL: URL
        var localExperimentalGateAllowed: Bool

        func request(
            manifest: ChromeMV3Manifest? = nil,
            moduleState: ChromeMV3ProfileHostModuleState = .enabled,
            extensionEnabled: Bool = true
        ) -> ChromeMV3ServiceWorkerJSExecutionRequest {
            ChromeMV3ServiceWorkerJSExecutionRequest(
                manifest: manifest ?? self.manifest,
                generatedBundleRecord: generatedRecord,
                extensionID: "service-worker-js-fixture-extension",
                profileID: "service-worker-js-fixture-profile",
                moduleState: moduleState,
                extensionEnabled: extensionEnabled,
                localExperimentalGateAllowed:
                    localExperimentalGateAllowed
            )
        }
    }

    private func makeHarness(
        source: String,
        serviceWorkerType: String? = nil,
        localExperimentalGateAllowed: Bool = false
    ) throws -> HarnessFixture {
        let fixtureDirectory = try temporaryDirectory()
            .appendingPathComponent("extension", isDirectory: true)
        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: true
        )
        var background: [String: Any] = [
            "service_worker": "background.js",
        ]
        if let serviceWorkerType {
            background["type"] = serviceWorkerType
        }
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Service Worker JS Execution Fixture",
            "version": "1.0.0",
            "background": background,
        ]
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        ).write(
            to: fixtureDirectory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        try source.write(
            to: fixtureDirectory.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        let storeRoot = try temporaryDirectory()
        let stage = try ChromeMV3OriginalBundleStore(
            rootURL: storeRoot
        ).stageUnpackedDirectory(at: fixtureDirectory)
        let generated = try ChromeMV3GeneratedBundleWriter(
            rootURL: storeRoot
        ).writeGeneratedBundle(
            originalBundleRecord: stage.originalBundleRecord,
            manifestSnapshot: stage.manifestSnapshot,
            planningRecord: stage.generatedBundlePlan
        )
        return HarnessFixture(
            manifest: stage.manifestSnapshot.normalizedManifest,
            generatedRecord: generated.record,
            generatedRootURL: generated.generatedBundleRootURL,
            localExperimentalGateAllowed: localExperimentalGateAllowed
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(url)
        return url
    }

}
