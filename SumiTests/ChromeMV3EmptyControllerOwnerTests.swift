import Foundation
import SwiftData
import WebKit
import XCTest

@testable import Sumi

final class ChromeMV3EmptyControllerOwnerTests: XCTestCase {
    func testDisabledModuleGateCannotCreateController() {
        let decision = makeDecision(
            extensionsModuleEnabled: false,
            hostEnabled: false,
            explicitControllerCreationAllowed: true
        )

        XCTAssertFalse(decision.canCreateControllerNow)
        XCTAssertFalse(decision.canLoadContextNow)
        XCTAssertFalse(decision.canAttachToNormalTabsNow)
        XCTAssertFalse(decision.runtimeLoadable)
        XCTAssertTrue(decision.blockers.contains(.extensionsModuleDisabled))
        XCTAssertTrue(decision.blockers.contains(.profileHostDisabled))
    }

    func testEnabledHostWithoutExplicitGateCannotCreateController() {
        let decision = makeDecision(
            explicitControllerCreationAllowed: false
        )

        XCTAssertFalse(decision.canCreateControllerNow)
        XCTAssertFalse(decision.canLoadContextNow)
        XCTAssertFalse(decision.canAttachToNormalTabsNow)
        XCTAssertFalse(decision.runtimeLoadable)
        XCTAssertEqual(decision.blockers, [.explicitControllerCreationNotAllowed])
    }

    func testControllerGateRejectsContextLoadingAndNormalTabAttachmentRequests() {
        let decision = makeDecision(
            explicitControllerCreationAllowed: true,
            requestedContextLoading: true,
            requestedNormalTabAttachment: true
        )

        XCTAssertFalse(decision.canCreateControllerNow)
        XCTAssertFalse(decision.canLoadContextNow)
        XCTAssertFalse(decision.canAttachToNormalTabsNow)
        XCTAssertFalse(decision.runtimeLoadable)
        XCTAssertTrue(decision.blockers.contains(.contextLoadingRequested))
        XCTAssertTrue(decision.blockers.contains(.normalTabAttachmentRequested))
    }

    func testControllerGateRequiresProfileAndWebsiteDataStoreIdentity() {
        let decision = makeDecision(
            explicitControllerCreationAllowed: true,
            profileIdentifier: ChromeMV3ProfileHost.unresolvedProfileIdentifier,
            profileDataStoreIdentity: .unresolved
        )

        XCTAssertFalse(decision.canCreateControllerNow)
        XCTAssertTrue(decision.blockers.contains(.profileIdentityUnavailable))
        XCTAssertTrue(
            decision.blockers.contains(.websiteDataStoreIdentityUnavailable)
        )
    }

    func testControllerGateRejectsDisabledRuntimeInvariantViolation() {
        var invariantStatus = ChromeMV3DisabledRuntimeInvariantStatus.satisfied
        invariantStatus.noControllerObjectCreated = false

        let decision = makeDecision(
            explicitControllerCreationAllowed: true,
            disabledRuntimeInvariantStatus: invariantStatus
        )

        XCTAssertFalse(decision.canCreateControllerNow)
        XCTAssertTrue(
            decision.blockers.contains(.disabledRuntimeInvariantViolation)
        )
    }

    @MainActor
    func testBlockedGateDoesNotCreateOwner() {
        let decision = makeDecision(
            explicitControllerCreationAllowed: false
        )

        let owner = ChromeMV3EmptyControllerFactory.makeOwner(
            gateDecision: decision,
            defaultWebsiteDataStore: .nonPersistent(),
            controllerIdentifier: UUID()
        )

        XCTAssertNil(owner)
    }

    @MainActor
    func testEnabledExplicitGateCreatesEmptyControllerOnly() throws {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let decision = makeDecision(
            explicitControllerCreationAllowed: true,
            profileDataStoreIdentity: .ephemeralProfileIdentifier("profile-1")
        )

        let owner = try XCTUnwrap(
            ChromeMV3EmptyControllerFactory.makeOwner(
                gateDecision: decision,
                defaultWebsiteDataStore: dataStore,
                controllerIdentifier: UUID()
            )
        )
        let controller = try XCTUnwrap(owner.controller)
        let webViewConfiguration = try XCTUnwrap(
            controller.configuration.webViewConfiguration
        )
        let diagnostics = owner.diagnostics()

        XCTAssertEqual(owner.state, .createdEmpty)
        XCTAssertEqual(diagnostics.controllerState, .createdEmpty)
        XCTAssertTrue(diagnostics.controllerCreated)
        XCTAssertEqual(controller.extensionContexts.count, 0)
        XCTAssertEqual(controller.extensions.count, 0)
        XCTAssertEqual(diagnostics.contextCount, 0)
        XCTAssertEqual(diagnostics.loadedExtensionCount, 0)
        XCTAssertEqual(diagnostics.attachedWebViewCount, 0)
        XCTAssertEqual(diagnostics.nativeMessagingPortCount, 0)
        XCTAssertEqual(diagnostics.configurationWebViewUserScriptCount, 0)
        XCTAssertFalse(diagnostics.configurationWebViewHasControllerAttachment)
        XCTAssertFalse(diagnostics.registersUserScriptsNow)
        XCTAssertFalse(diagnostics.launchesNativeMessagingNow)
        XCTAssertFalse(diagnostics.startsBackgroundWorkNow)
        XCTAssertFalse(diagnostics.canLoadContextNow)
        XCTAssertFalse(diagnostics.canAttachToNormalTabsNow)
        XCTAssertFalse(diagnostics.runtimeLoadable)
        XCTAssertNil(webViewConfiguration.webExtensionController)
        XCTAssertTrue(webViewConfiguration.userContentController.userScripts.isEmpty)
        XCTAssertTrue(controller.configuration.defaultWebsiteDataStore === dataStore)
        XCTAssertNil(WKWebViewConfiguration().webExtensionController)
    }

    @MainActor
    func testTeardownReleasesEmptyControllerAndReportsTornDown() throws {
        let owner = try XCTUnwrap(
            ChromeMV3EmptyControllerFactory.makeOwner(
                gateDecision: makeDecision(
                    explicitControllerCreationAllowed: true
                ),
                defaultWebsiteDataStore: .nonPersistent(),
                controllerIdentifier: UUID()
            )
        )

        XCTAssertNotNil(owner.controller)

        owner.tearDown()
        let diagnostics = owner.diagnostics()

        XCTAssertNil(owner.controller)
        XCTAssertEqual(owner.state, .tornDown)
        XCTAssertEqual(diagnostics.controllerState, .tornDown)
        XCTAssertFalse(diagnostics.controllerCreated)
        XCTAssertEqual(diagnostics.contextCount, 0)
        XCTAssertEqual(diagnostics.loadedExtensionCount, 0)
        XCTAssertEqual(diagnostics.attachedWebViewCount, 0)
        XCTAssertEqual(diagnostics.nativeMessagingPortCount, 0)
        XCTAssertFalse(diagnostics.canLoadContextNow)
        XCTAssertFalse(diagnostics.canAttachToNormalTabsNow)
        XCTAssertFalse(diagnostics.runtimeLoadable)
    }

    @MainActor
    func testSumiExtensionsModuleDoesNotCreateOwnerWhileDisabled() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = ChromeMV3EmptyControllerModuleProbe()
        let module = try makeExtensionsModule(
            registry: registry,
            probe: probe
        )

        let diagnostics = module.chromeMV3EmptyControllerDiagnosticsIfEnabled(
            explicitControllerCreationAllowed: true
        )
        let owner = module.createChromeMV3EmptyControllerOwnerIfEnabled(
            explicitControllerCreationAllowed: true
        )

        XCTAssertNil(diagnostics)
        XCTAssertNil(owner)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertEqual(probe.ownerFactoryCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    @MainActor
    func testSumiExtensionsModuleRequiresExplicitControllerGate() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.extensions)
        let probe = ChromeMV3EmptyControllerModuleProbe()
        let module = try makeExtensionsModule(
            registry: registry,
            probe: probe
        )

        let owner = module.createChromeMV3EmptyControllerOwnerIfEnabled(
            explicitControllerCreationAllowed: false
        )
        let diagnostics = try XCTUnwrap(
            module.chromeMV3EmptyControllerDiagnosticsIfEnabled(
                explicitControllerCreationAllowed: false
            )
        )

        XCTAssertNil(owner)
        XCTAssertEqual(diagnostics.controllerState, .notCreated)
        XCTAssertFalse(diagnostics.controllerCreated)
        XCTAssertFalse(diagnostics.gateDecision.canCreateControllerNow)
        XCTAssertTrue(
            diagnostics.gateDecision.blockers
                .contains(.explicitControllerCreationNotAllowed)
        )
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertEqual(probe.ownerFactoryCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    @MainActor
    func testSumiExtensionsModuleCreatesEmptyOwnerOnlyWithExplicitGate() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.extensions)
        let probe = ChromeMV3EmptyControllerModuleProbe()
        let module = try makeExtensionsModule(
            registry: registry,
            probe: probe
        )

        let owner = try XCTUnwrap(
            module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let diagnostics = try XCTUnwrap(
            module.chromeMV3EmptyControllerDiagnosticsIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )

        XCTAssertNotNil(owner.controller)
        XCTAssertEqual(owner.state, .createdEmpty)
        XCTAssertEqual(diagnostics.controllerState, .createdEmpty)
        XCTAssertTrue(diagnostics.controllerCreated)
        XCTAssertEqual(diagnostics.contextCount, 0)
        XCTAssertEqual(diagnostics.loadedExtensionCount, 0)
        XCTAssertEqual(diagnostics.attachedWebViewCount, 0)
        XCTAssertEqual(diagnostics.nativeMessagingPortCount, 0)
        XCTAssertFalse(diagnostics.canLoadContextNow)
        XCTAssertFalse(diagnostics.canAttachToNormalTabsNow)
        XCTAssertFalse(diagnostics.runtimeLoadable)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertEqual(probe.ownerFactoryCount, 1)
        XCTAssertFalse(module.hasLoadedRuntime)

        module.setEnabled(false)

        XCTAssertNil(
            module.chromeMV3EmptyControllerDiagnosticsIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testSourceGuardsForEmptyControllerOwnerBoundary() throws {
        let sourceFiles = try Self.chromeMV3SourceFiles()
        let controllerInitializerFiles = sourceFiles
            .filter { $0.contents.contains("WKWebExtension" + "Controller(") }
            .map(\.relativePath)
            .sorted()

        XCTAssertEqual(
            controllerInitializerFiles,
            [
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3EmptyControllerOwner.swift",
            ]
        )

        let extensionObjectInitializerFiles = sourceFiles
            .filter { $0.contents.contains("WKWebExtension" + "(") }
            .map(\.relativePath)
            .sorted()

        XCTAssertEqual(
            extensionObjectInitializerFiles,
            [
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionObjectProbeRunner.swift",
            ]
        )

        let assignmentFiles = sourceFiles
            .filter { Self.containsWebViewControllerAssignment($0.contents) }
            .map(\.relativePath)
            .sorted()

        XCTAssertEqual(
            assignmentFiles,
            [
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3NormalTabConfigurationAttachmentBridge.swift",
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3SyntheticConfigurationAttachmentHarness.swift",
            ]
        )

        for (forbidden, allowedFiles) in [
            ("WKWebExtension" + "Context(", []),
            ("load" + "ExtensionContext", []),
            (
                "add" + "UserScript",
                [
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3TabsScriptingJSMVP.swift",
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3StorageLocalRuntime.swift",
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerSyntheticFixture.swift",
                ]
            ),
            (
                "connect" + "Native",
                [
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeJSMessagingMVP.swift",
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerSyntheticFixture.swift",
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3NativeMessagingInternalRuntime.swift",
                ]
            ),
            ("DispatchSource" + "Ti" + "mer", []),
            ("Ti" + "mer", []),
        ] {
            let offenders = sourceFiles.filter {
                $0.contents.contains(forbidden)
                    && allowedFiles.contains($0.relativePath) == false
            }.map(\.relativePath).sorted()
            XCTAssertEqual(offenders, [], forbidden)
        }
    }

    private static func containsWebViewControllerAssignment(
        _ contents: String
    ) -> Bool {
        [
            "configuration.webExtensionController" + " =",
            "config.webExtensionController" + " =",
            "result.configuration?.webExtensionController" + " =",
        ].contains { contents.contains($0) }
    }

    private func makeDecision(
        extensionsModuleEnabled: Bool = true,
        hostEnabled: Bool = true,
        explicitControllerCreationAllowed: Bool,
        requestedContextLoading: Bool = false,
        requestedNormalTabAttachment: Bool = false,
        profileIdentifier: String = "profile-1",
        profileDataStoreIdentity: ChromeMV3ProfileDataStoreIdentity =
            .profileIdentifier("profile-1"),
        disabledRuntimeInvariantStatus: ChromeMV3DisabledRuntimeInvariantStatus =
            .satisfied
    ) -> ChromeMV3ControllerCreationGateDecision {
        let host = ChromeMV3ProfileHost(
            profileIdentifier: profileIdentifier,
            extensionsEnabled: hostEnabled,
            profileDataStoreIdentity: profileDataStoreIdentity
        )
        return host.controllerCreationGateDecision(
            extensionsModuleEnabled: extensionsModuleEnabled,
            explicitControllerCreationAllowed: explicitControllerCreationAllowed,
            requestedContextLoading: requestedContextLoading,
            requestedNormalTabAttachment: requestedNormalTabAttachment,
            disabledRuntimeInvariantStatus: disabledRuntimeInvariantStatus
        )
    }

    @MainActor
    private func makeExtensionsModule(
        registry: SumiModuleRegistry,
        probe: ChromeMV3EmptyControllerModuleProbe
    ) throws -> SumiExtensionsModule {
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let initialProfile = Profile(name: "Chrome MV3 Empty Controller Test")
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: { initialProfile },
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
    }

    private static func chromeMV3SourceFiles() throws
        -> [(relativePath: String, contents: String)]
    {
        let root = repoRoot.appendingPathComponent(
            "Sumi/Models/Extension/ChromeMV3"
        )
        return try FileManager.default
            .contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "swift" }
            .map { url in
                let relativePath =
                    "Sumi/Models/Extension/ChromeMV3/\(url.lastPathComponent)"
                return (
                    relativePath,
                    try String(contentsOf: url, encoding: .utf8)
                )
            }
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class ChromeMV3EmptyControllerModuleProbe {
    var managerCount = 0
    var ownerFactoryCount = 0
}
