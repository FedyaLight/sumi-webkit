import Foundation
import WebKit
import XCTest

@testable import Sumi

final class ChromeMV3SyntheticConfigurationAttachmentTests: XCTestCase {
    func testDisabledModuleCannotAttachSyntheticConfiguration() {
        let decision = ChromeMV3SyntheticConfigurationAttachmentGate.evaluate(
            input: gateInput(
                extensionsModuleEnabled: false,
                emptyControllerExists: true,
                explicitSyntheticConfigurationAttachmentAllowed: true
            )
        )

        XCTAssertFalse(decision.canAttachSyntheticConfigurationNow)
        XCTAssertFalse(decision.canAttachRealConfigurationNow)
        XCTAssertFalse(decision.canLoadContextNow)
        XCTAssertFalse(decision.runtimeLoadable)
        XCTAssertTrue(decision.blockers.contains(.extensionsModuleDisabled))
        XCTAssertEqual(decision.diagnostics.contextCount, 0)
        XCTAssertEqual(decision.diagnostics.loadedExtensionCount, 0)
    }

    func testNoEmptyControllerBlocksSyntheticAttachment() {
        let decision = ChromeMV3SyntheticConfigurationAttachmentGate.evaluate(
            input: gateInput(
                emptyControllerExists: false,
                explicitSyntheticConfigurationAttachmentAllowed: true
            )
        )

        XCTAssertFalse(decision.canAttachSyntheticConfigurationNow)
        XCTAssertTrue(decision.blockers.contains(.emptyControllerMissing))
        XCTAssertFalse(decision.canAttachRealConfigurationNow)
        XCTAssertFalse(decision.canLoadContextNow)
    }

    func testExplicitSyntheticGateMissingBlocksAttachment() {
        let decision = ChromeMV3SyntheticConfigurationAttachmentGate.evaluate(
            input: gateInput(
                emptyControllerExists: true,
                explicitSyntheticConfigurationAttachmentAllowed: false
            )
        )

        XCTAssertFalse(decision.canAttachSyntheticConfigurationNow)
        XCTAssertTrue(
            decision.blockers
                .contains(.explicitSyntheticAttachmentNotAllowed)
        )
        XCTAssertFalse(decision.canAttachRealConfigurationNow)
        XCTAssertFalse(decision.canLoadContextNow)
    }

    func testWrongSurfacesAreBlocked() {
        let cases: [(
            surface: ChromeMV3WebViewSurface,
            blocker: ChromeMV3SyntheticConfigurationAttachmentBlocker
        )] = [
            (.normalTab, .realNormalTabSurface),
            (.pinnedEssentialsLiveNormalBrowsing, .realNormalTabSurface),
            (.peekGlancePreview, .auxiliaryOrHelperSurface),
            (.miniWindow, .auxiliaryOrHelperSurface),
            (.faviconDownload, .auxiliaryOrHelperSurface),
            (.downloadHelper, .auxiliaryOrHelperSurface),
            (.helperWebView, .auxiliaryOrHelperSurface),
            (.webKitCreatedPopupOrNewWindow, .auxiliaryOrHelperSurface),
            (.extensionOwnedPopup, .extensionOwnedProductionSurface),
            (.extensionOwnedOptionsPage, .extensionOwnedProductionSurface),
        ]

        for testCase in cases {
            let decision = ChromeMV3SyntheticConfigurationAttachmentGate
                .evaluate(
                    input: gateInput(
                        emptyControllerExists: true,
                        explicitSyntheticConfigurationAttachmentAllowed: true,
                        surface: testCase.surface
                    )
                )

            XCTAssertFalse(
                decision.canAttachSyntheticConfigurationNow,
                testCase.surface.rawValue
            )
            XCTAssertTrue(
                decision.blockers
                    .contains(.surfaceIsNotSyntheticTestConfiguration),
                testCase.surface.rawValue
            )
            XCTAssertTrue(
                decision.blockers.contains(testCase.blocker),
                testCase.surface.rawValue
            )
            XCTAssertFalse(decision.canAttachRealConfigurationNow)
            XCTAssertFalse(decision.canLoadContextNow)
        }
    }

    func testRealNormalTabConfigurationFlagBlocksSyntheticAttachment() {
        let decision = ChromeMV3SyntheticConfigurationAttachmentGate.evaluate(
            input: gateInput(
                emptyControllerExists: true,
                explicitSyntheticConfigurationAttachmentAllowed: true,
                isRealNormalTabConfiguration: true
            )
        )

        XCTAssertFalse(decision.canAttachSyntheticConfigurationNow)
        XCTAssertTrue(decision.blockers.contains(.realNormalTabConfiguration))
        XCTAssertFalse(decision.canAttachRealConfigurationNow)
        XCTAssertFalse(decision.canLoadContextNow)
    }

    func testContextRequestAndRuntimeReadinessRemainBlocked() {
        let requestedLoadability = [false, true].last ?? false
        let contextRequest = ChromeMV3SyntheticConfigurationAttachmentGate
            .evaluate(
                input: gateInput(
                    emptyControllerExists: true,
                    explicitSyntheticConfigurationAttachmentAllowed: true,
                    requestedContextLoading: true
                )
            )
        let runtimeRequest = ChromeMV3SyntheticConfigurationAttachmentGate
            .evaluate(
                input: gateInput(
                    emptyControllerExists: true,
                    explicitSyntheticConfigurationAttachmentAllowed: true,
                    runtimeLoadable: requestedLoadability
                )
            )

        XCTAssertFalse(contextRequest.canAttachSyntheticConfigurationNow)
        XCTAssertTrue(
            contextRequest.blockers.contains(.contextLoadingRequested)
        )
        XCTAssertFalse(contextRequest.canLoadContextNow)
        XCTAssertFalse(contextRequest.runtimeLoadable)

        XCTAssertFalse(runtimeRequest.canAttachSyntheticConfigurationNow)
        XCTAssertTrue(
            runtimeRequest.blockers.contains(.runtimeLoadableRequested)
        )
        XCTAssertFalse(runtimeRequest.canLoadContextNow)
        XCTAssertFalse(runtimeRequest.runtimeLoadable)
    }

    @MainActor
    func testEnabledEmptyControllerAttachesToSyntheticConfigurationOnly()
        throws
    {
        let owner = try makeOwner()
        let controller = try XCTUnwrap(owner.controller)

        let result = ChromeMV3SyntheticConfigurationAttachmentHarness
            .attachSyntheticConfigurationIfAllowed(
                owner: owner,
                extensionsModuleEnabled: true,
                explicitSyntheticConfigurationAttachmentAllowed: true
            )
        let configuration = try XCTUnwrap(result.configuration)
        let diagnostics = result.diagnostics

        XCTAssertTrue(diagnostics.gateDecision.canAttachSyntheticConfigurationNow)
        XCTAssertFalse(diagnostics.gateDecision.canAttachRealConfigurationNow)
        XCTAssertFalse(diagnostics.gateDecision.canLoadContextNow)
        XCTAssertTrue(diagnostics.syntheticConfigurationCreated)
        XCTAssertTrue(diagnostics.syntheticConfigurationAttached)
        XCTAssertFalse(diagnostics.realConfigurationAttached)
        XCTAssertTrue(diagnostics.attachedControllerMatchesOwner)
        let attachedController = try XCTUnwrap(
            configuration.webExtensionController
        )
        XCTAssertEqual(
            ObjectIdentifier(attachedController),
            ObjectIdentifier(controller)
        )
        XCTAssertEqual(diagnostics.contextCount, 0)
        XCTAssertEqual(diagnostics.loadedExtensionCount, 0)
        XCTAssertEqual(diagnostics.attachedWebViewCount, 0)
        XCTAssertEqual(diagnostics.userScriptCount, 0)
        XCTAssertFalse(diagnostics.webExtensionCreated)
        XCTAssertFalse(diagnostics.webExtensionContextCreated)
        XCTAssertFalse(diagnostics.contextLoadCalled)
        XCTAssertFalse(diagnostics.generatedExtensionBundleLoaded)
        XCTAssertFalse(diagnostics.nativeMessagingLaunched)
        XCTAssertFalse(diagnostics.runtimeLoadable)
        XCTAssertFalse(diagnostics.canLoadContextNow)
        XCTAssertFalse(diagnostics.canAttachRealConfigurationNow)
    }

    @MainActor
    func testHarnessDoesNotAttachWithoutExplicitGate() throws {
        let owner = try makeOwner()
        let result = ChromeMV3SyntheticConfigurationAttachmentHarness
            .attachSyntheticConfigurationIfAllowed(
                owner: owner,
                extensionsModuleEnabled: true,
                explicitSyntheticConfigurationAttachmentAllowed: false
            )

        XCTAssertFalse(
            result.diagnostics.gateDecision.canAttachSyntheticConfigurationNow
        )
        XCTAssertFalse(result.diagnostics.syntheticConfigurationAttached)
        XCTAssertFalse(result.diagnostics.attachedControllerMatchesOwner)
        XCTAssertNil(result.configuration?.webExtensionController)
        XCTAssertEqual(result.diagnostics.contextCount, 0)
        XCTAssertFalse(result.diagnostics.canLoadContextNow)
        XCTAssertFalse(result.diagnostics.canAttachRealConfigurationNow)
    }

    @MainActor
    func testHarnessDoesNotAttachWithoutOwnerController() {
        let result = ChromeMV3SyntheticConfigurationAttachmentHarness
            .attachSyntheticConfigurationIfAllowed(
                owner: nil,
                extensionsModuleEnabled: true,
                explicitSyntheticConfigurationAttachmentAllowed: true
            )

        XCTAssertFalse(
            result.diagnostics.gateDecision.canAttachSyntheticConfigurationNow
        )
        XCTAssertTrue(
            result.diagnostics.gateDecision.blockers
                .contains(.emptyControllerMissing)
        )
        XCTAssertFalse(result.diagnostics.syntheticConfigurationAttached)
        XCTAssertNil(result.configuration?.webExtensionController)
        XCTAssertEqual(result.diagnostics.contextCount, 0)
    }

    @MainActor
    func testDetachClearsSyntheticConfigurationAndCanTearDownOwner()
        throws
    {
        let owner = try makeOwner()
        let result = ChromeMV3SyntheticConfigurationAttachmentHarness
            .attachSyntheticConfigurationIfAllowed(
                owner: owner,
                extensionsModuleEnabled: true,
                explicitSyntheticConfigurationAttachmentAllowed: true
            )

        XCTAssertNotNil(result.configuration?.webExtensionController)

        let detach = ChromeMV3SyntheticConfigurationAttachmentHarness
            .detachSyntheticConfiguration(
                result,
                owner: owner,
                tearDownOwner: true,
                trigger: .explicitReset
            )

        XCTAssertTrue(detach.hadSyntheticConfigurationAttachment)
        XCTAssertFalse(detach.syntheticConfigurationAttachedAfterDetach)
        XCTAssertNil(result.configuration?.webExtensionController)
        XCTAssertFalse(detach.realConfigurationAttached)
        XCTAssertTrue(detach.ownerTornDown)
        XCTAssertFalse(detach.ownerControllerExistsAfterTeardown)
        XCTAssertNil(owner.controller)
        XCTAssertEqual(detach.contextCount, 0)
        XCTAssertEqual(detach.loadedExtensionCount, 0)
        XCTAssertEqual(detach.attachedWebViewCount, 0)
        XCTAssertEqual(detach.pendingContextLoads, 0)
        XCTAssertEqual(detach.pendingAttachments, 0)
        XCTAssertFalse(detach.generatedArtifactsDeleted)
        XCTAssertFalse(detach.websiteDataCleared)
        XCTAssertFalse(detach.nativeMessagingPortsCancelled)
        XCTAssertFalse(detach.runtimeLoadable)
        XCTAssertFalse(detach.canLoadContextNow)
        XCTAssertFalse(detach.canAttachRealConfigurationNow)
    }

    @MainActor
    func testRealBrowserConfigNormalAndAuxiliaryConfigurationsRemainUnattached() {
        let profile = Profile(name: "Chrome MV3 Synthetic Guard")
        let browserConfiguration = BrowserConfiguration()
        let normalConfiguration =
            browserConfiguration.normalTabWebViewConfiguration(
                for: profile,
                url: URL(string: "https://example.com")
            )
        let normalDiagnostic =
            ChromeMV3WebViewConfigurationAttachmentGuard.inspect(
                configuration: normalConfiguration,
                siteID: "synthetic.normal",
                surface: .normalTab
            )

        XCTAssertTrue(normalDiagnostic.isNormalTabConfiguration)
        XCTAssertFalse(normalDiagnostic.hasControllerAttachment)
        XCTAssertFalse(normalDiagnostic.attachmentAllowedNow)
        XCTAssertNil(normalConfiguration.webExtensionController)

        let auxiliaryCases: [(
            BrowserConfigurationAuxiliarySurface,
            ChromeMV3WebViewSurface
        )] = [
            (.faviconDownload, .faviconDownload),
            (.glance, .peekGlancePreview),
            (.miniWindow, .miniWindow),
            (.extensionOptions, .extensionOwnedOptionsPage),
        ]

        for (surface, chromeSurface) in auxiliaryCases {
            let configuration =
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: surface
                )
            let diagnostic =
                ChromeMV3WebViewConfigurationAttachmentGuard.inspect(
                    configuration: configuration,
                    siteID: "synthetic.auxiliary.\(surface.rawValue)",
                    surface: chromeSurface
                )

            XCTAssertFalse(
                diagnostic.isNormalTabConfiguration,
                surface.rawValue
            )
            XCTAssertFalse(diagnostic.hasControllerAttachment, surface.rawValue)
            XCTAssertFalse(diagnostic.attachmentAllowedNow, surface.rawValue)
            XCTAssertNil(configuration.webExtensionController, surface.rawValue)
        }
    }

    func testSurfaceInventoryKeepsProductionPathsUnattached() {
        let diagnostics = ChromeMV3WebViewSurfaceInventory.diagnostics(
            extensionModuleEnabled: true,
            profileHostActive: true
        )

        XCTAssertFalse(diagnostics.isEmpty)
        XCTAssertFalse(
            diagnostics.contains {
                $0.surface == .syntheticTestConfiguration
            }
        )

        for diagnostic in diagnostics {
            XCTAssertFalse(
                diagnostic.controllerAttachmentAllowedNow,
                diagnostic.siteID
            )
            XCTAssertFalse(
                diagnostic.currentEligibility.canAttachControllerNow,
                diagnostic.siteID
            )
        }

        XCTAssertTrue(
            diagnostics.contains {
                $0.siteID == "extension.options.window"
                    && $0.currentEligibility.status ==
                        .futureEligibleThroughExtensionUIHostOnly
            }
        )
        XCTAssertTrue(
            diagnostics.contains {
                $0.siteID == "extension.action.popup"
                    && $0.currentEligibility.status ==
                        .futureEligibleThroughExtensionUIHostOnly
            }
        )
    }

    func testSourceGuardForSyntheticAttachmentBoundary() throws {
        let sourceFiles = try Self.chromeMV3SourceFiles()
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

        let initializerFiles = sourceFiles
            .filter { $0.contents.contains("WKWebExtension" + "Controller(") }
            .map(\.relativePath)
            .sorted()

        XCTAssertEqual(
            initializerFiles,
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

        let syntheticBridgeScopedFiles: Set<String> = [
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeJSMessagingMVP.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3TabsScriptingJSMVP.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3StorageLocalRuntime.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerSyntheticFixture.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3NativeMessagingInternalRuntime.swift",
        ]
        let source = sourceFiles
            .filter { syntheticBridgeScopedFiles.contains($0.relativePath) == false }
            .map(\.contents)
            .joined(separator: "\n")
        for forbidden in [
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

    private static func containsWebViewControllerAssignment(
        _ contents: String
    ) -> Bool {
        [
            "configuration.webExtensionController" + " =",
            "config.webExtensionController" + " =",
            "result.configuration?.webExtensionController" + " =",
        ].contains { contents.contains($0) }
    }

    private func gateInput(
        extensionsModuleEnabled: Bool = true,
        emptyControllerExists: Bool,
        explicitSyntheticConfigurationAttachmentAllowed: Bool,
        surface: ChromeMV3WebViewSurface = .syntheticTestConfiguration,
        isRealNormalTabConfiguration: Bool = false,
        requestedContextLoading: Bool = false,
        runtimeLoadable: Bool = false,
        contextCount: Int = 0,
        loadedExtensionCount: Int = 0
    ) -> ChromeMV3SyntheticConfigurationAttachmentGateInput {
        ChromeMV3SyntheticConfigurationAttachmentGateInput(
            extensionsModuleEnabled: extensionsModuleEnabled,
            emptyControllerExists: emptyControllerExists,
            explicitSyntheticConfigurationAttachmentAllowed:
                explicitSyntheticConfigurationAttachmentAllowed,
            surface: surface,
            isRealNormalTabConfiguration: isRealNormalTabConfiguration,
            requestedContextLoading: requestedContextLoading,
            runtimeLoadable: runtimeLoadable,
            contextCount: contextCount,
            loadedExtensionCount: loadedExtensionCount
        )
    }

    @MainActor
    private func makeOwner() throws -> ChromeMV3EmptyControllerOwner {
        try XCTUnwrap(
            ChromeMV3EmptyControllerFactory.makeOwner(
                gateDecision: makeDecision(
                    explicitControllerCreationAllowed: true
                ),
                defaultWebsiteDataStore: .nonPersistent(),
                controllerIdentifier: UUID()
            )
        )
    }

    private func makeDecision(
        explicitControllerCreationAllowed: Bool
    ) -> ChromeMV3ControllerCreationGateDecision {
        let host = ChromeMV3ProfileHost(
            profileIdentifier: "profile-1",
            extensionsEnabled: true,
            profileDataStoreIdentity: .ephemeralProfileIdentifier("profile-1")
        )
        return host.controllerCreationGateDecision(
            extensionsModuleEnabled: true,
            explicitControllerCreationAllowed:
                explicitControllerCreationAllowed
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
