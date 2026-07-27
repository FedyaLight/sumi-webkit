import AppKit
import WebKit
import XCTest

@testable import Sumi

/// Safari parity for the two chrome surfaces WebKit leaves to the embedding
/// app: manifest `commands` keyboard shortcuts (dispatched through
/// `WKWebExtensionContext.performCommand(for: NSEvent)`) and extension
/// context-menu items (`menuItems(for:)`, backed by the menus/contextMenus
/// API from the extension's background script).
@available(macOS 15.5, *)
@MainActor
final class SafariExtensionCommandAndContextMenuTests: XCTestCase {
    func testManifestCommandDispatchesFromKeyboardEvent() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Command Dispatch Profile")
        let fixture = makeSafariExtensionManagerTestFixture(
            context: container,
            initialProfile: profile
        )
        let manager = fixture.manager
        let inspection = fixture.inspection

        let installed = try await installCommandAndMenuProbeExtension(
            manager: manager,
            scratchDirectory: makeScratchDirectory()
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        let extensionContext = try XCTUnwrap(
            inspection.contextState.profileState.context(
                for: installed.id,
                profileId: profile.id
            )
        )
        XCTAssertTrue(extensionContext.isLoaded)

        let command = try XCTUnwrap(
            extensionContext.commands.first {
                $0.activationKey?.lowercased() == "u"
            },
            "manifest commands must surface on the loaded context"
        )
        XCTAssertTrue(
            command.modifierFlags.contains(.option)
                && command.modifierFlags.contains(.shift),
            "Alt+Shift+U must parse into option+shift modifiers"
        )

        let matching = try XCTUnwrap(
            keyDownEvent(key: "u", keyCode: 32, modifiers: [.option, .shift])
        )
        XCTAssertTrue(
            inspection.actionSurfaces.keyboardCommands.performCommand(
                for: matching
            ),
            "Alt+Shift+U must dispatch the manifest command"
        )

        let differentKey = try XCTUnwrap(
            keyDownEvent(key: "i", keyCode: 34, modifiers: [.option, .shift])
        )
        XCTAssertFalse(
            inspection.actionSurfaces.keyboardCommands.performCommand(
                for: differentKey
            ),
            "A non-declared shortcut must not be consumed"
        )

        let unmodified = try XCTUnwrap(
            keyDownEvent(key: "u", keyCode: 32, modifiers: [])
        )
        XCTAssertFalse(
            inspection.actionSurfaces.keyboardCommands.performCommand(
                for: unmodified
            ),
            "Plain typing must never reach extension command dispatch"
        )
    }

    func testBackgroundCreatedMenuItemsSurfaceOnPageContextMenu() async throws {
        let server = try await AutofillPagesHTTPServer.start()
        addTeardownBlock {
            server.stop()
        }

        let container = try makeTestContainer()
        let profile = Profile(name: "Context Menu Profile")
        let browserConfiguration = BrowserConfiguration()
        let fixture = makeSafariExtensionManagerTestFixture(
            context: container,
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
        browserManager.startupRestoreLifecycle.markLoadFinished()
        manager.attach(browserManager: browserManager)

        let installed = try await installCommandAndMenuProbeExtension(
            manager: manager,
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

        // menus.create runs at the top of the background worker.
        _ = try await inspection.nativeMessaging.backgroundWakes
            .ensureBackgroundAvailableIfRequired(
            for: extensionContext.webExtension,
            context: extensionContext,
            reason: .enable
        )

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionCommandAndContextMenuTests"
        )

        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: server.loginBasicURL.absoluteString,
            in: browserManager.spaceStateOwner.currentSpace,
            activate: false,
            webViewConfigurationOverride: configuration
        )
        tab.profileId = profile.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
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
            reason: "SafariExtensionCommandAndContextMenuTests"
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
        await fulfillment(of: [didFinish], timeout: 10)
        webView.navigationDelegate = nil

        try await waitForMenuRegistration(in: webView)
        let menuItems = inspection.normalTabs.requestedTabs
            .pageContextMenuItems(for: tab)

        XCTAssertTrue(
            containsMenuItem(titled: "Sumi Probe Menu Item", in: menuItems),
            "background menus.create item must surface for the page tab: \(menuItems.map(\.title))"
        )
    }

    // MARK: - Helpers

    private func waitForMenuRegistration(in webView: WKWebView) async throws {
        let status = try await webView.callAsyncJavaScript(
            """
            const root = document.documentElement;
            const readStatus = () => root.dataset.sumiMenuRegistration || null;
            const existingStatus = readStatus();
            if (existingStatus) {
                return existingStatus;
            }
            return await new Promise(resolve => {
                let timeoutID = null;
                const observer = new MutationObserver(() => {
                    const observedStatus = readStatus();
                    if (observedStatus) {
                        finish(observedStatus);
                    }
                });
                const finish = value => {
                    observer.disconnect();
                    if (timeoutID !== null) {
                        clearTimeout(timeoutID);
                    }
                    resolve(value);
                };
                observer.observe(root, {
                    attributes: true,
                    attributeFilter: ['data-sumi-menu-registration']
                });
                timeoutID = setTimeout(() => finish(readStatus()), 5000);
            });
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String
        XCTAssertEqual(status, "ready", "menu registration failed: \(status ?? "timeout")")
    }

    private func containsMenuItem(
        titled title: String,
        in items: [NSMenuItem]
    ) -> Bool {
        for item in items {
            if item.title == title {
                return true
            }
            if let submenu = item.submenu,
               containsMenuItem(titled: title, in: submenu.items) {
                return true
            }
        }
        return false
    }

    private func keyDownEvent(
        key: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    private func installCommandAndMenuProbeExtension(
        manager: ExtensionManager,
        scratchDirectory: URL
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(
            "CommandAndMenuProbeExtension",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "CommandAndMenuProbeExtension",
            "version": "1.0",
            "background": ["service_worker": "background.js"],
            "permissions": ["contextMenus"],
            "host_permissions": ["*://*/*"],
            "content_scripts": [[
                "matches": ["http://127.0.0.1/*"],
                "js": ["content.js"],
                "run_at": "document_start",
            ]],
            "commands": [
                "sumi-probe-command": [
                    "suggested_key": ["default": "Alt+Shift+U"],
                    "description": "Sumi probe command",
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(
                to: directoryURL.appendingPathComponent("manifest.json"),
                options: [.atomic]
            )

        let backgroundScript = """
        (() => {
          const api = globalThis.browser || globalThis.chrome;
          const menus = api.menus || api.contextMenus;
          let registrationStatus = 'error:menus-unavailable';
          let finishRegistration;
          const registrationSettled = new Promise(resolve => { finishRegistration = resolve; });
          if (menus && typeof menus.create === 'function') {
            menus.create({
              id: 'sumi-probe-menu-item',
              title: 'Sumi Probe Menu Item',
              contexts: ['all'],
            }, () => {
              const error = api.runtime && api.runtime.lastError;
              registrationStatus = error ? `error:${error.message}` : 'ready';
              finishRegistration();
            });
          } else {
            finishRegistration();
          }
          api.runtime.onMessage.addListener((message, _sender, sendResponse) => {
            if (!message || message.type !== 'sumi-menu-registration') return false;
            registrationSettled.then(() => sendResponse({ status: registrationStatus }));
            return true;
          });
          if (api.commands && api.commands.onCommand) {
            api.commands.onCommand.addListener(() => {});
          }
        })();
        """
        try Data(backgroundScript.utf8)
            .write(
                to: directoryURL.appendingPathComponent("background.js"),
                options: [.atomic]
            )

        let contentScript = """
        (() => {
          const api = globalThis.browser || globalThis.chrome;
          const publish = status => {
            document.documentElement.dataset.sumiMenuRegistration = status;
          };
          const request = { type: 'sumi-menu-registration' };
          if (globalThis.browser) {
            api.runtime.sendMessage(request).then(
              response => publish(response && response.status || 'error:empty-response'),
              error => publish(`error:${String(error)}`)
            );
          } else {
            api.runtime.sendMessage(request, response => {
              const error = api.runtime.lastError;
              publish(error ? `error:${error.message}` : response && response.status || 'error:empty-response');
            });
          }
        })();
        """
        try Data(contentScript.utf8)
            .write(
                to: directoryURL.appendingPathComponent("content.js"),
                options: [.atomic]
            )

        return try await manager.settingsCatalogBinding().install(
            from: directoryURL,
            enableOnInstall: false
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

    private func makeTestContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
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
