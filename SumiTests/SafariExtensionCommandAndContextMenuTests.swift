import AppKit
import SwiftData
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
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installCommandAndMenuProbeExtension(
            manager: manager,
            scratchDirectory: makeScratchDirectory()
        )
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
        let extensionContext = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
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
            manager.performExtensionKeyboardCommand(for: matching),
            "Alt+Shift+U must dispatch the manifest command"
        )

        let differentKey = try XCTUnwrap(
            keyDownEvent(key: "i", keyCode: 34, modifiers: [.option, .shift])
        )
        XCTAssertFalse(
            manager.performExtensionKeyboardCommand(for: differentKey),
            "A non-declared shortcut must not be consumed"
        )

        let unmodified = try XCTUnwrap(
            keyDownEvent(key: "u", keyCode: 32, modifiers: [])
        )
        XCTAssertFalse(
            manager.performExtensionKeyboardCommand(for: unmodified),
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
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration
        )
        let browserManager = makeSafariExtensionTestBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        // The startup restore task replaces the tab-manager structural state
        // when it lands; wait for it so the tab created below stays resolvable.
        await browserManager.tabManager.storeRestore.startupRestoreTask?.value

        let installed = try await installCommandAndMenuProbeExtension(
            manager: manager,
            scratchDirectory: makeScratchDirectory()
        )
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
        manager.setDefaultSiteAccess(
            .allow,
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        XCTAssertTrue(extensionContext.isLoaded)

        // menus.create runs at the top of the background worker.
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
            reason: "SafariExtensionCommandAndContextMenuTests"
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
            reason: "SafariExtensionCommandAndContextMenuTests"
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

        // Menu registration crosses the worker → UI process asynchronously.
        var menuItems: [NSMenuItem] = []
        for _ in 0..<50 {
            menuItems = manager.pageContextMenuItems(for: tab)
            if menuItems.isEmpty == false { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertTrue(
            containsMenuItem(titled: "Sumi Probe Menu Item", in: menuItems),
            "background menus.create item must surface for the page tab: \(menuItems.map(\.title))"
        )
    }

    // MARK: - Helpers

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
          if (menus && typeof menus.create === 'function') {
            menus.create({
              id: 'sumi-probe-menu-item',
              title: 'Sumi Probe Menu Item',
              contexts: ['all'],
            });
          }
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

        return try await manager.extensionInstaller.install(
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
