import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3PopupOptionsJSBridgeTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testDisabledModuleBlocksPopupOptionsBridge() throws {
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(moduleState: .disabled)
        )

        let response = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("key")]
        ))

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorCode, "extensionDisabled")
        XCTAssertFalse(response.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(response.contentScriptAttachmentAvailableInProduct)
        XCTAssertFalse(response.serviceWorkerWakeAttempted)
        XCTAssertFalse(response.nativeHostLaunchAttempted)
    }

    func testRuntimeSendMessageAndConnectUseDeterministicPopupOptionsModel()
        throws
    {
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration()
        )

        let promise = handler.handle(request(
            namespace: "runtime",
            methodName: "sendMessage",
            arguments: [.object(["ping": .bool(true)])],
            invocationMode: .promise
        ))
        let callback = handler.handle(request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [.number(1), .object(["ping": .bool(true)])],
            invocationMode: .callback
        ))
        let port = handler.handle(request(
            namespace: "runtime",
            methodName: "connect",
            invocationMode: .fireAndForget
        ))

        XCTAssertFalse(promise.succeeded)
        XCTAssertTrue(promise.promiseWouldReject)
        XCTAssertFalse(promise.callbackWouldSetLastError)
        XCTAssertTrue(promise.lastErrorMessage?.isEmpty == false)
        XCTAssertFalse(promise.serviceWorkerWakeAttempted)
        XCTAssertFalse(callback.succeeded)
        XCTAssertTrue(callback.callbackWouldSetLastError)
        XCTAssertFalse(callback.promiseWouldReject)
        XCTAssertEqual(callback.lastErrorCode, "runtimeDispatchUnavailable")
        XCTAssertTrue(port.succeeded)
        XCTAssertEqual(handler.diagnosticsSnapshot.portCount, 1)
        XCTAssertFalse(port.runtimeLoadable)
    }

    func testStorageLocalAndOnChangedUseExistingStorageRuntime() throws {
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration()
        )

        let set = handler.handle(request(
            namespace: "storage",
            methodName: "local.set",
            arguments: [.object(["alpha": .string("beta")])]
        ))
        let get = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("alpha")]
        ))
        let bytes = handler.handle(request(
            namespace: "storage",
            methodName: "local.getBytesInUse",
            arguments: [.string("alpha")]
        ))
        let remove = handler.handle(request(
            namespace: "storage",
            methodName: "local.remove",
            arguments: [.string("alpha")]
        ))
        let clear = handler.handle(request(
            namespace: "storage",
            methodName: "local.clear"
        ))

        XCTAssertTrue(set.succeeded)
        XCTAssertEqual(set.onChangedPayload?.areaName, "local")
        XCTAssertEqual(set.onChangedPayload?.serviceWorkerWakeRequired, false)
        XCTAssertEqual(stringValue(objectValue(get.resultPayload)?["alpha"]), "beta")
        XCTAssertTrue(bytes.succeeded)
        XCTAssertTrue(numberValue(bytes.resultPayload) ?? 0 > 0)
        XCTAssertTrue(remove.succeeded)
        XCTAssertTrue(clear.succeeded)
        XCTAssertEqual(handler.diagnosticsSnapshot.storageOnChangedPayloadCount, 2)
        XCTAssertFalse(set.serviceWorkerWakeAttempted)
    }

    func testPermissionsModeledPopupOptionsFlow() throws {
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                manifestPermissions: ["tabs"],
                manifestOptionalPermissions: ["history"],
                manifestOptionalHostPermissions: ["https://example.com/*"]
            )
        )

        let containsBefore = handler.handle(request(
            namespace: "permissions",
            methodName: "contains",
            arguments: [.object(["permissions": .array([.string("history")])])]
        ))
        let requestPermission = handler.handle(request(
            namespace: "permissions",
            methodName: "request",
            arguments: [.object([
                "permissions": .array([.string("history")]),
                "__sumiModeledPromptResult": .bool(true),
            ])]
        ))
        let requestOrigin = handler.handle(request(
            namespace: "permissions",
            methodName: "request",
            arguments: [.object([
                "origins": .array([.string("https://example.com/*")]),
                "__sumiModeledPromptResult": .string("accepted"),
            ])]
        ))
        let allAfterGrant = handler.handle(request(
            namespace: "permissions",
            methodName: "getAll"
        ))
        let removePermission = handler.handle(request(
            namespace: "permissions",
            methodName: "remove",
            arguments: [.object(["permissions": .array([.string("history")])])]
        ))
        let missingPrompt = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(manifestOptionalPermissions: ["bookmarks"])
        ).handle(request(
            namespace: "permissions",
            methodName: "request",
            arguments: [.object(["permissions": .array([.string("bookmarks")])])]
        ))

        XCTAssertEqual(boolValue(containsBefore.resultPayload), false)
        XCTAssertTrue(requestPermission.succeeded)
        XCTAssertEqual(requestPermission.permissionEventPayload?.eventKind, .onAdded)
        XCTAssertTrue(requestOrigin.succeeded)
        let allObject = try XCTUnwrap(objectValue(allAfterGrant.resultPayload))
        XCTAssertTrue(stringArrayValue(allObject["permissions"]).contains("history"))
        XCTAssertTrue(stringArrayValue(allObject["origins"]).contains("https://example.com/*"))
        XCTAssertTrue(removePermission.succeeded)
        XCTAssertFalse(missingPrompt.succeeded)
        XCTAssertEqual(missingPrompt.lastErrorCode, "productUIUnavailable")
        XCTAssertTrue(missingPrompt.lastErrorMessage?.contains("permission UI") == true)
    }

    func testTabsQueryRedactsAndExposesByModeledPermission() throws {
        let redactedHandler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration()
        )
        let visibleHandler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(manifestPermissions: ["tabs"])
        )

        let redacted = redactedHandler.handle(request(
            namespace: "tabs",
            methodName: "query",
            arguments: [.object(["active": .bool(true)])]
        ))
        let visible = visibleHandler.handle(request(
            namespace: "tabs",
            methodName: "query",
            arguments: [.object(["active": .bool(true)])]
        ))

        let redactedTab = try firstTabObject(redacted.resultPayload)
        let visibleTab = try firstTabObject(visible.resultPayload)
        XCTAssertTrue(redacted.succeeded)
        XCTAssertNil(redactedTab["url"])
        XCTAssertNil(redactedTab["title"])
        XCTAssertEqual(stringValue(visibleTab["url"]), "https://example.com/login")
        XCTAssertEqual(stringValue(visibleTab["title"]), "Example Login")
        XCTAssertFalse(visible.normalTabRuntimeBridgeAvailable)
    }

    func testUnsupportedPopupOptionsAPIsProduceDeterministicDiagnostics()
        throws
    {
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration()
        )
        let blockedCalls: [(String, String)] = [
            ("runtime", "sendNativeMessage"),
            ("runtime", "connect" + "Native"),
            ("tabs", "connect"),
            ("scripting", "executeScript"),
            ("nativeMessaging", "sendMessage"),
            ("sidePanel", "open"),
            ("offscreen", "createDocument"),
            ("identity", "getAuthToken"),
            ("declarativeNetRequest", "updateDynamicRules"),
            ("webRequest", "onBeforeRequest"),
            ("unknownNamespace", "unknownMethod"),
        ]

        for (namespace, methodName) in blockedCalls {
            let response = handler.handle(request(
                namespace: namespace,
                methodName: methodName,
                arguments: [.object([:])]
            ))
            XCTAssertFalse(response.succeeded, "\(namespace).\(methodName)")
            XCTAssertTrue(response.promiseWouldReject, "\(namespace).\(methodName)")
            XCTAssertTrue(response.lastErrorMessage?.isEmpty == false)
            XCTAssertNotNil(response.blockedAPIDiagnostic)
            XCTAssertFalse(response.nativeHostLaunchAttempted)
            XCTAssertFalse(response.serviceWorkerWakeAttempted)
        }
        XCTAssertTrue(handler.diagnosticsSnapshot.blockedAPIs.contains {
            $0.namespace == "scripting" && $0.methodName == "executeScript"
        })
    }

    func testTeardownClearsPopupOptionsBridgeState() throws {
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration()
        )
        _ = handler.handle(request(
            namespace: "runtime",
            methodName: "connect",
            invocationMode: .fireAndForget
        ))
        _ = handler.handle(request(
            namespace: "storage",
            methodName: "local.set",
            arguments: [.object(["alpha": .string("beta")])]
        ))

        XCTAssertEqual(handler.diagnosticsSnapshot.portCount, 1)
        XCTAssertEqual(handler.diagnosticsSnapshot.storageOnChangedPayloadCount, 1)
        handler.tearDown()
        let snapshot = handler.diagnosticsSnapshot
        XCTAssertEqual(snapshot.handledRequestCount, 0)
        XCTAssertEqual(snapshot.portCount, 0)
        XCTAssertEqual(snapshot.storageOnChangedPayloadCount, 0)
        XCTAssertTrue(snapshot.listenerRegistryClearedOnTeardown)
        XCTAssertTrue(snapshot.storageListenersClearedOnTeardown)
        XCTAssertTrue(snapshot.portStateClearedOnTeardown)
    }

    #if canImport(WebKit)
    @MainActor
    func testRealPopupOptionsWKWebViewInstallsBridgeAndRunsJS()
        async throws
    {
        let root = try makeTemporaryDirectory()
        let htmlURL = root.appendingPathComponent("popup.html")
        try """
        <!doctype html>
        <meta charset="utf-8">
        <title>Popup Bridge</title>
        <main data-sumi-extension-page-fixture-marker="safe">Popup</main>
        """.write(to: htmlURL, atomically: true, encoding: .utf8)
        let config = configuration(manifestPermissions: ["tabs"])
        let installation = ChromeMV3PopupOptionsJSBridgeInstallation(
            configuration: config,
            allowlist: config.allowlist,
            bridgeAvailable: true,
            scriptSource: ChromeMV3PopupOptionsJSShimSource.source(
                configuration: config
            ),
            messageHandlerName:
                ChromeMV3PopupOptionsJSShimSource.bridgeMessageHandlerName,
            diagnostics: config.diagnostics
        )
        let handle = ChromeMV3ProductPopupOptionsWKWebViewHandle(
            loadFileURL: htmlURL,
            readAccessURL: root,
            bridgeInstallation: installation
        )
        defer { handle.tearDown() }

        try await handle.waitForLoadForTesting()
        let raw = try await handle.callAsyncJavaScriptForTesting(
            """
            const changes = [];
            chrome.storage.onChanged.addListener((changesObject, areaName) => {
              changes.push({ areaName, value: changesObject.alpha.newValue });
            });
            await chrome.storage.local.set({ alpha: "beta" });
            const stored = await chrome.storage.local.get("alpha");
            const tabs = await chrome.tabs.query({ active: true });
            let promiseRejected = false;
            try {
              await chrome.tabs.sendMessage(1, { ping: true });
            } catch (error) {
              promiseRejected = String(error.message || error).includes("Receiving end");
            }
            let callbackLastError = null;
            await new Promise((resolve) => {
              chrome.tabs.sendMessage(1, { ping: true }, () => {
                callbackLastError = chrome.runtime.lastError
                  ? chrome.runtime.lastError.message
                  : null;
                resolve();
              });
            });
            return {
              hasChrome: !!chrome.runtime && !!browser.runtime,
              stored: stored.alpha,
              changeCount: changes.length,
              changeArea: changes[0] && changes[0].areaName,
              tabURL: tabs[0] && tabs[0].url,
              promiseRejected,
              callbackLastError,
              lastErrorAfterCallback: chrome.runtime.lastError || null
            };
            """
        )
        let object = try XCTUnwrap(raw as? [String: Any])

        XCTAssertEqual(object["hasChrome"] as? Bool, true)
        XCTAssertEqual(object["stored"] as? String, "beta")
        XCTAssertEqual(object["changeCount"] as? Int, 1)
        XCTAssertEqual(object["changeArea"] as? String, "local")
        XCTAssertEqual(object["tabURL"] as? String, "https://example.com/login")
        XCTAssertEqual(object["promiseRejected"] as? Bool, true)
        XCTAssertTrue((object["callbackLastError"] as? String)?
            .contains("Receiving end") == true)
        XCTAssertTrue(object["lastErrorAfterCallback"] is NSNull)
        let snapshot = try XCTUnwrap(
            handle.popupOptionsBridgeDiagnosticsSnapshot
        )
        XCTAssertTrue(snapshot.observedMethods.contains("storage.local.set"))
        XCTAssertTrue(snapshot.observedMethods.contains("tabs.sendMessage"))
    }
    #endif

    private func configuration(
        extensionID: String = "popup-options-extension",
        profileID: String = "popup-options-profile",
        surface: ChromeMV3ProductPopupOptionsSurface = .actionPopup,
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        bridgeAvailable: Bool = true,
        manifestPermissions: [String] = [],
        manifestOptionalPermissions: [String] = [],
        manifestHostPermissions: [String] = [],
        manifestOptionalHostPermissions: [String] = []
    ) -> ChromeMV3PopupOptionsJSBridgeConfiguration {
        ChromeMV3PopupOptionsJSBridgeConfiguration(
            extensionID: extensionID,
            profileID: profileID,
            surfaceID: "\(profileID):\(extensionID):\(surface.rawValue)",
            surface: surface,
            extensionBaseURLString: "chrome-extension://\(extensionID)/",
            moduleState: moduleState,
            bridgeAvailable: bridgeAvailable,
            popupOptionsJSBridgeAvailableInDeveloperPreview:
                bridgeAvailable && moduleState == .enabled,
            popupOptionsJSBridgeAvailableInPublicProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            contentScriptAttachmentAvailableInProduct: false,
            runtimeLoadable: false,
            manifestPermissions: manifestPermissions,
            manifestOptionalPermissions: manifestOptionalPermissions,
            manifestHostPermissions: manifestHostPermissions,
            manifestOptionalHostPermissions: manifestOptionalHostPermissions,
            allowlist: .defaultPolicy,
            diagnostics: [
                ChromeMV3PopupOptionsJSBridgeConfiguration
                    .productNormalTabBridgeInstallationGuard,
                ChromeMV3PopupOptionsJSBridgeConfiguration
                    .contentScriptProductAttachmentGuard,
            ]
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
            diagnostics: []
        )
    }

    private func firstTabObject(
        _ value: ChromeMV3StorageValue?
    ) throws -> [String: ChromeMV3StorageValue] {
        guard case .array(let tabs) = value,
              let first = tabs.first,
              case .object(let object) = first
        else {
            XCTFail("Expected first tab object.")
            return [:]
        }
        return object
    }

    private func objectValue(
        _ value: ChromeMV3StorageValue?
    ) -> [String: ChromeMV3StorageValue]? {
        guard case .object(let object) = value else { return nil }
        return object
    }

    private func stringValue(_ value: ChromeMV3StorageValue?) -> String? {
        guard case .string(let string) = value else { return nil }
        return string
    }

    private func boolValue(_ value: ChromeMV3StorageValue?) -> Bool? {
        guard case .bool(let bool) = value else { return nil }
        return bool
    }

    private func numberValue(_ value: ChromeMV3StorageValue?) -> Double? {
        guard case .number(let number) = value else { return nil }
        return number
    }

    private func stringArrayValue(_ value: ChromeMV3StorageValue?) -> [String] {
        guard case .array(let values) = value else { return [] }
        return values.compactMap(stringValue)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }
}
