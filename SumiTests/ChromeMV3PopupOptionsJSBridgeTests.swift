import Foundation
import XCTest

#if canImport(AppKit)
import AppKit
#endif

#if canImport(WebKit)
import WebKit
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

    func testControlledActionPopupPolicyRoutesRuntimeAndBlocksForbiddenAPIs()
        throws
    {
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                allowlist: .controlledActionPopupPolicy
            )
        )

        let runtime = handler.handle(request(
            namespace: "runtime",
            methodName: "sendMessage",
            arguments: [
                .object([
                    "command": .string("popup-opened"),
                    "token": .string("must-not-appear"),
                ]),
            ]
        ))
        let storageSet = handler.handle(request(
            namespace: "storage",
            methodName: "local.set",
            arguments: [
                .object([
                    "authToken": .string("must-not-appear"),
                ]),
            ]
        ))
        let storage = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("authToken")]
        ))
        let sessionSet = handler.handle(request(
            namespace: "storage",
            methodName: "session.set",
            arguments: [
                .object([
                    "sessionSecret": .string("must-not-appear"),
                ]),
            ]
        ))
        let session = handler.handle(request(
            namespace: "storage",
            methodName: "session.get",
            arguments: [.object(["sessionSecret": .bool(false)])]
        ))
        let native = handler.handle(request(
            namespace: "runtime",
            methodName: "sendNativeMessage",
            arguments: [
                .string("com.bitwarden.desktop"),
                .object(["token": .string("must-not-appear")]),
            ]
        ))

        XCTAssertFalse(runtime.succeeded)
        XCTAssertEqual(runtime.lastErrorCode, "noReceivingEnd")
        XCTAssertFalse(runtime.nativeHostLaunchAttempted)
        XCTAssertTrue(storageSet.succeeded)
        XCTAssertEqual(storageSet.resultPayload, .null)
        XCTAssertFalse(storageSet.nativeHostLaunchAttempted)
        XCTAssertTrue(storage.succeeded)
        XCTAssertEqual(
            storage.resultPayload,
            .object(["authToken": .string("must-not-appear")])
        )
        XCTAssertNil(storage.blockedAPIDiagnostic)
        XCTAssertFalse(storage.nativeHostLaunchAttempted)
        XCTAssertTrue(sessionSet.succeeded)
        XCTAssertEqual(sessionSet.onChangedPayload?.areaName, "session")
        XCTAssertTrue(session.succeeded)
        XCTAssertEqual(
            session.resultPayload,
            .object(["sessionSecret": .string("must-not-appear")])
        )
        XCTAssertFalse(session.nativeHostLaunchAttempted)
        XCTAssertFalse(native.succeeded)
        XCTAssertEqual(native.blockedAPIDiagnostic?.namespace, "runtime")
        XCTAssertEqual(
            native.blockedAPIDiagnostic?.methodName,
            "sendNativeMessage"
        )
        XCTAssertFalse(native.nativeHostLaunchAttempted)

        let snapshot = handler.diagnosticsSnapshot
        XCTAssertTrue(snapshot.observedMethods.contains("runtime.sendMessage"))
        XCTAssertTrue(snapshot.observedMethods.contains("storage.local.set"))
        XCTAssertTrue(snapshot.observedMethods.contains("storage.local.get"))
        XCTAssertTrue(snapshot.observedMethods.contains("storage.session.set"))
        XCTAssertTrue(snapshot.observedMethods.contains("storage.session.get"))
        XCTAssertTrue(
            snapshot.observedMethods.contains("runtime.sendNativeMessage")
        )
        XCTAssertTrue(snapshot.sanitizedBridgeRouteRecords.contains {
            $0.apiName == "runtime.sendMessage"
                && $0.safeCommandTypeActionFieldNames == ["command"]
        })
        XCTAssertFalse(snapshot.blockedAPIs.contains {
            $0.namespace == "storage" && $0.methodName == "local.*"
        })
        XCTAssertTrue(snapshot.sanitizedBridgeRouteRecords.contains {
            $0.apiName == "storage.local.set"
                && $0.targetContext == "storage.local"
                && $0.resultClassifier == "storageLocalBrokerSucceeded"
                && $0.safeMessageShapeClassification.contains("keyCount=1")
        })
        XCTAssertTrue(snapshot.sanitizedBridgeRouteRecords.contains {
            $0.apiName == "storage.local.get"
                && $0.targetContext == "storage.local"
                && $0.resultClassifier == "storageLocalBrokerSucceeded"
                && $0.safeMessageShapeClassification.contains(
                    "keyShape=singleString"
                )
        })
        XCTAssertTrue(snapshot.sanitizedBridgeRouteRecords.contains {
            $0.apiName == "storage.session.set"
                && $0.targetContext == "storage.session"
                && $0.resultClassifier == "storageSessionBrokerSucceeded"
                && $0.safeMessageShapeClassification.contains("keyCount=1")
        })
        XCTAssertTrue(snapshot.sanitizedBridgeRouteRecords.contains {
            $0.apiName == "storage.session.get"
                && $0.targetContext == "storage.session"
                && $0.resultClassifier == "storageSessionBrokerSucceeded"
                && $0.safeMessageShapeClassification.contains(
                    "keyShape=objectDefaults"
                )
        })
        XCTAssertTrue(snapshot.appStateDependencyTrace.enabled)
        XCTAssertEqual(
            snapshot.appStateDependencyTrace.storageOperations.filter {
                $0.context == "popup"
            }.count,
            4
        )
        XCTAssertTrue(
            snapshot.appStateDependencyTrace.storageOperations.allSatisfy {
                $0.keyHashes.allSatisfy {
                    $0.hasPrefix("redacted-key:length=")
                        && $0.contains(":saltedHash=")
                }
            }
        )
        XCTAssertEqual(
            snapshot.appStateDependencyTrace.correlationSummary
                .popupReadKeyHashesNeverWritten,
            []
        )
        XCTAssertFalse(
            snapshot.appStateDependencyTrace.correlationSummary
                .serviceWorkerStorageWritesAfterConnect
        )
        XCTAssertTrue(snapshot.blockedAPIs.contains {
            $0.namespace == "runtime"
                && $0.methodName == "sendNativeMessage"
        })
        let encoded = String(
            data: try JSONEncoder().encode(snapshot),
            encoding: .utf8
        ) ?? ""
        XCTAssertFalse(encoded.contains("must-not-appear"))
        XCTAssertFalse(encoded.contains("authToken"))
        XCTAssertFalse(encoded.contains("sessionSecret"))
        XCTAssertFalse(encoded.contains("com.bitwarden.desktop"))
    }

    @MainActor
    func testControlledActionPopupExecutesPackagedFileExecuteScriptOrFailsPrecisely()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let root = try makeTemporaryDirectory()
        let assets = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(
            at: assets,
            withIntermediateDirectories: true
        )
        try "globalThis.__sumiExecuteScriptFixture = 42; 42".write(
            to: assets.appendingPathComponent("parse.js"),
            atomically: true,
            encoding: .utf8
        )
        let extensionID = "popup-options-extension"
        let profileID = "popup-options-profile"
        let activeTabGrant = ChromeMV3ActiveTabGrant(
            extensionID: extensionID,
            profileID: profileID,
            tabID: 1,
            scope: .origin("https://example.com"),
            reason: .actionClick,
            userGestureModeled: true,
            createdSequence: 1,
            diagnostics: ["test activeTab grant"]
        )
        let baseConfiguration = configuration(
            extensionID: extensionID,
            profileID: profileID,
            manifestPermissions: ["activeTab", "scripting"],
            activeTabGrants: [activeTabGrant],
            allowlist: .controlledActionPopupPolicy,
            generatedBundleRootPath: root.path
        )
        let missingTargetHandler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: baseConfiguration
        )
        let executeRequest = request(
            namespace: "scripting",
            methodName: "executeScript",
            arguments: [
                .object([
                    "target": .object(["tabId": .number(1)]),
                    "files": .array([.string("assets/parse.js")]),
                    "injectImmediately": .bool(true),
                ]),
            ]
        )

        let missingTarget = await missingTargetHandler.handleAsync(
            executeRequest
        )
        XCTAssertFalse(missingTarget.succeeded)
        XCTAssertEqual(missingTarget.lastErrorCode, "contextNotLoaded")
        XCTAssertNil(missingTarget.resultPayload)
        XCTAssertTrue(
            missingTarget.diagnostics.contains {
                $0.contains("targetWebViewUnavailable")
                    || $0.contains(
                        "no eligible normal-tab WKWebView target"
                    )
            }
        )
        XCTAssertTrue(
            missingTarget.diagnostics.contains("scripting.executeScript allFrames=false.")
        )
        XCTAssertTrue(
            missingTarget.diagnostics.contains("scripting.executeScript frameIds=0")
        )
        XCTAssertTrue(
            missingTarget.diagnostics.contains(
                "scripting.executeScript world=ISOLATED(default)."
            )
        )
        XCTAssertTrue(
            missingTarget.diagnostics.contains(
                "scripting.executeScript injectImmediately=true."
            )
        )
        XCTAssertFalse(missingTarget.nativeHostLaunchAttempted)

        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: webViewConfiguration)
        let navigation = webView.loadHTMLString(
            "<!doctype html><title>fixture</title>",
            baseURL: URL(string: "https://example.com/")!
        )
        let navigationObserver = ChromeMV3PopupOptionsExecuteScriptTestNavigationObserver()
        webView.navigationDelegate = navigationObserver
        _ = try await navigationObserver.wait(navigation: navigation)
        let contentWorldName =
            "sumi.mv3.content.\(profileID).\(extensionID)"
        let executingHandler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: baseConfiguration,
            scriptingExecuteScriptTargetProvider: {
                _, _, tabID, frameID in
                guard tabID == 1, frameID == 0 else { return nil }
                return ChromeMV3ScriptingExecuteScriptWebViewTarget(
                    webView: webView,
                    contentWorld: WKContentWorld.world(
                        name: contentWorldName
                    ),
                    contentWorldName: contentWorldName,
                    frameID: 0,
                    localTabID: 1
                )
            }
        )
        let packaged = await executingHandler.handleAsync(executeRequest)

        XCTAssertTrue(
            packaged.succeeded,
            "packaged executeScript failed: \(packaged.lastErrorCode ?? "nil") \(packaged.diagnostics.joined(separator: " | "))"
        )
        XCTAssertNil(packaged.lastErrorCode)
        guard case .array(let results) = packaged.resultPayload else {
            return XCTFail("Expected InjectionResult array payload.")
        }
        XCTAssertEqual(results.count, 1)
        guard case .object(let first) = results[0] else {
            return XCTFail("Expected object InjectionResult.")
        }
        XCTAssertEqual(first["frameId"], .number(0))
        XCTAssertEqual(first["result"], .number(42))
        XCTAssertTrue(
            packaged.diagnostics.contains("executionClassifier=filesExecuted")
        )
        XCTAssertTrue(
            packaged.diagnostics.contains {
                $0.contains("No fake executeScript success")
            }
        )

        let remote = await executingHandler.handleAsync(request(
            namespace: "scripting",
            methodName: "executeScript",
            arguments: [
                .object([
                    "target": .object(["tabId": .number(1)]),
                    "files": .array([
                        .string("https://cdn.example.test/remote.js"),
                    ]),
                ]),
            ]
        ))
        let inlineFunction = await executingHandler.handleAsync(request(
            namespace: "scripting",
            methodName: "executeScript",
            arguments: [
                .object([
                    "target": .object(["tabId": .number(1)]),
                    "functionSource": .string("() => 1"),
                ]),
            ]
        ))
        let mainWorld = await executingHandler.handleAsync(request(
            namespace: "scripting",
            methodName: "executeScript",
            arguments: [
                .object([
                    "target": .object(["tabId": .number(1)]),
                    "files": .array([.string("assets/parse.js")]),
                    "world": .string("MAIN"),
                ]),
            ]
        ))
        let conflictingFrames = await executingHandler.handleAsync(request(
            namespace: "scripting",
            methodName: "executeScript",
            arguments: [
                .object([
                    "target": .object([
                        "tabId": .number(1),
                        "allFrames": .bool(true),
                        "frameIds": .array([.number(0)]),
                    ]),
                    "files": .array([.string("assets/parse.js")]),
                ]),
            ]
        ))
        let allFramesOnly = await executingHandler.handleAsync(request(
            namespace: "scripting",
            methodName: "executeScript",
            arguments: [
                .object([
                    "target": .object([
                        "tabId": .number(1),
                        "allFrames": .bool(true),
                    ]),
                    "files": .array([.string("assets/parse.js")]),
                ]),
            ]
        ))

        XCTAssertFalse(remote.succeeded)
        XCTAssertEqual(remote.lastErrorCode, "unsupportedAPI")
        XCTAssertTrue(
            remote.diagnostics.contains("No remote executable code was allowed.")
        )

        XCTAssertFalse(inlineFunction.succeeded)
        XCTAssertEqual(inlineFunction.lastErrorCode, "unsupportedAPI")
        XCTAssertTrue(
            inlineFunction.diagnostics.contains {
                $0.contains("function/inline execution is not exposed")
            }
        )

        XCTAssertFalse(mainWorld.succeeded)
        XCTAssertEqual(mainWorld.lastErrorCode, "unsupportedAPI")
        XCTAssertTrue(
            mainWorld.diagnostics.contains {
                $0.contains("MAIN-world execution is not exposed")
            }
        )

        XCTAssertFalse(conflictingFrames.succeeded)
        XCTAssertEqual(
            conflictingFrames.lastErrorMessage,
            "scripting.executeScript target.frameIds and target.allFrames cannot both be specified."
        )
        XCTAssertFalse(allFramesOnly.succeeded)
        XCTAssertEqual(
            allFramesOnly.lastErrorCode,
            "unsupportedAPI",
            "allFramesOnly diagnostics: \(allFramesOnly.diagnostics.joined(separator: " | "))"
        )
        XCTAssertTrue(
            allFramesOnly.diagnostics.contains {
                $0.contains("allFrames=true is not supported")
            }
        )
    }

    func testAppStateDependencyTraceClassifiesRepeatedEmptyPopupReadsWithoutWriter()
        throws
    {
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                allowlist: .controlledActionPopupPolicy
            )
        )

        let sensitiveStorageKey = "authTokenVaultSecretMustNotAppear"
        let first = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string(sensitiveStorageKey)]
        ))
        let second = handler.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string(sensitiveStorageKey)]
        ))

        XCTAssertTrue(first.succeeded)
        XCTAssertEqual(first.resultPayload, .object([:]))
        XCTAssertTrue(second.succeeded)
        XCTAssertEqual(second.resultPayload, .object([:]))

        let trace = handler.diagnosticsSnapshot.appStateDependencyTrace
        XCTAssertEqual(
            trace.correlationSummary.classification,
            "appStateWaitWithNoWriter"
        )
        XCTAssertEqual(trace.storageOperations.count, 2)
        XCTAssertEqual(
            trace.correlationSummary.popupReadKeyHashesNeverWritten.count,
            1
        )
        XCTAssertEqual(
            trace.correlationSummary.repeatedEmptyReadKeyHashes,
            trace.correlationSummary.popupReadKeyHashesNeverWritten
        )
        XCTAssertFalse(
            trace.correlationSummary.serviceWorkerStorageWritesAfterConnect
        )
        XCTAssertFalse(
            trace.correlationSummary
                .storageOnChangedReachedRegisteredListeners
        )

        let encoded = String(
            data: try JSONEncoder().encode(trace),
            encoding: .utf8
        ) ?? ""
        XCTAssertFalse(encoded.contains(sensitiveStorageKey))
        XCTAssertFalse(encoded.contains("authToken"))
        XCTAssertFalse(encoded.contains("Vault"))
        XCTAssertFalse(encoded.contains("Secret"))
        XCTAssertTrue(encoded.contains("redacted-key:length="))
        XCTAssertTrue(encoded.contains(":saltedHash="))
        XCTAssertTrue(
            encoded.contains(
                "No raw storage keys or values are recorded by the app-state dependency tracer."
            )
        )
    }

    func testControlledActionPopupStorageSessionIsMemoryScopedAndLocalPersists()
        throws
    {
        let storageRoot = try makeTemporaryDirectory()
        let config = configuration(
            extensionID: "storage-session-extension",
            profileID: "storage-session-profile",
            allowlist: .controlledActionPopupPolicy,
            storageLocalRootPath: storageRoot.path
        )
        let first = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: config
        )

        let localSet = first.handle(request(
            namespace: "storage",
            methodName: "local.set",
            arguments: [.object(["localKey": .string("persisted")])]
        ))
        let sessionSet = first.handle(request(
            namespace: "storage",
            methodName: "session.set",
            arguments: [
                .object([
                    "sessionKey": .object([
                        "kind": .string("shape-only"),
                        "enabled": .bool(true),
                    ]),
                ]),
            ],
            invocationMode: .callback
        ))
        let sessionBytes = first.handle(request(
            namespace: "storage",
            methodName: "session.getBytesInUse",
            arguments: [.array([.string("sessionKey")])]
        ))
        let sessionRemove = first.handle(request(
            namespace: "storage",
            methodName: "session.remove",
            arguments: [.string("sessionKey")]
        ))
        let sessionClear = first.handle(request(
            namespace: "storage",
            methodName: "session.clear"
        ))

        XCTAssertTrue(localSet.succeeded)
        XCTAssertTrue(sessionSet.succeeded)
        XCTAssertEqual(sessionSet.onChangedPayload?.areaName, "session")
        XCTAssertGreaterThan(numberValue(sessionBytes.resultPayload) ?? 0, 0)
        XCTAssertTrue(sessionRemove.succeeded)
        XCTAssertEqual(sessionRemove.onChangedPayload?.areaName, "session")
        XCTAssertTrue(sessionClear.succeeded)

        let paths = FileManager.default
            .enumerator(atPath: storageRoot.path)?
            .compactMap { $0 as? String } ?? []
        XCTAssertTrue(paths.contains {
            $0.hasSuffix("local/storage-snapshot.json")
        })
        XCTAssertFalse(paths.contains {
            $0.contains("/session/")
                || $0.hasPrefix("session/")
                || $0.contains("session/storage-snapshot.json")
        })

        let second = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: config
        )
        let reloadedLocal = second.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("localKey")]
        ))
        let reloadedSession = second.handle(request(
            namespace: "storage",
            methodName: "session.get",
            arguments: [.object(["sessionKey": .bool(false)])]
        ))

        XCTAssertEqual(
            reloadedLocal.resultPayload,
            .object(["localKey": .string("persisted")])
        )
        XCTAssertEqual(
            reloadedSession.resultPayload,
            .object(["sessionKey": .bool(false)])
        )

        let snapshot = first.diagnosticsSnapshot
        let encoded = String(
            data: try JSONEncoder().encode(snapshot),
            encoding: .utf8
        ) ?? ""
        XCTAssertTrue(snapshot.storageOnChangedPayloadCount >= 2)
        XCTAssertTrue(snapshot.sanitizedBridgeRouteRecords.contains {
            $0.apiName == "storage.session.getBytesInUse"
                && $0.targetContext == "storage.session"
                && $0.resultClassifier == "storageSessionBrokerSucceeded"
        })
        XCTAssertTrue(encoded.contains("area=session"))
        XCTAssertTrue(encoded.contains("valueShape=object:keyCount=1"))
        XCTAssertFalse(encoded.contains("sessionKey"))
        XCTAssertFalse(encoded.contains("shape-only"))
    }

    func testControlledRuntimeGetManifestReturnsGeneratedManifestCloneWithoutInternalMetadata()
        throws
    {
        let manifest: ChromeMV3StorageValue = .object([
            "manifest_version": .number(3),
            "name": .string("__MSG_appName__"),
            "version": .string("2026.1.0"),
            "action": .object([
                "default_popup": .string("popup/index.html"),
            ]),
            "permissions": .array([.string("storage"), .string("tabs")]),
            "optional_permissions": .array([.string("nativeMessaging")]),
            "host_permissions": .array([.string("https://example.com/*")]),
            "background": .object([
                "service_worker": .string("background.js"),
                "type": .string("module"),
            ]),
            "content_scripts": .array([
                .object([
                    "matches": .array([.string("https://example.com/*")]),
                    "js": .array([.string("content.js")]),
                ]),
            ]),
            "web_accessible_resources": .array([
                .object([
                    "resources": .array([.string("images/icon.png")]),
                    "matches": .array([.string("https://example.com/*")]),
                ]),
            ]),
            "content_security_policy": .object([
                "extension_pages": .string("script-src 'self'; object-src 'self'"),
            ]),
            "default_locale": .string("en"),
            "browser_specific_settings": .object([
                "gecko": .object(["id": .string("generic@example.test")]),
            ]),
            "generatedBundleRootPath": .string("/must/not/expose"),
            "manifestSHA256": .string("must-not-expose"),
            "diagnostics": .array([.string("must-not-expose")]),
            "_sumi_internal": .object([
                "profileRootPath": .string("/must/not/expose"),
            ]),
        ])
        let runtimeManifest = try XCTUnwrap(
            ChromeMV3PopupOptionsRuntimeManifestSnapshot
                .fromManifestPayload(manifest)
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                runtimeManifest: runtimeManifest,
                allowlist: .controlledActionPopupPolicy
            )
        )

        let response = handler.handle(request(
            namespace: "runtime",
            methodName: "getManifest"
        ))

        XCTAssertTrue(response.succeeded)
        XCTAssertFalse(response.nativeHostLaunchAttempted)
        XCTAssertFalse(response.serviceWorkerWakeAttempted)
        XCTAssertFalse(response.runtimeLoadable)
        let object = try XCTUnwrap(objectValue(response.resultPayload))
        XCTAssertEqual(numberValue(object["manifest_version"]), 3)
        XCTAssertEqual(stringValue(object["name"]), "__MSG_appName__")
        XCTAssertEqual(stringValue(object["version"]), "2026.1.0")
        XCTAssertEqual(
            stringValue(objectValue(object["action"])?["default_popup"]),
            "popup/index.html"
        )
        XCTAssertEqual(
            stringArrayValue(object["permissions"]),
            ["storage", "tabs"]
        )
        XCTAssertEqual(
            stringArrayValue(object["optional_permissions"]),
            ["nativeMessaging"]
        )
        XCTAssertEqual(
            stringArrayValue(object["host_permissions"]),
            ["https://example.com/*"]
        )
        XCTAssertNotNil(object["background"])
        XCTAssertNotNil(object["content_scripts"])
        XCTAssertNotNil(object["web_accessible_resources"])
        XCTAssertNotNil(object["content_security_policy"])
        XCTAssertEqual(stringValue(object["default_locale"]), "en")
        XCTAssertNotNil(object["browser_specific_settings"])
        XCTAssertNil(object["generatedBundleRootPath"])
        XCTAssertNil(object["manifestSHA256"])
        XCTAssertNil(object["diagnostics"])
        XCTAssertNil(object["_sumi_internal"])

        let snapshot = handler.diagnosticsSnapshot
        XCTAssertTrue(snapshot.observedMethods.contains("runtime.getManifest"))
        XCTAssertTrue(snapshot.sanitizedBridgeRouteRecords.contains {
            $0.apiName == "runtime.getManifest"
                && $0.targetContext == "manifest"
                && $0.resultClassifier == "manifestReturned"
                && $0.safeMessageShapeClassification.contains("keyCount=")
                && $0.diagnostics.contains("method=runtime.getManifest")
                && $0.diagnostics.contains("manifestVersion=3")
        })
        let encoded = String(
            data: try JSONEncoder().encode(snapshot),
            encoding: .utf8
        ) ?? ""
        XCTAssertTrue(encoded.contains("safeTopLevelManifestFields="))
        XCTAssertFalse(encoded.contains("/must/not/expose"))
        XCTAssertFalse(encoded.contains("must-not-expose"))
        XCTAssertFalse(encoded.contains("generatedBundleRootPath"))
        XCTAssertFalse(encoded.contains("manifestSHA256"))
        XCTAssertFalse(encoded.contains("profileRootPath"))
        XCTAssertFalse(encoded.contains("full manifest JSON"))
    }

    func testControlledRuntimeGetManifestSourceGuardsStayScopedAndGeneric()
        throws
    {
        let source = try String(
            contentsOf: URL(
                fileURLWithPath:
                    #filePath
            )
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3PopupOptionsJSBridge.swift"
            ),
            encoding: .utf8
        )
        let controlledPolicy =
            ChromeMV3PopupOptionsAPIMethodPolicy.controlledActionPopupPolicy

        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains("runtime.getManifest")
        )
        XCTAssertTrue(
            source.contains("Object.defineProperty(runtime, \"id\"")
        )
        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains("runtime.onMessage")
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                .allowedMethods
                .contains("runtime.onMessage")
        )
        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains("storage.session.get")
        )
        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains("storage.session.set")
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                .allowedMethods
                .contains("storage.session.get")
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                .exposedNamespaces
                .contains("storage.session")
        )
        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains("storage.sync.get")
        )
        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains(
                "storage.local.onChanged"
            )
        )
        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains(
                "storage.session.onChanged"
            )
        )
        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains(
                "storage.sync.onChanged"
            )
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                .allowedMethods
                .contains("storage.local.onChanged")
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                .allowedMethods
                .contains("storage.session.onChanged")
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                .allowedMethods
                .contains("storage.sync.onChanged")
        )
        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains("i18n.getMessage")
        )
        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains("i18n.getUILanguage")
        )
        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains("tabs.getCurrent")
        )
        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains(
                "extension.getBackgroundPage"
            )
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                .allowedMethods
                .contains("tabs.getCurrent")
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                .allowedMethods
                .contains("extension.getBackgroundPage")
        )
        XCTAssertTrue(
            controlledPolicy.exposedNamespaces.contains("i18n")
        )
        XCTAssertTrue(
            controlledPolicy.exposedNamespaces.contains("extension")
        )
        XCTAssertTrue(
            controlledPolicy.exposedNamespaces.contains("scripting")
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                .exposedNamespaces
                .contains("extension")
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                .allowedMethods
                .contains("i18n.getMessage")
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                .allowedMethods
                .contains("i18n.getUILanguage")
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                .exposedNamespaces
                .contains("i18n")
        )
        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains(
                "storage.sync.getBytesInUse"
            )
        )
        XCTAssertTrue(
            controlledPolicy.exposedNamespaces.contains("storage.sync")
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                .allowedMethods
                .contains("storage.sync.get")
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                .exposedNamespaces
                .contains("storage.sync")
        )
        XCTAssertFalse(
            controlledPolicy.allowedMethods.contains("contextMenus.create")
        )
        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains("scripting.executeScript")
        )
        XCTAssertTrue(
            controlledPolicy.exposedNamespaces.contains("permissions")
        )
        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains("permissions.contains")
        )
        XCTAssertTrue(
            controlledPolicy.allowedMethods.contains("permissions.getAll")
        )
        XCTAssertFalse(
            controlledPolicy.allowedMethods.contains("permissions.request")
        )
        XCTAssertFalse(
            controlledPolicy.blockedNamespaces.contains("permissions")
        )
        XCTAssertFalse(
            source.contains(
                "scripting.executeScript accepted package-local files[] only."
            )
        )
        XCTAssertFalse(
            source.contains(
                "scripting.executeScript returned one modeled result envelope per frame."
            )
        )
        let executorSource = try String(
            contentsOf: URL(
                fileURLWithPath:
                    #filePath
            )
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3ScriptingExecuteScriptExecutor.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            executorSource.contains(
                "Chrome-compatible executeScript must execute in an eligible target frame or reject; modeled no-op success is blocked."
            )
                || source.contains(
                    "Chrome-compatible executeScript must execute in an eligible target frame or reject; modeled no-op success is blocked."
                )
        )
        XCTAssertFalse(source.contains("executeScriptModeled"))
        XCTAssertFalse(
            controlledPolicy.allowedMethods.contains("runtime.getPlatformInfo")
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsAPIMethodPolicy.defaultPolicy
                .allowedMethods
                .contains("runtime.getPlatformInfo")
        )
        XCTAssertFalse(source.localizedCaseInsensitiveContains("bitwarden"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("1password"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("proton"))
        XCTAssertFalse(
            source.contains("com.bitwarden.desktop"),
            "getManifest must not launch or name any native host."
        )
        XCTAssertTrue(
            source.contains("runtime.getManifest source=generated-package-manifest-json.")
        )
        XCTAssertTrue(
            source.contains("runtimeManifestTemplate")
        )
        XCTAssertTrue(
            source.contains(
                "\"controlledRuntimeOnMessageCompatibilitySurface\""
            )
        )
        XCTAssertTrue(
            source.contains("Object.defineProperty(runtime, \"onMessage\"")
        )
        XCTAssertTrue(source.contains("makeEvent(\"runtime.onMessage\""))
        XCTAssertTrue(source.contains("debugRuntimeOnMessageEvent"))
        XCTAssertTrue(source.contains("targetContext=extensionPage"))
        XCTAssertTrue(source.contains("responseClassifier=registrationOnly"))
        XCTAssertTrue(source.contains("inboundRoute=notWired"))
        XCTAssertTrue(
            source.contains(
                "No raw message bodies, storage values, form values, URLs, or private payloads are recorded."
            )
        )
        XCTAssertTrue(
            source.contains("deepCloneJSONCompatible(runtimeManifestTemplate)")
        )
        XCTAssertTrue(
            source.contains("postBootstrapCheckpoint")
        )
        XCTAssertTrue(
            source.contains("executeScriptContinuationCheckpoint")
        )
        XCTAssertTrue(
            source.contains("popupRenderTimelineCheckpoint")
        )
        XCTAssertTrue(
            source.contains("debugTrackExecuteScriptPopupPromise")
        )
        XCTAssertTrue(
            source.contains("storageSessionExposed")
        )
        XCTAssertTrue(
            source.contains("storageSyncExposed")
        )
        XCTAssertTrue(
            source.contains("ChromeMV3PopupOptionsI18nCatalogSnapshot")
        )
        XCTAssertTrue(
            source.contains("i18nExposed")
        )
        XCTAssertTrue(
            source.contains("debugI18nCall")
        )
        XCTAssertTrue(
            source.contains("No raw localized message values are recorded.")
        )
        XCTAssertTrue(
            source.contains("controlledNavigatorCompatibilitySurface")
        )
        XCTAssertTrue(
            source.contains("installControlledNavigatorCompatibilitySurface")
        )
        XCTAssertTrue(
            source.contains("debugPlatformEnvironmentProbe")
        )
        XCTAssertTrue(
            source.contains("navigator.platformIdentity")
        )
        XCTAssertTrue(
            source.contains("Chrome/0.0.0.0")
        )
        XCTAssertTrue(
            source.contains("MacIntel")
        )
        XCTAssertTrue(
            source.contains("No raw user agent, language tags, storage data, message bodies, or form values are recorded.")
        )
        XCTAssertFalse(
            source.contains("Object.defineProperty(runtime, \"getPlatformInfo\"")
        )
        XCTAssertTrue(source.contains("\"tabs.getCurrent\""))
        XCTAssertTrue(
            source.contains("Object.defineProperty(tabs, \"getCurrent\"")
        )
        XCTAssertTrue(
            source.contains(
                "controlledTabsGetCurrentCompatibilitySurface"
            )
        )
        XCTAssertTrue(
            source.contains(
                "method=tabs.getCurrent namespace=chrome/browser result=undefined"
            )
        )
        XCTAssertTrue(source.contains("\"extension.getBackgroundPage\""))
        XCTAssertTrue(
            source.contains(
                "controlledExtensionGetBackgroundPageCompatibilitySurface"
            )
        )
        XCTAssertTrue(source.contains("controlledExtensionNamespace"))
        XCTAssertTrue(
            source.contains("Object.defineProperty(target, \"extension\"")
        )
        XCTAssertTrue(source.contains("debugExtensionNamespaceAccess"))
        XCTAssertTrue(source.contains("debugExtensionGetBackgroundPage"))
        XCTAssertTrue(
            source.contains(
                "method=extension.getBackgroundPage namespace="
            )
        )
        XCTAssertTrue(source.contains("result=\" + classifier"))
        XCTAssertTrue(
            source.contains(
                "No fake background page/window or service-worker internals were returned."
            )
        )
        XCTAssertTrue(
            source.contains("No broad legacy chrome.extension APIs are exposed.")
        )
        XCTAssertTrue(source.contains("syncBackend=localCompatibility"))
        XCTAssertTrue(
            source.contains("if (config.storageSessionExposed)")
        )
        XCTAssertTrue(
            source.contains("if (config.storageSyncExposed)")
        )
        XCTAssertTrue(
            source.contains("[\"local\", \"session\", \"sync\"]")
        )
        XCTAssertTrue(source.contains("storageAreaOnChanged"))
        XCTAssertTrue(source.contains("storageLocalOnChangedExposed"))
        XCTAssertTrue(source.contains("storageSessionOnChangedExposed"))
        XCTAssertTrue(source.contains("storageSyncOnChangedExposed"))
        XCTAssertTrue(
            source.contains("Object.defineProperty(local, \"onChanged\"")
        )
        XCTAssertTrue(
            source.contains("Object.defineProperty(session, \"onChanged\"")
        )
        XCTAssertTrue(
            source.contains("Object.defineProperty(sync, \"onChanged\"")
        )
        XCTAssertTrue(source.contains("debugStorageEvent"))
        XCTAssertTrue(source.contains("eventObjectPresent=true"))
        XCTAssertTrue(source.contains("listenerCount="))
        XCTAssertTrue(source.contains("changedKeyCount="))
        XCTAssertTrue(source.contains("debugStorageChangeValueShape"))
        XCTAssertTrue(
            source.contains("debugPostGetManifestBootstrapSentinel(true)")
        )
        XCTAssertTrue(
            source.contains("debugPostGetManifestBootstrapSentinel(false)")
        )
        XCTAssertTrue(
            source.contains("debugCoarseDOMState")
        )
        XCTAssertTrue(
            source.contains("ChromeMV3AppStateDependencyTraceSnapshot")
        )
        XCTAssertTrue(
            source.contains("appStateDependencyTraceSnapshot")
        )
        XCTAssertTrue(
            source.contains("appStateWaitWithNoWriter")
        )
        XCTAssertTrue(
            source.contains("appStateWaitWithMissingAPI")
        )
        XCTAssertTrue(
            source.contains("appStateWaitWithSuppressedEvent")
        )
        XCTAssertTrue(
            source.contains("appStateWaitWithNetworkOrAuthDependency")
        )
        XCTAssertTrue(
            source.contains("sumi-mv3-app-state-v1")
        )
        XCTAssertTrue(
            source.contains(":saltedHash=")
        )
        XCTAssertTrue(
            source.contains(
                "No raw storage keys or values are recorded by the app-state dependency tracer."
            )
        )
        XCTAssertTrue(
            source.contains(
                "No product/default exposure, extension-specific branches, fake storage, fake app state, fake runtime response, or native host launch is introduced by this tracer."
            )
        )
        XCTAssertTrue(
            source.contains("No raw storage values, message bodies, form values, manifest bodies, URLs, or private payloads were recorded.")
        )
        XCTAssertFalse(source.contains("storage.sync cloud"))
        XCTAssertFalse(source.contains("cross-device sync is performed."))
    }

    func testNavigatorCompatibilitySurfaceIsControlledActionPopupOnly()
        throws
    {
        let controlledActionPopupSource =
            ChromeMV3PopupOptionsJSShimSource.source(
                configuration: configuration(
                    allowlist: .controlledActionPopupPolicy
                )
            )
        let defaultActionPopupSource =
            ChromeMV3PopupOptionsJSShimSource.source(
                configuration: configuration()
            )
        let controlledOptionsPageSource =
            ChromeMV3PopupOptionsJSShimSource.source(
                configuration: configuration(
                    surface: .optionsPage,
                    allowlist: .controlledActionPopupPolicy
                )
            )

        XCTAssertTrue(
            controlledActionPopupSource.contains(
                "\"controlledNavigatorCompatibilitySurface\":true"
            )
        )
        XCTAssertTrue(
            defaultActionPopupSource.contains(
                "\"controlledNavigatorCompatibilitySurface\":false"
            )
        )
        XCTAssertTrue(
            controlledOptionsPageSource.contains(
                "\"controlledNavigatorCompatibilitySurface\":false"
            )
        )
        XCTAssertTrue(
            controlledActionPopupSource.contains(
                "installControlledNavigatorCompatibilitySurface();"
            )
        )
        let compatibilityFunctionStart = try XCTUnwrap(
            controlledActionPopupSource.range(
                of: "function installControlledNavigatorCompatibilitySurface()"
            )
        )
        let compatibilityFunctionPrefix =
            controlledActionPopupSource[compatibilityFunctionStart.lowerBound...]
                .prefix(220)
        XCTAssertTrue(
            compatibilityFunctionPrefix.contains(
                "if (!config.controlledNavigatorCompatibilitySurface)"
            )
        )
        XCTAssertTrue(compatibilityFunctionPrefix.contains("return;"))
        XCTAssertFalse(
            controlledActionPopupSource.contains(
                "Object.defineProperty(runtime, \"getPlatformInfo\""
            )
        )
        XCTAssertTrue(
            controlledActionPopupSource.contains(
                "Object.defineProperty(tabs, \"getCurrent\""
            )
        )
        XCTAssertTrue(
            controlledActionPopupSource.contains(
                "\"controlledExtensionGetBackgroundPageCompatibilitySurface\":true"
            )
        )
        XCTAssertTrue(
            controlledActionPopupSource.contains(
                "\"controlledRuntimeOnMessageCompatibilitySurface\":true"
            )
        )
        XCTAssertTrue(
            controlledActionPopupSource.contains(
                "Object.defineProperty(runtime, \"onMessage\""
            )
        )
        XCTAssertTrue(
            controlledActionPopupSource.contains(
                "Object.defineProperty(target, \"extension\""
            )
        )
        XCTAssertTrue(
            controlledActionPopupSource.contains(
                "Object.defineProperty(namespace, \"getBackgroundPage\""
            )
        )
        XCTAssertTrue(
            controlledActionPopupSource.contains("Chrome/0.0.0.0")
        )
        XCTAssertTrue(
            controlledActionPopupSource.contains("userAgentData=absent")
        )
        XCTAssertFalse(
            defaultActionPopupSource.contains(
                "Object.defineProperty(tabs, \"getCurrent\""
            )
        )
        XCTAssertTrue(
            defaultActionPopupSource.contains(
                "\"controlledExtensionGetBackgroundPageCompatibilitySurface\":false"
            )
        )
        XCTAssertTrue(
            defaultActionPopupSource.contains(
                "\"controlledRuntimeOnMessageCompatibilitySurface\":false"
            )
        )
        XCTAssertFalse(
            defaultActionPopupSource.contains(
                "Object.defineProperty(runtime, \"onMessage\""
            )
        )
        XCTAssertFalse(
            controlledOptionsPageSource.contains(
                "Object.defineProperty(tabs, \"getCurrent\""
            )
        )
        XCTAssertTrue(
            controlledOptionsPageSource.contains(
                "\"controlledExtensionGetBackgroundPageCompatibilitySurface\":false"
            )
        )
        XCTAssertTrue(
            controlledOptionsPageSource.contains(
                "\"controlledRuntimeOnMessageCompatibilitySurface\":true"
            )
        )
        XCTAssertTrue(
            controlledOptionsPageSource.contains(
                "Object.defineProperty(runtime, \"onMessage\""
            )
        )
    }

    func testI18nCatalogSnapshotRejectsSymlinkEscapedCatalogs()
        throws
    {
        let root = try makeTemporaryDirectory()
        let outside = try makeTemporaryDirectory()
        try """
        {
          "manifest_version": 3,
          "name": "__MSG_appName__",
          "version": "1.0.0",
          "default_locale": "en"
        }
        """.write(
            to: root.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        let localeRoot = root
            .appendingPathComponent("_locales", isDirectory: true)
            .appendingPathComponent("en", isDirectory: true)
        try FileManager.default.createDirectory(
            at: localeRoot,
            withIntermediateDirectories: true
        )
        let escapedCatalog = outside.appendingPathComponent("messages.json")
        try """
        {
          "appName": { "message": "Escaped localized value" }
        }
        """.write(to: escapedCatalog, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: localeRoot.appendingPathComponent("messages.json"),
            withDestinationURL: escapedCatalog
        )

        let runtimeManifest = try XCTUnwrap(
            ChromeMV3PopupOptionsRuntimeManifestSnapshot
                .fromGeneratedBundleRootPath(root.path)
        )
        let snapshot = try XCTUnwrap(
            ChromeMV3PopupOptionsI18nCatalogSnapshot
                .fromGeneratedBundleRootPath(
                    root.path,
                    runtimeManifest: runtimeManifest,
                    uiLanguageOverride: "en-US"
                )
        )

        XCTAssertEqual(snapshot.defaultLocaleDirectory, "en")
        XCTAssertEqual(snapshot.localeSearchOrder, ["en_US", "en"])
        XCTAssertTrue(snapshot.loadedCatalogLocales.isEmpty)
        XCTAssertTrue(snapshot.catalogs.isEmpty)
        let encoded = String(
            data: try JSONEncoder().encode(snapshot),
            encoding: .utf8
        ) ?? ""
        XCTAssertFalse(encoded.contains("Escaped localized value"))
        XCTAssertFalse(encoded.contains(outside.path))
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

    func testControlledStorageLocalPersistsByProfileAndExtensionWithoutRawDiagnostics()
        throws
    {
        let root = try makeTemporaryDirectory()
        let storageRoot = root.appendingPathComponent(
            "StorageLocal",
            isDirectory: true
        ).path
        let first = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: "generic-extension-a",
                profileID: "profile-a",
                allowlist: .controlledActionPopupPolicy,
                storageLocalRootPath: storageRoot
            )
        )
        let set = first.handle(request(
            namespace: "storage",
            methodName: "local.set",
            arguments: [
                .object([
                    "sensitiveStorageKey": .object([
                        "nestedSecret": .string("must-not-appear"),
                    ]),
                ]),
            ]
        ))

        XCTAssertTrue(set.succeeded)
        XCTAssertFalse(set.nativeHostLaunchAttempted)

        let second = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: "generic-extension-a",
                profileID: "profile-a",
                allowlist: .controlledActionPopupPolicy,
                storageLocalRootPath: storageRoot
            )
        )
        let get = second.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("sensitiveStorageKey")]
        ))
        let expectedPayload: ChromeMV3StorageValue = .object([
            "sensitiveStorageKey": .object([
                "nestedSecret": .string("must-not-appear"),
            ]),
        ])
        XCTAssertEqual(
            get.resultPayload,
            expectedPayload
        )
        XCTAssertFalse(get.nativeHostLaunchAttempted)

        let isolated = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: "generic-extension-b",
                profileID: "profile-a",
                allowlist: .controlledActionPopupPolicy,
                storageLocalRootPath: storageRoot
            )
        )
        let isolatedGet = isolated.handle(request(
            namespace: "storage",
            methodName: "local.get",
            arguments: [.string("sensitiveStorageKey")]
        ))
        let expectedMissingPayload: ChromeMV3StorageValue = .object([:])
        XCTAssertEqual(isolatedGet.resultPayload, expectedMissingPayload)

        let encoded = String(
            data: try JSONEncoder().encode(second.diagnosticsSnapshot),
            encoding: .utf8
        ) ?? ""
        XCTAssertTrue(encoded.contains("storageLocalBrokerSucceeded"))
        XCTAssertTrue(encoded.contains("keyShape=singleString"))
        XCTAssertTrue(encoded.contains("keyCount=1"))
        XCTAssertFalse(encoded.contains("sensitiveStorageKey"))
        XCTAssertFalse(encoded.contains("nestedSecret"))
        XCTAssertFalse(encoded.contains("must-not-appear"))
    }

    func testControlledStorageSyncUsesLocalCompatibilityBackendWithoutRawDiagnostics()
        throws
    {
        let root = try makeTemporaryDirectory()
        let storageRoot = root.appendingPathComponent(
            "StorageSyncLocalCompatibility",
            isDirectory: true
        ).path
        let first = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: "generic-extension-a",
                profileID: "profile-a",
                allowlist: .controlledActionPopupPolicy,
                storageSyncRootPath: storageRoot
            )
        )

        let set = first.handle(request(
            namespace: "storage",
            methodName: "sync.set",
            arguments: [
                .object([
                    "syncSensitiveKey": .object([
                        "nestedSecret": .string("must-not-appear"),
                    ]),
                ]),
            ]
        ))
        let get = first.handle(request(
            namespace: "storage",
            methodName: "sync.get",
            arguments: [.string("syncSensitiveKey")]
        ))
        let bytes = first.handle(request(
            namespace: "storage",
            methodName: "sync.getBytesInUse",
            arguments: [.string("syncSensitiveKey")]
        ))
        let remove = first.handle(request(
            namespace: "storage",
            methodName: "sync.remove",
            arguments: [.string("syncSensitiveKey")]
        ))
        let clear = first.handle(request(
            namespace: "storage",
            methodName: "sync.clear"
        ))

        XCTAssertTrue(set.succeeded)
        XCTAssertEqual(set.onChangedPayload?.areaName, "sync")
        XCTAssertEqual(
            set.onChangedPayload?.serviceWorkerWakeRequired,
            false
        )
        XCTAssertFalse(set.nativeHostLaunchAttempted)
        XCTAssertEqual(
            get.resultPayload,
            .object([
                "syncSensitiveKey": .object([
                    "nestedSecret": .string("must-not-appear"),
                ]),
            ])
        )
        XCTAssertTrue(bytes.succeeded)
        XCTAssertTrue(numberValue(bytes.resultPayload) ?? 0 > 0)
        XCTAssertTrue(remove.succeeded)
        XCTAssertTrue(clear.succeeded)
        XCTAssertEqual(
            first.diagnosticsSnapshot.storageOnChangedPayloadCount,
            2
        )
        XCTAssertTrue(first.diagnosticsSnapshot.observedMethods.contains(
            "storage.sync.set"
        ))

        let second = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: "generic-extension-a",
                profileID: "profile-a",
                allowlist: .controlledActionPopupPolicy,
                storageSyncRootPath: storageRoot
            )
        )
        let persisted = second.handle(request(
            namespace: "storage",
            methodName: "sync.get",
            arguments: [.string("syncSensitiveKey")]
        ))
        XCTAssertEqual(persisted.resultPayload, .object([:]))

        let third = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: "generic-extension-a",
                profileID: "profile-a",
                allowlist: .controlledActionPopupPolicy,
                storageSyncRootPath: storageRoot
            )
        )
        _ = third.handle(request(
            namespace: "storage",
            methodName: "sync.set",
            arguments: [.object(["syncSensitiveKey": .string("persisted")])]
        ))
        let reloaded = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: "generic-extension-a",
                profileID: "profile-a",
                allowlist: .controlledActionPopupPolicy,
                storageSyncRootPath: storageRoot
            )
        )
        let reloadedGet = reloaded.handle(request(
            namespace: "storage",
            methodName: "sync.get",
            arguments: [.string("syncSensitiveKey")]
        ))
        XCTAssertEqual(
            reloadedGet.resultPayload,
            .object(["syncSensitiveKey": .string("persisted")])
        )

        let isolated = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: "generic-extension-b",
                profileID: "profile-a",
                allowlist: .controlledActionPopupPolicy,
                storageSyncRootPath: storageRoot
            )
        )
        let isolatedGet = isolated.handle(request(
            namespace: "storage",
            methodName: "sync.get",
            arguments: [.string("syncSensitiveKey")]
        ))
        XCTAssertEqual(isolatedGet.resultPayload, .object([:]))

        let defaultPolicyResponse = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                allowlist: .defaultPolicy,
                storageSyncRootPath: storageRoot
            )
        ).handle(request(
            namespace: "storage",
            methodName: "sync.get",
            arguments: [.string("syncSensitiveKey")]
        ))
        XCTAssertFalse(defaultPolicyResponse.succeeded)

        let encoded = String(
            data: try JSONEncoder().encode(first.diagnosticsSnapshot),
            encoding: .utf8
        ) ?? ""
        XCTAssertTrue(encoded.contains("storageSyncLocalCompatibilitySucceeded"))
        XCTAssertTrue(encoded.contains("backend=localCompatibility"))
        XCTAssertTrue(encoded.contains("keyShape=singleString"))
        XCTAssertTrue(encoded.contains("keyCount=1"))
        XCTAssertFalse(encoded.contains("syncSensitiveKey"))
        XCTAssertFalse(encoded.contains("nestedSecret"))
        XCTAssertFalse(encoded.contains("must-not-appear"))
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

    func testControlledActionPopupTabsGetCurrentReturnsUndefined() throws {
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                allowlist: .controlledActionPopupPolicy
            )
        )

        let promise = handler.handle(request(
            namespace: "tabs",
            methodName: "getCurrent",
            invocationMode: .promise
        ))
        let callback = handler.handle(request(
            namespace: "tabs",
            methodName: "getCurrent",
            invocationMode: .callback
        ))
        let defaultPolicy = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration()
        ).handle(request(
            namespace: "tabs",
            methodName: "getCurrent"
        ))

        XCTAssertTrue(promise.succeeded)
        XCTAssertNil(promise.resultPayload)
        XCTAssertFalse(promise.promiseWouldReject)
        XCTAssertFalse(promise.callbackWouldSetLastError)
        XCTAssertTrue(callback.succeeded)
        XCTAssertNil(callback.resultPayload)
        XCTAssertFalse(callback.callbackWouldSetLastError)
        XCTAssertFalse(defaultPolicy.succeeded)
        XCTAssertEqual(defaultPolicy.lastErrorCode, "productBlocked")

        let records = handler.diagnosticsSnapshot.callRecords.filter {
            $0.namespace == "tabs" && $0.methodName == "getCurrent"
        }
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy(\.succeeded))
        XCTAssertTrue(records.allSatisfy {
            $0.nativeHostLaunchAttempted == false
                && $0.serviceWorkerWakeAttempted == false
        })
        XCTAssertTrue(records.allSatisfy {
            $0.diagnostics.contains {
                $0.contains("method=tabs.getCurrent")
                    && $0.contains("namespace=chrome/browser")
                    && $0.contains("result=undefined")
                    && $0.contains("redaction=notApplicable")
            }
        })
        let encoded = String(
            data: try JSONEncoder().encode(records),
            encoding: .utf8
        ) ?? ""
        XCTAssertFalse(encoded.contains("https://example.com/login"))
        XCTAssertFalse(encoded.contains("Example Login"))
        XCTAssertFalse(encoded.contains("favIconUrl"))
        XCTAssertFalse(encoded.contains("pendingUrl"))
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
    func testControlledI18nUsesGeneratedCatalogFallbackAndPlaceholders()
        async throws
    {
        let root = try makeTemporaryDirectory()
        let htmlURL = root.appendingPathComponent("popup.html")
        try """
        <!doctype html>
        <meta charset="utf-8">
        <title>I18n Popup</title>
        <main data-sumi-extension-page-fixture-marker="safe">Popup</main>
        """.write(to: htmlURL, atomically: true, encoding: .utf8)
        try """
        {
          "manifest_version": 3,
          "name": "__MSG_appName__",
          "version": "1.0.0",
          "default_locale": "en",
          "action": { "default_popup": "popup.html" }
        }
        """.write(
            to: root.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        let frLocale = root
            .appendingPathComponent("_locales", isDirectory: true)
            .appendingPathComponent("fr", isDirectory: true)
        let enLocale = root
            .appendingPathComponent("_locales", isDirectory: true)
            .appendingPathComponent("en", isDirectory: true)
        try FileManager.default.createDirectory(
            at: frLocale,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: enLocale,
            withIntermediateDirectories: true
        )
        try """
        {
          "helloName": {
            "message": "Bonjour $user$",
            "placeholders": {
              "user": { "content": "$1" }
            }
          }
        }
        """.write(
            to: frLocale.appendingPathComponent("messages.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "fallbackOnly": { "message": "Default only" },
          "htmlValue": { "message": "<tag $1" },
          "positional": { "message": "One $1 two $2" }
        }
        """.write(
            to: enLocale.appendingPathComponent("messages.json"),
            atomically: true,
            encoding: .utf8
        )
        let runtimeManifest = try XCTUnwrap(
            ChromeMV3PopupOptionsRuntimeManifestSnapshot
                .fromGeneratedBundleRootPath(root.path)
        )
        let i18nSnapshot = try XCTUnwrap(
            ChromeMV3PopupOptionsI18nCatalogSnapshot
                .fromGeneratedBundleRootPath(
                    root.path,
                    runtimeManifest: runtimeManifest,
                    uiLanguageOverride: "fr-CA"
                )
        )
        let config = configuration(
            runtimeManifest: runtimeManifest,
            i18nCatalogSnapshot: i18nSnapshot,
            allowlist: .controlledActionPopupPolicy
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
            const uiLanguage = chrome.i18n.getUILanguage();
            const hello = chrome.i18n.getMessage("helloName", "ZXQSUB742");
            const fallback = chrome.i18n.getMessage("fallbackOnly");
            const positional = chrome.i18n.getMessage("positional", ["uno", "dos"]);
            const escaped = chrome.i18n.getMessage(
              "htmlValue",
              ["raw"],
              { escapeLt: true }
            );
            const missing = chrome.i18n.getMessage("missingKey");
            const predefinedLocale = chrome.i18n.getMessage("@@ui_locale");
            const tooManyType = typeof chrome.i18n.getMessage(
              "helloName",
              ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
            );
            await new Promise((resolve) => setTimeout(resolve, 60));
            return {
              hasI18n: !!chrome.i18n,
              uiLanguage,
              hello,
              fallback,
              positional,
              escaped,
              missing,
              predefinedLocale,
              tooManyType,
              isGetMessagePromise:
                !!hello && typeof hello.then === "function"
            };
            """
        )
        let object = try XCTUnwrap(raw as? [String: Any])

        XCTAssertEqual(object["hasI18n"] as? Bool, true)
        XCTAssertEqual(object["uiLanguage"] as? String, "fr-CA")
        XCTAssertEqual(object["hello"] as? String, "Bonjour ZXQSUB742")
        XCTAssertEqual(object["fallback"] as? String, "Default only")
        XCTAssertEqual(object["positional"] as? String, "One uno two dos")
        XCTAssertEqual(object["escaped"] as? String, "&lt;tag raw")
        XCTAssertEqual(object["missing"] as? String, "")
        XCTAssertEqual(object["predefinedLocale"] as? String, "fr_CA")
        XCTAssertEqual(object["tooManyType"] as? String, "undefined")
        XCTAssertEqual(object["isGetMessagePromise"] as? Bool, false)

        let snapshot = try XCTUnwrap(
            handle.popupOptionsBridgeDiagnosticsSnapshot
        )
        XCTAssertTrue(snapshot.jsDebugRouteEvents.contains {
            $0.apiName == "chrome.i18n.getUILanguage"
                && $0.targetContext == "i18n"
                && $0.resultClassifier == "uiLanguageReturned"
        })
        XCTAssertTrue(snapshot.jsDebugRouteEvents.contains {
            $0.apiName == "chrome.i18n.getMessage"
                && $0.targetContext == "i18n"
                && $0.resultClassifier == "localizedMessageReturned"
                && $0.diagnostics.contains("fallbackLocaleUsed=true")
        })
        XCTAssertTrue(snapshot.jsDebugRouteEvents.contains {
            $0.apiName == "chrome.i18n.getMessage"
                && $0.targetContext == "i18n"
                && $0.resultClassifier == "messageMissing"
        })
        let encodedSnapshot = String(
            data: try JSONEncoder().encode(snapshot),
            encoding: .utf8
        ) ?? ""
        XCTAssertFalse(encodedSnapshot.contains("Bonjour"))
        XCTAssertFalse(encodedSnapshot.contains("Default only"))
        XCTAssertFalse(encodedSnapshot.contains("ZXQSUB742"))
        XCTAssertFalse(encodedSnapshot.contains("<tag"))
    }

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
            manifestOptionalHostPermissions: manifest.optionalHostPermissions,
            runtimeManifest:
                ChromeMV3PopupOptionsRuntimeManifestSnapshot
                .fromGeneratedBundleRootPath(
                    generated.generatedBundleRootURL.path
                ),
            allowlist: .controlledActionPopupPolicy
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
            const chromeCurrent = await chrome.tabs.getCurrent();
            const browserCurrent = await browser.tabs.getCurrent();
            const chromeBackgroundPage = chrome.extension.getBackgroundPage();
            const browserBackgroundPage = browser.extension.getBackgroundPage();
            let getCurrentCallbackIsUndefined = false;
            let getCurrentCallbackLastError = "unset";
            await new Promise((resolve) => {
              chrome.tabs.getCurrent(function(tab) {
                getCurrentCallbackIsUndefined = tab === undefined;
                getCurrentCallbackLastError = chrome.runtime.lastError
                  ? chrome.runtime.lastError.message
                  : null;
                resolve();
              });
            });
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
              hasChromeRuntimeGetManifest:
                !!globalThis.chrome
                && !!chrome.runtime
                && typeof chrome.runtime.getManifest === "function",
              manifestVersion:
                chrome.runtime.getManifest().manifest_version,
              manifestPopup:
                chrome.runtime.getManifest().action
                && chrome.runtime.getManifest().action.default_popup,
            hasBrowserRuntime:
                !!globalThis.browser
                && !!browser.runtime
                && typeof browser.runtime.connect === "function",
            hasChromeTabs:
                !!globalThis.chrome
                && !!chrome.tabs
                && typeof chrome.tabs.query === "function",
              navigatorUAHasChromeToken:
                navigator.userAgent.indexOf(" Chrome/") !== -1,
              navigatorUAHasSafariToken:
                navigator.userAgent.indexOf(" Safari/") !== -1,
              navigatorPlatformShape:
                /^Mac/i.test(navigator.platform || "") ? "mac" : "other",
              hasUserAgentData:
                !!navigator.userAgentData,
              userAgentDataBrandsCount:
                navigator.userAgentData
                && Array.isArray(navigator.userAgentData.brands)
                  ? navigator.userAgentData.brands.length
                  : 0,
              hasChromeRuntimeGetPlatformInfo:
                !!globalThis.chrome
                && !!chrome.runtime
                && typeof chrome.runtime.getPlatformInfo === "function",
              hasBrowserRuntimeGetPlatformInfo:
                !!globalThis.browser
                && !!browser.runtime
                && typeof browser.runtime.getPlatformInfo === "function",
              hasChromeRuntimeGetBrowserInfo:
                !!globalThis.chrome
                && !!chrome.runtime
                && typeof chrome.runtime.getBrowserInfo === "function",
              hasChromeTabsGetCurrent:
                !!globalThis.chrome
                && !!chrome.tabs
                && typeof chrome.tabs.getCurrent === "function",
              hasBrowserTabsGetCurrent:
                !!globalThis.browser
                && !!browser.tabs
                && typeof browser.tabs.getCurrent === "function",
              hasChromeExtension:
                !!globalThis.chrome
                && !!chrome.extension,
              hasBrowserExtension:
                !!globalThis.browser
                && !!browser.extension,
              hasChromeExtensionGetBackgroundPage:
                !!globalThis.chrome
                && !!chrome.extension
                && typeof chrome.extension.getBackgroundPage === "function",
              hasBrowserExtensionGetBackgroundPage:
                !!globalThis.browser
                && !!browser.extension
                && typeof browser.extension.getBackgroundPage === "function",
              chromeExtensionKeys:
                Object.keys(chrome.extension).sort(),
              browserExtensionKeys:
                Object.keys(browser.extension).sort(),
              chromeCurrentIsUndefined: chromeCurrent === undefined,
              browserCurrentIsUndefined: browserCurrent === undefined,
              chromeBackgroundPageIsNull: chromeBackgroundPage === null,
              browserBackgroundPageIsNull: browserBackgroundPage === null,
              getCurrentCallbackIsUndefined,
              getCurrentCallbackLastError,
              getCurrentLastErrorAfterCallback:
                chrome.runtime.lastError || null
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
        XCTAssertEqual(object["hasChromeRuntimeGetManifest"] as? Bool, true)
        XCTAssertEqual(object["manifestVersion"] as? Int, 3)
        XCTAssertEqual(object["manifestPopup"] as? String, "popup/index.html")
        XCTAssertEqual(object["hasBrowserRuntime"] as? Bool, true)
        XCTAssertEqual(object["hasChromeTabs"] as? Bool, true)
        XCTAssertEqual(object["navigatorUAHasChromeToken"] as? Bool, true)
        XCTAssertEqual(object["navigatorUAHasSafariToken"] as? Bool, true)
        XCTAssertEqual(object["navigatorPlatformShape"] as? String, "mac")
        XCTAssertEqual(
            object["hasChromeRuntimeGetPlatformInfo"] as? Bool,
            false
        )
        XCTAssertEqual(
            object["hasBrowserRuntimeGetPlatformInfo"] as? Bool,
            false
        )
        XCTAssertEqual(
            object["hasChromeRuntimeGetBrowserInfo"] as? Bool,
            false
        )
        XCTAssertEqual(object["hasChromeTabsGetCurrent"] as? Bool, true)
        XCTAssertEqual(object["hasBrowserTabsGetCurrent"] as? Bool, true)
        XCTAssertEqual(object["hasChromeExtension"] as? Bool, true)
        XCTAssertEqual(object["hasBrowserExtension"] as? Bool, true)
        XCTAssertEqual(
            object["hasChromeExtensionGetBackgroundPage"] as? Bool,
            true
        )
        XCTAssertEqual(
            object["hasBrowserExtensionGetBackgroundPage"] as? Bool,
            true
        )
        XCTAssertEqual(
            object["chromeExtensionKeys"] as? [String],
            ["getBackgroundPage"]
        )
        XCTAssertEqual(
            object["browserExtensionKeys"] as? [String],
            ["getBackgroundPage"]
        )
        XCTAssertEqual(object["chromeCurrentIsUndefined"] as? Bool, true)
        XCTAssertEqual(object["browserCurrentIsUndefined"] as? Bool, true)
        XCTAssertEqual(object["chromeBackgroundPageIsNull"] as? Bool, true)
        XCTAssertEqual(object["browserBackgroundPageIsNull"] as? Bool, true)
        XCTAssertEqual(object["getCurrentCallbackIsUndefined"] as? Bool, true)
        XCTAssertTrue(object["getCurrentCallbackLastError"] is NSNull)
        XCTAssertTrue(object["getCurrentLastErrorAfterCallback"] is NSNull)
        try await Task.sleep(nanoseconds: 3_800_000_000)
        XCTAssertEqual(handle.installedUserScriptCount, 1)
        XCTAssertEqual(handle.installedScriptMessageHandlerCount, 1)
        let snapshot = try XCTUnwrap(
            handle.popupOptionsBridgeDiagnosticsSnapshot
        )
        XCTAssertTrue(snapshot.callRecords.allSatisfy {
            $0.nativeHostLaunchAttempted == false
        })
        XCTAssertTrue(snapshot.observedMethods.contains("runtime.getManifest"))
        XCTAssertTrue(snapshot.observedMethods.contains("tabs.getCurrent"))
        XCTAssertFalse(
            snapshot.observedMethods.contains("extension.getBackgroundPage"),
            "extension.getBackgroundPage is synchronous JS-only and must not route through the Swift host."
        )
        XCTAssertTrue(snapshot.callRecords.contains {
            $0.namespace == "tabs"
                && $0.methodName == "getCurrent"
                && $0.succeeded
                && $0.diagnostics.contains {
                    $0.contains("method=tabs.getCurrent")
                        && $0.contains("result=undefined")
                        && $0.contains("redaction=notApplicable")
                }
        })
        let postBootstrapCheckpoints = snapshot.jsDebugRouteEvents.filter {
            $0.apiName == "postBootstrap.sentinel"
        }
        let finalPostBootstrapCheckpoint = postBootstrapCheckpoints.last
        XCTAssertFalse(
            finalPostBootstrapCheckpoint?
                .firstMissingAPIOrPermissionOrLifecycleError?
                .contains("tabs.getCurrent") == true
        )
        XCTAssertTrue(snapshot.jsDebugRouteEvents.contains {
            $0.eventKind == "extensionNamespaceAccessed"
                && $0.apiName == "chrome.extension"
                && $0.resultClassifier == "namespace returned"
        })
        XCTAssertTrue(snapshot.jsDebugRouteEvents.contains {
            $0.eventKind == "extensionNamespaceAccessed"
                && $0.apiName == "browser.extension"
                && $0.resultClassifier == "namespace returned"
        })
        XCTAssertTrue(snapshot.jsDebugRouteEvents.contains {
            $0.eventKind == "extensionMethodCalled"
                && $0.apiName == "chrome.extension.getBackgroundPage"
                && $0.resultClassifier == "null"
                && $0.diagnostics.contains {
                    $0.contains(
                        "No fake background page/window or service-worker internals were returned."
                    )
                }
        })
        XCTAssertTrue(snapshot.jsDebugRouteEvents.contains {
            $0.eventKind == "extensionMethodCalled"
                && $0.apiName == "browser.extension.getBackgroundPage"
                && $0.resultClassifier == "null"
        })
        let platformProbeEvents = snapshot.jsDebugRouteEvents.filter {
            $0.apiName == "navigator.platformIdentity"
        }
        XCTAssertTrue(platformProbeEvents.contains {
            $0.targetContext == "platform"
                && $0.diagnostics.contains("phase=preNavigatorCompatibility")
                && $0.diagnostics.contains("uaHasAppleWebKit=true")
                && $0.diagnostics.contains("uaHasChromeSignal=false")
                && $0.diagnostics.contains("uaHasSafariSignal=false")
                && $0.diagnostics.contains("platformShape=mac")
                && $0.diagnostics.contains("userAgentData=absent")
                && $0.diagnostics.contains("chromeRuntimeGetPlatformInfo=false")
                && $0.diagnostics.contains("browserRuntimePresent=true")
        })
        XCTAssertTrue(platformProbeEvents.contains {
            $0.targetContext == "platform"
                && $0.diagnostics.contains("phase=postNavigatorCompatibility")
                && $0.diagnostics.contains("knownBrowserFamilyAfter=true")
                && $0.diagnostics.contains("uaHasChromeSignal=true")
                && $0.diagnostics.contains("uaHasSafariSignal=true")
                && $0.diagnostics.contains("userAgentOverrideApplied=true")
                && $0.diagnostics.contains(
                    "userAgentOverrideKind=reducedChromeMac"
                )
        })
        let encodedSnapshot = String(
            data: try JSONEncoder().encode(snapshot),
            encoding: .utf8
        ) ?? ""
        XCTAssertFalse(encodedSnapshot.contains("this.device.toString"))
        XCTAssertFalse(encodedSnapshot.contains("null is not an object"))
        XCTAssertFalse(encodedSnapshot.contains("getManifest is not a function"))
        XCTAssertFalse(encodedSnapshot.contains(generated.generatedBundleRootURL.path))
        XCTAssertFalse(encodedSnapshot.contains(packageRoot.path))
        #if canImport(AppKit)
        XCTAssertEqual(
            bitwardenNativeHostRunningApplicationIdentifiers(),
            nativeHostWasRunning,
            "The controlled popup-host POC must not launch com.bitwarden.desktop."
        )
        #endif
    }

    @MainActor
    func testControlledRuntimeIDSurvivesWebExtensionPolyfillGuard()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("WKWebView extension-page bridge requires macOS 15.5.")
        }
        let extensionID = "popup-options-runtime-id"
        let root = try makeTemporaryDirectory()
        let htmlURL = root.appendingPathComponent("popup.html")
        try """
        <!doctype html>
        <meta charset="utf-8">
        <title>Runtime ID</title>
        """.write(to: htmlURL, atomically: true, encoding: .utf8)
        let config = configuration(
            extensionID: extensionID,
            allowlist: .controlledActionPopupPolicy
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
        let runtimeID = try await handle.callAsyncJavaScriptForTesting(
            """
            if (
              !(
                globalThis.chrome
                && globalThis.chrome.runtime
                && globalThis.chrome.runtime.id
              )
            ) {
              throw new Error(
                "This script should only be loaded in a browser extension."
              );
            }
            return chrome.runtime.id;
            """
        ) as? String
        XCTAssertEqual(runtimeID, extensionID)
    }

    @MainActor
    func testControlledRootNamespacesRemainExtensibleForPolyfillMetadata()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("WKWebView extension-page bridge requires macOS 15.5.")
        }
        let handle = try await makeControlledRuntimeIDBridgeHandle(
            extensionID: "popup-options-namespace-extensibility"
        )
        defer { handle.tearDown() }
        let probe = try await handle.callAsyncJavaScriptForTesting(
            """
            const chromeExtensible = Object.isExtensible(globalThis.chrome);
            const browserExtensible = Object.isExtensible(globalThis.browser);
            let browserESModuleWritable = false;
            let chromeAppWritable = false;
            let runtimeSendMessageWritable = false;
            try {
              Object.defineProperty(globalThis.browser, "__esModule", {
                value: true,
                configurable: true,
                enumerable: false,
                writable: true
              });
              browserESModuleWritable = true;
              delete globalThis.browser.__esModule;
            } catch (_) {}
            try {
              Object.defineProperty(globalThis.chrome, "app", {
                value: {},
                configurable: true,
                enumerable: true,
                writable: true
              });
              chromeAppWritable = true;
              delete globalThis.chrome.app;
            } catch (_) {}
            const runtimeDescriptor = Object.getOwnPropertyDescriptor(
              globalThis.chrome.runtime,
              "sendMessage"
            );
            runtimeSendMessageWritable = runtimeDescriptor?.writable === true;
            return {
              chromeExtensible,
              browserExtensible,
              browserESModuleWritable,
              chromeAppWritable,
              runtimeSendMessageWritable
            };
            """
        ) as? [String: Bool]
        XCTAssertEqual(probe?["chromeExtensible"], true)
        XCTAssertEqual(probe?["browserExtensible"], true)
        XCTAssertEqual(probe?["browserESModuleWritable"], true)
        XCTAssertEqual(probe?["chromeAppWritable"], true)
        XCTAssertEqual(probe?["runtimeSendMessageWritable"], false)
    }

    @MainActor
    func testControlledBrowserExportsSurviveWebpackESModuleMarker()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("WKWebView extension-page bridge requires macOS 15.5.")
        }
        let handle = try await makeControlledRuntimeIDBridgeHandle(
            extensionID: "popup-options-webpack-esmodule"
        )
        defer { handle.tearDown() }
        let survived = try await handle.callAsyncJavaScriptForTesting(
            """
            if (
              !(
                globalThis.chrome
                && globalThis.chrome.runtime
                && globalThis.chrome.runtime.id
              )
            ) {
              throw new Error(
                "This script should only be loaded in a browser extension."
              );
            }
            const moduleExports =
              globalThis.browser
              && globalThis.browser.runtime
              && globalThis.browser.runtime.id
                ? globalThis.browser
                : globalThis.chrome;
            Object.defineProperty(moduleExports, "__esModule", {
              value: true,
              configurable: true,
              enumerable: false,
              writable: true
            });
            delete moduleExports.__esModule;
            return moduleExports === globalThis.browser;
            """
        ) as? Bool
        XCTAssertEqual(survived, true)
    }

    @MainActor
    func testControlledChromeAppFeatureDetectionDoesNotThrow()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("WKWebView extension-page bridge requires macOS 15.5.")
        }
        let handle = try await makeControlledRuntimeIDBridgeHandle(
            extensionID: "popup-options-chrome-app-probe"
        )
        defer { handle.tearDown() }
        let observed = try await handle.callAsyncJavaScriptForTesting(
            """
            const hasOwnApp = Object.prototype.hasOwnProperty.call(
              globalThis.chrome || {},
              "app"
            );
            const appValue = globalThis.chrome && globalThis.chrome.app;
            return {
              hasOwnApp,
              appType: appValue === undefined ? "undefined" : typeof appValue
            };
            """
        ) as? [String: AnyHashable]
        XCTAssertEqual(observed?["hasOwnApp"], false)
        XCTAssertEqual(observed?["appType"], "undefined")
    }

    func testControlledPermissionsContainsCompatibility() throws {
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                manifestPermissions: ["storage", "tabs"],
                manifestOptionalPermissions: ["history"],
                manifestHostPermissions: ["https://example.com/*"],
                manifestOptionalHostPermissions: ["https://optional.example/*"],
                allowlist: .controlledActionPopupPolicy
            )
        )
        let grantedPermission = handler.handle(request(
            namespace: "permissions",
            methodName: "contains",
            arguments: [.object(["permissions": .array([.string("storage")])])],
            invocationMode: .promise
        ))
        let grantedOrigin = handler.handle(request(
            namespace: "permissions",
            methodName: "contains",
            arguments: [
                .object(["origins": .array([.string("https://example.com/*")])]),
            ],
            invocationMode: .promise
        ))
        let ungrantedPermission = handler.handle(request(
            namespace: "permissions",
            methodName: "contains",
            arguments: [.object(["permissions": .array([.string("history")])])],
            invocationMode: .promise
        ))
        let ungrantedOrigin = handler.handle(request(
            namespace: "permissions",
            methodName: "contains",
            arguments: [
                .object([
                    "origins": .array([.string("https://optional.example/*")]),
                ]),
            ],
            invocationMode: .promise
        ))
        let callback = handler.handle(request(
            namespace: "permissions",
            methodName: "contains",
            arguments: [.object(["permissions": .array([.string("tabs")])])],
            invocationMode: .callback
        ))
        let invalid = handler.handle(request(
            namespace: "permissions",
            methodName: "contains",
            arguments: [.object(["permissions": .string("storage")])],
            invocationMode: .promise
        ))
        let blockedRequest = handler.handle(request(
            namespace: "permissions",
            methodName: "request",
            arguments: [.object(["permissions": .array([.string("history")])])]
        ))
        let disabledModule = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                moduleState: .disabled,
                manifestPermissions: ["storage"],
                allowlist: .controlledActionPopupPolicy
            )
        ).handle(request(
            namespace: "permissions",
            methodName: "contains",
            arguments: [.object(["permissions": .array([.string("storage")])])]
        ))

        XCTAssertTrue(grantedPermission.succeeded)
        XCTAssertEqual(boolValue(grantedPermission.resultPayload), true)
        XCTAssertNil(grantedPermission.lastErrorCode)
        XCTAssertFalse(grantedPermission.promiseWouldReject)
        XCTAssertTrue(grantedOrigin.succeeded)
        XCTAssertEqual(boolValue(grantedOrigin.resultPayload), true)
        XCTAssertTrue(ungrantedPermission.succeeded)
        XCTAssertEqual(boolValue(ungrantedPermission.resultPayload), false)
        XCTAssertTrue(ungrantedOrigin.succeeded)
        XCTAssertEqual(boolValue(ungrantedOrigin.resultPayload), false)
        XCTAssertTrue(callback.succeeded)
        XCTAssertEqual(boolValue(callback.resultPayload), true)
        XCTAssertTrue(callback.callbackWouldSetLastError == false)
        XCTAssertFalse(invalid.succeeded)
        XCTAssertEqual(invalid.lastErrorCode, "invalidArguments")
        XCTAssertTrue(invalid.promiseWouldReject)
        XCTAssertFalse(blockedRequest.succeeded)
        XCTAssertEqual(blockedRequest.lastErrorCode, "productBlocked")
        XCTAssertFalse(disabledModule.succeeded)
        XCTAssertEqual(disabledModule.lastErrorCode, "extensionDisabled")

        let controlledSource = ChromeMV3PopupOptionsJSShimSource.source(
            configuration: configuration(
                allowlist: .controlledActionPopupPolicy
            )
        )
        let defaultSource = ChromeMV3PopupOptionsJSShimSource.source(
            configuration: configuration()
        )
        XCTAssertTrue(
            controlledSource.contains("\"permissionsContainsExposed\":true")
        )
        XCTAssertTrue(
            controlledSource.contains("\"permissionsGetAllExposed\":true")
        )
        XCTAssertFalse(
            controlledSource.contains("\"permissionsFullExposed\":true")
        )
        XCTAssertTrue(
            controlledSource.contains(
                "Object.defineProperty(permissions, \"contains\""
            )
        )
        XCTAssertTrue(
            controlledSource.contains(
                "Object.defineProperty(permissions, \"getAll\""
            )
        )
        XCTAssertFalse(
            controlledSource.contains(
                "Object.defineProperty(permissions, \"request\""
            )
        )
        XCTAssertTrue(defaultSource.contains("\"permissionsFullExposed\":true"))

        let privateContextDecision =
            ChromeMV3LocalMV3CompatibilityPolicy.evaluateActionPopup(
                ChromeMV3CompatibilityPolicyInput(
                    moduleEnabled: true,
                    developerPreviewLocalMV3FlowAvailable: true,
                    extensionID: "permissions-private-context",
                    profileID: "permissions-private-profile",
                    manifestVersion: 3,
                    sourceKind: .directory,
                    extensionEnabled: true,
                    profileAllowed: true,
                    normalNonPrivateContext: false,
                    actionDefaultPopupPresent: true,
                    forceNativeActionPopup: false,
                    forceControlledCompatibilityActionPopupOff: false
                )
            )
        XCTAssertTrue(
            privateContextDecision.blockers.contains(.privateContext)
        )
    }

    func testControlledPermissionsGetAllCompatibility() throws {
        let config = configuration(
            manifestPermissions: ["storage", "tabs"],
            manifestOptionalPermissions: ["history", "bookmarks"],
            manifestHostPermissions: ["https://example.com/*"],
            manifestOptionalHostPermissions: ["https://optional.example/*"],
            allowlist: .controlledActionPopupPolicy
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: config
        )
        let promise = handler.handle(request(
            namespace: "permissions",
            methodName: "getAll",
            invocationMode: .promise
        ))
        let callback = handler.handle(request(
            namespace: "permissions",
            methodName: "getAll",
            invocationMode: .callback
        ))
        let invalidArgs = handler.handle(request(
            namespace: "permissions",
            methodName: "getAll",
            arguments: [.object([:])],
            invocationMode: .promise
        ))
        let blockedRequest = handler.handle(request(
            namespace: "permissions",
            methodName: "request",
            arguments: [.object(["permissions": .array([.string("history")])])]
        ))
        let disabledModule = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                moduleState: .disabled,
                manifestPermissions: ["storage"],
                allowlist: .controlledActionPopupPolicy
            )
        ).handle(request(
            namespace: "permissions",
            methodName: "getAll"
        ))

        XCTAssertTrue(promise.succeeded)
        XCTAssertNil(promise.lastErrorCode)
        XCTAssertFalse(promise.promiseWouldReject)
        XCTAssertFalse(promise.callbackWouldSetLastError)
        let promiseObject = try XCTUnwrap(objectValue(promise.resultPayload))
        let permissions = stringArrayValue(promiseObject["permissions"])
        let origins = stringArrayValue(promiseObject["origins"])
        XCTAssertEqual(permissions, ["storage", "tabs"])
        XCTAssertEqual(origins, ["https://example.com/*"])
        XCTAssertFalse(permissions.contains("history"))
        XCTAssertFalse(permissions.contains("bookmarks"))
        XCTAssertFalse(origins.contains("https://optional.example/*"))

        XCTAssertTrue(callback.succeeded)
        XCTAssertNil(callback.lastErrorCode)
        XCTAssertFalse(callback.callbackWouldSetLastError)
        let callbackObject = try XCTUnwrap(objectValue(callback.resultPayload))
        XCTAssertEqual(
            stringArrayValue(callbackObject["permissions"]),
            permissions
        )
        XCTAssertEqual(stringArrayValue(callbackObject["origins"]), origins)

        XCTAssertFalse(invalidArgs.succeeded)
        XCTAssertEqual(invalidArgs.lastErrorCode, "invalidArguments")
        XCTAssertFalse(blockedRequest.succeeded)
        XCTAssertEqual(blockedRequest.lastErrorCode, "productBlocked")
        XCTAssertFalse(disabledModule.succeeded)
        XCTAssertEqual(disabledModule.lastErrorCode, "extensionDisabled")

        let root = try makeTemporaryDirectory()
        let store = ChromeMV3DeveloperPreviewPermissionStateStore(
            rootURL: root
        )
        let grantedOwner = ChromeMV3PermissionRuntimeStateOwner(
            permissionStore:
                ChromeMV3PermissionDecisionStore(
                    snapshot:
                        ChromeMV3PermissionDecisionStoreSnapshot(
                            extensionID: config.extensionID,
                            profileID: config.profileID,
                            declaredAPIPermissions: ["storage", "tabs"],
                            declaredHostPermissions: ["https://example.com/*"],
                            optionalAPIPermissions: ["history"],
                            optionalHostPermissions: [
                                "https://optional.example/*",
                            ],
                            grantedOptionalAPIPermissions: ["history"],
                            grantedOptionalHostPermissions: [
                                "https://optional.example/*",
                            ]
                        )
                )
        )
        try store.save(
            owner: grantedOwner,
            gateRecord: ChromeMV3PermissionPromptGateRecord.evaluate(
                moduleEnabled: true,
                extensionEnabled: true,
                developerPreviewGate: true
            )
        )
        let grantedHandler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(
                extensionID: config.extensionID,
                profileID: config.profileID,
                manifestPermissions: ["storage", "tabs"],
                manifestOptionalPermissions: ["history"],
                manifestHostPermissions: ["https://example.com/*"],
                manifestOptionalHostPermissions: [
                    "https://optional.example/*",
                ],
                allowlist: .controlledActionPopupPolicy
            ),
            permissionStateStore: store
        )
        let grantedAll = grantedHandler.handle(request(
            namespace: "permissions",
            methodName: "getAll"
        ))
        let grantedObject = try XCTUnwrap(objectValue(grantedAll.resultPayload))
        XCTAssertTrue(
            stringArrayValue(grantedObject["permissions"]).contains("history")
        )
        XCTAssertTrue(
            stringArrayValue(grantedObject["origins"])
                .contains("https://optional.example/*")
        )

        let containsAfterGetAll = handler.handle(request(
            namespace: "permissions",
            methodName: "contains",
            arguments: [.object(["permissions": .array([.string("storage")])])]
        ))
        XCTAssertTrue(containsAfterGetAll.succeeded)
        XCTAssertEqual(boolValue(containsAfterGetAll.resultPayload), true)

        let controlledSource = ChromeMV3PopupOptionsJSShimSource.source(
            configuration: config
        )
        XCTAssertTrue(
            controlledSource.contains("const browserRoot = rootObject(\"browser\")")
        )
        XCTAssertTrue(
            controlledSource.contains(
                "Object.defineProperty(permissions, \"getAll\""
            )
        )
    }

    @MainActor
    private func makeControlledRuntimeIDBridgeHandle(
        extensionID: String
    ) async throws -> ChromeMV3ProductPopupOptionsWKWebViewHandle {
        let root = try makeTemporaryDirectory()
        let htmlURL = root.appendingPathComponent("popup.html")
        try """
        <!doctype html>
        <meta charset="utf-8">
        <title>Runtime ID</title>
        """.write(to: htmlURL, atomically: true, encoding: .utf8)
        let config = configuration(
            extensionID: extensionID,
            allowlist: .controlledActionPopupPolicy
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
        try await handle.waitForLoadForTesting()
        return handle
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
        let runtimeManifest = try XCTUnwrap(
            ChromeMV3PopupOptionsRuntimeManifestSnapshot
                .fromManifestPayload(.object([
                    "manifest_version": .number(3),
                    "name": .string("Generic Popup Bridge"),
                    "version": .string("1.0.0"),
                    "action": .object([
                        "default_popup": .string("popup.html"),
                    ]),
                    "permissions": .array([
                        .string("storage"),
                        .string("tabs"),
                    ]),
                    "host_permissions": .array([
                        .string("https://example.com/*"),
                    ]),
                ]))
        )
        let config = configuration(
            manifestPermissions: ["tabs"],
            manifestHostPermissions: ["https://example.com/*"],
            runtimeManifest: runtimeManifest,
            allowlist: .controlledActionPopupPolicy
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
            const localChanges = [];
            const localRemovedChanges = [];
            const sessionChanges = [];
            const syncChanges = [];
            const browserLocalChanges = [];
            const runtimeMessages = [];
            const runtimeListener = function(message, sender, sendResponse) {
              runtimeMessages.push({
                argCount: arguments.length,
                hasSender: !!sender,
                sendResponseType: typeof sendResponse
              });
            };
            const removedRuntimeListener = function() {};
            const hasRuntimeOnMessageMethods =
              !!chrome.runtime.onMessage
              && typeof chrome.runtime.onMessage.addListener === "function"
              && typeof chrome.runtime.onMessage.removeListener === "function"
              && typeof chrome.runtime.onMessage.hasListener === "function"
              && typeof chrome.runtime.onMessage.hasListeners === "function";
            const browserRuntimeOnMessageSameObject =
              browser.runtime.onMessage === chrome.runtime.onMessage;
            chrome.runtime.onMessage.addListener(runtimeListener);
            chrome.runtime.onMessage.addListener(removedRuntimeListener);
            const runtimeHasListenerBeforeRemove =
              chrome.runtime.onMessage.hasListener(runtimeListener);
            const runtimeHasListenersBeforeRemove =
              chrome.runtime.onMessage.hasListeners();
            chrome.runtime.onMessage.removeListener(removedRuntimeListener);
            const runtimeRemovedHasListenerAfterRemove =
              chrome.runtime.onMessage.hasListener(removedRuntimeListener);
            chrome.storage.onChanged.addListener((changesObject, areaName) => {
              changes.push({
                areaName,
                hasAlpha: Object.prototype.hasOwnProperty.call(changesObject, "alpha"),
                changedKeyCount: Object.keys(changesObject).length
              });
            });
            const localListener = (changesObject, areaName) => {
              localChanges.push({
                areaName,
                hasOldValue: Object.prototype.hasOwnProperty.call(
                  changesObject.alpha || {},
                  "oldValue"
                ),
                oldValue: changesObject.alpha && changesObject.alpha.oldValue,
                hasNewValue: Object.prototype.hasOwnProperty.call(
                  changesObject.alpha || {},
                  "newValue"
                ),
                newValue: changesObject.alpha && changesObject.alpha.newValue
              });
            };
            const removedLocalListener = (changesObject, areaName) => {
              localRemovedChanges.push({ areaName });
            };
            chrome.storage.local.onChanged.addListener(localListener);
            chrome.storage.local.onChanged.addListener(removedLocalListener);
            const localHasListenerBeforeRemove =
              chrome.storage.local.onChanged.hasListener(localListener);
            const localHasListenersBeforeRemove =
              chrome.storage.local.onChanged.hasListeners();
            chrome.storage.local.onChanged.removeListener(removedLocalListener);
            const removedLocalHasListenerAfterRemove =
              chrome.storage.local.onChanged.hasListener(removedLocalListener);
            browser.storage.local.onChanged.addListener((changesObject, areaName) => {
              browserLocalChanges.push({
                areaName,
                hasAlpha: Object.prototype.hasOwnProperty.call(changesObject, "alpha")
              });
            });
            chrome.storage.session.onChanged.addListener((changesObject, areaName) => {
              sessionChanges.push({
                areaName,
                changedKeyCount: Object.keys(changesObject).length,
                hasSessionAlpha:
                  Object.prototype.hasOwnProperty.call(changesObject, "sessionAlpha"),
                setNewValue:
                  changesObject.sessionAlpha
                  && changesObject.sessionAlpha.newValue,
                clearOldValue:
                  changesObject.sessionAlpha
                  && changesObject.sessionAlpha.oldValue,
                clearHasNewValue:
                  Object.prototype.hasOwnProperty.call(
                    changesObject.sessionAlpha || {},
                    "newValue"
                  )
              });
            });
            browser.storage.sync.onChanged.addListener((changesObject, areaName) => {
              syncChanges.push({
                areaName,
                hasSyncAlpha:
                  Object.prototype.hasOwnProperty.call(changesObject, "syncAlpha"),
                newValue:
                  changesObject.syncAlpha
                  && changesObject.syncAlpha.newValue
              });
            });
            await chrome.storage.local.set({ alpha: "beta" });
            await chrome.storage.session.set({ sessionAlpha: "session-beta" });
            await chrome.storage.sync.set({ syncAlpha: "sync-beta" });
            await chrome.storage.local.remove("alpha");
            await chrome.storage.session.clear();
            const stored = await chrome.storage.local.get("alpha");
            const tabs = await chrome.tabs.query({ active: true });
            const chromeCurrent = await chrome.tabs.getCurrent();
            const browserCurrent = await browser.tabs.getCurrent();
            let getCurrentCallbackIsUndefined = false;
            let getCurrentCallbackArgCount = -1;
            let getCurrentCallbackLastError = "unset";
            await new Promise((resolve) => {
              chrome.tabs.getCurrent(function(tab) {
                getCurrentCallbackIsUndefined = tab === undefined;
                getCurrentCallbackArgCount = arguments.length;
                getCurrentCallbackLastError = chrome.runtime.lastError
                  ? chrome.runtime.lastError.message
                  : null;
                resolve();
              });
            });
            const getCurrentLastErrorAfterCallback =
              chrome.runtime.lastError || null;
            const firstManifest = chrome.runtime.getManifest();
            const isManifestPromise =
              !!firstManifest && typeof firstManifest.then === "function";
            firstManifest.name = "mutated";
            firstManifest.action.default_popup = "mutated.html";
            const secondManifest = chrome.runtime.getManifest();
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
            await new Promise((resolve) => setTimeout(resolve, 60));
            return {
              hasChrome: !!chrome.runtime && !!browser.runtime,
              storedHasAlpha: Object.prototype.hasOwnProperty.call(stored, "alpha"),
              changeCount: changes.length,
              changeArea: changes[0] && changes[0].areaName,
              globalAreas: changes.map((entry) => entry.areaName).sort(),
              hasLocalAreaOnChanged:
                !!chrome.storage.local.onChanged
                && typeof chrome.storage.local.onChanged.addListener === "function"
                && typeof chrome.storage.local.onChanged.removeListener === "function"
                && typeof chrome.storage.local.onChanged.hasListener === "function"
                && typeof chrome.storage.local.onChanged.hasListeners === "function",
              hasSessionAreaOnChanged:
                !!chrome.storage.session.onChanged
                && typeof chrome.storage.session.onChanged.addListener === "function",
              hasSyncAreaOnChanged:
                !!chrome.storage.sync.onChanged
                && typeof chrome.storage.sync.onChanged.addListener === "function",
              hasBrowserLocalAreaOnChanged:
                !!browser.storage.local.onChanged
                && typeof browser.storage.local.onChanged.addListener === "function",
              hasRuntimeOnMessageMethods,
              browserRuntimeOnMessageSameObject,
              runtimeHasListenerBeforeRemove,
              runtimeHasListenersBeforeRemove,
              runtimeRemovedHasListenerAfterRemove,
              runtimeMessageDispatchCount: runtimeMessages.length,
              localHasListenerBeforeRemove,
              localHasListenersBeforeRemove,
              removedLocalHasListenerAfterRemove,
              localChangeCount: localChanges.length,
              localAreas: localChanges.map((entry) => entry.areaName).sort(),
              localSetHasOldValue: localChanges[0] && localChanges[0].hasOldValue,
              localSetHasNewValue: localChanges[0] && localChanges[0].hasNewValue,
              localSetNewValue: localChanges[0] && localChanges[0].newValue,
              localRemoveOldValue: localChanges[1] && localChanges[1].oldValue,
              localRemoveHasNewValue: localChanges[1] && localChanges[1].hasNewValue,
              localRemovedListenerCount: localRemovedChanges.length,
              browserLocalChangeCount: browserLocalChanges.length,
              browserLocalAreas:
                browserLocalChanges.map((entry) => entry.areaName).sort(),
              sessionChangeCount: sessionChanges.length,
              sessionAreas: sessionChanges.map((entry) => entry.areaName).sort(),
              sessionSetNewValue: sessionChanges[0] && sessionChanges[0].setNewValue,
              sessionClearOldValue:
                sessionChanges[1] && sessionChanges[1].clearOldValue,
              sessionClearHasNewValue:
                sessionChanges[1] && sessionChanges[1].clearHasNewValue,
              syncChangeCount: syncChanges.length,
              syncAreas: syncChanges.map((entry) => entry.areaName).sort(),
              syncSetNewValue: syncChanges[0] && syncChanges[0].newValue,
              tabURL: tabs[0] && tabs[0].url,
              chromeCurrentIsUndefined: chromeCurrent === undefined,
              browserCurrentIsUndefined: browserCurrent === undefined,
              getCurrentCallbackIsUndefined,
              getCurrentCallbackArgCount,
              getCurrentCallbackLastError,
              getCurrentLastErrorAfterCallback,
              hasGetManifest:
                typeof chrome.runtime.getManifest === "function",
              manifestVersion: secondManifest.manifest_version,
              manifestName: secondManifest.name,
              manifestPopup: secondManifest.action.default_popup,
              isManifestPromise,
              promiseRejected,
              callbackLastError,
              lastErrorAfterCallback: chrome.runtime.lastError || null
            };
            """
        )
        let object = try XCTUnwrap(raw as? [String: Any])

        XCTAssertEqual(object["hasChrome"] as? Bool, true)
        XCTAssertEqual(object["storedHasAlpha"] as? Bool, false)
        XCTAssertEqual(object["changeCount"] as? Int, 5)
        XCTAssertEqual(object["changeArea"] as? String, "local")
        XCTAssertEqual(
            object["globalAreas"] as? [String],
            ["local", "local", "session", "session", "sync"]
        )
        XCTAssertEqual(object["hasLocalAreaOnChanged"] as? Bool, true)
        XCTAssertEqual(object["hasSessionAreaOnChanged"] as? Bool, true)
        XCTAssertEqual(object["hasSyncAreaOnChanged"] as? Bool, true)
        XCTAssertEqual(object["hasBrowserLocalAreaOnChanged"] as? Bool, true)
        XCTAssertEqual(object["hasRuntimeOnMessageMethods"] as? Bool, true)
        XCTAssertEqual(
            object["browserRuntimeOnMessageSameObject"] as? Bool,
            true
        )
        XCTAssertEqual(
            object["runtimeHasListenerBeforeRemove"] as? Bool,
            true
        )
        XCTAssertEqual(
            object["runtimeHasListenersBeforeRemove"] as? Bool,
            true
        )
        XCTAssertEqual(
            object["runtimeRemovedHasListenerAfterRemove"] as? Bool,
            false
        )
        XCTAssertEqual(object["runtimeMessageDispatchCount"] as? Int, 0)
        XCTAssertEqual(object["localHasListenerBeforeRemove"] as? Bool, true)
        XCTAssertEqual(
            object["localHasListenersBeforeRemove"] as? Bool,
            true
        )
        XCTAssertEqual(
            object["removedLocalHasListenerAfterRemove"] as? Bool,
            false
        )
        XCTAssertEqual(object["localChangeCount"] as? Int, 2)
        XCTAssertEqual(object["localAreas"] as? [String], ["local", "local"])
        XCTAssertEqual(object["localSetHasOldValue"] as? Bool, false)
        XCTAssertEqual(object["localSetHasNewValue"] as? Bool, true)
        XCTAssertEqual(object["localSetNewValue"] as? String, "beta")
        XCTAssertEqual(object["localRemoveOldValue"] as? String, "beta")
        XCTAssertEqual(object["localRemoveHasNewValue"] as? Bool, false)
        XCTAssertEqual(object["localRemovedListenerCount"] as? Int, 0)
        XCTAssertEqual(object["browserLocalChangeCount"] as? Int, 2)
        XCTAssertEqual(
            object["browserLocalAreas"] as? [String],
            ["local", "local"]
        )
        XCTAssertEqual(object["sessionChangeCount"] as? Int, 2)
        XCTAssertEqual(
            object["sessionAreas"] as? [String],
            ["session", "session"]
        )
        XCTAssertEqual(
            object["sessionSetNewValue"] as? String,
            "session-beta"
        )
        XCTAssertEqual(
            object["sessionClearOldValue"] as? String,
            "session-beta"
        )
        XCTAssertEqual(object["sessionClearHasNewValue"] as? Bool, false)
        XCTAssertEqual(object["syncChangeCount"] as? Int, 1)
        XCTAssertEqual(object["syncAreas"] as? [String], ["sync"])
        XCTAssertEqual(object["syncSetNewValue"] as? String, "sync-beta")
        XCTAssertEqual(object["tabURL"] as? String, "https://example.com/login")
        XCTAssertEqual(object["chromeCurrentIsUndefined"] as? Bool, true)
        XCTAssertEqual(object["browserCurrentIsUndefined"] as? Bool, true)
        XCTAssertEqual(object["getCurrentCallbackIsUndefined"] as? Bool, true)
        XCTAssertEqual(object["getCurrentCallbackArgCount"] as? Int, 1)
        XCTAssertTrue(object["getCurrentCallbackLastError"] is NSNull)
        XCTAssertTrue(object["getCurrentLastErrorAfterCallback"] is NSNull)
        XCTAssertEqual(object["hasGetManifest"] as? Bool, true)
        XCTAssertEqual(object["manifestVersion"] as? Int, 3)
        XCTAssertEqual(object["manifestName"] as? String, "Generic Popup Bridge")
        XCTAssertEqual(object["manifestPopup"] as? String, "popup.html")
        XCTAssertEqual(object["isManifestPromise"] as? Bool, false)
        XCTAssertEqual(object["promiseRejected"] as? Bool, true)
        XCTAssertTrue((object["callbackLastError"] as? String)?
            .contains("Receiving end") == true)
        XCTAssertTrue(object["lastErrorAfterCallback"] is NSNull)
        let snapshot = try XCTUnwrap(
            handle.popupOptionsBridgeDiagnosticsSnapshot
        )
        XCTAssertTrue(snapshot.observedMethods.contains("runtime.getManifest"))
        XCTAssertTrue(snapshot.observedMethods.contains("storage.local.set"))
        XCTAssertTrue(snapshot.observedMethods.contains("storage.session.set"))
        XCTAssertTrue(snapshot.observedMethods.contains("storage.sync.set"))
        XCTAssertTrue(snapshot.observedMethods.contains("tabs.getCurrent"))
        XCTAssertTrue(
            snapshot.observedMethods.contains("tabs.sendMessage"),
            "observedMethods=\(snapshot.observedMethods)"
        )
        XCTAssertTrue(snapshot.jsDebugRouteEvents.contains {
            $0.apiName == "chrome.runtime.onMessage"
                && $0.targetContext == "extensionPage"
                && $0.resultClassifier == "event object present"
                && $0.diagnostics.contains("eventObjectPresent=true")
                && $0.diagnostics.contains("listenerCount=0")
                && $0.diagnostics.contains(
                    "listenerRegistryScope=pageSession;profile;extension"
                )
                && $0.diagnostics.contains("sourceContext=actionPopup")
                && $0.diagnostics.contains("targetContext=extensionPage")
                && $0.diagnostics.contains("senderMetadataShape=none")
                && $0.diagnostics.contains("responseClassifier=registrationOnly")
                && $0.diagnostics.contains("inboundRoute=notWired")
        })
        XCTAssertTrue(snapshot.jsDebugRouteEvents.contains {
            $0.apiName == "chrome.runtime.onMessage"
                && $0.resultClassifier == "listener added"
                && $0.diagnostics.contains("listenerCount=2")
                && $0.diagnostics.contains("responseClassifier=registrationOnly")
                && $0.diagnostics.contains("inboundRoute=notWired")
        })
        XCTAssertTrue(snapshot.jsDebugRouteEvents.contains {
            $0.apiName == "chrome.runtime.onMessage"
                && $0.resultClassifier == "listener removed"
                && $0.diagnostics.contains("listenerCount=1")
                && $0.diagnostics.contains("responseClassifier=registrationOnly")
                && $0.diagnostics.contains("inboundRoute=notWired")
        })
        XCTAssertTrue(snapshot.jsDebugRouteEvents.contains {
            $0.apiName == "chrome.storage.local.onChanged"
                && $0.targetContext == "storage.local"
                && $0.resultClassifier == "storage area onChanged dispatched"
                && $0.diagnostics.contains("area=local")
                && $0.diagnostics.contains("eventObjectPresent=true")
                && $0.diagnostics.contains("listenerCount=2")
                && $0.diagnostics.contains("globalListenerCount=1")
                && $0.diagnostics.contains("changedKeyCount=1")
        })
        XCTAssertTrue(snapshot.jsDebugRouteEvents.contains {
            $0.apiName == "chrome.storage.session.onChanged"
                && $0.targetContext == "storage.session"
                && $0.resultClassifier == "storage area onChanged dispatched"
                && $0.diagnostics.contains("listenerCount=1")
                && $0.diagnostics.contains("changedKeyCount=1")
        })
        XCTAssertTrue(snapshot.jsDebugRouteEvents.contains {
            $0.apiName == "chrome.storage.sync.onChanged"
                && $0.targetContext == "storage.sync"
                && $0.resultClassifier == "storage area onChanged dispatched"
                && $0.diagnostics.contains("listenerCount=1")
                && $0.diagnostics.contains("changedKeyCount=1")
        })
        XCTAssertTrue(snapshot.callRecords.contains {
            $0.namespace == "tabs"
                && $0.methodName == "getCurrent"
                && $0.succeeded
                && $0.diagnostics.contains {
                    $0.contains("result=undefined")
                }
        })
        XCTAssertTrue(snapshot.callRecords.allSatisfy {
            $0.nativeHostLaunchAttempted == false
        })
        let encodedSnapshot = String(
            data: try JSONEncoder().encode(snapshot),
            encoding: .utf8
        ) ?? ""
        XCTAssertFalse(encodedSnapshot.contains("sessionAlpha"))
        XCTAssertFalse(encodedSnapshot.contains("syncAlpha"))
        XCTAssertFalse(encodedSnapshot.contains("session-beta"))
        XCTAssertFalse(encodedSnapshot.contains("sync-beta"))
        XCTAssertFalse(encodedSnapshot.contains("runtimeMessages"))
        XCTAssertFalse(encodedSnapshot.contains("sendResponseType"))
    }

    @MainActor
    func testRealPopupOptionsWKWebViewQueuesRuntimePortMessageUntilHostPortIDResolves()
        async throws
    {
        let root = try makeTemporaryDirectory()
        let htmlURL = root.appendingPathComponent("popup.html")
        try """
        <!doctype html>
        <meta charset="utf-8">
        <title>Runtime Port Popup</title>
        <main data-sumi-extension-page-fixture-marker="safe">Popup</main>
        """.write(to: htmlURL, atomically: true, encoding: .utf8)
        let session = try makeSharedLifecycleSession()
        registerRuntimePortEchoDispatchers(on: session)
        let config = configuration(
            allowlist: .controlledActionPopupPolicy
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
            sharedLifecycleSession: session,
            permissionPromptPresenter: nil,
            permissionEventDispatcher: nil
        )
        defer { handle.tearDown() }

        try await handle.waitForLoadForTesting()
        let raw = try await handle.callAsyncJavaScriptForTesting(
            """
            const port = chrome.runtime.connect();
            const messages = [];
            let disconnectCount = 0;
            let disconnectLastError = null;
            port.onMessage.addListener((message) => {
              messages.push({
                hasEcho: !!message.echo,
                echoPing:
                  !!message.echo && message.echo.ping === true
              });
            });
            port.onDisconnect.addListener(() => {
              disconnectCount += 1;
              disconnectLastError = chrome.runtime.lastError
                ? chrome.runtime.lastError.message
                : null;
            });
            port.postMessage({ ping: true });
            await new Promise((resolve) => setTimeout(resolve, 160));
            const beforeDisconnectCount = disconnectCount;
            const beforeDisconnectLastError = disconnectLastError;
            port.disconnect();
            await new Promise((resolve) => setTimeout(resolve, 60));
            const debug = globalThis.__sumiChromeMV3PopupOptionsDebugSnapshot();
            return {
              messageCount: messages.length,
              firstMessageHasEcho: messages[0] && messages[0].hasEcho,
              firstMessageEchoPing: messages[0] && messages[0].echoPing,
              beforeDisconnectCount,
              beforeDisconnectLastError,
              disconnectCount,
              disconnectLastError,
              pendingCount: debug.pending.length,
              queuedEventCount: debug.events.filter((event) => {
                return event.eventKind === "portMessageQueued";
              }).length,
              deliveredEventCount: debug.events.filter((event) => {
                return event.eventKind === "portMessageDelivered";
              }).length,
              failedEventCount: debug.events.filter((event) => {
                return event.eventKind === "portMessageBridgeFailed";
              }).length
            };
            """
        )
        let object = try XCTUnwrap(raw as? [String: Any])

        XCTAssertEqual(object["messageCount"] as? Int, 1)
        XCTAssertEqual(object["firstMessageHasEcho"] as? Bool, true)
        XCTAssertEqual(object["firstMessageEchoPing"] as? Bool, true)
        XCTAssertEqual(object["beforeDisconnectCount"] as? Int, 0)
        XCTAssertTrue(object["beforeDisconnectLastError"] is NSNull)
        XCTAssertEqual(object["disconnectCount"] as? Int, 1)
        XCTAssertTrue(object["disconnectLastError"] is NSNull)
        XCTAssertEqual(object["pendingCount"] as? Int, 0)
        XCTAssertEqual(object["queuedEventCount"] as? Int, 1)
        XCTAssertEqual(object["deliveredEventCount"] as? Int, 1)
        XCTAssertEqual(object["failedEventCount"] as? Int, 0)

        let snapshot = try XCTUnwrap(
            handle.popupOptionsBridgeDiagnosticsSnapshot
        )
        XCTAssertTrue(snapshot.observedMethods.contains("runtime.connect"))
        XCTAssertTrue(snapshot.observedMethods.contains(
            "runtime.port.postMessage"
        ))
        XCTAssertTrue(snapshot.observedMethods.contains(
            "runtime.port.disconnect"
        ))
        XCTAssertTrue(snapshot.jsDebugRouteEvents.contains {
            $0.eventKind == "portMessageQueued"
                && $0.apiName == "Port.postMessage"
                && $0.resultClassifier == "queued"
        })
        XCTAssertTrue(snapshot.jsDebugRouteEvents.contains {
            $0.eventKind == "portMessageDelivered"
                && $0.apiName == "runtime.port.postMessage"
                && $0.resultClassifier == "Port message delivered"
        })
        XCTAssertFalse(snapshot.jsDebugRouteEvents.contains {
            $0.eventKind == "portMessageBridgeFailed"
        })
        XCTAssertTrue(
            session.runtimeOwner.snapshot.activeKeepaliveRecords.isEmpty
        )
        let encodedSnapshot = String(
            data: try JSONEncoder().encode(snapshot),
            encoding: .utf8
        ) ?? ""
        XCTAssertFalse(encodedSnapshot.contains("\"ping\""))
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
        runtimeManifest: ChromeMV3PopupOptionsRuntimeManifestSnapshot? = nil,
        i18nCatalogSnapshot:
            ChromeMV3PopupOptionsI18nCatalogSnapshot? = nil,
        activeTabGrants: [ChromeMV3ActiveTabGrant] = [],
        allowlist: ChromeMV3PopupOptionsAPIMethodPolicy = .defaultPolicy,
        storageLocalRootPath: String? = nil,
        storageSyncRootPath: String? = nil,
        generatedBundleRootPath: String? = nil
    ) -> ChromeMV3PopupOptionsJSBridgeConfiguration {
        ChromeMV3PopupOptionsJSBridgeConfiguration(
            extensionID: extensionID,
            profileID: profileID,
            surfaceID: "\(profileID):\(extensionID):\(surface.rawValue)",
            surface: surface,
            extensionBaseURLString: "chrome-extension://\(extensionID)/",
            generatedBundleRootPath: generatedBundleRootPath,
            permissionStateRootPath: nil,
            storageLocalRootPath: storageLocalRootPath,
            storageSyncRootPath: storageSyncRootPath,
            moduleState: moduleState,
            bridgeAvailable: bridgeAvailable,
            popupOptionsJSBridgeAvailableInDeveloperPreview:
                bridgeAvailable && moduleState == .enabled,
            popupOptionsJSBridgeAvailableInPublicProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            contentScriptAttachmentAvailableInProduct: false,
            runtimeLoadable: false,
            runtimeManifest: runtimeManifest,
            i18nCatalogSnapshot: i18nCatalogSnapshot,
            manifestPermissions: manifestPermissions,
            manifestOptionalPermissions: manifestOptionalPermissions,
            manifestHostPermissions: manifestHostPermissions,
            manifestOptionalHostPermissions: manifestOptionalHostPermissions,
            activeTabGrants: activeTabGrants,
            allowlist: allowlist,
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

#if canImport(WebKit)
@MainActor
private final class ChromeMV3PopupOptionsExecuteScriptTestNavigationObserver:
    NSObject,
    WKNavigationDelegate
{
    private var continuation: CheckedContinuation<Void, Error>?

    func wait(navigation: WKNavigation?) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            if navigation == nil {
                continuation.resume()
                self.continuation = nil
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
#endif
