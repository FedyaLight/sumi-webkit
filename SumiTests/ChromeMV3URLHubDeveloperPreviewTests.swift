import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3URLHubDeveloperPreviewTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_720_100_000)
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    @MainActor
    func testURLHubSectionIsAbsentWhenExtensionsModuleDisabled()
        throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "urlhub-disabled",
            manifest: bitwardenManualSmokeManifest(name: "urlhub-disabled"),
            files: bitwardenManualSmokeFiles()
        )
        let module = try makeModule(enabled: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-urlhub-disabled",
            enableInternal: true
        )
        XCTAssertTrue(install.succeeded)
        module.setEnabled(false)

        let section = module.chromeMV3URLHubSectionViewModelIfEnabled(
            rootURL: root,
            currentPage: syntheticPageContext(
                profileID: "profile-urlhub-disabled"
            ),
            now: fixedDate
        )

        XCTAssertNil(section)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(".diagnostics").path
            )
        )
    }

    @MainActor
    func testURLHubPassiveReadoutShowsBitwardenDiagnosticRow()
        throws
    {
        let fixture = try installBitwardenURLHubFixture(
            named: "urlhub-readout",
            profileID: "profile-urlhub-readout",
            enableInternal: true
        )
        let artifactURL =
            ChromeMV3ExtensionManagerManualSmokeArtifactWriter.reportURL(
                rootURL: fixture.root,
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID
            )

        let section = try XCTUnwrap(
            fixture.module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: fixture.root,
                currentPage: syntheticPageContext(
                    profileID: fixture.record.profileID
                ),
                now: fixedDate
            )
        )
        let row = try XCTUnwrap(section.rows.first)

        XCTAssertEqual(section.rows.count, 1)
        XCTAssertEqual(row.extensionID, fixture.record.extensionID)
        XCTAssertEqual(row.profileID, fixture.record.profileID)
        XCTAssertEqual(row.displayName, fixture.record.displayName)
        XCTAssertEqual(row.sourceType, .localUnpacked)
        XCTAssertEqual(row.installIntakeStatus, .enabledInternal)
        XCTAssertTrue(row.installed)
        XCTAssertTrue(row.generatedBundleAvailable)
        XCTAssertNotNil(row.generatedBundleRecordID)
        XCTAssertNotNil(row.generatedBundleHash)
        XCTAssertNotNil(row.manifestHash)
        XCTAssertNotNil(row.originalBundleContentHash)
        XCTAssertFalse(row.productSupportClaim)
        XCTAssertEqual(row.developerPreviewLabel, "Local experimental developer preview")
        XCTAssertTrue(row.notProductSupportLabel.contains("not product support"))
        XCTAssertTrue(row.enabled)
        XCTAssertTrue(row.readiness.localExperimentalGateOpen)
        XCTAssertTrue(row.readiness.currentPageIsSyntheticDiagnosticPage)
        XCTAssertTrue(row.readiness.explicitDiagnosticActionCanRun)
        XCTAssertTrue(row.readiness.productRuntimeStayedOff)
        XCTAssertFalse(row.readiness.productDefaultRuntimeAvailable)
        XCTAssertEqual(row.readiness.blockers, [])
        XCTAssertTrue(row.diagnosticAction.available)
        XCTAssertNil(row.diagnosticAction.lastArtifactPath)
        XCTAssertNil(row.diagnosticAction.lastRunStatus)
        XCTAssertFalse(section.lifetime.artifactWrittenByReadout)
        XCTAssertEqual(section.lifetime.runtimeObjectsCreated, [])
        XCTAssertFalse(section.lifetime.serviceWorkerWakeAttempted)
        XCTAssertFalse(section.lifetime.nativeHostLaunchAttempted)
        XCTAssertFalse(section.lifetime.timersOrPollingStarted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactURL.path))
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    @MainActor
    func testURLHubShowsGenericInstalledExtensionStateWithoutFixtureCapability()
        throws
    {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "urlhub-generic-installed",
            manifest: genericMV3Manifest(name: "Generic Local MV3"),
            files: [:]
        )
        let module = try makeModule(enabled: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-urlhub-generic",
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)

        let installedState = try XCTUnwrap(
            ChromeMV3ExtensionLifecycleRegistry(rootURL: root)
                .installedExtensionState(
                    profileID: record.profileID,
                    extensionID: record.extensionID
                )
        )
        XCTAssertEqual(installedState.sourceType, .localUnpacked)
        XCTAssertEqual(installedState.stableLocalExtensionID, record.extensionID)
        XCTAssertEqual(installedState.displayName, "Generic Local MV3")
        XCTAssertTrue(installedState.installed)
        XCTAssertTrue(installedState.enabled)
        XCTAssertTrue(installedState.generatedBundleState.generatedBundleAvailable)
        XCTAssertNotNil(installedState.generatedBundleHash)
        XCTAssertNotNil(installedState.manifestHash)
        XCTAssertNotNil(installedState.originalBundleContentHash)
        XCTAssertFalse(installedState.productSupportClaim)

        let section = try XCTUnwrap(
            module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: root,
                currentPage: syntheticPageContext(profileID: record.profileID),
                now: fixedDate
            )
        )
        let row = try XCTUnwrap(section.rows.first)

        XCTAssertEqual(section.rows.count, 1)
        XCTAssertEqual(row.extensionID, record.extensionID)
        XCTAssertEqual(row.displayName, "Generic Local MV3")
        XCTAssertEqual(row.sourceType, .localUnpacked)
        XCTAssertEqual(row.installIntakeStatus, .enabledInternal)
        XCTAssertTrue(row.installed)
        XCTAssertTrue(row.enabled)
        XCTAssertTrue(row.generatedBundleAvailable)
        XCTAssertFalse(row.productSupportClaim)
        XCTAssertEqual(
            row.diagnosticAction.capabilityID,
            .reviewedGeneratedResourceNormalTabSmoke
        )
        XCTAssertFalse(row.diagnosticAction.capabilityAvailable)
        XCTAssertFalse(row.diagnosticAction.available)
        XCTAssertTrue(
            row.diagnosticAction.unavailableDiagnostics.contains {
                $0.code == .manualSmokeReviewedFileMissing
            }
        )
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    @MainActor
    func testURLHubReflectsGenericEnableDisableState() throws {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: "urlhub-generic-disabled",
            manifest: genericMV3Manifest(name: "Generic Disabled MV3"),
            files: [:]
        )
        let module = try makeModule(enabled: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-urlhub-generic-disabled",
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)

        let disabled = module
            .chromeMV3SetInternalExtensionEnabledThroughManager(
                false,
                rootURL: root,
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        XCTAssertTrue(disabled.succeeded)

        let section = try XCTUnwrap(
            module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: root,
                currentPage: syntheticPageContext(profileID: record.profileID),
                now: fixedDate
            )
        )
        let row = try XCTUnwrap(section.rows.first)

        XCTAssertEqual(row.installIntakeStatus, .disabledInternal)
        XCTAssertFalse(row.enabled)
        XCTAssertTrue(row.installed)
        XCTAssertTrue(row.generatedBundleAvailable)
        XCTAssertTrue(row.readiness.blockedByExtension)
        XCTAssertFalse(row.readiness.explicitDiagnosticActionCanRun)
        XCTAssertFalse(row.diagnosticAction.available)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    @MainActor
    func testURLHubReadinessBlocksNonSyntheticCurrentPage()
        throws
    {
        let fixture = try installBitwardenURLHubFixture(
            named: "urlhub-real-page-blocked",
            profileID: "profile-urlhub-real-page",
            enableInternal: true
        )

        let section = try XCTUnwrap(
            fixture.module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: fixture.root,
                currentPage: currentPageContext(
                    profileID: fixture.record.profileID,
                    urlString: "https://example.com/login",
                    surface: .normalTab
                ),
                now: fixedDate
            )
        )
        let row = try XCTUnwrap(section.rows.first)

        XCTAssertFalse(row.readiness.currentPageIsSyntheticDiagnosticPage)
        XCTAssertTrue(
            row.readiness.blockers.contains(.blockedByNonSyntheticOrigin)
        )
        XCTAssertTrue(row.readiness.blockedByNonSyntheticOrigin)
        XCTAssertFalse(row.readiness.explicitDiagnosticActionCanRun)
        XCTAssertFalse(row.diagnosticAction.available)
        XCTAssertTrue(
            row.diagnosticAction.disabledReason?
                .contains("blockedByNonSyntheticOrigin") == true
        )
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath:
                    ChromeMV3ExtensionManagerManualSmokeArtifactWriter
                    .reportURL(
                        rootURL: fixture.root,
                        profileID: fixture.record.profileID,
                        extensionID: fixture.record.extensionID
                    )
                    .path
            )
        )
    }

    @MainActor
    func testURLHubReadinessBlocksAuxiliaryAndFileSurfaces()
        throws
    {
        let fixture = try installBitwardenURLHubFixture(
            named: "urlhub-auxiliary-blocked",
            profileID: "profile-urlhub-auxiliary",
            enableInternal: true
        )

        let section = try XCTUnwrap(
            fixture.module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: fixture.root,
                currentPage: currentPageContext(
                    profileID: fixture.record.profileID,
                    urlString: "file:///tmp/login.html",
                    surface: .peekGlancePreview
                ),
                now: fixedDate
            )
        )
        let row = try XCTUnwrap(section.rows.first)

        XCTAssertTrue(row.readiness.blockers.contains(.blockedBySurface))
        XCTAssertTrue(
            row.readiness.blockers.contains(.blockedByAuxiliarySurface)
        )
        XCTAssertTrue(row.readiness.blockers.contains(.blockedByScheme))
        XCTAssertFalse(row.diagnosticAction.available)
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    @MainActor
    func testURLHubStateMatchesManagerSourceOfTruth() throws {
        let fixture = try installBitwardenURLHubFixture(
            named: "urlhub-manager-consistency",
            profileID: "profile-urlhub-consistency",
            enableInternal: true
        )
        let detail = try XCTUnwrap(
            fixture.module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: fixture.root,
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID
            )
        )
        let section = try XCTUnwrap(
            fixture.module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: fixture.root,
                currentPage: syntheticPageContext(
                    profileID: fixture.record.profileID
                ),
                now: fixedDate
            )
        )
        let row = try XCTUnwrap(section.rows.first)

        XCTAssertEqual(row.extensionID, detail.listItem.extensionID)
        XCTAssertEqual(row.profileID, detail.listItem.profileID)
        XCTAssertEqual(row.displayName, detail.listItem.name)
        XCTAssertEqual(row.enabled, detail.listItem.internalEnabled)
        XCTAssertEqual(
            row.diagnosticAction.actionID,
            detail.manualSmokeAction.actionID
        )
        XCTAssertEqual(
            row.diagnosticAction.lastArtifactPath,
            detail.manualSmokeAction.lastArtifactPath
        )
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    @MainActor
    func testURLHubExplicitActionWritesArtifactOnlyAfterInvocation()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Named WKContentWorld execution requires macOS 15.5.")
        }
        let fixture = try installBitwardenURLHubFixture(
            named: "urlhub-action-run",
            profileID: "profile-urlhub-action",
            enableInternal: true
        )
        let context = syntheticPageContext(profileID: fixture.record.profileID)
        let artifactURL =
            ChromeMV3ExtensionManagerManualSmokeArtifactWriter.reportURL(
                rootURL: fixture.root,
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID
            )

        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactURL.path))
        let before = try XCTUnwrap(
            fixture.module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: fixture.root,
                currentPage: context,
                now: fixedDate
            )?.rows.first
        )
        XCTAssertTrue(before.diagnosticAction.available)

        let result = await fixture.module
            .chromeMV3RunURLHubDiagnosticSmokeThroughURLHub(
                rootURL: fixture.root,
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID,
                currentPage: context,
                now: { self.fixedDate }
            )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertTrue(result.manualSmokeResult?.allowed == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactURL.path))
        let after = try XCTUnwrap(
            fixture.module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: fixture.root,
                currentPage: context,
                now: fixedDate
            )?.rows.first
        )
        XCTAssertEqual(after.diagnosticAction.lastRunStatus, .succeeded)
        XCTAssertEqual(after.diagnosticAction.lastArtifactPath, artifactURL.path)
        XCTAssertEqual(after.diagnosticAction.lastRetainedObjectCount, 0)
        XCTAssertTrue(after.diagnosticAction.lastTeardownCompleted == true)
        XCTAssertTrue(after.diagnosticAction.lastDOMFillSucceeded == true)
        assertNoRuntimeSideEffects(result, module: fixture.module)
    }

    func testURLHubMV3SourceGuardsStayPassiveAndURLHubScoped()
        throws
    {
        let modelSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3URLHubDeveloperPreview.swift"
        )
        let hubSource = try source(
            "Sumi/Components/Sidebar/URLBarHubPopover.swift"
        )
        let combined = modelSource + "\n" + hubSource
        let manualSmokeRunnerCall =
            ".run" + "Manual" + "Normal" + "Tab" + "Smoke(request)"
        let artifactWriterCall =
            ".write(artifact, rootURL: rootURL)"

        XCTAssertTrue(modelSource.contains("URL-hub developer-preview"))
        XCTAssertTrue(hubSource.contains("Local MV3 Preview"))
        XCTAssertTrue(hubSource.contains("urlhub-mv3-row-"))
        XCTAssertTrue(modelSource.contains("listInstalledExtensionStates"))
        XCTAssertTrue(modelSource.contains("productSupportClaim"))
        XCTAssertTrue(modelSource.contains("not product support"))
        XCTAssertTrue(modelSource.contains("chromeMV3URLHubSectionViewModelIfEnabled"))
        XCTAssertFalse(modelSource.contains("managerIfEnabled()"))
        XCTAssertFalse(modelSource.contains("WKWebView"))
        XCTAssertFalse(modelSource.contains("WKWebExtensionController"))
        XCTAssertFalse(modelSource.contains("WKWebExtensionContext"))
        XCTAssertFalse(modelSource.contains("addUser" + "Script"))
        XCTAssertFalse(modelSource.contains("addScript" + "MessageHandler"))
        XCTAssertFalse(modelSource.contains("Process" + "("))
        XCTAssertFalse(modelSource.contains("DispatchSource" + "Timer"))
        XCTAssertFalse(modelSource.contains("Timer.publish"))
        XCTAssertFalse(modelSource.contains("ExtensionToolbar"))
        XCTAssertFalse(modelSource.contains("toolbar action"))
        XCTAssertFalse(hubSource.contains(manualSmokeRunnerCall))
        XCTAssertFalse(hubSource.contains(artifactWriterCall))
        XCTAssertFalse(modelSource.contains(manualSmokeRunnerCall))
        XCTAssertFalse(modelSource.contains(artifactWriterCall))
        XCTAssertFalse(combined.contains("masterPassword"))
        XCTAssertFalse(combined.contains("accessToken"))
        XCTAssertFalse(combined.contains("connectNative"))
        XCTAssertFalse(combined.contains("sendNativeMessage"))
    }

    @MainActor
    private func installBitwardenURLHubFixture(
        named name: String,
        profileID: String,
        enableInternal: Bool
    ) throws -> InstalledURLHubFixture {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: name,
            manifest: bitwardenManualSmokeManifest(name: name),
            files: bitwardenManualSmokeFiles()
        )
        let module = try makeModule(enabled: true)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: profileID,
            enableInternal: enableInternal
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        return InstalledURLHubFixture(
            root: root,
            module: module,
            record: record
        )
    }

    @MainActor
    private func makeModule(enabled: Bool) throws -> SumiExtensionsModule {
        let harness = TestDefaultsHarness()
        let registry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.setEnabled(enabled, for: .extensions)
        return SumiExtensionsModule(moduleRegistry: registry)
    }

    private func syntheticPageContext(
        profileID: String
    ) -> ChromeMV3URLHubCurrentPageContext {
        currentPageContext(
            profileID: profileID,
            urlString:
                ChromeMV3URLHubDeveloperPreviewModelBuilder
                .syntheticDiagnosticURLString,
            surface: .normalTab
        )
    }

    private func currentPageContext(
        profileID: String,
        urlString: String,
        surface: ChromeMV3WebViewSurface
    ) -> ChromeMV3URLHubCurrentPageContext {
        ChromeMV3URLHubCurrentPageContext(
            profileID: profileID,
            tabID: "urlhub-test-tab",
            permissionBrokerTabID: 42,
            documentID: "urlhub-test-document",
            urlString: urlString,
            tabSurface: surface
        )
    }

    private func bitwardenManualSmokeManifest(name: String) -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Manager \(name)",
            "version": "1.0.0",
            "permissions": ["scripting", "activeTab"],
            "background": [
                "service_worker": "background.js",
            ],
            "content_scripts": [
                [
                    "matches": ["https://sumi.local.test/*"],
                    "js": [
                        "content/trigger-autofill-script-injection.js",
                        "content/trigger-autofill-script-injection.js",
                    ],
                ],
            ],
        ]
    }

    private func genericMV3Manifest(name: String) -> [String: Any] {
        [
            "manifest_version": 3,
            "name": name,
            "version": "1.0.0",
            "action": [
                "default_title": name,
            ],
        ]
    }

    private func bitwardenManualSmokeFiles() -> [String: String] {
        [
            "background.js": """
            function triggerAutofillScriptInjection(tabId) {
              return chrome.scripting.executeScript({
                target: { tabId, frameIds: [0] },
                files: ["content/bootstrap-autofill.js"],
                world: "ISOLATED",
                injectImmediately: true
              });
            }
            """,
            "content/trigger-autofill-script-injection.js": """
            chrome.runtime.sendMessage({ command: "triggerAutofillScriptInjection" });
            """,
            "content/bootstrap-autofill.js": bitwardenReviewedBootstrapScript(),
        ]
    }

    private func bitwardenReviewedBootstrapScript() -> String {
        """
        (() => {
          let listener;
          listener = (message, sender, sendResponse) => {
            if (message.command === "collectPageDetailsImmediately") {
              document.getElementById("sumi-login-email").opid = "__0";
              document.getElementById("sumi-login-password").opid = "__1";
              sendResponse({ fields: ["__0", "__1"] });
              return true;
            }
            if (message.command === "fillForm") {
              for (const [action, opid, value] of message.fillScript.script) {
                if (action !== "fill_by_opid") continue;
                const field = Array.from(document.querySelectorAll("input"))
                  .find((item) => item.opid === opid);
                if (field) field.value = value;
              }
              sendResponse(null);
              return true;
            }
            return null;
          };
          chrome.runtime.onMessage.addListener(listener);
          chrome.runtime.connect({ name: "autofill-injected-script-port" });
          window.bitwardenAutofillInit = {
            destroy() { chrome.runtime.onMessage.removeListener(listener); }
          };
        })();
        """
    }

    private func makeFixture(
        named name: String,
        manifest: [String: Any],
        files: [String: String]
    ) throws -> URL {
        let directory = try makeTemporaryDirectory()
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        for (relativePath, contents) in files {
            let fileURL = directory.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return directory
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }

    @MainActor
    private func assertNoRuntimeSideEffects(
        _ result: ChromeMV3ExtensionManagerActionResult,
        module: SumiExtensionsModule,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(result.runtimeAttachmentAttempted, file: file, line: line)
        XCTAssertFalse(result.runtimeObjectsCreated, file: file, line: line)
        XCTAssertFalse(result.serviceWorkerWakeAttempted, file: file, line: line)
        XCTAssertFalse(result.nativeHostLaunchAttempted, file: file, line: line)
        XCTAssertFalse(module.hasLoadedRuntime, file: file, line: line)
        XCTAssertFalse(result.productFlags.runtimeLoadable, file: file, line: line)
        XCTAssertFalse(
            result.productFlags.productRuntimeAvailable,
            file: file,
            line: line
        )
        XCTAssertFalse(
            result.productFlags.normalTabRuntimeBridgeAvailable,
            file: file,
            line: line
        )
        XCTAssertFalse(
            result.productFlags.productNetworkEnforcementAvailable,
            file: file,
            line: line
        )
        XCTAssertFalse(
            result.productFlags.productRuntimeExposed,
            file: file,
            line: line
        )
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: projectRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
private struct InstalledURLHubFixture {
    var root: URL
    var module: SumiExtensionsModule
    var record: ChromeMV3ExtensionLifecycleRecord
}
