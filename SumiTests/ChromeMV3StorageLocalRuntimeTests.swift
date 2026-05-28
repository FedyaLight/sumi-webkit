import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3StorageLocalRuntimeTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testInternalRuntimeStateOwnerPersistsAndIsolatesProfileExtensionNamespace()
        throws
    {
        let root = try temporaryDirectory(named: "runtime-state")
        let configuration =
            ChromeMV3StorageLocalRuntimeConfiguration.syntheticHarness(
                extensionID: "storage-extension",
                profileID: "profile-a"
            )
        let owner = ChromeMV3StorageLocalRuntimeStateOwner(
            configuration: configuration,
            persistenceRootURL: root
        )
        let handler = ChromeMV3StorageLocalJSBridgeHandler(
            configuration: configuration,
            runtimeStateOwner: owner
        )

        let set = handler.handle(
            request(
                "local.set",
                invocationMode: .promise,
                arguments: [
                    .object([
                        "token": .string("abc"),
                        "nested": .object([
                            "ok": .bool(true),
                            "list": .array([.number(1), .null]),
                        ]),
                    ]),
                ]
            )
        )

        XCTAssertTrue(set.succeeded)
        XCTAssertEqual(set.storageStateSummary.keys, ["nested", "token"])
        XCTAssertEqual(set.onChangedPayload?.areaName, "local")
        XCTAssertEqual(
            set.onChangedPayload?.serviceWorkerWakeRequired,
            false
        )

        let reloadedOwner = ChromeMV3StorageLocalRuntimeStateOwner(
            configuration: configuration,
            persistenceRootURL: root
        )
        XCTAssertTrue(try reloadedOwner.loadHostSnapshotIfPresent())
        let reloadedHandler = ChromeMV3StorageLocalJSBridgeHandler(
            configuration: configuration,
            runtimeStateOwner: reloadedOwner
        )
        let get = reloadedHandler.handle(
            request(
                "local.get",
                invocationMode: .promise,
                arguments: [.string("token")]
            )
        )

        XCTAssertEqual(
            object(get.resultPayload)?["token"],
            .string("abc")
        )

        let otherConfiguration =
            ChromeMV3StorageLocalRuntimeConfiguration.syntheticHarness(
                extensionID: "storage-extension",
                profileID: "profile-b"
            )
        let otherOwner = ChromeMV3StorageLocalRuntimeStateOwner(
            configuration: otherConfiguration,
            persistenceRootURL: root
        )
        XCTAssertFalse(try otherOwner.loadHostSnapshotIfPresent())
        XCTAssertTrue(otherOwner.exportSnapshot().values.isEmpty)
        XCTAssertNotEqual(
            owner.snapshot.namespace.namespaceID,
            otherOwner.snapshot.namespace.namespaceID
        )
    }

    func testStorageLocalShimSourceIsControlledAndLocalOnly() {
        let configuration =
            ChromeMV3StorageLocalRuntimeConfiguration.syntheticHarness()
        let source = ChromeMV3StorageLocalJSShimSource.source(
            configuration: configuration
        )
        let coverage = ChromeMV3StorageLocalJSShimSource.coverage

        XCTAssertEqual(coverage.exposedChromeNamespaces, ["runtime", "storage"])
        XCTAssertEqual(coverage.storageAreas, ["local"])
        XCTAssertEqual(coverage.localMethods.sorted(), [
            "clear",
            "get",
            "getBytesInUse",
            "remove",
            "set",
        ])
        XCTAssertEqual(coverage.storageEvents, ["onChanged"])
        XCTAssertTrue(
            source.contains("Object.defineProperty(storage, \"local\"")
        )
        XCTAssertTrue(
            source.contains("Object.defineProperty(storage, \"onChanged\"")
        )
        XCTAssertFalse(
            source.contains("Object.defineProperty(storage, \"sync\"")
        )
        XCTAssertFalse(
            source.contains("Object.defineProperty(chromeObject, \"tabs\"")
        )
        XCTAssertFalse(
            source.contains("Object.defineProperty(chromeObject, \"permissions\"")
        )
        XCTAssertFalse(
            source.contains("Object.defineProperty(chromeObject, \"nativeMessaging\"")
        )
    }

    func testStorageBridgeRoutesGetSetRemoveClearAndBytesToRuntimeState() {
        let handler = ChromeMV3StorageLocalJSBridgeHandler(
            configuration: .syntheticHarness()
        )
        let set = handler.handle(
            request(
                "local.set",
                invocationMode: .callback,
                arguments: [
                    .object([
                        "alpha": .string("one"),
                        "beta": .number(2),
                        "json": .object([
                            "array": .array([.bool(true), .null]),
                        ]),
                    ]),
                ]
            )
        )
        let get = handler.handle(
            request(
                "local.get",
                invocationMode: .promise,
                arguments: [
                    .object([
                        "alpha": .string("default"),
                        "missing": .bool(false),
                    ]),
                ]
            )
        )
        let bytes = handler.handle(
            request(
                "local.getBytesInUse",
                invocationMode: .promise,
                arguments: [.array([.string("alpha"), .string("json")])]
            )
        )
        let remove = handler.handle(
            request(
                "local.remove",
                invocationMode: .callback,
                arguments: [.string("beta")]
            )
        )
        let clear = handler.handle(
            request("local.clear", invocationMode: .promise)
        )

        XCTAssertTrue(set.succeeded)
        XCTAssertEqual(set.storageOperationRecord.changedKeys, [
            "alpha",
            "beta",
            "json",
        ])
        XCTAssertTrue(set.callbackWouldSetLastError == false)
        XCTAssertEqual(
            object(get.resultPayload)?["alpha"],
            .string("one")
        )
        XCTAssertEqual(
            object(get.resultPayload)?["missing"],
            .bool(false)
        )
        XCTAssertGreaterThan(number(bytes.resultPayload) ?? 0, 0)
        XCTAssertEqual(remove.onChangedPayload?.changedKeys, ["beta"])
        XCTAssertTrue(clear.succeeded)
        XCTAssertTrue(handler.runtimeStateOwner.exportSnapshot().values.isEmpty)
        XCTAssertFalse(set.storageJSBridgeAvailableInProduct)
        XCTAssertFalse(set.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(set.serviceWorkerWakeAvailable)
        XCTAssertFalse(set.runtimeLoadable)
    }

    func testStorageBridgeInvalidInputsSyncPolicyAndDisabledGate()
        throws
    {
        let handler = ChromeMV3StorageLocalJSBridgeHandler(
            configuration: .syntheticHarness()
        )
        let invalidKey = handler.handle(
            request(
                "local.get",
                invocationMode: .callback,
                arguments: [.number(1)]
            )
        )
        let invalidValue = handler.handle(
            request(
                "local.set",
                invocationMode: .promise,
                arguments: [.null]
            )
        )
        let sync = handler.handle(
            request("sync.get", invocationMode: .promise)
        )
        let disabledConfiguration =
            ChromeMV3StorageLocalRuntimeConfiguration.syntheticHarness(
                moduleState: .disabled
            )
        let disabled = ChromeMV3StorageLocalJSBridgeHandler(
            configuration: disabledConfiguration
        ).handle(request("local.get", invocationMode: .callback))

        XCTAssertFalse(invalidKey.succeeded)
        XCTAssertEqual(
            invalidKey.lastErrorCode,
            ChromeMV3JSBridgeErrorCode.invalidArguments.rawValue
        )
        XCTAssertTrue(invalidKey.callbackWouldSetLastError)

        XCTAssertFalse(invalidValue.succeeded)
        XCTAssertEqual(
            invalidValue.lastErrorCode,
            ChromeMV3JSBridgeErrorCode.invalidArguments.rawValue
        )
        XCTAssertTrue(invalidValue.promiseWouldReject)

        XCTAssertFalse(sync.succeeded)
        XCTAssertEqual(
            sync.lastErrorCode,
            ChromeMV3StorageErrorCode.syncUnavailable.rawValue
        )
        XCTAssertTrue(sync.promiseWouldReject)

        XCTAssertFalse(disabled.succeeded)
        XCTAssertEqual(
            disabled.lastErrorCode,
            ChromeMV3JSBridgeErrorCode.extensionDisabled.rawValue
        )
        XCTAssertFalse(
            disabled.storageImplementationAvailableInInternalRuntime
        )

        let report =
            ChromeMV3StorageLocalImplementationReportGenerator.makeReport()
        XCTAssertEqual(
            report.storageSyncPolicy.status,
            .deferredLocalOnlyFutureEmulation
        )
        XCTAssertTrue(
            report.quotaErrorDiagnostics.contains {
                $0.code == .quotaBytesExceeded
            }
        )
        XCTAssertEqual(
            try ChromeMV3DeterministicJSON.encodedData(report),
            try ChromeMV3DeterministicJSON.encodedData(report)
        )
    }

    @MainActor
    func testModuleWritesStorageLocalReportOnlyWhenEnabled()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }

        let root = try temporaryDirectory(named: "module-report")
        let reportURL = root.appendingPathComponent(
            ChromeMV3StorageLocalImplementationReportWriter.reportFileName
        )
        let disabled = try makeModule(enabled: false)

        let disabledReport =
            disabled.chromeMV3StorageLocalImplementationReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        let disabledWebKitReport =
            await disabled
            .chromeMV3StorageLocalWebKitSyntheticHarnessReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )

        XCTAssertNil(disabledReport)
        XCTAssertNil(disabledWebKitReport)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path))

        let enabled = try makeModule(enabled: true)
        let report = try XCTUnwrap(
            enabled.chromeMV3StorageLocalImplementationReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        )
        let decoded = try JSONDecoder().decode(
            ChromeMV3StorageLocalImplementationReport.self,
            from: Data(contentsOf: reportURL)
        )
        let diagnostics = enabled.chromeMV3InventoryDiagnosticsIfEnabled(
            rootURL: root
        )

        XCTAssertEqual(decoded.id, report.id)
        XCTAssertTrue(report.storageImplementationAvailableInInternalRuntime)
        XCTAssertTrue(report.storageJSBridgeAvailableInSyntheticHarness)
        XCTAssertFalse(report.storageJSBridgeAvailableInProduct)
        XCTAssertFalse(report.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(report.serviceWorkerWakeAvailable)
        XCTAssertFalse(report.nativeMessagingAvailable)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertEqual(
            diagnostics?.storageLocalImplementationReportSummary,
            report.summary
        )

        let optionalWebKitReport = await enabled
            .chromeMV3StorageLocalWebKitSyntheticHarnessReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        let webKitReport = try XCTUnwrap(
            optionalWebKitReport
        )
        XCTAssertTrue(
            webKitReport.summary
                .storageJSExecutedInWebKitSyntheticHarness
        )
        XCTAssertTrue(
            webKitReport.summary
                .storageOnChangedObservedOrDiagnosed
        )
        XCTAssertFalse(enabled.hasLoadedRuntime)
    }

    @MainActor
    func testWebKitSyntheticHarnessExercisesStorageLocalCalls()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 WebKit harness requires macOS 15.5.")
        }
        let result = await ChromeMV3StorageLocalJSSyntheticHarness.run(
            scriptBody:
                ChromeMV3StorageLocalJSSyntheticHarness
                .reportVerificationScriptBody
        )

        XCTAssertTrue(
            result.scriptEvaluationSucceeded,
            result.diagnostics.joined(separator: "\n")
        )
        let object = try XCTUnwrap(
            try decodedObject(result.scriptResultJSON)
        )

        XCTAssertEqual(
            object["exposedNamespaces"] as? [String],
            ["runtime", "storage"]
        )
        XCTAssertEqual(object["tabsMissing"] as? Bool, true)
        XCTAssertEqual(object["permissionsMissing"] as? Bool, true)
        XCTAssertEqual(object["nativeMessagingMissing"] as? Bool, true)
        XCTAssertEqual(object["storageSyncMissing"] as? Bool, true)
        for key in [
            "getStringCallbackOK",
            "getArrayCallbackOK",
            "getDefaultsCallbackOK",
            "getAllPromiseOK",
            "setCallbackOK",
            "setPromiseOK",
            "removeCallbackOK",
            "removePromiseOK",
            "clearCallbackOK",
            "clearPromiseOK",
            "getBytesInUseCallbackOK",
            "getBytesInUsePromiseOK",
            "invalidKeyLastErrorOK",
            "invalidValueLastErrorOK",
            "callbackLastErrorScopedOK",
            "promiseRejectsOnErrorOK",
            "onChangedListenerOK",
            "onChangedRemoveListenerOK",
            "onChangedHasListenerOK",
            "storageSyncDeferredOrUnsupportedOK",
        ] {
            XCTAssertEqual(object[key] as? Bool, true, key)
        }
        XCTAssertTrue(result.webKitExecutionSummary.getStringCallbackExecuted)
        XCTAssertTrue(result.webKitExecutionSummary.getAllPromiseExecuted)
        XCTAssertTrue(result.webKitExecutionSummary.setCallbackExecuted)
        XCTAssertTrue(result.webKitExecutionSummary.setPromiseExecuted)
        XCTAssertTrue(result.webKitExecutionSummary.removeCallbackExecuted)
        XCTAssertTrue(result.webKitExecutionSummary.clearPromiseExecuted)
        XCTAssertTrue(
            result.webKitExecutionSummary
                .getBytesInUsePromiseExecuted
        )
        XCTAssertTrue(result.webKitExecutionSummary.onChangedListenerObserved)
        XCTAssertTrue(result.webKitExecutionSummary.callbackLastErrorScoped)
        XCTAssertTrue(result.webKitExecutionSummary.promiseRejectsOnError)
        let harnessDebugSummary = [
            "handledRequestCount=\(result.handledRequestCount)",
            "storageOperationRequestCount=\(result.storageOperationRequestCount)",
            "rejectedRequestCount=\(result.rejectedRequestCount)",
            "operationRecordCount=\(result.storageStateSummary.operationRecordCount)",
            "onChangedPayloadCount=\(result.storageStateSummary.onChangedPayloadCount)",
            "scriptResultJSON=\(result.scriptResultJSON ?? "nil")",
            "diagnostics=\(result.diagnostics.joined(separator: " | "))",
        ].joined(separator: "\n")
        XCTAssertGreaterThanOrEqual(
            result.storageOperationRequestCount,
            14,
            harnessDebugSummary
        )
        XCTAssertGreaterThanOrEqual(
            result.rejectedRequestCount,
            2,
            harnessDebugSummary
        )
        XCTAssertGreaterThanOrEqual(
            result.storageStateSummary.onChangedPayloadCount,
            6
        )
        XCTAssertEqual(result.userScriptCount, 1)
        XCTAssertEqual(result.scriptMessageHandlerCount, 1)
        XCTAssertEqual(
            result.storageStateSummaryAfterTeardown.keyCount,
            0
        )
        XCTAssertEqual(
            result.storageStateSummaryAfterTeardown
                .operationRecordCount,
            0
        )
        XCTAssertFalse(result.storageJSBridgeAvailableInProduct)
        XCTAssertFalse(result.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(result.serviceWorkerWakeAvailable)
        XCTAssertFalse(result.nativeMessagingAvailable)
        XCTAssertFalse(result.runtimeLoadable)
    }

    func testSourceLevelGuardsForStorageLocalRuntime() throws {
        let sources = try sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
            "SumiTests",
        ])
        .filter {
            $0.relativePath.hasPrefix("Sumi/Models/Extension/ChromeMV3/")
                || $0.relativePath.hasPrefix("SumiTests/ChromeMV3")
        }
        let storageSource = sources.first {
            $0.relativePath
                == "Sumi/Models/Extension/ChromeMV3/ChromeMV3StorageLocalRuntime.swift"
        }?.contents ?? ""
        let browserConfigSource = try String(
            contentsOf:
                repoRoot()
                .appendingPathComponent(
                    "Sumi/Models/BrowserConfig/BrowserConfig.swift"
                ),
            encoding: .utf8
        )
        let storageHarnessAllowlist: Set<String> = [
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeJSMessagingMVP.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3TabsScriptingJSMVP.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3StorageLocalRuntime.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerSyntheticFixture.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionEventAPIsRuntime.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3SidePanelOffscreenIdentitySyntheticWebKitHarness.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3NativeMessagingInternalRuntime.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3PopupOptionsJSBridge.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ProductPopupOptionsUI.swift",
            "SumiTests/ChromeMV3RuntimeJSMessagingMVPTests.swift",
            "SumiTests/ChromeMV3TabsScriptingJSMVPTests.swift",
            "SumiTests/ChromeMV3StorageLocalRuntimeTests.swift",
            "SumiTests/ChromeMV3NativeMessagingInternalRuntimeTests.swift",
        ]
        let otherChromeMV3Joined = sources
            .filter { storageHarnessAllowlist.contains($0.relativePath) == false }
            .map(\.contents)
            .joined(separator: "\n")

        XCTAssertTrue(storageSource.contains("WKUser" + "Script("))
        XCTAssertTrue(storageSource.contains("addUser" + "Script"))
        XCTAssertTrue(storageSource.contains("add" + "ScriptMessageHandler"))
        XCTAssertFalse(
            otherChromeMV3Joined.contains(
                ChromeMV3StorageLocalJSShimSource.bridgeMessageHandlerName
            )
        )
        XCTAssertFalse(
            browserConfigSource.contains(
                ChromeMV3StorageLocalJSShimSource.bridgeMessageHandlerName
            )
        )
        XCTAssertFalse(
            browserConfigSource.contains("ChromeMV3StorageLocalJSShimSource")
        )
        for forbidden in [
            "connect" + "Native",
            "Pro" + "cess(",
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer",
        ] {
            XCTAssertFalse(otherChromeMV3Joined.contains(forbidden), forbidden)
        }
        for forbiddenRegex in [
            "runtime" + "Loadable.*" + "tr" + "ue",
            "storageJSBridgeAvailableInProduct.*" + "tr" + "ue",
            "normalTabRuntimeBridgeAvailable.*" + "tr" + "ue",
            "serviceWorkerWakeAvailable.*" + "tr" + "ue",
            "nativeMessagingAvailableInProduct.*" + "tr" + "ue",
            "productRuntimeExposed.*" + "tr" + "ue",
        ] {
            let regex = try NSRegularExpression(pattern: forbiddenRegex)
            let range = NSRange(
                otherChromeMV3Joined.startIndex...,
                in: otherChromeMV3Joined
            )
            XCTAssertNil(
                regex.firstMatch(in: otherChromeMV3Joined, range: range),
                forbiddenRegex
            )
        }
    }

    private func request(
        _ methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: UUID().uuidString,
            namespace: "storage",
            methodName: methodName,
            invocationMode: invocationMode,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    @MainActor
    private func makeModule(enabled: Bool) throws -> SumiExtensionsModule {
        let defaults = UserDefaults(
            suiteName:
                "ChromeMV3StorageLocalRuntimeTests.\(UUID().uuidString)"
        )!
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.setEnabled(enabled, for: .extensions)
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration()
        )
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ChromeMV3StorageLocalRuntimeTests",
                isDirectory: true
            )
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(root.deletingLastPathComponent())
        return root.standardizedFileURL
    }

    private func object(_ value: ChromeMV3StorageValue?)
        -> [String: ChromeMV3StorageValue]?
    {
        guard case .object(let object) = value else { return nil }
        return object
    }

    private func number(_ value: ChromeMV3StorageValue?) -> Double? {
        guard case .number(let value) = value else { return nil }
        return value
    }

    private func decodedObject(_ json: String?) throws -> [String: Any]? {
        guard let json,
              let data = json.data(using: .utf8)
        else {
            return nil
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func sourceFiles(
        in roots: [String]
    ) throws -> [(relativePath: String, contents: String)] {
        let root = repoRoot()
        var results: [(String, String)] = []
        for relativeRoot in roots {
            let url = root.appendingPathComponent(relativeRoot)
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            while let file = enumerator?.nextObject() as? URL {
                guard file.pathExtension == "swift" else { continue }
                let values = try file.resourceValues(
                    forKeys: [.isRegularFileKey]
                )
                guard values.isRegularFile == true else { continue }
                let relative = String(
                    file.standardizedFileURL.path.dropFirst(
                        root.standardizedFileURL.path.count + 1
                    )
                )
                results.append(
                    (
                        relative,
                        try String(contentsOf: file, encoding: .utf8)
                    )
                )
            }
        }
        return results
            .sorted { (lhs: (String, String), rhs: (String, String)) -> Bool in
                lhs.0 < rhs.0
            }
            .map { (relativePath: $0.0, contents: $0.1) }
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
    }
}
