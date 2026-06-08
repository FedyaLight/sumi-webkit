import Foundation
import XCTest

#if canImport(WebKit)
import WebKit
#endif

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

    func testControlledActionPopupLaunchRecordLoadsRealPackageResourcesAndUsesNarrowPolicy()
        throws
    {
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Controlled Popup Fixture",
            "version": "1.0.0",
            "action": ["default_popup": "popup/index.html"],
            "permissions": ["activeTab", "nativeMessaging"],
            "background": ["service_worker": "background.js"],
        ]
        let fixture = try installFixture(
            named: "controlled-real-popup",
            manifest: manifest,
            files: [
                "background.js": "",
                "popup/index.html": """
                    <!doctype html>
                    <html>
                    <head>
                    <meta charset="utf-8">
                    <link rel="stylesheet" href="main.css">
                    <title>Controlled Popup</title>
                    </head>
                    <body data-api="chrome.runtime.sendMessage">
                    <main data-sumi-extension-page-fixture-marker="safe">Popup</main>
                    <script src="polyfills.js"></script>
                    <script src="vendor.js"></script>
                    <script src="vendor-angular.js"></script>
                    <script src="main.js"></script>
                    </body>
                    </html>
                    """,
                "popup/main.css": "body { margin: 0; }",
                "popup/polyfills.js": "globalThis.__fixturePolyfills = true;",
                "popup/vendor.js": "globalThis.__fixtureVendor = true;",
                "popup/vendor-angular.js":
                    "globalThis.__fixtureAngular = true;",
                "popup/main.js": "chrome.runtime.getURL('popup/main.css');",
                "_locales/en/messages.json": #"{"appName":{"message":"Fixture"}}"#,
            ],
            enableInternal: true
        )
        let generatedRoot = try activeGeneratedRoot(for: fixture.record)
        let installedExtension = installedExtensionFixture(
            record: fixture.record,
            packageRoot: generatedRoot,
            manifest: manifest
        )

        let launchRecord =
            ChromeMV3ProductPopupOptionsLaunchPlanner
            .controlledActionPopupLaunchRecord(
                rootURL: fixture.root,
                profileID: fixture.record.profileID,
                installedExtension: installedExtension,
                managerGate: .evaluate(moduleEnabled: true),
                moduleEnabled: true
            )

        XCTAssertTrue(
            launchRecord.canOpen,
            popupOptionsDebugSummary(launchRecord)
        )
        XCTAssertEqual(launchRecord.resourceValidationState, .valid)
        XCTAssertEqual(launchRecord.declaredPath, "popup/index.html")
        XCTAssertEqual(
            launchRecord.generatedResourcePath,
            generatedRoot.appendingPathComponent("popup/index.html").path
        )
        XCTAssertEqual(
            launchRecord.generatedRewrittenBundlePath,
            generatedRoot.path
        )
        XCTAssertEqual(
            launchRecord.apiMethodPolicy,
            .controlledActionPopupPolicy
        )
        XCTAssertTrue(launchRecord.apiSurface.runtimeAvailable)
        XCTAssertTrue(launchRecord.apiSurface.tabsAvailable)
        XCTAssertTrue(launchRecord.apiSurface.storageLocalAvailable)
        XCTAssertTrue(launchRecord.apiSurface.storageSessionAvailable)
        XCTAssertTrue(launchRecord.apiSurface.permissionsAvailable)
        XCTAssertTrue(launchRecord.apiSurface.scriptingAvailable)
        XCTAssertFalse(launchRecord.apiSurface.nativeMessagingAvailable)
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "runtime.sendMessage"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "runtime.connect"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "tabs.sendMessage"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "storage.local.get"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "storage.local.set"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "storage.local.remove"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "storage.local.clear"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "storage.session.get"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "storage.session.set"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "storage.session.remove"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "storage.session.clear"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "storage.sync.get"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "storage.sync.set"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "storage.sync.remove"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "storage.sync.clear"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "i18n.getMessage"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "i18n.getUILanguage"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "scripting.executeScript"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "permissions.contains"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "permissions.getAll"
        ))
        XCTAssertTrue(launchRecord.apiSurface.allowedMethods.contains(
            "permissions.request"
        ))
        XCTAssertFalse(launchRecord.apiSurface.allowedMethods.contains(
            "permissions.remove"
        ))
        XCTAssertFalse(launchRecord.apiSurface.allowedMethods.contains(
            "tabs.connect"
        ))
        XCTAssertFalse(launchRecord.apiSurface.allowedMethods.contains(
            "runtime.sendNativeMessage"
        ))
        XCTAssertFalse(launchRecord.apiSurface.blockedMethods.contains {
            $0.namespace == "storage" && $0.methodName == "local.*"
        })
        XCTAssertFalse(launchRecord.apiSurface.blockedMethods.contains {
            $0.namespace == "storage" && $0.methodName == "session.*"
        })
        XCTAssertTrue(launchRecord.resourceResolution?.linkedResources
            .contains { $0.kind == .localScript } == true)
        XCTAssertTrue(launchRecord.resourceResolution?.executableLocalScriptPaths
            .contains { $0.hasSuffix("popup/main.js") } == true)

        let factory = FakePopupOptionsWebViewFactory()
        let controller = ChromeMV3ProductPopupOptionsHostController(
            factory: factory
        )
        let open = controller.open(launchRecord)
        let close = controller.close(
            profileID: launchRecord.profileID,
            extensionID: launchRecord.extensionID,
            surface: launchRecord.surface,
            reason: .userClosed
        )

        XCTAssertEqual(open.status, .succeeded)
        XCTAssertEqual(
            factory.loadedFileURLs.first?.path,
            launchRecord.generatedResourcePath
        )
        XCTAssertEqual(factory.readAccessURLs.first?.path, generatedRoot.path)
        XCTAssertEqual(
            factory.lastBridgeInstallation?.allowlist,
            .controlledActionPopupPolicy
        )
        #if DEBUG
        let hostEvents = factory.lastBridgeInstallation?
            .hostDiagnosticEvents ?? []
        let resourceEvents = hostEvents.filter {
            $0.apiName == "host.resourcePreflight"
        }
        XCTAssertEqual(resourceEvents.count, 5)
        XCTAssertTrue(resourceEvents.allSatisfy {
            $0.resultClassifier == "resource exists"
        })
        XCTAssertEqual(
            resourceEvents.filter {
                $0.diagnostics.contains("tag=script")
            }.count,
            4
        )
        XCTAssertTrue(resourceEvents.contains {
            $0.diagnostics.contains("normalizedPath=popup/main.js")
                && $0.diagnostics.contains("tag=script")
                && $0.diagnostics.contains("type=classic")
                && $0.diagnostics.contains("exists=true")
                && $0.diagnostics.contains("insideGeneratedRoot=true")
        })
        XCTAssertTrue(resourceEvents.contains {
            $0.diagnostics.contains("normalizedPath=popup/main.css")
                && $0.diagnostics.contains("tag=link")
                && $0.diagnostics.contains("type=rel=stylesheet")
                && $0.diagnostics.contains("exists=true")
                && $0.diagnostics.contains("insideGeneratedRoot=true")
        })
        XCTAssertFalse(hostEvents.contains {
            $0.diagnostics.contains { diagnostic in
                diagnostic.contains(generatedRoot.path)
            }
        })
        #endif
        XCTAssertEqual(open.nativeHostLaunchAttempted, false)
        XCTAssertEqual(close.nativeHostLaunchAttempted, false)
    }

    #if DEBUG
    func testControlledCompatibilityDefaultUsesFileBackedLoadingInLiveProductPath() {
        XCTAssertEqual(
            ChromeMV3ProductPopupOptionsLoadingMode.controlledCompatibilityDefault,
            .fileBacked
        )
    }

    func testDiagnosticCustomSchemeMapsGeneratedPopupResourcesInsideRootOnly()
        throws
    {
        let root = try makeTemporaryDirectory()
        let popupDirectory = root.appendingPathComponent(
            "popup",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: popupDirectory,
            withIntermediateDirectories: true
        )

        let html = "<!doctype html><script src=\"main.js\"></script>"
        let css = "body { margin: 0; }"
        let json = #"{"appName":{"message":"Fixture"}}"#
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg"></svg>"#
        let png = Data([0x89, 0x50, 0x4e, 0x47])
        let font = Data([0x77, 0x4f, 0x46, 0x32])
        try html.write(
            to: popupDirectory.appendingPathComponent("index.html"),
            atomically: true,
            encoding: .utf8
        )
        try "globalThis.__fixture = true;".write(
            to: popupDirectory.appendingPathComponent("main.js"),
            atomically: true,
            encoding: .utf8
        )
        try css.write(
            to: popupDirectory.appendingPathComponent("main.css"),
            atomically: true,
            encoding: .utf8
        )
        try json.write(
            to: root.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        try svg.write(
            to: popupDirectory.appendingPathComponent("icon.svg"),
            atomically: true,
            encoding: .utf8
        )
        try png.write(to: popupDirectory.appendingPathComponent("icon.png"))
        try font.write(
            to: popupDirectory.appendingPathComponent("font.woff2")
        )
        try Data([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00])
            .write(to: popupDirectory.appendingPathComponent("module.wasm"))

        let handler = ChromeMV3PopupOptionsDiagnosticURLSchemeHandler(
            rootURL: root,
            bridgeHandler: nil
        )
        let pageURL = root.appendingPathComponent("popup/index.html")
        let diagnosticURL = try XCTUnwrap(
            ChromeMV3PopupOptionsDiagnosticURLSchemeHandler.diagnosticURL(
                forFileURL: pageURL,
                rootURL: root
            )
        )

        XCTAssertEqual(diagnosticURL.scheme, "sumi-extension-page-diagnostic")
        XCTAssertEqual(diagnosticURL.host, "extension")
        XCTAssertEqual(diagnosticURL.path, "/popup/index.html")

        let suffixedPageURL = ChromeMV3ExtensionPageResourcePath
            .applyingExtensionPageURLSuffix(
                from: "popup/index.html?action#extension",
                to: pageURL
            )
        let suffixedDiagnosticURL = try XCTUnwrap(
            ChromeMV3PopupOptionsDiagnosticURLSchemeHandler.diagnosticURL(
                forFileURL: suffixedPageURL,
                rootURL: root
            )
        )
        let suffixedDiagnosticComponents = try XCTUnwrap(
            URLComponents(
                url: suffixedDiagnosticURL,
                resolvingAgainstBaseURL: false
            )
        )
        XCTAssertEqual(suffixedDiagnosticURL.path, "/popup/index.html")
        XCTAssertEqual(
            suffixedDiagnosticComponents.percentEncodedQuery,
            "action"
        )
        XCTAssertEqual(
            suffixedDiagnosticComponents.percentEncodedFragment,
            "extension"
        )

        let htmlResolution = handler.resolveForTesting(diagnosticURL)
        XCTAssertEqual(htmlResolution.status, .served)
        XCTAssertEqual(htmlResolution.relativePath, "popup/index.html")
        XCTAssertEqual(htmlResolution.mimeType, "text/html")
        XCTAssertEqual(htmlResolution.data, Data(html.utf8))
        XCTAssertEqual(htmlResolution.fileURL?.standardizedFileURL, pageURL)

        let cases: [(String, String)] = [
            ("popup/main.js", "text/javascript"),
            ("popup/main.css", "text/css"),
            ("manifest.json", "application/json"),
            ("popup/icon.png", "image/png"),
            ("popup/icon.svg", "image/svg+xml"),
            ("popup/font.woff2", "font/woff2"),
            ("popup/module.wasm", "application/wasm"),
        ]
        for (relativePath, mimeType) in cases {
            let url = try XCTUnwrap(
                ChromeMV3PopupOptionsDiagnosticURLSchemeHandler
                    .diagnosticURL(relativePath: relativePath)
            )
            let resolution = handler.resolveForTesting(url)
            XCTAssertEqual(resolution.status, .served, relativePath)
            XCTAssertEqual(resolution.relativePath, relativePath)
            XCTAssertEqual(resolution.mimeType, mimeType)
        }

        XCTAssertNil(
            ChromeMV3PopupOptionsDiagnosticURLSchemeHandler.diagnosticURL(
                relativePath: "../manifest.json"
            )
        )
        XCTAssertNil(
            ChromeMV3PopupOptionsDiagnosticURLSchemeHandler.diagnosticURL(
                forFileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("outside.html"),
                rootURL: root
            )
        )

        let missingURL = try XCTUnwrap(
            ChromeMV3PopupOptionsDiagnosticURLSchemeHandler.diagnosticURL(
                relativePath: "popup/missing.js"
            )
        )
        let missingResolution = handler.resolveForTesting(missingURL)
        XCTAssertEqual(missingResolution.status, .failed)
        XCTAssertEqual(missingResolution.errorCode, 7)

        let linkURL = popupDirectory.appendingPathComponent("link.js")
        try FileManager.default.createSymbolicLink(
            at: linkURL,
            withDestinationURL: popupDirectory.appendingPathComponent("main.js")
        )
        let symlinkURL = try XCTUnwrap(
            ChromeMV3PopupOptionsDiagnosticURLSchemeHandler.diagnosticURL(
                relativePath: "popup/link.js"
            )
        )
        let symlinkResolution = handler.resolveForTesting(symlinkURL)
        XCTAssertEqual(symlinkResolution.status, .failed)
        XCTAssertEqual(symlinkResolution.errorCode, 6)

        #if canImport(WebKit)
        XCTAssertFalse(
            WKWebView.handlesURLScheme(
                ChromeMV3PopupOptionsDiagnosticURLSchemeHandler.scheme
            )
        )
        #endif
    }

    func testDiagnosticCustomSchemeMIMETypesAreNarrowAndExplicit() {
        XCTAssertEqual(
            ChromeMV3PopupOptionsDiagnosticMIME.mimeType(for: "html"),
            "text/html"
        )
        XCTAssertEqual(
            ChromeMV3PopupOptionsDiagnosticMIME.mimeType(for: "js"),
            "text/javascript"
        )
        XCTAssertEqual(
            ChromeMV3PopupOptionsDiagnosticMIME.mimeType(for: "css"),
            "text/css"
        )
        XCTAssertEqual(
            ChromeMV3PopupOptionsDiagnosticMIME.mimeType(for: "json"),
            "application/json"
        )
        XCTAssertEqual(
            ChromeMV3PopupOptionsDiagnosticMIME.mimeType(for: "svg"),
            "image/svg+xml"
        )
        XCTAssertEqual(
            ChromeMV3PopupOptionsDiagnosticMIME.mimeType(for: "woff2"),
            "font/woff2"
        )
        XCTAssertEqual(
            ChromeMV3PopupOptionsDiagnosticMIME.mimeType(for: "wasm"),
            "application/wasm"
        )
        XCTAssertFalse(
            ChromeMV3PopupOptionsDiagnosticMIME.isText("application/wasm")
        )
    }
    #endif

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
        XCTAssertTrue(
            hostSource.contains(
                "ChromeMV3WKScriptMessageHandlerRegistration.register"
            )
        )
        XCTAssertTrue(
            hostSource.contains(
                "ChromeMV3WKScriptMessageHandlerRegistration.remove"
            )
        )
        XCTAssertFalse(
            hostSource.contains("userContentController.addScriptMessageHandler(")
        )
        XCTAssertFalse(managerSource.contains("addUser" + "Script"))
        XCTAssertFalse(
            managerSource.contains("userContentController.addScriptMessageHandler(")
        )
        XCTAssertFalse(moduleSource.contains("addUser" + "Script"))
        XCTAssertFalse(
            moduleSource.contains("userContentController.addScriptMessageHandler(")
        )
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
        XCTAssertTrue(hostSource.contains("ChromeMV3ProductPopupOptionsLoadingMode"))
        XCTAssertTrue(hostSource.contains("case diagnosticCustomScheme"))
        XCTAssertTrue(hostSource.contains("#if DEBUG"))
        XCTAssertTrue(hostSource.contains("WKURLSchemeHandler"))
        XCTAssertTrue(hostSource.contains("setURLSchemeHandler"))
        XCTAssertTrue(
            hostSource.contains(
                "sumi-extension-page-diagnostic"
            )
        )
        XCTAssertTrue(
            bridgeSource.contains(
                "sumi-extension-page-diagnostic"
            )
        )
        XCTAssertTrue(
            hostSource.contains(
                "controlledCompatibilityDefault"
            )
        )
        let traceSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3LivePopupProductPathTrace.swift"
        )
        XCTAssertTrue(traceSource.contains("#if DEBUG"))
        XCTAssertTrue(traceSource.contains("#endif"))
        XCTAssertTrue(
            hostSource.contains("refreshPopupPresentationDiagnosticsForTesting")
        )
        XCTAssertTrue(
            moduleSource.contains("scheduleChromeMV3LivePopupProductPathTraceCapture")
        )
        XCTAssertTrue(traceSource.contains("visibleTextLengthBucket"))
        XCTAssertTrue(traceSource.contains("objectIdentityHash"))
        XCTAssertTrue(traceSource.contains("ChromeMV3LivePopupStagedSnapshot"))
        XCTAssertTrue(traceSource.contains("stagedProbeScript"))
        XCTAssertTrue(
            traceSource.contains("ChromeMV3LivePopupStagedSnapshotCollector")
        )
        XCTAssertTrue(hostSource.contains("livePopupStagedSnapshots"))
        XCTAssertFalse(traceSource.contains("document.body.innerHTML"))
        XCTAssertFalse(traceSource.contains("localStorage.getItem("))
        XCTAssertTrue(hostSource.contains("enableFileBackedLocalResourceFetch"))
        XCTAssertTrue(
            hostSource.contains("shouldEnableFileBackedLocalResourceFetch")
        )
        XCTAssertTrue(
            hostSource.contains(
                "ChromeMV3PopupOptionsWebAssemblyStreamingCompatibilityShim"
            )
        )
        XCTAssertTrue(
            hostSource.contains(
                "guard shouldEnableFileBackedLocalResourceFetch"
            )
        )
        XCTAssertEqual(
            hostSource.components(
                separatedBy: "Self.enableFileBackedLocalResourceFetch("
            ).count - 1,
            2,
            "Controlled popup WKWebView inits must call the scoped helper only."
        )
        XCTAssertEqual(
            hostSource.components(
                separatedBy: #"forKey: "allowFileAccessFromFileURLs""#
            ).count - 1,
            1,
            "allowFileAccessFromFileURLs must be set only through the scoped helper."
        )
        XCTAssertFalse(
            combined.contains(#"forKey: "allowUniversalAccessFromFileURLs""#)
        )
        XCTAssertFalse(bridgeSource.contains("allowFileAccessFromFileURLs"))
        XCTAssertFalse(managerSource.contains("allowFileAccessFromFileURLs"))
        XCTAssertFalse(moduleSource.contains("allowFileAccessFromFileURLs"))
        XCTAssertFalse(
            normalTabGateSource.contains("allowFileAccessFromFileURLs")
        )
        XCTAssertFalse(
            normalTabBrowserSource.contains("allowFileAccessFromFileURLs")
        )
    }

    func testFileBackedPopupLocalResourceFetchScopePolicy() {
        XCTAssertTrue(
            ChromeMV3ProductPopupOptionsWKWebViewHandle
                .shouldEnableFileBackedLocalResourceFetch(
                    loadingMode: .fileBacked
                )
        )
        #if DEBUG
        XCTAssertFalse(
            ChromeMV3ProductPopupOptionsWKWebViewHandle
                .shouldEnableFileBackedLocalResourceFetch(
                    loadingMode: .diagnosticCustomScheme
                )
        )
        #endif
    }

    func testFileBackedWasmStreamingCompatibilityShimScopePolicy() throws {
        XCTAssertTrue(
            ChromeMV3PopupOptionsWebAssemblyStreamingCompatibilityShim
                .shouldInstall(loadingMode: .fileBacked)
        )
        #if DEBUG
        XCTAssertFalse(
            ChromeMV3PopupOptionsWebAssemblyStreamingCompatibilityShim
                .shouldInstall(loadingMode: .diagnosticCustomScheme)
        )
        #endif

        let shimSource =
            ChromeMV3PopupOptionsWebAssemblyStreamingCompatibilityShim.source()
        XCTAssertTrue(shimSource.contains("instantiateStreaming"))
        XCTAssertTrue(
            shimSource.contains(#"location.protocol || "") !== "file:""#)
        )
        XCTAssertTrue(shimSource.contains("Unexpected response MIME type"))
        XCTAssertTrue(shimSource.contains("application/wasm"))
        XCTAssertTrue(shimSource.contains("arrayBuffer"))
        XCTAssertTrue(shimSource.contains("wasm.instantiate"))
        XCTAssertFalse(shimSource.contains("allowUniversalAccessFromFileURLs"))

        let hostSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ProductPopupOptionsUI.swift"
        )
        let wasmShimSource = try source(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3PopupOptionsWebAssemblyStreamingCompatibilityShim.swift"
        )
        XCTAssertTrue(
            hostSource.contains(
                "ChromeMV3PopupOptionsWebAssemblyStreamingCompatibilityShim.installIfNeeded"
            )
        )
        XCTAssertEqual(
            hostSource.components(
                separatedBy:
                    "ChromeMV3PopupOptionsWebAssemblyStreamingCompatibilityShim.installIfNeeded"
            ).count - 1,
            2,
            "Controlled popup WKWebView inits must install the WASM shim only through the scoped helper."
        )
        XCTAssertFalse(wasmShimSource.contains("bitwarden"))
        XCTAssertFalse(wasmShimSource.contains("raindrop"))
    }

    #if canImport(WebKit)
    @MainActor
    func testFileBackedPopupLoadsLocalPackagedWasmThroughInstantiateStreaming()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip(
                "Controlled file-backed WebAssembly streaming test requires macOS 15.5."
            )
        }
        let packageRoot = try wasmStreamingFixtureRoot()
        let popupURL = packageRoot.appendingPathComponent("popup.html")
        let wasmURL = packageRoot
            .appendingPathComponent("assets/test.wasm")
        XCTAssertTrue(FileManager.default.fileExists(atPath: wasmURL.path))

        let handle = ChromeMV3ProductPopupOptionsWKWebViewHandle(
            loadFileURL: popupURL,
            readAccessURL: packageRoot,
            loadingMode: .fileBacked
        )
        defer { handle.tearDown() }

        try await handle.waitForLoadForTesting()
        let outcome = try await waitForWasmStreamingFixtureOutcome(
            handle: handle,
            timeoutSeconds: 8
        )
        XCTAssertEqual(outcome["outcome"] as? String, "ok", outcome.description)
        #if DEBUG
        let diagnostics = try await handle.callAsyncJavaScriptForTesting(
            """
            return Array.isArray(globalThis.__sumiControlledPopupWasmShimDiagnostics)
              ? globalThis.__sumiControlledPopupWasmShimDiagnostics
              : [];
            """
        )
        let entries = try XCTUnwrap(diagnostics as? [[String: String]])
        XCTAssertTrue(
            entries.contains {
                $0["category"] == "mimeMismatch"
                    && $0["scope"] == "localPackagedWasm"
            }
        )
        XCTAssertTrue(
            entries.contains {
                $0["category"] == "fallbackSucceeded"
                    && $0["scope"] == "localPackagedWasm"
            }
        )
        #endif
    }
    #endif

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

    private func installedExtensionFixture(
        record: ChromeMV3ExtensionLifecycleRecord,
        packageRoot: URL,
        manifest: [String: Any]
    ) -> InstalledExtension {
        let action = manifest["action"] as? [String: Any]
        let optionsUI = manifest["options_ui"] as? [String: Any]
        let hasBackground = manifest["background"] != nil
        let hasAction = action != nil
        let optionsPagePath = manifest["options_page"] as? String
        let optionsUIPagePath = optionsUI?["page"] as? String
        let contentScripts = manifest["content_scripts"] as? [[String: Any]]
        return InstalledExtensionRecord(
            id: record.extensionID,
            name: record.displayName,
            version: record.displayVersion,
            manifestVersion: manifest["manifest_version"] as? Int ?? 3,
            description: nil,
            isEnabled: record.runtimeState.internalRuntimeEnabled,
            installDate: record.installedAt,
            lastUpdateDate: record.updatedAt,
            packagePath: packageRoot.path,
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: hasBackground ? .serviceWorker : .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: record.originalBundleRecordID,
            manifestRootFingerprint: record.installID,
            sourceBundlePath: record.originalBundleRootPath,
            optionsPagePath: optionsPagePath ?? optionsUIPagePath,
            defaultPopupPath: action?["default_popup"] as? String,
            hasBackground: hasBackground,
            hasAction: hasAction,
            hasOptionsPage:
                optionsPagePath != nil || optionsUIPagePath != nil,
            hasContentScripts: (contentScripts ?? []).isEmpty == false,
            hasExtensionPages: hasAction
                || optionsPagePath != nil
                || optionsUIPagePath != nil,
            activationSummary:
                ExtensionActivationSummary(
                    matchPatternStrings: [],
                    broadScope: false,
                    hasContentScripts: (contentScripts ?? []).isEmpty == false,
                    hasAction: hasAction,
                    hasOptionsPage:
                        optionsPagePath != nil || optionsUIPagePath != nil,
                    hasExtensionPages: hasAction
                        || optionsPagePath != nil
                        || optionsUIPagePath != nil
                ),
            manifest: manifest
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

    private func wasmStreamingFixtureRoot() throws -> URL {
        let sourceRoot = projectRoot()
            .appendingPathComponent(
                "SumiTests/Fixtures/mv3-wasm-streaming-popup",
                isDirectory: true
            )
            .standardizedFileURL
        let manifestSource = sourceRoot
            .appendingPathComponent("wasm-streaming-fixture-manifest.json")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: manifestSource.path),
            "mv3-wasm-streaming-popup fixture is unavailable."
        )

        let packageRoot = try makeTemporaryDirectory()
        let assetsDirectory = packageRoot
            .appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(
            at: assetsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: manifestSource,
            to: packageRoot.appendingPathComponent("manifest.json")
        )
        try FileManager.default.copyItem(
            at: sourceRoot.appendingPathComponent(
                "wasm-streaming-fixture-popup.html"
            ),
            to: packageRoot.appendingPathComponent("popup.html")
        )
        try FileManager.default.copyItem(
            at: sourceRoot.appendingPathComponent(
                "wasm-streaming-fixture-popup.js"
            ),
            to: packageRoot.appendingPathComponent("popup.js")
        )
        try FileManager.default.copyItem(
            at: sourceRoot.appendingPathComponent(
                "wasm-streaming-fixture-background.js"
            ),
            to: packageRoot.appendingPathComponent("background.js")
        )
        try FileManager.default.copyItem(
            at: sourceRoot.appendingPathComponent(
                "assets/wasm-streaming-test.wasm"
            ),
            to: assetsDirectory.appendingPathComponent("test.wasm")
        )
        return packageRoot
    }

    #if canImport(WebKit)
    @MainActor
    private func waitForWasmStreamingFixtureOutcome(
        handle: ChromeMV3ProductPopupOptionsWKWebViewHandle,
        timeoutSeconds: TimeInterval
    ) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let raw = try await handle.callAsyncJavaScriptForTesting(
                """
                const node = document.getElementById("wasm-status");
                return {
                  outcome: node ? node.dataset.outcome || "pending" : "missing",
                  detail: node ? node.dataset.detail || "" : ""
                };
                """
            )
            if let object = raw as? [String: Any],
               let outcome = object["outcome"] as? String,
               outcome != "pending"
            {
                return object
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw XCTSkip("Timed out waiting for WASM streaming fixture outcome.")
    }
    #endif
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
