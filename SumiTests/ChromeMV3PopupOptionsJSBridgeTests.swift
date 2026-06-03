import Foundation
import XCTest

#if canImport(AppKit)
import AppKit
#endif

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
        XCTAssertEqual(callback.lastErrorCode, "noReceivingEnd")
        XCTAssertTrue(port.succeeded)
        XCTAssertEqual(handler.diagnosticsSnapshot.portCount, 1)
        XCTAssertFalse(port.runtimeLoadable)
    }

    func testSanitizedBridgeSnapshotRecordsRoutesWithoutMessageBodies()
        throws
    {
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration()
        )

        _ = handler.handle(request(
            namespace: "runtime",
            methodName: "sendMessage",
            arguments: [
                .object([
                    "command": .string("sensitive-command-value"),
                    "token": .string("must-not-appear"),
                ]),
            ]
        ))
        _ = handler.handle(request(
            namespace: "runtime",
            methodName: "connect",
            arguments: [
                .object(["name": .string("popup-safe-port")]),
            ],
            invocationMode: .fireAndForget
        ))
        _ = handler.handle(request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [
                .number(1),
                .object([
                    "type": .string("sensitive-type-value"),
                    "cookie": .string("must-not-appear"),
                ]),
            ]
        ))

        let snapshot = handler.diagnosticsSnapshot
        let routes = snapshot.sanitizedBridgeRouteRecords
        XCTAssertEqual(routes.count, 3)
        XCTAssertTrue(routes.contains {
            $0.sourceContext == "actionPopup"
                && $0.targetContext == "serviceWorker"
                && $0.apiName == "runtime.sendMessage"
                && $0.safeCommandTypeActionFieldNames == ["command"]
                && $0.resultClassifier == "noReceivingEnd"
        })
        XCTAssertTrue(routes.contains {
            $0.apiName == "runtime.connect"
                && $0.portName == "popup-safe-port"
                && $0.safeCommandTypeActionFieldNames == ["name"]
        })
        XCTAssertTrue(routes.contains {
            $0.apiName == "tabs.sendMessage"
                && $0.targetContext == "contentScript"
                && $0.safeCommandTypeActionFieldNames == ["type"]
                && $0.resultClassifier == "noReceivingEnd"
        })
        let encoded = String(
            data: try JSONEncoder().encode(snapshot),
            encoding: .utf8
        ) ?? ""
        XCTAssertFalse(encoded.contains("sensitive-command-value"))
        XCTAssertFalse(encoded.contains("sensitive-type-value"))
        XCTAssertFalse(encoded.contains("must-not-appear"))
        XCTAssertFalse(encoded.contains("cookie\":\"must-not-appear"))
        XCTAssertFalse(encoded.contains("token\":\"must-not-appear"))
    }

    @MainActor
    func testNativeActionPopupBoundaryPayloadShapeSanitizesSensitiveBodies()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("WKWebExtension native popup boundary requires macOS 15.5.")
        }

        let shape = ChromeMV3NativeActionPopupBoundaryRecorder
            .sanitizedPayloadShape([
                "command": "sensitive-command-value",
                "token": "must-not-appear",
                "password": "must-not-appear",
                "nested": ["cookie": "must-not-appear"],
            ])

        XCTAssertTrue(shape.contains("object(keyCount:4"))
        XCTAssertTrue(shape.contains("safeFieldNames:[\"command\"]"))
        XCTAssertTrue(shape.contains("sensitiveKeyPresent:true"))
        XCTAssertFalse(shape.contains("sensitive-command-value"))
        XCTAssertFalse(shape.contains("must-not-appear"))
        XCTAssertFalse(shape.contains("cookie"))
        XCTAssertFalse(shape.contains("token\":\""))
        XCTAssertFalse(shape.contains("password\":\""))
    }

    func testRuntimeSendMessageRoutesThroughSharedLifecycleWhenProvided()
        throws
    {
        let session = try makeSharedLifecycleSession()
        session.registerListener(
            event: .runtimeOnMessage,
            listenerID: "popup-runtime-on-message",
            outcome: .modelDispatched(.string("popup-ok"))
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(),
            sharedLifecycleSession: session
        )

        let response = handler.handle(request(
            namespace: "runtime",
            methodName: "sendMessage",
            arguments: [.object(["ping": .bool(true)])]
        ))

        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(response.resultPayload, .string("popup-ok"))
        XCTAssertTrue(response.serviceWorkerWakeAttempted)
        XCTAssertEqual(
            response.serviceWorkerLifecycleWakeResult?.sessionID,
            session.key.lifecycleSessionID
        )
        XCTAssertEqual(
            response.serviceWorkerLifecycleWakeResult?.sourceComponentKind,
            .extensionPageHostHarness
        )
        XCTAssertFalse(response.runtimeLoadable)
    }

    func testRuntimeSendMessageRoutesThroughSharedJSListenerDispatcher()
        throws
    {
        let session = try makeSharedLifecycleSession()
        session.registerJSListenerDispatcher(
            event: .runtimeOnMessage,
            listenerID: "popup-js-runtime-on-message"
        ) { input in
            let responsePayload: ChromeMV3StorageValue = .object([
                "echo": input.arguments.first ?? .null,
                "source": .string(input.source.rawValue),
                "senderURLRedacted": .bool(input.sender.urlRedacted),
            ])
            session.registerListener(
                event: input.event,
                listenerID: "popup-js-runtime-on-message-executed",
                outcome: .modelDispatched(responsePayload)
            )
            let wake = session.routeEvent(
                reason: input.source.wakeReason,
                listenerEvent: input.event,
                sourceComponentID: input.sourceComponentID,
                sourceComponentKind: input.sourceComponentKind,
                payload: input.arguments.first,
                payloadSummary: input.payloadSummary,
                sourceContext: input.source.sourceContext
            )
            return ChromeMV3ServiceWorkerJSListenerDispatchResult(
                event: input.event,
                listenerID: "popup-js-runtime-on-message",
                resultKind: wake.dispatched ? .delivered : .noReceiver,
                responsePayload: wake.responsePayload,
                lastErrorMessage: wake.lastErrorMessage,
                lifecycleWakeResult: wake,
                diagnostics: [
                    "Popup test JS dispatcher routed through shared lifecycle.",
                ]
            )
        }
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(),
            sharedLifecycleSession: session
        )

        let response = handler.handle(request(
            namespace: "runtime",
            methodName: "sendMessage",
            arguments: [.object(["ping": .bool(true)])]
        ))

        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(
            response.resultPayload,
            .object([
                "echo": .object(["ping": .bool(true)]),
                "senderURLRedacted": .bool(false),
                "source": .string("popupOptionsRuntimeMessage"),
            ])
        )
        XCTAssertTrue(response.serviceWorkerWakeAttempted)
        XCTAssertEqual(
            response.serviceWorkerLifecycleWakeResult?.sessionID,
            session.key.lifecycleSessionID
        )
        XCTAssertEqual(
            response.serviceWorkerLifecycleWakeResult?.sourceComponentKind,
            .extensionPageHostHarness
        )
    }

    func testRuntimeSendMessageNoListenerStaysPreciseWithSharedLifecycle()
        throws
    {
        let session = try makeSharedLifecycleSession()
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(),
            sharedLifecycleSession: session
        )

        let response = handler.handle(request(
            namespace: "runtime",
            methodName: "sendMessage",
            arguments: [.object(["ping": .bool(true)])]
        ))

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorCode, "noReceivingEnd")
        XCTAssertTrue(response.serviceWorkerWakeAttempted)
        XCTAssertEqual(
            response.serviceWorkerLifecycleWakeResult?.listenerEvent,
            .runtimeOnMessage
        )
        XCTAssertEqual(
            response.serviceWorkerLifecycleWakeResult?.blockers,
            ["No synthetic/model listener is registered."]
        )
        XCTAssertFalse(response.runtimeLoadable)
    }

    func testRuntimeConnectRoutesThroughSharedLifecycleWhenProvided()
        throws
    {
        let session = try makeSharedLifecycleSession()
        session.registerListener(
            event: .runtimeOnConnect,
            listenerID: "popup-runtime-on-connect"
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(),
            sharedLifecycleSession: session
        )

        let response = handler.handle(request(
            namespace: "runtime",
            methodName: "connect",
            arguments: [.object(["name": .string("popup-runtime")])],
            invocationMode: .fireAndForget
        ))

        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(
            stringValue(objectValue(response.resultPayload)?["portKind"]),
            "serviceWorkerRuntimePort"
        )
        XCTAssertTrue(response.serviceWorkerWakeAttempted)
        XCTAssertEqual(
            response.serviceWorkerLifecycleWakeResult?.listenerEvent,
            .runtimeOnConnect
        )
        XCTAssertEqual(
            response.serviceWorkerLifecycleWakeResult?.keepaliveRecord?.kind,
            .runtimePort
        )
        XCTAssertFalse(response.runtimeLoadable)
    }

    func testRuntimeConnectPortMessagesAndDisconnectUseCapturedDispatcher()
        throws
    {
        let session = try makeSharedLifecycleSession()
        registerRuntimePortEchoDispatchers(on: session)
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(),
            sharedLifecycleSession: session
        )

        let connect = handler.handle(request(
            namespace: "runtime",
            methodName: "connect",
            arguments: [.object(["name": .string("popup-runtime")])],
            invocationMode: .fireAndForget
        ))
        let portID = try XCTUnwrap(
            stringValue(objectValue(connect.resultPayload)?["portID"])
        )
        let post = handler.handle(request(
            namespace: "runtime",
            methodName: "port.postMessage",
            arguments: [
                .string(portID),
                .object(["ping": .bool(true)]),
            ],
            invocationMode: .fireAndForget
        ))
        let disconnect = handler.handle(request(
            namespace: "runtime",
            methodName: "port.disconnect",
            arguments: [.string(portID)],
            invocationMode: .fireAndForget
        ))
        let postPayload = try XCTUnwrap(objectValue(post.resultPayload))
        let postedMessages = try XCTUnwrap(postPayload["postedMessages"])
        guard case .array(let messages) = postedMessages,
              case .object(let firstMessage)? = messages.first
        else {
            XCTFail("Expected posted service-worker Port message.")
            return
        }

        XCTAssertTrue(connect.succeeded)
        XCTAssertEqual(
            stringValue(objectValue(connect.resultPayload)?["name"]),
            "popup-runtime"
        )
        XCTAssertTrue(post.succeeded)
        XCTAssertEqual(boolValue(postPayload["delivered"]), true)
        XCTAssertEqual(stringValue(firstMessage["portID"]), portID)
        XCTAssertEqual(
            objectValue(firstMessage["echo"]),
            ["ping": .bool(true)]
        )
        XCTAssertTrue(disconnect.succeeded)
        XCTAssertEqual(
            boolValue(objectValue(disconnect.resultPayload)?["disconnected"]),
            true
        )
        XCTAssertTrue(
            session.runtimeOwner.snapshot.activeKeepaliveRecords.isEmpty
        )
        XCTAssertTrue(handler.diagnosticsSnapshot.observedMethods.contains(
            "runtime.port.postMessage"
        ))
        XCTAssertTrue(handler.diagnosticsSnapshot.observedMethods.contains(
            "runtime.port.disconnect"
        ))
    }

    func testStorageAndPermissionEventsRouteThroughSharedLifecycleWhenProvided()
        throws
    {
        let session = try makeSharedLifecycleSession()
        session.registerListener(
            event: .storageOnChanged,
            listenerID: "popup-storage-on-changed"
        )
        session.registerListener(
            event: .permissionsOnAdded,
            listenerID: "popup-permissions-on-added"
        )
        let presenter = ChromeMV3TestPermissionPromptPresenter(
            disposition: .accepted
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                manifestOptionalPermissions: ["history"]
            ),
            permissionPromptPresenter: presenter,
            sharedLifecycleSession: session
        )

        let storage = handler.handle(request(
            namespace: "storage",
            methodName: "local.set",
            arguments: [.object(["alpha": .string("beta")])]
        ))
        let permission = handler.handle(request(
            namespace: "permissions",
            methodName: "request",
            arguments: [.object([
                "permissions": .array([.string("history")]),
            ])]
        ))

        XCTAssertTrue(storage.succeeded)
        XCTAssertTrue(storage.serviceWorkerWakeAttempted)
        XCTAssertEqual(
            storage.serviceWorkerLifecycleWakeResult?.reason,
            .storageChanged
        )
        XCTAssertEqual(
            storage.onChangedPayload?.serviceWorkerWakeRequired,
            true
        )
        XCTAssertTrue(permission.succeeded)
        XCTAssertTrue(permission.serviceWorkerWakeAttempted)
        XCTAssertEqual(
            permission.serviceWorkerLifecycleWakeResult?.listenerEvent,
            .permissionsOnAdded
        )
        XCTAssertEqual(
            Set(session.runtimeOwner.snapshot.events.map(\.reason)),
            Set([.storageChanged, .permissionsChanged])
        )
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

    func testPermissionsPromptPopupOptionsFlow() throws {
        let presenter = ChromeMV3TestPermissionPromptPresenter(
            disposition: .accepted
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                manifestPermissions: ["tabs"],
                manifestOptionalPermissions: ["history"],
                manifestOptionalHostPermissions: ["https://example.com/*"]
            ),
            permissionPromptPresenter: presenter
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
            ])]
        ))
        let requestOrigin = handler.handle(request(
            namespace: "permissions",
            methodName: "request",
            arguments: [.object([
                "origins": .array([.string("https://example.com/*")]),
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
        XCTAssertEqual(presenter.presentedRequests.count, 2)
        XCTAssertEqual(
            handler.diagnosticsSnapshot.permissionPromptResults
                .map(\.disposition),
            [.accepted, .accepted]
        )
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
        let hostHandler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                configuration(manifestHostPermissions: ["https://example.com/*"])
        )
        let noEndpointConnect = hostHandler.handle(request(
            namespace: "tabs",
            methodName: "connect",
            arguments: [.number(1)]
        ))
        XCTAssertFalse(noEndpointConnect.succeeded)
        XCTAssertEqual(noEndpointConnect.lastErrorCode, "noReceivingEnd")
    }

    func testTabsConnectPortDeliveryUsesContentScriptEndpointRegistry()
        throws
    {
        let extensionID = "popup-options-extension"
        let profileID = "popup-options-profile"
        let root = try makeTemporaryDirectory()
        try "void 0;\n".write(
            to: root.appendingPathComponent("content.js"),
            atomically: true,
            encoding: .utf8
        )
        let manifest = try ChromeMV3ManifestValidator.validateJSONObject([
            "manifest_version": 3,
            "name": "Popup Port Fixture",
            "version": "1.0.0",
            "host_permissions": ["https://example.com/*"],
            "content_scripts": [
                [
                    "matches": ["https://example.com/*"],
                    "js": ["content.js"],
                ],
            ],
        ])
        let plan = ChromeMV3ContentScriptAttachmentPlan.make(
            manifest: manifest,
            generatedBundleRootURL: root,
            extensionID: extensionID,
            profileID: profileID
        )
        let broker = ChromeMV3PermissionBroker(
            state: ChromeMV3PermissionBrokerState(
                extensionID: extensionID,
                profileID: profileID,
                hostPermissions: ["https://example.com/*"]
            )
        )
        let preflight = ChromeMV3NormalTabContentScriptPreflightEvaluator
            .evaluate(
                input: ChromeMV3NormalTabContentScriptPreflightInput(
                    moduleEnabled: true,
                    extensionEnabled: true,
                    productRuntimePreflightAllowsNormalTabAttachment: true,
                    contentScriptGate: .developerPreviewAllowed(),
                    attachmentPlan: plan,
                    permissionBroker: broker,
                    tabID: 7,
                    frameID: 0,
                    documentID: "document-1",
                    navigationSequence: 1,
                    urlString: "https://example.com/login",
                    tabSurface: .normalTab,
                    generatedBundleActive: true,
                    webKitUserContentControllerAvailable: true,
                    teardownPending: false
                )
            )
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        _ = registry.registerEndpoint(
            preflight: preflight,
            connectListenerRegistered: true
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                configuration(
                    manifestHostPermissions: ["https://example.com/*"]
                ),
            contentScriptEndpointRegistry: registry
        )

        let connect = handler.handle(request(
            namespace: "tabs",
            methodName: "connect",
            arguments: [
                .number(7),
                .object(["name": .string("popup-port")]),
            ],
            invocationMode: .fireAndForget
        ))
        let portID = try XCTUnwrap(
            stringValue(objectValue(connect.resultPayload)?["portID"])
        )
        let post = handler.handle(request(
            namespace: "tabs",
            methodName: "port.postMessage",
            arguments: [
                .string(portID),
                .object(["hello": .string("content")]),
            ],
            invocationMode: .fireAndForget
        ))
        let disconnect = handler.handle(request(
            namespace: "tabs",
            methodName: "port.disconnect",
            arguments: [.string(portID)],
            invocationMode: .fireAndForget
        ))

        XCTAssertTrue(connect.succeeded)
        XCTAssertEqual(
            stringValue(objectValue(connect.resultPayload)?["portKind"]),
            "contentScriptEndpointPort"
        )
        XCTAssertTrue(post.succeeded)
        XCTAssertTrue(disconnect.succeeded)
        XCTAssertEqual(registry.summary.portMessageCount, 1)
        XCTAssertEqual(registry.summary.activePortCount, 0)
        XCTAssertEqual(registry.summary.disconnectedPortCount, 1)
        XCTAssertTrue(handler.diagnosticsSnapshot.observedMethods.contains(
            "tabs.port.postMessage"
        ))
        XCTAssertTrue(handler.diagnosticsSnapshot.observedMethods.contains(
            "tabs.port.disconnect"
        ))
    }

    func testNativeMessagingBridgeRequiresTrustedHostApprovalAndRunsFixture()
        throws
    {
        let extensionID = "abcdefghijklmnopabcdefghijklmnop"
        let profileID = "popup-native-profile"
        let hostName = ChromeMV3NativeMessagingFixtureHostBuilder
            .passwordManagerFixtureHostName
        let root = try makeTemporaryDirectory()
        let fixtureRoot = root.appendingPathComponent(
            "native-hosts",
            isDirectory: true
        )
        _ = try ChromeMV3NativeMessagingFixtureHostBuilder.writeFixtureHost(
            kind: .echo,
            rootURL: fixtureRoot,
            hostName: hostName,
            extensionID: extensionID
        )

        var unapprovedConfig = configuration(
            extensionID: extensionID,
            profileID: profileID,
            manifestPermissions: ["nativeMessaging"]
        )
        unapprovedConfig.nativeMessagingFixtureHostRootPaths = [
            fixtureRoot.path,
        ]
        let unapproved = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: unapprovedConfig
        ).handle(request(
            namespace: "runtime",
            methodName: "send" + "NativeMessage",
            arguments: [
                .string(hostName),
                .object(["kind": .string("unapproved")]),
            ]
        ))

        let lookupPolicy = ChromeMV3NativeHostLookupPolicy.macOS(
            explicitTestRootPath: fixtureRoot.path
        )
        let approval = ChromeMV3NativeTrustedHostPolicyFactory
            .recordForExplicitDeveloperPreviewApproval(
                hostName: hostName,
                extensionID: extensionID,
                profileID: profileID,
                lookupPolicy: lookupPolicy,
                permissionState: .grantedByManifest,
                approvedRootPaths: [fixtureRoot.path],
                sequence: 1,
                now: Date(timeIntervalSince1970: 1)
            )
            .record
        var approvedConfig = unapprovedConfig
        approvedConfig.nativeMessagingTrustedHostApprovalRecords = [approval]
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: approvedConfig
        )
        let send = handler.handle(request(
            namespace: "runtime",
            methodName: "send" + "NativeMessage",
            arguments: [
                .string(hostName),
                .object(["kind": .string("send" + "NativeMessage")]),
            ]
        ))
        let connect = handler.handle(request(
            namespace: "runtime",
            methodName: "connect" + "Native",
            arguments: [.string(hostName)],
            invocationMode: .fireAndForget
        ))
        let portID = try XCTUnwrap(
            stringValue(objectValue(connect.resultPayload)?["portID"])
        )
        let post = handler.handle(request(
            namespace: "runtime",
            methodName: "nativePort.postMessage",
            arguments: [
                .string(portID),
                .object(["kind": .string("portMessage")]),
            ],
            invocationMode: .fireAndForget
        ))
        let disconnect = handler.handle(request(
            namespace: "runtime",
            methodName: "nativePort.disconnect",
            arguments: [.string(portID)],
            invocationMode: .fireAndForget
        ))
        let postResponse = objectValue(
            objectValue(post.resultPayload)?["response"]
        )

        XCTAssertFalse(unapproved.succeeded)
        XCTAssertEqual(unapproved.lastErrorCode, "trustedHostApprovalRequired")
        XCTAssertFalse(unapproved.nativeHostLaunchAttempted)

        XCTAssertTrue(send.succeeded, send.diagnostics.joined(separator: "\n"))
        XCTAssertTrue(send.nativeHostLaunchAttempted)
        XCTAssertEqual(
            stringValue(objectValue(objectValue(send.resultPayload)?["echo"])?["kind"]),
            "send" + "NativeMessage"
        )
        XCTAssertTrue(connect.succeeded)
        XCTAssertTrue(connect.nativeHostLaunchAttempted)
        XCTAssertEqual(
            stringValue(objectValue(connect.resultPayload)?["portKind"]),
            "nativeMessagingTrustedFixturePort"
        )
        XCTAssertTrue(post.succeeded)
        XCTAssertEqual(
            stringValue(objectValue(postResponse?["echo"])?["kind"]),
            "portMessage"
        )
        XCTAssertTrue(disconnect.succeeded)
        XCTAssertFalse(disconnect.serviceWorkerWakeAttempted)
    }

    func testNativeMessagingUnavailableReturnsChromeHostErrorWithoutLaunch() {
        let expected = ChromeMV3NativeMessagingRuntimeErrorCode
            .hostManifestMissing.lastErrorMessage
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                manifestPermissions: ["nativeMessaging"]
            )
        )

        let send = handler.handle(request(
            namespace: "runtime",
            methodName: "send" + "NativeMessage",
            arguments: [
                .string("com.bitwarden.desktop"),
                .object(["kind": .string("probe")]),
            ]
        ))
        let connect = handler.handle(request(
            namespace: "runtime",
            methodName: "connect" + "Native",
            arguments: [.string("com.bitwarden.desktop")],
            invocationMode: .fireAndForget
        ))

        XCTAssertFalse(send.succeeded)
        XCTAssertEqual(send.lastErrorMessage, expected)
        XCTAssertEqual(send.lastErrorCode, "hostManifestMissing")
        XCTAssertFalse(send.nativeHostLaunchAttempted)
        XCTAssertFalse(connect.succeeded)
        XCTAssertEqual(connect.lastErrorMessage, expected)
        XCTAssertEqual(connect.lastErrorCode, "hostManifestMissing")
        XCTAssertFalse(connect.nativeHostLaunchAttempted)
        XCTAssertTrue(send.diagnostics.contains {
            $0.contains("Product native messaging remains unavailable")
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
    func testControlledPopupHostLoadsRealBitwardenDefaultPopupWithExistingBridge()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("WKWebView extension-page bridge POC requires macOS 15.5.")
        }

        let packageRoot = URL(
            fileURLWithPath:
                "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/bitwarden",
            isDirectory: true
        )
        try XCTSkipUnless(
            FileManager.default.fileExists(
                atPath: packageRoot.appendingPathComponent("manifest.json").path
            ),
            "Bitwarden real package fixture is not available."
        )
        #if canImport(AppKit)
        let nativeHostWasRunning =
            bitwardenNativeHostRunningApplicationIdentifiers()
        #endif

        let storeRoot = try makeTemporaryDirectory()
        let stage = try ChromeMV3OriginalBundleStore(
            rootURL: storeRoot,
            now: { Date(timeIntervalSince1970: 601) }
        ).stageUnpackedDirectory(at: packageRoot)
        let generated = try ChromeMV3GeneratedBundleWriter(rootURL: storeRoot)
            .writeGeneratedBundle(
                originalBundleRecord: stage.originalBundleRecord,
                manifestSnapshot: stage.manifestSnapshot,
                planningRecord: stage.generatedBundlePlan
            )
        let popupURL = generated.generatedBundleRootURL
            .appendingPathComponent("popup/index.html")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: popupURL.path),
            "Bitwarden generated action.default_popup was not preserved."
        )
        let popupHTML = try String(contentsOf: popupURL, encoding: .utf8)
        XCTAssertTrue(popupHTML.contains("<title>Bitwarden</title>"))
        XCTAssertTrue(popupHTML.contains("<app-root>"))
        XCTAssertTrue(popupHTML.contains("id=\"loading\""))

        for path in [
            "_locales/en/messages.json",
            "popup/index.html",
            "popup/main.css",
            "popup/main.js",
            "popup/polyfills.js",
            "popup/vendor-angular.js",
            "popup/vendor.js",
        ] {
            XCTAssertTrue(generated.record.copiedResourcePaths.contains(path), path)
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: generated.generatedBundleRootURL
                        .appendingPathComponent(path)
                        .path
                ),
                path
            )
        }

        let manifest = stage.manifestSnapshot.normalizedManifest
        let config = configuration(
            extensionID: "bitwarden-real-local",
            profileID: "profile-controlled-bitwarden-popup-poc",
            manifestPermissions: manifest.permissions,
            manifestOptionalPermissions: manifest.optionalPermissions,
            manifestHostPermissions: manifest.hostPermissions,
            manifestOptionalHostPermissions: manifest.optionalHostPermissions
        )
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
            loadFileURL: popupURL,
            readAccessURL: generated.generatedBundleRootURL,
            bridgeInstallation: installation,
            permissionPromptPresenter: nil,
            permissionEventDispatcher: nil
        )
        defer { handle.tearDown() }

        try await handle.waitForLoadForTesting()
        let raw = try await handle.callAsyncJavaScriptForTesting(
            """
            return {
              title: document.title,
              hasAppRoot: !!document.querySelector("app-root"),
              hasLoadingShell: !!document.querySelector("#loading"),
              scriptSrcs: Array.from(document.scripts)
                .map((script) => script.getAttribute("src") || ""),
              stylesheetHrefs: Array.from(
                  document.querySelectorAll('link[rel="stylesheet"]')
                )
                .map((link) => link.getAttribute("href") || ""),
              hasChromeRuntime:
                !!globalThis.chrome
                && !!chrome.runtime
                && typeof chrome.runtime.sendMessage === "function",
              hasBrowserRuntime:
                !!globalThis.browser
                && !!browser.runtime
                && typeof browser.runtime.connect === "function",
              hasChromeTabs:
                !!globalThis.chrome
                && !!chrome.tabs
                && typeof chrome.tabs.query === "function"
            };
            """
        )
        let object = try XCTUnwrap(raw as? [String: Any])
        let scriptSrcs = try XCTUnwrap(object["scriptSrcs"] as? [String])
        let stylesheetHrefs = try XCTUnwrap(
            object["stylesheetHrefs"] as? [String]
        )

        XCTAssertEqual(object["title"] as? String, "Bitwarden")
        XCTAssertEqual(object["hasAppRoot"] as? Bool, true)
        XCTAssertTrue(scriptSrcs.contains("../popup/polyfills.js"))
        XCTAssertTrue(scriptSrcs.contains("../popup/vendor.js"))
        XCTAssertTrue(scriptSrcs.contains("../popup/vendor-angular.js"))
        XCTAssertTrue(scriptSrcs.contains("../popup/main.js"))
        XCTAssertTrue(stylesheetHrefs.contains("../popup/main.css"))
        XCTAssertEqual(object["hasChromeRuntime"] as? Bool, true)
        XCTAssertEqual(object["hasBrowserRuntime"] as? Bool, true)
        XCTAssertEqual(object["hasChromeTabs"] as? Bool, true)
        XCTAssertEqual(handle.installedUserScriptCount, 1)
        XCTAssertEqual(handle.installedScriptMessageHandlerCount, 1)
        let snapshot = try XCTUnwrap(
            handle.popupOptionsBridgeDiagnosticsSnapshot
        )
        XCTAssertTrue(snapshot.callRecords.allSatisfy {
            $0.nativeHostLaunchAttempted == false
        })
        #if canImport(AppKit)
        XCTAssertEqual(
            bitwardenNativeHostRunningApplicationIdentifiers(),
            nativeHostWasRunning,
            "The controlled popup-host POC must not launch com.bitwarden.desktop."
        )
        #endif
    }

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
        let config = configuration(
            manifestPermissions: ["tabs"],
            manifestHostPermissions: ["https://example.com/*"]
        )
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
            bridgeInstallation: installation,
            permissionPromptPresenter: nil,
            permissionEventDispatcher: nil
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

    @MainActor
    func testRealPopupOptionsWKWebViewReportsNativeMessagingUnavailableLikeChrome()
        async throws
    {
        let root = try makeTemporaryDirectory()
        let htmlURL = root.appendingPathComponent("popup.html")
        try """
        <!doctype html>
        <meta charset="utf-8">
        <title>Popup Native Messaging</title>
        <main data-sumi-extension-page-fixture-marker="safe">Popup</main>
        """.write(to: htmlURL, atomically: true, encoding: .utf8)
        let config = configuration(
            manifestPermissions: ["nativeMessaging"]
        )
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
            bridgeInstallation: installation,
            permissionPromptPresenter: nil,
            permissionEventDispatcher: nil
        )
        defer { handle.tearDown() }

        try await handle.waitForLoadForTesting()
        let raw = try await handle.callAsyncJavaScriptForTesting(
            """
            const host = "com.bitwarden.desktop";
            let callbackArgCount = -1;
            let callbackLastErrorInside = null;
            await new Promise((resolve) => {
              chrome.runtime.sendNativeMessage(host, {kind: "callback"}, function() {
                callbackArgCount = arguments.length;
                callbackLastErrorInside = chrome.runtime.lastError
                  ? chrome.runtime.lastError.message
                  : null;
                resolve();
              });
            });
            const callbackLastErrorOutside = chrome.runtime.lastError || null;
            let promiseError = null;
            try {
              await chrome.runtime.sendNativeMessage(host, {kind: "promise"});
            } catch (error) {
              promiseError = error.message;
            }
            const port = chrome.runtime.connectNative(host);
            let disconnectCount = 0;
            let disconnectLastErrorInside = null;
            port.onDisconnect.addListener(() => {
              disconnectCount += 1;
              disconnectLastErrorInside = chrome.runtime.lastError
                ? chrome.runtime.lastError.message
                : null;
            });
            await chrome.runtime.sendMessage({kind: "flushNativeUnavailable"}).catch(() => undefined);
            const disconnectLastErrorOutside = chrome.runtime.lastError || null;
            return {
              callbackArgCount,
              callbackLastErrorInside,
              callbackLastErrorOutside,
              promiseError,
              disconnectCount,
              disconnectLastErrorInside,
              disconnectLastErrorOutside,
              nativeMessagingMissing: chrome.nativeMessaging === undefined
            };
            """
        )
        let object = try XCTUnwrap(raw as? [String: Any])
        let expected = ChromeMV3NativeMessagingRuntimeErrorCode
            .hostManifestMissing.lastErrorMessage

        XCTAssertEqual(object["callbackArgCount"] as? Int, 0)
        XCTAssertEqual(object["callbackLastErrorInside"] as? String, expected)
        XCTAssertTrue(object["callbackLastErrorOutside"] is NSNull)
        XCTAssertEqual(object["promiseError"] as? String, expected)
        XCTAssertEqual(object["disconnectCount"] as? Int, 1)
        XCTAssertEqual(object["disconnectLastErrorInside"] as? String, expected)
        XCTAssertTrue(
            object["disconnectLastErrorOutside"] == nil
                || object["disconnectLastErrorOutside"] is NSNull,
            String(describing: object["disconnectLastErrorOutside"])
        )
        XCTAssertNotNil(object["nativeMessagingMissing"] as? Bool)
        let snapshot = try XCTUnwrap(
            handle.popupOptionsBridgeDiagnosticsSnapshot
        )
        XCTAssertTrue(snapshot.callRecords.allSatisfy {
            $0.nativeHostLaunchAttempted == false
        })
        XCTAssertTrue(snapshot.observedMethods.contains(
            "runtime.send" + "NativeMessage"
        ))
        XCTAssertTrue(snapshot.observedMethods.contains(
            "runtime.connect" + "Native"
        ))
    }
    #endif

    #if canImport(AppKit)
    private func bitwardenNativeHostRunningApplicationIdentifiers() -> [String] {
        NSWorkspace.shared.runningApplications
            .compactMap(\.bundleIdentifier)
            .filter { $0 == "com.bitwarden.desktop" }
            .sorted()
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
        manifestOptionalHostPermissions: [String] = [],
        activeTabGrants: [ChromeMV3ActiveTabGrant] = []
    ) -> ChromeMV3PopupOptionsJSBridgeConfiguration {
        ChromeMV3PopupOptionsJSBridgeConfiguration(
            extensionID: extensionID,
            profileID: profileID,
            surfaceID: "\(profileID):\(extensionID):\(surface.rawValue)",
            surface: surface,
            extensionBaseURLString: "chrome-extension://\(extensionID)/",
            permissionStateRootPath: nil,
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
            activeTabGrants: activeTabGrants,
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

    private func makeSharedLifecycleSession(
        profileID: String = "popup-options-profile",
        extensionID: String = "popup-options-extension"
    ) throws -> ChromeMV3ServiceWorkerSharedLifecycleSession {
        try XCTUnwrap(
            ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
                .session(profileID: profileID, extensionID: extensionID)
        )
    }

    private func registerRuntimePortEchoDispatchers(
        on session: ChromeMV3ServiceWorkerSharedLifecycleSession
    ) {
        session.registerJSListenerDispatcher(
            event: .runtimeOnConnect,
            listenerID: "popup-js-runtime-on-connect"
        ) { input in
            let name: String
            if case .object(let object)? = input.arguments.first,
               case .string(let portName)? = object["name"]
            {
                name = portName
            } else {
                name = ""
            }
            let responsePayload: ChromeMV3StorageValue = .object([
                "name": .string(name),
                "portID": .string(input.portID ?? ""),
            ])
            session.registerListener(
                event: input.event,
                listenerID: "popup-js-runtime-on-connect-executed",
                outcome: .modelDispatched(responsePayload)
            )
            let wake = session.routeEvent(
                reason: input.source.wakeReason,
                listenerEvent: input.event,
                sourceComponentID: input.sourceComponentID,
                sourceComponentKind: input.sourceComponentKind,
                payload: input.arguments.first,
                payloadSummary: input.payloadSummary,
                sourceContext: input.source.sourceContext,
                keepaliveKind: input.keepaliveKind,
                portID: input.portID
            )
            session.registerRuntimePortMessageDispatcher(
                dispatcherID: "popup-test-runtime-port-message"
            ) { portInput in
                let wake = session.routeEvent(
                    reason: portInput.source.wakeReason,
                    listenerEvent: .runtimeOnConnect,
                    sourceComponentID: portInput.sourceComponentID,
                    sourceComponentKind: portInput.sourceComponentKind,
                    payload: portInput.message,
                    payloadSummary: portInput.payloadSummary,
                    sourceContext: portInput.source.sourceContext,
                    portID: portInput.portID
                )
                return ChromeMV3ServiceWorkerRuntimePortDeliveryResult(
                    portID: portInput.portID,
                    delivered: true,
                    connected: true,
                    postedMessages: [
                        .object([
                            "echo": portInput.message ?? .null,
                            "portID": .string(portInput.portID),
                        ]),
                    ],
                    onMessageListenerCount: 1,
                    onDisconnectListenerCount: 1,
                    disconnectReason: nil,
                    lastErrorMessage: nil,
                    lifecycleWakeResult: wake,
                    diagnostics: [
                        "Test runtime Port message dispatcher echoed a service-worker Port.postMessage response.",
                    ]
                )
            }
            session.registerRuntimePortDisconnectDispatcher(
                dispatcherID: "popup-test-runtime-port-disconnect"
            ) { portInput in
                _ = session.disconnectKeepalive(portID: portInput.portID)
                return ChromeMV3ServiceWorkerRuntimePortDeliveryResult(
                    portID: portInput.portID,
                    delivered: true,
                    connected: false,
                    postedMessages: [],
                    onMessageListenerCount: 1,
                    onDisconnectListenerCount: 1,
                    disconnectReason: portInput.disconnectReason,
                    lastErrorMessage: nil,
                    lifecycleWakeResult: nil,
                    diagnostics: [
                        "Test runtime Port disconnect dispatcher released keepalive state.",
                    ]
                )
            }
            return ChromeMV3ServiceWorkerJSListenerDispatchResult(
                event: input.event,
                listenerID: "popup-js-runtime-on-connect",
                resultKind: wake.dispatched ? .delivered : .noReceiver,
                responsePayload: wake.responsePayload,
                lastErrorMessage: wake.lastErrorMessage,
                lifecycleWakeResult: wake,
                diagnostics: [
                    "Popup test JS onConnect dispatcher routed through shared lifecycle.",
                ]
            )
        }
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
