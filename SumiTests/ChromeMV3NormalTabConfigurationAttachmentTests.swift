import Foundation
import SwiftData
import WebKit
import XCTest

@testable import Sumi

final class ChromeMV3NormalTabConfigurationAttachmentTests: XCTestCase {
    @MainActor
    func testDefaultBrowserConfigHelperLeavesNormalTabUnattached() {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Chrome MV3 Default Off")

        let result = browserConfiguration
            .normalTabWebViewConfigurationWithChromeMV3AttachmentGate(
                for: profile,
                url: URL(string: "https://example.com")
            )

        XCTAssertTrue(result.configuration.sumiIsNormalTabWebViewConfiguration)
        XCTAssertNil(result.configuration.webExtensionController)
        XCTAssertFalse(result.diagnostics.normalTabConfigurationAttached)
        XCTAssertFalse(
            result.diagnostics.gateDecision
                .canAttachNormalTabConfigurationNow
        )
        XCTAssertTrue(
            result.diagnostics.gateDecision.blockers
                .contains(.extensionsModuleDisabled)
        )
        XCTAssertFalse(result.diagnostics.runtimeLoadable)
        XCTAssertFalse(result.diagnostics.canLoadContextNow)
    }

    @MainActor
    func testDisabledModuleLeavesNormalTabConfigurationUnattached() throws {
        let fixture = try makeModuleFixture(extensionsEnabled: false)
        defer { fixture.tearDown() }
        let request = fixture.module
            .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                explicitInternalNormalTabAttachmentAllowed: true
            )

        let result = fixture.browserConfiguration
            .normalTabWebViewConfigurationWithChromeMV3AttachmentGate(
                for: fixture.profile,
                url: URL(string: "https://example.com"),
                chromeMV3AttachmentRequest: request
            )

        XCTAssertNil(request)
        XCTAssertNil(result.configuration.webExtensionController)
        XCTAssertFalse(result.diagnostics.normalTabConfigurationAttached)
        XCTAssertFalse(
            result.diagnostics.gateDecision
                .canAttachNormalTabConfigurationNow
        )
        XCTAssertEqual(fixture.probe.ownerFactoryCount, 0)
        XCTAssertEqual(fixture.probe.managerCount, 0)
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    @MainActor
    func testEnabledModuleWithInternalGateOffLeavesNormalTabUnattached()
        throws
    {
        let fixture = try makeModuleFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        _ = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let request = try XCTUnwrap(
            fixture.module
                .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                    explicitInternalNormalTabAttachmentAllowed: false
                )
        )

        let result = fixture.browserConfiguration
            .normalTabWebViewConfigurationWithChromeMV3AttachmentGate(
                for: fixture.profile,
                url: URL(string: "https://example.com"),
                chromeMV3AttachmentRequest: request
            )

        XCTAssertNil(result.configuration.webExtensionController)
        XCTAssertFalse(result.diagnostics.normalTabConfigurationAttached)
        XCTAssertTrue(
            result.diagnostics.gateDecision.blockers.contains(
                .explicitInternalNormalTabAttachmentNotAllowed
            )
        )
        XCTAssertEqual(result.diagnostics.contextCount, 0)
        XCTAssertEqual(result.diagnostics.loadedExtensionCount, 0)
        XCTAssertEqual(result.diagnostics.nativeMessagingPortCount, 0)
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
        XCTAssertEqual(fixture.probe.managerCount, 0)
    }

    @MainActor
    func testEnabledInternalGateAttachesSameEmptyControllerToNormalTabOnly()
        throws
    {
        let fixture = try makeModuleFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        let owner = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let controller = try XCTUnwrap(owner.controller)
        let request = try XCTUnwrap(
            fixture.module
                .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                    explicitInternalNormalTabAttachmentAllowed: true
                )
        )

        let result = fixture.browserConfiguration
            .normalTabWebViewConfigurationWithChromeMV3AttachmentGate(
                for: fixture.profile,
                url: URL(string: "https://example.com"),
                chromeMV3AttachmentRequest: request
            )
        let attachedController = try XCTUnwrap(
            result.configuration.webExtensionController
        )

        XCTAssertEqual(
            ObjectIdentifier(attachedController),
            ObjectIdentifier(controller)
        )
        XCTAssertTrue(result.configuration.sumiIsNormalTabWebViewConfiguration)
        XCTAssertTrue(
            result.configuration.sumiHasChromeMV3NormalTabConfigurationAttachment
        )
        XCTAssertTrue(result.diagnostics.normalTabConfigurationAttached)
        XCTAssertFalse(result.diagnostics.auxiliaryConfigurationAttached)
        XCTAssertTrue(result.diagnostics.attachedControllerMatchesOwner)
        XCTAssertTrue(
            result.diagnostics.gateDecision
                .canAttachNormalTabConfigurationNow
        )
        XCTAssertFalse(
            result.diagnostics.gateDecision
                .canAttachAuxiliaryConfigurationNow
        )
        XCTAssertEqual(result.diagnostics.contextCount, 0)
        XCTAssertEqual(result.diagnostics.loadedExtensionCount, 0)
        XCTAssertEqual(result.diagnostics.attachedWebViewCount, 0)
        XCTAssertFalse(result.diagnostics.webExtensionCreated)
        XCTAssertFalse(result.diagnostics.webExtensionContextCreated)
        XCTAssertFalse(result.diagnostics.contextLoadCalled)
        XCTAssertFalse(result.diagnostics.generatedExtensionBundleLoaded)
        XCTAssertFalse(result.diagnostics.nativeMessagingLaunched)
        XCTAssertEqual(result.diagnostics.nativeMessagingPortCount, 0)
        XCTAssertFalse(result.diagnostics.runtimeLoadable)
        XCTAssertFalse(result.diagnostics.canLoadContextNow)
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
        XCTAssertEqual(fixture.probe.managerCount, 0)
    }

    @MainActor
    func testPinnedEssentialsLiveNormalBrowsingFollowsNormalTabGate()
        throws
    {
        let fixture = try makeModuleFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        let owner = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let controller = try XCTUnwrap(owner.controller)
        let request = try XCTUnwrap(
            fixture.module
                .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                    explicitInternalNormalTabAttachmentAllowed: true,
                    surface: .pinnedEssentialsLiveNormalBrowsing
                )
        )

        let result = fixture.browserConfiguration
            .normalTabWebViewConfigurationWithChromeMV3AttachmentGate(
                for: fixture.profile,
                url: URL(string: "https://example.com"),
                chromeMV3AttachmentRequest: request
            )
        let attachedController = try XCTUnwrap(
            result.configuration.webExtensionController
        )

        XCTAssertEqual(
            ObjectIdentifier(attachedController),
            ObjectIdentifier(controller)
        )
        XCTAssertEqual(
            result.diagnostics.gateDecision.input.surface,
            .pinnedEssentialsLiveNormalBrowsing
        )
        XCTAssertTrue(result.diagnostics.normalTabConfigurationAttached)
        XCTAssertEqual(result.diagnostics.contextCount, 0)
        XCTAssertFalse(result.diagnostics.canLoadContextNow)
    }

    @MainActor
    func testLauncherPreviewMiniFaviconDownloadHelperAndExtensionUISurfacesDoNotAttach()
        throws
    {
        let fixture = try makeModuleFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        _ = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let browserConfiguration = fixture.browserConfiguration
        let normalConfiguration = browserConfiguration.normalTabWebViewConfiguration(
            for: fixture.profile,
            url: URL(string: "https://example.com")
        )
        let auxiliaryConfigurations: [(ChromeMV3WebViewSurface, WKWebViewConfiguration)] = [
            (
                .peekGlancePreview,
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: .glance
                )
            ),
            (
                .miniWindow,
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: .miniWindow
                )
            ),
            (
                .faviconDownload,
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: .faviconDownload
                )
            ),
            (
                .downloadHelper,
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: .faviconDownload
                )
            ),
            (
                .helperWebView,
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: .miniWindow
                )
            ),
            (
                .extensionOwnedPopup,
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: .extensionOptions
                )
            ),
            (
                .extensionOwnedOptionsPage,
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: .extensionOptions
                )
            ),
        ]

        let launcherRequest = try XCTUnwrap(
            fixture.module
                .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                    explicitInternalNormalTabAttachmentAllowed: true,
                    surface: .pinnedEssentialsLauncherMetadata
                )
        )
        let launcherDiagnostics =
            ChromeMV3NormalTabConfigurationAttachmentBridge.attachIfAllowed(
                configuration: normalConfiguration,
                request: launcherRequest
            )
        XCTAssertNil(normalConfiguration.webExtensionController)
        XCTAssertFalse(launcherDiagnostics.normalTabConfigurationAttached)
        XCTAssertTrue(
            launcherDiagnostics.gateDecision.blockers
                .contains(.launcherMetadataSurface)
        )

        for (surface, configuration) in auxiliaryConfigurations {
            let request = try XCTUnwrap(
                fixture.module
                    .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                        explicitInternalNormalTabAttachmentAllowed: true,
                        surface: surface
                    )
            )
            let diagnostics =
                ChromeMV3NormalTabConfigurationAttachmentBridge
                    .attachIfAllowed(
                        configuration: configuration,
                        request: request
                    )

            XCTAssertNil(configuration.webExtensionController, surface.rawValue)
            XCTAssertFalse(
                diagnostics.normalTabConfigurationAttached,
                surface.rawValue
            )
            XCTAssertFalse(
                diagnostics.auxiliaryConfigurationAttached,
                surface.rawValue
            )
            XCTAssertFalse(
                diagnostics.gateDecision.canAttachNormalTabConfigurationNow,
                surface.rawValue
            )
            XCTAssertFalse(
                diagnostics.gateDecision.canAttachAuxiliaryConfigurationNow,
                surface.rawValue
            )
            XCTAssertEqual(diagnostics.contextCount, 0, surface.rawValue)
            XCTAssertEqual(diagnostics.loadedExtensionCount, 0, surface.rawValue)
        }
    }

    @MainActor
    func testExtensionOptionsLegacyCopyDoesNotPropagateMarkedChromeMV3NormalTabAttachment()
        throws
    {
        let fixture = try makeModuleFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        _ = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let request = try XCTUnwrap(
            fixture.module
                .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                    explicitInternalNormalTabAttachmentAllowed: true
                )
        )
        let attachedNormal = fixture.browserConfiguration
            .normalTabWebViewConfigurationWithChromeMV3AttachmentGate(
                for: fixture.profile,
                url: URL(string: "https://example.com"),
                chromeMV3AttachmentRequest: request
            )

        let optionsConfiguration = fixture.browserConfiguration
            .auxiliaryWebViewConfiguration(
                from: attachedNormal.configuration,
                surface: .extensionOptions
            )

        XCTAssertNotNil(attachedNormal.configuration.webExtensionController)
        XCTAssertTrue(
            attachedNormal.configuration
                .sumiHasChromeMV3NormalTabConfigurationAttachment
        )
        XCTAssertNil(optionsConfiguration.webExtensionController)
        XCTAssertFalse(
            optionsConfiguration.sumiHasChromeMV3NormalTabConfigurationAttachment
        )
        XCTAssertFalse(optionsConfiguration.sumiIsNormalTabWebViewConfiguration)
    }

    @MainActor
    func testTeardownDetachesTrackedNormalTabConfigurationAndFutureDiagnosticsBlock()
        throws
    {
        let fixture = try makeModuleFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        _ = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let request = try XCTUnwrap(
            fixture.module
                .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                    explicitInternalNormalTabAttachmentAllowed: true
                )
        )
        let result = fixture.browserConfiguration
            .normalTabWebViewConfigurationWithChromeMV3AttachmentGate(
                for: fixture.profile,
                url: URL(string: "https://example.com"),
                chromeMV3AttachmentRequest: request
            )

        XCTAssertNotNil(result.configuration.webExtensionController)
        XCTAssertTrue(
            result.configuration.sumiHasChromeMV3NormalTabConfigurationAttachment
        )

        let teardown = try XCTUnwrap(
            fixture.module.tearDownChromeMV3EmptyControllerOwnerIfEnabled(
                trigger: .moduleDisable
            )
        )
        let postTeardownRequest = try XCTUnwrap(
            fixture.module
                .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                    explicitInternalNormalTabAttachmentAllowed: true
                )
        )
        let diagnostics =
            ChromeMV3NormalTabConfigurationAttachmentBridge.inspect(
                configuration: result.configuration,
                request: postTeardownRequest
            )

        XCTAssertNil(result.configuration.webExtensionController)
        XCTAssertFalse(
            result.configuration.sumiHasChromeMV3NormalTabConfigurationAttachment
        )
        XCTAssertEqual(teardown.contextCount, 0)
        XCTAssertEqual(teardown.loadedExtensionCount, 0)
        XCTAssertEqual(teardown.nativeMessagingPortCount, 0)
        XCTAssertFalse(diagnostics.normalTabConfigurationAttached)
        XCTAssertTrue(
            diagnostics.gateDecision.blockers.contains(.emptyControllerMissing)
        )
        XCTAssertFalse(diagnostics.runtimeLoadable)
        XCTAssertFalse(diagnostics.canLoadContextNow)
    }

    func testGateBlocksContextLoadabilityAndRuntimeReadinessRequests() {
        let requested = !false
        let contextDecision = ChromeMV3NormalTabConfigurationAttachmentGate
            .evaluate(
                input: gateInput(
                    requestedContextLoading: requested
                )
            )
        let loadCapabilityDecision = ChromeMV3NormalTabConfigurationAttachmentGate
            .evaluate(
                input: gateInput(
                    canLoadContextNow: requested
                )
            )
        let loadabilityDecision = ChromeMV3NormalTabConfigurationAttachmentGate
            .evaluate(
                input: gateInput(
                    runtimeLoadable: requested
                )
            )

        XCTAssertFalse(
            contextDecision.canAttachNormalTabConfigurationNow
        )
        XCTAssertTrue(
            contextDecision.blockers.contains(.contextLoadingRequested)
        )
        XCTAssertFalse(contextDecision.canLoadContextNow)
        XCTAssertFalse(contextDecision.runtimeLoadable)

        XCTAssertFalse(
            loadCapabilityDecision.canAttachNormalTabConfigurationNow
        )
        XCTAssertTrue(
            loadCapabilityDecision.blockers.contains(
                .contextLoadingCapabilityEnabled
            )
        )
        XCTAssertFalse(loadCapabilityDecision.canLoadContextNow)

        XCTAssertFalse(loadabilityDecision.canAttachNormalTabConfigurationNow)
        XCTAssertTrue(
            loadabilityDecision.blockers.contains(.runtimeLoadableRequested)
        )
        XCTAssertFalse(loadabilityDecision.runtimeLoadable)
    }

    func testSourceGuardForNormalTabAttachmentBoundary() throws {
        let sourceFiles = try Self.sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
            "Sumi/Models/BrowserConfig",
            "Sumi/Models/Tab",
            "Sumi/Components/MiniWindow",
            "Sumi/Favicons",
            "Sumi/Managers/GlanceManager",
        ])
        let assignmentFiles = sourceFiles
            .filter { $0.contents.contains("webExtensionController" + " =") }
            .map(\.relativePath)
            .sorted()

        XCTAssertEqual(
            assignmentFiles,
            [
                "Sumi/Models/BrowserConfig/BrowserConfig.swift",
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3NormalTabConfigurationAttachmentBridge.swift",
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3SyntheticConfigurationAttachmentHarness.swift",
            ]
        )

        let chromeMV3Source = try Self.sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
        ])
        let source = chromeMV3Source.map(\.contents).joined(separator: "\n")
        for forbidden in [
            "WKWebExtension" + "(",
            "WKWebExtension" + "Context(",
            "load" + "ExtensionContext",
            "add" + "UserScript",
            "connect" + "Native",
            "DispatchSource" + "Ti" + "mer",
            "scheduled" + "Ti" + "mer",
            "Ti" + "mer",
            "poll" + "ing",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    private func gateInput(
        extensionsModuleEnabled: Bool = true,
        profileHostEnabled: Bool = true,
        emptyControllerExists: Bool = true,
        explicitInternalNormalTabAttachmentAllowed: Bool = true,
        surface: ChromeMV3WebViewSurface = .normalTab,
        isRealNormalTabConfiguration: Bool = true,
        configurationHasControllerAttachment: Bool = false,
        requestedContextLoading: Bool = false,
        canLoadContextNow: Bool = false,
        runtimeLoadable: Bool = false,
        contextCount: Int = 0,
        loadedExtensionCount: Int = 0,
        nativeMessagingPortCount: Int = 0
    ) -> ChromeMV3NormalTabConfigurationAttachmentGateInput {
        ChromeMV3NormalTabConfigurationAttachmentGateInput(
            extensionsModuleEnabled: extensionsModuleEnabled,
            profileHostEnabled: profileHostEnabled,
            emptyControllerExists: emptyControllerExists,
            explicitInternalNormalTabAttachmentAllowed:
                explicitInternalNormalTabAttachmentAllowed,
            surface: surface,
            isRealNormalTabConfiguration: isRealNormalTabConfiguration,
            configurationHasControllerAttachment:
                configurationHasControllerAttachment,
            requestedContextLoading: requestedContextLoading,
            canLoadContextNow: canLoadContextNow,
            runtimeLoadable: runtimeLoadable,
            contextCount: contextCount,
            loadedExtensionCount: loadedExtensionCount,
            nativeMessagingPortCount: nativeMessagingPortCount
        )
    }

    @MainActor
    private func makeModuleFixture(
        extensionsEnabled: Bool
    ) throws -> ChromeMV3NormalTabAttachmentModuleFixture {
        let harness = TestDefaultsHarness()
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        if extensionsEnabled {
            registry.enable(.extensions)
        }
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Chrome MV3 Normal Attachment Test")
        let probe = ChromeMV3NormalTabAttachmentModuleProbe()
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: {
                probe.profileProviderCount += 1
                return profile
            },
            managerFactory: { context, initialProfile, browserConfiguration in
                probe.managerCount += 1
                return ExtensionManager(
                    context: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration
                )
            },
            chromeMV3EmptyControllerOwnerFactory: { decision, dataStore, identifier in
                probe.ownerFactoryCount += 1
                return ChromeMV3EmptyControllerFactory.makeOwner(
                    gateDecision: decision,
                    defaultWebsiteDataStore: dataStore,
                    controllerIdentifier: identifier
                )
            }
        )

        return ChromeMV3NormalTabAttachmentModuleFixture(
            defaultsHarness: harness,
            browserConfiguration: browserConfiguration,
            profile: profile,
            module: module,
            probe: probe
        )
    }

    private static func sourceFiles(
        in directories: [String]
    ) throws -> [(relativePath: String, contents: String)] {
        try directories.flatMap { directory
            -> [(relativePath: String, contents: String)] in
            let root = repoRoot.appendingPathComponent(directory)
            guard FileManager.default.fileExists(atPath: root.path) else {
                return []
            }
            let urls = FileManager.default
                .enumerator(
                    at: root,
                    includingPropertiesForKeys: nil
                )?
                .compactMap { $0 as? URL } ?? []
            return try urls
                .filter { $0.pathExtension == "swift" }
                .map { url in
                    let relativePath = url.path
                        .replacingOccurrences(
                            of: repoRoot.path + "/",
                            with: ""
                        )
                    return (
                        relativePath,
                        try String(contentsOf: url, encoding: .utf8)
                    )
                }
        }
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
private struct ChromeMV3NormalTabAttachmentModuleFixture {
    let defaultsHarness: TestDefaultsHarness
    let browserConfiguration: BrowserConfiguration
    let profile: Profile
    let module: SumiExtensionsModule
    let probe: ChromeMV3NormalTabAttachmentModuleProbe

    func tearDown() {
        defaultsHarness.reset()
    }
}

@MainActor
private final class ChromeMV3NormalTabAttachmentModuleProbe {
    var profileProviderCount = 0
    var managerCount = 0
    var ownerFactoryCount = 0
}
