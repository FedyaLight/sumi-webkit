// Sumi: externally_connectable background helper
// Intercepts onMessage/onConnect on the extension background,
// filters Sumi envelopes, and dispatches to onMessageExternal/onConnectExternal.
// Host-initiated external sendMessage still uses these envelopes (public WebKit
// has no app→background sendMessage); connect uses the same external path.
(function() {
    var CONNECT_PREFIX = '__sumi_ec_external_connect__:';

    function getRuntimes() {
        var r = [];
        try { if (typeof browser !== 'undefined' && browser.runtime) r.push(browser.runtime); } catch (_) {}
        try { if (typeof chrome !== 'undefined' && chrome.runtime) r.push(chrome.runtime); } catch (_) {}
        return r;
    }

    function isEnvelope(msg) {
        return !!(msg && typeof msg === 'object' && msg.__sumi_ec_external_message === true);
    }

    function parseConnectMeta(port) {
        if (!port || typeof port.name !== 'string' || port.name.indexOf(CONNECT_PREFIX) !== 0) return null;
        try { return JSON.parse(port.name.slice(CONNECT_PREFIX.length)); } catch (_) { return null; }
    }

    function normalizeSender(envelope, nativeSender) {
        var s = envelope && typeof envelope.sender === 'object' ? envelope.sender : {};
        var out = {};
        if (typeof s.origin === 'string') out.origin = s.origin;
        if (typeof s.url === 'string') out.url = s.url;
        if (typeof s.frameId === 'number') out.frameId = s.frameId;
        if (nativeSender) {
            if (nativeSender.tab !== undefined) out.tab = nativeSender.tab;
            if (out.frameId === undefined && typeof nativeSender.frameId === 'number') out.frameId = nativeSender.frameId;
            if (out.url === undefined && typeof nativeSender.url === 'string') out.url = nativeSender.url;
        }
        if (out.origin === undefined && typeof out.url === 'string') {
            try { out.origin = new URL(out.url).origin; } catch (_) {}
        }
        return out;
    }

    function makeEvent(nativeEvent) {
        var listeners = [];
        return {
            _dispatch: function() {
                var args = Array.prototype.slice.call(arguments);
                var async = false;
                listeners.slice().forEach(function(fn) {
                    try {
                        var r = fn.apply(null, args);
                        if (r === true || (r && typeof r.then === 'function')) async = true;
                    } catch (_) {}
                });
                return async;
            },
            addListener: function(fn) { if (typeof fn === 'function' && listeners.indexOf(fn) < 0) listeners.push(fn); },
            removeListener: function(fn) { var i = listeners.indexOf(fn); if (i >= 0) listeners.splice(i, 1); },
            hasListener: function(fn) { return listeners.indexOf(fn) >= 0; },
            hasListeners: function() { return listeners.length > 0; }
        };
    }

    function wrapOnMessage(rt, externalEvent) {
        var native = rt.onMessage;
        if (!native || typeof native.addListener !== 'function') return;
        var nativeAdd = native.addListener.bind(native);
        var nativeRemove = native.removeListener.bind(native);
        var pairs = [];

        nativeAdd(function(message, sender, sendResponse) {
            if (!isEnvelope(message)) return;
            return externalEvent._dispatch(message.payload, normalizeSender(message, sender), sendResponse);
        });

        rt.onMessage = {
            addListener: function(fn) {
                if (typeof fn !== 'function') return;
                var w = function(msg, s, sr) { if (!isEnvelope(msg)) return fn(msg, s, sr); };
                pairs.push({ o: fn, w: w });
                nativeAdd(w);
            },
            removeListener: function(fn) {
                for (var i = 0; i < pairs.length; i++) {
                    if (pairs[i].o === fn) { nativeRemove(pairs[i].w); pairs.splice(i, 1); return; }
                }
            },
            hasListener: function(fn) { return pairs.some(function(p) { return p.o === fn; }); },
            hasListeners: function() { return pairs.length > 0; }
        };
    }

    function wrapOnConnect(rt, externalEvent) {
        var native = rt.onConnect;
        if (!native || typeof native.addListener !== 'function') return;
        var nativeAdd = native.addListener.bind(native);
        var nativeRemove = native.removeListener.bind(native);
        var pairs = [];

        nativeAdd(function(port) {
            var meta = parseConnectMeta(port);
            if (!meta) return;
            var synth = {
                name: typeof meta.name === 'string' ? meta.name : '',
                sender: normalizeSender({ sender: meta.sender }, port.sender),
                onMessage: makeEvent(),
                onDisconnect: makeEvent(),
                postMessage: function(m) { port.postMessage(m); },
                disconnect: function() { try { port.disconnect(); } catch (_) {} }
            };
            port.onMessage.addListener(function(m) { synth.onMessage._dispatch(m, synth); });
            port.onDisconnect.addListener(function() { synth.onDisconnect._dispatch(synth); });
            externalEvent._dispatch(synth);
        });

        rt.onConnect = {
            addListener: function(fn) {
                if (typeof fn !== 'function') return;
                var w = function(p) { if (!parseConnectMeta(p)) return fn(p); };
                pairs.push({ o: fn, w: w });
                nativeAdd(w);
            },
            removeListener: function(fn) {
                for (var i = 0; i < pairs.length; i++) {
                    if (pairs[i].o === fn) { nativeRemove(pairs[i].w); pairs.splice(i, 1); return; }
                }
            },
            hasListener: function(fn) { return pairs.some(function(p) { return p.o === fn; }); },
            hasListeners: function() { return pairs.length > 0; }
        };
    }

    var root = typeof globalThis !== 'undefined' ? globalThis : self;
    if (root.__sumiEcBgHelperInstalled) return;
    root.__sumiEcBgHelperInstalled = true;

    getRuntimes().forEach(function(rt) {
        var extMsg = makeEvent(rt.onMessageExternal);
        var extConn = makeEvent(rt.onConnectExternal);
        wrapOnMessage(rt, extMsg);
        wrapOnConnect(rt, extConn);
        try { rt.onMessageExternal = extMsg; } catch (_) {}
        try { rt.onConnectExternal = extConn; } catch (_) {}
    });
})();
