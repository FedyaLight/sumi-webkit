import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionInlineOverlayRuntimeTests: XCTestCase {
    func testExtensionIframeCanResizeThroughRuntimePortAndPostMessage() async throws {
        let server = try await AutofillPagesHTTPServer.start()
        addTeardownBlock {
            server.stop()
        }

        let container = try makeTestContainer()
        let profile = Profile(name: "Inline Overlay Runtime Profile")
        let browserConfiguration = BrowserConfiguration()
        let fixture = makeSafariExtensionManagerTestFixture(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = fixture.manager
        let inspection = fixture.inspection
        let attachedRuntime = fixture.attachedRuntime
        let windowRegistry = WindowRegistry()
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile,
            windowRegistry: windowRegistry
        )
        manager.attach(browserManager: browserManager)
        await browserManager.tabManager.storeRestore.startupRestoreTask?.value

        let installed = try await installSafariStyleInlineOverlayProbeExtension(
            inspection: inspection,
            scratchDirectory: makeScratchDirectory()
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        inspection.actionPolicy.siteAccess.setDefaultSiteAccess(
            .allow,
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(
            inspection.contextState.profileState.context(
                for: installed.id,
                profileId: profile.id
            )
        )
        XCTAssertTrue(extensionContext.isLoaded)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionInlineOverlayRuntimeTests"
        )

        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: server.loginBasicURL.absoluteString,
            in: browserManager.tabManager.spaceStateOwner.currentSpace,
            activate: false,
            webViewConfigurationOverride: configuration
        )
        tab.profileId = profile.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = tab.spaceId
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        attachedRuntime.runtime.normalTabs.tabRegistration.register(
            tab,
            reason: "SafariExtensionInlineOverlayRuntimeTests"
        )
        XCTAssertTrue(
            attachedRuntime.runtime.normalTabs.publishedTabs
                .containsPublishedTab(tab)
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
        await fulfillment(of: [didFinish], timeout: 5)
        webView.navigationDelegate = nil

        let result = try await waitForInlineOverlayResult(in: webView)
        XCTAssertEqual(result.status, "resized", result.detail)
        XCTAssertGreaterThan(result.height, 20, result.detail)
        XCTAssertTrue(
            result.detail.contains("safari-web-extension:"),
            result.detail
        )
        XCTAssertTrue(
            result.detail.contains("\"runtimeConnectWrapped\":false"),
            result.detail
        )
    }

    private func waitForInlineOverlayResult(
        in webView: WKWebView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> (status: String, height: Double, detail: String) {
        let json = try await webView.callAsyncJavaScript(
            """
            const readResult = () => {
                const root = document.documentElement;
                const iframe = document.getElementById('sumi-inline-overlay-probe-frame');
                return JSON.stringify({
                    status: root.dataset.sumiInlineOverlayStatus || null,
                    detail: root.dataset.sumiInlineOverlayDetail || '',
                    height: iframe ? iframe.getBoundingClientRect().height : 0,
                    inlineHeight: iframe ? getComputedStyle(iframe).height : '',
                    backgroundMessage: root.dataset.sumiInlineBackgroundMessage || ''
                });
            };
            const isSettled = value => {
                const status = JSON.parse(value).status;
                return status === 'resized' || (status && status.startsWith('error:'));
            };
            const existingResult = readResult();
            if (isSettled(existingResult)) {
                return existingResult;
            }
            return await new Promise(resolve => {
                let timeoutID = null;
                const observer = new MutationObserver(() => {
                    const observedResult = readResult();
                    if (isSettled(observedResult)) {
                        finish(observedResult);
                    }
                });
                const finish = value => {
                    observer.disconnect();
                    if (timeoutID !== null) {
                        clearTimeout(timeoutID);
                    }
                    resolve(value);
                };
                observer.observe(document.documentElement, {
                    attributes: true,
                    attributeFilter: ['data-sumi-inline-overlay-status']
                });
                timeoutID = setTimeout(() => finish(readResult()), 7000);
            });
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String ?? ""
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? String
        else {
            XCTFail("Timed out waiting for inline overlay resize", file: file, line: line)
            return ("timeout", 0, "")
        }
        return (
            status,
            object["height"] as? Double ?? 0,
            object["detail"] as? String ?? ""
        )
    }

    private func installSafariStyleInlineOverlayProbeExtension(
        inspection: ExtensionManagerTestInspection,
        scratchDirectory: URL
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(
            "InlineOverlayProbeExtension",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "InlineOverlayProbeExtension",
            "version": "1.0",
            "permissions": ["<all_urls>", "storage"],
            "background": [
                "scripts": ["background.js"],
                "persistent": true,
            ],
            "content_scripts": [[
                "matches": ["<all_urls>"],
                "js": ["content.js"],
                "run_at": "document_idle",
            ]],
            "sandbox": [
                "pages": ["overlay/menu-list.html"],
                "content_security_policy": "sandbox allow-scripts; script-src 'self'",
            ],
            "web_accessible_resources": [
                "overlay/menu.html",
                "overlay/menu.js",
                "overlay/menu-list.html",
                "overlay/menu-list.js",
                "overlay/menu-list.css",
            ],
        ]
        try writeJSON(manifest, to: directoryURL.appendingPathComponent("manifest.json"))

        let overlayDirectory = directoryURL.appendingPathComponent(
            "overlay",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: overlayDirectory,
            withIntermediateDirectories: true
        )

        let backgroundScript = """
        (() => {
          const api = globalThis.browser || globalThis.chrome;
          const probeState = {
            connects: 0,
            lastPortName: null,
            lastSenderTabId: null,
            lastMessage: null
          };
          api.runtime.onConnect.addListener((port) => {
            if (!port) {
              return;
            }
            probeState.connects += 1;
            probeState.lastPortName = port.name || null;
            probeState.lastSenderTabId =
              port.sender && port.sender.tab ? port.sender.tab.id : null;
            if (port.name !== 'autofill-inline-menu-list-port') {
              probeState.lastMessage = {
                command: 'unexpectedPortName',
                portName: port.name || null
              };
              port.postMessage(probeState.lastMessage);
              return;
            }
            if (!port.sender || !port.sender.tab || port.sender.tab.id == null) {
              probeState.lastMessage = {
                command: 'missingSenderTab',
                sender: port.sender || null
              };
              port.postMessage(probeState.lastMessage);
              return;
            }
            const iframeUrl = api.runtime.getURL('overlay/menu-list.html');
            const styleSheetUrl = api.runtime.getURL('overlay/menu-list.css');
            const extensionOrigin = new URL(api.runtime.getURL('')).origin;
            probeState.lastMessage = {
              command: 'initAutofillInlineMenuList',
              portName: port.name,
              iframeUrl,
              styleSheetUrl,
              extensionOrigin,
              pageTitle: 'Probe inline menu list',
              connectorPortName: 'autofill-inline-menu-list-message-connector',
              senderTabId: port.sender.tab.id,
              items: [{ text: 'Probe login item' }]
            };
            port.postMessage(probeState.lastMessage);
          });
          api.runtime.onMessage.addListener((message, sender, sendResponse) => {
            if (!message || message.command !== 'sumi-inline-background-ping') {
              return;
            }
            sendResponse({
              ok: true,
              url: globalThis.location && globalThis.location.href,
              runtimeURL: api.runtime.getURL('overlay/menu-list.html'),
              runtimeURLProtocol: new URL(api.runtime.getURL('overlay/menu-list.html')).protocol,
              probeState,
              connectNative:
                typeof api.runtime.connect === 'function' &&
                api.runtime.connect.__sumiRuntimeConnectCompatibilityWrapped !== true,
              onConnectNative:
                api.runtime.onConnect &&
                api.runtime.onConnect.addListener &&
                api.runtime.onConnect.addListener.__sumiRuntimeConnectCompatibilityWrapped !== true
            });
            return true;
          });
        })();
        """
        try Data(backgroundScript.utf8)
            .write(to: directoryURL.appendingPathComponent("background.js"), options: [.atomic])

        let contentScript = """
        (() => {
          const setStatus = (status, detail) => {
            document.documentElement.dataset.sumiInlineOverlayStatus = status;
            document.documentElement.dataset.sumiInlineOverlayDetail =
              JSON.stringify(detail || {});
          };
          const setBackgroundMessage = (status, detail) => {
            document.documentElement.dataset.sumiInlineBackgroundMessage =
              JSON.stringify(Object.assign({ status }, detail || {}));
          };

          try {
            const api = globalThis.browser || globalThis.chrome;
            const runtime = api && api.runtime;
            if (!runtime || typeof runtime.getURL !== 'function') {
              throw new Error('runtime.getURL unavailable in content script');
            }
            if (typeof runtime.connect !== 'function') {
              throw new Error('runtime.connect unavailable in content script');
            }
            const runtimeConnectWrapped = () =>
              Boolean(
                runtime.connect &&
                runtime.connect.__sumiRuntimeConnectCompatibilityWrapped === true
              );
            if (typeof runtime.sendMessage === 'function') {
              runtime.sendMessage(
                { command: 'sumi-inline-background-ping' },
                (response) => {
                  const error = runtime.lastError && runtime.lastError.message;
                  setBackgroundMessage(error ? 'error' : 'response', {
                    error: error || null,
                    response: response || null
                  });
                }
              );
            } else {
              setBackgroundMessage('unavailable');
            }

            const token = 'probe-token-' + Math.random().toString(16).slice(2);
            const extensionOrigin = runtime.getURL('').replace(/\\/$/, '');
            const outerFrameURL = runtime.getURL('overlay/menu.html');
            const iframe = document.createElement('iframe');
            document.documentElement.dataset.sumiInlineRuntimeURL = outerFrameURL;
            document.documentElement.dataset.sumiInlineRuntimeURLProtocol =
              new URL(outerFrameURL).protocol;
            iframe.id = 'sumi-inline-overlay-probe-frame';
            iframe.src = outerFrameURL;
            iframe.style.cssText = [
              'position:fixed',
              'left:32px',
              'top:32px',
              'width:260px',
              'height:0px',
              'min-width:260px',
              'border:1px solid rgb(0,128,255)',
              'z-index:2147483647',
              'overflow:hidden',
              'opacity:1'
            ].join(';');

            window.addEventListener('message', (event) => {
              if (event.source !== iframe.contentWindow) {
                return;
              }
              const message = event.data || {};
              if (message.token !== token) {
                setStatus('error:token-mismatch', {
                  origin: event.origin,
                  command: message.command || null
                });
                return;
              }
              if (message.command !== 'updateAutofillInlineMenuListHeight') {
                setStatus('error:unexpected-command', {
                  origin: event.origin,
                  command: message.command || null
                });
                return;
              }
              Object.assign(iframe.style, message.styles || {});
              setStatus('resized', {
                origin: event.origin,
                height: iframe.style.height,
                runtimeURL: outerFrameURL,
                runtimeURLProtocol: new URL(outerFrameURL).protocol,
                iframeSrc: iframe.src,
                extensionOrigin,
                runtimeConnectWrapped: runtimeConnectWrapped()
              });
            });

            const connectPort = () => {
              const port = runtime.connect({
                name: 'autofill-inline-menu-list-port'
              });
              setStatus('port-connected', { extensionOrigin });
              port.onDisconnect.addListener(() => {
                const error = runtime.lastError && runtime.lastError.message;
                setStatus('error:port-disconnected', { error: error || null });
              });
              port.onMessage.addListener((message) => {
                if (!message || message.command !== 'initAutofillInlineMenuList') {
                  setStatus('error:unexpected-port-message', {
                    message: message || null
                  });
                  return;
                }
                if (!iframe.contentWindow) {
                  setStatus('error:iframe-window-missing');
                  return;
                }
                iframe.contentWindow.postMessage(
                  Object.assign({}, message, { token, portKey: 'probe-port-key' }),
                  extensionOrigin
                );
                setStatus('init-forwarded', {
                  command: message && message.command,
                  iframeUrl: message.iframeUrl || null,
                  iframeUrlProtocol: message.iframeUrl
                    ? new URL(message.iframeUrl).protocol
                    : null,
                  extensionOrigin
                });
              });
            };

            iframe.addEventListener('load', () => {
              if (document.documentElement.dataset.sumiInlineOverlayStatus === 'created') {
                setStatus('iframe-loaded', { extensionOrigin });
              }
              connectPort();
            });
            document.documentElement.appendChild(iframe);
            setStatus('created', { extensionOrigin });

            setTimeout(() => {
              const current = document.documentElement.dataset.sumiInlineOverlayStatus;
              if (current !== 'resized' && !String(current).startsWith('error:')) {
                const finishTimeout = () => {
                  setStatus('error:timeout', {
                    current,
                    runtimeConnectWrapped: runtimeConnectWrapped(),
                    backgroundMessage:
                      document.documentElement.dataset.sumiInlineBackgroundMessage || null
                  });
                };
                if (runtime && typeof runtime.sendMessage === 'function') {
                  runtime.sendMessage(
                    { command: 'sumi-inline-background-ping' },
                    (response) => {
                      const error = runtime.lastError && runtime.lastError.message;
                      setBackgroundMessage(error ? 'error' : 'response', {
                        error: error || null,
                        response: response || null
                      });
                      finishTimeout();
                    }
                  );
                } else {
                  finishTimeout();
                }
              }
            }, 5000);
          } catch (error) {
            setStatus('error:exception', String(error && (error.message || error)));
          }
        })();
        """
        try Data(contentScript.utf8)
            .write(to: directoryURL.appendingPathComponent("content.js"), options: [.atomic])

        let overlayHTML = """
        <!doctype html>
        <meta charset="utf-8">
        <title>Inline overlay probe</title>
        <style>
        html, body { margin: 0; padding: 0; }
        </style>
        <script src="menu.js"></script>
        """
        try Data(overlayHTML.utf8)
            .write(to: overlayDirectory.appendingPathComponent("menu.html"), options: [.atomic])

        let overlayScript = """
        (() => {
          let token = null;
          let messageOrigin = null;
          let inlineMenuPageIframe = null;

          const extensionProtocols = new Set([
            'chrome-extension:',
            'moz-extension:',
            'safari-web-extension:'
          ]);

          const postToParent = (message) => {
            if (!token || !messageOrigin) {
              return;
            }
            parent.postMessage(Object.assign({}, message, { token }), messageOrigin);
          };

          const isExtensionUrlWithOrigin = (url, expectedOrigin) => {
            try {
              const parsed = new URL(url);
              if (!extensionProtocols.has(parsed.protocol)) {
                return false;
              }
              return parsed.origin === expectedOrigin ||
                parsed.href.startsWith(expectedOrigin + '/');
            } catch (_) {
              return false;
            }
          };

          window.addEventListener('message', (event) => {
            if (event.source !== parent) {
              const message = event.data || {};
              if (inlineMenuPageIframe &&
                  event.source === inlineMenuPageIframe.contentWindow &&
                  message.token === token) {
                postToParent(message);
              }
              return;
            }
            if (messageOrigin && event.origin !== messageOrigin) {
              return;
            }
            messageOrigin = event.origin;

            const message = event.data || {};
            if (message.command !== 'initAutofillInlineMenuList' || !message.token) {
              return;
            }
            token = message.token;

            const expectedOrigin = message.extensionOrigin;
            if (!isExtensionUrlWithOrigin(message.iframeUrl, expectedOrigin)) {
              postToParent({
                command: 'probeError',
                reason: 'iframe-url-rejected',
                iframeUrl: message.iframeUrl || null,
                extensionOrigin: expectedOrigin || null,
                parsedProtocol: message.iframeUrl
                  ? new URL(message.iframeUrl).protocol
                  : null
              });
              return;
            }
            if (!isExtensionUrlWithOrigin(message.styleSheetUrl, expectedOrigin)) {
              postToParent({
                command: 'probeError',
                reason: 'stylesheet-url-rejected',
                styleSheetUrl: message.styleSheetUrl || null,
                extensionOrigin: expectedOrigin || null
              });
              return;
            }

            inlineMenuPageIframe = document.createElement('iframe');
            inlineMenuPageIframe.setAttribute('sandbox', 'allow-scripts');
            inlineMenuPageIframe.setAttribute('src', message.iframeUrl);
            inlineMenuPageIframe.style.cssText = [
              'position:fixed',
              'left:0',
              'top:0',
              'width:100%',
              'height:100%',
              'border:0',
              'margin:0',
              'padding:0'
            ].join(';');
            inlineMenuPageIframe.addEventListener('load', () => {
              inlineMenuPageIframe.contentWindow.postMessage(
                Object.assign({}, message, { token }),
                '*'
              );
            }, { once: true });
            document.body.appendChild(inlineMenuPageIframe);
          });
        })();
        """
        try Data(overlayScript.utf8)
            .write(to: overlayDirectory.appendingPathComponent("menu.js"), options: [.atomic])

        let listHTML = """
        <!doctype html>
        <meta charset="utf-8">
        <title>Inline overlay list probe</title>
        <style>
        html, body { margin: 0; padding: 0; }
        </style>
        <script src="menu-list.js"></script>
        """
        try Data(listHTML.utf8)
            .write(to: overlayDirectory.appendingPathComponent("menu-list.html"), options: [.atomic])

        let listStyle = """
        .probe-list {
          box-sizing: border-box;
          width: 260px;
          min-height: 48px;
          padding: 12px;
          font: 13px -apple-system, BlinkMacSystemFont, sans-serif;
          background: rgb(255,255,255);
          color: rgb(20,20,20);
        }
        """
        try Data(listStyle.utf8)
            .write(to: overlayDirectory.appendingPathComponent("menu-list.css"), options: [.atomic])

        let listScript = """
        (() => {
          let token = null;
          let messageOrigin = null;
          let observer = null;

          const postToParent = (message) => {
            if (!token || !messageOrigin) {
              return;
            }
            parent.postMessage(Object.assign({}, message, { token }), messageOrigin);
          };

          window.addEventListener('message', (event) => {
            if (event.source !== parent) {
              return;
            }
            if (messageOrigin && event.origin !== messageOrigin) {
              return;
            }
            messageOrigin = event.origin;

            const message = event.data || {};
            if (message.command !== 'initAutofillInlineMenuList' || !message.token) {
              return;
            }
            token = message.token;

            const link = document.createElement('link');
            link.setAttribute('rel', 'stylesheet');
            link.setAttribute('href', message.styleSheetUrl);
            document.head.appendChild(link);

            const container = document.createElement('div');
            container.id = 'inline-menu-list';
            container.className = 'probe-list';
            container.textContent = 'Probe login item';
            document.body.appendChild(container);

            observer = new ResizeObserver((entries) => {
              const height = Math.ceil(entries[0].contentRect.height);
              postToParent({
                command: 'updateAutofillInlineMenuListHeight',
                styles: { height: `${height}px` }
              });
            });
            observer.observe(container);
          });
        })();
        """
        try Data(listScript.utf8)
            .write(to: overlayDirectory.appendingPathComponent("menu-list.js"), options: [.atomic])

        let resolvedExtensionId = UUID().uuidString
        let destinationDirectory = ExtensionPathSafety.extensionsDirectory()
            .appendingPathComponent(resolvedExtensionId, isDirectory: true)
        if FileManager.default.fileExists(atPath: destinationDirectory.path) {
            try FileManager.default.removeItem(at: destinationDirectory)
        }
        try FileManager.default.copyItem(at: directoryURL, to: destinationDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: destinationDirectory)
        }

        let installedManifest = try ExtensionManifestValidation.validate(
            at: destinationDirectory.appendingPathComponent("manifest.json"),
            policy: .safariWebExtension
        )
        let record = try inspection.installation.metadata.makeInstalledRecord(
            extensionId: resolvedExtensionId,
            manifest: installedManifest,
            extensionRoot: destinationDirectory,
            isEnabled: false,
            sourceKind: .safariAppExtension,
            sourceBundlePath: scratchDirectory
                .appendingPathComponent("missing-\(resolvedExtensionId).appex")
                .path,
            sourceFingerprintURL: destinationDirectory,
            existingEntity: nil
        )
        try inspection.installation.metadata.persist(record: record)
        _ = inspection.installation.catalog.load()
        return record
    }

    private func writeJSON(_ object: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            .write(to: url, options: [.atomic])
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
            _: WKWebView,
            didFinish _: WKNavigation! // swiftlint:disable:this implicitly_unwrapped_optional
        ) {
            onFinish()
        }
    }
}
