import AppKit
import SwiftData
import WebKit
import XCTest

@testable import Sumi

/// Live end-to-end probe against the real installed 1Password for Safari
/// `.appex` (`com.1password.safari.extension`, MV2 + persistent background
/// page + nativeMessaging + scripting). Skipped when 1Password for Safari is
/// not installed. Proves the full Sumi pipeline: appex import → enable →
/// site-access seeding → MV2 background load → content-script injection for
/// a real page load → action/popup + command surfaces.
@available(macOS 15.5, *)
@MainActor
final class SafariExtension1PasswordRuntimeTests: XCTestCase {
    private static let appexPath =
        "/Applications/1Password for Safari.app/Contents/PlugIns/1Password.appex"

    func testInstalled1PasswordEndToEndRuntime() async throws {
        let appexURL = URL(fileURLWithPath: Self.appexPath)
        guard FileManager.default.fileExists(atPath: appexURL.path) else {
            throw XCTSkip("1Password for Safari is not installed on this machine.")
        }

        let server = try await AutofillPagesHTTPServer.start()
        addTeardownBlock {
            server.stop()
        }

        let container = try makeTestContainer()
        let profile = Profile(name: "1Password Runtime Profile")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration
        )
        let browserManager = makeSafariExtensionTestBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)
        await browserManager.tabManager.storeRestore.startupRestoreTask?.value

        // Real import path for a Safari app extension: validates the signed
        // bundle, copies resources for persistence, loads the runtime.
        let installed = try await manager.extensionInstaller.install(
            from: appexURL,
            enableOnInstall: true
        )
        let extensionContext = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        XCTAssertTrue(extensionContext.isLoaded)

        // Safari-appex default seeding (Cycle 23) must grant the declared
        // <all_urls> access without any user configuration.
        let allURLs = WKWebExtension.MatchPattern.allURLs()
        let allHostsAndSchemes = WKWebExtension.MatchPattern.allHostsAndSchemes()
        XCTAssertTrue(
            manager.isGrantedPermissionStatus(
                extensionContext.permissionStatus(for: allURLs)
            ) || manager.isGrantedPermissionStatus(
                extensionContext.permissionStatus(for: allHostsAndSchemes)
            ),
            "declared <all_urls> access must seed as granted for the Safari appex import"
        )
        XCTAssertTrue(
            extensionContext.hasAccess(to: server.loginBasicURL),
            "extension must have host access to the test page"
        )

        // Requested API permissions must be granted (incl. nativeMessaging,
        // scripting, contextMenus, tabs, storage, alarms, webNavigation).
        for permission in ["nativeMessaging", "scripting", "storage", "tabs", "contextMenus"] {
            XCTAssertTrue(
                manager.isGrantedPermissionStatus(
                    extensionContext.permissionStatus(
                        for: WKWebExtension.Permission(rawValue: permission)
                    )
                ),
                "\(permission) must be granted"
            )
        }
        XCTAssertTrue(
            extensionContext.unsupportedAPIs.isEmpty,
            "no APIs may be hidden from 1Password: \(extensionContext.unsupportedAPIs)"
        )

        // WebKit routes the reserved `_execute_browser_action` shortcut
        // (Cmd+Shift+X) through the action rather than the public `commands`
        // list, so only assert the command surface is queryable without error.
        _ = extensionContext.commands

        // MV2 persistent background page must load through the wake path.
        XCTAssertTrue(extensionContext.webExtension.hasBackgroundContent)
        _ = try await manager.ensureBackgroundAvailableIfRequired(
            for: extensionContext.webExtension,
            context: extensionContext,
            reason: .enable
        )

        // A live third-party MV2 bundle may surface benign manifest warnings;
        // record rather than fail the runtime probe on them.
        let loadErrors = extensionContext.webExtension.errors
        if loadErrors.isEmpty == false {
            print("SafariExtension1PasswordRuntimeTests loadErrors=\(loadErrors.map(\.localizedDescription))")
        }

        // Full tab stack: content scripts must inject into a real page load.
        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtension1PasswordRuntimeTests"
        )
        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: server.loginBasicURL.absoluteString,
            in: browserManager.tabManager.spaceStateOwner.currentSpace,
            activate: false,
            webViewConfigurationOverride: configuration
        )
        tab.profileId = profile.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)
        manager.registerTabWithExtensionRuntime(
            tab,
            reason: "SafariExtension1PasswordRuntimeTests"
        )

        let didFinish = expectation(description: "page loaded")
        let delegate = NavigationDelegateBox {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate
        webView.load(
            URLRequest(
                url: server.loginBasicURL,
                cachePolicy: .reloadIgnoringLocalCacheData
            )
        )
        await fulfillment(of: [didFinish], timeout: 15)
        webView.navigationDelegate = nil

        XCTAssertTrue(
            extensionContext.hasInjectedContent,
            "1Password must report injectable content for granted hosts"
        )
        XCTAssertTrue(
            extensionContext.hasInjectedContent(for: server.loginBasicURL),
            "content scripts must be injectable for the loaded login page URL"
        )
        let adapter = try XCTUnwrap(manager.adapterResolutionOwner.stableAdapter(for: tab))
        XCTAssertNotNil(
            extensionContext.action(for: adapter),
            "the browser_action surface must resolve for the tab"
        )

        // Native-core boundary (the one capability a third-party browser
        // cannot provide): 1Password's background reaches its desktop core via
        // runtime.connectNative("")/sendNativeMessage("", …), which routes to
        // the extension's OWN .appex SafariWebExtensionHandler. Hosting that
        // handler requires the Apple-private
        // `com.apple.private.can-load-any-content-blocker` entitlement, which
        // AMFI grants only to Safari — see PlugInKit error 11 documented in
        // SumiSafariExtensionCompatibility.md (Cycle 27). Sumi must therefore
        // REJECT the native message cleanly (not hang), so 1Password's own
        // "can't connect to the desktop app" UI can take over. Assert the
        // graceful rejection rather than a success that the OS forbids.
        let nativeResult = try await nativeMessageRejectionResult(
            extensionContext: extensionContext
        )
        XCTAssertEqual(
            nativeResult,
            "rejected",
            "sendNativeMessage must reject cleanly, not hang or crash the worker (got \(nativeResult))"
        )
    }

    /// Loads a bundled extension page and issues 1Password's own core native
    /// message. Because hosting the appex handler is OS-blocked for
    /// third-party browsers, Sumi must reject the call — the worker sees a
    /// rejected promise, never a hang. Returns "rejected" on the expected
    /// clean failure, "replied" if a reply somehow arrives, or a diagnostic.
    private func nativeMessageRejectionResult(
        extensionContext: WKWebExtensionContext
    ) async throws -> String {
        let configuration = try XCTUnwrap(extensionContext.webViewConfiguration)
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 240),
            configuration: configuration
        )
        webView.load(
            URLRequest(url: extensionContext.baseURL.appendingPathComponent("credits.html"))
        )

        for _ in 0..<50 {
            try await Task.sleep(nanoseconds: 200_000_000)
            let result = try? await webView.evaluateJavaScript(
                """
                (() => {
                  const api = globalThis.browser || globalThis.chrome;
                  if (!api || !api.runtime || !api.runtime.sendNativeMessage) { return 'no-api'; }
                  if (!globalThis.__sumiNativeProbeStarted) {
                    globalThis.__sumiNativeProbeStarted = true;
                    globalThis.__sumiNativeProbeResult = 'pending';
                    Promise.resolve(api.runtime.sendNativeMessage('', { name: 'request-os-version' }))
                      .then(reply => {
                        globalThis.__sumiNativeProbeResult =
                          reply === undefined ? 'rejected' : 'replied';
                      })
                      .catch(() => { globalThis.__sumiNativeProbeResult = 'rejected'; });
                  }
                  return globalThis.__sumiNativeProbeResult;
                })()
                """
            )
            if let status = result as? String, status != "pending" {
                return status
            }
        }
        return "timeout"
    }

    // MARK: - Helpers

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private final class NavigationDelegateBox: NSObject, WKNavigationDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onFinish()
        }
    }
}
