import Combine
import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
class SafariExtensionWebViewControllerWiringTestCase: XCTestCase {
    func makeManager(
        context: ModelContext,
        profile: Profile,
        browserConfiguration: BrowserConfiguration = BrowserConfiguration(),
        moduleRegistry: SumiModuleRegistry = .unavailable(),
        assemblyOverrides: ExtensionManagerTestAssemblyOverrides? = nil
    ) -> (
        manager: ExtensionManager,
        browserConfiguration: BrowserConfiguration,
        attachedRuntime: ExtensionAttachedRuntimeCapture,
        inspection: ExtensionManagerTestInspection
    ) {
        let fixture = makeSafariExtensionManagerTestFixture(
            context: context,
            initialProfile: profile,
            browserConfiguration: browserConfiguration,
            moduleRegistry: moduleRegistry,
            assemblyOverrides: assemblyOverrides
        )
        return (
            fixture.manager,
            browserConfiguration,
            fixture.attachedRuntime,
            fixture.inspection
        )
    }

    func makeBrowserManager(
        moduleRegistry: SumiModuleRegistry? = nil,
        extensionsModule: SumiExtensionsModule? = nil,
        profile: Profile? = nil,
        windowRegistry: WindowRegistry? = nil
    ) -> BrowserManager {
        let browserManager = makeSafariExtensionTestBrowserManager(
            moduleRegistry: moduleRegistry,
            extensionsModule: extensionsModule,
            profile: profile,
            windowRegistry: windowRegistry,
            automaticallyStartPersistedStateLoad: false
        )
        return browserManager
    }

    func makeWindowRequestRouter(
        inspection: ExtensionManagerTestInspection,
        attachedRuntime: ExtensionAttachedBrowserRuntimeInspection,
        windowCreation: any ExtensionRequestedWindowCreating
    ) -> ExtensionWindowRequestRouter {
        ExtensionWindowRequestRouter(
            profileRuntime: inspection.contextState.profiles,
            targetResolver: attachedRuntime.requestedTabs.targetResolver,
            loadResolver: inspection.normalTabs.loadResolver,
            contextPreloader: attachedRuntime.requestedTabs.contextPreloader,
            tabOpening: attachedRuntime.requestedTabs.opening,
            windowQuery: { attachedRuntime.bridge.windows },
            windowCreation: { windowCreation },
            publishedWindow: { window, profileID in
                attachedRuntime.publications.windowPublications
                    .publishedWindowAdapter(
                        for: window,
                        profileID: profileID
                    )
            }
        )
    }

    @discardableResult
    func attachUsableExtensionWebView(
        to tab: Tab,
        inspection: ExtensionManagerTestInspection,
        profile: Profile
    ) -> WKWebView {
        let configuration = inspection.controller.browserConfiguration
            .auxiliaryWebViewConfiguration(surface: .extensionOptions)
        inspection.normalTabs.configuration
            .prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)
        return webView
    }
    func makeTab(profileId: UUID, url: URL) -> Tab {
        let tab = Tab(url: url, name: "Test")
        tab.profileId = profileId
        return tab
    }

    func makeTab(profileId: UUID, url: URL, browserManager: BrowserManager) -> Tab {
        let tabs = browserManager
        let space = tabs.spaceStateOwner.firstSpace(forProfile: profileId)
            ?? installTestSpace(
                in: tabs.spaceStateOwner,
                name: "Test Space",
                profileID: profileId
            )
        let tab = tabs.tabFactory.makeTab(
            url: url,
            name: "Test",
            spaceId: space.id,
            index: tabs.regularTabCollectionOwner.tabs(in: space.id).count
        )
        tab.profileId = profileId
        tabs.regularTabLifecycleOwner.addTab(tab)
        return tab
    }

    @discardableResult
    func registerWindowDisplaying(
        _ tab: Tab,
        profileId: UUID,
        browserManager: BrowserManager
    ) -> BrowserWindowState {
        let registry = browserManager.windowRegistry
        let window = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: window)
        window.currentProfileId = profileId
        window.currentSpaceId = tab.spaceId
        window.currentTabId = tab.id
        if let spaceID = tab.spaceId {
            window.activeTabForSpace[spaceID] = tab.id
        }
        registry.register(window)
        registry.setActive(window)
        addTeardownBlock {
            registry.unregister(window.id)
        }
        return window
    }

    @discardableResult
    func publishNormalExtensionWindow(
        inspection: ExtensionManagerTestInspection,
        browserManager: BrowserManager,
        profile: Profile
    ) -> BrowserWindowState {
        let sourceTab = makeTab(
            profileId: profile.id,
            url: URL(string: "https://source.example.test/")!,
            browserManager: browserManager
        )
        sourceTab.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: browserManager)
        )
        let window = registerWindowDisplaying(
            sourceTab,
            profileId: profile.id,
            browserManager: browserManager
        )
        attachUsableExtensionWebView(
            to: sourceTab,
            inspection: inspection,
            profile: profile
        )
        inspection.browserPublication.reloads.reloadLoadedRuntime(
            reason: "SafariExtensionWebViewControllerWiringTests.sourceWindow",
            profileID: profile.id
        )
        XCTAssertNotNil(
            inspection.normalTabs.adapters.existingWindowAdapter(for: window.id)
        )
        return window
    }

    func makeLoadedExtensionContext(
        manager: ExtensionManager,
        inspection: ExtensionManagerTestInspection,
        profile: Profile
    ) async throws -> WKWebExtensionContext {
        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ContextProbeExtension"
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        let context = try await inspection.contextCoordination.residency
            .ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        return try XCTUnwrap(context)
    }

    func backgroundRuntimeState(
        in inspection: ExtensionManagerTestInspection,
        extensionID: String,
        profileID: UUID
    ) -> ExtensionManager.BackgroundRuntimeState {
        inspection.contextState.background.state(
            for: ExtensionRuntimeResidencyState.scopedKey(
                extensionId: extensionID,
                profileId: profileID
            )
        )
    }

    func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    func replacingPackageRoot(
        of record: InstalledExtension,
        with packageRoot: URL
    ) -> InstalledExtension {
        InstalledExtension(
            id: record.id,
            name: record.name,
            version: record.version,
            manifestVersion: record.manifestVersion,
            description: record.description,
            isEnabled: record.isEnabled,
            installDate: record.installDate,
            lastUpdateDate: record.lastUpdateDate,
            packagePath: packageRoot.path,
            iconPath: record.iconPath,
            sourceKind: record.sourceKind,
            backgroundModel: record.backgroundModel,
            incognitoMode: record.incognitoMode,
            sourcePathFingerprint: "replacement-\(UUID().uuidString)",
            manifestRootFingerprint: "replacement-\(UUID().uuidString)",
            sourceBundlePath: packageRoot.path,
            safariRuntimeIdentity: record.safariRuntimeIdentity,
            optionsPagePath: record.optionsPagePath,
            defaultPopupPath: record.defaultPopupPath,
            hasBackground: record.hasBackground,
            hasAction: record.hasAction,
            hasOptionsPage: record.hasOptionsPage,
            hasContentScripts: record.hasContentScripts,
            hasExtensionPages: record.hasExtensionPages,
            activationSummary: record.activationSummary,
            manifest: record.manifest
        )
    }

    func makeScratchDirectory() throws -> URL {
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

    func awaitExtensionRenderMetrics(
        in webView: WKWebView
    ) async throws -> ExtensionRenderMetrics {
        let extensionPageLoaded = expectation(description: "extension page loaded")
        var observation: AnyCancellable?
        observation = webView.publisher(for: \.url, options: [.initial, .new])
            .combineLatest(webView.publisher(for: \.isLoading, options: [.initial, .new]))
            .filter { url, isLoading in
                ExtensionURLIdentity.isOwned(url) && !isLoading
            }
            .prefix(1)
            .sink { _ in
                extensionPageLoaded.fulfill()
            }
        await fulfillment(of: [extensionPageLoaded], timeout: 8)
        withExtendedLifetime(observation) {}

        let rawValue = try await webView.evaluateJavaScript("""
            (() => [
              document.readyState,
              document.querySelectorAll('body *').length,
              document.scripts.length,
              document.body ? (document.body.dataset.sumiRenderMarker || '') : '',
              ['safari-web-extension:', 'webkit-extension:'].includes(location.protocol)
            ].join('|'))();
            """) as? String
        return try ExtensionRenderMetrics(rawValue: rawValue ?? "")
    }

    func installContentScriptProbeExtension(
        manager: ExtensionManager,
        scratchDirectory: URL
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(
            "ContentScriptCSSProbe",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "ContentScriptCSSProbe",
            "version": "1.0",
            "host_permissions": ["<all_urls>"],
            "content_scripts": [[
                "matches": ["<all_urls>"],
                "js": ["content.js"],
                "css": ["overlay.css"],
                "run_at": "document_idle",
            ]],
            "web_accessible_resources": [[
                "resources": ["overlay.html"],
                "matches": ["<all_urls>"],
            ]],
        ]
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: manifestURL, options: [.atomic])
        try Data("true;".utf8)
            .write(to: directoryURL.appendingPathComponent("content.js"), options: [.atomic])
        try Data("iframe{height:1px;}".utf8)
            .write(to: directoryURL.appendingPathComponent("overlay.css"), options: [.atomic])
        try Data("<!doctype html><title>overlay</title>".utf8)
            .write(to: directoryURL.appendingPathComponent("overlay.html"), options: [.atomic])

        return try await manager.settingsCatalogBinding().install(
            from: directoryURL,
            enableOnInstall: false
        )
    }

    func installContentScriptBackgroundProbeExtension(
        manager: ExtensionManager,
        scratchDirectory: URL
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(
            "ContentScriptBackgroundProbe",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "ContentScriptBackgroundProbe",
            "version": "1.0",
            "host_permissions": ["<all_urls>"],
            "background": [
                "service_worker": "background.js",
            ],
            "content_scripts": [[
                "matches": ["<all_urls>"],
                "js": ["content.js"],
                "run_at": "document_idle",
            ]],
        ]
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: manifestURL, options: [.atomic])
        try Data("true;".utf8)
            .write(to: directoryURL.appendingPathComponent("content.js"), options: [.atomic])
        try Data("globalThis.__sumiBackgroundProbe = true;".utf8)
            .write(to: directoryURL.appendingPathComponent("background.js"), options: [.atomic])

        return try await manager.settingsCatalogBinding().install(
            from: directoryURL,
            enableOnInstall: false
        )
    }

    func installContentScriptNativeMessagingProbeExtension(
        manager: ExtensionManager,
        scratchDirectory: URL
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(
            "ContentScriptNativeMessagingProbe",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "ContentScriptNativeMessagingProbe",
            "version": "1.0",
            "permissions": ["nativeMessaging"],
            "host_permissions": ["<all_urls>"],
            "background": [
                "service_worker": "background.js",
            ],
            "content_scripts": [[
                "matches": ["<all_urls>"],
                "js": ["content.js"],
                "run_at": "document_start",
            ]],
        ]
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: manifestURL, options: [.atomic])
        try Data("browser.runtime.sendMessage({kind:'probe'});".utf8)
            .write(to: directoryURL.appendingPathComponent("content.js"), options: [.atomic])
        try Data("globalThis.__sumiNativeMessagingBackgroundProbe = true;".utf8)
            .write(to: directoryURL.appendingPathComponent("background.js"), options: [.atomic])

        return try await manager.settingsCatalogBinding().install(
            from: directoryURL,
            enableOnInstall: false
        )
    }

    func installUnpackedExtension(
        manager: ExtensionManager,
        scratchDirectory: URL,
        name: String,
        optionsPage: String? = nil
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": name,
            "version": "1.0",
            "host_permissions": ["<all_urls>"],
            "action": ["default_popup": "popup.html"],
        ]
        if let optionsPage {
            manifest["options_ui"] = ["page": optionsPage]
        }
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        )
        try manifestData.write(to: manifestURL, options: [.atomic])
        try Data(
            """
            <!doctype html>
            <title>popup</title>
            <main id="ready">Loaded</main>
            <script src="popup.js"></script>
            """.utf8
        )
            .write(to: directoryURL.appendingPathComponent("popup.html"), options: [.atomic])
        if let optionsPage {
            try Data(
                """
                <!doctype html>
                <title>options</title>
                <main id="ready">Loaded</main>
                <script src="popup.js"></script>
                """.utf8
            )
                .write(to: directoryURL.appendingPathComponent(optionsPage), options: [.atomic])
        }
        try Data(
            """
            document.body.dataset.sumiRenderMarker = 'rendered';
            """.utf8
        )
            .write(to: directoryURL.appendingPathComponent("popup.js"), options: [.atomic])

        return try await manager.settingsCatalogBinding().install(
            from: directoryURL,
            enableOnInstall: false
        )
    }

    static func firstWebView(in root: NSView) -> WKWebView? {
        if let webView = root as? WKWebView {
            return webView
        }
        for subview in root.subviews {
            if let webView = firstWebView(in: subview) {
                return webView
            }
        }
        return nil
    }
}

struct ExtensionRenderMetrics: Equatable {
    var readyState: String
    var elementCount: Int
    var scriptCount: Int
    var marker: String
    var loadedFromExtensionScheme: Bool

    static let empty = ExtensionRenderMetrics(
        readyState: "",
        elementCount: 0,
        scriptCount: 0,
        marker: "",
        loadedFromExtensionScheme: false
    )

    var debugSummary: String {
        [
            "ready=\(readyState)",
            "elements=\(elementCount)",
            "scripts=\(scriptCount)",
            "marker=\(marker)",
            "extensionScheme=\(loadedFromExtensionScheme)",
        ].joined(separator: " ")
    }

    init(
        readyState: String,
        elementCount: Int,
        scriptCount: Int,
        marker: String,
        loadedFromExtensionScheme: Bool
    ) {
        self.readyState = readyState
        self.elementCount = elementCount
        self.scriptCount = scriptCount
        self.marker = marker
        self.loadedFromExtensionScheme = loadedFromExtensionScheme
    }

    init(rawValue: String) throws {
        let parts = rawValue.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 5,
              let elements = Int(parts[1]),
              let scripts = Int(parts[2])
        else {
            throw NSError(
                domain: "SafariExtensionWebViewControllerWiringTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid render metrics"]
            )
        }

        readyState = String(parts[0])
        elementCount = elements
        scriptCount = scripts
        marker = String(parts[3])
        loadedFromExtensionScheme = parts[4] == "true"
    }
}
