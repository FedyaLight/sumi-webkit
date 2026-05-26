import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3ExtensionEventAPIsRuntimeTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testShimSourceExposesOnlyEventAPINamespacesAndFalseProductFlags() {
        let configuration =
            ChromeMV3ExtensionEventAPIsConfiguration.syntheticHarness()
        let source = ChromeMV3ExtensionEventAPIsJSShimSource.source(
            configuration: configuration
        )
        let coverage = ChromeMV3ExtensionEventAPIsJSShimSource.coverage

        XCTAssertEqual(coverage.exposedChromeNamespaces, [
            "alarms",
            "contextMenus",
            "runtime",
            "webNavigation",
        ])
        XCTAssertEqual(coverage.contextMenusMethods.sorted(), [
            "create",
            "remove",
            "removeAll",
            "update",
        ])
        XCTAssertEqual(coverage.alarmsMethods.sorted(), [
            "clear",
            "clearAll",
            "create",
            "get",
            "getAll",
        ])
        XCTAssertTrue(source.contains("Object.defineProperty(chromeObject, \"contextMenus\""))
        XCTAssertTrue(source.contains("Object.defineProperty(chromeObject, \"alarms\""))
        XCTAssertTrue(source.contains("Object.defineProperty(chromeObject, \"webNavigation\""))
        XCTAssertFalse(source.contains("Object.defineProperty(chromeObject, \"tabs\""))
        XCTAssertFalse(source.contains("Object.defineProperty(chromeObject, \"scripting\""))
        XCTAssertFalse(configuration.contextMenusAvailableInProduct)
        XCTAssertFalse(configuration.alarmsRealSchedulingAvailableInProduct)
        XCTAssertFalse(configuration.webNavigationAvailableInProduct)
        XCTAssertFalse(configuration.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(configuration.runtimeLoadable)
    }

    func testContextMenusCreateDuplicateUpdateRemoveAndRemoveAll() throws {
        let handler = ChromeMV3ExtensionEventAPIsJSBridgeHandler(
            configuration: .syntheticHarness()
        )
        let create = handler.handle(
            request(
                namespace: "contextMenus",
                methodName: "create",
                arguments: [
                    .object([
                        "id": .string("item-1"),
                        "title": .string("Open"),
                        "contexts": .array([.string("page")]),
                        "enabled": .bool(true),
                    ]),
                ]
            )
        )
        let duplicate = handler.handle(
            request(
                namespace: "contextMenus",
                methodName: "create",
                invocationMode: .callback,
                arguments: [
                    .object([
                        "id": .string("item-1"),
                        "title": .string("Duplicate"),
                    ]),
                ]
            )
        )
        let update = handler.handle(
            request(
                namespace: "contextMenus",
                methodName: "update",
                arguments: [
                    .string("item-1"),
                    .object([
                        "title": .string("Open Updated"),
                        "checked": .bool(true),
                    ]),
                ]
            )
        )
        XCTAssertTrue(update.succeeded)
        XCTAssertEqual(
            handler.runtimeStateOwner.item(id: "item-1")?.title,
            "Open Updated"
        )

        let remove = handler.handle(
            request(
                namespace: "contextMenus",
                methodName: "remove",
                arguments: [.string("item-1")]
            )
        )
        _ = handler.handle(
            request(
                namespace: "contextMenus",
                methodName: "create",
                arguments: [
                    .object([
                        "id": .string("item-2"),
                        "title": .string("Second"),
                    ]),
                ]
            )
        )
        let removeAll = handler.handle(
            request(namespace: "contextMenus", methodName: "removeAll")
        )

        XCTAssertTrue(create.succeeded)
        XCTAssertEqual(create.resultPayload, .string("item-1"))
        XCTAssertFalse(duplicate.succeeded)
        XCTAssertEqual(duplicate.lastErrorCode, "duplicateMenuItemID")
        XCTAssertTrue(duplicate.callbackWouldSetLastError)
        XCTAssertTrue(remove.succeeded)
        XCTAssertNil(handler.runtimeStateOwner.item(id: "item-1"))
        XCTAssertTrue(removeAll.succeeded)
        XCTAssertEqual(handler.runtimeStateOwner.contextMenusSummary.itemCount, 0)
        XCTAssertFalse(removeAll.contextMenusAvailableInProduct)
    }

    func testContextMenuSyntheticClickDispatchesThroughSharedLifecycleSession()
        throws
    {
        let session = try sharedSession()
        let handler = ChromeMV3ExtensionEventAPIsJSBridgeHandler(
            configuration: .syntheticHarness(
                extensionID: session.key.extensionID,
                profileID: session.key.profileID
            ),
            sharedLifecycleSession: session
        )
        _ = handler.handle(
            listenerRequest(
                namespace: "contextMenus",
                methodName: "onClicked.addListener",
                listenerID: "context-listener"
            )
        )
        _ = handler.handle(
            request(
                namespace: "contextMenus",
                methodName: "create",
                arguments: [
                    .object([
                        "id": .string("item-click"),
                        "title": .string("Click"),
                        "contexts": .array([.string("page")]),
                        "documentUrlPatterns":
                            .array([.string("https://example.com/*")]),
                    ]),
                ]
            )
        )

        let click = handler.triggerContextMenuClick(
            .page(menuItemID: "item-click")
        )

        XCTAssertTrue(click.dispatched, click.diagnostics.joined(separator: "\n"))
        XCTAssertEqual(click.sharedLifecycleSessionID, session.key.lifecycleSessionID)
        XCTAssertEqual(
            click.serviceWorkerLifecycleWakeResult?.sourceComponentKind,
            .contextMenusHarness
        )
        XCTAssertTrue(
            session.runtimeOwner.snapshot.events.contains {
                $0.reason == .contextMenusClicked
                    && $0.listenerEvent == .contextMenusOnClicked
            }
        )
    }

    func testAlarmsCreateGetClearAndExplicitTriggerWithoutScheduling() throws {
        let session = try sharedSession()
        let handler = ChromeMV3ExtensionEventAPIsJSBridgeHandler(
            configuration: .syntheticHarness(
                extensionID: session.key.extensionID,
                profileID: session.key.profileID
            ),
            sharedLifecycleSession: session
        )
        _ = handler.handle(
            listenerRequest(
                namespace: "alarms",
                methodName: "onAlarm.addListener",
                listenerID: "alarm-listener"
            )
        )
        let create = handler.handle(
            request(
                namespace: "alarms",
                methodName: "create",
                arguments: [
                    .string("sync"),
                    .object([
                        "delayInMinutes": .number(1),
                        "periodInMinutes": .number(5),
                    ]),
                ]
            )
        )
        let get = handler.handle(
            request(
                namespace: "alarms",
                methodName: "get",
                arguments: [.string("sync")]
            )
        )
        let all = handler.handle(
            request(namespace: "alarms", methodName: "getAll")
        )
        let trigger = handler.triggerAlarm(name: "sync")
        XCTAssertTrue(create.succeeded)
        XCTAssertEqual(handler.runtimeStateOwner.alarm(name: "sync")?.repeating, true)

        let clear = handler.handle(
            request(
                namespace: "alarms",
                methodName: "clear",
                arguments: [.string("sync")]
            )
        )
        let clearAll = handler.handle(
            request(namespace: "alarms", methodName: "clearAll")
        )

        XCTAssertEqual(object(get.resultPayload)?["name"], .string("sync"))
        XCTAssertEqual(array(all.resultPayload)?.count, 1)
        XCTAssertTrue(trigger.dispatched, trigger.diagnostics.joined(separator: "\n"))
        XCTAssertTrue(trigger.repeatingAlarmValueStateRetained)
        XCTAssertEqual(trigger.sharedLifecycleSessionID, session.key.lifecycleSessionID)
        XCTAssertEqual(
            trigger.serviceWorkerLifecycleWakeResult?.sourceComponentKind,
            .alarmsHarness
        )
        XCTAssertEqual(clear.resultPayload, .bool(true))
        XCTAssertEqual(clearAll.resultPayload, .bool(false))
        XCTAssertFalse(create.alarmsRealSchedulingAvailableInProduct)
    }

    func testWebNavigationFiltersSyntheticEventsAndFrameMethodsUseFixtureStore()
        throws
    {
        let session = try sharedSession()
        let handler = ChromeMV3ExtensionEventAPIsJSBridgeHandler(
            configuration: .syntheticHarness(
                extensionID: session.key.extensionID,
                profileID: session.key.profileID
            ),
            sharedLifecycleSession: session
        )
        let listener = handler.handle(
            listenerRequest(
                namespace: "webNavigation",
                methodName: "onCommitted.addListener",
                listenerID: "nav-listener",
                arguments: [
                    .object([
                        "url": .array([
                            .object([
                                "hostEquals": .string("example.com"),
                                "schemes": .array([.string("https")]),
                            ]),
                        ]),
                    ]),
                ]
            )
        )
        let ignored = handler.emitWebNavigationEvent(
            .committed(url: "https://other.example/login")
        )
        let committed = handler.emitWebNavigationEvent(
            .committed(url: "https://example.com/login", sequence: 2)
        )
        let frame = handler.handle(
            request(
                namespace: "webNavigation",
                methodName: "getFrame",
                arguments: [
                    .object([
                        "tabId": .number(1),
                        "frameId": .number(0),
                    ]),
                ]
            )
        )
        let frames = handler.handle(
            request(
                namespace: "webNavigation",
                methodName: "getAllFrames",
                arguments: [.object(["tabId": .number(1)])]
            )
        )

        XCTAssertTrue(listener.succeeded)
        XCTAssertEqual(
            listener.listenerFilterSummary.webNavigationFilterCount,
            1
        )
        XCTAssertFalse(ignored.dispatched)
        XCTAssertTrue(committed.dispatched, committed.diagnostics.joined(separator: "\n"))
        XCTAssertEqual(committed.sharedLifecycleSessionID, session.key.lifecycleSessionID)
        XCTAssertEqual(
            committed.serviceWorkerLifecycleWakeResult?.listenerEvent,
            .webNavigationOnCommitted
        )
        XCTAssertEqual(object(frame.resultPayload)?["url"], .string("https://example.com/login"))
        XCTAssertEqual(array(frames.resultPayload)?.count, 1)
        XCTAssertFalse(committed.sharedLifecycleSessionID?.isEmpty ?? true)
        XCTAssertFalse(listener.webNavigationAvailableInProduct)
    }

    func testReportCoversEventAPIsAndWritesDeterministicJSON() throws {
        let report = ChromeMV3ExtensionEventAPIsReportGenerator.makeReport(
            extensionID: "event-report-extension",
            profileID: "event-report-profile"
        )
        let root = try temporaryDirectory(named: "event-report")

        XCTAssertEqual(
            report.reportFileName,
            ChromeMV3ExtensionEventAPIsReportWriter.reportFileName
        )
        XCTAssertTrue(report.contextMenusAvailableInInternalFixture)
        XCTAssertTrue(report.alarmsAvailableInInternalFixture)
        XCTAssertTrue(report.webNavigationAvailableInInternalFixture)
        XCTAssertTrue(report.sharedLifecycleSessionUsage.sharedLifecycleSessionUsed)
        XCTAssertTrue(report.contextMenusClickFlow.contains(\.dispatched))
        XCTAssertTrue(report.alarmsExplicitTriggerFlow.contains(\.dispatched))
        XCTAssertTrue(report.syntheticNavigationFlow.contains(\.dispatched))
        XCTAssertFalse(report.contextMenusAvailableInProduct)
        XCTAssertFalse(report.alarmsRealSchedulingAvailableInProduct)
        XCTAssertFalse(report.webNavigationAvailableInProduct)
        XCTAssertFalse(report.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(report.runtimeLoadable)

        try ChromeMV3ExtensionEventAPIsReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )
        let decoded = try JSONDecoder().decode(
            ChromeMV3ExtensionEventAPIsReport.self,
            from:
                Data(
                    contentsOf:
                        root.appendingPathComponent(report.reportFileName)
                )
        )
        XCTAssertEqual(decoded, report)
    }

    @MainActor
    func testDisabledModuleBlocksEventAPIsReportAndWritesNoFile() throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }
        let root = try temporaryDirectory(named: "disabled-module")
        let module = try makeModule(enabled: false)
        let report = module.chromeMV3ExtensionEventAPIsReportIfEnabled(
            fromRewrittenBundleRoot: root,
            writeReport: true
        )

        XCTAssertNil(report)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath:
                    root.appendingPathComponent(
                        ChromeMV3ExtensionEventAPIsReportWriter.reportFileName
                    ).path
            )
        )
        XCTAssertFalse(module.tearDownChromeMV3ExtensionEventAPIsIfEnabled())
    }

    @MainActor
    func testModuleReportLinksIntoProfileDiagnostics() throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }
        let root = try temporaryDirectory(named: "module-report")
        let module = try makeModule(enabled: true)
        let report = try XCTUnwrap(
            module.chromeMV3ExtensionEventAPIsReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        )
        let diagnostics = module.chromeMV3InventoryDiagnosticsIfEnabled(rootURL: root)

        XCTAssertEqual(
            diagnostics?.extensionEventAPIsReportSummary,
            report.summary
        )
        XCTAssertTrue(module.tearDownChromeMV3ExtensionEventAPIsIfEnabled())
    }

    @MainActor
    func testWebKitSyntheticHarnessExercisesEventAPICalls() async throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Requires macOS 15.5 WebKit API surface.")
        }

        let result = await ChromeMV3ExtensionEventAPIsSyntheticHarness.run(
            scriptBody:
                ChromeMV3ExtensionEventAPIsSyntheticHarness
                .reportVerificationScriptBody
        )

        XCTAssertTrue(
            result.scriptEvaluationSucceeded,
            result.diagnostics.joined(separator: "\n")
        )
        XCTAssertTrue(result.webKitExecutionSummary.contextMenusCreateExecuted)
        XCTAssertTrue(result.webKitExecutionSummary.alarmsCreateExecuted)
        XCTAssertTrue(
            result.webKitExecutionSummary.webNavigationListenerRegistered
        )
        XCTAssertTrue(
            result.webKitExecutionSummary.lastErrorScopedFromActualJSCall
        )
        XCTAssertFalse(result.contextMenusAvailableInProduct)
        XCTAssertFalse(result.alarmsRealSchedulingAvailableInProduct)
        XCTAssertFalse(result.webNavigationAvailableInProduct)
        XCTAssertFalse(result.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(result.runtimeLoadable)
    }

    func testSourceGuardsForEventAPIsAvoidForbiddenProductPaths()
        throws
    {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionEventAPIsRuntime.swift"
            )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let forbiddenTokens = [
            "Ti" + "mer",
            "DispatchSource" + "Ti" + "mer",
            "Process" + "(",
            "NS" + "Menu",
            "webExtension" + "Controller",
            "Browser" + "Config",
        ]
        for token in forbiddenTokens {
            XCTAssertFalse(source.contains(token), token)
        }
        for flag in [
            "contextMenusAvailableInProduct",
            "alarmsRealSchedulingAvailableInProduct",
            "webNavigationAvailableInProduct",
            "normalTabRuntimeBridgeAvailable",
            "runtimeLoadable",
            "productRuntimeExposed",
        ] {
            let unsafeLines = source.split(separator: "\n").filter {
                $0.contains(flag) && $0.contains("true")
            }
            XCTAssertTrue(unsafeLines.isEmpty, "\(flag): \(unsafeLines)")
        }
    }

    private func sharedSession(
        profileID: String = "event-profile",
        extensionID: String = "event-extension"
    ) throws -> ChromeMV3ServiceWorkerSharedLifecycleSession {
        try XCTUnwrap(
            ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
                .session(profileID: profileID, extensionID: extensionID)
        )
    }

    private func request(
        namespace: String,
        methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode = .promise,
        arguments: [ChromeMV3StorageValue] = []
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
            diagnostics: []
        )
    }

    private func listenerRequest(
        namespace: String,
        methodName: String,
        listenerID: String,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: UUID().uuidString,
            namespace: namespace,
            methodName: methodName,
            invocationMode: .fireAndForget,
            arguments: arguments,
            listenerID: listenerID,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    @MainActor
    private func makeModule(enabled: Bool) throws -> SumiExtensionsModule {
        let defaults = UserDefaults(
            suiteName:
                "ChromeMV3ExtensionEventAPIsRuntimeTests.\(UUID().uuidString)"
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
                "ChromeMV3ExtensionEventAPIsRuntimeTests",
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

    private func object(
        _ value: ChromeMV3StorageValue?
    ) -> [String: ChromeMV3StorageValue]? {
        guard case .object(let object) = value else { return nil }
        return object
    }

    private func array(
        _ value: ChromeMV3StorageValue?
    ) -> [ChromeMV3StorageValue]? {
        guard case .array(let array) = value else { return nil }
        return array
    }
}

private extension Array where Element == ChromeMV3ContextMenusClickDispatchRecord {
    func contains(
        _ keyPath: KeyPath<ChromeMV3ContextMenusClickDispatchRecord, Bool>
    ) -> Bool {
        contains { $0[keyPath: keyPath] }
    }
}

private extension Array where Element == ChromeMV3AlarmTriggerRecord {
    func contains(_ keyPath: KeyPath<ChromeMV3AlarmTriggerRecord, Bool>) -> Bool {
        contains { $0[keyPath: keyPath] }
    }
}

private extension Array where Element == ChromeMV3WebNavigationDispatchRecord {
    func contains(
        _ keyPath: KeyPath<ChromeMV3WebNavigationDispatchRecord, Bool>
    ) -> Bool {
        contains { $0[keyPath: keyPath] }
    }
}
