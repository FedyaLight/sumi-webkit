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
        session.setServiceWorkerLocalStorageMirror { popupBroker in
            guard
                let exported = harness.exportStorageValues(area: .local)
            else { return .empty }
            return ChromeMV3ServiceWorkerLocalStorageMirror
                .reconcileServiceWorkerExportIntoBrokers(
                    exported,
                    hostBackedBroker: &brokerHolder.broker,
                    popupBroker: &popupBroker,
                    writerContextCategory: "popupWakeSW"
                )
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

    func testLazySessionProviderMirrorsAsyncServiceWorkerWriteOnStorageRead()
        throws
    {
        let storageRoot = try makeTemporaryDirectory()
        let profileID = "lazy-async-storage-profile"
        let extensionID = "lazy-async-storage-extension"
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
        try registerAsyncStorageMirror(
            harness: harness,
            session: session,
            storageRoot: storageRoot,
            profileID: profileID,
            extensionID: extensionID
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: extensionID,
                profileID: profileID,
                allowlist: .controlledActionPopupPolicy,
                storageLocalRootPath: storageRoot.path
            ),
            sharedLifecycleSessionProvider: { session }
        )

        let connect = handler.handle(request(
            namespace: "runtime",
            methodName: "connect",
            arguments: [.object(["name": .string("lazy-async-storage")])],
            invocationMode: .fireAndForget
        ))
        XCTAssertTrue(connect.succeeded)
        XCTAssertTrue(
            connect.diagnostics.contains("serviceWorkerStorageMirror=applied")
                || connect.onChangedPayload != nil
        )

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

    func testStorageReadBeforeConnectMirrorIsEmptyAfterConnectReadIsPopulated()
        throws
    {
        let storageRoot = try makeTemporaryDirectory()
        let profileID = "ordering-async-storage-profile"
        let extensionID = "ordering-async-storage-extension"
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
        try registerAsyncStorageMirror(
            harness: harness,
            session: session,
            storageRoot: storageRoot,
            profileID: profileID,
            extensionID: extensionID
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: extensionID,
                profileID: profileID,
                allowlist: .controlledActionPopupPolicy,
                storageLocalRootPath: storageRoot.path
            ),
            sharedLifecycleSessionProvider: { session }
        )

        let beforeConnect = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("mv3AsyncStartupStorageMarker")]
        ))
        XCTAssertTrue(beforeConnect.succeeded)
        XCTAssertNil(
            objectValue(beforeConnect.resultPayload)?["mv3AsyncStartupStorageMarker"]
        )

        let connect = handler.handle(request(
            namespace: "runtime",
            methodName: "connect",
            arguments: [.object(["name": .string("ordering-async-storage")])],
            invocationMode: .fireAndForget
        ))
        XCTAssertTrue(connect.succeeded)

        let afterConnect = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("mv3AsyncStartupStorageMarker")]
        ))
        XCTAssertTrue(afterConnect.succeeded)
        XCTAssertEqual(
            stringValue(
                objectValue(afterConnect.resultPayload)?[
                    "mv3AsyncStartupStorageMarker"
                ]
            ),
            "async-startup"
        )
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
        try registerAsyncStorageMirror(
            harness: harness,
            session: session,
            storageRoot: storageRoot,
            profileID: profileID,
            extensionID: extensionID
        )

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

    func testLazyControlledPopupPathMirrorsIntoPopupBrokerOnStorageGetAfterAsyncWrite()
        throws
    {
        let storageRoot = try makeTemporaryDirectory()
        let profileID = "live-path-mirror-profile"
        let extensionID = "live-path-mirror-extension"
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
        try registerAsyncStorageMirror(
            harness: harness,
            session: session,
            storageRoot: storageRoot,
            profileID: profileID,
            extensionID: extensionID
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: extensionID,
                profileID: profileID,
                allowlist: .controlledActionPopupPolicy,
                storageLocalRootPath: storageRoot.path
            ),
            sharedLifecycleSessionProvider: { session }
        )

        let connect = handler.handle(request(
            namespace: "runtime",
            methodName: "connect",
            arguments: [.object(["name": .string("live-path-mirror")])],
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
            stringValue(
                objectValue(read.resultPayload)?["mv3AsyncStartupStorageMarker"]
            ),
            "async-startup"
        )
        let snapshot = handler.diagnosticsSnapshot
        XCTAssertTrue(
            snapshot.diagnostics.contains(
                "storageMirrorPath.storageGetMirrorAttemptedCategory=attempted"
            )
        )
        XCTAssertTrue(
            snapshot.diagnostics.contains(
                "storageMirrorPath.mirrorCalledFromStorageGetCategory=called"
            )
        )
        XCTAssertTrue(
            snapshot.diagnostics.contains(
                "storageMirrorPath.lazySharedSessionResolvedCategory=resolved"
            )
        )
        XCTAssertTrue(
            snapshot.diagnostics.contains {
                $0.hasPrefix(
                    "storageMirrorPath.mirrorChangedKeyCountBucket="
                ) && $0 != "storageMirrorPath.mirrorChangedKeyCountBucket=0"
            }
                || snapshot.diagnostics.contains(
                    "storageMirrorPath.popupReadAfterMirrorCategory=readPopulatedAfterMirror"
                )
        )
    }

    func testSameLifecycleSessionCapturesAndMirrorsServiceWorkerWrite() throws {
        let storageRoot = try makeTemporaryDirectory()
        let profileID = "same-session-mirror-profile"
        let extensionID = "same-session-mirror-extension"
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
        try registerAsyncStorageMirror(
            harness: harness,
            session: session,
            storageRoot: storageRoot,
            profileID: profileID,
            extensionID: extensionID
        )
        var resolvedSessions: [String] = []
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: extensionID,
                profileID: profileID,
                allowlist: .controlledActionPopupPolicy,
                storageLocalRootPath: storageRoot.path
            ),
            sharedLifecycleSessionProvider: {
                resolvedSessions.append(session.key.lifecycleSessionID)
                return session
            }
        )

        _ = handler.handle(request(
            namespace: "runtime",
            methodName: "connect",
            arguments: [.object(["name": .string("same-session")])],
            invocationMode: .fireAndForget
        ))
        let read = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("mv3AsyncStartupStorageMarker")]
        ))
        XCTAssertEqual(resolvedSessions.count, 1)
        XCTAssertEqual(resolvedSessions.first, session.key.lifecycleSessionID)
        XCTAssertEqual(
            stringValue(
                objectValue(read.resultPayload)?["mv3AsyncStartupStorageMarker"]
            ),
            "async-startup"
        )
    }

    func testMirroredWriteDispatchesStorageOnChangedToPopupListeners() throws {
        let storageRoot = try makeTemporaryDirectory()
        let profileID = "mirror-onchanged-profile"
        let extensionID = "mirror-onchanged-extension"
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
        try registerAsyncStorageMirror(
            harness: harness,
            session: session,
            storageRoot: storageRoot,
            profileID: profileID,
            extensionID: extensionID
        )
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
            arguments: [.object(["name": .string("mirror-onchanged")])],
            invocationMode: .fireAndForget
        ))
        XCTAssertTrue(connect.succeeded)
        XCTAssertNotNil(connect.onChangedPayload)
        XCTAssertTrue(connect.onChangedPayload?.changedKeys.isEmpty == false)
        let read = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("mv3AsyncStartupStorageMarker")]
        ))
        XCTAssertTrue(read.succeeded)
        XCTAssertEqual(
            stringValue(
                objectValue(read.resultPayload)?["mv3AsyncStartupStorageMarker"]
            ),
            "async-startup"
        )
        XCTAssertGreaterThan(
            handler.diagnosticsSnapshot.storageOnChangedPayloadCount,
            0
        )
    }

    func testDisabledStorageReadDoesNotWakeSharedLifecycleSession() throws {
        let storageRoot = try makeTemporaryDirectory()
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: "guard-extension",
                profileID: "guard-profile",
                allowlist: .defaultPolicy,
                storageLocalRootPath: storageRoot.path
            )
        )
        let read = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("fixtureMarker")]
        ))
        XCTAssertTrue(read.succeeded)
        XCTAssertFalse(
            handler.diagnosticsSnapshot.diagnostics.contains {
                $0.hasPrefix(
                    "storageMirrorPath.lazySharedSessionWakeAttemptedCategory=attempted"
                )
            }
        )
        XCTAssertFalse(
            handler.diagnosticsSnapshot.diagnostics.contains {
                $0.hasPrefix(
                    "storageMirrorPath.mirrorCalledFromStorageGetCategory=called"
                )
            }
        )
    }

    func testStalePopupBrokerHydratesFromExportWhenHostBackedImportHasNoChanges()
        throws
    {
        let storageRoot = try makeTemporaryDirectory()
        let profileID = "stale-hydration-profile"
        let extensionID = "stale-hydration-extension"
        let namespace = ChromeMV3StorageNamespace(
            profileID: profileID,
            extensionID: extensionID,
            area: .local
        )
        let harness = try makeHarnessExportingSeededStorage(
            extensionID: extensionID,
            profileID: profileID,
            seededValues: [
                "mv3StaleHydrationMarker": .string("from-sw"),
            ]
        )
        let session = try XCTUnwrap(
            ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
                .session(profileID: profileID, extensionID: extensionID)
        )
        harness.attachCapturedListenerDispatchers(
            to: session,
            clearingExisting: true
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
        session.setServiceWorkerLocalStorageMirror { popupBroker in
            guard
                let exported = harness.exportStorageValues(area: .local)
            else { return .empty }
            return ChromeMV3ServiceWorkerLocalStorageMirror
                .reconcileServiceWorkerExportIntoBrokers(
                    exported,
                    hostBackedBroker: &brokerHolder.broker,
                    popupBroker: &popupBroker,
                    writerContextCategory: "popupWakeSW"
                )
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
        let seededValues: [String: ChromeMV3StorageValue] = [
            "mv3StaleHydrationMarker": .string("from-sw"),
        ]
        _ = ChromeMV3ServiceWorkerLocalStorageMirror.mirrorExportedValues(
            seededValues,
            into: &brokerHolder.broker,
            writerContextCategory: "testSeed"
        )
        let read = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("mv3StaleHydrationMarker")]
        ))
        XCTAssertTrue(read.succeeded)
        XCTAssertEqual(
            stringValue(
                objectValue(read.resultPayload)?["mv3StaleHydrationMarker"]
            ),
            "from-sw"
        )
        let snapshot = handler.diagnosticsSnapshot
        XCTAssertTrue(
            snapshot.diagnostics.contains(
                "storageMirrorPath.hostBackedImportSnapshotCategory=noChangesImported"
            )
                || snapshot.diagnostics.contains(
                    "storageMirrorPath.popupHydrationCategory=alreadyCurrent"
                )
        )
        XCTAssertTrue(
            snapshot.diagnostics.contains(
                "storageMirrorPath.storageGetResponseContainsMirroredValueCategory=containsMirroredValue"
            )
        )
        XCTAssertTrue(
            snapshot.diagnostics.contains {
                $0.hasPrefix(
                    "storageMirrorPath.popupBrokerImportedExportedValueCountBucket="
                ) && $0 != "storageMirrorPath.popupBrokerImportedExportedValueCountBucket=0"
            }
                || snapshot.diagnostics.contains(
                    "storageMirrorPath.popupHydrationCategory=alreadyCurrent"
                )
        )
    }

    func testAlreadySyncedBrokersDoNotDispatchDuplicateStorageOnChangedOnStorageGet()
        throws
    {
        let storageRoot = try makeTemporaryDirectory()
        let profileID = "no-duplicate-onchanged-profile"
        let extensionID = "no-duplicate-onchanged-extension"
        let harness = try makeHarnessExportingSeededStorage(
            extensionID: extensionID,
            profileID: profileID,
            seededValues: [
                "mv3DuplicateOnChangedMarker": .string("stable"),
            ]
        )
        let session = try XCTUnwrap(
            ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
                .session(profileID: profileID, extensionID: extensionID)
        )
        harness.attachCapturedListenerDispatchers(
            to: session,
            clearingExisting: true
        )
        try registerAsyncStorageMirror(
            harness: harness,
            session: session,
            storageRoot: storageRoot,
            profileID: profileID,
            extensionID: extensionID
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: extensionID,
                profileID: profileID,
                allowlist: .controlledActionPopupPolicy,
                storageLocalRootPath: storageRoot.path
            ),
            sharedLifecycleSession: session
        )
        _ = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("mv3DuplicateOnChangedMarker")]
        ))
        let onChangedBefore =
            handler.diagnosticsSnapshot.storageOnChangedPayloadCount
        _ = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("mv3DuplicateOnChangedMarker")]
        ))
        XCTAssertEqual(
            handler.diagnosticsSnapshot.storageOnChangedPayloadCount,
            onChangedBefore
        )
    }

    func testStoreBrokerAlreadySyncedStillMirrorsIntoSeparatePopupBrokerOnStorageGet()
        throws
    {
        let storageRoot = try makeTemporaryDirectory()
        let profileID = "dual-broker-mirror-profile"
        let extensionID = "dual-broker-mirror-extension"
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
        try registerAsyncStorageMirror(
            harness: harness,
            session: session,
            storageRoot: storageRoot,
            profileID: profileID,
            extensionID: extensionID
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: extensionID,
                profileID: profileID,
                allowlist: .controlledActionPopupPolicy,
                storageLocalRootPath: storageRoot.path
            ),
            sharedLifecycleSession: session
        )

        _ = handler.handle(request(
            namespace: "runtime",
            methodName: "connect",
            arguments: [.object(["name": .string("dual-broker")])],
            invocationMode: .fireAndForget
        ))

        let read = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("mv3AsyncStartupStorageMarker")]
        ))
        XCTAssertEqual(
            stringValue(
                objectValue(read.resultPayload)?["mv3AsyncStartupStorageMarker"]
            ),
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

    private func makeHarnessExportingSeededStorage(
        extensionID: String,
        profileID: String,
        seededValues: [String: ChromeMV3StorageValue]
    ) throws -> ChromeMV3ServiceWorkerJSExecutionHarness {
        let fixtureDirectory = try makeTemporaryDirectory()
            .appendingPathComponent("extension", isDirectory: true)
        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Seeded Storage Export Harness",
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
          port.postMessage({ type: "seeded-storage-ready" });
        });
        """.write(
            to: fixtureDirectory.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )
        let harness = try stagedHarness(
            fixtureDirectory: fixtureDirectory,
            extensionID: extensionID,
            profileID: profileID
        )
        XCTAssertTrue(
            ChromeMV3ServiceWorkerLocalStorageMirror.seedBrokerSnapshot(
                seededValues,
                into: harness,
                area: .local
            )
        )
        return harness
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

    private func registerAsyncStorageMirror(
        harness: ChromeMV3ServiceWorkerJSExecutionHarness,
        session: ChromeMV3ServiceWorkerSharedLifecycleSession,
        storageRoot: URL,
        profileID: String,
        extensionID: String
    ) throws {
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
        session.setServiceWorkerLocalStorageMirror { popupBroker in
            let asyncFlush =
                ChromeMV3ServiceWorkerLocalStorageMirror
                .flushDeferredServiceWorkerWork(in: harness)
            XCTAssertTrue(asyncFlush.attempted)
            guard
                let exported = harness.exportStorageValues(area: .local)
            else { return .empty }
            return ChromeMV3ServiceWorkerLocalStorageMirror
                .reconcileServiceWorkerExportIntoBrokers(
                    exported,
                    hostBackedBroker: &brokerHolder.broker,
                    popupBroker: &popupBroker,
                    writerContextCategory: "popupWakeSW"
                )
        }
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
