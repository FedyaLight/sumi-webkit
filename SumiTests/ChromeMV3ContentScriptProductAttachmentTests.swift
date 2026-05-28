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

    func testMatchAboutBlankAndOriginFallbackDiagnosticsArePrecise()
        throws
    {
        let root = try makeBundle(files: ["content.js": "void 0;\n"])
        var manifest = try ChromeMV3ManifestValidator.validateJSONObject([
            "manifest_version": 3,
            "name": "Related Frame Content Scripts",
            "version": "1.0.0",
        ])
        manifest.contentScripts = [
            contentScript(js: ["content.js"], matchAboutBlank: true),
            contentScript(js: ["content.js"], matchOriginAsFallback: true),
        ]

        let plan = ChromeMV3ContentScriptAttachmentPlan.make(
            manifest: manifest,
            generatedBundleRootURL: root,
            extensionID: extensionID,
            profileID: profileID
        )

        XCTAssertTrue(
            Set(plan.declaredScripts.flatMap(\.blockers))
                .contains(.frameBehaviorUnsupported)
        )
        XCTAssertTrue(plan.diagnostics.joined(separator: "\n")
            .contains("match_about_blank"))
        XCTAssertTrue(plan.diagnostics.joined(separator: "\n")
            .contains("match_origin_as_fallback"))
        XCTAssertTrue(plan.supportedScripts.isEmpty)
    }

    func testCSSRemainsBlockedWithScopedRemovalDiagnostic() throws {
        let root = try makeBundle(files: [
            "content.js": "void 0;\n",
            "style.css": "body { color: rgb(1 2 3); }\n",
        ])
        var manifest = try ChromeMV3ManifestValidator.validateJSONObject([
            "manifest_version": 3,
            "name": "CSS Content Script",
            "version": "1.0.0",
        ])
        manifest.contentScripts = [
            contentScript(js: ["content.js"], css: ["style.css"]),
        ]

        let plan = ChromeMV3ContentScriptAttachmentPlan.make(
            manifest: manifest,
            generatedBundleRootURL: root,
            extensionID: extensionID,
            profileID: profileID
        )
        let record = try XCTUnwrap(plan.declaredScripts.first)

        XCTAssertEqual(record.cssPolicyStatus, .blockedScopedRemovalUnavailable)
        XCTAssertTrue(record.blockers.contains(.cssUnsupported))
        XCTAssertTrue(record.diagnostics.joined(separator: "\n")
            .contains("No product global stylesheet leakage"))
        XCTAssertTrue(record.diagnostics.joined(separator: "\n")
            .contains("CSS file validated"))
    }

    func testMainWorldRemainsBlockedAndNotDowngraded() throws {
        let root = try makeBundle(files: ["content.js": "void 0;\n"])
        var manifest = try ChromeMV3ManifestValidator.validateJSONObject([
            "manifest_version": 3,
            "name": "Main World Content Script",
            "version": "1.0.0",
        ])
        manifest.contentScripts = [
            contentScript(js: ["content.js"], world: "MAIN"),
        ]

        let plan = ChromeMV3ContentScriptAttachmentPlan.make(
            manifest: manifest,
            generatedBundleRootURL: root,
            extensionID: extensionID,
            profileID: profileID
        )
        let record = try XCTUnwrap(plan.declaredScripts.first)

        XCTAssertEqual(record.world, .main)
        XCTAssertTrue(record.blockers.contains(.unsupportedWorld))
        XCTAssertTrue(record.diagnostics.joined(separator: "\n")
            .contains("not silently downgraded"))
        XCTAssertTrue(plan.supportedScripts.isEmpty)
    }

    func testFrameTargetingRecordsMainFrameAndBlocksSubframes()
        throws
    {
        let main = try makePreflightFixture()
        XCTAssertEqual(main.preflight.frameTarget.tabID, 7)
        XCTAssertEqual(main.preflight.frameTarget.frameID, 0)
        XCTAssertEqual(main.preflight.frameTarget.documentID, "document-1")
        XCTAssertEqual(main.preflight.frameTarget.navigationSequence, 1)
        XCTAssertEqual(main.preflight.frameTarget.urlClassification, .httpFamily)
        XCTAssertEqual(main.preflight.frameTarget.originRelationship, .mainFrame)

        let subframeTarget = ChromeMV3ContentScriptFrameTarget.make(
            tabID: 7,
            frameID: 4,
            parentFrameID: 0,
            documentID: "document-subframe",
            navigationSequence: 2,
            urlString: "https://example.com/frame",
            parentURLString: "https://example.com/login",
            isMainFrame: false
        )
        let subframe = try makePreflightFixture(
            urlString: "https://example.com/frame",
            frameID: 4,
            documentID: "document-subframe",
            navigationSequence: 2,
            frameTarget: subframeTarget
        )

        XCTAssertFalse(subframe.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertTrue(
            subframe.preflight.blockers.contains(.frameBehaviorUnsupported)
        )
        XCTAssertEqual(
            subframe.preflight.frameTarget.originRelationship,
            .sameOriginWithParent
        )
        XCTAssertTrue(subframe.preflight.diagnostics.joined(separator: "\n")
            .contains("subframe"))
    }

    func testSpecialFrameTargetsAreBlockedWithPreciseDiagnostics()
        throws
    {
        let aboutTarget = ChromeMV3ContentScriptFrameTarget.make(
            tabID: 7,
            frameID: 5,
            parentFrameID: 0,
            documentID: "about-document",
            navigationSequence: 3,
            urlString: "about:blank",
            parentURLString: "https://example.com/login",
            isMainFrame: false
        )
        let blobTarget = ChromeMV3ContentScriptFrameTarget.make(
            tabID: 7,
            frameID: 6,
            parentFrameID: 0,
            documentID: "blob-document",
            navigationSequence: 4,
            urlString: "blob:https://example.com/uuid",
            parentURLString: "https://example.com/login",
            isMainFrame: false
        )

        let about = try makePreflightFixture(
            urlString: "about:blank",
            frameID: 5,
            documentID: "about-document",
            navigationSequence: 3,
            frameTarget: aboutTarget
        )
        let blob = try makePreflightFixture(
            urlString: "blob:https://example.com/uuid",
            frameID: 6,
            documentID: "blob-document",
            navigationSequence: 4,
            frameTarget: blobTarget
        )

        XCTAssertTrue(about.preflight.blockers.contains(.frameBehaviorUnsupported))
        XCTAssertTrue(about.preflight.diagnostics.joined(separator: "\n")
            .contains("match_about_blank"))
        XCTAssertTrue(blob.preflight.blockers.contains(.frameBehaviorUnsupported))
        XCTAssertTrue(blob.preflight.diagnostics.joined(separator: "\n")
            .contains("match_origin_as_fallback"))
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
        XCTAssertEqual(registry.summary.activePortCount, 1)

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
        XCTAssertEqual(registry.summary.activePortCount, 0)
        XCTAssertEqual(registry.summary.disconnectedPortCount, 1)
    }

    func testPortMessageDeliveryBothDirectionsAndDisconnect() throws {
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
                popupConfiguration(hostPermissions: ["https://example.com/*"]),
            contentScriptEndpointRegistry: registry
        )
        let connect = handler.handle(request(
            namespace: "tabs",
            methodName: "connect",
            arguments: [
                .number(7),
                .object(["name": .string("preview-port")]),
            ],
            invocationMode: .fireAndForget
        ))
        let portID = try XCTUnwrap(
            stringValue(objectValue(connect.resultPayload)?["portID"])
        )
        let sender = try XCTUnwrap(objectValue(
            objectValue(connect.resultPayload)?["sender"]
        ))

        let outbound = handler.handle(request(
            namespace: "tabs",
            methodName: "port.postMessage",
            arguments: [
                .string(portID),
                .object(["ping": .bool(true)]),
            ],
            invocationMode: .fireAndForget
        ))
        let contentHost = ChromeMV3ContentScriptBridgeHost(
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
        let inbound = contentHost.handle([
            "namespace": "runtime",
            "methodName": "port.postMessage",
            "bridgeCallID": "content-port-post",
            "arguments": [
                portID,
                ["pong": true],
            ],
        ])
        let disconnect = handler.handle(request(
            namespace: "tabs",
            methodName: "port.disconnect",
            arguments: [.string(portID)],
            invocationMode: .fireAndForget
        ))

        XCTAssertEqual(endpoint.senderMetadata.endpointID, endpoint.endpointID)
        XCTAssertEqual(stringValue(sender["documentId"]), "document-1")
        XCTAssertEqual(stringValue(sender["url"]), "https://example.com/login")
        XCTAssertEqual(boolValue(sender["urlRedacted"]), false)
        XCTAssertTrue(outbound.succeeded)
        XCTAssertTrue(inbound.succeeded)
        XCTAssertTrue(disconnect.succeeded)
        XCTAssertEqual(registry.summary.portMessageCount, 2)
        XCTAssertEqual(registry.summary.activePortCount, 0)
        XCTAssertEqual(registry.summary.disconnectedPortCount, 1)
        XCTAssertTrue(
            registry.summary.portDisconnectReasons.contains(
                "Port.disconnect called by popup/options."
            )
        )
    }

    func testNavigationLifecycleAndWebViewLifecycleRecordsTeardown()
        throws
    {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        _ = registry.registerEndpoint(
            preflight: fixture.preflight,
            connectListenerRegistered: true
        )
        registry.navigationCommitted(
            profileID: profileID,
            tabID: 7,
            navigationSequence: 2
        )
        registry.navigationFinished(
            profileID: profileID,
            tabID: 7,
            navigationSequence: 2
        )
        registry.sameDocumentNavigation(
            profileID: profileID,
            tabID: 7,
            navigationSequence: 2
        )
        registry.navigationFailed(
            profileID: profileID,
            tabID: 7,
            navigationSequence: 1
        )

        XCTAssertTrue(registry.summary.lifecycleStates.contains(.navigationCommitted))
        XCTAssertTrue(registry.summary.lifecycleStates.contains(.navigationFinished))
        XCTAssertTrue(registry.summary.lifecycleStates.contains(.sameDocumentNavigation))
        XCTAssertTrue(registry.summary.lifecycleStates.contains(.navigationFailed))
        XCTAssertEqual(registry.summary.activeEndpointCount, 0)

        let replacement = ChromeMV3ContentScriptEndpointRegistry()
        _ = replacement.registerEndpoint(
            preflight: fixture.preflight,
            connectListenerRegistered: true
        )
        replacement.detachForWebViewReplacement(profileID: profileID, tabID: 7)
        XCTAssertTrue(replacement.summary.lifecycleStates.contains(.webViewReplaced))

        let suspension = ChromeMV3ContentScriptEndpointRegistry()
        _ = suspension.registerEndpoint(
            preflight: fixture.preflight,
            connectListenerRegistered: true
        )
        suspension.detachForWebViewSuspension(profileID: profileID, tabID: 7)
        XCTAssertTrue(suspension.summary.lifecycleStates.contains(.webViewSuspended))

        let discard = ChromeMV3ContentScriptEndpointRegistry()
        _ = discard.registerEndpoint(
            preflight: fixture.preflight,
            connectListenerRegistered: true
        )
        discard.detachForWebViewDiscard(profileID: profileID, tabID: 7)
        XCTAssertTrue(discard.summary.lifecycleStates.contains(.webViewDiscarded))
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

    func testContentScriptRuntimeConnectBlockedDiagnostic() throws {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        _ = registry.registerEndpoint(
            preflight: fixture.preflight,
            connectListenerRegistered: true
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
            "methodName": "connect",
            "bridgeCallID": "runtime-connect-blocked",
            "arguments": [["name": "content-runtime"]],
        ])

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorCode, "routeNotImplemented")
        XCTAssertTrue(response.diagnostics.joined(separator: "\n")
            .contains("No fake runtime Port"))
        XCTAssertFalse(response.serviceWorkerWakeAttempted)
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
        tabSurface: ChromeMV3WebViewSurface = .normalTab,
        frameID: Int = 0,
        documentID: String = "document-1",
        navigationSequence: Int = 1,
        frameTarget: ChromeMV3ContentScriptFrameTarget = .unknownMainFrame
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
                    frameID: frameID,
                    documentID: documentID,
                    navigationSequence: navigationSequence,
                    urlString: urlString,
                    frameTarget: frameTarget,
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
            permissionStateRootPath: nil,
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
        matchAboutBlank: Bool = false,
        matchOriginAsFallback: Bool = false,
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
            matchAboutBlank: matchAboutBlank,
            matchOriginAsFallback: matchOriginAsFallback,
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

    private func boolValue(_ value: ChromeMV3StorageValue?) -> Bool? {
        guard case .bool(let bool) = value else { return nil }
        return bool
    }
}

private struct PreflightFixture {
    var root: URL
    var manifest: ChromeMV3Manifest
    var plan: ChromeMV3ContentScriptAttachmentPlan
    var preflight: ChromeMV3NormalTabContentScriptPreflight
}
