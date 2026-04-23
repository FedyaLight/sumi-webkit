//
//  UserScriptGMBridge.swift
//  Sumi
//
//  Native implementation of Greasemonkey/Tampermonkey API.
//  Provides GM.* and GM_* functions via WKScriptMessageHandler,
//  with native URLSession for GM_xmlhttpRequest (bypasses CORS/CSP).
//
//  Greasemonkey-style APIs commonly used by translation/network userscripts.
//

import AppKit
import Foundation
import UserNotifications
import WebKit

final class UserScriptGMBridge: NSObject, WKScriptMessageHandler {

    let script: UserScript
    private let contentWorld: WKContentWorld
    private weak var tabOpenHandler: SumiScriptsTabHandler?
    weak var downloadManager: DownloadManager?

    // Per-script persistent storage using UserDefaults suite
    private let storage: UserDefaults?
    private var volatileStorage: [String: Any] = [:]

    // Per-tab transient storage (GM.getTab/saveTab)
    private var tabStorage: [String: Any] = [:]

    // Active XHR tasks (for abort support)
    var activeTasks: [String: URLSessionTask] = [:]
    var activeDownloadItems: [String: DownloadItem] = [:]

    init(
        script: UserScript,
        profileId: UUID?,
        contentWorld: WKContentWorld,
        tabOpenHandler: SumiScriptsTabHandler?,
        downloadManager: DownloadManager?
    ) {
        self.script = script
        self.contentWorld = contentWorld
        self.tabOpenHandler = tabOpenHandler
        self.downloadManager = downloadManager

        if let profileId {
            let suiteName = "group.sumi.userscripts.\(profileId.uuidString).\(UserScriptStore.sanitizeFilename(script.filename))"
            self.storage = UserDefaults(suiteName: suiteName) ?? .standard
        } else {
            self.storage = nil
        }

        super.init()
    }

    /// The message handler name used in JS to communicate with this bridge.
    var messageHandlerName: String {
        "sumiGM_\(script.id.uuidString)"
    }

    func resolveMenuCommand(_ commandId: String, webView: WKWebView?) {
        resolveCallback(commandId, result: NSNull(), webView: webView)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let method = body["method"] as? String
        else { return }

        let callbackId = body["callbackId"] as? String ?? ""
        let args = body["args"] as? [String: Any] ?? [:]

        if method == "__sumi_runtimeError" {
            NotificationCenter.default.post(
                name: .sumiUserScriptRuntimeError,
                object: self,
                userInfo: [
                    "scriptId": script.id.uuidString,
                    "scriptFilename": script.filename,
                    "kind": args["kind"] as? String ?? "error",
                    "message": args["message"] as? String ?? "",
                    "location": args["location"] as? String ?? "",
                    "stack": args["stack"] as? String ?? ""
                ]
            )
            return
        }

        UserScriptGMDispatch.route(
            bridge: self,
            method: method,
            args: args,
            callbackId: callbackId,
            webView: message.webView
        )
    }

    // MARK: - GM_getValue / GM.getValue

    func performGetValue(args: [String: Any], callbackId: String, webView: WKWebView?) {
        let key = args["key"] as? String ?? ""
        let defaultValue = args["defaultValue"]

        let stored = storedValue(forKey: key)
        let result = stored ?? defaultValue as Any
        resolveCallback(callbackId, result: result, webView: webView)
    }

    // MARK: - GM_setValue / GM.setValue

    func performSetValue(args: [String: Any], callbackId: String, webView: WKWebView?) {
        let key = args["key"] as? String ?? ""
        let value = args["value"]
        setStoredValue(value, forKey: key)
        resolveCallback(callbackId, result: true, webView: webView)
    }

    func performSetValues(args: [String: Any], callbackId: String, webView: WKWebView?) {
        if let values = args["data"] as? [String: Any] {
            for (key, value) in values {
                setStoredValue(value, forKey: key)
            }
        }
        resolveCallback(callbackId, result: true, webView: webView)
    }

    // MARK: - GM_deleteValue / GM.deleteValue

    func performDeleteValue(args: [String: Any], callbackId: String, webView: WKWebView?) {
        let key = args["key"] as? String ?? ""
        removeStoredValue(forKey: key)
        resolveCallback(callbackId, result: true, webView: webView)
    }

    func performDeleteValues(args: [String: Any], callbackId: String, webView: WKWebView?) {
        if let keys = args["keys"] as? [String] {
            keys.forEach(removeStoredValue)
        } else if let keys = args["keys"] as? [Any] {
            keys.compactMap { $0 as? String }.forEach(removeStoredValue)
        }
        resolveCallback(callbackId, result: true, webView: webView)
    }

    // MARK: - GM_listValues / GM.listValues

    func performListValues(callbackId: String, webView: WKWebView?) {
        let gmKeys = storedKeys()
        resolveCallback(callbackId, result: gmKeys, webView: webView)
    }

    func performGetTab(callbackId: String, webView: WKWebView?) {
        resolveCallback(callbackId, result: tabStorage, webView: webView)
    }

    func performSaveTab(args: [String: Any], callbackId: String, webView: WKWebView?) {
        if let tabObj = args["tabObj"] {
            tabStorage = (tabObj as? [String: Any]) ?? [:]
        }
        resolveCallback(callbackId, result: true, webView: webView)
    }

    // MARK: - GM.getValues (batch)

    func performGetValues(args: [String: Any], callbackId: String, webView: WKWebView?) {
        if let data = args["data"] as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, defaultValue) in data {
                let stored = storedValue(forKey: key)
                result[key] = stored ?? defaultValue
            }
            resolveCallback(callbackId, result: result, webView: webView)
            return
        }

        if let keys = args["data"] as? [String] {
            var result: [String: Any] = [:]
            for key in keys {
                if let stored = storedValue(forKey: key) {
                    result[key] = stored
                }
            }
            resolveCallback(callbackId, result: result, webView: webView)
            return
        }

        var result: [String: Any] = [:]
        for key in storedKeys() {
            if let stored = storedValue(forKey: key) {
                result[key] = stored
            }
        }
        resolveCallback(callbackId, result: result, webView: webView)
    }

    private func storedValue(forKey key: String) -> Any? {
        if let storage {
            return storage.object(forKey: "gmval_\(key)")
        }
        return volatileStorage[key]
    }

    private func setStoredValue(_ value: Any?, forKey key: String) {
        if let storage {
            storage.set(value, forKey: "gmval_\(key)")
        } else {
            volatileStorage[key] = value
        }
    }

    private func removeStoredValue(forKey key: String) {
        if let storage {
            storage.removeObject(forKey: "gmval_\(key)")
        } else {
            volatileStorage.removeValue(forKey: key)
        }
    }

    private func storedKeys() -> [String] {
        if let storage {
            return storage.dictionaryRepresentation().keys
                .filter { $0.hasPrefix("gmval_") }
                .map { String($0.dropFirst(6)) }
        }
        return Array(volatileStorage.keys)
    }

    // MARK: - GM_getResourceText

    func performGetResourceText(args: [String: Any], callbackId: String, webView: WKWebView?) {
        guard let name = args["name"] as? String else {
            resolveCallback(callbackId, result: nil, webView: webView)
            return
        }
        let text = script.resourceData[name]
        resolveCallback(callbackId, result: text, webView: webView)
    }

    // MARK: - GM_getResourceURL

    func performGetResourceURL(args: [String: Any], callbackId: String, webView: WKWebView?) {
        guard let name = args["name"] as? String else {
            resolveCallback(callbackId, result: nil, webView: webView)
            return
        }

        if let dataString = script.resourceData[name] {
            // For simplicity in native context, we return a data URL if it's text,
            // or we could bridge to a local sumi-resource:// URL if needed.
            // quoid/userscripts uses blob/data URLs.
            let encoded = dataString.data(using: .utf8)?.base64EncodedString() ?? ""
            let mimeType = "text/plain" // We'd ideally store MIME type in script.resourceData
            let dataURL = "data:\(mimeType);base64,\(encoded)"
            resolveCallback(callbackId, result: dataURL, webView: webView)
        } else {
            resolveCallback(callbackId, result: nil, webView: webView)
        }
    }

    // MARK: - GM_registerMenuCommand

    func performRegisterMenuCommand(args: [String: Any]) {
        guard let caption = args["caption"] as? String,
              let commandId = args["commandId"] as? String
        else { return }

        DispatchQueue.main.async {
            self.script.menuCommands[caption] = commandId
            NotificationCenter.default.post(name: .sumiUserScriptMenuCommandsDidChange, object: self.script)
        }
    }

    func performUnregisterMenuCommand(args: [String: Any]) {
        guard let caption = args["caption"] as? String else { return }

        DispatchQueue.main.async {
            self.script.menuCommands.removeValue(forKey: caption)
            NotificationCenter.default.post(name: .sumiUserScriptMenuCommandsDidChange, object: self.script)
        }
    }

    // MARK: - GM_addStyle

    func performSetClipboard(args: [String: Any], callbackId: String, webView: WKWebView?) {
        if let data = args["data"] as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(data, forType: .string)
        }
        resolveCallback(callbackId, result: true, webView: webView)
    }

    func performWindowClose(callbackId: String, webView: WKWebView?) {
        tabOpenHandler?.closeTab(tabId: nil)
        resolveCallback(callbackId, result: true, webView: webView)
    }

    func performWindowFocus(callbackId: String, webView: WKWebView?) {
        webView?.window?.makeKeyAndOrderFront(nil)
        resolveCallback(callbackId, result: true, webView: webView)
    }

    func performAddStyle(args: [String: Any], webView: WKWebView?) {
        guard let css = args["css"] as? String, let webView else { return }

        let escapedCSS = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let js = """
        (function() {
            var tag = document.createElement('style');
            tag.textContent = `\(escapedCSS)`;
            (document.head || document.documentElement).appendChild(tag);
        })();
        """

        DispatchQueue.main.async {
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func performOpenInTab(args: [String: Any], callbackId: String, webView: WKWebView?) {
        guard let url = args["url"] as? String else {
            rejectCallback(callbackId, error: "Missing URL", webView: webView)
            return
        }

        let active = args["active"] as? Bool ?? !(args["background"] as? Bool ?? false)
        tabOpenHandler?.openTab(url: url, background: active == false)
        resolveCallback(callbackId, result: [
            "closed": false,
            "id": UUID().uuidString
        ], webView: webView)
    }

    // MARK: - GM_notification

    func performNotification(args: [String: Any]) {
        let title = args["title"] as? String ?? "Sumi UserScript"
        let text = args["text"] as? String ?? args["details"] as? String ?? ""

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                RuntimeDiagnostics.debug(
                    "GM_notification authorization failed: \(error.localizedDescription)",
                    category: "SumiScripts"
                )
            }
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = text
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "sumi-userscript-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request) { error in
                if let error {
                    RuntimeDiagnostics.debug(
                        "GM_notification delivery failed: \(error.localizedDescription)",
                        category: "SumiScripts"
                    )
                }
            }
        }
    }

    // MARK: - JS Callbacks

    func resolveCallback(_ callbackId: String, result: Any?, webView: WKWebView?) {
        guard !callbackId.isEmpty else { return }
        runBridgeCallback(
            """
            window.__sumiGM_resolve(callbackId, result);
            """,
            arguments: [
                "callbackId": callbackId,
                "result": result ?? NSNull()
            ],
            webView: webView
        )
    }

    func rejectCallback(_ callbackId: String, error: String, webView: WKWebView?) {
        guard !callbackId.isEmpty else { return }
        runBridgeCallback(
            """
            window.__sumiGM_reject(callbackId, errorMessage);
            """,
            arguments: [
                "callbackId": callbackId,
                "errorMessage": error
            ],
            webView: webView
        )
    }

    func runBridgeCallback(
        _ source: String,
        arguments: [String: Any],
        webView: WKWebView?
    ) {
        guard let webView else { return }
        let contentWorld = self.contentWorld
        DispatchQueue.main.async {
            webView.callAsyncJavaScript(
                source,
                arguments: arguments,
                in: nil,
                in: contentWorld,
                completionHandler: nil
            )
        }
    }

}

// MARK: - Tab Handler Protocol

/// Protocol for SumiScriptsManager to provide tab operations to GM bridge.
@MainActor
protocol SumiScriptsTabHandler: AnyObject {
    func openTab(url: String, background: Bool)
    func closeTab(tabId: String?)
}

extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
