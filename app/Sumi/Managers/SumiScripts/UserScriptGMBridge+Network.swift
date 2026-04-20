//
//  UserScriptGMBridge+Network.swift
//  Sumi
//
//  GM_xmlhttpRequest / GM.download (URLSession).
//

import Foundation
import WebKit

extension UserScriptGMBridge {

    // MARK: - GM_xmlhttpRequest (native URLSession, bypasses CORS)

    func performXMLHttpRequest(args: [String: Any], callbackId: String, webView: WKWebView?) {
        guard let urlString = args["url"] as? String,
              let url = URL(string: urlString)
        else {
            rejectCallback(callbackId, error: "Invalid URL", webView: webView)
            return
        }

        if !script.metadata.connects.isEmpty {
            let host = url.host ?? ""
            let isAllowed = script.metadata.connects.contains { connectDomain in
                if connectDomain == "*" { return true }
                return host == connectDomain || host.hasSuffix(".\(connectDomain)")
            }
            if !isAllowed {
                rejectCallback(callbackId, error: "Domain not in @connect whitelist: \(host)", webView: webView)
                return
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = (args["method"] as? String)?.uppercased() ?? "GET"

        if let headers = args["headers"] as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        if let timeout = args["timeout"] as? Int, timeout > 0 {
            request.timeoutInterval = TimeInterval(timeout) / 1000.0
        }

        if let data = args["data"] as? String {
            request.httpBody = data.data(using: .utf8)
        }

        if let mimeOverride = args["overrideMimeType"] as? String {
            request.setValue(mimeOverride, forHTTPHeaderField: "Accept")
        }

        let responseType = args["responseType"] as? String ?? ""
        let requestId = callbackId

        let task = URLSession.shared.dataTask(with: request) { [weak self, weak webView] data, response, error in
            guard let self, let webView else { return }

            self.activeTasks.removeValue(forKey: requestId)

            if let error {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    self.sendXHREvent("onabort", callbackId: callbackId, response: [
                        "status": 0,
                        "statusText": "abort",
                        "responseText": "",
                        "readyState": 4
                    ], webView: webView)
                    return
                }

                self.sendXHREvent("onerror", callbackId: callbackId, response: [
                    "status": 0,
                    "statusText": error.localizedDescription,
                    "responseText": "",
                    "readyState": 4
                ], webView: webView)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.sendXHREvent("onerror", callbackId: callbackId, response: [
                    "status": 0,
                    "statusText": "No response",
                    "readyState": 4
                ], webView: webView)
                return
            }

            let headers = httpResponse.allHeaderFields.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")

            var responseText = ""
            var responseValue: Any = ""

            if let data {
                switch responseType {
                case "json":
                    responseText = String(data: data, encoding: .utf8) ?? ""
                    responseValue = responseText
                case "arraybuffer", "blob":
                    responseValue = data.base64EncodedString()
                    responseText = ""
                default:
                    responseText = String(data: data, encoding: .utf8) ?? ""
                    responseValue = responseText
                }
            }

            let responseObj: [String: Any] = [
                "status": httpResponse.statusCode,
                "statusText": HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                "responseHeaders": headers,
                "responseText": responseText,
                "response": responseValue,
                "responseType": responseType,
                "responseURL": httpResponse.url?.absoluteString ?? urlString,
                "finalUrl": httpResponse.url?.absoluteString ?? urlString,
                "readyState": 4
            ]

            self.sendXHREvent("onload", callbackId: callbackId, response: responseObj, webView: webView)
        }

        activeTasks[requestId] = task
        task.resume()

        sendXHREvent("onloadstart", callbackId: callbackId, response: [
            "readyState": 1,
            "status": 0,
            "statusText": ""
        ], webView: webView)
    }

    func performXMLHttpRequestAbort(args: [String: Any]) {
        if let requestId = args["requestId"] as? String {
            activeTasks[requestId]?.cancel()
            activeTasks.removeValue(forKey: requestId)
        }
    }

    func performDownload(args: [String: Any], callbackId: String, webView: WKWebView?) {
        let details = args["details"] as? [String: Any] ?? args
        guard let rawURL = details["url"] as? String,
              let url = URL(string: rawURL, relativeTo: webView?.url)?.absoluteURL
        else {
            rejectCallback(callbackId, error: "Invalid download URL", webView: webView)
            return
        }

        let filename = (details["name"] as? String)
            ?? url.lastPathComponent.nonEmpty
            ?? "download"
        let requestId = callbackId.isEmpty ? UUID().uuidString : callbackId
        let task = URLSession.shared.downloadTask(with: url) { [weak self, weak webView] tempURL, response, error in
            guard let self else { return }
            self.activeTasks.removeValue(forKey: requestId)

            if let error {
                self.rejectCallback(requestId, error: error.localizedDescription, webView: webView)
                return
            }
            guard let tempURL else {
                self.rejectCallback(requestId, error: "No downloaded file", webView: webView)
                return
            }

            let destination = Self.uniqueDownloadDestination(filename: filename)
            do {
                try FileManager.default.moveItem(at: tempURL, to: destination)
                self.resolveCallback(requestId, result: [
                    "status": 200,
                    "filename": destination.path,
                    "finalUrl": response?.url?.absoluteString ?? url.absoluteString
                ], webView: webView)
            } catch {
                self.rejectCallback(requestId, error: error.localizedDescription, webView: webView)
            }
        }
        activeTasks[requestId] = task
        task.resume()
    }

    private static func uniqueDownloadDestination(filename: String) -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let cleanName = filename.replacingOccurrences(of: "/", with: "_")
        var destination = downloads.appendingPathComponent(cleanName)
        let ext = destination.pathExtension
        let base = destination.deletingPathExtension().lastPathComponent
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = downloads.appendingPathComponent(
                "\(base) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
            )
            counter += 1
        }
        return destination
    }

    func sendXHREvent(_ event: String, callbackId: String, response: [String: Any], webView: WKWebView?) {
        runBridgeCallback(
            """
            window.__sumiGM_xhrCallback(callbackId, eventName, response);
            """,
            arguments: [
                "callbackId": callbackId,
                "eventName": event,
                "response": response
            ],
            webView: webView
        )
    }
}
