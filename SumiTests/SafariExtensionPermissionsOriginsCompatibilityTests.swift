import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionPermissionsOriginsCompatibilityTests: XCTestCase {
    func testNormalizesHTTPURLOriginWithPortToHostPattern() {
        XCTAssertEqual(
            SafariExtensionPermissionsOriginsCompatibility
                .normalizedOriginForWebKitPermissionsAPI(
                    "http://127.0.0.1:8765/login-basic.html?cache=1"
                ),
            "http://127.0.0.1/*"
        )
        XCTAssertEqual(
            SafariExtensionPermissionsOriginsCompatibility
                .normalizedOriginForWebKitPermissionsAPI(
                    "https://Example.com:8443/accounts/login#field"
                ),
            "https://example.com/*"
        )
        XCTAssertEqual(
            SafariExtensionPermissionsOriginsCompatibility
                .normalizedOriginForWebKitPermissionsAPI(
                    "http://localhost:8765/login-basic.html"
                ),
            "http://localhost/*"
        )
    }

    func testLeavesValidMatchPatternsUnchanged() {
        let values = [
            "<all_urls>",
            "http://127.0.0.1/*",
            "https://example.com/login?next=home",
            "*://*.example.com/*",
        ]

        for value in values {
            XCTAssertEqual(
                SafariExtensionPermissionsOriginsCompatibility
                    .normalizedOriginForWebKitPermissionsAPI(value),
                value
            )
        }
    }

    func testLeavesNonHTTPAndInvalidOriginsUnchanged() {
        let values = [
            "file:///tmp/login.html",
            "webkit-extension://extension-id/page.html",
            "not a url",
            "https://[::1]:8443/login",
            "",
        ]

        for value in values {
            XCTAssertEqual(
                SafariExtensionPermissionsOriginsCompatibility
                    .normalizedOriginForWebKitPermissionsAPI(value),
                value
            )
        }
    }

    func testPrivateUserScriptSPIWrapperCreatesAssociatedPrelude() {
        let baseURL = URL(string: "webkit-extension://ext-test")!
        let script = SafariExtensionPermissionsOriginsCompatibility
            .makePreludeUserScript(associatedURL: baseURL)

        XCTAssertNotNil(script)
        XCTAssertTrue(
            script?.source.contains(
                "__sumiWebExtensionPermissionsOriginsCompatibilityInstalled"
            ) == true
        )
    }

    func testPermissionsContainsLocationHrefWithPortRendersOverlay() async throws {
        let server = try await AutofillPagesHTTPServer.start()
        addTeardownBlock {
            server.stop()
        }

        let container = try makeTestContainer()
        let profile = Profile(name: "Permissions Origins Profile")
        let browserConfiguration = BrowserConfiguration()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration
        )
        let browserManager = BrowserManager()
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installPermissionsOriginProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await manager.enableExtension(installed.id)
        let extensionContext = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        XCTAssertTrue(extensionContext.isLoaded)

        let pageURL = server.loginBasicURL
        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionPermissionsOriginsCompatibilityTests"
        )

        let tab = browserManager.tabManager.createNewTab(
            url: pageURL.absoluteString,
            in: browserManager.tabManager.currentSpace,
            activate: false,
            webViewConfigurationOverride: configuration
        )
        tab.profileId = profile.id
        tab.browserManager = browserManager

        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab._webView = webView

        manager.registerTabWithExtensionRuntime(
            tab,
            reason: "SafariExtensionPermissionsOriginsCompatibilityTests"
        )

        let didFinish = expectation(description: "page loaded")
        let delegate = NavigationDelegateBox {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate
        webView.load(URLRequest(url: pageURL, cachePolicy: .reloadIgnoringLocalCacheData))
        await fulfillment(of: [didFinish], timeout: 5)
        webView.navigationDelegate = nil

        let result = try await waitForPermissionsOverlayResult(in: webView)
        XCTAssertEqual(result, "true")
    }

    private func waitForPermissionsOverlayResult(
        in webView: WKWebView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> String? {
        let script = """
        (() => {
          const overlay = document.getElementById('sumi-permissions-origin-overlay');
          if (overlay) {
            return overlay.dataset.result || 'missing-result';
          }
          return document.documentElement.dataset.sumiPermissionsOriginError || null;
        })();
        """

        for _ in 0..<50 {
            if let result = try await evaluateString(script, in: webView) {
                return result
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTFail("Timed out waiting for permissions origin overlay", file: file, line: line)
        return nil
    }

    private func evaluateString(
        _ script: String,
        in webView: WKWebView
    ) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if result is NSNull {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: result as? String)
            }
        }
    }

    private func installPermissionsOriginProbeExtension(
        manager: ExtensionManager,
        scratchDirectory: URL
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(
            "PermissionsOriginProbeExtension",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "PermissionsOriginProbeExtension",
            "version": "1.0",
            "host_permissions": ["<all_urls>"],
            "content_scripts": [[
                "matches": ["<all_urls>"],
                "js": ["content.js"],
                "run_at": "document_idle",
            ]],
            "web_accessible_resources": [[
                "resources": ["probe.html", "probe.js"],
                "matches": ["<all_urls>"],
            ]],
        ]
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: manifestURL, options: [.atomic])

        let contentScript = """
        (() => {
          const renderResult = (result, metadata) => {
            const overlay = document.createElement('div');
            overlay.id = 'sumi-permissions-origin-overlay';
            overlay.dataset.result = String(result);
            overlay.dataset.metadata = JSON.stringify(metadata || {});
            overlay.style.cssText = [
              'position:fixed',
              'left:0',
              'top:0',
              'width:121px',
              'height:43px',
              'z-index:2147483647',
              'background:rgb(0, 128, 255)'
            ].join(';');
            document.documentElement.appendChild(overlay);
          };

          try {
            const api = globalThis.browser || globalThis.chrome;
            const runtime = api && api.runtime;
            if (!runtime || typeof runtime.getURL !== 'function') {
              throw new Error('runtime.getURL unavailable in content script');
            }

            const expectedSource = 'sumi-permissions-origin-probe';
            window.addEventListener('message', (event) => {
              if (!event.data || event.data.source !== expectedSource) {
                return;
              }
              if (event.data.error) {
                document.documentElement.dataset.sumiPermissionsOriginError =
                  event.data.error;
                return;
              }
              renderResult(event.data.result, event.data);
            });

            const iframe = document.createElement('iframe');
            iframe.id = 'sumi-permissions-origin-probe-frame';
            iframe.src = runtime.getURL('probe.html') +
              '?pageURL=' + encodeURIComponent(location.href);
            iframe.style.cssText = [
              'position:fixed',
              'left:-1000px',
              'top:-1000px',
              'width:10px',
              'height:10px',
              'border:0'
            ].join(';');
            document.documentElement.appendChild(iframe);

            setTimeout(() => {
              if (!document.getElementById('sumi-permissions-origin-overlay')) {
                document.documentElement.dataset.sumiPermissionsOriginError =
                  'timed out waiting for extension frame response';
              }
            }, 3000);
          } catch (error) {
            document.documentElement.dataset.sumiPermissionsOriginError =
              String(error && (error.message || error));
          }
        })();
        """
        try Data(contentScript.utf8)
            .write(to: directoryURL.appendingPathComponent("content.js"), options: [.atomic])

        let probeHTML = """
        <!doctype html>
        <meta charset="utf-8">
        <script src="probe.js"></script>
        """
        try Data(probeHTML.utf8)
            .write(to: directoryURL.appendingPathComponent("probe.html"), options: [.atomic])

        let probeScript = """
        (async () => {
          const source = 'sumi-permissions-origin-probe';
          try {
            const pageURL = new URL(location.href).searchParams.get('pageURL');
            const api = globalThis.browser || globalThis.chrome;
            const hasPermissionsAPI =
              !!(api && api.permissions && typeof api.permissions.contains === 'function');
            if (!hasPermissionsAPI) {
              throw new Error('permissions.contains unavailable in extension frame');
            }
            const result = await api.permissions.contains({
              origins: [pageURL]
            });
            parent.postMessage({
              source,
              result: String(result),
              hasPermissionsAPI,
              preludeInstalled:
                globalThis.__sumiWebExtensionPermissionsOriginsCompatibilityInstalled === true
            }, '*');
          } catch (error) {
            parent.postMessage({
              source,
              error: String(error && (error.message || error))
            }, '*');
          }
        })();
        """
        try Data(probeScript.utf8)
            .write(to: directoryURL.appendingPathComponent("probe.js"), options: [.atomic])

        return try await manager.performInstallation(
            from: directoryURL,
            enableOnInstall: false
        )
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private final class NavigationDelegateBox: NSObject, WKNavigationDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            onFinish()
        }
    }
}
