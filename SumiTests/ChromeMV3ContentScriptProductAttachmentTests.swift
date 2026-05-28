import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3ContentScriptProductAttachmentTests: XCTestCase {
    private let extensionID = "content-script-extension"
    private let profileID = "content-script-profile"
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testDefaultGateKeepsContentScriptAttachmentOff() throws {
        let gate = ChromeMV3ContentScriptProductGateRecord.defaultBlocked()

        XCTAssertFalse(gate.contentScriptAttachmentAvailableInDeveloperPreview)
        XCTAssertFalse(gate.contentScriptAttachmentAvailableInPublicProduct)
        XCTAssertFalse(gate.contentScriptBridgeAvailableInDeveloperPreview)
        XCTAssertFalse(gate.contentScriptBridgeAvailableInPublicProduct)
        XCTAssertFalse(gate.staticContentScriptsAllowed)
        XCTAssertFalse(gate.dynamicScriptingAllowed)
        XCTAssertFalse(gate.normalTabGeneralRuntimeAvailable)
        XCTAssertTrue(gate.blockers.contains(.contentScriptGateBlocked))
        XCTAssertTrue(gate.blockers.contains(.dynamicScriptingBlocked))
    }

    func testInstallAndManagerRenderingAloneDoNotRegisterEndpoints()
        throws
    {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()

        XCTAssertTrue(fixture.preflight.canRegisterEndpointNow)
        XCTAssertEqual(registry.summary.endpointCount, 0)
        XCTAssertEqual(registry.summary.activeEndpointCount, 0)
        XCTAssertEqual(registry.summary.portCount, 0)
    }

    func testNonMatchingURLBlocksAttachment() throws {
        let fixture = try makePreflightFixture(
            urlString: "https://other.example/login"
        )

        XCTAssertFalse(fixture.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertTrue(fixture.preflight.blockers.contains(.urlNotMatched))
        XCTAssertTrue(
            fixture.preflight.blockers.contains(.noEligibleDeclaredContentScript)
        )
    }

    func testMatchingURLPassesPreflightWithHostPermission() throws {
        let fixture = try makePreflightFixture()

        XCTAssertTrue(fixture.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertTrue(fixture.preflight.canExposeContentScriptBridgeNow)
        XCTAssertTrue(fixture.preflight.canRegisterEndpointNow)
        XCTAssertEqual(fixture.preflight.matchedScripts.count, 1)
        XCTAssertTrue(fixture.preflight.hostAccessDecision.hasHostAccess)
        XCTAssertTrue(fixture.preflight.blockers.isEmpty)
    }

    func testMissingHostPermissionBlocksAndActiveTabGrantAllows()
        throws
    {
        let missing = try makePreflightFixture(hostPermissions: [])
        let active = try makePreflightFixture(
            hostPermissions: [],
            apiPermissions: ["activeTab"],
            activeTabGrants: [
                ChromeMV3ActiveTabGrant(
                    extensionID: extensionID,
                    profileID: profileID,
                    tabID: 7,
                    scope: .origin("https://example.com"),
                    reason: .testFixture,
                    userGestureModeled: true,
                    createdSequence: 1
                ),
            ]
        )

        XCTAssertFalse(missing.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertTrue(
            missing.preflight.blockers.contains(.hostPermissionMissing)
                || missing.preflight.blockers.contains(.activeTabMissing)
        )
        XCTAssertTrue(active.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertTrue(active.preflight.hostAccessDecision.allowedByActiveTab)
    }

    func testRevokedHostPermissionBlocksFutureAttachment() throws {
        let fixture = try makePreflightFixture(
            revokedPermissions: ["https://example.com/*"]
        )

        XCTAssertFalse(fixture.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertTrue(fixture.preflight.blockers.contains(.hostPermissionMissing))
        XCTAssertTrue(fixture.preflight.hostAccessDecision.revokedByPattern)
    }

    func testManifestAttachmentModelDiagnosesUnsafeMissingAndUnsupported()
        throws
    {
        let root = try makeBundle(files: ["content.js": "void 0;\n"])
        var manifest = try ChromeMV3ManifestValidator.validateJSONObject([
            "manifest_version": 3,
            "name": "Blocked Content Scripts",
            "version": "1.0.0",
        ])
        manifest.contentScripts = [
            contentScript(js: ["missing.js"]),
            contentScript(js: ["../evil.js"]),
            contentScript(js: ["content.js"], world: "MAIN"),
            contentScript(js: ["content.js"], allFrames: true),
            contentScript(js: ["content.js"], css: ["style.css"]),
        ]
        let plan = ChromeMV3ContentScriptAttachmentPlan.make(
            manifest: manifest,
            generatedBundleRootURL: root,
            extensionID: extensionID,
            profileID: profileID
        )
        let blockers = Set(plan.declaredScripts.flatMap(\.blockers))

        XCTAssertTrue(blockers.contains(.missingJSFile))
        XCTAssertTrue(blockers.contains(.unsafeJSPath))
        XCTAssertTrue(blockers.contains(.unsupportedWorld))
        XCTAssertTrue(blockers.contains(.frameBehaviorUnsupported))
        XCTAssertTrue(blockers.contains(.cssUnsupported))
        XCTAssertTrue(plan.supportedScripts.isEmpty)
    }

    func testEndpointRegistryRoutesMessagesPortsAndTeardown()
        throws
    {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        let endpoint = try XCTUnwrap(
            registry.registerEndpoint(
                preflight: fixture.preflight,
                messageListenerRegistered: true,
                connectListenerRegistered: true
            )
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                popupConfiguration(
                    hostPermissions: ["https://example.com/*"]
                ),
            contentScriptEndpointRegistry: registry
        )

        let message = handler.handle(request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [
                .number(7),
                .object(["ping": .bool(true)]),
            ]
        ))
        let connect = handler.handle(request(
            namespace: "tabs",
            methodName: "connect",
            arguments: [
                .number(7),
                .object(["name": .string("preview-port")]),
            ],
            invocationMode: .fireAndForget
        ))

        XCTAssertEqual(endpoint.tabID, 7)
        XCTAssertTrue(message.succeeded)
        XCTAssertEqual(
            stringValue(objectValue(message.resultPayload)?["target"]),
            "contentScriptEndpoint"
        )
        XCTAssertTrue(connect.succeeded)
        XCTAssertEqual(
            stringValue(objectValue(connect.resultPayload)?["portKind"]),
            "contentScriptEndpointPort"
        )
        XCTAssertEqual(registry.summary.portCount, 1)

        registry.navigationStarted(
            profileID: profileID,
            tabID: 7,
            oldNavigationSequence: 1
        )
        let staleMessage = handler.handle(request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [
                .number(7),
                .object(["ping": .bool(true)]),
            ]
        ))
        XCTAssertFalse(staleMessage.succeeded)
        XCTAssertEqual(staleMessage.lastErrorCode, "noReceivingEnd")
        XCTAssertTrue(
            registry.summary.lifecycleStates.contains(.navigationInvalidated)
        )
    }

    func testListenerMissingReturnsNoReceivingEnd() throws {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        _ = registry.registerEndpoint(preflight: fixture.preflight)
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                popupConfiguration(
                    hostPermissions: ["https://example.com/*"]
                ),
            contentScriptEndpointRegistry: registry
        )

        let response = handler.handle(request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [
                .number(7),
                .object(["ping": .bool(true)]),
            ]
        ))

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorCode, "noReceivingEnd")
    }

    func testContentScriptRuntimeSendMessageIsDeterministicNoReceiver()
        throws
    {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        _ = registry.registerEndpoint(
            preflight: fixture.preflight,
            messageListenerRegistered: true
        )
        let host = ChromeMV3ContentScriptBridgeHost(
            extensionID: extensionID,
            profileID: profileID,
            tabID: 7,
            frameID: 0,
            documentID: "document-1",
            urlString: "https://example.com/login",
            permissionBroker:
                permissionBroker(hostPermissions: ["https://example.com/*"]),
            endpointRegistry: registry
        )

        let response = host.handle([
            "namespace": "runtime",
            "methodName": "sendMessage",
            "bridgeCallID": "content-script-send-message",
        ])

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorCode, "noReceivingEnd")
        XCTAssertFalse(response.serviceWorkerWakeAttempted)
        XCTAssertFalse(response.nativeHostLaunchAttempted)
    }

    func testDisableUninstallResetAndTabCloseTeardownEndpoints()
        throws
    {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        _ = registry.registerEndpoint(
            preflight: fixture.preflight,
            messageListenerRegistered: true,
            connectListenerRegistered: true
        )

        registry.detachForExtensionDisable(
            extensionID: extensionID,
            profileID: profileID
        )
        XCTAssertEqual(registry.summary.activeEndpointCount, 0)
        XCTAssertTrue(
            registry.summary.lifecycleStates.contains(.disabledWhileAttached)
        )

        let second = ChromeMV3ContentScriptEndpointRegistry()
        _ = second.registerEndpoint(
            preflight: fixture.preflight,
            messageListenerRegistered: true
        )
        second.detachForUninstall(extensionID: extensionID, profileID: profileID)
        XCTAssertTrue(
            second.summary.lifecycleStates.contains(.uninstalledWhileAttached)
        )

        let third = ChromeMV3ContentScriptEndpointRegistry()
        _ = third.registerEndpoint(
            preflight: fixture.preflight,
            messageListenerRegistered: true
        )
        third.detachForReset(profileID: profileID)
        XCTAssertTrue(third.summary.lifecycleStates.contains(.resetWhileAttached))

        let fourth = ChromeMV3ContentScriptEndpointRegistry()
        _ = fourth.registerEndpoint(
            preflight: fixture.preflight,
            messageListenerRegistered: true
        )
        fourth.detachForTabClose(profileID: profileID, tabID: 7)
        XCTAssertTrue(fourth.summary.lifecycleStates.contains(.tabClosed))
        XCTAssertTrue(fourth.summary.lifecycleStates.contains(.teardownComplete))
    }

    #if canImport(WebKit)
    @MainActor
    func testWKUserScriptAttachmentOccursOnlyAfterDeveloperPreviewGates()
        throws
    {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration = true
        let before = configuration.userContentController.userScripts.count

        let attachment =
            ChromeMV3ContentScriptWKAttachmentExecutor.attachIfAllowed(
                configuration: configuration,
                preflight: fixture.preflight,
                permissionBroker:
                    permissionBroker(hostPermissions: ["https://example.com/*"]),
                endpointRegistry: registry
            )

        XCTAssertTrue(attachment.result.attached)
        XCTAssertTrue(attachment.result.endpointRegistered)
        XCTAssertGreaterThan(
            configuration.userContentController.userScripts.count,
            before
        )
        XCTAssertEqual(registry.summary.endpointCount, 1)
        attachment.handle?.tearDown(reason: "test teardown")
        XCTAssertEqual(configuration.userContentController.userScripts.count, before)
        XCTAssertTrue(registry.summary.lifecycleStates.contains(.teardownComplete))
    }

    @MainActor
    func testWKUserScriptAttachmentRefusesAuxiliarySurface()
        throws
    {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration = false

        let attachment =
            ChromeMV3ContentScriptWKAttachmentExecutor.attachIfAllowed(
                configuration: configuration,
                preflight: fixture.preflight,
                permissionBroker:
                    permissionBroker(hostPermissions: ["https://example.com/*"]),
                endpointRegistry: registry
            )

        XCTAssertFalse(attachment.result.attached)
        XCTAssertTrue(attachment.result.blockers.contains(.tabSurfaceIneligible))
        XCTAssertEqual(configuration.userContentController.userScripts.count, 0)
    }
    #endif

    private func makePreflightFixture(
        urlString: String = "https://example.com/login",
        hostPermissions: [String] = ["https://example.com/*"],
        apiPermissions: [String] = [],
        activeTabGrants: [ChromeMV3ActiveTabGrant] = [],
        revokedPermissions: [String] = [],
        moduleEnabled: Bool = true,
        extensionEnabled: Bool = true,
        generatedBundleActive: Bool = true,
        gate: ChromeMV3ContentScriptProductGateRecord =
            .developerPreviewAllowed(),
        tabSurface: ChromeMV3WebViewSurface = .normalTab
    ) throws -> PreflightFixture {
        let root = try makeBundle(files: ["content.js": "globalThis.__sumiMV3Content = true;\n"])
        let manifest = try ChromeMV3ManifestValidator.validateJSONObject([
            "manifest_version": 3,
            "name": "Content Script Fixture",
            "version": "1.0.0",
            "permissions": apiPermissions,
            "host_permissions": hostPermissions,
            "content_scripts": [
                [
                    "matches": ["https://example.com/*"],
                    "js": ["content.js"],
                    "run_at": "document_start",
                ],
            ],
        ])
        let plan = ChromeMV3ContentScriptAttachmentPlan.make(
            manifest: manifest,
            generatedBundleRootURL: root,
            extensionID: extensionID,
            profileID: profileID
        )
        let broker = permissionBroker(
            apiPermissions: apiPermissions,
            hostPermissions: hostPermissions,
            activeTabGrants: activeTabGrants,
            revokedPermissions: revokedPermissions
        )
        let preflight = ChromeMV3NormalTabContentScriptPreflightEvaluator
            .evaluate(
                input: ChromeMV3NormalTabContentScriptPreflightInput(
                    moduleEnabled: moduleEnabled,
                    extensionEnabled: extensionEnabled,
                    productRuntimePreflightAllowsNormalTabAttachment: true,
                    contentScriptGate: gate,
                    attachmentPlan: plan,
                    permissionBroker: broker,
                    tabID: 7,
                    frameID: 0,
                    documentID: "document-1",
                    navigationSequence: 1,
                    urlString: urlString,
                    tabSurface: tabSurface,
                    generatedBundleActive: generatedBundleActive,
                    webKitUserContentControllerAvailable: true,
                    teardownPending: false
                )
            )
        return PreflightFixture(
            root: root,
            manifest: manifest,
            plan: plan,
            preflight: preflight
        )
    }

    private func permissionBroker(
        apiPermissions: [String] = [],
        hostPermissions: [String],
        activeTabGrants: [ChromeMV3ActiveTabGrant] = [],
        revokedPermissions: [String] = []
    ) -> ChromeMV3PermissionBroker {
        ChromeMV3PermissionBroker(
            state: ChromeMV3PermissionBrokerState(
                extensionID: extensionID,
                profileID: profileID,
                requiredPermissions: apiPermissions,
                hostPermissions: hostPermissions,
                revokedPermissions: revokedPermissions,
                activeTabGrants: activeTabGrants
            )
        )
    }

    private func popupConfiguration(
        hostPermissions: [String],
        apiPermissions: [String] = []
    ) -> ChromeMV3PopupOptionsJSBridgeConfiguration {
        ChromeMV3PopupOptionsJSBridgeConfiguration(
            extensionID: extensionID,
            profileID: profileID,
            surfaceID: "\(profileID):\(extensionID):actionPopup",
            surface: .actionPopup,
            extensionBaseURLString: "chrome-extension://\(extensionID)/",
            moduleState: .enabled,
            bridgeAvailable: true,
            popupOptionsJSBridgeAvailableInDeveloperPreview: true,
            popupOptionsJSBridgeAvailableInPublicProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            contentScriptAttachmentAvailableInProduct: false,
            runtimeLoadable: false,
            manifestPermissions: apiPermissions,
            manifestOptionalPermissions: [],
            manifestHostPermissions: hostPermissions,
            manifestOptionalHostPermissions: [],
            activeTabGrants: [],
            allowlist: .defaultPolicy,
            diagnostics: [
                "Popup/options bridge test configuration."
            ]
        )
    }

    private func request(
        namespace: String,
        methodName: String,
        arguments: [ChromeMV3StorageValue] = [],
        invocationMode: ChromeMV3JSBridgeInvocationMode = .promise
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: UUID().uuidString,
            namespace: namespace,
            methodName: methodName,
            invocationMode: invocationMode,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    private func makeBundle(files: [String: String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
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

    private func contentScript(
        js: [String],
        css: [String] = [],
        allFrames: Bool = false,
        world: String? = nil
    ) -> ChromeMV3ContentScript {
        ChromeMV3ContentScript(
            matches: ["https://example.com/*"],
            excludeMatches: [],
            includeGlobs: [],
            excludeGlobs: [],
            js: js,
            css: css,
            allFrames: allFrames,
            matchAboutBlank: false,
            matchOriginAsFallback: false,
            runAt: "document_start",
            world: world
        )
    }

    private func objectValue(
        _ value: ChromeMV3StorageValue?
    ) -> [String: ChromeMV3StorageValue]? {
        guard case .object(let object) = value else { return nil }
        return object
    }

    private func stringValue(_ value: ChromeMV3StorageValue?) -> String? {
        guard case .string(let string) = value else { return nil }
        return string
    }
}

private struct PreflightFixture {
    var root: URL
    var manifest: ChromeMV3Manifest
    var plan: ChromeMV3ContentScriptAttachmentPlan
    var preflight: ChromeMV3NormalTabContentScriptPreflight
}
