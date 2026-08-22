import AppKit
import Foundation
import WebKit

enum SumiWebPageImagePasteboard {
    @MainActor
    static func copyImage(at url: URL, from webView: WKWebView) {
        Task { @MainActor [weak webView] in
            guard let webView,
                  let data = await imageData(at: url, from: webView),
                  let image = NSImage(data: data)
            else { return }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
    }

    @MainActor
    private static func imageData(at url: URL, from webView: WKWebView) async -> Data? {
        switch url.scheme?.lowercased() {
        case "data":
            return dataURLContents(url)
        case "blob":
            return await blobContents(url, from: webView)
        case "http", "https":
            return await networkContents(url, from: webView)
        case "file":
            return try? Data(contentsOf: url)
        default:
            return nil
        }
    }

    private static func dataURLContents(_ url: URL) -> Data? {
        let value = url.absoluteString
        guard let comma = value.firstIndex(of: ",") else { return nil }
        let header = value[..<comma]
        let rawPayload = String(value[value.index(after: comma)...])
        let payload = rawPayload.removingPercentEncoding ?? rawPayload
        if header.lowercased().hasSuffix(";base64") {
            return Data(base64Encoded: payload)
        }
        return Data(payload.utf8)
    }

    @MainActor
    private static func blobContents(_ url: URL, from webView: WKWebView) async -> Data? {
        let script = """
        const response = await fetch(url);
        const bytes = new Uint8Array(await response.arrayBuffer());
        let binary = '';
        for (let offset = 0; offset < bytes.length; offset += 0x8000) {
          binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
        }
        return btoa(binary);
        """
        guard let base64 = try? await webView.callAsyncJavaScript(
            script,
            arguments: ["url": url.absoluteString],
            in: nil,
            contentWorld: .page
        ) as? String else { return nil }
        return Data(base64Encoded: base64)
    }

    @MainActor
    private static func networkContents(_ url: URL, from webView: WKWebView) async -> Data? {
        let configuration = URLSessionConfiguration.ephemeral
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        for cookie in cookies {
            configuration.httpCookieStorage?.setCookie(cookie)
        }
        var request = URLRequest(url: url)
        request.setValue(webView.url?.absoluteString, forHTTPHeaderField: "Referer")
        do {
            let (data, response) = try await URLSession(configuration: configuration).data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else { return nil }
            return data
        } catch {
            return nil
        }
    }
}
