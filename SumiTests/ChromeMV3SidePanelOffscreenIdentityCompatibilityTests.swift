import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3SidePanelOffscreenIdentityCompatibilityTests:
    XCTestCase
{
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testSidePanelDefaultPathIsDetectedAndResourceSafe() throws {
        let root = try makeExtensionRoot(
            named: "side-panel-safe",
            manifest: [
                "manifest_version": 3,
                "name": "Side Panel",
                "version": "1.0",
                "permissions": ["sidePanel"],
                "side_panel": ["default_path": "sidepanel.html"],
            ],
            resources: [
                "sidepanel.html": pageHTML(title: "Side"),
            ]
        )
        let manifest = try validateManifest(root: root)
        let report = ChromeMV3SidePanelOffscreenIdentityCompatibilityReportGenerator
            .makeReport(
                manifest: manifest,
                generatedBundleRootURL: root
            )

        XCTAssertTrue(report.apiDetection.sidePanelDeclaredByManifestKey)
        XCTAssertTrue(report.apiDetection.sidePanelPermissionDeclared)
        XCTAssertEqual(
            report.sidePanelManifestResourceSummary.defaultPath,
            "sidepanel.html"
        )
        XCTAssertTrue(
            report.sidePanelManifestResourceSummary
                .syntheticHostDiagnostics.defaultPathResolved
        )
        XCTAssertTrue(
            report.sidePanelManifestResourceSummary
                .syntheticHostDiagnostics.defaultPathResourceSafe
        )
        XCTAssertFalse(report.sidePanelAvailableInProduct)
        XCTAssertFalse(report.runtimeLoadable)
    }

    func testUnsafeSidePanelPathIsRejected() throws {
        let root = try makeExtensionRoot(
            named: "side-panel-unsafe",
            manifest: [
                "manifest_version": 3,
                "name": "Unsafe Side Panel",
                "version": "1.0",
                "side_panel": ["default_path": "../sidepanel.html"],
            ],
            resources: [:]
        )
        let model = ChromeMV3ExtensionPageDeclarationReader.read(
            generatedRewrittenRootPath: root.path
        )
        let declaration = try XCTUnwrap(model.declarations.first {
            $0.kind == .sidePanel
        })
        let report = ChromeMV3SidePanelOffscreenIdentityCompatibilityReportGenerator
            .makeReport(manifest: nil, generatedBundleRootURL: root)

        XCTAssertEqual(declaration.pathSafety, .unsafe)
        XCTAssertTrue(
            report.sidePanelManifestResourceSummary.unsafePathDiagnosed
        )
        XCTAssertFalse(
            report.sidePanelManifestResourceSummary
                .syntheticHostDiagnostics.syntheticHiddenHostAllowedByPolicy
        )
    }

    func testMissingNonHTMLAndRemoteSidePanelResourcesAreDiagnosed()
        throws
    {
        let missingRoot = try makeExtensionRoot(
            named: "side-panel-missing",
            manifest: [
                "manifest_version": 3,
                "name": "Missing Side Panel",
                "version": "1.0",
                "side_panel": ["default_path": "missing.html"],
            ],
            resources: [:]
        )
        let nonHTMLRoot = try makeExtensionRoot(
            named: "side-panel-non-html",
            manifest: [
                "manifest_version": 3,
                "name": "Non HTML Side Panel",
                "version": "1.0",
                "side_panel": ["default_path": "sidepanel.txt"],
            ],
            resources: ["sidepanel.txt": "not html"]
        )
        let remoteRoot = try makeExtensionRoot(
            named: "side-panel-remote",
            manifest: [
                "manifest_version": 3,
                "name": "Remote Side Panel",
                "version": "1.0",
                "side_panel": ["default_path": "sidepanel.html"],
            ],
            resources: [
                "sidepanel.html": pageHTML(
                    title: "Remote",
                    body: #"<img src="https://example.com/logo.png" alt="">"#
                ),
            ]
        )

        let missing = ChromeMV3SidePanelOffscreenIdentityCompatibilityReportGenerator
            .makeReport(manifest: nil, generatedBundleRootURL: missingRoot)
        let nonHTML = ChromeMV3SidePanelOffscreenIdentityCompatibilityReportGenerator
            .makeReport(manifest: nil, generatedBundleRootURL: nonHTMLRoot)
        let remote = ChromeMV3SidePanelOffscreenIdentityCompatibilityReportGenerator
            .makeReport(manifest: nil, generatedBundleRootURL: remoteRoot)

        XCTAssertTrue(missing.sidePanelManifestResourceSummary.missingPageDiagnosed)
        XCTAssertTrue(nonHTML.sidePanelManifestResourceSummary.nonHTMLResourceDiagnosed)
        XCTAssertTrue(
            remote.sidePanelManifestResourceSummary
                .remoteResourceDependencyDiagnosed
        )
    }

    func testSidePanelSetOptionsGetOptionsMutateSyntheticStateAndOpenBlocks()
        throws
    {
        let root = try makeExtensionRoot(
            named: "side-panel-bridge",
            manifest: [
                "manifest_version": 3,
                "name": "Side Panel Bridge",
                "version": "1.0",
                "side_panel": ["default_path": "default.html"],
            ],
            resources: [
                "default.html": pageHTML(title: "Default"),
                "tab.html": pageHTML(title: "Tab"),
            ]
        )
        var owner = stateOwner(root: root, defaultSidePanelPath: "default.html")

        let set = owner.handle(request(
            namespace: "sidePanel",
            methodName: "setOptions",
            mode: .promise,
            arguments: [
                .object([
                    "tabId": .number(7),
                    "path": .string("tab.html"),
                    "enabled": .bool(false),
                ]),
            ]
        ))
        let get = owner.handle(request(
            namespace: "sidePanel",
            methodName: "getOptions",
            mode: .callback,
            arguments: [.object(["tabId": .number(7)])]
        ))
        let open = owner.handle(request(
            namespace: "sidePanel",
            methodName: "open",
            mode: .callback,
            arguments: [.object(["tabId": .number(7)])]
        ))

        XCTAssertTrue(set.succeeded)
        XCTAssertTrue(get.succeeded)
        XCTAssertEqual(
            get.resultPayload,
            .object([
                "enabled": .bool(false),
                "path": .string("tab.html"),
                "tabId": .number(7),
            ])
        )
        XCTAssertFalse(open.succeeded)
        XCTAssertEqual(open.lastErrorCode, "productUIUnavailable")
        XCTAssertTrue(open.callbackWouldSetLastError)
        XCTAssertFalse(open.sidePanelAvailableInProduct)
    }

    func testOffscreenCreateHasAndCloseModelOnlyDocument() throws {
        let root = try makeExtensionRoot(
            named: "offscreen-model",
            manifest: [
                "manifest_version": 3,
                "name": "Offscreen",
                "version": "1.0",
                "permissions": ["offscreen"],
            ],
            resources: ["offscreen.html": pageHTML(title: "Offscreen")]
        )
        var owner = stateOwner(root: root)
        let create = owner.handle(offscreenCreateRequest(
            url: "offscreen.html",
            reasons: ["TESTING"],
            justification: "fixture validation"
        ))
        let has = owner.handle(request(
            namespace: "offscreen",
            methodName: "hasDocument"
        ))
        let close = owner.handle(request(
            namespace: "offscreen",
            methodName: "closeDocument"
        ))
        let hasAfterClose = owner.handle(request(
            namespace: "offscreen",
            methodName: "hasDocument"
        ))

        XCTAssertTrue(create.succeeded)
        XCTAssertTrue(has.succeeded)
        XCTAssertEqual(has.resultPayload, .bool(true))
        XCTAssertTrue(close.succeeded)
        XCTAssertEqual(hasAfterClose.resultPayload, .bool(false))
        XCTAssertEqual(
            owner.offscreenLifecycleSummary.productHiddenWebViewRuntimeCreated,
            false
        )
        XCTAssertEqual(owner.offscreenLifecycleSummary.serviceWorkerWakeCount, 0)
        XCTAssertFalse(owner.offscreenLifecycleSummary.recurringWorkCreated)
    }

    func testOffscreenUnsupportedAndProductBlockedReasonsAreDiagnosed()
        throws
    {
        let root = try makeExtensionRoot(
            named: "offscreen-blocked",
            manifest: [
                "manifest_version": 3,
                "name": "Offscreen Blocked",
                "version": "1.0",
                "permissions": ["offscreen"],
            ],
            resources: ["offscreen.html": pageHTML(title: "Offscreen")]
        )
        var owner = stateOwner(root: root)
        let unsupported = owner.handle(offscreenCreateRequest(
            url: "offscreen.html",
            reasons: ["NOT_A_REASON"],
            justification: "fixture validation"
        ))
        let productBlocked = owner.handle(offscreenCreateRequest(
            url: "offscreen.html",
            reasons: ["USER_MEDIA"],
            justification: "fixture validation"
        ))

        XCTAssertFalse(unsupported.succeeded)
        XCTAssertEqual(unsupported.lastErrorCode, "invalidArguments")
        XCTAssertTrue(
            unsupported.diagnostics.contains {
                $0.contains("Unsupported offscreen reason")
            }
        )
        XCTAssertFalse(productBlocked.succeeded)
        XCTAssertEqual(
            productBlocked.lastErrorCode,
            "offscreenProductRuntimeBlocked"
        )
        XCTAssertFalse(productBlocked.offscreenAvailableInProduct)
    }

    func testIdentityRedirectAuthFlowTokenAndSyntheticCacheBehavior() throws {
        var blocked = stateOwner(
            syntheticIdentityFixture: .none
        )
        let redirect = blocked.handle(request(
            namespace: "identity",
            methodName: "getRedirectURL",
            arguments: [.string("callback")]
        ))
        let blockedAuth = blocked.handle(request(
            namespace: "identity",
            methodName: "launchWebAuthFlow",
            arguments: [
                .object([
                    "url": .string("https://provider.example/auth"),
                    "interactive": .bool(true),
                ]),
            ]
        ))
        let blockedToken = blocked.handle(request(
            namespace: "identity",
            methodName: "getAuthToken",
            arguments: [.object(["interactive": .bool(false)])]
        ))

        XCTAssertEqual(
            redirect.resultPayload,
            .string(
                "https://sidepanel-offscreen-identity-extension.chromiumapp.org/callback"
            )
        )
        XCTAssertFalse(blockedAuth.succeeded)
        XCTAssertEqual(blockedAuth.lastErrorCode, "syntheticFixtureUnavailable")
        XCTAssertFalse(blockedAuth.identityExternalAuthNetworkAllowed)
        XCTAssertFalse(blockedToken.succeeded)

        var fixture = stateOwner(
            syntheticIdentityFixture: .testOnly(
                authFlowRedirectURL:
                    "https://sidepanel-offscreen-identity-extension.chromiumapp.org/callback#ok",
                authToken: "synthetic-token",
                grantedScopes: ["email"]
            )
        )
        let auth = fixture.handle(request(
            namespace: "identity",
            methodName: "launchWebAuthFlow",
            arguments: [
                .object([
                    "url": .string("https://provider.example/auth"),
                    "interactive": .bool(true),
                ]),
            ]
        ))
        let token = fixture.handle(request(
            namespace: "identity",
            methodName: "getAuthToken",
            arguments: [.object(["scopes": .array([.string("email")])])]
        ))
        let remove = fixture.handle(request(
            namespace: "identity",
            methodName: "removeCachedAuthToken",
            arguments: [.object(["token": .string("synthetic-token")])]
        ))
        let afterRemove = fixture.handle(request(
            namespace: "identity",
            methodName: "getAuthToken"
        ))

        XCTAssertTrue(auth.succeeded)
        XCTAssertTrue(token.succeeded)
        XCTAssertEqual(
            token.resultPayload,
            .object([
                "grantedScopes": .array([.string("email")]),
                "token": .string("synthetic-token"),
            ])
        )
        XCTAssertTrue(remove.succeeded)
        XCTAssertFalse(afterRemove.succeeded)
        XCTAssertEqual(afterRemove.lastErrorCode, "syntheticFixtureUnavailable")
    }

    func testGenericJSBridgeRoutesCompatibilityNamespaces() {
        var environment =
            ChromeMV3JSBridgeContractEnvironment
            .passwordManagerModelFixture(
                extensionID: "bridge-extension",
                profileID: "bridge-profile"
            )
        let response = ChromeMV3JSBridgeContractRouter.route(
            ChromeMV3JSBridgeRequestEnvelope(
                extensionID: "bridge-extension",
                profileID: "bridge-profile",
                sourceContext: .testFixture,
                namespace: .identity,
                methodName: "getRedirectURL",
                rawArguments: [.string("done")],
                invocationMode: .promise
            ),
            environment: &environment
        )

        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(
            response.routeResult?.sidePanelOffscreenIdentityResponse?
                .namespace,
            "identity"
        )
        XCTAssertFalse(response.runtimeExposureNow)
        XCTAssertFalse(response.jsBridgeAvailableNow)
    }

    func testCompatibilityReportWriterIsDeterministicAndProductFlagsStayFalse()
        throws
    {
        let root = try makeExtensionRoot(
            named: "report",
            manifest: [
                "manifest_version": 3,
                "name": "Report",
                "version": "1.0",
                "permissions": ["sidePanel", "offscreen", "identity"],
                "side_panel": ["default_path": "sidepanel.html"],
                "oauth2": [
                    "client_id": "synthetic-client",
                    "scopes": ["email"],
                ],
            ],
            resources: [
                "sidepanel.html": pageHTML(title: "Side"),
                "worker.js": """
                chrome.sidePanel.setOptions({path: "sidepanel.html"});
                chrome.offscreen.hasDocument();
                chrome.identity.getRedirectURL("done");
                """,
            ]
        )
        let manifest = try validateManifest(root: root)
        let report = ChromeMV3SidePanelOffscreenIdentityCompatibilityReportGenerator
            .makeReport(
                manifest: manifest,
                generatedBundleRootURL: root,
                syntheticIdentityFixture:
                    .testOnly(authToken: "do-not-serialize")
            )
        try ChromeMV3SidePanelOffscreenIdentityCompatibilityReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )
        let decoded = try JSONDecoder().decode(
            ChromeMV3SidePanelOffscreenIdentityCompatibilityReport.self,
            from:
                Data(
                    contentsOf:
                        root.appendingPathComponent(report.reportFileName)
                )
        )
        let json = String(
            data: try ChromeMV3DeterministicJSON.encodedData(decoded),
            encoding: .utf8
        ) ?? ""

        XCTAssertEqual(decoded, report)
        XCTAssertTrue(decoded.apiDetection.sidePanelAPIUsedInSource)
        XCTAssertTrue(decoded.apiDetection.offscreenAPIUsedInSource)
        XCTAssertTrue(decoded.apiDetection.identityAPIUsedInSource)
        XCTAssertFalse(decoded.sidePanelAvailableInProduct)
        XCTAssertFalse(decoded.offscreenAvailableInProduct)
        XCTAssertFalse(decoded.identityAvailableInProduct)
        XCTAssertFalse(decoded.identityExternalAuthNetworkAllowed)
        XCTAssertFalse(decoded.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(decoded.runtimeLoadable)
        XCTAssertFalse(decoded.productRuntimeExposed)
        XCTAssertFalse(json.contains("do-not-serialize"))
    }

    @MainActor
    func testDisabledModuleBlocksCompatibilityReportAndEnabledLinksDiagnostics()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }
        let root = try makeExtensionRoot(
            named: "module",
            manifest: [
                "manifest_version": 3,
                "name": "Module",
                "version": "1.0",
                "permissions": ["sidePanel"],
                "side_panel": ["default_path": "sidepanel.html"],
            ],
            resources: ["sidepanel.html": pageHTML(title: "Side")]
        )
        let disabled = try makeModule(enabled: false)
        let disabledReport = disabled
            .chromeMV3SidePanelOffscreenIdentityCompatibilityReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        XCTAssertNil(disabledReport)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath:
                    root.appendingPathComponent(
                        ChromeMV3SidePanelOffscreenIdentityCompatibilityReportWriter
                            .reportFileName
                    ).path
            )
        )

        let enabled = try makeModule(enabled: true)
        let report = try XCTUnwrap(
            enabled
                .chromeMV3SidePanelOffscreenIdentityCompatibilityReportIfEnabled(
                    fromRewrittenBundleRoot: root,
                    writeReport: true
                )
        )
        let diagnostics = enabled.chromeMV3InventoryDiagnosticsIfEnabled(
            rootURL: root
        )
        XCTAssertEqual(
            diagnostics?.sidePanelOffscreenIdentityReportSummary,
            report.summary
        )
        XCTAssertFalse(enabled.hasLoadedRuntime)
        XCTAssertTrue(
            enabled
                .tearDownChromeMV3SidePanelOffscreenIdentityCompatibilityIfEnabled()
        )
    }

    func testSourceLevelGuardsForSidePanelOffscreenIdentityLayer()
        throws
    {
        let sources = try sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
            "SumiTests",
        ])
        let targetFiles = sources.filter {
            $0.relativePath ==
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3SidePanelOffscreenIdentityCompatibility.swift"
        }
        let joined = targetFiles.map(\.contents).joined(separator: "\n")
        for forbidden in [
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer",
            "Pro" + "cess(",
            "URL" + "Session",
            "ASWeb" + "AuthenticationSession",
            "WKWeb" + "View",
            "Browser" + "Config",
            "add" + "UserScript",
            "add" + "ScriptMessageHandler",
        ] {
            XCTAssertFalse(joined.contains(forbidden), forbidden)
        }

        let chromeMV3Joined = targetFiles.map(\.contents)
            .joined(separator: "\n")
        for forbiddenRegex in [
            "sidePanelAvailableInProduct.*" + "tr" + "ue",
            "offscreenAvailableInProduct.*" + "tr" + "ue",
            "identityAvailableInProduct.*" + "tr" + "ue",
            "identityExternalAuthNetworkAllowed.*" + "tr" + "ue",
            "normalTabRuntimeBridgeAvailable.*" + "tr" + "ue",
            "runtimeLoadable.*" + "tr" + "ue",
            "productRuntimeExposed.*" + "tr" + "ue",
        ] {
            XCTAssertNil(
                chromeMV3Joined.range(
                    of: forbiddenRegex,
                    options: .regularExpression
                ),
                forbiddenRegex
            )
        }
    }

    private func stateOwner(
        root: URL? = nil,
        defaultSidePanelPath: String? = nil,
        syntheticIdentityFixture:
            ChromeMV3IdentitySyntheticFixture = .none
    ) -> ChromeMV3SidePanelOffscreenIdentityRuntimeStateOwner {
        ChromeMV3SidePanelOffscreenIdentityRuntimeStateOwner(
            configuration:
                ChromeMV3SidePanelOffscreenIdentityConfiguration
                .syntheticHarness(
                    generatedBundleRootPath: root?.path,
                    defaultSidePanelPath: defaultSidePanelPath,
                    syntheticIdentityFixture: syntheticIdentityFixture
                )
        )
    }

    private func request(
        namespace: String,
        methodName: String,
        mode: ChromeMV3JSBridgeInvocationMode = .promise,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3SidePanelOffscreenIdentityBridgeRequest {
        ChromeMV3SidePanelOffscreenIdentityBridgeRequest(
            namespace: namespace,
            methodName: methodName,
            invocationMode: mode,
            arguments: arguments
        )
    }

    private func offscreenCreateRequest(
        url: String,
        reasons: [String],
        justification: String
    ) -> ChromeMV3SidePanelOffscreenIdentityBridgeRequest {
        request(
            namespace: "offscreen",
            methodName: "createDocument",
            arguments: [
                .object([
                    "url": .string(url),
                    "reasons":
                        .array(reasons.map(ChromeMV3StorageValue.string)),
                    "justification": .string(justification),
                ]),
            ]
        )
    }

    private func validateManifest(root: URL) throws -> ChromeMV3Manifest {
        try ChromeMV3ManifestValidator.validateManifestFile(
            at: root.appendingPathComponent("manifest.json")
        )
    }

    private func makeExtensionRoot(
        named name: String,
        manifest: [String: Any],
        resources: [String: String]
    ) throws -> URL {
        let root = try temporaryDirectory(named: name)
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys, .prettyPrinted]
        )
        try manifestData.write(
            to: root.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        for (path, contents) in resources {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private func pageHTML(title: String, body: String = "") -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(title)</title>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    @MainActor
    private func makeModule(enabled: Bool) throws -> SumiExtensionsModule {
        let defaults = UserDefaults(
            suiteName:
                "ChromeMV3SidePanelOffscreenIdentityTests.\(UUID().uuidString)"
        )!
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.setEnabled(enabled, for: .extensions)
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration()
        )
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ChromeMV3SidePanelOffscreenIdentityCompatibilityTests",
                isDirectory: true
            )
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(root.deletingLastPathComponent())
        return root.standardizedFileURL
    }

    private func sourceFiles(
        in roots: [String]
    ) throws -> [(relativePath: String, contents: String)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var files: [(String, String)] = []
        for relativeRoot in roots {
            let absoluteRoot = root.appendingPathComponent(relativeRoot)
            guard let enumerator = FileManager.default.enumerator(
                at: absoluteRoot,
                includingPropertiesForKeys: nil
            ) else { continue }
            for case let fileURL as URL in enumerator
                where fileURL.pathExtension == "swift"
            {
                let contents = try String(
                    contentsOf: fileURL,
                    encoding: .utf8
                )
                let relative = fileURL.path
                    .replacingOccurrences(
                        of: root.path + "/",
                        with: ""
                    )
                files.append((relative, contents))
            }
        }
        return files
    }
}
