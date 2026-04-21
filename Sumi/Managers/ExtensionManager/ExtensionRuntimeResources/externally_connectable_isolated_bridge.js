// Sumi: externally_connectable bridge relay (connect-only)
// Runs as extension content script (ISOLATED world) with browser.runtime access.
// sendMessage is handled directly via callAsyncJavaScript in the isolated world;
// this relay only handles connect/port lifecycle via postMessage from page-world.
(function() {
    var runtimeAPI = null;
    try {
        if (typeof browser !== 'undefined' && browser.runtime) {
            runtimeAPI = browser.runtime;
        } else if (typeof chrome !== 'undefined' && chrome.runtime) {
            runtimeAPI = chrome.runtime;
        }
    } catch (_) {}

    var bridgePorts = Object.create(null);
    var externalConnectNamePrefix = '__sumi_ec_external_connect__:';
    var debugLoggingEnabled = __SUMI_DEBUG_LOGGING_ENABLED__;

    function debugLog(message) {
        if (!debugLoggingEnabled || typeof console === 'undefined' || typeof console.log !== 'function') return;
        console.log(message);
    }

    function debugWarn(message) {
        if (!debugLoggingEnabled || typeof console === 'undefined' || typeof console.warn !== 'function') return;
        console.warn(message);
    }

    function currentRuntimeId() {
        try {
            return runtimeAPI && runtimeAPI.id ? runtimeAPI.id : null;
        } catch (_) {
            return null;
        }
    }

    try {
        var relayRegistryKey = '__sumiEcBridgeRelayInstalledRuntimeIds';
        var relayRegistry = window[relayRegistryKey];
        if (!relayRegistry || typeof relayRegistry !== 'object') {
            relayRegistry = Object.create(null);
            window[relayRegistryKey] = relayRegistry;
        }
        var relayRegistryRuntimeId = currentRuntimeId() || '__unknown__';
        if (relayRegistry[relayRegistryRuntimeId]) {
            debugLog('[SUMI-EC] Relay already installed for runtime=' + relayRegistryRuntimeId);
            return;
        }
        relayRegistry[relayRegistryRuntimeId] = true;
    } catch (_) {}

    function isTargetedMessage(data) {
        if (!data || typeof data !== 'object') return false;
        var targetRuntimeId = data.targetRuntimeId;
        if (!targetRuntimeId || typeof targetRuntimeId !== 'string') return false;
        var runtimeId = currentRuntimeId();
        return !!runtimeId && targetRuntimeId === runtimeId;
    }

    function lastErrorMessage() {
        try {
            if (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.lastError && chrome.runtime.lastError.message) {
                return chrome.runtime.lastError.message;
            }
        } catch (_) {}
        return null;
    }

    function relayConnectOpen(data) {
        var portId = data.portId;
        if (!portId) return;

        if (!runtimeAPI || typeof runtimeAPI.connect !== 'function') {
            window.postMessage({
                type: 'sumi_ec_connect_disconnect',
                portId: portId,
                targetRuntimeId: currentRuntimeId(),
                error: 'runtime.connect unavailable'
            }, '*');
            return;
        }

        var connectInfo = data.connectInfo;
        if (!connectInfo || typeof connectInfo !== 'object') {
            connectInfo = {};
        } else {
            connectInfo = Object.assign({}, connectInfo);
        }

        if (data.nativeExternal) {
            var originalName = typeof connectInfo.name === 'string' ? connectInfo.name : '';
            connectInfo.name = externalConnectNamePrefix + JSON.stringify({
                name: originalName,
                portId: portId,
                sender: data.sender || null,
                targetRuntimeId: data.targetRuntimeId || currentRuntimeId()
            });
        }

        debugLog('[SUMI-EC] Relay connect open id=' + portId + ' name=' + (connectInfo.name || '') + ' ext=' + (data.extensionId || '(none)'));

        var port;
        try {
            port = runtimeAPI.connect(connectInfo);
        } catch (error) {
            window.postMessage({
                type: 'sumi_ec_connect_disconnect',
                portId: portId,
                targetRuntimeId: currentRuntimeId(),
                error: (error && error.message) ? error.message : String(error)
            }, '*');
            return;
        }

        bridgePorts[portId] = port;
        port.onMessage.addListener(function(message) {
            window.postMessage({
                type: 'sumi_ec_connect_message',
                portId: portId,
                targetRuntimeId: currentRuntimeId(),
                message: message
            }, '*');
        });
        port.onDisconnect.addListener(function() {
            var error = lastErrorMessage();
            delete bridgePorts[portId];
            debugLog('[SUMI-EC] Relay connect disconnect id=' + portId + (error ? (' error=' + error) : ''));
            window.postMessage({
                type: 'sumi_ec_connect_disconnect',
                portId: portId,
                targetRuntimeId: currentRuntimeId(),
                error: error
            }, '*');
        });

        window.postMessage({
            type: 'sumi_ec_connect_opened',
            portId: portId,
            targetRuntimeId: currentRuntimeId()
        }, '*');
    }

    function relayConnectPost(data) {
        var port = bridgePorts[data.portId];
        if (!port) return;
        try {
            port.postMessage(data.message);
        } catch (error) {
            delete bridgePorts[data.portId];
            window.postMessage({
                type: 'sumi_ec_connect_disconnect',
                portId: data.portId,
                targetRuntimeId: currentRuntimeId(),
                error: (error && error.message) ? error.message : String(error)
            }, '*');
        }
    }

    function relayConnectClose(data) {
        var portId = data.portId;
        var port = bridgePorts[portId];
        if (!port) return;
        delete bridgePorts[portId];
        try {
            port.disconnect();
        } catch (_) {}
        window.postMessage({
            type: 'sumi_ec_connect_disconnect',
            portId: portId,
            targetRuntimeId: currentRuntimeId(),
            error: null
        }, '*');
    }

    window.addEventListener('message', function(event) {
        if (event.source !== window) return;
        if (!event.data || typeof event.data.type !== 'string') return;
        if (event.data.type === 'sumi_ec_connect_open') {
            if (!isTargetedMessage(event.data)) return;
            relayConnectOpen(event.data);
            return;
        }
        if (event.data.type === 'sumi_ec_connect_post') {
            if (!isTargetedMessage(event.data)) return;
            relayConnectPost(event.data);
            return;
        }
        if (event.data.type === 'sumi_ec_connect_close') {
            if (!isTargetedMessage(event.data)) return;
            relayConnectClose(event.data);
            return;
        }
    });
})();
