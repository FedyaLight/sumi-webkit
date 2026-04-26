import SwiftData
import UserScript
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiExtensionsModuleTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private var temporaryDirectories: [URL] = []
    private var defaultsSnapshots: [String: Any] = [:]
    private var missingDefaultsKeys: Set<String> = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        containers = []
        temporaryDirectories = []
        defaultsSnapshots = [:]
        missingDefaultsKeys = []
        preserveDefaultsValueIfNeeded(for: pinnedToolbarStorageKey)
        preserveDefaultsValueIfNeeded(for: ExtensionManager.controllerIdentifierKey)
        #if DEBUG
            preserveDefaultsValueIfNeeded(for: ExtensionManager.testControllerIdentifiersDefaultsKey)
        #endif
        UserDefaults.standard.removeObject(forKey: pinnedToolbarStorageKey)
        UserDefaults.standard.removeObject(forKey: ExtensionManager.controllerIdentifierKey)
        #if DEBUG
            UserDefaults.standard.removeObject(forKey: ExtensionManager.testControllerIdentifiersDefaultsKey)
        #endif
    }

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        containers.removeAll()
        temporaryDirectories.removeAll()

        let defaults = UserDefaults.standard
        for (key, value) in defaultsSnapshots {
            defaults.set(value, forKey: key)
        }
        for key in missingDefaultsKeys {
            defaults.removeObject(forKey: key)
        }

        defaultsSnapshots = [:]
        missingDefaultsKeys = []
        try super.tearDownWithError()
    }

    func testDisabledModuleReturnsEmptySurfacesWithoutConstructingRuntime() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = ExtensionsRuntimeProbe()
        let module = try makeModule(registry: registry, probe: probe)

        XCTAssertFalse(module.isEnabled)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertNil(module.managerIfEnabled())
        XCTAssertNil(module.managerIfLoadedAndEnabled())
        XCTAssertTrue(module.normalTabUserScripts().isEmpty)
        XCTAssertTrue(module.surfaceStore.installedExtensions.isEmpty)

        let configuration = WKWebViewConfiguration()
        module.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            reason: "SumiExtensionsModuleTests.disabled.configuration"
        )
        XCTAssertNil(configuration.webExtensionController)

        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        module.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: URL(string: "https://example.com"),
            reason: "SumiExtensionsModuleTests.disabled.webView"
        )
        module.releaseExternallyConnectableRuntimeIfLoaded(
            for: webView,
            reason: "SumiExtensionsModuleTests.disabled.release"
        )

        XCTAssertTrue(
            module.orderedPinnedToolbarSlots(
                enabledExtensions: [],
                sumiScriptsManagerEnabled: true
            ).isEmpty
        )
        XCTAssertFalse(module.isPinnedToToolbar("disabled.extension"))
        let discoveredExtensions = await module.discoverSafariExtensions()
        XCTAssertTrue(discoveredExtensions.isEmpty)

        let installCompletion = expectation(description: "disabled install completes without runtime")
        module.installSafariExtension(makeSafariExtensionInfo()) { result in
            if case .success = result {
                XCTFail("Disabled module should not install Safari extensions")
            }
            installCompletion.fulfill()
        }
        await fulfillment(of: [installCompletion], timeout: 1)

        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testEnabledModulePersistsAndConstructsManagerLazily() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)
        let probe = ExtensionsRuntimeProbe()
        let module = try makeModule(registry: registry, probe: probe)

        module.setEnabled(true)

        XCTAssertTrue(registry.isEnabled(.extensions))
        XCTAssertTrue(SumiModuleRegistry(settingsStore: store).isEnabled(.extensions))
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertEqual(probe.managerCount, 0)

        let manager = try XCTUnwrap(module.managerIfEnabled())

        XCTAssertTrue(module.hasLoadedRuntime)
        XCTAssertTrue(manager === module.managerIfEnabled())
        XCTAssertTrue(manager === module.managerIfLoadedAndEnabled())
        XCTAssertEqual(probe.managerCount, 1)
    }

    func testEnabledManagementSurfaceBindsAfterLazyManagerCreation() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = ExtensionsRuntimeProbe()
        let module = try makeModule(registry: registry, probe: probe)
        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: Self.externallyConnectableManifest(name: "Surface Fixture")
        )
        let record = makeInstalledExtensionRecord(
            id: "surface.fixture",
            packageURL: extensionRoot,
            manifest: Self.externallyConnectableManifest(name: "Surface Fixture")
        )

        module.setEnabled(true)
        XCTAssertTrue(module.surfaceStore.installedExtensions.isEmpty)
        XCTAssertEqual(probe.managerCount, 0)

        let manager = try XCTUnwrap(module.managerIfEnabled())
        manager.debugReplaceInstalledExtensions([record])
        try await waitUntil {
            module.surfaceStore.enabledExtensions.map(\.id) == [record.id]
        }

        XCTAssertEqual(probe.managerCount, 1)
        XCTAssertEqual(module.surfaceStore.enabledExtensions.map(\.id), [record.id])
    }

    func testEnabledNormalTabScriptsCanContributeExternallyConnectableBridgeAndDisableBlocksFutureAttachment() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = ExtensionsRuntimeProbe()
        let module = try makeModule(registry: registry, probe: probe)
        let manifest = Self.externallyConnectableManifest(name: "Bridge Fixture")
        let extensionRoot = try makeUnpackedExtensionDirectory(manifest: manifest)
        let record = makeInstalledExtensionRecord(
            id: "bridge.fixture",
            packageURL: extensionRoot,
            manifest: manifest
        )

        module.setEnabled(true)
        let manager = try XCTUnwrap(module.managerIfEnabled())
        manager.debugReplaceInstalledExtensions([record])
        manager.debugSetupExternallyConnectablePageBridge(
            extensionId: record.id,
            packagePath: extensionRoot.path
        )

        let enabledScripts = module.normalTabUserScripts()
        let enabledSource = enabledScripts.map(\.source).joined(separator: "\n")
        XCTAssertEqual(enabledScripts.count, 1)
        XCTAssertTrue(enabledSource.contains("SUMI_EC_PAGE_BRIDGE:"))
        XCTAssertEqual(probe.managerCount, 1)

        module.setEnabled(false)

        XCTAssertFalse(registry.isEnabled(.extensions))
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertNil(module.managerIfLoadedAndEnabled())
        XCTAssertTrue(module.normalTabUserScripts().isEmpty)

        let disabledConfiguration = WKWebViewConfiguration()
        module.prepareWebViewConfigurationForExtensionRuntime(
            disabledConfiguration,
            reason: "SumiExtensionsModuleTests.disabledAfterEnabled"
        )
        XCTAssertNil(disabledConfiguration.webExtensionController)
        XCTAssertEqual(probe.managerCount, 1)
    }

    func testEnabledWebViewConfigurationPreparationConstructsRuntimeOnlyOnDemand() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = ExtensionsRuntimeProbe()
        let manifest = Self.contentScriptManifest(name: "Content Script Fixture")
        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: manifest,
            extraFiles: ["content.js": "window.__sumiExtensionContentScriptFixture = true;"]
        )
        let record = makeInstalledExtensionRecord(
            id: "content.fixture",
            packageURL: extensionRoot,
            manifest: manifest,
            hasContentScripts: true
        )
        let module = try makeModule(registry: registry, probe: probe) { manager in
            manager.debugReplaceInstalledExtensions([record])
        }

        module.setEnabled(true)
        XCTAssertEqual(probe.managerCount, 0)

        let configuration = WKWebViewConfiguration()
        module.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            reason: "SumiExtensionsModuleTests.enabled.configuration"
        )

        XCTAssertEqual(probe.managerCount, 1)
        XCTAssertNotNil(configuration.webExtensionController)
        XCTAssertTrue(module.hasLoadedRuntime)
    }

    func testToolbarAndOptionsAccessStayBehindModule() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = ExtensionsRuntimeProbe()
        let module = try makeModule(registry: registry, probe: probe)

        XCTAssertTrue(
            module.orderedPinnedToolbarSlots(
                enabledExtensions: [],
                sumiScriptsManagerEnabled: true
            ).isEmpty
        )
        XCTAssertFalse(module.isPinnedToToolbar("toolbar.fixture"))
        XCTAssertEqual(probe.managerCount, 0)

        let optionsConfiguration = BrowserConfiguration().auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        module.prepareWebViewConfigurationForExtensionRuntime(
            optionsConfiguration,
            reason: "SumiExtensionsModuleTests.disabled.options"
        )
        XCTAssertNil(optionsConfiguration.webExtensionController)
        XCTAssertEqual(probe.managerCount, 0)

        module.setEnabled(true)
        module.pinToToolbar("toolbar.fixture")

        let manager = try XCTUnwrap(module.managerIfLoadedAndEnabled())
        XCTAssertTrue(manager.isPinnedToToolbar("toolbar.fixture"))
        XCTAssertTrue(module.isPinnedToToolbar("toolbar.fixture"))
        XCTAssertEqual(probe.managerCount, 1)

        module.unpinFromToolbar("toolbar.fixture")
        XCTAssertFalse(module.isPinnedToToolbar("toolbar.fixture"))
    }

    func testNativeMessagingConstructionRemainsInsideExtensionRuntimePath() throws {
        let moduleSource = try Self.source(named: "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift")
        let delegateSource = try Self.source(named: "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift")

        XCTAssertFalse(moduleSource.contains("NativeMessagingHandler("))
        XCTAssertTrue(delegateSource.contains("NativeMessagingHandler("))
    }

    func testModuleToggleDoesNotReloadOrInjectAlreadyLoadedPages() throws {
        let moduleSource = try Self.source(named: "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift")

        for forbiddenPattern in [
            "reload()",
            "webView.reload",
            "currentTab?.refresh",
            "evaluateJavaScript",
            "replaceManagedUserScripts",
            "replaceUserScripts",
        ] {
            XCTAssertFalse(moduleSource.contains(forbiddenPattern), forbiddenPattern)
        }
    }

    func testCoreScriptAndModuleBoundariesRemainSeparate() throws {
        let tabRuntimeSource = try Self.source(named: "Sumi/Models/Tab/Tab+WebViewRuntime.swift")
        let moduleSource = try Self.source(named: "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift")

        XCTAssertTrue(tabRuntimeSource.contains("var scripts = normalTabCoreUserScripts()"))
        XCTAssertTrue(tabRuntimeSource.contains("extensionsModule.normalTabUserScripts()"))
        XCTAssertTrue(tabRuntimeSource.contains("userscriptsModule.normalTabUserScripts"))
        XCTAssertFalse(moduleSource.contains("SumiTabSuspensionUserScript"))
        XCTAssertFalse(moduleSource.contains("SumiUserscriptsModule"))
        XCTAssertFalse(moduleSource.contains("SumiTrackingProtectionModule"))
        XCTAssertFalse(moduleSource.contains("SumiContentBlockingService"))
    }

    private func makeModule(
        registry: SumiModuleRegistry,
        probe: ExtensionsRuntimeProbe,
        configureManager: ((ExtensionManager) -> Void)? = nil
    ) throws -> SumiExtensionsModule {
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        containers.append(container)
        let initialProfile = Profile(name: "Extensions Module Tests")

        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: { initialProfile },
            managerFactory: { context, initialProfile, browserConfiguration in
                probe.managerCount += 1
                let manager = ExtensionManager(
                    context: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration
                )
                configureManager?(manager)
                return manager
            }
        )
    }

    private func makeUnpackedExtensionDirectory(
        manifest: [String: Any],
        extraFiles: [String: String] = [:]
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiExtensionsModuleTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)

        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        )
        try manifestData.write(to: directory.appendingPathComponent("manifest.json"))
        for (relativePath, contents) in extraFiles {
            let fileURL = directory.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return directory
    }

    private func makeInstalledExtensionRecord(
        id: String,
        packageURL: URL,
        manifest: [String: Any],
        hasContentScripts: Bool = false
    ) -> InstalledExtension {
        InstalledExtension(
            id: id,
            name: manifest["name"] as? String ?? id,
            version: manifest["version"] as? String ?? "1.0",
            manifestVersion: manifest["manifest_version"] as? Int ?? 3,
            description: nil,
            isEnabled: true,
            installDate: Date(timeIntervalSince1970: 0),
            lastUpdateDate: Date(timeIntervalSince1970: 0),
            packagePath: packageURL.path,
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: id,
            manifestRootFingerprint: id,
            sourceBundlePath: packageURL.path,
            teamID: nil,
            appBundleID: nil,
            appexBundleID: nil,
            optionsPagePath: nil,
            defaultPopupPath: nil,
            hasBackground: false,
            hasAction: true,
            hasOptionsPage: false,
            hasContentScripts: hasContentScripts,
            hasExtensionPages: false,
            trustSummary: SafariExtensionTrustSummary(
                state: .developmentDirectory,
                teamID: nil,
                appBundleID: nil,
                appexBundleID: nil,
                signingIdentifier: nil,
                sourcePath: packageURL.path,
                importedAt: Date(timeIntervalSince1970: 0)
            ),
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: ["https://example.com/*"],
                broadScope: false,
                hasContentScripts: hasContentScripts,
                hasAction: true,
                hasOptionsPage: false,
                hasExtensionPages: false
            ),
            manifest: manifest
        )
    }

    private func makeSafariExtensionInfo() -> SafariExtensionInfo {
        let appURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DisabledExtension.app", isDirectory: true)
        let appexURL = appURL
            .appendingPathComponent("Contents/PlugIns/DisabledExtension.appex", isDirectory: true)
        return SafariExtensionInfo(
            id: "disabled.extension.info",
            name: "Disabled Extension",
            appPath: appURL,
            appexPath: appexURL
        )
    }

    private func preserveDefaultsValueIfNeeded(for key: String) {
        let defaults = UserDefaults.standard
        if let value = defaults.object(forKey: key) {
            defaultsSnapshots[key] = value
        } else {
            missingDefaultsKeys.insert(key)
        }
    }

    private var pinnedToolbarStorageKey: String {
        "\(SumiAppIdentity.bundleIdentifier).extensions.toolbarPinnedIDsByProfile"
    }

    private static func externallyConnectableManifest(name: String) -> [String: Any] {
        [
            "manifest_version": 3,
            "name": name,
            "version": "1.0",
            "externally_connectable": [
                "matches": ["https://accounts.example.com/*"]
            ],
        ]
    }

    private static func contentScriptManifest(name: String) -> [String: Any] {
        [
            "manifest_version": 3,
            "name": name,
            "version": "1.0",
            "content_scripts": [
                [
                    "matches": ["https://example.com/*"],
                    "js": ["content.js"],
                ],
            ],
        ]
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(predicate())
    }
}

private final class ExtensionsRuntimeProbe {
    var managerCount = 0
}
