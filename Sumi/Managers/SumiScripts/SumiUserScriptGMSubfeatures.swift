//
//  SumiUserScriptGMSubfeatures.swift
//  Sumi
//
//  Dispatches userscript privileged API messages to domain-specific handlers
//  (DuckDuckGo-style Subfeature routing without a monolithic switch in the bridge).
//

import WebKit

/// Central entry: routes `method` from the JS shim to the appropriate handler on `UserScriptGMBridge`.
enum UserScriptGMDispatch {

    static func route(
        bridge: UserScriptGMBridge,
        method: String,
        args: [String: Any],
        callbackId: String,
        webView: WKWebView?
    ) {
        if GMValueSubfeature.route(bridge: bridge, method: method, args: args, callbackId: callbackId, webView: webView) {
            return
        }
        if GMResourceSubfeature.route(bridge: bridge, method: method, args: args, callbackId: callbackId, webView: webView) {
            return
        }
        if GMNetworkSubfeature.route(bridge: bridge, method: method, args: args, callbackId: callbackId, webView: webView) {
            return
        }
        if GMUISubfeature.route(bridge: bridge, method: method, args: args, callbackId: callbackId, webView: webView) {
            return
        }
    }
}

// MARK: - Value storage & tab object

enum GMValueSubfeature {
    static func route(
        bridge: UserScriptGMBridge,
        method: String,
        args: [String: Any],
        callbackId: String,
        webView: WKWebView?
    ) -> Bool {
        switch method {
        case "GM_getValue", "GM.getValue":
            bridge.performGetValue(args: args, callbackId: callbackId, webView: webView)
            return true
        case "GM_getValues", "GM.getValues":
            bridge.performGetValues(args: args, callbackId: callbackId, webView: webView)
            return true
        case "GM_setValue", "GM.setValue":
            bridge.performSetValue(args: args, callbackId: callbackId, webView: webView)
            return true
        case "GM_setValues", "GM.setValues":
            bridge.performSetValues(args: args, callbackId: callbackId, webView: webView)
            return true
        case "GM_deleteValue", "GM.deleteValue":
            bridge.performDeleteValue(args: args, callbackId: callbackId, webView: webView)
            return true
        case "GM_deleteValues", "GM.deleteValues":
            bridge.performDeleteValues(args: args, callbackId: callbackId, webView: webView)
            return true
        case "GM_listValues", "GM.listValues":
            bridge.performListValues(callbackId: callbackId, webView: webView)
            return true
        case "GM.getTab":
            bridge.performGetTab(callbackId: callbackId, webView: webView)
            return true
        case "GM.saveTab":
            bridge.performSaveTab(args: args, callbackId: callbackId, webView: webView)
            return true
        default:
            return false
        }
    }
}

// MARK: - @resource

enum GMResourceSubfeature {
    static func route(
        bridge: UserScriptGMBridge,
        method: String,
        args: [String: Any],
        callbackId: String,
        webView: WKWebView?
    ) -> Bool {
        switch method {
        case "GM_getResourceText", "GM.getResourceText":
            bridge.performGetResourceText(args: args, callbackId: callbackId, webView: webView)
            return true
        case "GM_getResourceURL", "GM.getResourceUrl":
            bridge.performGetResourceURL(args: args, callbackId: callbackId, webView: webView)
            return true
        default:
            return false
        }
    }
}

// MARK: - XHR / download

enum GMNetworkSubfeature {
    static func route(
        bridge: UserScriptGMBridge,
        method: String,
        args: [String: Any],
        callbackId: String,
        webView: WKWebView?
    ) -> Bool {
        switch method {
        case "GM_xmlhttpRequest":
            bridge.performXMLHttpRequest(args: args, callbackId: callbackId, webView: webView)
            return true
        case "GM_xmlhttpRequest_abort":
            bridge.performXMLHttpRequestAbort(args: args)
            return true
        case "GM_download":
            bridge.performDownload(args: args, callbackId: callbackId, webView: webView)
            return true
        default:
            return false
        }
    }
}

// MARK: - UI, menu, tabs, clipboard, notifications, window grants

enum GMUISubfeature {
    static func route(
        bridge: UserScriptGMBridge,
        method: String,
        args: [String: Any],
        callbackId: String,
        webView: WKWebView?
    ) -> Bool {
        switch method {
        case "GM_addStyle":
            bridge.performAddStyle(args: args, webView: webView)
            return true
        case "GM_notification":
            bridge.performNotification(args: args)
            return true
        case "GM_registerMenuCommand":
            bridge.performRegisterMenuCommand(args: args)
            return true
        case "GM_unregisterMenuCommand":
            bridge.performUnregisterMenuCommand(args: args)
            return true
        case "GM_setClipboard", "GM.setClipboard":
            bridge.performSetClipboard(args: args, callbackId: callbackId, webView: webView)
            return true
        case "GM_openInTab", "GM.openInTab":
            bridge.performOpenInTab(args: args, callbackId: callbackId, webView: webView)
            return true
        case "window.close":
            bridge.performWindowClose(callbackId: callbackId, webView: webView)
            return true
        case "window.focus":
            bridge.performWindowFocus(callbackId: callbackId, webView: webView)
            return true
        default:
            return false
        }
    }
}
