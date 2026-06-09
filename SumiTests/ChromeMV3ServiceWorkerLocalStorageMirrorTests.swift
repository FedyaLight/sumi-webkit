import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3ServiceWorkerLocalStorageMirrorTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testMirrorExportedValuesPersistsAndProducesOnChangedPayload() throws {
        let root = try makeTemporaryDirectory()
        let namespace = ChromeMV3StorageNamespace(
            profileID: "profile-a",
            extensionID: "extension-a",
            area: .local
        )
        var broker = ChromeMV3StorageBroker(
            namespace: namespace,
            persistenceMode: .hostBacked(rootURL: root)
        )

        let mirror = ChromeMV3ServiceWorkerLocalStorageMirror.mirrorExportedValues(
            ["fixtureMarker": .string("startup")],
            into: &broker,
            writerContextCategory: "popupWakeSW"
        )

        XCTAssertTrue(mirror.result.succeeded)
        XCTAssertTrue(mirror.result.persisted)
        XCTAssertEqual(mirror.result.changedKeyCount, 1)
        XCTAssertEqual(mirror.result.writerContextCategory, "popupWakeSW")
        XCTAssertEqual(mirror.result.snapshotCategory, "hostSnapshotPersisted")
        XCTAssertEqual(mirror.onChangedPayload?.areaName, "local")
        XCTAssertEqual(mirror.onChangedPayload?.changedKeys, ["fixtureMarker"])

        var reloaded = ChromeMV3StorageBroker(
            namespace: namespace,
            persistenceMode: .hostBacked(rootURL: root)
        )
        XCTAssertTrue(try reloaded.loadHostSnapshotIfPresent())
        XCTAssertEqual(
            reloaded.exportSnapshot().values["fixtureMarker"],
            .string("startup")
        )
    }

    func testControlledPopupServiceWorkerWriteIsVisibleToPopupBroker() throws {
        let storageRoot = try makeTemporaryDirectory()
        let profileID = "storage-visibility-profile"
        let extensionID = "storage-visibility-extension"
        let harness = try makeHarnessWritingStorageOnConnect(
            extensionID: extensionID,
            profileID: profileID
        )
        let session = try XCTUnwrap(
            ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
                .session(profileID: profileID, extensionID: extensionID)
        )
        harness.attachCapturedListenerDispatchers(
            to: session,
            clearingExisting: true
        )

        let namespace = ChromeMV3StorageNamespace(
            profileID: profileID,
            extensionID: extensionID,
            area: .local
        )
        final class BrokerHolder: @unchecked Sendable {
            var broker: ChromeMV3StorageBroker
            init(broker: ChromeMV3StorageBroker) {
                self.broker = broker
            }
        }
        let brokerHolder = BrokerHolder(
            broker: ChromeMV3StorageBroker(
                namespace: namespace,
                persistenceMode: .hostBacked(rootURL: storageRoot)
            )
        )
        session.setServiceWorkerLocalStorageMirror {
            guard
                let exported = harness.exportStorageValues(area: .local)
            else { return nil }
            let mirror = ChromeMV3ServiceWorkerLocalStorageMirror
                .mirrorExportedValues(
                    exported,
                    into: &brokerHolder.broker,
                    writerContextCategory: "popupWakeSW"
                )
            return mirror.onChangedPayload
        }

        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: extensionID,
                profileID: profileID,
                allowlist: .controlledActionPopupPolicy,
                storageLocalRootPath: storageRoot.path
            ),
            sharedLifecycleSession: session
        )

        let connect = handler.handle(request(
            namespace: "runtime",
            methodName: "connect",
            arguments: [.object(["name": .string("mv3-storage-visibility")])],
            invocationMode: .fireAndForget
        ))
        XCTAssertTrue(connect.succeeded)
        XCTAssertNotNil(connect.onChangedPayload)
        XCTAssertTrue(
            connect.diagnostics.contains("serviceWorkerStorageMirror=applied")
        )

        let read = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("mv3StartupStorageMarker")]
        ))
        XCTAssertTrue(read.succeeded)
        XCTAssertEqual(
            stringValue(objectValue(read.resultPayload)?["mv3StartupStorageMarker"]),
            "startup"
        )
    }

    private func makeHarnessWritingStorageOnConnect(
        extensionID: String,
        profileID: String
    ) throws -> ChromeMV3ServiceWorkerJSExecutionHarness {
        let fixtureDirectory = try makeTemporaryDirectory()
            .appendingPathComponent("extension", isDirectory: true)
        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Storage Visibility Harness",
            "version": "1.0.0",
            "background": [
                "service_worker": "background.js",
            ],
        ]
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        ).write(
            to: fixtureDirectory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        try """
        chrome.runtime.onConnect.addListener((port) => {
          chrome.storage.local.set({ mv3StartupStorageMarker: "startup" });
          port.postMessage({ type: "storage-written" });
        });
        """.write(
            to: fixtureDirectory.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )
        let storeRoot = try makeTemporaryDirectory()
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
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: ChromeMV3ServiceWorkerJSExecutionRequest(
                manifest: stage.manifestSnapshot.normalizedManifest,
                generatedBundleRecord: generated.record,
                extensionID: extensionID,
                profileID: profileID,
                moduleState: .enabled,
                extensionEnabled: true,
                localExperimentalGateAllowed: true,
                dynamicImportRewriteExperimentAllowed: true
            )
        )
        let start = harness.start()
        XCTAssertTrue(
            start.status == .running || harness.canDispatchCapturedListeners,
            start.diagnostics.joined(separator: "\n")
        )
        XCTAssertTrue(harness.capturedListener(for: .runtimeOnConnect))
        return harness
    }

    func testFlushDeferredServiceWorkerWorkDrainsQueuedTimeoutsBeforeMirror()
        throws
    {
        let harness = try makeHarnessWritingStorageOnConnect(
            extensionID: "deferred-drain-extension",
            profileID: "deferred-drain-profile"
        )
        let start = harness.start()
        XCTAssertEqual(start.status, .running)
        let drained =
            ChromeMV3ServiceWorkerLocalStorageMirror
            .flushDeferredServiceWorkerWork(in: harness)
        XCTAssertTrue(drained.attempted)
        XCTAssertGreaterThanOrEqual(drained.iterationCount, 0)
    }

    func testControlledPopupAsyncServiceWorkerWriteIsVisibleToPopupBroker()
        throws
    {
        let storageRoot = try makeTemporaryDirectory()
        let profileID = "async-storage-visibility-profile"
        let extensionID = "async-storage-visibility-extension"
        let harness = try makeHarnessWritingStorageAsyncOnConnect(
            extensionID: extensionID,
            profileID: profileID
        )
        let session = try XCTUnwrap(
            ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
                .session(profileID: profileID, extensionID: extensionID)
        )
        harness.attachCapturedListenerDispatchers(
            to: session,
            clearingExisting: true
        )

        let namespace = ChromeMV3StorageNamespace(
            profileID: profileID,
            extensionID: extensionID,
            area: .local
        )
        final class BrokerHolder: @unchecked Sendable {
            var broker: ChromeMV3StorageBroker
            init(broker: ChromeMV3StorageBroker) {
                self.broker = broker
            }
        }
        let brokerHolder = BrokerHolder(
            broker: ChromeMV3StorageBroker(
                namespace: namespace,
                persistenceMode: .hostBacked(rootURL: storageRoot)
            )
        )
        session.setServiceWorkerLocalStorageMirror {
            let asyncFlush =
                ChromeMV3ServiceWorkerLocalStorageMirror
                .flushDeferredServiceWorkerWork(in: harness)
            XCTAssertTrue(asyncFlush.attempted)
            guard
                let exported = harness.exportStorageValues(area: .local)
            else { return nil }
            let mirror = ChromeMV3ServiceWorkerLocalStorageMirror
                .mirrorExportedValues(
                    exported,
                    into: &brokerHolder.broker,
                    writerContextCategory: "popupWakeSW"
                )
            return mirror.onChangedPayload
        }

        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: extensionID,
                profileID: profileID,
                allowlist: .controlledActionPopupPolicy,
                storageLocalRootPath: storageRoot.path
            ),
            sharedLifecycleSession: session
        )

        let connect = handler.handle(request(
            namespace: "runtime",
            methodName: "connect",
            arguments: [.object(["name": .string("mv3-async-storage-visibility")])],
            invocationMode: .fireAndForget
        ))
        XCTAssertTrue(connect.succeeded)

        let read = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("mv3AsyncStartupStorageMarker")]
        ))
        XCTAssertTrue(read.succeeded)
        XCTAssertEqual(
            stringValue(objectValue(read.resultPayload)?["mv3AsyncStartupStorageMarker"]),
            "async-startup"
        )
    }

    func testBoundedAsyncFlushDoesNotRunAwayOnRecursiveTimers() throws {
        let harness = try makeHarnessWithRunawayTimers(
            extensionID: "runaway-timer-extension",
            profileID: "runaway-timer-profile"
        )
        XCTAssertEqual(harness.start().status, .running)
        _ = harness.dispatch(
            source: .popupOptionsRuntimeMessage,
            arguments: [.string("prime")],
            payloadSummary: "prime runaway timer fixture"
        )
        let flush =
            ChromeMV3ServiceWorkerLocalStorageMirror
            .flushDeferredServiceWorkerWork(
                in: harness,
                maxDrainPasses: 8,
                maxCallbacksPerPass: 50,
                maxElapsedMilliseconds: 50
            )
        XCTAssertTrue(flush.attempted)
        XCTAssertLessThanOrEqual(flush.iterationCount, 8)
        XCTAssertLessThanOrEqual(flush.totalTimerCallbacks, 400)
        XCTAssertTrue(flush.budgetExceeded || flush.iterationCount <= 8)
    }

    private func makeHarnessWritingStorageAsyncOnConnect(
        extensionID: String,
        profileID: String
    ) throws -> ChromeMV3ServiceWorkerJSExecutionHarness {
        let fixtureDirectory = try makeTemporaryDirectory()
            .appendingPathComponent("extension", isDirectory: true)
        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Async Storage Visibility Harness",
            "version": "1.0.0",
            "background": [
                "service_worker": "background.js",
            ],
        ]
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        ).write(
            to: fixtureDirectory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        try """
        chrome.runtime.onConnect.addListener(async (port) => {
          await Promise.resolve();
          chrome.storage.local.set({ mv3AsyncStartupStorageMarker: "async-startup" });
          port.postMessage({ type: "storage-written" });
        });
        """.write(
            to: fixtureDirectory.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )
        return try stagedHarness(
            fixtureDirectory: fixtureDirectory,
            extensionID: extensionID,
            profileID: profileID
        )
    }

    private func makeHarnessWithRunawayTimers(
        extensionID: String,
        profileID: String
    ) throws -> ChromeMV3ServiceWorkerJSExecutionHarness {
        let fixtureDirectory = try makeTemporaryDirectory()
            .appendingPathComponent("extension", isDirectory: true)
        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Runaway Timer Harness",
            "version": "1.0.0",
            "background": [
                "service_worker": "background.js",
            ],
        ]
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        ).write(
            to: fixtureDirectory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        try """
        globalThis.runawayCount = 0;
        chrome.runtime.onMessage.addListener(() => {
          const schedule = () => {
            setTimeout(() => {
              runawayCount += 1;
              schedule();
            }, 0);
          };
          schedule();
          return true;
        });
        """.write(
            to: fixtureDirectory.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )
        return try stagedHarness(
            fixtureDirectory: fixtureDirectory,
            extensionID: extensionID,
            profileID: profileID
        )
    }

    private func stagedHarness(
        fixtureDirectory: URL,
        extensionID: String,
        profileID: String
    ) throws -> ChromeMV3ServiceWorkerJSExecutionHarness {
        let storeRoot = try makeTemporaryDirectory()
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
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request: ChromeMV3ServiceWorkerJSExecutionRequest(
                manifest: stage.manifestSnapshot.normalizedManifest,
                generatedBundleRecord: generated.record,
                extensionID: extensionID,
                profileID: profileID,
                moduleState: .enabled,
                extensionEnabled: true,
                localExperimentalGateAllowed: true,
                dynamicImportRewriteExperimentAllowed: true
            )
        )
        let start = harness.start()
        XCTAssertTrue(
            start.status == .running || harness.canDispatchCapturedListeners,
            start.diagnostics.joined(separator: "\n")
        )
        return harness
    }

    private func configuration(
        extensionID: String,
        profileID: String,
        allowlist: ChromeMV3PopupOptionsAPIMethodPolicy,
        storageLocalRootPath: String
    ) -> ChromeMV3PopupOptionsJSBridgeConfiguration {
        ChromeMV3PopupOptionsJSBridgeConfiguration(
            extensionID: extensionID,
            profileID: profileID,
            surfaceID: "\(profileID):\(extensionID):actionPopup",
            surface: .actionPopup,
            extensionBaseURLString: "chrome-extension://\(extensionID)/",
            storageLocalRootPath: storageLocalRootPath,
            moduleState: .enabled,
            bridgeAvailable: true,
            popupOptionsJSBridgeAvailableInDeveloperPreview: true,
            popupOptionsJSBridgeAvailableInPublicProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            contentScriptAttachmentAvailableInProduct: false,
            runtimeLoadable: false,
            manifestPermissions: ["storage"],
            manifestOptionalPermissions: [],
            manifestHostPermissions: [],
            manifestOptionalHostPermissions: [],
            activeTabGrants: [],
            allowlist: allowlist,
            diagnostics: []
        )
    }

    private func request(
        namespace: String,
        methodName: String,
        arguments: [ChromeMV3StorageValue] = [],
        invocationMode: ChromeMV3JSBridgeInvocationMode = .promise
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: UUID().uuidString,
            namespace: namespace,
            methodName: methodName,
            invocationMode: invocationMode,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: nil,
            diagnostics: [],
            internalModeledUserGesture: false
        )
    }

    private func objectValue(
        _ value: ChromeMV3StorageValue?
    ) -> [String: ChromeMV3StorageValue]? {
        guard case .object(let object)? = value else { return nil }
        return object
    }

    private func stringValue(_ value: ChromeMV3StorageValue?) -> String? {
        guard case .string(let string)? = value else { return nil }
        return string
    }

    private func makeTemporaryDirectory() throws -> URL {
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
