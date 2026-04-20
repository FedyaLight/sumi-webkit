__SUMI_BRIDGE_MARKER__
(function(config) {
    if (!config || typeof config !== 'object') return;

    var _allowedHosts = Array.isArray(config.allowedHosts) ? config.allowedHosts : [];
    var _bridgeMarkerKey = typeof config.bridgeMarkerKey === 'string' ? config.bridgeMarkerKey : __SUMI_BRIDGE_MARKER_STRING__;
    var _configuredRuntimeId = typeof config.configuredRuntimeId === 'string' ? config.configuredRuntimeId : null;
    var _debugLoggingEnabled = !!config.debugLoggingEnabled;
    var _nativeBridgeHandlerName = typeof config.nativeBridgeHandlerName === 'string' ? config.nativeBridgeHandlerName : null;
    var _bridgeVersion = typeof config.bridgeVersion === 'number' ? config.bridgeVersion : 1;
    var _activeRuntimeId = _configuredRuntimeId;

    if (_allowedHosts.length) {
        var hostname = location.hostname;
        var allowed = _allowedHosts.some(function(host) {
            return hostname === host || hostname.endsWith('.' + host);
        });
        if (!allowed) return;
    }

    function debugLog(message) {
        if (!_debugLoggingEnabled || !window.console || typeof console.log !== 'function') return;
        console.log(message);
    }

    function debugWarn(message) {
        if (!_debugLoggingEnabled || !window.console || typeof console.warn !== 'function') return;
        console.warn(message);
    }

    function debugError(message) {
        if (!_debugLoggingEnabled || !window.console || typeof console.error !== 'function') return;
        console.error(message);
    }

    function errorText(error) {
        return (error && error.message) ? error.message : String(error);
    }

    function shimRegistryKey() {
        if (_configuredRuntimeId) {
            return 'runtime:' + _configuredRuntimeId;
        }
        if (_bridgeMarkerKey) {
            return 'marker:' + _bridgeMarkerKey;
        }
        if (_nativeBridgeHandlerName) {
            return 'handler:' + _nativeBridgeHandlerName;
        }
        return 'anonymous';
    }

    var shimRegistry = window.__sumiEcShimInstalledRuntimeIds;
    if (!shimRegistry || typeof shimRegistry !== 'object') {
        shimRegistry = Object.create(null);
        window.__sumiEcShimInstalledRuntimeIds = shimRegistry;
    }

    var _shimRegistryKey = shimRegistryKey();
    if (shimRegistry[_shimRegistryKey]) {
        debugLog('[SUMI-EC] Page shim already installed for ' + _shimRegistryKey + '; skipping duplicate bootstrap');
        return;
    }
    shimRegistry[_shimRegistryKey] = true;

    debugLog('[SUMI-EC] Installing externally_connectable polyfill for ' + _shimRegistryKey + ' on ' + location.href);

    var bridgeReady = false;
    var bridgePorts = Object.create(null);

    function makeEvent() {
        var listeners = [];
        return {
            addListener: function(fn) {
                if (typeof fn !== 'function') return;
                if (listeners.indexOf(fn) >= 0) return;
                listeners.push(fn);
            },
            removeListener: function(fn) {
                var idx = listeners.indexOf(fn);
                if (idx >= 0) listeners.splice(idx, 1);
            },
            hasListener: function(fn) {
                return listeners.indexOf(fn) >= 0;
            },
            dispatch: function() {
                var args = Array.prototype.slice.call(arguments);
                var snapshot = listeners.slice();
                for (var i = 0; i < snapshot.length; i += 1) {
                    try {
                        snapshot[i].apply(null, args);
                    } catch (error) {
                        debugError('[SUMI-EC] Listener error: ' + errorText(error));
                    }
                }
            }
        };
    }

    function markBridgeReady() {
        if (bridgeReady) return;
        bridgeReady = true;
    }

    function activeRuntimeId() {
        return _activeRuntimeId || _configuredRuntimeId;
    }

    function matchesActiveRuntimeId(runtimeId) {
        if (!runtimeId || typeof runtimeId !== 'string') return true;
        return runtimeId === activeRuntimeId();
    }

    function normalizeSendMessageArgs(argsLike) {
        var args = Array.prototype.slice.call(argsLike);
        var callback = null;

        if (args.length && typeof args[args.length - 1] === 'function') {
            callback = args.pop();
        }

        var extensionId = null;
        var message = undefined;
        var options = undefined;

        if (args.length === 1) {
            message = args[0];
        } else if (args.length === 2) {
            if (typeof args[0] === 'string') {
                extensionId = args[0];
                message = args[1];
            } else {
                message = args[0];
                options = args[1];
            }
        } else if (args.length >= 3) {
            extensionId = args[0];
            message = args[1];
            options = args[2];
        }

        return {
            extensionId: extensionId,
            message: message,
            options: options,
            callback: callback
        };
    }

    function normalizeConnectArgs(argsLike) {
        var args = Array.prototype.slice.call(argsLike);
        var extensionId = null;
        var connectInfo = {};

        if (args.length === 1) {
            if (typeof args[0] === 'string') {
                extensionId = args[0];
            } else {
                connectInfo = args[0];
            }
        } else if (args.length >= 2) {
            extensionId = args[0];
            connectInfo = args[1];
        }

        if (!connectInfo || typeof connectInfo !== 'object') {
            connectInfo = {};
        }

        return {
            extensionId: extensionId,
            connectInfo: connectInfo
        };
    }

    function setChromeLastError(error) {
        if (!window.chrome) window.chrome = {};
        if (!window.chrome.runtime) window.chrome.runtime = {};
        if (error) {
            window.chrome.runtime.lastError = { message: error.message || String(error) };
        } else if (window.chrome.runtime.lastError) {
            try {
                delete window.chrome.runtime.lastError;
            } catch (_) {
                window.chrome.runtime.lastError = undefined;
            }
        }
    }

    function clearChromeLastErrorAsync() {
        setTimeout(function() { setChromeLastError(null); }, 0);
    }

    function nativeBridgeHandler() {
        return window.webkit && window.webkit.messageHandlers
            ? window.webkit.messageHandlers[_nativeBridgeHandlerName]
            : null;
    }

    function newBridgeRequestId() {
        try {
            if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
                return crypto.randomUUID();
            }
        } catch (_) {}
        return 'sumi_ec_req_' + String(Date.now()) + '_' + Math.random().toString(36).slice(2, 11);
    }

    function requestViaNativeBridge(parsed, requestType) {
        var handler = nativeBridgeHandler();
        if (!handler || typeof handler.postMessage !== 'function') {
            return Promise.reject(new Error('Native extension bridge unavailable'));
        }

        return Promise.resolve(handler.postMessage({
            bridgeVersion: _bridgeVersion,
            featureName: 'runtime',
            method: 'sendMessage',
            id: newBridgeRequestId(),
            params: {
                documentURL: location.href,
                extensionId: parsed.extensionId || activeRuntimeId(),
                message: parsed.message,
                options: typeof parsed.options === 'undefined' ? null : parsed.options,
                origin: location.origin,
                requestType: requestType || null,
                timeoutMs: 30000
            }
        }));
    }

    function requestViaNativeConnect(method, payload) {
        var handler = nativeBridgeHandler();
        if (!handler || typeof handler.postMessage !== 'function') {
            return Promise.reject(new Error('Native connect bridge unavailable'));
        }

        return Promise.resolve(handler.postMessage({
            bridgeVersion: _bridgeVersion,
            featureName: 'runtime',
            method: method,
            id: newBridgeRequestId(),
            params: Object.assign({
                documentURL: location.href,
                extensionId: activeRuntimeId(),
                origin: location.origin,
                timeoutMs: 30000
            }, payload || {})
        }));
    }

    function closeBridgePort(portId, errorMessage) {
        var entry = bridgePorts[portId];
        if (!entry || entry.disconnected) return;
        entry.disconnected = true;
        delete bridgePorts[portId];

        if (errorMessage) {
            setChromeLastError(new Error(errorMessage));
            try {
                entry.onDisconnect.dispatch(entry.port);
            } finally {
                clearChromeLastErrorAsync();
            }
            return;
        }
        entry.onDisconnect.dispatch(entry.port);
    }

    function createBridgePortEntry(parsed, portId, connectInfo) {
        var onMessage = makeEvent();
        var onDisconnect = makeEvent();

        var entry = {
            connectInfo: connectInfo,
            disconnected: false,
            opened: false,
            pendingMessages: [],
            onMessage: onMessage,
            onDisconnect: onDisconnect,
            port: null
        };

        var port = {
            name: typeof connectInfo.name === 'string' ? connectInfo.name : '',
            postMessage: function(message) {
                if (entry.disconnected) throw new Error('Port is disconnected');
                if (!entry.opened) {
                    entry.pendingMessages.push(message);
                    return;
                }
                requestViaNativeConnect('runtime.connect.postMessage', {
                    extensionId: parsed.extensionId || activeRuntimeId(),
                    message: message,
                    portId: portId,
                }).catch(function(error) {
                    closeBridgePort(
                        portId,
                        (error && error.message) ? error.message : String(error)
                    );
                });
            },
            disconnect: function() {
                if (entry.disconnected) return;
                requestViaNativeConnect('runtime.connect.disconnect', {
                    extensionId: parsed.extensionId || activeRuntimeId(),
                    portId: portId
                }).catch(function() {});
                closeBridgePort(portId, null);
            },
            onMessage: onMessage,
            onDisconnect: onDisconnect
        };
        entry.port = port;
        return entry;
    }

    function createBridgePort(parsed) {
        var portId = 'sumi_ec_port_' + Math.random().toString(36).slice(2, 11);
        var connectInfo = parsed.connectInfo || {};
        var entry = createBridgePortEntry(parsed, portId, connectInfo);
        var port = entry.port;
        bridgePorts[portId] = entry;

        requestViaNativeConnect('runtime.connect.open', {
            connectInfo: connectInfo,
            extensionId: parsed.extensionId || activeRuntimeId(),
            portId: portId
        }).catch(function(error) {
            var message = (error && error.message) ? error.message : String(error);
            debugWarn('[SUMI-EC] Native port open failed id=' + portId + ': ' + message);
            closeBridgePort(portId, message);
        });

        return port;
    }

    window.__sumiEcNativePortOpened = function(portId, payload) {
        var entry = bridgePorts[portId];
        if (!entry || entry.disconnected) return false;
        entry.opened = true;
        var pendingMessages = entry.pendingMessages.slice();
        entry.pendingMessages.length = 0;
        pendingMessages.forEach(function(message) {
            if (entry.disconnected) return;
            requestViaNativeConnect('runtime.connect.postMessage', {
                extensionId: (payload && payload.extensionId) ? payload.extensionId : activeRuntimeId(),
                message: message,
                portId: portId
            }).catch(function(error) {
                closeBridgePort(
                    portId,
                    (error && error.message) ? error.message : String(error)
                );
            });
        });
        return true;
    };

    window.__sumiEcNativePortMessage = function(portId, message) {
        var entry = bridgePorts[portId];
        if (!entry || entry.disconnected) return false;
        entry.onMessage.dispatch(message, entry.port);
        return true;
    };

    window.__sumiEcNativePortDisconnected = function(portId, errorMessage) {
        closeBridgePort(portId, errorMessage || null);
        return true;
    };

    function makeSendMessageWrapper(originalSendMessage, runtimeKind, runtimeObject) {
        return function() {
            var parsed = normalizeSendMessageArgs(arguments);
            var requestType = (
                parsed.message && typeof parsed.message === 'object' && parsed.message.type
            ) ? parsed.message.type : typeof parsed.message;

            var shouldBridge = !!activeRuntimeId()
                || parsed.extensionId !== null
                || typeof originalSendMessage !== 'function';
            debugLog('[SUMI-EC] sendMessage called via ' + runtimeKind + ' type=' + requestType + ' ext=' + (parsed.extensionId || '(none)') + ' mode=' + (shouldBridge ? 'native' : 'native-runtime'));

            var promise;
            if (shouldBridge) {
                promise = requestViaNativeBridge(parsed, requestType);
            } else {
                try {
                    promise = Promise.resolve(originalSendMessage.apply(runtimeObject, arguments));
                } catch (error) {
                    promise = Promise.reject(error);
                }
            }

            if (parsed.callback) {
                promise.then(function(response) {
                    setChromeLastError(null);
                    parsed.callback(response);
                }).catch(function(error) {
                    setChromeLastError(error);
                    try {
                        parsed.callback();
                    } finally {
                        clearChromeLastErrorAsync();
                    }
                });
                return;
            }

            return promise;
        };
    }

    function makeConnectWrapper(originalConnect, runtimeKind, runtimeObject) {
        return function() {
            var parsed = normalizeConnectArgs(arguments);
            var shouldBridge = !!activeRuntimeId()
                || parsed.extensionId !== null
                || typeof originalConnect !== 'function';
            debugLog('[SUMI-EC] connect called via ' + runtimeKind + ' ext=' + (parsed.extensionId || '(none)') + ' mode=' + (shouldBridge ? 'native' : 'native-runtime'));

            if (shouldBridge) {
                return createBridgePort(parsed);
            }

            try {
                return originalConnect.apply(runtimeObject, arguments);
            } catch (error) {
                throw error;
            }
        };
    }

    function installRuntimeShim(runtimeObject, runtimeKind) {
        if (!runtimeObject || typeof runtimeObject !== 'object') return;

        var currentSendMessage = typeof runtimeObject.sendMessage === 'function'
            ? runtimeObject.sendMessage
            : null;
        if (typeof runtimeObject.__sumiEcWrappedSendMessage !== 'function'
            || runtimeObject.sendMessage !== runtimeObject.__sumiEcWrappedSendMessage) {
            runtimeObject.__sumiEcWrappedSendMessage = makeSendMessageWrapper(
                currentSendMessage,
                runtimeKind,
                runtimeObject
            );
            runtimeObject.sendMessage = runtimeObject.__sumiEcWrappedSendMessage;
        }

        var currentConnect = typeof runtimeObject.connect === 'function'
            ? runtimeObject.connect
            : null;
        if (typeof runtimeObject.__sumiEcWrappedConnect !== 'function'
            || runtimeObject.connect !== runtimeObject.__sumiEcWrappedConnect) {
            runtimeObject.__sumiEcWrappedConnect = makeConnectWrapper(
                currentConnect,
                runtimeKind,
                runtimeObject
            );
            runtimeObject.connect = runtimeObject.__sumiEcWrappedConnect;
        }
    }

    function ensureRuntimeObject(rootName) {
        if (!window[rootName]) window[rootName] = {};
        if (!window[rootName].runtime) window[rootName].runtime = {};
        return window[rootName].runtime;
    }

    window.addEventListener('message', function(event) {
        if (event.source !== window) return;
        if (!event.data || typeof event.data.type !== 'string') return;
        if (event.data.type === 'sumi_ec_connect_message') {
            if (!matchesActiveRuntimeId(event.data.targetRuntimeId)) return;
            var messageEntry = bridgePorts[event.data.portId];
            if (!messageEntry || messageEntry.disconnected) return;
            messageEntry.onMessage.dispatch(event.data.message, messageEntry.port);
            return;
        }
        if (event.data.type === 'sumi_ec_connect_disconnect') {
            if (!matchesActiveRuntimeId(event.data.targetRuntimeId)) return;
            closeBridgePort(event.data.portId, event.data.error || null);
            return;
        }
    });

    var browserRuntime = ensureRuntimeObject('browser');
    var chromeRuntime = ensureRuntimeObject('chrome');
    installRuntimeShim(browserRuntime, 'browser.runtime');
    installRuntimeShim(chromeRuntime, 'chrome.runtime');
    markBridgeReady();

    debugLog('[SUMI-EC] Polyfill ready - runtime sendMessage/connect wrapped (configured=' + _configuredRuntimeId + ', mode=native)');
})(__SUMI_CONFIG_JSON__);
