//
//  UserScriptGMBridge+JSShim.swift
//  Sumi
//
//  GM_* / GM object JavaScript shim string generation.
//

import Foundation
import WebKit

extension UserScriptGMBridge {
    /// Generates the JavaScript shim code that provides GM.* and GM_* globals
    /// and routes calls to the native handler.
    func generateJSShim() -> String {
        let handlerName = messageHandlerName

        // Build GM.info / GM_info
        let scriptMeta = script.metadata
        let grantsJSON = (try? JSONSerialization.data(withJSONObject: scriptMeta.grants))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let matchesJSON = (try? JSONSerialization.data(withJSONObject: scriptMeta.matches))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let excludesJSON = (try? JSONSerialization.data(withJSONObject: scriptMeta.excludeMatches))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let requiresJSON = (try? JSONSerialization.data(withJSONObject: scriptMeta.requires))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let resourcesJSON = (try? JSONSerialization.data(withJSONObject: scriptMeta.resources))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let excludesIncludeJSON = (try? JSONSerialization.data(withJSONObject: scriptMeta.excludes))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let antifeaturesJSON = (try? JSONSerialization.data(withJSONObject: scriptMeta.antifeatures))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let sumiCompatJSON = (try? JSONSerialization.data(withJSONObject: scriptMeta.sumiCompat))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let scriptMetaStrEscaped = scriptMeta.metablock
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        let escapedSource = (scriptMeta.sourceURL ?? "").replacingOccurrences(of: "\"", with: "\\\"")

        let escapedName = scriptMeta.name.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedDesc = (scriptMeta.description ?? "").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedVersion = (scriptMeta.version ?? "").replacingOccurrences(of: "\"", with: "\\\"")
        let grantsWindowFocus = scriptMeta.grants.contains("window.focus")
        let grantsWindowClose = scriptMeta.grants.contains("window.close")
        let diagFilenameEscaped = script.filename
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        return """
        (function() {
            'use strict';

            // Callback registry
            const __callbacks = {};
            const __valueListeners = {};
            let __callbackCounter = 0;
            let __listenerCounter = 0;

            function __newCallbackId() {
                return 'cb_' + (++__callbackCounter) + '_' + Math.random().toString(36).slice(2, 8);
            }

            function __sendMessage(method, args, resolve, reject) {
                const callbackId = __newCallbackId();
                if (resolve) __callbacks[callbackId] = { resolve, reject };
                window.webkit.messageHandlers['\(handlerName)'].postMessage({
                    context: '\(handlerName)',
                    featureName: 'gm',
                    method: method,
                    id: callbackId,
                    params: {
                        callbackId: callbackId,
                        args: args || {}
                    }
                });
                return callbackId;
            }

            // Global callback handlers (called from native side)
            window.__sumiGM_resolve = function(id, result) {
                const cb = __callbacks[id];
                if (cb) { cb.resolve(result); delete __callbacks[id]; }
            };
            window.__sumiGM_reject = function(id, error) {
                const cb = __callbacks[id];
                if (cb) { cb.reject(new Error(error)); delete __callbacks[id]; }
            };

            function __base64ToArrayBuffer(base64) {
                const binary = atob(base64 || '');
                const bytes = new Uint8Array(binary.length);
                for (let i = 0; i < binary.length; i++) {
                    bytes[i] = binary.charCodeAt(i);
                }
                return bytes.buffer;
            }

            function __normalizeXhrResponse(response) {
                if (!response || typeof response !== 'object') return response;
                const responseType = String(response.responseType || '').toLowerCase();
                if ((responseType === 'blob' || responseType === 'arraybuffer') && typeof response.response === 'string') {
                    const buffer = __base64ToArrayBuffer(response.response);
                    response.response = responseType === 'blob' ? new Blob([buffer]) : buffer;
                    response.responseText = '';
                } else if (responseType === 'json' && typeof response.response === 'string') {
                    try { response.response = response.response.length ? JSON.parse(response.response) : null; } catch (_) {}
                }
                if (response.finalUrl == null && response.responseURL != null) {
                    response.finalUrl = response.responseURL;
                }
                return response;
            }

            function __normalizeXhrHeaders(headers) {
                if (!headers) return {};
                const result = {};
                if (typeof Headers !== 'undefined' && headers instanceof Headers) {
                    headers.forEach((value, key) => { result[key] = String(value); });
                    return result;
                }
                if (Array.isArray(headers)) {
                    headers.forEach(entry => {
                        if (Array.isArray(entry) && entry.length >= 2) result[String(entry[0])] = String(entry[1]);
                    });
                    return result;
                }
                Object.entries(headers).forEach(([key, value]) => {
                    if (value != null) result[key] = String(value);
                });
                return result;
            }

            function __normalizeXhrData(data) {
                if (data == null || typeof data === 'string') return data;
                if (typeof URLSearchParams !== 'undefined' && data instanceof URLSearchParams) return data.toString();
                if (data instanceof ArrayBuffer) {
                    const bytes = new Uint8Array(data);
                    let binary = '';
                    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
                    return btoa(binary);
                }
                if (ArrayBuffer.isView(data)) {
                    const bytes = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
                    let binary = '';
                    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
                    return btoa(binary);
                }
                try { return JSON.stringify(data); } catch (_) { return String(data); }
            }

            function __normalizeNotificationDetails(details) {
                if (typeof details === 'string') {
                    return { text: details };
                }
                details = details || {};
                const result = {};
                ['title', 'text', 'details', 'body', 'image', 'icon', 'tag'].forEach(key => {
                    if (details[key] != null) result[key] = String(details[key]);
                });
                if (details.silent != null) result.silent = !!details.silent;
                return result;
            }

            // XHR callback handler
            window.__sumiGM_xhrCallback = function(id, event, response) {
                const cb = __callbacks[id];
                if (!cb) return;
                response = __normalizeXhrResponse(response);
                if (cb[event]) cb[event](response);
                if (cb['onreadystatechange']) cb['onreadystatechange'](response);
                if (event === 'onload' || event === 'onerror' || event === 'ontimeout' || event === 'onabort') {
                    if (cb['onloadend']) cb['onloadend'](response);
                    cb.resolve(response);
                    delete __callbacks[id];
                }
            };

            // GM.info / GM_info (Violentmonkey-compatible subset)
            const __gmInfo = {
                scriptHandler: 'SumiScripts',
                version: '1.0.0',
                scriptMetaStr: "\(scriptMetaStrEscaped)",
                script: {
                    name: "\(escapedName)",
                    description: "\(escapedDesc)",
                    version: "\(escapedVersion)",
                    uuid: '\(script.id.uuidString)',
                    grant: \(grantsJSON),
                    matches: \(matchesJSON),
                    'exclude-match': \(excludesJSON),
                    exclude: \(excludesIncludeJSON),
                    require: \(requiresJSON),
                    sumiCompat: \(sumiCompatJSON),
                    resources: \(resourcesJSON),
                    antifeature: \(antifeaturesJSON),
                    source: "\(escapedSource)",
                    filename: '\(script.filename)',
                    namespace: '\(scriptMeta.namespace ?? "")',
                    'run-at': '\(scriptMeta.runAt.rawValue)',
                    'inject-into': '\(scriptMeta.injectInto.rawValue)',
                    noframes: \(scriptMeta.noframes ? "true" : "false")
                }
            };
            Object.freeze(__gmInfo.script);
            Object.freeze(__gmInfo);

            const unsafeWindow = window;
            const __grantsWindowFocus = \(grantsWindowFocus ? "true" : "false");
            const __grantsWindowClose = \(grantsWindowClose ? "true" : "false");

            function __notifyValueListeners(key, oldValue, newValue, remote) {
                Object.values(__valueListeners).forEach(listener => {
                    if (listener.key !== key) return;
                    try { listener.callback(key, oldValue, newValue, remote); } catch (error) { console.error(error); }
                });
            }

            // GM object
            const GM = {
                info: __gmInfo,
                getValue: function(key, defaultValue) {
                    return new Promise((resolve, reject) => {
                        __sendMessage('GM.getValue', { key, defaultValue }, resolve, reject);
                    });
                },
                getValues: function(data) {
                    return new Promise((resolve, reject) => {
                        __sendMessage('GM.getValues', { data }, resolve, reject);
                    });
                },
                setValue: function(key, value) {
                    return new Promise((resolve, reject) => {
                        GM.getValue(key).then(oldValue => {
                            __sendMessage('GM.setValue', { key, value }, result => {
                                __notifyValueListeners(key, oldValue, value, false);
                                resolve(result);
                            }, reject);
                        }, reject);
                    });
                },
                setValues: function(data) {
                    return new Promise((resolve, reject) => {
                        __sendMessage('GM.setValues', { data }, resolve, reject);
                    });
                },
                deleteValue: function(key) {
                    return new Promise((resolve, reject) => {
                        GM.getValue(key).then(oldValue => {
                            __sendMessage('GM.deleteValue', { key }, result => {
                                __notifyValueListeners(key, oldValue, undefined, false);
                                resolve(result);
                            }, reject);
                        }, reject);
                    });
                },
                deleteValues: function(keys) {
                    return new Promise((resolve, reject) => {
                        __sendMessage('GM.deleteValues', { keys }, resolve, reject);
                    });
                },
                listValues: function() {
                    return new Promise((resolve, reject) => {
                        __sendMessage('GM.listValues', {}, resolve, reject);
                    });
                },
                addStyle: function(css) {
                    var tag = document.createElement('style');
                    tag.textContent = css || '';
                    (document.head || document.documentElement).appendChild(tag);
                    return Promise.resolve(tag);
                },
                addElement: function(parent, tagName, attributes) {
                    if (typeof parent === 'string') {
                        attributes = tagName;
                        tagName = parent;
                        parent = document.body || document.documentElement;
                    }
                    const el = document.createElement(tagName);
                    Object.entries(attributes || {}).forEach(([key, value]) => {
                        if (key === 'textContent') el.textContent = value;
                        else if (key === 'innerHTML') el.innerHTML = value;
                        else el.setAttribute(key, value);
                    });
                    (parent || document.body || document.documentElement).appendChild(el);
                    return el;
                },
                getResourceText: function(name) {
                    return new Promise((resolve, reject) => {
                        __sendMessage('GM.getResourceText', { name }, resolve, reject);
                    });
                },
                getResourceUrl: function(name) {
                    return new Promise((resolve, reject) => {
                        __sendMessage('GM.getResourceUrl', { name }, resolve, reject);
                    });
                },
                xmlHttpRequest: function(details) {
                    let abortId = null;
                    const promise = new Promise((resolve, reject) => {
                        const callbackId = __newCallbackId();
                        abortId = callbackId;
                        __callbacks[callbackId] = {
                            resolve, reject,
                            onload: details.onload,
                            onerror: details.onerror,
                            onloadstart: details.onloadstart,
                            onloadend: details.onloadend,
                            onprogress: details.onprogress,
                            ontimeout: details.ontimeout,
                            onabort: details.onabort,
                            onreadystatechange: details.onreadystatechange
                        };
                        window.webkit.messageHandlers['\(handlerName)'].postMessage({
                            context: '\(handlerName)',
                            featureName: 'gm',
                            method: 'GM_xmlhttpRequest',
                            id: callbackId,
                            params: {
                                callbackId: callbackId,
                                args: {
                                    url: details.url,
                                    method: details.method || 'GET',
                                    headers: __normalizeXhrHeaders(details.headers),
                                    data: __normalizeXhrData(details.data),
                                    timeout: details.timeout,
                                    responseType: details.responseType || '',
                                    overrideMimeType: details.overrideMimeType,
                                    user: details.user,
                                    password: details.password
                                }
                            }
                        });
                    });
                    promise.abort = function() {
                        if (abortId) {
                            __sendMessage('GM_xmlhttpRequest_abort', { requestId: abortId });
                        }
                    };
                    return promise;
                },
                xmlhttpRequest: function(details) {
                    return GM.xmlHttpRequest(details);
                },
                download: function(details, name) {
                    if (typeof details === 'string') details = { url: details, name };
                    let abortId = null;
                    const promise = new Promise((resolve, reject) => {
                        abortId = __sendMessage('GM_download', { details }, resolve, reject);
                    });
                    return {
                        abort: function() {
                            if (abortId) __sendMessage('GM_xmlhttpRequest_abort', { requestId: abortId });
                        },
                        then: promise.then.bind(promise),
                        catch: promise.catch.bind(promise),
                        finally: promise.finally.bind(promise)
                    };
                },
                openInTab: function(url, options) {
                    const background = typeof options === 'boolean' ? options : !(options && options.active !== false);
                    let closed = false;
                    __sendMessage('GM_openInTab', {
                        url,
                        active: typeof options === 'object' ? options.active !== false : !background,
                        background,
                        insert: typeof options === 'object' ? options.insert !== false : true,
                        pinned: typeof options === 'object' ? !!options.pinned : false
                    });
                    return {
                        get closed() { return closed; },
                        close: function() { closed = true; },
                        onclose: null
                    };
                },
                addValueChangeListener: function(key, callback) {
                    const id = 'vl_' + (++__listenerCounter);
                    __valueListeners[id] = { key, callback };
                    return id;
                },
                removeValueChangeListener: function(id) {
                    delete __valueListeners[id];
                },
                setClipboard: function(data, type) {
                    return new Promise((resolve, reject) => {
                        __sendMessage('GM.setClipboard', { data, type: type || 'text/plain' }, resolve, reject);
                    });
                },
                getTab: function() {
                    return new Promise((resolve, reject) => {
                        __sendMessage('GM.getTab', {}, resolve, reject);
                    });
                },
                saveTab: function(tabObj) {
                    return new Promise((resolve, reject) => {
                        __sendMessage('GM.saveTab', { tabObj }, resolve, reject);
                    });
                },
                notification: function(details) {
                    details = __normalizeNotificationDetails(details);
                    return new Promise((resolve, reject) => {
                        __sendMessage('GM_notification', details || {}, resolve, reject);
                    });
                }
            };

            // Legacy GM_ functions (synchronous-style wrappers)
            function GM_getValue(key, defaultValue) {
                return GM.getValue(key, defaultValue);
            }
            function GM_getValues(data) {
                return GM.getValues(data);
            }
            function GM_setValue(key, value) {
                return GM.setValue(key, value);
            }
            function GM_setValues(data) {
                return GM.setValues(data);
            }
            function GM_deleteValue(key) {
                return GM.deleteValue(key);
            }
            function GM_deleteValues(keys) {
                return GM.deleteValues(keys);
            }
            function GM_listValues() {
                return GM.listValues();
            }
            function GM_addStyle(css) {
                return GM.addStyle(css);
            }
            function GM_xmlhttpRequest(details) {
                const result = GM.xmlHttpRequest(details);
                return { abort: function() { result.abort(); } };
            }
            function GM_download(details, name) {
                return GM.download(details, name);
            }
            function GM_openInTab(url, options) {
                return GM.openInTab(url, options);
            }
            function GM_addElement(parent, tagName, attributes) {
                return GM.addElement(parent, tagName, attributes);
            }
            function GM_notification(details, ondone) {
                if (typeof details === 'string') {
                    details = {
                        text: details,
                        title: typeof ondone === 'string' ? ondone : ''
                    };
                }
                const promise = GM.notification(__normalizeNotificationDetails(details));
                if (typeof ondone === 'function') {
                    promise.then(function(result) {
                        ondone(result);
                    }, function(error) {
                        ondone(error);
                    });
                } else if (details && typeof details.ondone === 'function') {
                    promise.then(function(result) {
                        details.ondone(result);
                    }, function(error) {
                        details.ondone(error);
                    });
                }
                return promise;
            }
            function GM_setClipboard(data, type) {
                __sendMessage('GM.setClipboard', { data, type: type || 'text/plain' });
            }

            if (__grantsWindowFocus) {
                const __nativeWindowFocus = typeof window.focus === 'function' ? window.focus.bind(window) : null;
                window.focus = function() {
                    __sendMessage('window.focus', {});
                    try { return __nativeWindowFocus && __nativeWindowFocus(); } catch (_) { return undefined; }
                };
            }

            if (__grantsWindowClose) {
                window.close = function() {
                    __sendMessage('window.close', {});
                };
            }

            function GM_registerMenuCommand(caption, commandFunc, accessKey) {
                const commandId = __newCallbackId();
                __callbacks[commandId] = { resolve: commandFunc };
                __sendMessage('GM_registerMenuCommand', { caption, commandId, accessKey });
                return caption; // Common GM behavior
            }
            function GM_unregisterMenuCommand(caption) {
                __sendMessage('GM_unregisterMenuCommand', { caption });
            }
            function GM_addValueChangeListener(key, callback) {
                return GM.addValueChangeListener(key, callback);
            }
            function GM_removeValueChangeListener(id) {
                return GM.removeValueChangeListener(id);
            }
            function GM_getResourceText(name) {
                return GM.getResourceText(name);
            }
            function GM_getResourceURL(name) {
                return GM.getResourceUrl(name);
            }
            const GM_info = __gmInfo;

            // Expose to script scope
            window.GM = GM;
            window.GM_info = GM_info;
            window.unsafeWindow = unsafeWindow;
            window.GM_getValue = GM_getValue;
            window.GM_getValues = GM_getValues;
            window.GM_setValue = GM_setValue;
            window.GM_setValues = GM_setValues;
            window.GM_deleteValue = GM_deleteValue;
            window.GM_deleteValues = GM_deleteValues;
            window.GM_listValues = GM_listValues;
            window.GM_addStyle = GM_addStyle;
            window.GM_addElement = GM_addElement;
            window.GM_xmlhttpRequest = GM_xmlhttpRequest;
            window.GM_download = GM_download;
            window.GM_openInTab = GM_openInTab;
            window.GM_notification = GM_notification;
            window.GM_setClipboard = GM_setClipboard;
            window.GM_getResourceText = GM_getResourceText;
            window.GM_getResourceURL = GM_getResourceURL;
            window.GM_registerMenuCommand = GM_registerMenuCommand;
            window.GM_unregisterMenuCommand = GM_unregisterMenuCommand;
            window.GM_addValueChangeListener = GM_addValueChangeListener;
            window.GM_removeValueChangeListener = GM_removeValueChangeListener;

            window.__sumiScriptFilenameForDiag = '\(diagFilenameEscaped)';
            function __sumiReportRuntime(kind, detail) {
                try {
                    window.webkit.messageHandlers['\(handlerName)'].postMessage({
                        context: '\(handlerName)',
                        featureName: 'gm',
                        method: '__sumi_runtimeError',
                        params: {
                            callbackId: '',
                            args: Object.assign({ kind: kind }, detail || {})
                        }
                    });
                } catch (_) {}
            }
            window.addEventListener('error', function(e) {
                __sumiReportRuntime('error', {
                    message: e.message || '',
                    location: (e.filename || '') + ':' + (e.lineno || 0),
                    stack: (e.error && e.error.stack) ? String(e.error.stack) : ''
                });
            });
            window.addEventListener('unhandledrejection', function(e) {
                var reason = e.reason;
                __sumiReportRuntime('unhandledrejection', {
                    message: reason != null ? String(reason) : '',
                    stack: (reason && reason.stack) ? String(reason.stack) : ''
                });
            });
        })();
        """
    }
}
