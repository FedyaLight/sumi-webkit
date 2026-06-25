//
//  SumiUserScriptGMSubfeatures.swift
//  Sumi
//
//  Dispatches userscript privileged API messages to domain-specific handlers
//  (DuckDuckGo-style Subfeature routing without a monolithic switch in the bridge).
//

import WebKit

extension UserScriptGMBridge {
    func allowsNativeGMMethod(_ method: String) -> Bool {
        guard method != "__sumi_runtimeError" else { return true }

        let grants = Set(script.metadata.grants)
        guard !grants.isEmpty, !grants.contains("none") else {
            return false
        }

        return Self.grants(forNativeGMMethod: method).contains { grants.contains($0) }
    }

    private static func grants(forNativeGMMethod method: String) -> [String] {
        switch method {
        case "GM_getValue", "GM.getValue":
            return ["GM_getValue", "GM.getValue"]
        case "GM_getValues", "GM.getValues":
            return ["GM_getValues", "GM.getValues"]
        case "GM_setValue", "GM.setValue":
            return ["GM_setValue", "GM.setValue"]
        case "GM_setValues", "GM.setValues":
            return ["GM_setValues", "GM.setValues"]
        case "GM_deleteValue", "GM.deleteValue":
            return ["GM_deleteValue", "GM.deleteValue"]
        case "GM_deleteValues", "GM.deleteValues":
            return ["GM_deleteValues", "GM.deleteValues"]
        case "GM_listValues", "GM.listValues":
            return ["GM_listValues", "GM.listValues"]
        case "GM.getTab":
            return ["GM.getTab"]
        case "GM.saveTab":
            return ["GM.saveTab"]
        case "GM_getResourceText", "GM.getResourceText":
            return ["GM_getResourceText", "GM.getResourceText"]
        case "GM_getResourceURL", "GM.getResourceUrl":
            return ["GM_getResourceURL", "GM_getResourceUrl", "GM.getResourceURL", "GM.getResourceUrl"]
        case "GM_xmlhttpRequest":
            return ["GM_xmlhttpRequest", "GM.xmlHttpRequest", "GM.xmlhttpRequest"]
        case "GM_xmlhttpRequest_abort":
            return ["GM_xmlhttpRequest", "GM.xmlHttpRequest", "GM.xmlhttpRequest", "GM_download", "GM.download"]
        case "GM_download":
            return ["GM_download", "GM.download"]
        case "GM_addStyle":
            return ["GM_addStyle", "GM.addStyle"]
        case "GM_notification":
            return ["GM_notification", "GM.notification"]
        case "GM_registerMenuCommand":
            return ["GM_registerMenuCommand", "GM.registerMenuCommand"]
        case "GM_unregisterMenuCommand":
            return ["GM_unregisterMenuCommand", "GM.unregisterMenuCommand"]
        case "GM_setClipboard", "GM.setClipboard":
            return ["GM_setClipboard", "GM.setClipboard"]
        case "GM_openInTab", "GM.openInTab":
            return ["GM_openInTab", "GM.openInTab"]
        case "window.close":
            return ["window.close"]
        case "window.focus":
            return ["window.focus"]
        default:
            return []
        }
    }
}

/// Central entry: routes `method` from the JS shim to the appropriate handler on `UserScriptGMBridge`.
@MainActor
enum UserScriptGMDispatch {

    static func route(
        bridge: UserScriptGMBridge,
        method: String,
        args: [String: Any],
        callbackId: String,
        webView: WKWebView?,
        original: WKScriptMessage?
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
        if GMUISubfeature.route(
            bridge: bridge,
            method: method,
            args: args,
            callbackId: callbackId,
            webView: webView,
            original: original
        ) {
            return
        }
    }
}

// MARK: - Value storage & tab object

@MainActor
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

@MainActor
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

@MainActor
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

@MainActor
enum GMUISubfeature {
    static func route(
        bridge: UserScriptGMBridge,
        method: String,
        args: [String: Any],
        callbackId: String,
        webView: WKWebView?,
        original: WKScriptMessage?
    ) -> Bool {
        switch method {
        case "GM_addStyle":
            bridge.performAddStyle(callbackId: callbackId, webView: webView)
            return true
        case "GM_notification":
            bridge.performNotification(
                args: args,
                callbackId: callbackId,
                webView: webView,
                frame: original?.frameInfo
            )
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
