import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3StorageBrokerTests: XCTestCase {
    func testStorageValueModelValidatesJSONCompatibleValuesAndEncoding()
        throws
    {
        let value = ChromeMV3StorageValue.object([
            "b": .string("second"),
            "a": .string("first"),
            "nested": .array([.bool(true), .null]),
        ])
        let sameValueDifferentOrder = ChromeMV3StorageValue.object([
            "nested": .array([.bool(true), .null]),
            "a": .string("first"),
            "b": .string("second"),
        ])
        let invalid = ChromeMV3StorageValue.object([
            "bad": .number(Double.nan),
        ])

        XCTAssertTrue(value.isJSONCompatible)
        XCTAssertEqual(
            try value.canonicalJSONString(),
            try sameValueDifferentOrder.canonicalJSONString()
        )
        XCTAssertLessThan(
            try XCTUnwrap(
                value.canonicalJSONString().range(of: "\"a\"")?.lowerBound
            ),
            try XCTUnwrap(
                value.canonicalJSONString().range(of: "\"b\"")?.lowerBound
            )
        )
        XCTAssertFalse(invalid.isJSONCompatible)
        XCTAssertEqual(invalid.validationDiagnostics.first?.code, .invalidValue)
    }

    func testStorageLocalSetGetRemoveClearAndChangeDiff() {
        var broker = storageBroker(area: .local)

        let set = broker.set([
            "token": .string("abc"),
            "count": .number(1),
        ])
        let get = broker.get(keys: ["token", "missing"])
        let remove = broker.remove(keys: ["token"])
        let clear = broker.clear()

        XCTAssertTrue(set.succeeded)
        XCTAssertEqual(set.changeSet.changedKeys, ["count", "token"])
        XCTAssertEqual(
            set.changeSet.changes.first { $0.key == "token" }?.newValue,
            .string("abc")
        )
        XCTAssertEqual(get.returnedValues, ["token": .string("abc")])
        XCTAssertTrue(remove.succeeded)
        XCTAssertEqual(remove.changeSet.changedKeys, ["token"])
        XCTAssertEqual(
            remove.changeSet.changes.first?.oldValue,
            .string("abc")
        )
        XCTAssertTrue(clear.succeeded)
        XCTAssertEqual(clear.changeSet.changedKeys, ["count"])
        XCTAssertTrue(broker.exportSnapshot().values.isEmpty)
        XCTAssertFalse(set.canWriteStorageNow)
        XCTAssertFalse(set.canDispatchStorageChangeEventNow)
        XCTAssertFalse(set.canWakeServiceWorkerNow)
        XCTAssertFalse(set.canLoadContextNow)
        XCTAssertFalse(set.runtimeLoadable)
    }

    func testStorageLocalGetBytesInUseIsDeterministic() {
        var first = storageBroker(area: .local)
        var second = storageBroker(area: .local)
        _ = first.set([
            "b": .object(["z": .string("last"), "a": .string("first")]),
            "a": .string("value"),
        ])
        _ = second.set([
            "a": .string("value"),
            "b": .object(["a": .string("first"), "z": .string("last")]),
        ])

        let firstBytes = first.getBytesInUse()
        let secondBytes = second.getBytesInUse()

        XCTAssertEqual(firstBytes.bytesInUse, secondBytes.bytesInUse)
        XCTAssertEqual(
            firstBytes.quotaEvaluation.itemByteUsage.map(\.key),
            ["a", "b"]
        )
        XCTAssertTrue(firstBytes.quotaEvaluation.withinQuota)
    }

    func testHostBackedBrokerNamespacesProfileExtensionAndArea() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let namespace = ChromeMV3StorageNamespace(
            profileID: "profile/A",
            extensionID: "extension:B",
            area: .local
        )
        var broker = ChromeMV3StorageBroker(
            namespace: namespace,
            persistenceMode: .hostBacked(rootURL: root)
        )

        _ = broker.set(["key": .string("value")])

        let snapshotURL = try XCTUnwrap(broker.snapshotURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
        XCTAssertTrue(snapshotURL.path.contains("profile%2FA"))
        XCTAssertTrue(snapshotURL.path.contains("extension%3AB"))
        XCTAssertTrue(snapshotURL.path.contains("/local/"))

        var reloaded = ChromeMV3StorageBroker(
            namespace: namespace,
            persistenceMode: .hostBacked(rootURL: root)
        )
        XCTAssertTrue(try reloaded.loadHostSnapshotIfPresent())
        XCTAssertEqual(reloaded.exportSnapshot().values, ["key": .string("value")])
    }

    func testSnapshotImportExportKeepsNamespaceBoundaries() {
        var local = storageBroker(area: .local)
        var otherProfile = ChromeMV3StorageBroker(
            namespace: ChromeMV3StorageNamespace(
                profileID: "other-profile",
                extensionID: "extension",
                area: .local
            )
        )
        _ = local.set(["key": .string("value")])

        let imported = otherProfile.importSnapshot(local.exportSnapshot())

        XCTAssertFalse(imported.succeeded)
        XCTAssertEqual(
            imported.errorDiagnostics.first?.code,
            .snapshotNamespaceMismatch
        )
        XCTAssertTrue(otherProfile.exportSnapshot().values.isEmpty)
    }

    func testStorageSessionPolicyAndCleanupAreRepresented() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var broker = ChromeMV3StorageBroker(
            namespace: ChromeMV3StorageNamespace(
                profileID: "profile",
                extensionID: "extension",
                area: .session
            ),
            persistenceMode: .hostBacked(rootURL: root)
        )

        let set = broker.set(["unlock": .bool(true)])
        let report = ChromeMV3StorageBrokerReadinessReportGenerator.makeReport(
            extensionID: "extension",
            profileID: "profile",
            storagePermissionDetected: true,
            passwordManagerLikeFixtureDetected: true
        )

        XCTAssertTrue(set.succeeded)
        XCTAssertNil(broker.snapshotURL)
        XCTAssertEqual(
            broker.areaRecord.persistencePolicy,
            .memoryOnlyExtensionSession
        )
        XCTAssertEqual(
            report.sessionPolicy.extensionDisableCleanupPolicy,
            "Clear session storage on extension disable, reload, update, or uninstall before any future runtime handle is exposed."
        )
        XCTAssertEqual(
            report.sessionPolicy.accessLevelDefault,
            .notExposedByDefault
        )
    }

    func testStorageSyncAndManagedPoliciesRemainUnavailable() {
        var sync = storageBroker(area: .sync)
        var managed = storageBroker(area: .managed)
        let report = ChromeMV3StorageBrokerReadinessReportGenerator.makeReport(
            extensionID: "extension",
            profileID: "profile",
            storagePermissionDetected: true
        )

        let syncSet = sync.set(["key": .string("value")])
        let managedGet = managed.getAll()

        XCTAssertFalse(syncSet.succeeded)
        XCTAssertFalse(managedGet.succeeded)
        XCTAssertEqual(
            report.syncPolicy.status,
            .deferredLocalOnlyFutureEmulation
        )
        XCTAssertFalse(report.syncPolicy.runtimeImplementedNow)
        XCTAssertFalse(report.syncPolicy.brokerModelOperationsAvailable)
        XCTAssertTrue(
            report.storageAreaSupportSummary.contains {
                $0.area == .managed
                    && $0.availabilityStatus == .unsupportedManagedPolicy
            }
        )
    }

    func testStorageOnChangedPayloadIsDeterministicButNotDispatched()
        throws
    {
        let namespace = ChromeMV3StorageNamespace(
            profileID: "profile",
            extensionID: "extension",
            area: .local
        )
        let first = ChromeMV3StorageChangeSet.make(
            namespace: namespace,
            oldValues: ["b": .string("old"), "a": .number(1)],
            newValues: ["b": .string("new"), "c": .bool(true)]
        )
        let second = ChromeMV3StorageChangeSet.make(
            namespace: namespace,
            oldValues: ["a": .number(1), "b": .string("old")],
            newValues: ["c": .bool(true), "b": .string("new")]
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.changedKeys, ["a", "b", "c"])
        XCTAssertFalse(first.futureOnChangedPayload.wouldDispatchNow)
        XCTAssertTrue(
            first.futureOnChangedPayload.listenerRegistrationRequired
        )
        XCTAssertTrue(first.futureOnChangedPayload.serviceWorkerWakeRequired)
        XCTAssertEqual(
            try ChromeMV3DeterministicJSON.encodedData(first),
            try ChromeMV3DeterministicJSON.encodedData(second)
        )
    }

    func testStorageReadinessReportKeepsRuntimeExposureBlocked()
        throws
    {
        let report = ChromeMV3StorageBrokerReadinessReportGenerator.makeReport(
            extensionID: "extension",
            profileID: "profile",
            storagePermissionDetected: true,
            passwordManagerLikeFixtureDetected: true,
            runtimeMessagingStillBlocked: true,
            nativeMessagingStillBlocked: true
        )
        let first = try ChromeMV3DeterministicJSON.encodedData(report)
        let second = try ChromeMV3DeterministicJSON.encodedData(report)

        XCTAssertEqual(first, second)
        XCTAssertTrue(report.brokerModelOperationsAvailable)
        XCTAssertFalse(report.canReadStorageNow)
        XCTAssertFalse(report.canWriteStorageNow)
        XCTAssertFalse(report.canDispatchStorageChangeEventNow)
        XCTAssertFalse(report.canWakeServiceWorkerNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertFalse(
            report.passwordManagerStorageSummary
                .passwordManagerStorageReady
        )
        XCTAssertTrue(
            report.passwordManagerStorageSummary
                .storageLocalModelAvailable
        )
        XCTAssertTrue(
            report.passwordManagerStorageSummary
                .storageSessionPolicyAvailable
        )
        XCTAssertEqual(
            report.storageAreaSupportSummary.map(\.area).sorted(),
            ChromeMV3StorageAreaKind.allCases.sorted()
        )
    }

    @MainActor
    func testSumiExtensionsModuleWritesStorageReadinessReportOnlyWhenEnabled()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writePasswordManagerLikeManifest(to: root)
        let contextReport = makeContextReadinessReport(root: root)
        try ChromeMV3ContextReadinessReportWriter.write(
            contextReport,
            toRewrittenBundleRoot: root
        )
        let prerequisites = try ChromeMV3RuntimeBridgePrerequisitesReportGenerator
            .makeReport(loadingContextReadinessReportFrom: root)
        try ChromeMV3RuntimeBridgePrerequisitesReportWriter.write(
            prerequisites,
            toRewrittenBundleRoot: root
        )
        let reportURL = root.appendingPathComponent(
            ChromeMV3StorageBrokerReadinessReportWriter.reportFileName
        )
        let disabledHarness = TestDefaultsHarness()
        defer { disabledHarness.reset() }
        let disabledRegistry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: disabledHarness.defaults)
        )
        let disabledModule = SumiExtensionsModule(
            moduleRegistry: disabledRegistry,
            browserConfiguration: BrowserConfiguration()
        )

        let disabledReport =
            disabledModule.chromeMV3StorageBrokerReadinessReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )

        XCTAssertNil(disabledReport)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path))

        let enabledHarness = TestDefaultsHarness()
        defer { enabledHarness.reset() }
        let enabledRegistry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: enabledHarness.defaults)
        )
        enabledRegistry.enable(.extensions)
        let enabledModule = SumiExtensionsModule(
            moduleRegistry: enabledRegistry,
            browserConfiguration: BrowserConfiguration()
        )

        let enabledReport = try XCTUnwrap(
            enabledModule.chromeMV3StorageBrokerReadinessReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        )
        let diagnostics = enabledModule.chromeMV3InventoryDiagnosticsIfEnabled(
            rootURL: root
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertEqual(
            diagnostics?.storageBrokerReadinessReportSummary,
            enabledReport.summary
        )
        XCTAssertFalse(enabledModule.hasLoadedRuntime)
        XCTAssertFalse(enabledReport.summary.canLoadContextNow)
        XCTAssertFalse(enabledReport.summary.runtimeLoadable)
    }

    func testRuntimeBridgeAndMessagingReportsIncludeStorageSummary()
        throws
    {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writePasswordManagerLikeManifest(to: root)
        let contextReport = makeContextReadinessReport(root: root)
        try ChromeMV3ContextReadinessReportWriter.write(
            contextReport,
            toRewrittenBundleRoot: root
        )
        let prerequisites = try ChromeMV3RuntimeBridgePrerequisitesReportGenerator
            .makeReport(loadingContextReadinessReportFrom: root)
        let readiness = ChromeMV3RuntimeBridgeReadinessReportGenerator
            .makeReport(
                prerequisitesReport: prerequisites,
                prerequisitesReportPath: root
                    .appendingPathComponent(
                        ChromeMV3RuntimeBridgePrerequisitesReportWriter
                            .reportFileName
                    )
                    .path,
                contextReadinessReport: contextReport
            )
        let messaging = ChromeMV3RuntimeMessagingContractReportGenerator
            .makeReport(prerequisitesReport: prerequisites)

        XCTAssertEqual(
            readiness.storageBrokerReadinessReportSummary?
                .storageSyncPolicy,
            .deferredLocalOnlyFutureEmulation
        )
        XCTAssertEqual(
            messaging.summary.storageBrokerReadinessReportSummary?
                .storageLocalModelAvailable,
            true
        )
        let dispatchFlag = try XCTUnwrap(
            readiness.storageBrokerReadinessReportSummary?
                .canDispatchStorageChangeEventNow
        )
        XCTAssertFalse(dispatchFlag)
        XCTAssertEqual(
            readiness.storageAPIOperationsReportSummary?
                .operationHandlerAvailableInModel,
            true
        )
        XCTAssertEqual(
            messaging.summary.storageAPIOperationsReportSummary?
                .jsRuntimeStorageExposureNow,
            false
        )
    }

    func testStorageAPIOperationGetSingleKeyReturnsResultEnvelope() {
        var broker = storageBroker(
            area: .local,
            initialValues: [
                "token": .string("abc"),
                "other": .number(1),
            ]
        )
        let input = storageAPIInput(
            operation: .get,
            invocationMode: .promise,
            keySelector: .singleString("token")
        )

        let result = ChromeMV3StorageAPIOperationHandler()
            .handle(input, broker: &broker)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.resultPayload.values, ["token": .string("abc")])
        XCTAssertEqual(result.normalizedKeySelector?.stableOrdering, ["token"])
        XCTAssertTrue(result.promiseBehavior.wouldResolve)
        XCTAssertFalse(result.callbackBehavior.wouldInvokeCallback)
        XCTAssertTrue(result.brokerOperationExecutedInModel)
        XCTAssertFalse(result.runtimeImplementedNow)
        XCTAssertFalse(result.jsRuntimeStorageExposureNow)
    }

    func testStorageAPIGetMultipleKeysDefaultsAndAllAreDeterministic()
        throws
    {
        var broker = storageBroker(
            area: .local,
            initialValues: [
                "b": .string("two"),
                "a": .string("one"),
            ]
        )
        let multiple = storageAPIInput(
            operation: .get,
            keySelector: .stringArray(["b", "a", "b"])
        )
        let defaults = storageAPIInput(
            operation: .get,
            keySelector: .defaults([
                "a": .string("default"),
                "missing": .bool(true),
            ])
        )
        let all = storageAPIInput(
            operation: .get,
            keySelector: .allKeys
        )
        let handler = ChromeMV3StorageAPIOperationHandler()

        let multipleResult = handler.handle(multiple, broker: &broker)
        let defaultsResult = handler.handle(defaults, broker: &broker)
        let allResult = handler.handle(all, broker: &broker)

        XCTAssertEqual(
            multipleResult.normalizedKeySelector?.stableOrdering,
            ["a", "b"]
        )
        XCTAssertEqual(
            multipleResult.normalizedKeySelector?.duplicateKeysDropped,
            ["b"]
        )
        XCTAssertEqual(
            multipleResult.resultPayload.values,
            ["a": .string("one"), "b": .string("two")]
        )
        XCTAssertEqual(
            defaultsResult.resultPayload.values,
            ["a": .string("one"), "missing": .bool(true)]
        )
        XCTAssertEqual(
            allResult.resultPayload.values.keys.sorted(),
            ["a", "b"]
        )
        XCTAssertEqual(
            try ChromeMV3DeterministicJSON.encodedData(multipleResult),
            try ChromeMV3DeterministicJSON.encodedData(multipleResult)
        )
    }

    func testStorageAPISetRemoveClearAndGetBytesUseBrokerModel() {
        var broker = storageBroker(
            area: .session,
            initialValues: [
                "unlock": .bool(true),
                "count": .number(3),
            ]
        )
        let handler = ChromeMV3StorageAPIOperationHandler()
        let set = handler.handle(
            storageAPIInput(
                area: .session,
                operation: .set,
                invocationMode: .callback,
                values: ["count": .number(4), "new": .string("value")],
                sourceContext: .serviceWorker
            ),
            broker: &broker
        )
        let bytes = handler.handle(
            storageAPIInput(
                area: .session,
                operation: .getBytesInUse,
                keySelector: .stringArray(["new", "count"]),
                sourceContext: .serviceWorker
            ),
            broker: &broker
        )
        let remove = handler.handle(
            storageAPIInput(
                area: .session,
                operation: .remove,
                keySelector: .singleString("unlock"),
                sourceContext: .serviceWorker
            ),
            broker: &broker
        )
        let clear = handler.handle(
            storageAPIInput(
                area: .session,
                operation: .clear,
                sourceContext: .serviceWorker
            ),
            broker: &broker
        )

        XCTAssertTrue(set.succeeded)
        XCTAssertEqual(set.changedKeys, ["count", "new"])
        XCTAssertTrue(set.callbackBehavior.wouldInvokeCallback)
        XCTAssertEqual(set.callbackBehavior.callbackPayload?.voidResult, true)
        XCTAssertGreaterThan(bytes.resultPayload.bytesInUse ?? 0, 0)
        XCTAssertEqual(remove.changedKeys, ["unlock"])
        XCTAssertEqual(clear.changedKeys, ["count", "new"])
        XCTAssertTrue(broker.exportSnapshot().values.isEmpty)
        XCTAssertTrue([set, remove, clear].allSatisfy {
            $0.generatedOnChangedPayload?.wouldDispatchNow == false
        })
    }

    func testStorageAPIInvalidKeyInvalidValueAndQuotaMapLastError() {
        var keyBroker = storageBroker(area: .local)
        var valueBroker = storageBroker(area: .local)
        var quotaBroker = storageBroker(area: .local)
        let handler = ChromeMV3StorageAPIOperationHandler()

        let invalidKey = handler.handle(
            storageAPIInput(
                operation: .get,
                invocationMode: .callback,
                keySelector: .invalidType("number")
            ),
            broker: &keyBroker
        )
        let invalidValue = handler.handle(
            storageAPIInput(
                operation: .set,
                invocationMode: .promise,
                values: ["bad": .number(.nan)]
            ),
            broker: &valueBroker
        )
        let quota = handler.handle(
            storageAPIInput(
                operation: .set,
                invocationMode: .promise,
                values: [
                    "blob": .string(
                        String(repeating: "x", count: 10_485_760)
                    ),
                ]
            ),
            broker: &quotaBroker
        )

        XCTAssertFalse(invalidKey.succeeded)
        XCTAssertEqual(invalidKey.futureLastErrorContract?.code, .invalidKey)
        XCTAssertTrue(invalidKey.callbackBehavior.wouldSetRuntimeLastError)
        XCTAssertFalse(invalidValue.succeeded)
        XCTAssertEqual(
            invalidValue.futureLastErrorContract?.code,
            .invalidValue
        )
        XCTAssertTrue(invalidValue.promiseBehavior.wouldReject)
        XCTAssertFalse(quota.succeeded)
        XCTAssertEqual(
            quota.futureLastErrorContract?.code,
            .quotaBytesExceeded
        )
        XCTAssertEqual(
            quota.futureLastErrorContract?.retryability,
            .retryAfterQuotaCleanup
        )
    }

    func testStorageAPIDisabledSyncManagedAndRuntimeExposureRemainBlocked() {
        var local = storageBroker(area: .local)
        var sync = storageBroker(area: .sync)
        var managed = storageBroker(area: .managed)
        let disabled = ChromeMV3StorageAPIOperationHandler(
            state: .disabledModule
        ).handle(
            storageAPIInput(operation: .get, keySelector: .singleString("a")),
            broker: &local
        )
        let syncResult = ChromeMV3StorageAPIOperationHandler().handle(
            storageAPIInput(
                area: .sync,
                operation: .get,
                keySelector: .singleString("a")
            ),
            broker: &sync
        )
        let managedResult = ChromeMV3StorageAPIOperationHandler().handle(
            storageAPIInput(
                area: .managed,
                operation: .get,
                keySelector: .allKeys
            ),
            broker: &managed
        )
        var runtimeBroker = storageBroker(area: .local)
        var runtimeState = ChromeMV3StorageAPIOperationHandlerState
            .enabledModelTestFixture
        runtimeState.requestedJSRuntimeExecution = true
        let runtimeExposure = ChromeMV3StorageAPIOperationHandler(
            state: runtimeState
        ).handle(
            storageAPIInput(operation: .get, keySelector: .singleString("a")),
            broker: &runtimeBroker
        )

        XCTAssertEqual(
            disabled.futureLastErrorContract?.code,
            .extensionDisabled
        )
        XCTAssertFalse(disabled.brokerOperationExecutedInModel)
        XCTAssertEqual(syncResult.futureLastErrorContract?.code, .syncUnavailable)
        XCTAssertFalse(syncResult.brokerOperationExecutedInModel)
        XCTAssertEqual(
            managedResult.futureLastErrorContract?.code,
            .areaUnsupported
        )
        XCTAssertEqual(
            runtimeExposure.futureLastErrorContract?.code,
            .operationNotImplementedForJSRuntime
        )
        XCTAssertFalse(runtimeExposure.jsRuntimeStorageExposureNow)
        XCTAssertFalse(runtimeExposure.canLoadContextNow)
        XCTAssertFalse(runtimeExposure.runtimeLoadable)
    }

    func testStorageAPIOnChangedPayloadGeneratedButNotDispatched() {
        var broker = storageBroker(
            area: .local,
            initialValues: ["a": .string("old")]
        )
        let result = ChromeMV3StorageAPIOperationHandler().handle(
            storageAPIInput(
                operation: .set,
                values: ["a": .string("new")]
            ),
            broker: &broker
        )
        let payload = result.generatedOnChangedPayload

        XCTAssertEqual(payload?.areaName, "local")
        XCTAssertEqual(payload?.changedKeys, ["a"])
        XCTAssertEqual(payload?.changes.first?.oldValue, .string("old"))
        XCTAssertEqual(payload?.changes.first?.newValue, .string("new"))
        XCTAssertFalse(payload?.wouldDispatchNow ?? true)
        XCTAssertTrue(payload?.listenerRegistrationRequired ?? false)
        XCTAssertTrue(payload?.serviceWorkerWakeRequired ?? false)
    }

    func testStorageAPIOperationsReportKeepsRuntimeBlocked()
        throws
    {
        let report = ChromeMV3StorageAPIOperationsReportGenerator.makeReport(
            extensionID: "extension",
            profileID: "profile",
            storagePermissionDetected: true,
            passwordManagerLikeFixtureDetected: true,
            runtimeMessagingStillBlocked: true,
            nativeMessagingStillBlocked: true
        )
        let first = try ChromeMV3DeterministicJSON.encodedData(report)
        let second = try ChromeMV3DeterministicJSON.encodedData(report)

        XCTAssertEqual(first, second)
        XCTAssertTrue(report.brokerModelOperationsAvailable)
        XCTAssertTrue(report.summary.operationHandlerAvailableInModel)
        XCTAssertEqual(
            report.summary.operationKindsModeled,
            [.clear, .get, .getBytesInUse, .remove, .set]
        )
        XCTAssertTrue(
            report.operationHandlerCoverage.contains {
                $0.area == .local
                    && $0.operation == .set
                    && $0.brokerOperationCanExecuteInModel
            }
        )
        XCTAssertTrue(
            report.operationHandlerCoverage.contains {
                $0.area == .sync
                    && $0.areaPolicyStatus == .deferred
            }
        )
        XCTAssertTrue(
            report.errorLastErrorCoverage.contains {
                $0.code == .operationNotImplementedForJSRuntime
            }
        )
        XCTAssertFalse(report.jsRuntimeStorageExposureNow)
        XCTAssertFalse(report.canDispatchStorageChangeEventNow)
        XCTAssertFalse(report.canWakeServiceWorkerNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertFalse(
            report.passwordManagerStorageAPISummary
                .passwordManagerStorageAPIReady
        )
        XCTAssertTrue(
            report.passwordManagerStorageAPISummary
                .storageLocalOperationHandlerAvailableInModel
        )
        XCTAssertTrue(
            report.passwordManagerStorageAPISummary
                .storageSessionOperationHandlerAvailableInModel
        )
        XCTAssertFalse(report.onChangedGenerationCoverage.isEmpty)
        XCTAssertTrue(
            report.onChangedGenerationCoverage.allSatisfy {
                $0.wouldDispatchNow == false
            }
        )
    }

    @MainActor
    func testSumiExtensionsModuleWritesStorageAPIOperationsReportOnlyWhenEnabled()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writePasswordManagerLikeManifest(to: root)
        let contextReport = makeContextReadinessReport(root: root)
        try ChromeMV3ContextReadinessReportWriter.write(
            contextReport,
            toRewrittenBundleRoot: root
        )
        let prerequisites = try ChromeMV3RuntimeBridgePrerequisitesReportGenerator
            .makeReport(loadingContextReadinessReportFrom: root)
        try ChromeMV3RuntimeBridgePrerequisitesReportWriter.write(
            prerequisites,
            toRewrittenBundleRoot: root
        )
        let reportURL = root.appendingPathComponent(
            ChromeMV3StorageAPIOperationsReportWriter.reportFileName
        )
        let disabledHarness = TestDefaultsHarness()
        defer { disabledHarness.reset() }
        let disabledRegistry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: disabledHarness.defaults)
        )
        let disabledModule = SumiExtensionsModule(
            moduleRegistry: disabledRegistry,
            browserConfiguration: BrowserConfiguration()
        )

        let disabledReport =
            disabledModule.chromeMV3StorageAPIOperationsReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )

        XCTAssertNil(disabledReport)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path))

        let enabledHarness = TestDefaultsHarness()
        defer { enabledHarness.reset() }
        let enabledRegistry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: enabledHarness.defaults)
        )
        enabledRegistry.enable(.extensions)
        let enabledModule = SumiExtensionsModule(
            moduleRegistry: enabledRegistry,
            browserConfiguration: BrowserConfiguration()
        )

        let enabledReport = try XCTUnwrap(
            enabledModule.chromeMV3StorageAPIOperationsReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        )
        let diagnostics = enabledModule.chromeMV3InventoryDiagnosticsIfEnabled(
            rootURL: root
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertEqual(
            diagnostics?.storageAPIOperationsReportSummary,
            enabledReport.summary
        )
        XCTAssertFalse(enabledModule.hasLoadedRuntime)
        XCTAssertFalse(enabledReport.summary.canLoadContextNow)
        XCTAssertFalse(enabledReport.summary.runtimeLoadable)
    }

    func testStorageSourceGuardsKeepRuntimeBoundariesAbsent() throws {
        let files = try Self.sourceFiles()
        let joined = files.map(\.contents).joined(separator: "\n")
        let boundaryGuardJoined = files
            .filter {
                $0.relativePath
                    != "Sumi/Models/Extension/ChromeMV3/ChromeMV3TabsScriptingJSMVP.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeJSMessagingMVP.swift"
                    && $0.relativePath
                        != "SumiTests/ChromeMV3RuntimeJSMessagingMVPTests.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3StorageLocalRuntime.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerSyntheticFixture.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionEventAPIsRuntime.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3SidePanelOffscreenIdentitySyntheticWebKitHarness.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3NativeMessagingInternalRuntime.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerRealPackageCompatibility.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3PopupOptionsJSBridge.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3ProductPopupOptionsUI.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3ContentScriptProductAttachment.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3PopupOptionsWebAssemblyStreamingCompatibilityShim.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3LivePopupProductPathTrace.swift"
                    && $0.relativePath
                        != "SumiTests/ChromeMV3ControlledPopupBaselineFixture.swift"
                    && $0.relativePath
                        != "SumiTests/ChromeMV3NativeMessagingInternalRuntimeTests.swift"
                    && $0.relativePath
                        != "SumiTests/ChromeMV3PopupOptionsJSBridgeTests.swift"
                    && $0.relativePath
                        != "SumiTests/ChromeMV3URLHubDeveloperPreviewTests.swift"
                    && $0.relativePath
                        != "SumiTests/ChromeMV3PasswordManagerRealPackageCompatibilityTests.swift"
            }
            .map(\.contents)
            .joined(separator: "\n")
        let forbidden = [
            "WKWebExtension" + "Context(",
            "load" + "ExtensionContext",
            "add" + "UserScript",
            "connect" + "Native",
            "Process" + "(",
            "DispatchSource" + "Ti" + "mer",
            "runtime" + "Loadable" + " = " + "tr" + "ue",
            "canCreate" + "ContextNow" + " = " + "tr" + "ue",
            "canLoad" + "ContextNow" + " = " + "tr" + "ue",
            "jsRuntimeStorage" + "ExposureNow" + " = " + "tr" + "ue",
            "canDispatchStorage" + "ChangeEventNow" + " = " + "tr" + "ue",
            "canWake" + "ServiceWorkerNow" + " = " + "tr" + "ue",
            "passwordManager" + "StorageReady" + " = " + "tr" + "ue",
            "passwordManager" + "StorageAPIReady" + " = " + "tr" + "ue",
        ]

        for pattern in forbidden {
            if pattern == "add" + "UserScript"
                || pattern == "connect" + "Native"
                || pattern == "Process" + "("
            {
                XCTAssertFalse(boundaryGuardJoined.contains(pattern), pattern)
            } else {
                XCTAssertFalse(joined.contains(pattern), pattern)
            }
        }
    }

    private func storageBroker(
        area: ChromeMV3StorageAreaKind
    ) -> ChromeMV3StorageBroker {
        storageBroker(area: area, initialValues: [:])
    }

    private func storageBroker(
        area: ChromeMV3StorageAreaKind,
        initialValues: [String: ChromeMV3StorageValue]
    ) -> ChromeMV3StorageBroker {
        ChromeMV3StorageBroker(
            namespace: ChromeMV3StorageNamespace(
                profileID: "profile",
                extensionID: "extension",
                area: area
            ),
            initialValues: initialValues
        )
    }

    private func storageAPIInput(
        area: ChromeMV3StorageAreaKind = .local,
        operation: ChromeMV3StorageOperationKind,
        invocationMode: ChromeMV3StorageAPIInvocationMode = .promise,
        keySelector: ChromeMV3StorageAPIKeySelector? = nil,
        values: [String: ChromeMV3StorageValue] = [:],
        sourceContext: ChromeMV3StorageAPISourceContext = .testFixture
    ) -> ChromeMV3StorageAPIOperationInput {
        ChromeMV3StorageAPIOperationInput(
            extensionID: "extension",
            profileID: "profile",
            area: area,
            operation: operation,
            invocationMode: invocationMode,
            keySelector: keySelector,
            values: values,
            sourceContext: sourceContext
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ChromeMV3StorageBrokerTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func writePasswordManagerLikeManifest(to root: URL) throws {
        let manifest = """
        {
          "manifest_version": 3,
          "name": "Password Storage Fixture",
          "version": "1.0",
          "permissions": ["storage", "nativeMessaging", "activeTab"],
          "host_permissions": ["https://example.com/*"],
          "background": { "service_worker": "service-worker.js" },
          "action": { "default_popup": "popup.html" },
          "content_scripts": [
            {
              "matches": ["https://example.com/*"],
              "js": ["content.js"]
            }
          ]
        }
        """
        try Data(manifest.utf8).write(
            to: root.appendingPathComponent("manifest.json")
        )
    }

    private func makeContextReadinessReport(
        root: URL
    ) -> ChromeMV3ContextReadinessReport {
        let candidate = ChromeMV3RewrittenVariantCandidate(
            id: "storage-fixture",
            generatedVariantRootPath: nil,
            rewrittenVariantRootPath: root.path,
            runtimeLoadabilityReportPath: nil,
            rewrittenManifestSHA256: nil,
            runtimeLoadabilityReportSHA256: nil,
            manifestVersion: 3,
            rewrittenVariantExists: true
        )
        return ChromeMV3ContextReadinessReportGenerator.makeReport(
            candidate: candidate,
            objectAcceptanceReport: nil,
            emptyControllerDiagnostics: nil,
            runtimeLoadabilityReport: nil
        )
    }

    private static func sourceFiles()
        throws -> [(relativePath: String, contents: String)]
    {
        let root = repoRoot
        let chromeDirectory = root.appendingPathComponent(
            "Sumi/Models/Extension/ChromeMV3",
            isDirectory: true
        )
        let testsDirectory = root.appendingPathComponent(
            "SumiTests",
            isDirectory: true
        )
        var urls: [URL] = []
        if let enumerator = FileManager.default.enumerator(
            at: chromeDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) {
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                urls.append(url)
            }
        }
        if let enumerator = FileManager.default.enumerator(
            at: testsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) {
            for case let url as URL in enumerator
            where url.pathExtension == "swift"
                && url.lastPathComponent.hasPrefix("ChromeMV3")
            {
                urls.append(url)
            }
        }
        return try urls.sorted { $0.path < $1.path }.map { url in
            let relativePath = String(url.path.dropFirst(root.path.count + 1))
            return (
                relativePath,
                try String(contentsOf: url, encoding: .utf8)
            )
        }
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
