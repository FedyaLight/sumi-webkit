import Foundation
import BrowserServicesKit
import SwiftData
import WebKit
import XCTest
@testable import Sumi

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerTests {
    func testExternallyConnectableBridgeEnvelopeDecodesSendMessageRequest() throws {
        let body: [String: Any] = [
            "bridgeVersion": 1,
            "featureName": "runtime",
            "method": "sendMessage",
            "id": "request-1",
            "params": [
                "extensionId": "fixture.extension",
                "message": [
                    "count": 1,
                    "type": "ping",
                ],
                "options": NSNull(),
                "origin": "https://example.com",
                "timeoutMs": 5000,
            ],
        ]

        let envelope = try XCTUnwrap(
            ExternallyConnectableBridgeCodec.decode(
                ExternallyConnectableBridgeEnvelope.self,
                from: body
            )
        )
        let request = try XCTUnwrap(
            envelope.decodeParams(ExternallyConnectableNativeSendMessageRequest.self)
        )

        XCTAssertEqual(envelope.featureName, "runtime")
        XCTAssertEqual(envelope.method, "sendMessage")
        XCTAssertEqual(envelope.id, "request-1")
        XCTAssertEqual(request.extensionId, "fixture.extension")
        XCTAssertEqual(
            request.message?.foundationObject as? [String: AnyHashable],
            [
                "count": 1,
                "type": "ping",
            ]
        )
    }

    func testExternallyConnectableBridgeEnvelopeRejectsInvalidPayload() {
        let invalidBody: [String: Any] = [
            "featureName": "runtime",
            "params": [:],
        ]

        let envelope = ExternallyConnectableBridgeCodec.decode(
            ExternallyConnectableBridgeEnvelope.self,
            from: invalidBody
        )

        XCTAssertNil(envelope)
    }

    func testExternallyConnectableBridgeCodecRoundTripsConnectRequestAndAcceptedResponse() throws {
        let body: [String: Any] = [
            "bridgeVersion": 1,
            "featureName": "runtime",
            "method": "runtime.connect.open",
            "params": [
                "extensionId": "fixture.extension",
                "portId": "port-1",
                "timeoutMs": 1234,
                "connectInfo": [
                    "name": "fixture-port",
                    "persist": true,
                ],
            ],
        ]

        let envelope = try XCTUnwrap(
            ExternallyConnectableBridgeCodec.decode(
                ExternallyConnectableBridgeEnvelope.self,
                from: body
            )
        )
        let request = try XCTUnwrap(
            envelope.decodeParams(ExternallyConnectableNativeConnectOpenRequest.self)
        )
        let connectInfo = request.connectInfo?.mapValues(\.foundationObject)
        let response = ExternallyConnectableBridgeCodec.foundationObject(
            from: ExternallyConnectableNativeAcceptedResponse(
                accepted: true,
                portId: "port-1"
            )
        ) as? [String: AnyHashable]

        XCTAssertEqual(request.extensionId, "fixture.extension")
        XCTAssertEqual(request.portId, "port-1")
        XCTAssertEqual(request.timeoutMs, 1234)
        XCTAssertEqual(
            connectInfo as? [String: AnyHashable],
            [
                "name": "fixture-port",
                "persist": true,
            ]
        )
        XCTAssertEqual(
            response,
            [
                "accepted": true,
                "portId": "port-1",
            ]
        )
    }

    func testExtensionRuntimeBundledScriptLoaderFindsAllTemplates() {
        let requiredFileNames = [
            "externally_connectable_background_helper.js",
            "externally_connectable_isolated_bridge.js",
            "externally_connectable_page_bridge.js",
            "externally_connectable_worker.js",
            "selective_content_script_guard.js",
            "webkit_runtime_compat.js",
            "webkit_runtime_compat_worker.js",
        ]

        for fileName in requiredFileNames {
            let source = ExtensionRuntimeBundledScript.source(fileName: fileName)
            XCTAssertNotNil(source, "Missing bundled runtime template \(fileName)")
            XCTAssertFalse(source?.isEmpty ?? true, "Bundled runtime template \(fileName) is empty")
        }
    }

    func testPageBridgeScriptIncludesNativeSendMessageTransportConfiguration() {
        let source = ExtensionManager.debugExternallyConnectablePageBridgeScriptSource()

        XCTAssertTrue(source.contains("window.webkit.messageHandlers"))
        XCTAssertTrue(
            source.contains(
                ExtensionManager.externallyConnectableNativeBridgeHandlerName
            )
        )
        XCTAssertTrue(source.contains("featureName: 'runtime'"))
        XCTAssertTrue(source.contains("method: 'sendMessage'"))
        XCTAssertTrue(source.contains("runtime.connect.open"))
        XCTAssertTrue(source.contains("__sumiEcNativePortOpened"))
        XCTAssertTrue(source.contains("chrome.runtime.lastError"))
        XCTAssertTrue(source.contains("createBridgePort"))
        XCTAssertTrue(source.contains("nativeHybrid"))
        XCTAssertFalse(source.contains("useNativeSendMessage"))
        XCTAssertFalse(source.contains("useNativeConnect"))
        XCTAssertFalse(source.contains("requestViaLegacySendMessageBridge"))
        XCTAssertFalse(source.contains("createLegacyBridgePort"))
        XCTAssertFalse(source.contains("CustomEvent"))
    }

    func testBundledRuntimeTemplateRenderingSubstitutesPageBridgeValues() {
        let bridgeMarker = "/* bundled-template-marker */"
        let source = ExtensionManager.debugExternallyConnectablePageBridgeScriptSource(
            allowedHosts: ["accounts.example.com", "example.org"],
            configuredRuntimeId: "fixture.extension",
            bridgeMarker: bridgeMarker
        )

        XCTAssertTrue(source.contains(bridgeMarker))
        XCTAssertTrue(source.contains("\"accounts.example.com\""))
        XCTAssertTrue(source.contains("\"example.org\""))
        XCTAssertTrue(source.contains("\"fixture.extension\""))
        XCTAssertTrue(
            source.contains(ExtensionManager.externallyConnectableNativeBridgeHandlerName)
        )
        XCTAssertFalse(source.contains("__SUMI_CONFIG_JSON__"))
        XCTAssertFalse(source.contains("__SUMI_BRIDGE_MARKER__"))
        XCTAssertFalse(source.contains("__SUMI_BRIDGE_MARKER_STRING__"))
    }

    func testBundledRuntimeTemplateRenderingSubstitutesCompatibilityWorkerValues() {
        let source = ExtensionManager.webKitRuntimeCompatibilityServiceWorkerWrapperScript(
            originalServiceWorker: "background.js",
            backgroundType: nil
        )

        XCTAssertTrue(
            source.contains("SUMI_WEBKIT_RUNTIME_COMPAT_ORIGINAL_SERVICE_WORKER: background.js")
        )
        XCTAssertTrue(
            source.contains("SUMI_WEBKIT_RUNTIME_COMPAT_SERVICE_WORKER_MODE: classic")
        )
        XCTAssertTrue(
            source.contains("importScripts(\"sumi_webkit_runtime_compat.js\", \"background.js\");")
        )
        XCTAssertFalse(source.contains("__SUMI_ORIGINAL_SERVICE_WORKER__"))
        XCTAssertFalse(source.contains("__SUMI_BACKGROUND_TYPE__"))
        XCTAssertFalse(source.contains("__SUMI_WORKER_IMPORTS__"))
    }

    func testBackgroundHelperDispatchesEnvelopeToOnMessageExternal() async throws {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        try await loadHTMLString(
            "<!doctype html><html><head></head><body>background-helper</body></html>",
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        let helperSource = ExtensionManager
            .debugExternallyConnectableBackgroundHelperScriptSource()
        let rawResult = try await webView.callAsyncJavaScript(
            """
            function makeEvent() {
                var listeners = [];
                return {
                    addListener: function(listener) {
                        listeners.push(listener);
                    },
                    removeListener: function(listener) {
                        listeners = listeners.filter(function(candidate) {
                            return candidate !== listener;
                        });
                    },
                    hasListener: function(listener) {
                        return listeners.indexOf(listener) !== -1;
                    },
                    hasListeners: function() {
                        return listeners.length > 0;
                    },
                    dispatch: function(message, sender, sendResponse) {
                        listeners.slice().forEach(function(listener) {
                            listener(message, sender, sendResponse);
                        });
                    }
                };
            }

            window.browser = {
                runtime: {
                    id: 'fixture.extension',
                    onConnectExternal: makeEvent(),
                    onMessage: makeEvent(),
                    onMessageExternal: makeEvent()
                }
            };
            window.chrome = { runtime: window.browser.runtime };

            var nativeOnMessage = window.browser.runtime.onMessage;

            \(helperSource)

            var regularMessages = [];
            window.browser.runtime.onMessage.addListener(function(message) {
                regularMessages.push(message && message.type ? message.type : typeof message);
            });

            window.browser.runtime.onMessageExternal.addListener(function(message, sender, sendResponse) {
                sendResponse({
                    echo: message,
                    sender: sender,
                    via: 'external'
                });
                return true;
            });

            return await new Promise((resolve) => {
                nativeOnMessage.dispatch(
                    {
                        __sumi_ec_external_message: true,
                        payload: {
                            type: 'ping',
                            payload: { source: 'helper-test' }
                        },
                        sender: {
                            origin: 'https://example.com',
                            url: 'https://example.com/',
                            frameId: 0
                        },
                        targetRuntimeId: 'fixture.extension'
                    },
                    {
                        frameId: 7,
                        tab: { id: 42 },
                        url: 'https://ignored.example/internal'
                    },
                    function(response) {
                        nativeOnMessage.dispatch(
                            { type: 'internal' },
                            {},
                            function() {}
                        );
                        resolve({
                            externalResponse: response,
                            regularMessages: regularMessages
                        });
                    }
                );
            });
            """,
            contentWorld: .page
        )

        let result = try XCTUnwrap(rawResult as? [String: Any])
        let response = try XCTUnwrap(result["externalResponse"] as? [String: Any])
        let echo = try XCTUnwrap(response["echo"] as? [String: Any])
        let sender = try XCTUnwrap(response["sender"] as? [String: Any])
        let regularMessages = try XCTUnwrap(result["regularMessages"] as? [String])

        XCTAssertEqual(response["via"] as? String, "external")
        XCTAssertEqual(echo["type"] as? String, "ping")
        XCTAssertEqual(
            (echo["payload"] as? [String: Any])?["source"] as? String,
            "helper-test"
        )
        XCTAssertEqual(sender["origin"] as? String, "https://example.com")
        XCTAssertEqual(sender["url"] as? String, "https://example.com/")
        XCTAssertEqual((sender["tab"] as? [String: Any])?["id"] as? Int, 42)
        XCTAssertEqual(sender["frameId"] as? Int, 0)
        XCTAssertEqual(regularMessages, ["internal"])
    }

    func testBackgroundHelperDispatchesSumiPortToOnConnectExternal() async throws {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        try await loadHTMLString(
            "<!doctype html><html><head></head><body>background-helper-connect</body></html>",
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        let helperSource = ExtensionManager
            .debugExternallyConnectableBackgroundHelperScriptSource()
        let rawResult = try await webView.callAsyncJavaScript(
            """
            function makeEvent() {
                var listeners = [];
                return {
                    addListener: function(listener) {
                        listeners.push(listener);
                    },
                    removeListener: function(listener) {
                        listeners = listeners.filter(function(candidate) {
                            return candidate !== listener;
                        });
                    },
                    hasListener: function(listener) {
                        return listeners.indexOf(listener) !== -1;
                    },
                    hasListeners: function() {
                        return listeners.length > 0;
                    },
                    dispatch: function() {
                        var args = Array.prototype.slice.call(arguments);
                        listeners.slice().forEach(function(listener) {
                            listener.apply(null, args);
                        });
                    }
                };
            }

            window.browser = {
                runtime: {
                    id: 'fixture.extension',
                    onConnect: makeEvent(),
                    onConnectExternal: makeEvent(),
                    onMessage: makeEvent(),
                    onMessageExternal: makeEvent()
                }
            };
            window.chrome = { runtime: window.browser.runtime };

            var nativeOnConnect = window.browser.runtime.onConnect;

            \(helperSource)

            var internalPorts = [];
            window.browser.runtime.onConnect.addListener(function(port) {
                internalPorts.push(port && port.name ? port.name : '');
            });

            return await new Promise((resolve) => {
                var outboundMessages = [];
                var disconnectCount = 0;

                window.browser.runtime.onConnectExternal.addListener(function(port) {
                    port.postMessage({ from: 'external-listener' });
                    port.onMessage.addListener(function(message) {
                        resolve({
                            disconnectCount: disconnectCount,
                            internalPorts: internalPorts,
                            receivedMessage: message,
                            sender: port.sender,
                            sentMessages: outboundMessages,
                            syntheticName: port.name
                        });
                    });
                    port.onDisconnect.addListener(function() {
                        disconnectCount += 1;
                    });
                });

                var nativePort = {
                    name: '__sumi_ec_external_connect__:' + JSON.stringify({
                        name: 'fixture-port',
                        sender: {
                            origin: 'https://example.com',
                            url: 'https://example.com/',
                            frameId: 0
                        },
                        targetRuntimeId: 'fixture.extension'
                    }),
                    onDisconnect: makeEvent(),
                    onMessage: makeEvent(),
                    postMessage: function(message) {
                        outboundMessages.push(message);
                    },
                    disconnect: function() {
                        this.onDisconnect.dispatch();
                    },
                    sender: {
                        tab: { id: 42 },
                        url: 'https://ignored.example/internal'
                    }
                };

                nativeOnConnect.dispatch(nativePort);
                nativePort.onMessage.dispatch({ type: 'port-echo' });
            });
            """,
            contentWorld: .page
        )

        let result = try XCTUnwrap(rawResult as? [String: Any])
        let receivedMessage = try XCTUnwrap(result["receivedMessage"] as? [String: Any])
        let sender = try XCTUnwrap(result["sender"] as? [String: Any])
        let sentMessages = try XCTUnwrap(result["sentMessages"] as? [[String: Any]])
        let internalPorts = try XCTUnwrap(result["internalPorts"] as? [String])

        XCTAssertEqual(result["syntheticName"] as? String, "fixture-port")
        XCTAssertEqual(receivedMessage["type"] as? String, "port-echo")
        XCTAssertEqual(sender["origin"] as? String, "https://example.com")
        XCTAssertEqual(sender["url"] as? String, "https://example.com/")
        XCTAssertEqual((sender["tab"] as? [String: Any])?["id"] as? Int, 42)
        XCTAssertEqual(sentMessages.count, 1)
        XCTAssertEqual(sentMessages[0]["from"] as? String, "external-listener")
        XCTAssertTrue(internalPorts.isEmpty)
    }

    func testBackgroundHelperRepeatedInstallStaysIdempotent() async throws {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        try await loadHTMLString(
            "<!doctype html><html><head></head><body>background-helper-repeat</body></html>",
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        let helperSource = ExtensionManager
            .debugExternallyConnectableBackgroundHelperScriptSource()
        let rawResult = try await webView.callAsyncJavaScript(
            """
            function makeEvent() {
                var listeners = [];
                return {
                    addListener: function(listener) {
                        listeners.push(listener);
                    },
                    removeListener: function(listener) {
                        listeners = listeners.filter(function(candidate) {
                            return candidate !== listener;
                        });
                    },
                    hasListener: function(listener) {
                        return listeners.indexOf(listener) !== -1;
                    },
                    hasListeners: function() {
                        return listeners.length > 0;
                    },
                    dispatch: function() {
                        var args = Array.prototype.slice.call(arguments);
                        listeners.slice().forEach(function(listener) {
                            listener.apply(null, args);
                        });
                    }
                };
            }

            window.browser = {
                runtime: {
                    id: 'fixture.extension',
                    onConnect: makeEvent(),
                    onConnectExternal: makeEvent(),
                    onMessage: makeEvent(),
                    onMessageExternal: makeEvent()
                }
            };
            window.chrome = { runtime: window.browser.runtime };

            var nativeOnMessage = window.browser.runtime.onMessage;

            \(helperSource)
            \(helperSource)

            var externalDispatchCount = 0;
            window.browser.runtime.onMessageExternal.addListener(function(message, sender, sendResponse) {
                externalDispatchCount += 1;
                sendResponse({ ok: true, sender: sender });
                return true;
            });

            return await new Promise((resolve) => {
                nativeOnMessage.dispatch(
                    {
                        __sumi_ec_external_message: true,
                        payload: { type: 'ping' },
                        sender: {
                            origin: 'https://example.com',
                            url: 'https://example.com/',
                            frameId: 0
                        },
                        targetRuntimeId: 'fixture.extension'
                    },
                    { tab: { id: 9 } },
                    function(response) {
                        resolve({
                            externalDispatchCount: externalDispatchCount,
                            response: response
                        });
                    }
                );
            });
            """,
            contentWorld: .page
        )

        let result = try XCTUnwrap(rawResult as? [String: Any])
        let response = try XCTUnwrap(result["response"] as? [String: Any])

        XCTAssertEqual(result["externalDispatchCount"] as? Int, 1)
        XCTAssertEqual(response["ok"] as? Bool, true)
    }

    func testBackgroundHelperReusesInstalledEventsForAliasRuntimeObjects() async throws {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        try await loadHTMLString(
            "<!doctype html><html><head></head><body>background-helper-alias-runtime</body></html>",
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        let helperSource = ExtensionManager
            .debugExternallyConnectableBackgroundHelperScriptSource()
        let rawResult = try await webView.callAsyncJavaScript(
            """
            function makeEvent() {
                var listeners = [];
                return {
                    addListener: function(listener) {
                        listeners.push(listener);
                    },
                    removeListener: function(listener) {
                        listeners = listeners.filter(function(candidate) {
                            return candidate !== listener;
                        });
                    },
                    hasListener: function(listener) {
                        return listeners.indexOf(listener) !== -1;
                    },
                    hasListeners: function() {
                        return listeners.length > 0;
                    },
                    dispatch: function() {
                        var args = Array.prototype.slice.call(arguments);
                        listeners.slice().forEach(function(listener) {
                            listener.apply(null, args);
                        });
                    }
                };
            }

            var browserRuntime = {
                id: 'fixture.extension',
                onConnect: makeEvent(),
                onConnectExternal: makeEvent(),
                onMessage: makeEvent(),
                onMessageExternal: makeEvent()
            };
            var chromeRuntime = {
                id: 'fixture.extension',
                onConnect: makeEvent(),
                onConnectExternal: makeEvent(),
                onMessage: makeEvent(),
                onMessageExternal: makeEvent()
            };

            window.browser = { runtime: browserRuntime };
            window.chrome = { runtime: chromeRuntime };

            var nativeOnMessage = browserRuntime.onMessage;

            \(helperSource)

            var externalDispatchCount = 0;
            window.chrome.runtime.onMessageExternal.addListener(function(message, sender, sendResponse) {
                externalDispatchCount += 1;
                sendResponse({ ok: true, via: 'chrome.runtime' });
                return true;
            });

            return await new Promise((resolve) => {
                nativeOnMessage.dispatch(
                    {
                        __sumi_ec_external_message: true,
                        payload: { type: 'ping' },
                        sender: {
                            origin: 'https://example.com',
                            url: 'https://example.com/',
                            frameId: 0
                        },
                        targetRuntimeId: 'fixture.extension'
                    },
                    { tab: { id: 9 } },
                    function(response) {
                        resolve({
                            externalDispatchCount: externalDispatchCount,
                            response: response,
                            sharedExternalEvent: window.browser.runtime.onMessageExternal === window.chrome.runtime.onMessageExternal,
                            sharedMessageEvent: window.browser.runtime.onMessage === window.chrome.runtime.onMessage
                        });
                    }
                );
            });
            """,
            contentWorld: .page
        )

        let result = try XCTUnwrap(rawResult as? [String: Any])
        let response = try XCTUnwrap(result["response"] as? [String: Any])

        XCTAssertEqual(result["externalDispatchCount"] as? Int, 1)
        XCTAssertEqual(result["sharedExternalEvent"] as? Bool, true)
        XCTAssertEqual(result["sharedMessageEvent"] as? Bool, true)
        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertEqual(response["via"] as? String, "chrome.runtime")
    }

    func testBackgroundHelperInstallsIndependentlyForDistinctRuntimeIDs() async throws {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        try await loadHTMLString(
            "<!doctype html><html><head></head><body>background-helper-distinct-runtime</body></html>",
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        let helperSource = ExtensionManager
            .debugExternallyConnectableBackgroundHelperScriptSource()
        let rawResult = try await webView.callAsyncJavaScript(
            """
            function makeEvent() {
                var listeners = [];
                return {
                    addListener: function(listener) {
                        listeners.push(listener);
                    },
                    removeListener: function(listener) {
                        listeners = listeners.filter(function(candidate) {
                            return candidate !== listener;
                        });
                    },
                    hasListener: function(listener) {
                        return listeners.indexOf(listener) !== -1;
                    },
                    hasListeners: function() {
                        return listeners.length > 0;
                    },
                    dispatch: function() {
                        var args = Array.prototype.slice.call(arguments);
                        listeners.slice().forEach(function(listener) {
                            listener.apply(null, args);
                        });
                    }
                };
            }

            var browserRuntime = {
                id: 'fixture.browser',
                onConnect: makeEvent(),
                onConnectExternal: makeEvent(),
                onMessage: makeEvent(),
                onMessageExternal: makeEvent()
            };
            var chromeRuntime = {
                id: 'fixture.chrome',
                onConnect: makeEvent(),
                onConnectExternal: makeEvent(),
                onMessage: makeEvent(),
                onMessageExternal: makeEvent()
            };

            window.browser = { runtime: browserRuntime };
            window.chrome = { runtime: chromeRuntime };

            var nativeBrowserOnMessage = browserRuntime.onMessage;
            var nativeChromeOnMessage = chromeRuntime.onMessage;

            \(helperSource)

            var browserDispatchCount = 0;
            var chromeDispatchCount = 0;

            window.browser.runtime.onMessageExternal.addListener(function(message, sender, sendResponse) {
                browserDispatchCount += 1;
                sendResponse({ runtime: 'browser' });
                return true;
            });
            window.chrome.runtime.onMessageExternal.addListener(function(message, sender, sendResponse) {
                chromeDispatchCount += 1;
                sendResponse({ runtime: 'chrome' });
                return true;
            });

            return await new Promise((resolve) => {
                nativeBrowserOnMessage.dispatch(
                    {
                        __sumi_ec_external_message: true,
                        payload: { type: 'browser' },
                        sender: { origin: 'https://example.com', url: 'https://example.com/', frameId: 0 },
                        targetRuntimeId: 'fixture.browser'
                    },
                    {},
                    function(browserResponse) {
                        nativeChromeOnMessage.dispatch(
                            {
                                __sumi_ec_external_message: true,
                                payload: { type: 'chrome' },
                                sender: { origin: 'https://example.com', url: 'https://example.com/', frameId: 0 },
                                targetRuntimeId: 'fixture.chrome'
                            },
                            {},
                            function(chromeResponse) {
                                resolve({
                                    browserDispatchCount: browserDispatchCount,
                                    chromeDispatchCount: chromeDispatchCount,
                                    browserResponse: browserResponse,
                                    chromeResponse: chromeResponse,
                                    sharedExternalEvent: window.browser.runtime.onMessageExternal === window.chrome.runtime.onMessageExternal
                                });
                            }
                        );
                    }
                );
            });
            """,
            contentWorld: .page
        )

        let result = try XCTUnwrap(rawResult as? [String: Any])
        let browserResponse = try XCTUnwrap(result["browserResponse"] as? [String: Any])
        let chromeResponse = try XCTUnwrap(result["chromeResponse"] as? [String: Any])

        XCTAssertEqual(result["browserDispatchCount"] as? Int, 1)
        XCTAssertEqual(result["chromeDispatchCount"] as? Int, 1)
        XCTAssertEqual(browserResponse["runtime"] as? String, "browser")
        XCTAssertEqual(chromeResponse["runtime"] as? String, "chrome")
        XCTAssertEqual(result["sharedExternalEvent"] as? Bool, false)
    }

    func testBackgroundHelperFallsBackToObjectIdentityWithoutRuntimeID() async throws {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        try await loadHTMLString(
            "<!doctype html><html><head></head><body>background-helper-object-fallback</body></html>",
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        let helperSource = ExtensionManager
            .debugExternallyConnectableBackgroundHelperScriptSource()
        let rawResult = try await webView.callAsyncJavaScript(
            """
            function makeEvent() {
                var listeners = [];
                return {
                    addListener: function(listener) {
                        listeners.push(listener);
                    },
                    removeListener: function(listener) {
                        listeners = listeners.filter(function(candidate) {
                            return candidate !== listener;
                        });
                    },
                    hasListener: function(listener) {
                        return listeners.indexOf(listener) !== -1;
                    },
                    hasListeners: function() {
                        return listeners.length > 0;
                    },
                    dispatch: function() {
                        var args = Array.prototype.slice.call(arguments);
                        listeners.slice().forEach(function(listener) {
                            listener.apply(null, args);
                        });
                    }
                };
            }

            window.browser = {
                runtime: {
                    onConnect: makeEvent(),
                    onConnectExternal: makeEvent(),
                    onMessage: makeEvent(),
                    onMessageExternal: makeEvent()
                }
            };
            window.chrome = { runtime: window.browser.runtime };

            var nativeOnMessage = window.browser.runtime.onMessage;

            \(helperSource)
            \(helperSource)

            var externalDispatchCount = 0;
            window.browser.runtime.onMessageExternal.addListener(function(message, sender, sendResponse) {
                externalDispatchCount += 1;
                sendResponse({ ok: true });
                return true;
            });

            return await new Promise((resolve) => {
                nativeOnMessage.dispatch(
                    {
                        __sumi_ec_external_message: true,
                        payload: { type: 'ping' },
                        sender: {
                            origin: 'https://example.com',
                            url: 'https://example.com/',
                            frameId: 0
                        }
                    },
                    {},
                    function(response) {
                        resolve({
                            externalDispatchCount: externalDispatchCount,
                            response: response
                        });
                    }
                );
            });
            """,
            contentWorld: .page
        )

        let result = try XCTUnwrap(rawResult as? [String: Any])
        let response = try XCTUnwrap(result["response"] as? [String: Any])

        XCTAssertEqual(result["externalDispatchCount"] as? Int, 1)
        XCTAssertEqual(response["ok"] as? Bool, true)
    }

    func testRelayScriptRepeatedInstallSuppressesDuplicateConnectOpenDelivery() async throws {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        try await loadHTMLString(
            "<!doctype html><html><head></head><body>relay-repeat</body></html>",
            baseURL: URL(string: "https://example.com/")!,
            in: webView
        )

        let relaySource = ExtensionManager.debugExternallyConnectableBridgeScriptSource()
        let rawResult = try await webView.callAsyncJavaScript(
            """
            function makeEvent() {
                var listeners = [];
                return {
                    addListener: function(listener) {
                        listeners.push(listener);
                    },
                    removeListener: function(listener) {
                        listeners = listeners.filter(function(candidate) {
                            return candidate !== listener;
                        });
                    },
                    dispatch: function() {
                        var args = Array.prototype.slice.call(arguments);
                        listeners.slice().forEach(function(listener) {
                            listener.apply(null, args);
                        });
                    }
                };
            }

            var connectCallCount = 0;
            var openedEventCount = 0;

            window.browser = {
                runtime: {
                    id: 'fixture.extension',
                    connect: function(info) {
                        connectCallCount += 1;
                        return {
                            name: info && info.name ? info.name : '',
                            onMessage: makeEvent(),
                            onDisconnect: makeEvent(),
                            postMessage: function() {},
                            disconnect: function() {}
                        };
                    }
                }
            };
            window.chrome = { runtime: window.browser.runtime };

            window.addEventListener('message', function(event) {
                if (event.source !== window) return;
                if (!event.data || event.data.type !== 'sumi_ec_connect_opened') return;
                openedEventCount += 1;
            });

            \(relaySource)
            \(relaySource)

            window.postMessage({
                type: 'sumi_ec_connect_open',
                targetRuntimeId: 'fixture.extension',
                extensionId: 'fixture.extension',
                connectInfo: { name: 'fixture-port' },
                portId: 'port-repeat'
            }, '*');

            return await new Promise((resolve) => {
                setTimeout(function() {
                    resolve({
                        connectCallCount: connectCallCount,
                        openedEventCount: openedEventCount
                    });
                }, 20);
            });
            """,
            contentWorld: .page
        )

        let result = try XCTUnwrap(rawResult as? [String: Any])
        XCTAssertEqual(result["connectCallCount"] as? Int, 1)
        XCTAssertEqual(result["openedEventCount"] as? Int, 1)
    }

    func testExternallyConnectablePolicyKeepsOnlyValidMatchPatterns() {
        let manifest: [String: Any] = [
            "externally_connectable": [
                "matches": [
                    "https://accounts.example.com/*",
                    "notaurl",
                    "<all_urls>",
                ]
            ]
        ]

        let policy = ExtensionManager.externallyConnectablePolicy(
            from: manifest,
            extensionId: "policy.test"
        )

        XCTAssertNotNil(policy)
        XCTAssertEqual(policy?.matchPatterns.count, 1)
        XCTAssertEqual(
            policy?.matchPatternStrings,
            ["https://accounts.example.com/*", "notaurl", "<all_urls>"]
        )
        XCTAssertEqual(policy?.normalizedHostnames, ["accounts.example.com"])
    }

    func testPageBridgeReconciliationIsIdempotentAndRemovesStaleScripts() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Bridge Runtime",
            "version": "1.0",
            "externally_connectable": [
                "matches": ["https://accounts.example.com/*"]
            ],
        ]
        let extensionRoot = try makeUnpackedExtensionDirectory(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let record = makeInstalledExtensionRecord(
            id: "bridge.runtime",
            packagePath: extensionRoot.path,
            sourceBundlePath: extensionRoot.path,
            manifest: manifest,
            isEnabled: true
        )

        manager.debugReplaceInstalledExtensions([record])
        manager.debugSetupExternallyConnectablePageBridge(
            extensionId: record.id,
            packagePath: extensionRoot.path
        )

        var snapshot = manager.debugRuntimeStateSnapshot
        XCTAssertEqual(snapshot.installedPageBridgeIDs, [record.id])
        XCTAssertEqual(snapshot.managedPageBridgeScriptCount, 1)

        manager.debugSetupExternallyConnectablePageBridge(
            extensionId: record.id,
            packagePath: extensionRoot.path
        )
        snapshot = manager.debugRuntimeStateSnapshot
        XCTAssertEqual(snapshot.installedPageBridgeIDs, [record.id])
        XCTAssertEqual(snapshot.managedPageBridgeScriptCount, 1)

        let strippedManifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Bridge Runtime",
            "version": "1.0",
        ]
        let strippedManifestData = try JSONSerialization.data(
            withJSONObject: strippedManifest,
            options: [.sortedKeys]
        )
        try strippedManifestData.write(
            to: extensionRoot.appendingPathComponent("manifest.json")
        )

        manager.debugSetupExternallyConnectablePageBridge(
            extensionId: record.id,
            packagePath: extensionRoot.path
        )
        snapshot = manager.debugRuntimeStateSnapshot
        XCTAssertTrue(snapshot.installedPageBridgeIDs.isEmpty)
        XCTAssertEqual(snapshot.managedPageBridgeScriptCount, 0)
    }

    func testPageBridgeReconciliationInstallsReadinessAwareBridgeShim() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Readiness Bridge",
            "version": "1.0",
            "externally_connectable": [
                "matches": ["https://accounts.example.com/*"]
            ],
        ]
        let extensionRoot = try makeUnpackedExtensionDirectory(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        manager.debugSetupExternallyConnectablePageBridge(
            extensionId: "bridge.readiness",
            packagePath: extensionRoot.path
        )

        let bridgeSources = harness.browserConfiguration
            .webViewConfiguration
            .userContentController
            .userScripts
            .filter { ExtensionManager.isManagedExternallyConnectablePageBridgeScript($0) }
            .map(\.source)

        XCTAssertEqual(bridgeSources.count, 1)

        let source = bridgeSources[0]
        XCTAssertFalse(source.isEmpty)
        XCTAssertTrue(source.contains("__sumiEcShimInstalledRuntimeIds"))
        XCTAssertTrue(source.contains("__sumiEcWrappedSendMessage"))
        XCTAssertTrue(source.contains("__sumiEcWrappedConnect"))
        XCTAssertTrue(source.contains("sumi_ec_port_"))

        let oldMessagePrefix = "no" + "ok_ec"
        let oldGlobalPrefix = "__" + "nookEc"
        let oldLogPrefix = "NOOK" + "-EC"
        XCTAssertFalse(source.contains(oldMessagePrefix))
        XCTAssertFalse(source.contains(oldGlobalPrefix))
        XCTAssertFalse(source.contains(oldLogPrefix))
    }

    func testPageBridgeRuntimeScopedRegistryAllowsDistinctRuntimeIDs() async throws {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        try await loadHTMLString(
            "<!doctype html><html><head></head><body>page-bridge-runtime-scope</body></html>",
            baseURL: URL(string: "https://accounts.example.com/")!,
            in: webView
        )

        let shimOne = ExtensionManager.debugExternallyConnectablePageBridgeScriptSource(
            configuredRuntimeId: "bridge.one",
            bridgeMarker: "/* debug one */"
        )
        let shimTwo = ExtensionManager.debugExternallyConnectablePageBridgeScriptSource(
            configuredRuntimeId: "bridge.two",
            bridgeMarker: "/* debug two */"
        )

        let rawResult = try await webView.callAsyncJavaScript(
            """
            window.browser = {
                runtime: {
                    id: 'fixture.runtime',
                    sendMessage: function() { return Promise.resolve(null); },
                    connect: function() {
                        return {
                            name: '',
                            onMessage: { addListener: function() {}, removeListener: function() {}, hasListener: function() { return false; } },
                            onDisconnect: { addListener: function() {}, removeListener: function() {}, hasListener: function() { return false; } },
                            postMessage: function() {},
                            disconnect: function() {}
                        };
                    }
                }
            };
            window.chrome = { runtime: window.browser.runtime };

            \(shimOne)
            \(shimTwo)

            var registry = window.__sumiEcShimInstalledRuntimeIds || {};
            return {
                keys: Object.keys(registry).sort(),
                bridgeOneInstalled: !!registry['runtime:bridge.one'],
                bridgeTwoInstalled: !!registry['runtime:bridge.two']
            };
            """,
            contentWorld: .page
        )

        let result = try XCTUnwrap(rawResult as? [String: Any])
        let keys = try XCTUnwrap(result["keys"] as? [String])

        XCTAssertEqual(keys, ["runtime:bridge.one", "runtime:bridge.two"])
        XCTAssertEqual(result["bridgeOneInstalled"] as? Bool, true)
        XCTAssertEqual(result["bridgeTwoInstalled"] as? Bool, true)
    }

    func testDebugRuntimeStateSnapshotIncludesExternallyConnectableState() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let webView = WKWebView(
            frame: .zero,
            configuration: harness.browserConfiguration.auxiliaryWebViewConfiguration(
                surface: .miniWindow
            )
        )
        let pageURL = try XCTUnwrap(URL(string: "https://accounts.example.com/index.html"))
        let requestID = UUID()

        manager.externallyConnectablePolicies["fixture.extension"] = ExternallyConnectablePolicy(
            extensionId: "fixture.extension",
            matchPatternStrings: ["https://accounts.example.com/*"],
            matchPatterns: [
                try XCTUnwrap(
                    WKWebExtension.MatchPattern(
                        string: "https://accounts.example.com/*"
                    )
                )
            ]
        )
        manager.ecRegistry.setTrackedPageURL(pageURL.absoluteString, for: webView)
        manager.ecRegistry.addRequest(
            PendingExternallyConnectableNativeRequest(
                id: requestID,
                extensionId: "fixture.extension",
                webViewIdentifier: ObjectIdentifier(webView)
            ) { _, _ in }
        )

        let snapshot = manager.debugRuntimeStateSnapshot

        XCTAssertEqual(snapshot.externallyConnectablePolicyIDs, ["fixture.extension"])
        XCTAssertTrue(manager.ecRegistry.hasTrackedState(for: webView))
        XCTAssertEqual(snapshot.pendingExternallyConnectableNativeRequestCount, 1)
        XCTAssertTrue(snapshot.externallyConnectableNativePortIDs.isEmpty)
    }

    func testExternallyConnectableBridgeScriptIncludesVersionedSenderRelay() {
        let source = ExtensionManager.debugExternallyConnectableBridgeScriptSource()

        XCTAssertTrue(source.contains("[SUMI-EC]"))
        XCTAssertTrue(source.contains("sumi_ec_connect_open"))
        XCTAssertTrue(source.contains("externalConnectNamePrefix"))
        XCTAssertTrue(source.contains("sender: data.sender || null"))
        XCTAssertTrue(source.contains("targetRuntimeId: data.targetRuntimeId || currentRuntimeId()"))
        XCTAssertTrue(source.contains("runtime.connect unavailable"))

        let oldMessagePrefix = "no" + "ok_ec"
        let oldGlobalPrefix = "__" + "nookEc"
        let oldLogPrefix = "NOOK" + "-EC"
        XCTAssertFalse(source.contains(oldMessagePrefix))
        XCTAssertFalse(source.contains(oldGlobalPrefix))
        XCTAssertFalse(source.contains(oldLogPrefix))
    }

    func testPatchManifestDoesNotInjectLegacyIframeBridgeForPasswordManagers() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Bitwarden Password Manager",
            "version": "1.0",
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestURL)

        manager.patchManifestForWebKit(at: manifestURL)
        manager.patchManifestForWebKit(at: manifestURL)

        let patched = try ExtensionUtils.validateManifest(at: manifestURL)
        let contentScripts = patched["content_scripts"] as? [[String: Any]] ?? []
        let iframeBridgeEntries = contentScripts.filter {
            (($0["js"] as? [String]) ?? []).contains("sumi_iframe_bridge.js")
        }

        XCTAssertEqual(iframeBridgeEntries.count, 0)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: rootURL.appendingPathComponent("sumi_iframe_bridge.js").path
            )
        )
    }

    func testExtensionRuntimeConfigurationStartsWithoutManagedPageBridges() throws {
        let harness = try makeExtensionRuntimeHarness()
        _ = makeExtensionManager(in: harness)

        let managedScripts = harness.browserConfiguration
            .webViewConfiguration
            .userContentController
            .userScripts
            .filter { ExtensionManager.isManagedExternallyConnectablePageBridgeScript($0) }

        XCTAssertEqual(managedScripts.count, 0)
        XCTAssertTrue(
            harness.browserConfiguration
                .webViewConfiguration
                .defaultWebpagePreferences
                .allowsContentJavaScript
        )
    }

    func testNormalTabUserScriptsInstallExternallyConnectableBrokerWhenPoliciesExist() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Allowed Origin Bridge",
            "version": "1.0",
            "externally_connectable": [
                "matches": ["https://accounts.example.com/*"]
            ],
        ]
        let extensionRoot = try makeUnpackedExtensionDirectory(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let record = makeInstalledExtensionRecord(
            id: "bridge.allowed",
            packagePath: extensionRoot.path,
            sourceBundlePath: extensionRoot.path,
            manifest: manifest,
            isEnabled: true
        )

        manager.debugReplaceInstalledExtensions([record])
        manager.debugSetupExternallyConnectablePageBridge(
            extensionId: record.id,
            packagePath: extensionRoot.path
        )

        let scripts = manager.normalTabUserScripts()
        XCTAssertEqual(scripts.count, 1)

        let provider = SumiNormalTabUserScripts(managedUserScripts: scripts)
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: provider
        )
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let allowedURL = try XCTUnwrap(
            URL(string: "https://accounts.example.com/index.html")
        )

        await controller.awaitContentBlockingAssetsInstalled()
        try await loadHTMLString(
            "<html><body>allowed</body></html>",
            baseURL: allowedURL,
            in: webView
        )

        let rawResult = try await webView.callAsyncJavaScript(
            """
            return {
                hasNativeHandler: !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.sumiExternallyConnectableRuntime)
            };
            """,
            contentWorld: .page
        )
        let result = try XCTUnwrap(rawResult as? [String: Any])

        XCTAssertEqual(result["hasNativeHandler"] as? Bool, true)
    }

    func testNormalTabUserScriptsSkipExternallyConnectableBrokerWithoutPolicy() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let scripts = manager.normalTabUserScripts()
        XCTAssertTrue(scripts.isEmpty)

        let provider = SumiNormalTabUserScripts(managedUserScripts: scripts)
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: provider
        )
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let pageURL = try XCTUnwrap(
            URL(string: "https://accounts.example.com/index.html")
        )

        await controller.awaitContentBlockingAssetsInstalled()
        try await loadHTMLString(
            "<html><body>no-policy</body></html>",
            baseURL: pageURL,
            in: webView
        )

        let rawResult = try await webView.callAsyncJavaScript(
            """
            return {
                hasNativeHandler: !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.sumiExternallyConnectableRuntime)
            };
            """,
            contentWorld: .page
        )
        let result = try XCTUnwrap(rawResult as? [String: Any])

        XCTAssertEqual(result["hasNativeHandler"] as? Bool, false)
    }

    func testPageBridgeNativeSendMessagePromiseReturnsResponsePayload() async throws {
        let (webView, nativeHandler) = try await makeExternallyConnectableShimWebView {
            payload in
            (
                [
                    "ok": true,
                    "echo": payload["message"] ?? NSNull(),
                ],
                nil
            )
        }
        let shimSource = ExtensionManager.debugExternallyConnectablePageBridgeScriptSource(
            allowedHosts: []
        )

        let rawResult = try await webView.callAsyncJavaScript(
            """
            \(shimSource)
            return await window.browser.runtime.sendMessage({
                type: 'ping',
                payload: { source: 'promise-test' }
            });
            """,
            contentWorld: .page
        )
        let result = try XCTUnwrap(rawResult as? [String: Any])
        let echo = try XCTUnwrap(result["echo"] as? [String: Any])

        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(echo["type"] as? String, "ping")
        XCTAssertEqual(
            (echo["payload"] as? [String: Any])?["source"] as? String,
            "promise-test"
        )
        XCTAssertEqual(nativeHandler.receivedPayloads.count, 1)
        let firstPayload = nativeHandler.receivedPayloads[0]
        XCTAssertEqual(firstPayload["featureName"] as? String, "runtime")
        XCTAssertEqual(firstPayload["method"] as? String, "sendMessage")
        XCTAssertEqual(
            (firstPayload["params"] as? [String: Any])?["extensionId"] as? String,
            "debug.extension"
        )
    }

    func testPageBridgeChromeCallbackReceivesLastErrorAndClearsItAsync() async throws {
        let (webView, _) = try await makeExternallyConnectableShimWebView { _ in
            (nil, "Rejected by native fixture")
        }
        let shimSource = ExtensionManager.debugExternallyConnectablePageBridgeScriptSource(
            allowedHosts: []
        )

        let rawResult = try await webView.callAsyncJavaScript(
            """
            \(shimSource)
            return await new Promise((resolve) => {
                window.chrome.runtime.sendMessage({ type: 'ping' }, function(response) {
                    resolve({
                        callbackResponseType: typeof response,
                        lastErrorMessage: window.chrome.runtime.lastError ? window.chrome.runtime.lastError.message : null
                    });
                });
            });
            """,
            contentWorld: .page
        )
        let result = try XCTUnwrap(rawResult as? [String: Any])

        XCTAssertEqual(result["callbackResponseType"] as? String, "undefined")
        XCTAssertEqual(
            result["lastErrorMessage"] as? String,
            "Rejected by native fixture"
        )

        let rawCleared = try await webView.callAsyncJavaScript(
            """
            \(shimSource)
            await new Promise((resolve) => {
                window.chrome.runtime.sendMessage({ type: 'ping' }, function() {
                    setTimeout(resolve, 20);
                });
            });
            return window.chrome.runtime.lastError == null;
            """,
            contentWorld: .page
        )
        XCTAssertEqual(rawCleared as? Bool, true)
    }

    func testPageBridgeNativeConnectQueuesMessagesUntilOpenedAndReceivesEcho() async throws {
        let (webView, nativeHandler) = try await makeExternallyConnectableNativeConnectShimWebView()
        let shimSource = ExtensionManager.debugExternallyConnectablePageBridgeScriptSource(
            allowedHosts: []
        )

        let rawResult = try await webView.callAsyncJavaScript(
            """
            \(shimSource)
            return await new Promise((resolve) => {
                var pageSideOpenEventCount = 0;
                var originalPostMessage = window.postMessage.bind(window);
                window.postMessage = function(message, targetOrigin) {
                    if (message && message.type === 'sumi_ec_connect_open') {
                        pageSideOpenEventCount += 1;
                    }
                    return originalPostMessage(message, targetOrigin);
                };
                var port = window.browser.runtime.connect({ name: 'fixture-port' });
                var received = [];
                port.onMessage.addListener(function(message) {
                    received.push(message);
                    resolve({
                        pageSideOpenEventCount: pageSideOpenEventCount,
                        received: received,
                        portName: port.name
                    });
                });
                port.postMessage({ type: 'ping', payload: { source: 'connect-test' } });
            });
            """,
            contentWorld: .page
        )

        let result = try XCTUnwrap(rawResult as? [String: Any])
        let received = try XCTUnwrap(result["received"] as? [[String: Any]])

        XCTAssertEqual(result["portName"] as? String, "fixture-port")
        XCTAssertEqual(result["pageSideOpenEventCount"] as? Int, 0)
        XCTAssertEqual(nativeHandler.openPayloads.count, 1)
        XCTAssertEqual(nativeHandler.postPayloads.count, 1)
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received[0]["type"] as? String, "port-echo")
        let echo = try XCTUnwrap(received[0]["echo"] as? [String: Any])
        XCTAssertEqual(echo["type"] as? String, "ping")
    }

    func testPageBridgeNativeConnectDisconnectMakesPortThrowOnPost() async throws {
        let (webView, nativeHandler) = try await makeExternallyConnectableNativeConnectShimWebView()
        let shimSource = ExtensionManager.debugExternallyConnectablePageBridgeScriptSource(
            allowedHosts: []
        )

        let rawResult = try await webView.callAsyncJavaScript(
            """
            \(shimSource)
            return await new Promise((resolve) => {
                var port = window.browser.runtime.connect({ name: 'fixture-port' });
                setTimeout(function() {
                    port.disconnect();
                    try {
                        port.postMessage({ type: 'after-disconnect' });
                        resolve({ errorMessage: null });
                    } catch (error) {
                        resolve({ errorMessage: error.message || String(error) });
                    }
                }, 20);
            });
            """,
            contentWorld: .page
        )

        let result = try XCTUnwrap(rawResult as? [String: Any])
        XCTAssertEqual(result["errorMessage"] as? String, "Port is disconnected")
        XCTAssertEqual(nativeHandler.disconnectPayloads.count, 1)
    }

    func testPageBridgeNativeConnectOpenFailureSurfacesAsyncDisconnectAndLastError() async throws {
        let (webView, nativeHandler) = try await makeExternallyConnectableNativeConnectShimWebView()
        nativeHandler.openErrorMessage = "Rejected by native connect fixture"
        let shimSource = ExtensionManager.debugExternallyConnectablePageBridgeScriptSource(
            allowedHosts: []
        )

        let rawResult = try await webView.callAsyncJavaScript(
            """
            \(shimSource)
            return await new Promise((resolve) => {
                var port = window.chrome.runtime.connect({ name: 'fixture-port' });
                port.onDisconnect.addListener(function() {
                    resolve({
                        lastErrorMessage: window.chrome.runtime.lastError ? window.chrome.runtime.lastError.message : null
                    });
                });
            });
            """,
            contentWorld: .page
        )

        let result = try XCTUnwrap(rawResult as? [String: Any])
        XCTAssertEqual(
            result["lastErrorMessage"] as? String,
            "Rejected by native connect fixture"
        )
    }

    func testNativeSendMessageValidationRejectsWrongOrigin() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionId = "bridge.allowed"
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Allowed Origin Bridge",
            "version": "1.0",
            "externally_connectable": [
                "matches": ["https://accounts.example.com/*"]
            ],
        ]
        let extensionRoot = try makeUnpackedExtensionDirectory(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let policy = try XCTUnwrap(
            ExtensionManager.externallyConnectablePolicy(
                from: manifest,
                extensionId: extensionId
            )
        )
        manager.externallyConnectablePolicies[extensionId] = policy

        let record = makeInstalledExtensionRecord(
            id: extensionId,
            packagePath: extensionRoot.path,
            sourceBundlePath: extensionRoot.path,
            manifest: manifest,
            isEnabled: true
        )
        manager.debugReplaceInstalledExtensions([record])

        let extensionContext = try await makeExtensionContext(at: extensionRoot)
        manager.configureContextIdentity(extensionContext, extensionId: extensionId)
        manager.extensionContexts[extensionId] = extensionContext

        let webView = WKWebView(
            frame: .zero,
            configuration: harness.browserConfiguration.auxiliaryWebViewConfiguration(
                surface: .miniWindow
            )
        )
        let blockedURL = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=123"))
        manager.updateExternallyConnectableNavigationLifecycle(
            for: webView,
            currentURL: blockedURL
        )

        let validation = manager.validateExternallyConnectableNativeSendMessageTarget(
            extensionId: extensionId,
            webView: webView,
            isMainFrame: true,
            sourceURL: blockedURL,
            sourceOrigin: "https://www.youtube.com"
        )

        XCTAssertNil(validation)
    }

    func testNativeConnectValidationRejectsWrongOrigin() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionId = "bridge.connect.allowed"
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Allowed Origin Bridge",
            "version": "1.0",
            "externally_connectable": [
                "matches": ["https://accounts.example.com/*"]
            ],
        ]

        let extensionRoot = try makeUnpackedExtensionDirectory(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let policy = try XCTUnwrap(
            ExtensionManager.externallyConnectablePolicy(
                from: manifest,
                extensionId: extensionId
            )
        )
        manager.externallyConnectablePolicies[extensionId] = policy
        manager.debugReplaceInstalledExtensions([
            makeInstalledExtensionRecord(
                id: extensionId,
                packagePath: extensionRoot.path,
                sourceBundlePath: extensionRoot.path,
                manifest: manifest,
                isEnabled: true
            )
        ])
        manager.extensionContexts[extensionId] = try await makeExtensionContext(
            at: extensionRoot
        )

        let webView = WKWebView(
            frame: .zero,
            configuration: harness.browserConfiguration.auxiliaryWebViewConfiguration(
                surface: .miniWindow
            )
        )
        let blockedURL = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=123"))
        manager.updateExternallyConnectableNavigationLifecycle(
            for: webView,
            currentURL: blockedURL
        )

        let validation = manager.validateExternallyConnectableNativeConnectOpenTarget(
            extensionId: extensionId,
            webView: webView,
            isMainFrame: true,
            sourceURL: blockedURL,
            sourceOrigin: "https://www.youtube.com"
        )

        XCTAssertNil(validation)
    }

    func testNativeSendMessageValidationRejectsDisabledOrUnloadedExtension() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionId = "bridge.stateful"
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "State Validation Bridge",
            "version": "1.0",
            "externally_connectable": [
                "matches": ["https://accounts.example.com/*"]
            ],
        ]
        let extensionRoot = try makeUnpackedExtensionDirectory(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let policy = try XCTUnwrap(
            ExtensionManager.externallyConnectablePolicy(
                from: manifest,
                extensionId: extensionId
            )
        )
        manager.externallyConnectablePolicies[extensionId] = policy

        let allowedURL = try XCTUnwrap(
            URL(string: "https://accounts.example.com/index.html")
        )
        let webView = WKWebView(
            frame: .zero,
            configuration: harness.browserConfiguration.auxiliaryWebViewConfiguration(
                surface: .miniWindow
            )
        )
        manager.updateExternallyConnectableNavigationLifecycle(
            for: webView,
            currentURL: allowedURL
        )

        let disabledRecord = makeInstalledExtensionRecord(
            id: extensionId,
            packagePath: extensionRoot.path,
            sourceBundlePath: extensionRoot.path,
            manifest: manifest,
            isEnabled: false
        )
        manager.debugReplaceInstalledExtensions([disabledRecord])

        XCTAssertNil(
            manager.validateExternallyConnectableNativeSendMessageTarget(
                extensionId: extensionId,
                webView: webView,
                isMainFrame: true,
                sourceURL: allowedURL,
                sourceOrigin: "https://accounts.example.com"
            )
        )

        let enabledRecord = makeInstalledExtensionRecord(
            id: extensionId,
            packagePath: extensionRoot.path,
            sourceBundlePath: extensionRoot.path,
            manifest: manifest,
            isEnabled: true
        )
        manager.debugReplaceInstalledExtensions([enabledRecord])
        manager.extensionContexts.removeValue(forKey: extensionId)

        XCTAssertNil(
            manager.validateExternallyConnectableNativeSendMessageTarget(
                extensionId: extensionId,
                webView: webView,
                isMainFrame: true,
                sourceURL: allowedURL,
                sourceOrigin: "https://accounts.example.com"
            )
        )
    }

    func testNavigationLifecycleCancelsPendingNativeSendMessageRequests() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let webView = WKWebView(
            frame: .zero,
            configuration: harness.browserConfiguration.auxiliaryWebViewConfiguration(
                surface: .miniWindow
            )
        )
        let originalURL = try XCTUnwrap(
            URL(string: "https://accounts.example.com/original")
        )
        let nextURL = try XCTUnwrap(
            URL(string: "https://accounts.example.com/next")
        )
        let webViewID = ObjectIdentifier(webView)
        var resolvedReply: Any?
        var resolvedError: String?

        manager.updateExternallyConnectableNavigationLifecycle(
            for: webView,
            currentURL: originalURL
        )

        let requestID = UUID()
        manager.ecRegistry.addRequest(
            PendingExternallyConnectableNativeRequest(
                id: requestID,
                extensionId: "bridge.pending",
                webViewIdentifier: webViewID
            ) { reply, errorMessage in
                resolvedReply = reply
                resolvedError = errorMessage
            }
        )

        manager.updateExternallyConnectableNavigationLifecycle(
            for: webView,
            currentURL: nextURL
        )

        XCTAssertNil(resolvedReply)
        XCTAssertEqual(
            resolvedError,
            "Extension request canceled due to navigation"
        )
        XCTAssertTrue(manager.ecRegistry.allRequestIDs.isEmpty)
    }

    func testPrepareWebViewForExtensionRuntimePreservesExistingScriptsAndAttachesController() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: "window.__fixturePageScript = true;",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: "window.__fixtureDefaultClientScript = true;",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .defaultClient
            )
        )
        let webView = WKWebView(frame: .zero, configuration: configuration)

        manager.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: URL(string: "webkit-extension://fixture/popup.html")
        )
        manager.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: URL(string: "webkit-extension://fixture/popup.html")
        )

        XCTAssertTrue(
            webView.configuration.defaultWebpagePreferences.allowsContentJavaScript
        )
    }

    func testPrepareExtensionContextForRuntimeUsesContextConfigurationWhenAvailable() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 2,
                "name": "Background Bootstrap",
                "description": "Fixture",
                "version": "1.0",
                "background": [
                    "scripts": ["background.js"],
                ],
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        try "console.log('background');".write(
            to: extensionRoot.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        let controller = try requireRuntimeController(for: manager)

        manager.debugPrepareExtensionContextForRuntime(
            extensionContext,
            extensionId: "debug.background-bootstrap"
        )

        if let configuration = extensionContext.webViewConfiguration {
            XCTAssertTrue(
                configuration.defaultWebpagePreferences.allowsContentJavaScript
            )
            XCTAssertTrue(configuration.webExtensionController === controller)
        } else {
            XCTAssertTrue(
                harness.browserConfiguration
                    .webViewConfiguration
                    .defaultWebpagePreferences
                    .allowsContentJavaScript
            )
            XCTAssertTrue(
                harness.browserConfiguration
                    .webViewConfiguration
                    .webExtensionController === controller
            )
        }
    }

    func testExtensionTabAdapterImplementsWindowSelectorExpectedByWebKit() {
        XCTAssertTrue(
            ExtensionTabAdapter.instancesRespond(
                to: NSSelectorFromString("windowForWebExtensionContext:")
            )
        )
    }

    func testExtensionTabAdapterImplementsPermissionGestureSelectorExpectedByWebKit() {
        XCTAssertTrue(
            ExtensionTabAdapter.instancesRespond(
                to: NSSelectorFromString(
                    "shouldGrantPermissionsOnUserGestureForWebExtensionContext:"
                )
            )
        )
    }

    func testDeclaredHostPatternAlreadyGrantsSpecificURLAccess() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let extensionRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let manifestURL = extensionRoot.appendingPathComponent("manifest.json")
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Host Access",
            "description": "Host access fixture",
            "version": "1.0",
            "permissions": [
                "storage",
                "https://sponsor.ajay.app/*",
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestURL)

        manager.patchManifestForWebKit(at: manifestURL)

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        manager.debugGrantDeclaredPermissions(
            to: extensionContext,
            webExtension: webExtension
        )

        let sponsorAPIURL = try XCTUnwrap(
            URL(string: "https://sponsor.ajay.app/api/skipSegments/abcde")
        )

        XCTAssertEqual(
            extensionContext.permissionStatus(for: sponsorAPIURL),
            .grantedExplicitly
        )
    }

    func testCoveredHostPatternCanAutoGrantSpecificURLAccess() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let extensionRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let manifestURL = extensionRoot.appendingPathComponent("manifest.json")
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Host Access",
            "description": "Host access fixture",
            "version": "1.0",
            "permissions": [
                "storage",
                "https://sponsor.ajay.app/*",
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestURL)

        manager.patchManifestForWebKit(at: manifestURL)

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        manager.debugGrantDeclaredPermissions(
            to: extensionContext,
            webExtension: webExtension
        )

        let sponsorAPIURL = try XCTUnwrap(
            URL(string: "https://sponsor.ajay.app/api/skipSegments/abcde")
        )

        let autoGranted = manager.debugAutoGrantCoveredURLs(
            [sponsorAPIURL],
            for: extensionContext
        )

        XCTAssertEqual(autoGranted, [sponsorAPIURL])
        XCTAssertEqual(
            extensionContext.permissionStatus(for: sponsorAPIURL),
            .grantedExplicitly
        )
    }

    func testPermissionPromptDelegateSilentlyReturnsOnlyAlreadyGrantedPermissions() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let browserManager = BrowserManager()
        manager.debugAttachBrowserManager(browserManager)

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Silent Permission",
            "version": "1.0",
            "permissions": ["storage", "tabs"],
        ]
        let extensionRoot = try makeUnpackedExtensionDirectory(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        let storagePermission = try XCTUnwrap(
            webExtension.requestedPermissions.first { $0.rawValue == "storage" }
        )
        let tabsPermission = try XCTUnwrap(
            webExtension.requestedPermissions.first { $0.rawValue == "tabs" }
        )
        extensionContext.setPermissionStatus(.grantedExplicitly, for: storagePermission)

        let granted = await withCheckedContinuation { continuation in
            manager.webExtensionController(
                try! requireRuntimeController(for: manager),
                promptForPermissions: [storagePermission, tabsPermission],
                in: nil,
                for: extensionContext
            ) { permissions, _ in
                continuation.resume(returning: permissions)
            }
        }

        XCTAssertEqual(granted, Set([storagePermission]))
        XCTAssertEqual(
            extensionContext.permissionStatus(for: tabsPermission),
            .deniedExplicitly
        )
        XCTAssertFalse(browserManager.dialogManager.isVisible)
    }

    func testMatchPatternPromptDelegateSilentlyReturnsOnlyAlreadyGrantedPatterns() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let browserManager = BrowserManager()
        manager.debugAttachBrowserManager(browserManager)

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Silent Match Pattern",
            "version": "1.0",
            "host_permissions": [
                "https://allowed.example/*",
                "https://denied.example/*",
            ],
        ]
        let extensionRoot = try makeUnpackedExtensionDirectory(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        let allowedPattern = try XCTUnwrap(
            webExtension.requestedPermissionMatchPatterns.first {
                $0.string == "https://allowed.example/*"
            }
        )
        let deniedPattern = try XCTUnwrap(
            webExtension.requestedPermissionMatchPatterns.first {
                $0.string == "https://denied.example/*"
            }
        )
        extensionContext.setPermissionStatus(.grantedExplicitly, for: allowedPattern)

        let granted = await withCheckedContinuation { continuation in
            manager.webExtensionController(
                try! requireRuntimeController(for: manager),
                promptForPermissionMatchPatterns: [allowedPattern, deniedPattern],
                in: nil,
                for: extensionContext
            ) { matchPatterns, _ in
                continuation.resume(returning: matchPatterns)
            }
        }

        XCTAssertEqual(granted, Set([allowedPattern]))
        XCTAssertEqual(
            extensionContext.permissionStatus(for: deniedPattern),
            .deniedExplicitly
        )
        XCTAssertFalse(browserManager.dialogManager.isVisible)
    }

    func testURLAccessPromptDelegateAutoGrantsCoveredURLAndSilentlyDeniesOthers() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let browserManager = BrowserManager()
        manager.debugAttachBrowserManager(browserManager)

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Silent URL Access",
            "version": "1.0",
            "host_permissions": ["https://allowed.example/*"],
        ]
        let extensionRoot = try makeUnpackedExtensionDirectory(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        let allowedPattern = try XCTUnwrap(
            webExtension.requestedPermissionMatchPatterns.first {
                $0.string == "https://allowed.example/*"
            }
        )
        extensionContext.setPermissionStatus(.grantedExplicitly, for: allowedPattern)

        let allowedURL = try XCTUnwrap(URL(string: "https://allowed.example/video"))
        let deniedURL = try XCTUnwrap(URL(string: "https://relap.io/hb/adfox/bid"))

        let granted = await withCheckedContinuation { continuation in
            manager.webExtensionController(
                try! requireRuntimeController(for: manager),
                promptForPermissionToAccess: [allowedURL, deniedURL],
                in: nil,
                for: extensionContext
            ) { urls, _ in
                continuation.resume(returning: urls)
            }
        }

        XCTAssertEqual(granted, Set([allowedURL]))
        XCTAssertEqual(
            extensionContext.permissionStatus(for: allowedURL),
            .grantedExplicitly
        )
        XCTAssertEqual(
            extensionContext.permissionStatus(for: deniedURL),
            .deniedExplicitly
        )
        XCTAssertFalse(browserManager.dialogManager.isVisible)
    }
}
