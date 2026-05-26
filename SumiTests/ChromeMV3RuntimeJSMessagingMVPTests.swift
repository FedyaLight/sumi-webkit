import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3RuntimeJSMessagingMVPTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testRuntimeOnlyShimSourceExposesOnlyRuntimeNamespace() {
        let configuration = ChromeMV3RuntimeJSBridgeConfiguration
            .syntheticHarness()
        let source = ChromeMV3RuntimeJSShimSource.source(
            configuration: configuration
        )
        let coverage = ChromeMV3RuntimeJSShimSource.coverage

        XCTAssertEqual(coverage.exposedChromeNamespaces, ["runtime"])
        XCTAssertEqual(
            coverage.runtimeMethods.sorted(),
            ["connect", "sendMessage"]
        )
        XCTAssertTrue(source.contains("Object.defineProperty(chromeObject, \"runtime\""))
        XCTAssertFalse(source.contains("Object.defineProperty(chromeObject, \"tabs\""))
        XCTAssertFalse(source.contains("Object.defineProperty(chromeObject, \"storage\""))
        XCTAssertFalse(source.contains("Object.defineProperty(chromeObject, \"permissions\""))
        XCTAssertFalse(source.contains("Object.defineProperty(chromeObject, \"scripting\""))
        XCTAssertFalse(source.contains("Object.defineProperty(chromeObject, \"nativeMessaging\""))
    }

    func testHandlerRejectsUnsupportedNamespacesAndMethods() {
        let handler = ChromeMV3RuntimeJSBridgeHandler(
            configuration: .syntheticHarness()
        )
        let namespace = handler.handle([
            "namespace": "tabs",
            "methodName": "sendMessage",
            "invocationMode": "promise",
            "arguments": [],
        ])
        let method = handler.handle([
            "namespace": "runtime",
            "methodName": "getBackgroundPage",
            "invocationMode": "promise",
            "arguments": [],
        ])

        XCTAssertFalse(namespace.succeeded)
        XCTAssertEqual(
            namespace.lastErrorCode,
            ChromeMV3JSBridgeErrorCode.namespaceUnsupported.rawValue
        )
        XCTAssertFalse(method.succeeded)
        XCTAssertEqual(
            method.lastErrorCode,
            ChromeMV3JSBridgeErrorCode.methodUnsupported.rawValue
        )
    }

    func testSendMessageCallbackAndPromiseRouteToSwiftDispatcher() {
        let handler = ChromeMV3RuntimeJSBridgeHandler(
            configuration: .syntheticHarness()
        )
        _ = handler.handle(
            listenerRequest("onMessage.addListener", listenerID: "listener-1")
        )

        let callback = handler.handle(
            request(
                "sendMessage",
                invocationMode: .callback,
                arguments: [.object(["kind": .string("callback")])]
            )
        )
        let promise = handler.handle(
            request(
                "sendMessage",
                invocationMode: .promise,
                arguments: [.object(["kind": .string("promise")])]
            )
        )

        XCTAssertTrue(callback.succeeded)
        XCTAssertTrue(promise.succeeded)
        XCTAssertEqual(callback.runtimeDispatcherResult?.modelHandlerInvoked, true)
        XCTAssertEqual(promise.runtimeDispatcherResult?.modelHandlerInvoked, true)
        XCTAssertEqual(handler.sendMessageDispatchCount, 2)
        XCTAssertEqual(
            promise.runtimeDispatcherResult?.responsePayload,
            .object([
                "listenerCount": .number(1),
                "ok": .bool(true),
                "target": .string("runtimeJSSyntheticOnMessageModel"),
            ])
        )
    }

    func testNoReceivingEndInvalidArgumentsAndLastErrorContracts() {
        let handler = ChromeMV3RuntimeJSBridgeHandler(
            configuration: .syntheticHarness()
        )

        let noReceiver = handler.handle(
            request(
                "sendMessage",
                invocationMode: .callback,
                arguments: [.object(["kind": .string("noReceiver")])]
            )
        )
        let invalid = handler.handle(
            request("sendMessage", invocationMode: .promise)
        )

        XCTAssertFalse(noReceiver.succeeded)
        XCTAssertEqual(
            noReceiver.lastErrorCode,
            ChromeMV3RuntimeLastErrorCase.noReceivingEnd.rawValue
        )
        XCTAssertEqual(
            noReceiver.lastErrorMessage,
            "Could not establish connection. Receiving end does not exist."
        )
        XCTAssertTrue(noReceiver.callbackWouldSetLastError)
        XCTAssertFalse(noReceiver.promiseWouldReject)

        XCTAssertFalse(invalid.succeeded)
        XCTAssertEqual(
            invalid.lastErrorCode,
            ChromeMV3JSBridgeErrorCode.invalidArguments.rawValue
        )
        XCTAssertTrue(invalid.promiseWouldReject)
        XCTAssertFalse(invalid.callbackWouldSetLastError)
    }

    func testConnectOnConnectPortPostMessageAndDisconnectAreModelOnly() {
        let handler = ChromeMV3RuntimeJSBridgeHandler(
            configuration: .syntheticHarness()
        )
        _ = handler.handle(
            listenerRequest("onConnect.addListener", listenerID: "connect-1")
        )

        let connect = handler.handle(
            request(
                "connect",
                invocationMode: .fireAndForget,
                arguments: [.object(["name": .string("demo")])]
            )
        )
        let postMessage = handler.handle(
            portRequest(
                "Port.postMessage",
                portID: "port-1",
                arguments: [.object(["kind": .string("portMessage")])]
            )
        )
        let disconnect = handler.handle(
            portRequest("Port.disconnect", portID: "port-1")
        )

        XCTAssertTrue(connect.succeeded)
        XCTAssertNotNil(connect.runtimeDispatcherResult?.modelPortPreflight)
        XCTAssertEqual(
            connect.runtimeDispatcherResult?
                .modelPortPreflight?
                .canOpenRuntimePortNow,
            false
        )
        XCTAssertTrue(postMessage.succeeded)
        XCTAssertTrue(disconnect.succeeded)
        XCTAssertEqual(handler.modelPortCreateCount, 1)
        XCTAssertEqual(handler.modelPortPostMessageCount, 1)
        XCTAssertEqual(handler.modelPortDisconnectCount, 1)
        XCTAssertFalse(connect.nativeMessagingAvailable)
        XCTAssertFalse(connect.serviceWorkerWakeAvailable)
    }

    func testSyntheticListenerRegistryTeardownClearsListeners() {
        let handler = ChromeMV3RuntimeJSBridgeHandler(
            configuration: .syntheticHarness()
        )
        _ = handler.handle(
            listenerRequest("onMessage.addListener", listenerID: "message-1")
        )
        _ = handler.handle(
            listenerRequest("onConnect.addListener", listenerID: "connect-1")
        )

        XCTAssertEqual(
            handler.listenerRegistry.summary.onMessageListenerCount,
            1
        )
        XCTAssertEqual(
            handler.listenerRegistry.summary.onConnectListenerCount,
            1
        )

        handler.tearDown()

        XCTAssertEqual(
            handler.listenerRegistry.summary.onMessageListenerCount,
            0
        )
        XCTAssertEqual(
            handler.listenerRegistry.summary.onConnectListenerCount,
            0
        )
        XCTAssertEqual(handler.listenerRegistry.summary.modelEndpointCount, 0)
    }

    @MainActor
    func testReportWriterAndDisabledModuleBehavior() throws {
        guard #available(macOS 15.5, *) else { return }
        let root = try temporaryDirectory(named: "runtime-js-report")
        let disabled = try makeModule(enabled: false)
        let disabledReport =
            disabled.chromeMV3RuntimeJSMessagingMVPReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )

        XCTAssertNil(disabledReport)
        XCTAssertFalse(disabled.hasLoadedRuntime)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath:
                    root.appendingPathComponent(
                        ChromeMV3RuntimeJSMessagingMVPReportWriter
                            .reportFileName
                    )
                    .path
            )
        )

        let enabled = try makeModule(enabled: true)
        let report = try XCTUnwrap(
            enabled.chromeMV3RuntimeJSMessagingMVPReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        )
        let reportURL = root.appendingPathComponent(
            ChromeMV3RuntimeJSMessagingMVPReportWriter.reportFileName
        )
        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(
            ChromeMV3RuntimeJSMessagingMVPReport.self,
            from: data
        )

        XCTAssertEqual(decoded.id, report.id)
        XCTAssertTrue(decoded.runtimeJSBridgeAvailableInSyntheticHarness)
        XCTAssertFalse(decoded.runtimeJSBridgeAvailableInProduct)
        XCTAssertFalse(decoded.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(decoded.serviceWorkerWakeAvailable)
        XCTAssertFalse(decoded.nativeMessagingAvailable)
        XCTAssertFalse(decoded.runtimeLoadable)
        XCTAssertFalse(decoded.productRuntimeExposed)
    }

    @MainActor
    func testWebKitSyntheticHarnessExercisesCallbackPromiseLastErrorAndPorts()
        async throws
    {
        guard #available(macOS 15.5, *) else { return }
        let result = await ChromeMV3RuntimeJSSyntheticHarness.run(
            scriptBody: """
            const exposedNamespaces = Object.keys(chrome).sort();
            const runtimeKeys = Object.keys(chrome.runtime).sort();
            let callbackInside = null;
            let callbackOutside = null;
            let callbackArgCount = -1;
            await new Promise((resolve) => {
              chrome.runtime.sendMessage({kind: "noReceiver"}, function() {
                callbackArgCount = arguments.length;
                callbackInside = chrome.runtime.lastError && chrome.runtime.lastError.message;
                resolve();
              });
            });
            callbackOutside = chrome.runtime.lastError || null;
            chrome.runtime.onMessage.addListener((message, sender) => {
              return {echo: message.kind, senderID: sender.id};
            });
            const promiseResult = await chrome.runtime.sendMessage({kind: "promise"});
            let callbackResponse = null;
            await new Promise((resolve) => {
              chrome.runtime.sendMessage({kind: "callback"}, function(response) {
                callbackResponse = response;
                resolve();
              });
            });
            let onConnectName = null;
            let receiverMessage = null;
            let senderMessage = null;
            let disconnectSeen = false;
            chrome.runtime.onConnect.addListener((port) => {
              onConnectName = port.name;
              port.onMessage.addListener((message) => {
                receiverMessage = message.kind;
              });
              port.onDisconnect.addListener(() => {
                disconnectSeen = true;
              });
              port.postMessage({kind: "fromReceiver"});
            });
            const port = chrome.runtime.connect({name: "demo"});
            port.onMessage.addListener((message) => {
              senderMessage = message.kind;
            });
            await chrome.runtime.sendMessage({kind: "flushConnect"});
            port.postMessage({kind: "fromSender"});
            port.disconnect();
            await chrome.runtime.sendMessage({kind: "flushDisconnect"});
            return {
              exposedNamespaces,
              runtimeKeys,
              tabsMissing: chrome.tabs === undefined,
              storageMissing: chrome.storage === undefined,
              permissionsMissing: chrome.permissions === undefined,
              scriptingMissing: chrome.scripting === undefined,
              nativeMessagingMissing: chrome.nativeMessaging === undefined,
              callbackInside,
              callbackOutside,
              callbackArgCount,
              promiseResult,
              callbackResponse,
              onConnectName,
              receiverMessage,
              senderMessage,
              disconnectSeen
            };
            """
        )

        XCTAssertTrue(result.scriptEvaluationSucceeded, result.diagnostics.joined(separator: "\n"))
        let object = try XCTUnwrap(
            try decodedObject(result.scriptResultJSON)
        )
        XCTAssertEqual(object["exposedNamespaces"] as? [String], ["runtime"])
        XCTAssertEqual(object["tabsMissing"] as? Bool, true)
        XCTAssertEqual(object["storageMissing"] as? Bool, true)
        XCTAssertEqual(object["permissionsMissing"] as? Bool, true)
        XCTAssertEqual(object["scriptingMissing"] as? Bool, true)
        XCTAssertEqual(object["nativeMessagingMissing"] as? Bool, true)
        XCTAssertEqual(
            object["callbackInside"] as? String,
            "Could not establish connection. Receiving end does not exist."
        )
        XCTAssertTrue(object["callbackOutside"] is NSNull)
        XCTAssertEqual(object["callbackArgCount"] as? Double, 0)
        XCTAssertEqual(
            (object["promiseResult"] as? [String: Any])?["echo"] as? String,
            "promise"
        )
        XCTAssertEqual(
            (object["callbackResponse"] as? [String: Any])?["echo"] as? String,
            "callback"
        )
        XCTAssertEqual(object["onConnectName"] as? String, "demo")
        XCTAssertEqual(object["receiverMessage"] as? String, "fromSender")
        XCTAssertEqual(object["senderMessage"] as? String, "fromReceiver")
        XCTAssertEqual(object["disconnectSeen"] as? Bool, true)
        XCTAssertEqual(result.userScriptCount, 0)
        XCTAssertEqual(result.scriptMessageHandlerCount, 1)
        XCTAssertFalse(result.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(result.runtimeJSBridgeAvailableInProduct)
        XCTAssertFalse(result.runtimeLoadable)
    }

    func testSourceLevelGuardsForRuntimeJSMessagingMVP() throws {
        let sources = try sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
            "SumiTests",
        ])
        .filter {
            $0.relativePath.hasPrefix("Sumi/Models/Extension/ChromeMV3/")
                || $0.relativePath.hasPrefix("SumiTests/ChromeMV3")
        }
        let runtimeBridgeFiles: Set<String> = [
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeJSMessagingMVP.swift",
            "SumiTests/ChromeMV3RuntimeJSMessagingMVPTests.swift",
        ]
        let runtimeBridgeJoined = sources
            .filter { runtimeBridgeFiles.contains($0.relativePath) }
            .map(\.contents)
            .joined(separator: "\n")
        let otherJoined = sources
            .filter { runtimeBridgeFiles.contains($0.relativePath) == false }
            .map(\.contents)
            .joined(separator: "\n")

        XCTAssertTrue(
            runtimeBridgeJoined.contains("add" + "ScriptMessageHandler")
        )
        XCTAssertFalse(otherJoined.contains("add" + "ScriptMessageHandler"))
        for forbidden in [
            "connect" + "Native",
            "Pro" + "cess(",
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer",
        ] {
            XCTAssertFalse(runtimeBridgeJoined.contains(forbidden), forbidden)
            XCTAssertFalse(otherJoined.contains(forbidden), forbidden)
        }
        for forbiddenRegex in [
            "runtime" + "Loadable.*" + "tr" + "ue",
            "runtimeJSBridgeAvailableInProduct.*" + "tr" + "ue",
            "normalTabRuntimeBridgeAvailable.*" + "tr" + "ue",
            "serviceWorkerWakeAvailable.*" + "tr" + "ue",
            "nativeMessagingAvailable.*" + "tr" + "ue",
            "productRuntimeExposed.*" + "tr" + "ue",
        ] {
            let regex = try NSRegularExpression(pattern: forbiddenRegex)
            let runtimeRange = NSRange(
                runtimeBridgeJoined.startIndex...,
                in: runtimeBridgeJoined
            )
            let otherRange = NSRange(otherJoined.startIndex..., in: otherJoined)
            XCTAssertNil(
                regex.firstMatch(
                    in: runtimeBridgeJoined,
                    range: runtimeRange
                ),
                forbiddenRegex
            )
            XCTAssertNil(
                regex.firstMatch(in: otherJoined, range: otherRange),
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
            namespace: "runtime",
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
        _ methodName: String,
        listenerID: String
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: UUID().uuidString,
            namespace: "runtime",
            methodName: methodName,
            invocationMode: .fireAndForget,
            arguments: [],
            listenerID: listenerID,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    private func portRequest(
        _ methodName: String,
        portID: String,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: UUID().uuidString,
            namespace: "runtime",
            methodName: methodName,
            invocationMode: .fireAndForget,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: portID,
            diagnostics: []
        )
    }

    @MainActor
    private func makeModule(enabled: Bool) throws -> SumiExtensionsModule {
        let defaults = UserDefaults(
            suiteName:
                "ChromeMV3RuntimeJSMessagingMVPTests.\(UUID().uuidString)"
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
                "ChromeMV3RuntimeJSMessagingMVPTests",
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
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
    }
}
