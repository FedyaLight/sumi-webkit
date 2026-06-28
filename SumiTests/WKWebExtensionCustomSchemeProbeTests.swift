import WebKit
import XCTest

@available(macOS 15.5, *)
@MainActor
final class WKWebExtensionCustomSchemeProbeTests: XCTestCase {
    func testSafariWebExtensionResourceSchemeEndToEnd() async throws {
        try await verifyCustomResourceScheme("safari-web-extension")
    }

    private func verifyCustomResourceScheme(_ scheme: String) async throws {
        WKWebExtension.MatchPattern.registerCustomURLScheme(scheme)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Custom Scheme Probe",
            "version": "1.0",
            "options_page": "options.html",
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: directory.appendingPathComponent("manifest.json"))
        try Data("<title>custom-scheme-ok</title>".utf8)
            .write(to: directory.appendingPathComponent("options.html"))

        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = "probe-\(scheme)"
        context.baseURL = try XCTUnwrap(URL(string: "\(scheme)://probe-host"))

        let controller = WKWebExtensionController(configuration: .nonPersistent())
        try controller.load(context)
        defer { try? controller.unload(context) }

        let optionsURL = try XCTUnwrap(context.optionsPageURL)
        XCTAssertEqual(context.baseURL.scheme, scheme)
        XCTAssertEqual(optionsURL.scheme, scheme)
        XCTAssertIdentical(controller.extensionContext(for: context.baseURL), context)
        XCTAssertIdentical(controller.extensionContext(for: optionsURL), context)

        let configuration = try XCTUnwrap(context.webViewConfiguration)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let didFinish = expectation(description: "Loaded \(scheme) extension resource")
        let navigationDelegate = CustomSchemeProbeNavigationDelegate {
            didFinish.fulfill()
        }
        webView.navigationDelegate = navigationDelegate
        webView.load(URLRequest(url: optionsURL))
        await fulfillment(of: [didFinish], timeout: 5)

        let locationProtocol = try await webView.evaluateJavaScript("location.protocol") as? String
        let title = try await webView.evaluateJavaScript("document.title") as? String
        XCTAssertEqual(locationProtocol, "\(scheme):")
        XCTAssertEqual(title, "custom-scheme-ok")
    }
}

@available(macOS 15.5, *)
@MainActor
private final class CustomSchemeProbeNavigationDelegate: NSObject, WKNavigationDelegate {
    var didFinish: () -> Void

    init(didFinish: @escaping () -> Void) {
        self.didFinish = didFinish
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) { // swiftlint:disable:this implicitly_unwrapped_optional
        didFinish()
    }
}
