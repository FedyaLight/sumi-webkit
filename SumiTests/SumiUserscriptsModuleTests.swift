import SwiftData
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiUserscriptsModuleTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testDisabledModuleAccessorsDoNotConstructRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = UserscriptsRuntimeProbe()
        let module = makeModule(registry: registry, probe: probe)

        XCTAssertFalse(module.isEnabled)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertNil(module.managerIfEnabled())
        XCTAssertTrue(
            module.normalTabUserScripts(
                for: URL(string: "https://www.example.test/path")!,
                webViewId: UUID(),
                profileId: UUID(),
                isEphemeral: false
            )
            .isEmpty
        )
        XCTAssertFalse(
            module.interceptInstallNavigationIfNeeded(
                URL(string: "https://www.example.test/script.user.js")!
            )
        )
        module.cleanupWebViewIfLoaded(
            controller: WKUserContentController(),
            webViewId: UUID()
        )

        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertEqual(probe.storeCount, 0)
        XCTAssertEqual(probe.injectorCount, 0)
    }

    func testSetEnabledPersistsWithoutConstructingRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = UserscriptsRuntimeProbe()
        let module = makeModule(registry: registry, probe: probe)

        module.setEnabled(true)

        XCTAssertTrue(registry.isEnabled(.userScripts))
        XCTAssertTrue(module.isEnabled)
        XCTAssertFalse(module.hasLoadedRuntime)

        module.setEnabled(false)

        XCTAssertFalse(registry.isEnabled(.userScripts))
        XCTAssertFalse(module.isEnabled)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertEqual(probe.storeCount, 0)
        XCTAssertEqual(probe.injectorCount, 0)
    }

    func testEnabledModuleConstructsManagerStoreAndInjectorLazilyOnce() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.userScripts)
        let probe = UserscriptsRuntimeProbe()
        let module = makeModule(registry: registry, probe: probe)

        XCTAssertTrue(module.isEnabled)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertEqual(probe.storeCount, 0)
        XCTAssertEqual(probe.injectorCount, 0)

        let firstManager = try XCTUnwrap(module.managerIfEnabled())
        let secondManager = try XCTUnwrap(module.managerIfEnabled())

        XCTAssertIdentical(firstManager, secondManager)
        XCTAssertTrue(firstManager.isEnabled)
        XCTAssertEqual(probe.managerCount, 1)
        XCTAssertEqual(probe.storeCount, 1)
        XCTAssertEqual(probe.injectorCount, 1)
    }

    func testEnabledNormalTabPathContributesInstalledUserscripts() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.userScripts)
        let scriptsDirectory = try makeTemporaryScriptsDirectory()
        try writeScript(
            named: "enabled.user.js",
            in: scriptsDirectory,
            match: "https://www.example.test/*"
        )
        let probe = UserscriptsRuntimeProbe()
        let module = makeModule(
            registry: registry,
            probe: probe,
            scriptsDirectory: scriptsDirectory
        )

        let scripts = module.normalTabUserScripts(
            for: URL(string: "https://www.example.test/page")!,
            webViewId: UUID(),
            profileId: UUID(),
            isEphemeral: false
        )

        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].source.contains(UserScriptInjector.userScriptMarker))
        XCTAssertEqual(probe.managerCount, 1)
        XCTAssertEqual(probe.storeCount, 1)
        XCTAssertEqual(probe.injectorCount, 1)
    }

    func testPrivateTabsSkipUserscriptsByDefault() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.userScripts)
        let scriptsDirectory = try makeTemporaryScriptsDirectory()
        try writeScript(
            named: "private-default.user.js",
            in: scriptsDirectory,
            match: "https://www.example.test/*"
        )
        let probe = UserscriptsRuntimeProbe()
        let module = makeModule(
            registry: registry,
            probe: probe,
            scriptsDirectory: scriptsDirectory
        )
        let url = URL(string: "https://www.example.test/page")!

        XCTAssertEqual(
            module.normalTabUserScripts(
                for: url,
                webViewId: UUID(),
                profileId: UUID(),
                isEphemeral: false
            )
            .count,
            1
        )
        XCTAssertTrue(
            module.normalTabUserScripts(
                for: url,
                webViewId: UUID(),
                profileId: UUID(),
                isEphemeral: true
            )
            .isEmpty
        )
    }

    func testPrivateTabsInjectUserscriptsOnlyWhenExplicitlyAllowed() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.userScripts)
        let scriptsDirectory = try makeTemporaryScriptsDirectory()
        let filename = "private-allowed.user.js"
        try writeScript(
            named: filename,
            in: scriptsDirectory,
            match: "https://www.example.test/*"
        )
        let container = try makeUserscriptContainer()
        let context = ModelContext(container)
        context.insert(
            UserScriptEntity(
                namespace: "https://example.test/module",
                name: "Module Test",
                version: nil,
                scriptDescription: nil,
                author: nil,
                iconURLString: nil,
                homepageURLString: nil,
                supportURLString: nil,
                downloadURLString: nil,
                updateURLString: nil,
                sourcePath: scriptsDirectory.appendingPathComponent(filename).path,
                contentHash: "",
                metadataJSON: "{}",
                isEnabled: true,
                allowPrivateBrowsing: true
            )
        )
        try context.save()
        let probe = UserscriptsRuntimeProbe()
        let module = makeModule(
            registry: registry,
            probe: probe,
            context: context,
            scriptsDirectory: scriptsDirectory
        )

        let scripts = module.normalTabUserScripts(
            for: URL(string: "https://www.example.test/page")!,
            webViewId: UUID(),
            profileId: UUID(),
            isEphemeral: true
        )

        XCTAssertEqual(scripts.count, 1)
    }

    func testDisablingModulePreventsFutureUserScriptContributions() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.userScripts)
        let scriptsDirectory = try makeTemporaryScriptsDirectory()
        try writeScript(
            named: "future.user.js",
            in: scriptsDirectory,
            match: "https://www.example.test/*"
        )
        let probe = UserscriptsRuntimeProbe()
        let module = makeModule(
            registry: registry,
            probe: probe,
            scriptsDirectory: scriptsDirectory
        )

        XCTAssertEqual(
            module.normalTabUserScripts(
                for: URL(string: "https://www.example.test/first")!,
                webViewId: UUID(),
                profileId: UUID(),
                isEphemeral: false
            )
            .count,
            1
        )

        module.setEnabled(false)

        XCTAssertNil(module.managerIfEnabled())
        XCTAssertTrue(
            module.normalTabUserScripts(
                for: URL(string: "https://www.example.test/second")!,
                webViewId: UUID(),
                profileId: UUID(),
                isEphemeral: false
            )
            .isEmpty
        )
        XCTAssertEqual(probe.managerCount, 1)
        XCTAssertEqual(probe.storeCount, 1)
        XCTAssertEqual(probe.injectorCount, 1)
    }

    func testModuleToggleDoesNotReloadOrInjectAlreadyLoadedPages() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = UserscriptsRuntimeProbe()
        let module = makeModule(registry: registry, probe: probe)

        module.setEnabled(true)
        module.setEnabled(false)

        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertEqual(probe.storeCount, 0)
        XCTAssertEqual(probe.injectorCount, 0)
    }

    func testAttachedModuleRoutesTabCommandsThroughRuntime() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.userScripts)
        let probe = UserscriptsRuntimeProbe()
        let module = makeModule(registry: registry, probe: probe)
        let browserManager = BrowserManager()
        browserManager.webViewCoordinator = WebViewCoordinator()
        let sourceSpace = browserManager.tabManager.createSpace(name: "Userscripts Source")
        let globalSpace = browserManager.tabManager.createSpace(name: "Userscripts Global")
        browserManager.tabManager.currentSpace = globalSpace
        let sourceWindow = BrowserWindowState()
        sourceWindow.currentSpaceId = sourceSpace.id
        let globalWindow = BrowserWindowState()
        globalWindow.currentSpaceId = globalSpace.id
        let windowRegistry = WindowRegistry()
        windowRegistry.register(sourceWindow)
        windowRegistry.register(globalWindow)
        windowRegistry.setActive(globalWindow)
        browserManager.windowRegistry = windowRegistry
        let sourceTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/source",
            in: sourceSpace,
            activate: false
        )
        sourceWindow.currentTabId = sourceTab.id
        let globalTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/global",
            in: globalSpace,
            activate: false
        )
        globalWindow.currentTabId = globalTab.id
        let sourceWebView = WKWebView()
        browserManager.webViewCoordinator?.setWebView(sourceWebView, for: sourceTab.id, in: sourceWindow.id)
        let initialSourceTabCount = browserManager.tabManager.tabs(in: sourceSpace).count
        let initialGlobalTabCount = browserManager.tabManager.tabs(in: globalSpace).count

        module.attach(runtime: .live(browserManager: browserManager))
        let manager = try XCTUnwrap(module.managerIfEnabled())

        manager.openTab(
            url: "https://example.com/userscript-open",
            background: false,
            sourceWebView: sourceWebView
        )

        let openedTab = try XCTUnwrap(
            browserManager.tabManager.tabs(in: sourceSpace).first {
                $0.url.absoluteString == "https://example.com/userscript-open"
            }
        )
        XCTAssertEqual(openedTab.url.absoluteString, "https://example.com/userscript-open")
        XCTAssertEqual(openedTab.spaceId, sourceSpace.id)
        XCTAssertEqual(sourceWindow.currentTabId, openedTab.id)
        XCTAssertEqual(globalWindow.currentTabId, globalTab.id)
        XCTAssertEqual(browserManager.tabManager.tabs(in: sourceSpace).count, initialSourceTabCount + 1)
        XCTAssertEqual(browserManager.tabManager.tabs(in: globalSpace).count, initialGlobalTabCount)

        manager.closeTab(tabId: openedTab.id.uuidString)

        XCTAssertNil(browserManager.tabManager.tab(for: openedTab.id))
        manager.closeTab(tabId: nil, sourceWebView: sourceWebView)
        XCTAssertNil(browserManager.tabManager.tab(for: sourceTab.id))
        XCTAssertNotNil(browserManager.tabManager.tab(for: globalTab.id))
    }

    private func makeModule(
        registry: SumiModuleRegistry,
        probe: UserscriptsRuntimeProbe,
        context: ModelContext? = nil,
        scriptsDirectory: URL? = nil
    ) -> SumiUserscriptsModule {
        SumiUserscriptsModule(
            moduleRegistry: registry,
            context: context,
            managerFactory: { context in
                probe.managerCount += 1
                return SumiScriptsManager(
                    context: context,
                    storeFactory: { context in
                        probe.storeCount += 1
                        return UserScriptStore(
                            directory: scriptsDirectory,
                            context: context
                        )
                    },
                    injectorFactory: {
                        probe.injectorCount += 1
                        return UserScriptInjector()
                    }
                )
            }
        )
    }

    private func makeTemporaryScriptsDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiUserscriptsModuleTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }

    private func makeUserscriptContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([UserScriptEntity.self, UserScriptResourceEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func writeScript(
        named filename: String,
        in directory: URL,
        match: String
    ) throws {
        let source = """
        // ==UserScript==
        // @name Module Test
        // @namespace https://example.test/module
        // @version 1.0
        // @match \(match)
        // ==/UserScript==
        window.__sumiUserscriptsModuleTest = true;
        """
        try source.write(
            to: directory.appendingPathComponent(filename),
            atomically: true,
            encoding: .utf8
        )
    }
}

private final class UserscriptsRuntimeProbe {
    var managerCount = 0
    var storeCount = 0
    var injectorCount = 0
}
