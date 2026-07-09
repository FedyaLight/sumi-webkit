import SwiftData
import WebKit
import XCTest

@testable import Sumi

/// Proves WebKit's native `browser.scripting` implementation works through
/// Sumi's tab adapters for a Safari-target MV3 extension, mirroring the exact
/// calls Proton Pass's worker makes to bootstrap its autofill inline UI
/// (`injection.ts`): `executeScript({files})` for client.js,
/// MAIN-world `executeScript({files})` for elements.js, MAIN-world
/// `executeScript({func, args})` for element registration, and `insertCSS`.
@available(macOS 15.5, *)
@MainActor
final class SafariExtensionScriptingRuntimeTests: XCTestCase {
    func testWorkerDrivenScriptingInjectionMirrorsProtonBootstrap() async throws {
        let server = try await AutofillPagesHTTPServer.start()
        addTeardownBlock {
            server.stop()
        }

        let container = try makeTestContainer()
        let profile = Profile(name: "Scripting Runtime Profile")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration
        )
        let browserManager = makeSafariExtensionTestBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        // The startup restore task replaces the tab-manager structural state
        // when it lands; wait for it so the tab created below stays resolvable
        // for the scripting target lookup.
        await browserManager.tabManager.storeRestore.startupRestoreTask?.value

        let installed = try await installScriptingProbeExtension(
            manager: manager,
            scratchDirectory: makeScratchDirectory()
        )
        _ = try await manager.installationFlowOwner.enableExtension(installed.id)
        let extensionContext = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        XCTAssertTrue(extensionContext.isLoaded)
        XCTAssertEqual(
            extensionContext.permissionStatus(
                for: WKWebExtension.Permission(rawValue: "scripting")
            ),
            .grantedExplicitly,
            "Safari-target manifests must get scripting granted like Safari does"
        )
        XCTAssertFalse(
            extensionContext.unsupportedAPIs.contains {
                $0.hasPrefix("browser.scripting")
            },
            "browser.scripting must not be hidden from Safari-target extensions"
        )

        _ = try await manager.ensureBackgroundAvailableIfRequired(
            for: extensionContext.webExtension,
            context: extensionContext,
            reason: .enable
        )

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionScriptingRuntimeTests"
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
            reason: "SafariExtensionScriptingRuntimeTests"
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
        await fulfillment(of: [didFinish], timeout: 10)
        webView.navigationDelegate = nil

        let probe = try await waitForScriptingProbeResult(in: webView)

        let worker = try XCTUnwrap(
            probe["worker"] as? [String: Any],
            "worker response missing: \(probe)"
        )
        XCTAssertEqual(
            worker["scriptingAvailable"] as? Bool,
            true,
            "browser.scripting must be exposed to the background worker"
        )
        XCTAssertEqual(
            worker["files"] as? String,
            "ok",
            "executeScript({files:['client.js']}) failed: \(worker)"
        )
        XCTAssertEqual(
            worker["mainFiles"] as? String,
            "ok",
            "MAIN-world executeScript({files:['elements.js']}) failed: \(worker)"
        )
        XCTAssertEqual(
            worker["funcArgs"] as? String,
            "ok",
            "MAIN-world executeScript({func, args}) failed: \(worker)"
        )
        XCTAssertEqual(
            worker["css"] as? String,
            "ok",
            "insertCSS({files:['client.css']}) failed: \(worker)"
        )

        XCTAssertEqual(
            probe["clientInjected"] as? String,
            "true",
            "client.js (isolated world) did not run in the page: \(probe)"
        )
        XCTAssertEqual(
            probe["mainWorldMarker"] as? String,
            "true",
            "elements.js (MAIN world) did not run in the page: \(probe)"
        )
        XCTAssertEqual(
            probe["elementsRegistered"] as? String,
            "probe-hash:true",
            "MAIN-world func/args registration did not reach elements.js: \(probe)"
        )
        XCTAssertEqual(
            probe["cssValue"] as? String,
            "injected",
            "insertCSS stylesheet not applied to the page: \(probe)"
        )
    }

    private func waitForScriptingProbeResult(
        in webView: WKWebView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [String: Any] {
        let script = """
        (() => {
          return document.documentElement.dataset.sumiScriptingProbe || null;
        })();
        """

        var lastRaw: String?
        for _ in 0..<100 {
            if let raw = try? await webView.evaluateJavaScript(script) as? String {
                lastRaw = raw
                if let data = raw.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data)
                       as? [String: Any] {
                    return object
                }
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail(
            "Timed out waiting for scripting probe result; last=\(lastRaw ?? "nil")",
            file: file,
            line: line
        )
        return [:]
    }

    private func installScriptingProbeExtension(
        manager: ExtensionManager,
        scratchDirectory: URL
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(
            "ScriptingProbeExtension",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "ScriptingProbeExtension",
            "version": "1.0",
            "browser_specific_settings": [
                "safari": ["strict_min_version": "16.0"],
            ],
            "background": ["service_worker": "background.js"],
            "permissions": ["scripting", "storage"],
            "host_permissions": ["*://*/*"],
            "content_scripts": [[
                "matches": ["*://*/*"],
                "js": ["orchestrator.js"],
                "run_at": "document_end",
            ]],
        ]
        try writeJSON(manifest, to: directoryURL.appendingPathComponent("manifest.json"))

        // Mirrors Proton Pass injection.ts: the worker resolves the sender tab
        // and injects the autofill client + MAIN-world element registration.
        let backgroundScript = """
        (() => {
          const api = globalThis.browser || globalThis.chrome;
          api.runtime.onMessage.addListener((message, sender, sendResponse) => {
            if (!message || message.command !== 'sumi-scripting-probe') {
              return;
            }
            (async () => {
              const results = {};
              try {
                const tabId = sender.tab && sender.tab.id;
                const frameId = sender.frameId;
                results.sender = { tabId: tabId ?? null, frameId: frameId ?? null };
                results.scriptingAvailable =
                  !!(api.scripting && typeof api.scripting.executeScript === 'function');
                const target = { tabId, frameIds: [frameId] };
                try {
                  await api.scripting.executeScript({ target, files: ['client.js'] });
                  results.files = 'ok';
                } catch (e) {
                  results.files = 'error:' + String(e && (e.message || e));
                }
                try {
                  await api.scripting.executeScript({
                    target,
                    world: 'MAIN',
                    files: ['elements.js'],
                  });
                  results.mainFiles = 'ok';
                } catch (e) {
                  results.mainFiles = 'error:' + String(e && (e.message || e));
                }
                try {
                  await api.scripting.executeScript({
                    target,
                    world: 'MAIN',
                    args: ['probe-hash', true],
                    func: (hash, mainFrame) => {
                      if (window.registerPassElements) {
                        window.registerPassElements(hash, mainFrame);
                      }
                    },
                  });
                  results.funcArgs = 'ok';
                } catch (e) {
                  results.funcArgs = 'error:' + String(e && (e.message || e));
                }
                try {
                  await api.scripting.insertCSS({
                    target: { tabId },
                    files: ['client.css'],
                  });
                  results.css = 'ok';
                } catch (e) {
                  results.css = 'error:' + String(e && (e.message || e));
                }
              } catch (e) {
                results.fatal = String(e && (e.message || e));
              }
              sendResponse(results);
            })();
            return true;
          });
        })();
        """
        try Data(backgroundScript.utf8)
            .write(
                to: directoryURL.appendingPathComponent("background.js"),
                options: [.atomic]
            )

        let orchestratorScript = """
        (() => {
          const api = globalThis.browser || globalThis.chrome;
          const finish = (worker) => {
            const marker = document.getElementById('sumi-scripting-css-marker')
              || (() => {
                const element = document.createElement('div');
                element.id = 'sumi-scripting-css-marker';
                document.documentElement.appendChild(element);
                return element;
              })();
            const cssValue = getComputedStyle(marker)
              .getPropertyValue('--sumi-scripting-css')
              .trim();
            document.documentElement.dataset.sumiScriptingProbe = JSON.stringify({
              worker: worker || { error: 'no worker response' },
              clientInjected:
                document.documentElement.dataset.sumiScriptingClientInjected || null,
              mainWorldMarker:
                document.documentElement.dataset.sumiScriptingMainWorld || null,
              elementsRegistered:
                document.documentElement.dataset.sumiScriptingElementsRegistered || null,
              cssValue,
            });
          };
          try {
            api.runtime.sendMessage({ command: 'sumi-scripting-probe' }, (response) => {
              const error = api.runtime.lastError && api.runtime.lastError.message;
              finish(error ? { error } : response);
            });
          } catch (error) {
            finish({ error: String(error && (error.message || error)) });
          }
        })();
        """
        try Data(orchestratorScript.utf8)
            .write(
                to: directoryURL.appendingPathComponent("orchestrator.js"),
                options: [.atomic]
            )

        let clientScript = """
        document.documentElement.dataset.sumiScriptingClientInjected = 'true';
        """
        try Data(clientScript.utf8)
            .write(
                to: directoryURL.appendingPathComponent("client.js"),
                options: [.atomic]
            )

        let elementsScript = """
        window.registerPassElements = (hash, mainFrame) => {
          document.documentElement.dataset.sumiScriptingElementsRegistered =
            hash + ':' + mainFrame;
        };
        document.documentElement.dataset.sumiScriptingMainWorld = 'true';
        """
        try Data(elementsScript.utf8)
            .write(
                to: directoryURL.appendingPathComponent("elements.js"),
                options: [.atomic]
            )

        let clientStyle = """
        #sumi-scripting-css-marker { --sumi-scripting-css: injected; }
        """
        try Data(clientStyle.utf8)
            .write(
                to: directoryURL.appendingPathComponent("client.css"),
                options: [.atomic]
            )

        let resolvedExtensionId = UUID().uuidString
        let destinationDirectory = ExtensionUtils.extensionsDirectory()
            .appendingPathComponent(resolvedExtensionId, isDirectory: true)
        if FileManager.default.fileExists(atPath: destinationDirectory.path) {
            try FileManager.default.removeItem(at: destinationDirectory)
        }
        try FileManager.default.copyItem(at: directoryURL, to: destinationDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: destinationDirectory)
        }

        let installedManifest = try ExtensionUtils.validateManifest(
            at: destinationDirectory.appendingPathComponent("manifest.json"),
            policy: .safariWebExtension
        )
        let record = try manager.makeInstalledRecord(
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
        try manager.persist(record: record)
        _ = manager.installationFlowOwner.loadInstalledExtensionMetadata()
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
