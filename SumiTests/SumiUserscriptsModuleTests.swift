import UserScript
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiUserscriptsModuleTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
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

        XCTAssertTrue(firstManager === secondManager)
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

    func testModuleToggleDoesNotReloadOrInjectAlreadyLoadedPages() throws {
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

        let source = try Self.source(
            named: "Sumi/Managers/SumiScripts/SumiUserscriptsModule.swift"
        )
        XCTAssertFalse(source.contains("reload("))
        XCTAssertFalse(source.contains("webView.reload"))
        XCTAssertFalse(source.contains("evaluateJavaScript"))
        XCTAssertFalse(source.contains("replaceNormalTabUserScripts"))
    }

    func testUserscriptsModuleSourceDoesNotTouchOtherOptionalRuntimes() throws {
        let source = try Self.source(
            named: "Sumi/Managers/SumiScripts/SumiUserscriptsModule.swift"
        )

        for forbiddenPattern in [
            "ExtensionManager(",
            "NativeMessagingHandler(",
            "SumiTrackingProtectionModule",
            "SumiTrackingRuleListPipeline",
            "SumiContentBlockingService",
        ] {
            XCTAssertFalse(source.contains(forbiddenPattern), forbiddenPattern)
        }
    }

    func testUserscriptsManagerDoesNotPersistLegacyMasterSwitch() throws {
        let source = try Self.source(
            named: "Sumi/Managers/SumiScripts/SumiScriptsManager.swift"
        )

        XCTAssertFalse(source.contains("SumiScripts.enabled"))
    }

    private func makeModule(
        registry: SumiModuleRegistry,
        probe: UserscriptsRuntimeProbe,
        scriptsDirectory: URL? = nil
    ) -> SumiUserscriptsModule {
        SumiUserscriptsModule(
            moduleRegistry: registry,
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

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}

private final class UserscriptsRuntimeProbe {
    var managerCount = 0
    var storeCount = 0
    var injectorCount = 0
}
