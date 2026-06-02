import Foundation
import XCTest

@testable import Sumi

@MainActor
final class ChromeMV3ProductPopupOptionsUITests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testDisabledModuleBlocksPopupOptionsUIWithoutWebView() throws {
        let installed = try installFixture(
            named: "disabled-module-popup",
            manifest: popupManifest(),
            files: ["popup.html": pageHTML(title: "Popup")],
            enableInternal: true
        )
        let fakeFactory = FakePopupOptionsWebViewFactory()
        let disabledModule = try makeModule(
            enabled: false,
            factory: fakeFactory
        )

        let result = disabledModule.chromeMV3OpenActionPopupThroughManager(
            rootURL: installed.root,
            profileID: installed.record.profileID,
            extensionID: installed.record.extensionID
        )

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.blockedDiagnostics.contains {
            $0.code == .moduleDisabled
        })
        XCTAssertEqual(fakeFactory.createCount, 0)
        XCTAssertEqual(
            disabledModule.chromeMV3PopupOptionsActiveSessionCountForTesting,
            0
        )
        XCTAssertFalse(disabledModule.hasLoadedRuntime)
    }

    func testManagerRenderingDoesNotCreatePopupOptionsWebView() throws {
        let fixture = try installFixture(
            named: "render-popup",
            manifest: popupManifest(),
            files: ["popup.html": pageHTML(title: "Popup")],
            enableInternal: true
        )

        _ = fixture.module.chromeMV3ExtensionManagerListViewModelIfEnabled(
            rootURL: fixture.root
        )
        let detail = try XCTUnwrap(
            fixture.module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: fixture.root,
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID
            )
        )

        XCTAssertTrue(
            detail.popupOptionsLaunchState.actionPopup.canOpen,
            popupOptionsDebugSummary(detail.popupOptionsLaunchState.actionPopup)
        )
        XCTAssertTrue(detail.actions.contains {
            $0.action == .openActionPopup && $0.available
        }, detail.actions.map {
            "\($0.action.rawValue):\($0.available)"
        }.joined(separator: ", "))
        XCTAssertTrue(detail.actions.contains {
            $0.action == .openOptions && !$0.available
        })
        XCTAssertEqual(fixture.factory.createCount, 0)
        XCTAssertEqual(
            fixture.module.chromeMV3PopupOptionsActiveSessionCountForTesting,
            0
        )
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    func testActionPopupDeclaredSafeOpensAndClosesThroughGatedHost()
        throws
    {
        let fixture = try installFixture(
            named: "safe-popup",
            manifest: popupManifest(),
            files: ["popup.html": pageHTML(title: "Popup")],
            enableInternal: true
        )

        let open = fixture.module.chromeMV3OpenActionPopupThroughManager(
            rootURL: fixture.root,
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID
        )
        let close = fixture.module.chromeMV3ClosePopupOptionsThroughManager(
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID
        )

        XCTAssertEqual(open.status, .succeeded)
        XCTAssertEqual(open.popupOptionsRunResult?.webViewCreated, true)
        XCTAssertEqual(open.popupOptionsRunResult?.popupOptionsBridgeInstalled, true)
        XCTAssertEqual(open.popupOptionsRunResult?.popupOptionsUserScriptInstalled, true)
        XCTAssertTrue(open.popupOptionsRunResult?.popupOptionsAPIAllowlist
            .contains("runtime.sendMessage") == true)
        XCTAssertTrue(fixture.factory.lastBridgeInstallation?.bridgeAvailable == true)
        XCTAssertEqual(open.popupOptionsRunResult?.normalTabAttached, false)
        XCTAssertEqual(
            open.popupOptionsRunResult?
                .contentScriptsInjectedIntoProductPages,
            false
        )
        XCTAssertEqual(open.popupOptionsRunResult?.nativeHostLaunchAttempted, false)
        XCTAssertEqual(open.popupOptionsRunResult?.serviceWorkerWakeAttempted, false)
        XCTAssertEqual(fixture.factory.createCount, 1)
        XCTAssertEqual(fixture.factory.teardownCount, 1)
        XCTAssertEqual(close.status, .succeeded)
        XCTAssertEqual(close.popupOptionsRunResult?.webViewReleased, true)
        XCTAssertTrue(close.popupOptionsRunResult?.lifecycleEvents.contains(
            .teardownComplete
        ) == true)
        XCTAssertEqual(
            fixture.module.chromeMV3PopupOptionsActiveSessionCountForTesting,
            0
        )
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    func testDisabledExtensionBlocksPopupOpenWithoutWebView() throws {
        let fixture = try installFixture(
            named: "disabled-extension-popup",
            manifest: popupManifest(),
            files: ["popup.html": pageHTML(title: "Popup")],
            enableInternal: false
        )

        let result = fixture.module.chromeMV3OpenActionPopupThroughManager(
            rootURL: fixture.root,
            profileID: fixture.record.profileID,
            extensionID: fixture.record.extensionID
        )

        XCTAssertEqual(result.status, .blocked)
        XCTAssertTrue(result.popupOptionsRunResult?.launchRecord?.blockers
            .contains(.extensionDisabled) == true)
        XCTAssertEqual(fixture.factory.createCount, 0)
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    func testMissingPopupPathIsDiagnosedFromGeneratedBundle() throws {
        let fixture = try installFixture(
            named: "missing-popup",
            manifest: popupManifest(),
            files: ["popup.html": pageHTML(title: "Popup")],
            enableInternal: true
        )
        try FileManager.default.removeItem(
            at: try activeGeneratedRoot(for: fixture.record)
                .appendingPathComponent("popup.html")
        )

        let detail = try XCTUnwrap(
            fixture.module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: fixture.root,
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID
            )
        )

        XCTAssertFalse(detail.popupOptionsLaunchState.actionPopup.canOpen)
        XCTAssertEqual(
            detail.popupOptionsLaunchState.actionPopup
                .resourceValidationState,
            .missingResource
        )
        XCTAssertTrue(detail.popupOptionsLaunchState.actionPopup.blockers
            .contains(.missingPageResource))
        XCTAssertEqual(fixture.factory.createCount, 0)
    }

    func testUnsafePopupPathIsRejectedFromGeneratedBundle() throws {
        let fixture = try installFixture(
            named: "unsafe-popup",
            manifest: popupManifest(),
            files: ["popup.html": pageHTML(title: "Popup")],
            enableInternal: true
        )
        try rewriteGeneratedManifest(
            for: fixture.record,
            mutate: { manifest in
                manifest["action"] = ["default_popup": "../popup.html"]
            }
        )

        let detail = try XCTUnwrap(
            fixture.module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: fixture.root,
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID
            )
        )

        XCTAssertFalse(detail.popupOptionsLaunchState.actionPopup.canOpen)
        XCTAssertEqual(
            detail.popupOptionsLaunchState.actionPopup
                .resourceValidationState,
            .unsafePath
        )
        XCTAssertTrue(detail.popupOptionsLaunchState.actionPopup.blockers
            .contains(.unsafePagePath))
        XCTAssertEqual(fixture.factory.createCount, 0)
    }

    func testOptionsPageAndOptionsUIBecomeLaunchableWhenSafe() throws {
        let pageFixture = try installFixture(
            named: "options-page",
            manifest: optionsPageManifest(),
            files: ["options.html": pageHTML(title: "Options")],
            enableInternal: true
        )
        let uiFixture = try installFixture(
            named: "options-ui",
            manifest: optionsUIManifest(openInTab: true),
            files: ["embedded.html": pageHTML(title: "Embedded Options")],
            enableInternal: true
        )

        let pageDetail = try XCTUnwrap(
            pageFixture.module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: pageFixture.root,
                profileID: pageFixture.record.profileID,
                extensionID: pageFixture.record.extensionID
            )
        )
        let uiDetail = try XCTUnwrap(
            uiFixture.module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: uiFixture.root,
                profileID: uiFixture.record.profileID,
                extensionID: uiFixture.record.extensionID
            )
        )

        XCTAssertTrue(pageDetail.popupOptionsLaunchState.primaryOptions?.canOpen == true)
        XCTAssertEqual(
            pageDetail.popupOptionsLaunchState.primaryOptions?.surface,
            .optionsPage
        )
        XCTAssertTrue(uiDetail.popupOptionsLaunchState.primaryOptions?.canOpen == true)
        XCTAssertEqual(
            uiDetail.popupOptionsLaunchState.primaryOptions?.surface,
            .optionsUI
        )
        XCTAssertEqual(
            uiDetail.popupOptionsLaunchState.primaryOptions?
                .optionsUIOpenInTab,
            true
        )

        let open = uiFixture.module.chromeMV3OpenOptionsThroughManager(
            rootURL: uiFixture.root,
            profileID: uiFixture.record.profileID,
            extensionID: uiFixture.record.extensionID
        )
        XCTAssertEqual(open.status, .succeeded)
        XCTAssertEqual(open.popupOptionsRunResult?.requestedSurface, .optionsUI)
        XCTAssertEqual(uiFixture.factory.createCount, 1)
    }

    func testPopupOptionsHostTearsDownOnDisableUninstallAndReset()
        throws
    {
        let disableFixture = try installFixture(
            named: "disable-open-popup",
            manifest: popupManifest(),
            files: ["popup.html": pageHTML(title: "Popup")],
            enableInternal: true
        )
        _ = disableFixture.module.chromeMV3OpenActionPopupThroughManager(
            rootURL: disableFixture.root,
            profileID: disableFixture.record.profileID,
            extensionID: disableFixture.record.extensionID
        )
        _ = disableFixture.module.chromeMV3SetInternalExtensionEnabledThroughManager(
            false,
            rootURL: disableFixture.root,
            profileID: disableFixture.record.profileID,
            extensionID: disableFixture.record.extensionID
        )
        XCTAssertEqual(disableFixture.factory.teardownCount, 1)
        XCTAssertEqual(
            disableFixture.module.chromeMV3PopupOptionsActiveSessionCountForTesting,
            0
        )

        let uninstallFixture = try installFixture(
            named: "uninstall-open-popup",
            manifest: popupManifest(),
            files: ["popup.html": pageHTML(title: "Popup")],
            enableInternal: true
        )
        _ = uninstallFixture.module.chromeMV3OpenActionPopupThroughManager(
            rootURL: uninstallFixture.root,
            profileID: uninstallFixture.record.profileID,
            extensionID: uninstallFixture.record.extensionID
        )
        _ = uninstallFixture.module.chromeMV3UninstallThroughManager(
            rootURL: uninstallFixture.root,
            profileID: uninstallFixture.record.profileID,
            extensionID: uninstallFixture.record.extensionID
        )
        XCTAssertEqual(uninstallFixture.factory.teardownCount, 1)
        XCTAssertEqual(
            uninstallFixture.module.chromeMV3PopupOptionsActiveSessionCountForTesting,
            0
        )

        let resetFixture = try installFixture(
            named: "reset-open-popup",
            manifest: popupManifest(),
            files: ["popup.html": pageHTML(title: "Popup")],
            enableInternal: true
        )
        _ = resetFixture.module.chromeMV3OpenActionPopupThroughManager(
            rootURL: resetFixture.root,
            profileID: resetFixture.record.profileID,
            extensionID: resetFixture.record.extensionID
        )
        _ = resetFixture.module.chromeMV3ResetThroughManager(
            rootURL: resetFixture.root,
            profileID: resetFixture.record.profileID,
            extensionID: resetFixture.record.extensionID
        )
        XCTAssertEqual(resetFixture.factory.teardownCount, 1)
        XCTAssertEqual(
            resetFixture.module.chromeMV3PopupOptionsActiveSessionCountForTesting,
            0
        )
    }

    func testPopupOptionsAPISurfaceIsLimitedAndNormalTabsRemainOff()
        throws
    {
        let fixture = try installFixture(
            named: "api-limited-popup",
            manifest: [
                "manifest_version": 3,
                "name": "API Limited Popup",
                "version": "1.0.0",
                "permissions": ["storage", "nativeMessaging"],
                "background": ["service_worker": "worker.js"],
                "content_scripts": [
                    [
                        "matches": ["https://example.com/*"],
                        "js": ["content.js"],
                    ],
                ],
                "action": ["default_popup": "popup.html"],
            ],
            files: [
                "popup.html": pageHTML(title: "Popup"),
                "worker.js": "",
                "content.js": "",
            ],
            enableInternal: true
        )
        let detail = try XCTUnwrap(
            fixture.module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: fixture.root,
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID
            )
        )
        let popup = detail.popupOptionsLaunchState.actionPopup

        XCTAssertTrue(popup.canOpen)
        XCTAssertFalse(popup.apiSurface.nativeMessagingAvailable)
        XCTAssertFalse(popup.apiSurface.serviceWorkerWakeAllowed)
        XCTAssertTrue(popup.apiSurface.tabsAvailable)
        XCTAssertTrue(popup.apiSurface.scriptingAvailable)
        XCTAssertTrue(popup.apiSurface.allowedMethods.contains("tabs.query"))
        XCTAssertTrue(popup.apiSurface.blockedMethods.contains {
            $0.namespace == "tabs" && $0.methodName == "sendMessage"
        })
        XCTAssertTrue(popup.apiSurface.blockedMethods.contains {
            $0.namespace == "scripting" && $0.methodName == "executeScript"
        })
        XCTAssertFalse(popup.gateRecord.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(popup.gateRecord.contentScriptAttachmentAvailable)
        XCTAssertFalse(popup.gateRecord.runtimeLoadable)
        XCTAssertFalse(detail.productEnablementPreflight.normalTabPreflight
            .canAttachToNormalTabNow)
    }

    func testToolbarPlaceholderIsDeferred() throws {
        let fixture = try installFixture(
            named: "toolbar-deferred-popup",
            manifest: popupManifest(),
            files: ["popup.html": pageHTML(title: "Popup")],
            enableInternal: true
        )
        let detail = try XCTUnwrap(
            fixture.module.chromeMV3ExtensionManagerDetailViewModelIfEnabled(
                rootURL: fixture.root,
                profileID: fixture.record.profileID,
                extensionID: fixture.record.extensionID
            )
        )

        XCTAssertTrue(detail.popupOptionsLaunchState.toolbarActionUIDeferred)
        XCTAssertTrue(detail.gate.diagnostics.contains {
            $0.code == .runtimeActionsUnavailable
        })
    }

    func testProductPopupOptionsSourceGuards() throws {
        let hostSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ProductPopupOptionsUI.swift"
        )
        let bridgeSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3PopupOptionsJSBridge.swift"
        )
        let managerSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionManagerDeveloperPreview.swift"
        )
        let moduleSource = try source(
            "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift"
        )
        let normalTabGateSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3NormalTabConfigurationAttachmentGate.swift"
        )
        let normalTabBrowserSource = try source(
            "Sumi/Managers/BrowserManager/BrowserManager.swift"
        )
        let combined =
            hostSource + "\n" + bridgeSource + "\n" + managerSource + "\n"
                + moduleSource
        let enabledWord = "tr" + "ue"

        for token in [
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer" + "(",
            "Ti" + "mer" + ".publish",
            "Ti" + "mer" + ".scheduled",
        ] {
            XCTAssertFalse(combined.contains(token), token)
        }
        XCTAssertFalse(combined.contains("Process" + "("))
        XCTAssertTrue(hostSource.contains("addUser" + "Script"))
        XCTAssertTrue(hostSource.contains("addScript" + "MessageHandler"))
        XCTAssertFalse(managerSource.contains("addUser" + "Script"))
        XCTAssertFalse(managerSource.contains("addScript" + "MessageHandler"))
        XCTAssertFalse(moduleSource.contains("addUser" + "Script"))
        XCTAssertFalse(moduleSource.contains("addScript" + "MessageHandler"))
        XCTAssertFalse(normalTabGateSource.contains("ChromeMV3PopupOptionsJSShimSource"))
        XCTAssertFalse(normalTabBrowserSource.contains("ChromeMV3PopupOptionsJSShimSource"))
        XCTAssertFalse(combined.contains("WKContent" + "RuleList"))
        XCTAssertFalse(combined.contains("chrome" + ".google"))
        XCTAssertFalse(
            combined.contains("productRuntimeAvailable: " + enabledWord)
        )
        XCTAssertFalse(
            combined.contains(
                "normalTabRuntimeBridgeAvailable: " + enabledWord
            )
        )
        XCTAssertFalse(combined.contains("runtimeLoadable: " + enabledWord))
        XCTAssertFalse(
            combined.contains("productRuntimeExposed: " + enabledWord)
        )
        XCTAssertTrue(hostSource.contains("toolbarActionUIDeferred"))
        XCTAssertTrue(hostSource.contains("actionPopupUIAvailableInDeveloperPreview"))
        XCTAssertTrue(hostSource.contains("optionsUIAvailableInDeveloperPreview"))
        XCTAssertTrue(
            bridgeSource.contains(
                "popupOptionsJSBridgeNeverInstalledInProductNormalTabWebViews"
            )
        )
        XCTAssertTrue(
            bridgeSource.contains(
                "popupOptionsJSBridgeDoesNotAttachProductContentScripts"
            )
        )
    }

    private func installFixture(
        named name: String,
        manifest: [String: Any],
        files: [String: String],
        enableInternal: Bool
    ) throws -> InstalledPopupOptionsFixture {
        let root = try makeTemporaryDirectory()
        let source = try makeFixture(
            named: name,
            manifest: manifest,
            files: files
        )
        let factory = FakePopupOptionsWebViewFactory()
        let module = try makeModule(enabled: true, factory: factory)
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: source,
            profileID: "profile-\(name)",
            enableInternal: enableInternal
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        XCTAssertTrue(install.succeeded)
        return InstalledPopupOptionsFixture(
            root: root,
            module: module,
            factory: factory,
            record: record
        )
    }

    private func makeModule(
        enabled: Bool,
        factory: FakePopupOptionsWebViewFactory
    ) throws -> SumiExtensionsModule {
        let harness = TestDefaultsHarness()
        let registry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.setEnabled(enabled, for: .extensions)
        return SumiExtensionsModule(
            moduleRegistry: registry,
            chromeMV3PopupOptionsWebViewFactory: { factory }
        )
    }

    private func popupManifest() -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Popup Fixture",
            "version": "1.0.0",
            "action": ["default_popup": "popup.html"],
        ]
    }

    private func optionsPageManifest() -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Options Page Fixture",
            "version": "1.0.0",
            "options_page": "options.html",
        ]
    }

    private func optionsUIManifest(openInTab: Bool) -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Options UI Fixture",
            "version": "1.0.0",
            "options_ui": [
                "page": "embedded.html",
                "open_in_tab": openInTab,
            ],
        ]
    }

    private func pageHTML(title: String) -> String {
        """
        <!doctype html>
        <html>
        <head><meta charset="utf-8"><title>\(title)</title></head>
        <body><main data-sumi-extension-page-fixture-marker="safe">\(title)</main></body>
        </html>
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

    private func activeGeneratedRoot(
        for record: ChromeMV3ExtensionLifecycleRecord
    ) throws -> URL {
        let activeID = try XCTUnwrap(record.activeGeneratedVersionID)
        let version = try XCTUnwrap(record.generatedBundleVersions.first {
            $0.id == activeID
        })
        return URL(
            fileURLWithPath: version.generatedBundleRootPath,
            isDirectory: true
        )
    }

    private func rewriteGeneratedManifest(
        for record: ChromeMV3ExtensionLifecycleRecord,
        mutate: (inout [String: Any]) -> Void
    ) throws {
        let manifestURL = try activeGeneratedRoot(for: record)
            .appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        mutate(&object)
        let newData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try newData.write(to: manifestURL, options: [.atomic])
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

    private func popupOptionsDebugSummary(
        _ record: ChromeMV3ProductPopupOptionsLaunchRecord
    ) -> String {
        [
            "surface=\(record.surface.rawValue)",
            "canOpen=\(record.canOpen)",
            "validation=\(record.resourceValidationState.rawValue)",
            "productGate=\(record.productGateState.rawValue)",
            "host=\(record.hostCreationState.rawValue)",
            "bridge=\(record.bridgeAPIAvailabilityState.rawValue)",
            "declared=\(record.declaredPath ?? "nil")",
            "generated=\(record.generatedRewrittenBundlePath ?? "nil")",
            "blockers=\(record.blockers.map(\.rawValue).joined(separator: ","))",
            "diagnostics=\(record.diagnostics.joined(separator: " | "))",
        ].joined(separator: " ")
    }
}

@MainActor
private final class FakePopupOptionsWebViewFactory:
    ChromeMV3PopupOptionsWebViewFactory
{
    var createCount = 0
    var teardownCount = 0
    var loadedFileURLs: [URL] = []
    var readAccessURLs: [URL] = []
    var lastBridgeInstallation:
        ChromeMV3PopupOptionsJSBridgeInstallation?
    var failCreation = false

    func createWebView(
        loadFileURL: URL,
        allowingReadAccessTo readAccessURL: URL
    ) throws -> ChromeMV3PopupOptionsWebViewHandle {
        if failCreation {
            throw NSError(
                domain: "FakePopupOptionsWebViewFactory",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Fake popup/options WebView creation failed.",
                ]
            )
        }
        createCount += 1
        loadedFileURLs.append(loadFileURL)
        readAccessURLs.append(readAccessURL)
        return FakePopupOptionsWebViewHandle { [weak self] in
            self?.teardownCount += 1
        }
    }

    func createWebView(
        loadFileURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        bridgeInstallation:
            ChromeMV3PopupOptionsJSBridgeInstallation,
        permissionPromptPresenter:
            ChromeMV3PermissionPromptPresenting?,
        permissionEventDispatcher:
            ChromeMV3PermissionEventDispatching?
    ) throws -> ChromeMV3PopupOptionsWebViewHandle {
        lastBridgeInstallation = bridgeInstallation
        _ = permissionPromptPresenter
        _ = permissionEventDispatcher
        return try createWebView(
            loadFileURL: loadFileURL,
            allowingReadAccessTo: readAccessURL
        )
    }
}

@MainActor
private final class FakePopupOptionsWebViewHandle:
    ChromeMV3PopupOptionsWebViewHandle
{
    private let onTearDown: () -> Void
    private var didTearDown = false

    init(onTearDown: @escaping () -> Void) {
        self.onTearDown = onTearDown
    }

    func tearDown() {
        guard didTearDown == false else { return }
        didTearDown = true
        onTearDown()
    }
}

@MainActor
private struct InstalledPopupOptionsFixture {
    var root: URL
    var module: SumiExtensionsModule
    var factory: FakePopupOptionsWebViewFactory
    var record: ChromeMV3ExtensionLifecycleRecord
}
