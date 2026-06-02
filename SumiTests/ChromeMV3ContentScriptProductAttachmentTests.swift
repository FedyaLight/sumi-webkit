import Foundation
import XCTest
#if canImport(WebKit)
import WebKit
#endif

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

    func testEndpointDoesNotRegisterWhenDefaultGateIsClosed()
        throws
    {
        let fixture = try makePreflightFixture(gate: .defaultBlocked())
        let registry = ChromeMV3ContentScriptEndpointRegistry()

        XCTAssertFalse(fixture.preflight.canRegisterEndpointNow)
        XCTAssertNil(registry.registerEndpoint(preflight: fixture.preflight))
        XCTAssertEqual(registry.summary.endpointCount, 0)
    }

    func testEndpointDoesNotRegisterForBlockedFileTarget()
        throws
    {
        let fixture = try makePreflightFixture(
            urlString: "file:///Users/test/login.html",
            hostPermissions: ["<all_urls>"],
            contentScriptMatches: ["file:///*"]
        )
        let registry = ChromeMV3ContentScriptEndpointRegistry()

        XCTAssertFalse(fixture.preflight.canRegisterEndpointNow)
        XCTAssertNil(registry.registerEndpoint(preflight: fixture.preflight))
        XCTAssertEqual(registry.summary.endpointCount, 0)
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

    func testCSSAttachmentRequiresSamePreflightGates() throws {
        let disabledModule = try makePreflightFixture(
            moduleEnabled: false,
            includeCSS: true
        )
        let disabledExtension = try makePreflightFixture(
            extensionEnabled: false,
            includeCSS: true
        )
        let nonMatching = try makePreflightFixture(
            urlString: "https://other.example/login",
            includeCSS: true
        )
        let missingPermission = try makePreflightFixture(
            hostPermissions: [],
            includeCSS: true
        )
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
            ],
            includeCSS: true
        )

        XCTAssertFalse(disabledModule.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertTrue(disabledModule.preflight.blockers.contains(.moduleDisabled))
        XCTAssertFalse(disabledExtension.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertTrue(
            disabledExtension.preflight.blockers.contains(.extensionDisabled)
        )
        XCTAssertFalse(nonMatching.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertTrue(nonMatching.preflight.blockers.contains(.urlNotMatched))
        XCTAssertFalse(missingPermission.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertTrue(
            missingPermission.preflight.blockers.contains(.hostPermissionMissing)
                || missingPermission.preflight.blockers.contains(.activeTabMissing)
        )
        XCTAssertTrue(active.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertEqual(
            active.preflight.matchedScripts.flatMap(\.validatedCSSFilePaths),
            ["style.css"]
        )
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
            contentScript(js: ["content.js"], matchAboutBlank: true),
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
        XCTAssertTrue(blockers.contains(.missingCSSFile))
        XCTAssertTrue(plan.supportedScripts.isEmpty)
    }

    func testFileExcludePatternDoesNotBlockNonFileEligibleTarget()
        throws
    {
        let fixture = try makePreflightFixture(
            contentScriptMatches: ["*://*/*", "file:///*"],
            contentScriptExcludeMatches: ["file:///*.xml*"]
        )
        let decision = try XCTUnwrap(
            fixture.preflight.targetDecisions.first
        )

        XCTAssertTrue(fixture.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertTrue(decision.matched)
        XCTAssertFalse(decision.excluded)
        XCTAssertEqual(decision.excludeIgnoredForTarget, ["file:///*.xml*"])
        XCTAssertTrue(
            decision.unsupportedButNonBlocking.contains("file:///*")
        )
        XCTAssertTrue(
            decision.unsupportedButNonBlocking.contains("file:///*.xml*")
        )
        XCTAssertFalse(
            fixture.plan.declaredScripts.first?.blockers
                .contains(.unsupportedMatchPattern) == true
        )
    }

    func testActualFileTargetRemainsBlockedEvenWithFileMatchPattern()
        throws
    {
        let fixture = try makePreflightFixture(
            urlString: "file:///Users/test/login.html",
            hostPermissions: ["<all_urls>"],
            contentScriptMatches: ["file:///*"]
        )
        let decision = try XCTUnwrap(
            fixture.preflight.targetDecisions.first
        )

        XCTAssertFalse(fixture.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertTrue(decision.matchPatternMatched)
        XCTAssertTrue(
            fixture.preflight.blockers.contains(.frameBehaviorUnsupported)
        )
        XCTAssertTrue(
            fixture.preflight.blockers.contains(.hostPermissionMissing)
                || fixture.preflight.blockers.contains(.activeTabMissing)
        )
        XCTAssertTrue(fixture.preflight.diagnostics.joined(separator: "\n")
            .contains("file"))
    }

    func testInvalidMatchPatternRemainsBlocker() throws {
        let fixture = try makePreflightFixture(
            contentScriptMatches: ["https://*example.com/*"]
        )
        let record = try XCTUnwrap(fixture.plan.declaredScripts.first)
        let decision = try XCTUnwrap(fixture.preflight.targetDecisions.first)

        XCTAssertFalse(fixture.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertTrue(record.blockers.contains(.unsupportedMatchPattern))
        XCTAssertTrue(decision.blockers.contains(.unsupportedMatchPattern))
        XCTAssertTrue(
            fixture.preflight.blockers.contains(.noEligibleDeclaredContentScript)
        )
    }

    func testAllFramesTrueIsTopFrameOnlyAndDeferred() throws {
        let topFrame = try makePreflightFixture(allFrames: true)
        let record = try XCTUnwrap(topFrame.plan.declaredScripts.first)
        let decision = try XCTUnwrap(topFrame.preflight.targetDecisions.first)

        XCTAssertTrue(topFrame.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertTrue(record.allFramesDeclared)
        XCTAssertEqual(record.frameSupport, .topFrameOnly)
        XCTAssertTrue(record.multiFrameDeferred)
        XCTAssertTrue(decision.allFramesDeclared)
        XCTAssertEqual(decision.frameSupport, .topFrameOnly)
        XCTAssertTrue(decision.multiFrameDeferred)
        XCTAssertFalse(record.blockers.contains(.frameBehaviorUnsupported))

        let subframeTarget = ChromeMV3ContentScriptFrameTarget.make(
            tabID: 7,
            frameID: 4,
            parentFrameID: 0,
            documentID: "subframe-document",
            navigationSequence: 2,
            urlString: "https://example.com/frame",
            parentURLString: "https://example.com/login",
            isMainFrame: false
        )
        let subframe = try makePreflightFixture(
            urlString: "https://example.com/frame",
            frameID: 4,
            documentID: "subframe-document",
            navigationSequence: 2,
            frameTarget: subframeTarget,
            allFrames: true
        )

        XCTAssertFalse(subframe.preflight.canAttachDeclaredContentScriptsNow)
        XCTAssertTrue(
            subframe.preflight.blockers.contains(.frameBehaviorUnsupported)
        )
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

    func testCSSSupportPolicyRecordsDeveloperPreviewOnlyStrategy() throws {
        let policy =
            ChromeMV3ContentScriptCSSSupportPolicy
            .developerPreviewPrivateUserStyleSheet()

        XCTAssertTrue(policy.cssContentScriptsAvailableInDeveloperPreview)
        XCTAssertFalse(policy.cssContentScriptsAvailableInPublicProduct)
        XCTAssertEqual(policy.cssInjectionStrategy, .privateWKUserStyleSheet)
        XCTAssertEqual(
            policy.cssRemovalStrategy,
            .removeAssociatedContentWorldStyleSheets
        )
        XCTAssertEqual(
            policy.cssScopeGuarantee,
            .extensionProfileNormalTabMainFrameDocumentNavigation
        )
        XCTAssertNil(policy.cssBlockedReason)
    }

    func testManifestCSSResourceModelValidatesOrderSizeAndHash() throws {
        let root = try makeBundle(files: [
            "content.js": "void 0;\n",
            "style.css": "body { color: rgb(1 2 3); }\n",
            "theme.css": ":root { --sumi-test: 1; }\n",
        ])
        var manifest = try ChromeMV3ManifestValidator.validateJSONObject([
            "manifest_version": 3,
            "name": "CSS Content Script",
            "version": "1.0.0",
        ])
        manifest.contentScripts = [
            contentScript(js: ["content.js"], css: ["style.css", "theme.css"]),
        ]

        let plan = ChromeMV3ContentScriptAttachmentPlan.make(
            manifest: manifest,
            generatedBundleRootURL: root,
            extensionID: extensionID,
            profileID: profileID
        )
        let record = try XCTUnwrap(plan.declaredScripts.first)

        XCTAssertEqual(record.cssPolicyStatus, .supportedPrivateUserStyleSheet)
        XCTAssertEqual(record.cssFiles, ["style.css", "theme.css"])
        XCTAssertEqual(record.validatedCSSFilePaths, ["style.css", "theme.css"])
        XCTAssertEqual(record.cssResources.map(\.injectionOrder), [0, 1])
        XCTAssertTrue(record.cssResources.allSatisfy(\.fileExists))
        XCTAssertTrue(record.cssResources.allSatisfy(\.pathSafe))
        XCTAssertEqual(record.cssResources[0].contentByteCount, 28)
        XCTAssertNotNil(record.cssResources[0].contentSHA256)
        XCTAssertFalse(record.blockers.contains(.cssUnsupported))
        XCTAssertTrue(record.diagnostics.joined(separator: "\n")
            .contains("CSS resources are recorded"))
        XCTAssertTrue(record.diagnostics.joined(separator: "\n")
            .contains("CSS file validated"))
        XCTAssertTrue(plan.diagnostics.joined(separator: "\n")
            .contains("scripting.insertCSS remains outside this plan"))
    }

    func testCSSPathValidationRejectsTraversalAndMissingFile() throws {
        let root = try makeBundle(files: ["content.js": "void 0;\n"])
        var manifest = try ChromeMV3ManifestValidator.validateJSONObject([
            "manifest_version": 3,
            "name": "Unsafe CSS Content Script",
            "version": "1.0.0",
        ])
        manifest.contentScripts = [
            contentScript(js: ["content.js"], css: ["../style.css"]),
            contentScript(js: ["content.js"], css: ["missing.css"]),
        ]

        let plan = ChromeMV3ContentScriptAttachmentPlan.make(
            manifest: manifest,
            generatedBundleRootURL: root,
            extensionID: extensionID,
            profileID: profileID
        )
        let blockers = Set(plan.declaredScripts.flatMap(\.blockers))

        XCTAssertTrue(blockers.contains(.unsafeCSSPath))
        XCTAssertTrue(blockers.contains(.missingCSSFile))
        XCTAssertTrue(plan.declaredScripts.flatMap(\.cssResources)
            .contains { $0.pathSafe == false })
        XCTAssertTrue(plan.declaredScripts.flatMap(\.cssResources)
            .contains { $0.fileExists == false })
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
        XCTAssertEqual(
            objectValue(message.resultPayload)?["listenerCount"],
            .number(1)
        )
        XCTAssertTrue(connect.succeeded)
        XCTAssertEqual(
            stringValue(objectValue(connect.resultPayload)?["portKind"]),
            "contentScriptEndpointPort"
        )
        XCTAssertEqual(registry.summary.portCount, 1)
        XCTAssertEqual(registry.summary.activePortCount, 1)
        XCTAssertEqual(registry.summary.endpointMetadata.count, 1)
        XCTAssertEqual(
            registry.summary.endpointMetadata.first?.hostPermissionSource,
            .requiredHostPermission
        )
        XCTAssertEqual(
            registry.summary.endpointMetadata.first?.teardownPolicy.contains(
                "navigation"
            ),
            true
        )

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

    func testCSSAttachmentLifecycleInvalidatesWithEndpointTeardown()
        throws
    {
        let fixture = try makePreflightFixture(includeCSS: true)
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        _ = registry.registerEndpoint(
            preflight: fixture.preflight,
            connectListenerRegistered: true
        )

        XCTAssertEqual(registry.summary.cssAttachmentCount, 1)
        XCTAssertEqual(registry.summary.activeCSSAttachmentCount, 1)

        registry.navigationStarted(
            profileID: profileID,
            tabID: 7,
            oldNavigationSequence: 1
        )
        XCTAssertEqual(registry.summary.activeCSSAttachmentCount, 0)
        XCTAssertTrue(
            registry.summary.lifecycleStates.contains(.navigationInvalidated)
        )

        let permissionRegistry = ChromeMV3ContentScriptEndpointRegistry()
        _ = permissionRegistry.registerEndpoint(
            preflight: fixture.preflight,
            connectListenerRegistered: true
        )
        permissionRegistry.invalidateForPermissionChange(
            extensionID: extensionID,
            profileID: profileID,
            permissionBroker: permissionBroker(hostPermissions: []),
            reason: "activeTab grant expired."
        )
        XCTAssertEqual(permissionRegistry.summary.activeCSSAttachmentCount, 0)

        let disableRegistry = ChromeMV3ContentScriptEndpointRegistry()
        _ = disableRegistry.registerEndpoint(
            preflight: fixture.preflight,
            connectListenerRegistered: true
        )
        disableRegistry.detachForExtensionDisable(
            extensionID: extensionID,
            profileID: profileID
        )
        XCTAssertEqual(disableRegistry.summary.activeCSSAttachmentCount, 0)
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
        XCTAssertTrue(response.diagnostics.joined(separator: "\n")
            .contains("present but has no runtime.onMessage listener"))
    }

    func testEndpointLookupClassifiesWrongTabAndFrame() throws {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        _ = registry.registerEndpoint(
            preflight: fixture.preflight,
            messageListenerRegistered: true
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                popupConfiguration(
                    hostPermissions: ["https://example.com/*"]
                ),
            contentScriptEndpointRegistry: registry
        )

        let wrongTab = handler.handle(request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [
                .number(8),
                .object(["ping": .bool(true)]),
            ]
        ))
        let wrongFrame = handler.handle(request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [
                .number(7),
                .object(["ping": .bool(true)]),
                .object(["frameId": .number(9)]),
            ]
        ))

        XCTAssertFalse(wrongTab.succeeded)
        XCTAssertEqual(wrongTab.lastErrorCode, "noReceivingEnd")
        XCTAssertTrue(wrongTab.diagnostics.joined(separator: "\n")
            .contains("Endpoint lookup classification: wrongTab"))
        XCTAssertFalse(wrongFrame.succeeded)
        XCTAssertEqual(wrongFrame.lastErrorCode, "noReceivingEnd")
        XCTAssertTrue(wrongFrame.diagnostics.joined(separator: "\n")
            .contains("Endpoint lookup classification: wrongFrame"))
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

    func testContentScriptRuntimeSendMessageRoutesThroughSharedLifecycle()
        throws
    {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        _ = registry.registerEndpoint(
            preflight: fixture.preflight,
            messageListenerRegistered: true
        )
        let session = try makeSharedLifecycleSession()
        session.registerListener(
            event: .runtimeOnMessage,
            listenerID: "content-runtime-on-message",
            outcome: .modelDispatched(.string("content-ok"))
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
            endpointRegistry: registry,
            sharedLifecycleSession: session
        )

        let response = host.handle([
            "namespace": "runtime",
            "methodName": "sendMessage",
            "bridgeCallID": "content-script-send-message-lifecycle",
            "arguments": [["ping": true]],
        ])

        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(response.resultPayload, .string("content-ok"))
        XCTAssertTrue(response.serviceWorkerWakeAttempted)
        XCTAssertEqual(
            response.serviceWorkerLifecycleWakeResult?.sourceComponentKind,
            .contentScriptSyntheticEndpoint
        )
        XCTAssertEqual(
            response.serviceWorkerLifecycleWakeResult?.sessionID,
            session.key.lifecycleSessionID
        )
    }

    func testContentScriptRuntimeSendMessageRoutesThroughSharedJSListenerDispatcher()
        throws
    {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        _ = registry.registerEndpoint(
            preflight: fixture.preflight,
            messageListenerRegistered: true
        )
        let session = try makeSharedLifecycleSession()
        session.registerJSListenerDispatcher(
            event: .runtimeOnMessage,
            listenerID: "content-js-runtime-on-message"
        ) { input in
            let responsePayload: ChromeMV3StorageValue = .object([
                "echo": input.arguments.first ?? .null,
                "frameId": .number(Double(input.sender.frameID ?? -1)),
                "senderURLRedacted": .bool(input.sender.urlRedacted),
                "tabId": .number(Double(input.sender.tabID ?? -1)),
            ])
            session.registerListener(
                event: input.event,
                listenerID: "content-js-runtime-on-message-executed",
                outcome: .modelDispatched(responsePayload)
            )
            let wake = session.routeEvent(
                reason: input.source.wakeReason,
                listenerEvent: input.event,
                sourceComponentID: input.sourceComponentID,
                sourceComponentKind: input.sourceComponentKind,
                payload: input.arguments.first,
                payloadSummary: input.payloadSummary,
                sourceContext: input.source.sourceContext
            )
            return ChromeMV3ServiceWorkerJSListenerDispatchResult(
                event: input.event,
                listenerID: "content-js-runtime-on-message",
                resultKind: wake.dispatched ? .delivered : .noReceiver,
                responsePayload: wake.responsePayload,
                lastErrorMessage: wake.lastErrorMessage,
                lifecycleWakeResult: wake,
                diagnostics: [
                    "Content-script test JS dispatcher routed through shared lifecycle.",
                ]
            )
        }
        let host = ChromeMV3ContentScriptBridgeHost(
            extensionID: extensionID,
            profileID: profileID,
            tabID: 7,
            frameID: 0,
            documentID: "document-1",
            urlString: "https://example.com/login",
            permissionBroker:
                permissionBroker(hostPermissions: ["https://example.com/*"]),
            endpointRegistry: registry,
            sharedLifecycleSession: session
        )

        let response = host.handle([
            "namespace": "runtime",
            "methodName": "sendMessage",
            "bridgeCallID": "content-script-send-message-js-dispatcher",
            "arguments": [["ping": true]],
        ])

        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(
            response.resultPayload,
            .object([
                "echo": .object(["ping": .bool(true)]),
                "frameId": .number(0),
                "senderURLRedacted": .bool(true),
                "tabId": .number(7),
            ])
        )
        XCTAssertTrue(response.serviceWorkerWakeAttempted)
        XCTAssertEqual(
            response.serviceWorkerLifecycleWakeResult?.sessionID,
            session.key.lifecycleSessionID
        )
        XCTAssertEqual(
            response.serviceWorkerLifecycleWakeResult?.sourceComponentKind,
            .contentScriptSyntheticEndpoint
        )
    }

    func testContentScriptRuntimeSendMessageNoListenerStaysPrecise()
        throws
    {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        _ = registry.registerEndpoint(
            preflight: fixture.preflight,
            messageListenerRegistered: true
        )
        let session = try makeSharedLifecycleSession()
        let host = ChromeMV3ContentScriptBridgeHost(
            extensionID: extensionID,
            profileID: profileID,
            tabID: 7,
            frameID: 0,
            documentID: "document-1",
            urlString: "https://example.com/login",
            permissionBroker:
                permissionBroker(hostPermissions: ["https://example.com/*"]),
            endpointRegistry: registry,
            sharedLifecycleSession: session
        )

        let response = host.handle([
            "namespace": "runtime",
            "methodName": "sendMessage",
            "bridgeCallID": "content-script-send-message-no-listener",
            "arguments": [["ping": true]],
        ])

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorCode, "noReceivingEnd")
        XCTAssertTrue(response.serviceWorkerWakeAttempted)
        XCTAssertEqual(
            response.serviceWorkerLifecycleWakeResult?.listenerEvent,
            .runtimeOnMessage
        )
        XCTAssertEqual(
            response.serviceWorkerLifecycleWakeResult?.blockers,
            ["No synthetic/model listener is registered."]
        )
        XCTAssertTrue(response.diagnostics.joined(separator: "\n")
            .contains("no listener accepted"))
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

    func testContentScriptRuntimeConnectPortUsesSharedLifecycleKeepalive()
        throws
    {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        _ = registry.registerEndpoint(
            preflight: fixture.preflight,
            connectListenerRegistered: true
        )
        let session = try makeSharedLifecycleSession()
        session.registerListener(
            event: .runtimeOnConnect,
            listenerID: "content-runtime-on-connect"
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
            endpointRegistry: registry,
            sharedLifecycleSession: session
        )

        let connect = host.handle([
            "namespace": "runtime",
            "methodName": "connect",
            "bridgeCallID": "runtime-connect-lifecycle",
            "arguments": [["name": "content-runtime"]],
        ])
        let portID = try XCTUnwrap(
            stringValue(objectValue(connect.resultPayload)?["portID"])
        )
        XCTAssertTrue(connect.succeeded)
        XCTAssertTrue(connect.serviceWorkerWakeAttempted)
        XCTAssertEqual(
            session.runtimeOwner.snapshot.activeKeepaliveRecords.count,
            1
        )

        let post = host.handle([
            "namespace": "runtime",
            "methodName": "port.postMessage",
            "bridgeCallID": "runtime-port-post-lifecycle",
            "arguments": [portID, ["payload": true]],
        ])
        let disconnect = host.handle([
            "namespace": "runtime",
            "methodName": "port.disconnect",
            "bridgeCallID": "runtime-port-disconnect-lifecycle",
            "arguments": [portID],
        ])

        XCTAssertTrue(post.succeeded)
        XCTAssertTrue(post.serviceWorkerWakeAttempted)
        XCTAssertTrue(disconnect.succeeded)
        XCTAssertTrue(
            session.runtimeOwner.snapshot.activeKeepaliveRecords.isEmpty
        )
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
        XCTAssertEqual(attachment.result.installedCSSStyleSheetCount, 0)
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
        XCTAssertEqual(attachment.result.installedCSSStyleSheetCount, 0)
        XCTAssertEqual(configuration.userContentController.userScripts.count, 0)
    }

    @MainActor
    func testWKUserStyleSheetCSSAttachmentIsScopedAndRemoved()
        async throws
    {
        let pageURL = URL(string: "https://example.com/login")!
        let matchPattern = "<all_urls>"
        let fixture = try makePreflightFixture(
            urlString: pageURL.absoluteString,
            hostPermissions: [matchPattern],
            contentScriptMatches: [matchPattern],
            includeCSS: true
        )
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration = true

        let attachment =
            ChromeMV3ContentScriptWKAttachmentExecutor.attachIfAllowed(
                configuration: configuration,
                preflight: fixture.preflight,
                permissionBroker:
                    permissionBroker(hostPermissions: [matchPattern]),
                endpointRegistry: registry
            )

        XCTAssertTrue(attachment.result.attached)
        XCTAssertEqual(attachment.result.installedCSSStyleSheetCount, 1)

        let styledWebView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            configuration: configuration
        )
        let unrelatedConfiguration = WKWebViewConfiguration()
        unrelatedConfiguration.sumiIsNormalTabWebViewConfiguration = true
        let unrelatedWebView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            configuration: unrelatedConfiguration
        )

        try await loadURL(pageURL, into: styledWebView)
        try await loadURL(pageURL, into: unrelatedWebView)
        let styledColor = try await bodyBackgroundColor(in: styledWebView)
        let unrelatedColor = try await bodyBackgroundColor(in: unrelatedWebView)

        XCTAssertEqual(styledColor, "rgb(9, 8, 7)")
        XCTAssertNotEqual(unrelatedColor, "rgb(9, 8, 7)")

        attachment.handle?.tearDown(reason: "css teardown test")
        try await loadURL(pageURL, into: styledWebView)
        let afterTeardown = try await bodyBackgroundColor(in: styledWebView)

        XCTAssertNotEqual(afterTeardown, "rgb(9, 8, 7)")
        XCTAssertEqual(registry.summary.activeCSSAttachmentCount, 0)
    }

    @MainActor
    func testWKNormalTabRuntimeBridgeSendsMessageAndPerformsDummyFill()
        async throws
    {
        let pageURL = URL(string: "https://example.com/login")!
        let fixture = try makePreflightFixture(
            urlString: pageURL.absoluteString,
            contentScriptSource: """
            document.addEventListener("DOMContentLoaded", async () => {
              const response = await chrome.runtime.sendMessage({
                type: "sumiSyntheticFillLogin"
              });
              document.querySelector("#username").value = response.username;
              document.querySelector("#password").value = response.password;
              document.body.dataset.sumiRuntimeBridgeFill = response.ok ? "filled" : "blocked";
            });
            """
        )
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        let session = try makeSharedLifecycleSession()
        session.registerListener(
            event: .runtimeOnMessage,
            listenerID: "normal-tab-runtime-fill-listener",
            outcome: .modelDispatched(.object([
                "ok": .bool(true),
                "username": .string("sumi-test-user@example.test"),
                "password": .string("sumi-test-password-not-secret"),
            ]))
        )
        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration = true
        let beforeScriptCount =
            configuration.userContentController.userScripts.count

        let attachment =
            ChromeMV3ContentScriptWKAttachmentExecutor.attachIfAllowed(
                configuration: configuration,
                preflight: fixture.preflight,
                permissionBroker:
                    permissionBroker(hostPermissions: ["https://example.com/*"]),
                endpointRegistry: registry,
                sharedLifecycleSession: session
            )

        XCTAssertTrue(attachment.result.attached)
        XCTAssertTrue(attachment.result.endpointRegistered)
        XCTAssertGreaterThan(
            attachment.result.installedUserScriptCount,
            beforeScriptCount
        )
        XCTAssertEqual(attachment.result.installedScriptMessageHandlerCount, 1)
        XCTAssertEqual(
            fixture.preflight.matchedScripts.flatMap(\.validatedJSFilePaths),
            ["content.js"]
        )
        XCTAssertFalse(
            fixture.preflight.diagnostics.joined(separator: "\n")
                .contains("bootstrap-autofill")
        )

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            configuration: configuration
        )
        try await loadURL(pageURL, html: contentScriptLoginHTML, into: webView)
        let filled = try await waitForDummyLoginFill(in: webView)

        XCTAssertEqual(filled["status"], "filled")
        XCTAssertEqual(filled["username"], "sumi-test-user@example.test")
        XCTAssertEqual(filled["password"], "sumi-test-password-not-secret")
        XCTAssertTrue(
            session.runtimeOwner.snapshot.events.contains {
                $0.reason == .runtimeMessage
                    && $0.sourceContext == .contentScript
            }
        )
        XCTAssertEqual(registry.summary.activeEndpointCount, 1)

        attachment.handle?.tearDown(reason: "normal-tab runtime fill teardown")
        XCTAssertEqual(
            configuration.userContentController.userScripts.count,
            beforeScriptCount
        )
        XCTAssertEqual(registry.summary.activeEndpointCount, 0)
        XCTAssertTrue(session.runtimeOwner.snapshot.activeKeepaliveRecords.isEmpty)
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
        frameTarget: ChromeMV3ContentScriptFrameTarget = .unknownMainFrame,
        contentScriptMatches: [String] = ["https://example.com/*"],
        contentScriptExcludeMatches: [String] = [],
        allFrames: Bool = false,
        includeCSS: Bool = false,
        contentScriptSource: String = "globalThis.__sumiMV3Content = true;\n"
    ) throws -> PreflightFixture {
        var files = [
            "content.js": contentScriptSource,
        ]
        if includeCSS {
            files["style.css"] =
                "body { background-color: rgb(9, 8, 7) !important; }\n"
        }
        let root = try makeBundle(files: files)
        var contentScript: [String: Any] = [
            "matches": contentScriptMatches,
            "exclude_matches": contentScriptExcludeMatches,
            "js": ["content.js"],
            "run_at": "document_start",
            "all_frames": allFrames,
        ]
        if includeCSS {
            contentScript["css"] = ["style.css"]
        }
        let manifest = try ChromeMV3ManifestValidator.validateJSONObject([
            "manifest_version": 3,
            "name": "Content Script Fixture",
            "version": "1.0.0",
            "permissions": apiPermissions,
            "host_permissions": hostPermissions,
            "content_scripts": [contentScript],
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

    private func makeSharedLifecycleSession()
        throws -> ChromeMV3ServiceWorkerSharedLifecycleSession
    {
        try XCTUnwrap(
            ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
                .session(profileID: profileID, extensionID: extensionID)
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

    #if canImport(WebKit)
    @MainActor
    private func loadURL(
        _ url: URL,
        html: String = contentScriptCSSHTML,
        into webView: WKWebView
    ) async throws {
        let didFinish = expectation(description: "content script CSS page loaded")
        let delegate = ContentScriptCSSNavigationDelegate {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate
        if #available(macOS 12.0, *) {
            webView.loadSimulatedRequest(
                URLRequest(url: url),
                responseHTML: html
            )
        } else {
            webView.loadHTMLString(html, baseURL: url)
        }
        await fulfillment(of: [didFinish], timeout: 5)
        webView.navigationDelegate = nil
        _ = delegate
    }

    @MainActor
    private func bodyBackgroundColor(in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(
                "getComputedStyle(document.body).backgroundColor"
            ) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: result as? String ?? "")
            }
        }
    }

    @MainActor
    private func waitForDummyLoginFill(
        in webView: WKWebView
    ) async throws -> [String: String] {
        let script = """
        ({
          status: document.body.dataset.sumiRuntimeBridgeFill || "",
          username: document.querySelector("#username")?.value || "",
          password: document.querySelector("#password")?.value || ""
        })
        """
        for _ in 0..<50 {
            let result = try await webView.evaluateJavaScript(script)
            if let object = result as? [String: String],
               object["status"] == "filled"
            {
                return object
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let result = try await webView.evaluateJavaScript(script)
        return result as? [String: String] ?? [:]
    }
    #endif

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

#if canImport(WebKit)
private let contentScriptCSSHTML =
    """
    <!doctype html>
    <html>
      <head><meta charset="utf-8"><title>CSS Scope</title></head>
      <body><main id="probe">probe</main></body>
    </html>
    """

private let contentScriptLoginHTML =
    """
    <!doctype html>
    <html>
      <head><meta charset="utf-8"><title>Synthetic Login</title></head>
      <body>
        <form id="synthetic-login-form">
          <label for="username">Email</label>
          <input id="username" name="username" autocomplete="username" type="email">
          <label for="password">Password</label>
          <input id="password" name="password" autocomplete="current-password" type="password">
          <button id="submit-login" type="button">Sign in</button>
        </form>
      </body>
    </html>
    """

private final class ContentScriptCSSNavigationDelegate:
    NSObject,
    WKNavigationDelegate
{
    private let didFinish: () -> Void

    init(didFinish: @escaping () -> Void) {
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        _ = webView
        _ = navigation
        didFinish()
    }
}
#endif
