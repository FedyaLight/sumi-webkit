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

    func testLivePreparedPackageManagerBinderSourceGuards() throws {
        let managerSource = try sourceFile(
            "Sumi/Managers/ExtensionManager/ExtensionManager+ChromeMV3ContentScripts.swift"
        )
        let moduleSource = try sourceFile(
            "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift"
        )
        let popupSource = try sourceFile(
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ProductPopupOptionsUI.swift"
        )

        XCTAssertTrue(managerSource.contains(
            "ChromeMV3GeneratedBundleWriter.metadataFileName"
        ))
        XCTAssertTrue(managerSource.contains(
            "ChromeMV3ManifestValidator"
        ))
        XCTAssertTrue(managerSource.contains(
            "ChromeMV3ContentScriptAttachmentPlan.make"
        ))
        XCTAssertTrue(managerSource.contains(
            "ChromeMV3NormalTabContentScriptPreflightEvaluator"
        ))
        XCTAssertTrue(managerSource.contains(
            "ChromeMV3ContentScriptWKAttachmentExecutor.attachIfAllowed"
        ))
        XCTAssertTrue(managerSource.contains(
            "ChromeMV3LivePreparedServiceWorkerLifecycleStore"
        ))
        XCTAssertTrue(managerSource.contains(
            "sharedLifecycleSessionProvider"
        ))
        XCTAssertTrue(managerSource.contains(
            "ChromeMV3ServiceWorkerJSExecutionHarness"
        ))
        XCTAssertTrue(managerSource.contains(
            "nativePortKeepaliveAvailableInFixture: false"
        ))
        XCTAssertTrue(managerSource.contains(
            "serviceWorkerLifecycle=lazy-content-script-runtime-port"
        ))
        XCTAssertTrue(managerSource.contains(
            "bindWebViewForMessageDispatch"
        ))
        XCTAssertTrue(managerSource.contains(
            "Manifest content_scripts.matches contributes static injection host scope."
        ))
        XCTAssertTrue(managerSource.contains(
            "profile.isEphemeral == false"
        ))
        XCTAssertTrue(managerSource.contains(
            "browserManager?.windowRegistry?.windows[windowID] != nil"
        ))
        XCTAssertTrue(managerSource.contains(
            #"["http", "https"]"#
        ))
        XCTAssertTrue(managerSource.contains(
            "frameID: 0"
        ))
        XCTAssertTrue(managerSource.contains(
            "contentWorld=sumi.mv3.content."
        ))
        XCTAssertTrue(managerSource.contains(
            "injectionTiming=shim:document_start,declared:manifest_run_at"
        ))
        XCTAssertTrue(moduleSource.contains(
            "chromeMV3InternalNormalTabConfigurationAttachmentAllowed"
        ))
        XCTAssertTrue(popupSource.contains(
            "contentScriptEndpointRegistryProvider"
        ))
        XCTAssertFalse(managerSource.contains("collectPageDetailsImmediately"))
        XCTAssertFalse(managerSource.contains("fillForm"))
        XCTAssertFalse(managerSource.contains("com.bitwarden.desktop"))
        XCTAssertFalse(managerSource.contains("WKContentWorld.pageWorld"))
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

    func testManifestJSResourcesPreserveDeclaredInjectionOrder() throws {
        let root = try makeBundle(files: [
            "z-first.js": "globalThis.sumiOrder = ['first'];\n",
            "a-second.js": "globalThis.sumiOrder.push('second');\n",
        ])
        var manifest = try ChromeMV3ManifestValidator.validateJSONObject([
            "manifest_version": 3,
            "name": "Ordered JS Content Script",
            "version": "1.0.0",
        ])
        manifest.contentScripts = [
            contentScript(js: ["z-first.js", "a-second.js"]),
        ]

        let plan = ChromeMV3ContentScriptAttachmentPlan.make(
            manifest: manifest,
            generatedBundleRootURL: root,
            extensionID: extensionID,
            profileID: profileID
        )
        let record = try XCTUnwrap(plan.declaredScripts.first)

        XCTAssertEqual(record.jsFiles, ["z-first.js", "a-second.js"])
        XCTAssertEqual(
            record.validatedJSFilePaths,
            ["z-first.js", "a-second.js"]
        )
        XCTAssertTrue(record.diagnostics.joined(separator: "\n")
            .contains("JS resources are recorded"))
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

    func testTabsQueryAndSendMessageUseActiveCapturedEndpointOnly()
        throws
    {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        _ = try XCTUnwrap(
            registry.registerEndpoint(
                preflight: fixture.preflight,
                messageListenerRegistered: true
            )
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                popupConfiguration(
                    hostPermissions: ["https://example.com/*"]
                ),
            contentScriptEndpointRegistry: registry
        )

        let query = handler.handle(request(
            namespace: "tabs",
            methodName: "query",
            arguments: [
                .object([
                    "active": .bool(true),
                    "currentWindow": .bool(true),
                ]),
            ]
        ))
        let broadQuery = handler.handle(request(
            namespace: "tabs",
            methodName: "query",
            arguments: [.object(["active": .bool(true)])]
        ))
        let serviceWorkerQuery = handler.handleServiceWorkerTabsRequest(
            request(
                namespace: "tabs",
                methodName: "query",
                arguments: [
                    .object([
                        "active": .bool(true),
                        "currentWindow": .bool(true),
                    ]),
                ]
            )
        )
        let serviceWorkerMessage = handler.handleServiceWorkerTabsRequest(
            request(
                namespace: "tabs",
                methodName: "sendMessage",
                arguments: [
                    .number(7),
                    .object(["type": .string("service-worker-probe")]),
                    .object(["frameId": .number(0)]),
                ]
            )
        )

        guard case .array(let tabs)? = query.resultPayload,
              case .object(let firstTab)? = tabs.first
        else {
            return XCTFail("Expected one active tab payload.")
        }
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(firstTab["id"], .number(7))
        XCTAssertEqual(stringValue(firstTab["url"]), "https://example.com/login")
        XCTAssertTrue(query.diagnostics.joined(separator: "\n").contains(
            "captured content-script endpoint registry"
        ))
        guard case .array(let broadTabs)? = broadQuery.resultPayload else {
            return XCTFail("Expected broad query payload.")
        }
        XCTAssertTrue(broadTabs.isEmpty)
        XCTAssertTrue(broadQuery.diagnostics.joined(separator: "\n").contains(
            "rejected broad enumeration"
        ))
        XCTAssertTrue(serviceWorkerQuery.succeeded)
        XCTAssertTrue(serviceWorkerMessage.succeeded)
        XCTAssertTrue(
            serviceWorkerMessage.diagnostics.joined(separator: "\n")
                .contains("sourceContext=serviceWorker")
        )
        XCTAssertFalse(serviceWorkerMessage.nativeHostLaunchAttempted)
    }

    func testTabsMessagingBridgeBlocksWrongProfilePrivateAndMissingPermission()
        throws
    {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        _ = try XCTUnwrap(
            registry.registerEndpoint(
                preflight: fixture.preflight,
                messageListenerRegistered: true
            )
        )
        let allowedBroker =
            permissionBroker(hostPermissions: ["https://example.com/*"])

        let wrongProfile = ChromeMV3ContentScriptTabsMessagingBridge.query(
            registry: registry,
            request:
                ChromeMV3ContentScriptTabsQueryRequest(
                    extensionID: extensionID,
                    profileID: "other-profile",
                    sourceContext: .actionPopup,
                    queryInfo: [
                        "active": .bool(true),
                        "currentWindow": .bool(true),
                    ],
                    permissionBroker: allowedBroker,
                    activeTabID: 7
                )
        )
        let privateTab = ChromeMV3ContentScriptTabsMessagingBridge.query(
            registry: registry,
            request:
                ChromeMV3ContentScriptTabsQueryRequest(
                    extensionID: extensionID,
                    profileID: profileID,
                    sourceContext: .actionPopup,
                    queryInfo: [
                        "active": .bool(true),
                        "currentWindow": .bool(true),
                    ],
                    permissionBroker: allowedBroker,
                    activeTabID: 7,
                    offRecordTabIDs: [7]
                )
        )
        let missingPermission =
            ChromeMV3ContentScriptTabsMessagingBridge.sendMessage(
                registry: registry,
                request:
                    ChromeMV3ContentScriptTabsSendMessageRequest(
                        extensionID: extensionID,
                        profileID: profileID,
                        sourceContext: .actionPopup,
                        extensionBaseURLString:
                            "chrome-extension://\(extensionID)/",
                        tabID: 7,
                        frameID: 0,
                        documentID: "document-1",
                        message: .object(["type": .string("probe")]),
                        permissionBroker: permissionBroker(hostPermissions: []),
                        responseMode: .promise,
                        userGestureAvailable: true,
                        bridgeCallID: "missing-permission"
                    )
            )

        XCTAssertTrue(wrongProfile.tabs.isEmpty)
        XCTAssertTrue(wrongProfile.diagnostics.joined(separator: "\n").contains(
            "no active top-frame content-script endpoint"
        ))
        XCTAssertTrue(privateTab.tabs.isEmpty)
        XCTAssertTrue(privateTab.diagnostics.joined(separator: "\n").contains(
            "private/off-record"
        ))
        XCTAssertFalse(missingPermission.succeeded)
        XCTAssertEqual(
            missingPermission.selectedLastError?.error,
            .hostPermissionMissing
        )
        XCTAssertTrue(missingPermission.diagnostics.joined(separator: "\n")
            .contains("permission/gate result=blocked"))
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
                "senderURLRedacted": .bool(false),
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

    func testContentScriptRuntimeConnectCreatesSharedLifecycleSessionLazilyAndReleasesAfterDisconnect()
        throws
    {
        let fixture = try makePreflightFixture()
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        _ = registry.registerEndpoint(
            preflight: fixture.preflight,
            connectListenerRegistered: true
        )
        let session = try makeSharedLifecycleSession()
        registerRuntimePortEchoDispatchers(on: session)
        var providerCallCount = 0
        var releaseCallCount = 0
        var releaseReason: String?
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
            sharedLifecycleSessionProvider: {
                providerCallCount += 1
                return session
            },
            sharedLifecycleSessionReleaseHandler: { releasedSession, reason in
                XCTAssertTrue(releasedSession === session)
                releaseCallCount += 1
                releaseReason = reason
            }
        )

        XCTAssertEqual(providerCallCount, 0)
        XCTAssertTrue(session.runtimeOwner.snapshot.activeKeepaliveRecords.isEmpty)

        let connect = host.handle([
            "namespace": "runtime",
            "methodName": "connect",
            "bridgeCallID": "runtime-connect-lazy-lifecycle",
            "arguments": [["name": "content-runtime"]],
        ])
        let portID = try XCTUnwrap(
            stringValue(objectValue(connect.resultPayload)?["portID"])
        )

        XCTAssertTrue(connect.succeeded)
        XCTAssertEqual(providerCallCount, 1)
        XCTAssertEqual(
            stringValue(objectValue(connect.resultPayload)?["name"]),
            "content-runtime"
        )
        XCTAssertEqual(
            session.runtimeOwner.snapshot.activeKeepaliveRecords.count,
            1
        )
        let disconnect = host.handle([
            "namespace": "runtime",
            "methodName": "port.disconnect",
            "bridgeCallID": "runtime-port-disconnect-lazy-lifecycle",
            "arguments": [portID],
        ])
        XCTAssertTrue(disconnect.succeeded)
        XCTAssertEqual(releaseCallCount, 1)
        XCTAssertEqual(releaseReason, "Port.disconnect called by content script.")
        XCTAssertTrue(session.runtimeOwner.snapshot.activeKeepaliveRecords.isEmpty)
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
        var capturedConnectInput:
            ChromeMV3ServiceWorkerJSListenerDispatchInput?
        var capturedPortMessageInput:
            ChromeMV3ServiceWorkerRuntimePortDeliveryInput?
        registerRuntimePortEchoDispatchers(
            on: session,
            onConnectInput: { capturedConnectInput = $0 },
            onPortMessageInput: { capturedPortMessageInput = $0 }
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
        let connectInput = try XCTUnwrap(capturedConnectInput)
        let connectArgument = try XCTUnwrap(
            objectValue(connectInput.arguments.first)
        )
        let senderPayload = try XCTUnwrap(
            objectValue(connectArgument["sender"])
        )
        XCTAssertTrue(connect.succeeded)
        XCTAssertTrue(connect.serviceWorkerWakeAttempted)
        XCTAssertEqual(
            session.runtimeOwner.snapshot.activeKeepaliveRecords.count,
            1
        )
        XCTAssertEqual(connectInput.sender.tabID, 7)
        XCTAssertEqual(connectInput.sender.frameID, 0)
        XCTAssertEqual(connectInput.sender.documentID, "document-1")
        XCTAssertEqual(connectInput.sender.sourceURL, "https://example.com/login")
        XCTAssertEqual(connectInput.sender.urlRedacted, false)
        XCTAssertEqual(stringValue(senderPayload["id"]), extensionID)
        XCTAssertEqual(stringValue(senderPayload["extensionID"]), extensionID)
        XCTAssertEqual(stringValue(senderPayload["profileID"]), profileID)
        XCTAssertEqual(senderPayload["tabId"], .number(7))
        XCTAssertEqual(senderPayload["frameId"], .number(0))
        XCTAssertEqual(stringValue(senderPayload["documentId"]), "document-1")
        XCTAssertEqual(
            stringValue(senderPayload["url"]),
            "https://example.com/login"
        )
        XCTAssertEqual(stringValue(senderPayload["origin"]), "https://example.com")
        XCTAssertEqual(boolValue(senderPayload["urlRedacted"]), false)

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
        let postPayload = try XCTUnwrap(objectValue(post.resultPayload))
        let postedMessages = try XCTUnwrap(postPayload["postedMessages"])
        guard case .array(let messages) = postedMessages,
              case .object(let firstMessage)? = messages.first
        else {
            XCTFail("Expected posted service-worker Port message.")
            return
        }

        XCTAssertTrue(post.succeeded)
        XCTAssertTrue(post.serviceWorkerWakeAttempted)
        XCTAssertEqual(capturedPortMessageInput?.sender.tabID, 7)
        XCTAssertEqual(capturedPortMessageInput?.sender.frameID, 0)
        XCTAssertEqual(
            capturedPortMessageInput?.sender.sourceURL,
            "https://example.com/login"
        )
        XCTAssertEqual(boolValue(postPayload["delivered"]), true)
        XCTAssertEqual(stringValue(firstMessage["portID"]), portID)
        XCTAssertEqual(
            objectValue(firstMessage["echo"]),
            ["payload": .bool(true)]
        )
        XCTAssertTrue(disconnect.succeeded)
        XCTAssertEqual(
            boolValue(objectValue(disconnect.resultPayload)?["disconnected"]),
            true
        )
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

    @MainActor
    func testWKTabsSendMessageDispatchesSyncResponseToRealOnMessageListener()
        async throws
    {
        let fixture = try makePreflightFixture(
            contentScriptSource: """
            chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
              if (message && message.type === "sync") {
                sendResponse({
                  ok: true,
                  mode: "sync",
                  echo: message.value,
                  senderId: sender.id,
                  sourceContext: sender.sourceContext,
                  targetDocumentId: sender.sumiTargetDocumentId
                });
              }
            });
            """
        )
        let harness = try await makeTabsMessageHarness(fixture: fixture)

        let response = await harness.handler.handleAsync(request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [
                .number(7),
                .object([
                    "type": .string("sync"),
                    "value": .string("hello"),
                ]),
                .object([
                    "frameId": .number(0),
                    "documentId": .string("document-1"),
                ]),
            ]
        ))
        let payload = try XCTUnwrap(objectValue(response.resultPayload))

        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(stringValue(payload["mode"]), "sync")
        XCTAssertEqual(stringValue(payload["echo"]), "hello")
        XCTAssertEqual(stringValue(payload["senderId"]), extensionID)
        XCTAssertEqual(stringValue(payload["sourceContext"]), "actionPopup")
        XCTAssertEqual(stringValue(payload["targetDocumentId"]), "document-1")
        XCTAssertTrue(
            response.diagnostics.joined(separator: "\n")
                .contains("dispatchResult=sendResponse")
        )
        XCTAssertTrue(response.diagnostics.joined(separator: "\n")
            .contains("No MAIN-world injection"))

        harness.attachment.handle?.tearDown(reason: "sync dispatch teardown")
    }

    @MainActor
    func testWKTabsSendMessageDispatchesAsyncSendResponseWhenListenerReturnsTrue()
        async throws
    {
        let fixture = try makePreflightFixture(
            contentScriptSource: """
            chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
              if (message && message.type === "async") {
                setTimeout(() => sendResponse({
                  ok: true,
                  mode: "async",
                  value: message.value + "-done"
                }), 10);
                return true;
              }
            });
            """
        )
        let harness = try await makeTabsMessageHarness(fixture: fixture)

        let response = await harness.handler.handleAsync(request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [
                .number(7),
                .object([
                    "type": .string("async"),
                    "value": .string("work"),
                ]),
                .object([
                    "frameId": .number(0),
                    "documentId": .string("document-1"),
                ]),
            ]
        ))
        let payload = try XCTUnwrap(objectValue(response.resultPayload))

        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(stringValue(payload["mode"]), "async")
        XCTAssertEqual(stringValue(payload["value"]), "work-done")
        XCTAssertTrue(
            response.diagnostics.joined(separator: "\n")
                .contains("runtime.onMessage sendResponse resolved")
        )

        harness.attachment.handle?.tearDown(reason: "async dispatch teardown")
    }

    @MainActor
    func testWKTabsSendMessageNoListenerAfterRemoveReportsNoReceivingEnd()
        async throws
    {
        let fixture = try makePreflightFixture(
            contentScriptSource: """
            const removedListener = () => {};
            chrome.runtime.onMessage.addListener(removedListener);
            chrome.runtime.onMessage.removeListener(removedListener);
            """
        )
        let harness = try await makeTabsMessageHarness(fixture: fixture)

        let response = await harness.handler.handleAsync(request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [
                .number(7),
                .object(["type": .string("missing")]),
                .object(["frameId": .number(0)]),
            ],
            invocationMode: .callback
        ))

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorCode, "noReceivingEnd")
        XCTAssertTrue(response.callbackWouldSetLastError)
        XCTAssertTrue(
            response.diagnostics.joined(separator: "\n")
                .contains("listenerCount=0")
        )

        harness.attachment.handle?.tearDown(reason: "no listener teardown")
    }

    @MainActor
    func testWKTabsSendMessageListenerPresentWithoutResponseIsClassified()
        async throws
    {
        let fixture = try makePreflightFixture(
            contentScriptSource: """
            chrome.runtime.onMessage.addListener(() => {
              // Intentionally ignore the message without responding.
            });
            """
        )
        let harness = try await makeTabsMessageHarness(fixture: fixture)

        let response = await harness.handler.handleAsync(request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [
                .number(7),
                .object(["type": .string("unhandled")]),
                .object(["frameId": .number(0)]),
            ]
        ))

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorCode, "noReceivingEnd")
        let diagnostics = response.diagnostics.joined(separator: "\n")
        XCTAssertTrue(diagnostics.contains("listenerCount=1"), diagnostics)
        XCTAssertTrue(
            diagnostics.contains("listenerInvoked=true"),
            diagnostics
        )
        XCTAssertTrue(
            diagnostics.contains("sendResponseCalled=false"),
            diagnostics
        )
        XCTAssertTrue(
            diagnostics.contains(
                "resultClassifier=listenerPresentButNoResponse"
            ),
            diagnostics
        )

        harness.attachment.handle?.tearDown(reason: "no response teardown")
    }

    @MainActor
    func testWKTabsSendMessageListenerThrowSurfacesLastError()
        async throws
    {
        let fixture = try makePreflightFixture(
            contentScriptSource: """
            chrome.runtime.onMessage.addListener(() => {
              throw new Error("content listener exploded");
            });
            """
        )
        let harness = try await makeTabsMessageHarness(fixture: fixture)

        let response = await harness.handler.handleAsync(request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [
                .number(7),
                .object(["type": .string("throw")]),
                .object(["frameId": .number(0)]),
            ]
        ))

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorCode, "timeout")
        XCTAssertEqual(response.lastErrorMessage, "content listener exploded")
        XCTAssertTrue(
            response.diagnostics.joined(separator: "\n")
                .contains("dispatchResult=listenerThrew")
        )

        harness.attachment.handle?.tearDown(reason: "throw teardown")
    }

    @MainActor
    func testWKTabsSendMessageWrongDocumentBlocksBeforeContentWorldDispatch()
        async throws
    {
        let fixture = try makePreflightFixture(
            contentScriptSource: """
            chrome.runtime.onMessage.addListener((_message, _sender, sendResponse) => {
              sendResponse({ok: true});
            });
            """
        )
        let harness = try await makeTabsMessageHarness(fixture: fixture)

        let response = await harness.handler.handleAsync(request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [
                .number(7),
                .object(["type": .string("wrong-document")]),
                .object([
                    "frameId": .number(0),
                    "documentId": .string("wrong-document"),
                ]),
            ]
        ))

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorCode, "noReceivingEnd")
        XCTAssertTrue(
            response.diagnostics.joined(separator: "\n")
                .contains("Endpoint lookup classification: endpointMissing")
        )
        XCTAssertFalse(
            response.diagnostics.joined(separator: "\n")
                .contains("Content-world runtime.onMessage dispatch started")
        )

        harness.attachment.handle?.tearDown(reason: "wrong document teardown")
    }

    @MainActor
    func testWKTabsSendMessageTeardownRemovesJSDispatcher()
        async throws
    {
        let fixture = try makePreflightFixture(
            contentScriptSource: """
            chrome.runtime.onMessage.addListener((_message, _sender, sendResponse) => {
              sendResponse({ok: true});
            });
            """
        )
        let harness = try await makeTabsMessageHarness(fixture: fixture)

        XCTAssertEqual(harness.registry.summary.activeJSDispatcherCount, 1)
        harness.attachment.handle?.tearDown(reason: "dispatcher teardown")

        XCTAssertEqual(harness.registry.summary.activeEndpointCount, 0)
        XCTAssertEqual(harness.registry.summary.activeJSDispatcherCount, 0)
        XCTAssertTrue(
            harness.registry.summary.lifecycleStates.contains(.teardownComplete)
        )
    }

    @MainActor
    func testWKAttachmentHandleTeardownKeepsOtherSharedRegistryEndpointAlive()
        async throws
    {
        let first = try makePreflightFixture(
            tabID: 7,
            documentID: "document-first"
        )
        let second = try makePreflightFixture(
            tabID: 8,
            documentID: "document-second"
        )
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        let firstConfiguration = WKWebViewConfiguration()
        firstConfiguration.sumiIsNormalTabWebViewConfiguration = true
        let secondConfiguration = WKWebViewConfiguration()
        secondConfiguration.sumiIsNormalTabWebViewConfiguration = true
        let broker = permissionBroker(
            hostPermissions: ["https://example.com/*"]
        )
        let firstAttachment =
            ChromeMV3ContentScriptWKAttachmentExecutor.attachIfAllowed(
                configuration: firstConfiguration,
                preflight: first.preflight,
                permissionBroker: broker,
                endpointRegistry: registry
            )
        let secondAttachment =
            ChromeMV3ContentScriptWKAttachmentExecutor.attachIfAllowed(
                configuration: secondConfiguration,
                preflight: second.preflight,
                permissionBroker: broker,
                endpointRegistry: registry
            )

        XCTAssertEqual(registry.summary.activeEndpointCount, 2)
        firstAttachment.handle?.tearDown(reason: "first endpoint teardown")

        XCTAssertEqual(registry.summary.activeEndpointCount, 1)
        XCTAssertNotNil(
            registry.targetEndpoint(
                extensionID: extensionID,
                profileID: profileID,
                tabID: 8,
                frameID: 0,
                documentID: "document-second"
            )
        )

        secondAttachment.handle?.tearDown(reason: "second endpoint teardown")
        XCTAssertEqual(registry.summary.activeEndpointCount, 0)
    }

    @MainActor
    func testWKPreparedBitwardenDeclaredContentScriptKeepsListenerAfterRuntimePortConnect()
        async throws
    {
        let packageRoot = URL(
            fileURLWithPath:
                "/Users/fedaefimov/Downloads/Aura/mv3-test-extensions/bitwarden",
            isDirectory: true
        )
        guard FileManager.default.fileExists(
            atPath: packageRoot.appendingPathComponent("manifest.json").path
        ) else {
            throw XCTSkip("Local Bitwarden MV3 package fixture is unavailable.")
        }

        let storeRoot = try makeBundle(files: [:])
        let stage = try ChromeMV3OriginalBundleStore(rootURL: storeRoot)
            .stageUnpackedDirectory(at: packageRoot)
        let generated = try ChromeMV3GeneratedBundleWriter(rootURL: storeRoot)
            .writeGeneratedBundle(
                originalBundleRecord: stage.originalBundleRecord,
                manifestSnapshot: stage.manifestSnapshot,
                planningRecord: stage.generatedBundlePlan
            )
        let manifest = try ChromeMV3ManifestValidator.validateManifestFile(
            at: generated.generatedManifestURL
        )
        let plan = ChromeMV3ContentScriptAttachmentPlan.make(
            manifest: manifest,
            generatedBundleRootURL: generated.generatedBundleRootURL,
            extensionID: extensionID,
            profileID: profileID
        )
        let broker = permissionBroker(
            apiPermissions: manifest.permissions,
            hostPermissions:
                manifest.hostPermissions
                    + manifest.contentScripts.flatMap(\.matches)
        )
        let pageURL = URL(string: "https://example.com/login")!
        let preflight = ChromeMV3NormalTabContentScriptPreflightEvaluator
            .evaluate(
                input: ChromeMV3NormalTabContentScriptPreflightInput(
                    moduleEnabled: true,
                    extensionEnabled: true,
                    productRuntimePreflightAllowsNormalTabAttachment: true,
                    contentScriptGate: .developerPreviewAllowed(),
                    attachmentPlan: plan,
                    permissionBroker: broker,
                    tabID: 7,
                    frameID: 0,
                    documentID: "bitwarden-real-document",
                    navigationSequence: 1,
                    urlString: pageURL.absoluteString,
                    frameTarget: .make(
                        tabID: 7,
                        frameID: 0,
                        parentFrameID: nil,
                        documentID: "bitwarden-real-document",
                        navigationSequence: 1,
                        urlString: pageURL.absoluteString,
                        parentURLString: nil,
                        isMainFrame: true
                    ),
                    tabSurface: .normalTab,
                    generatedBundleActive: true,
                    webKitUserContentControllerAvailable: true,
                    teardownPending: false
                )
            )
        XCTAssertEqual(
            preflight.matchedScripts.flatMap(\.validatedJSFilePaths),
            [
                "content/content-message-handler.js",
                "content/trigger-autofill-script-injection.js",
            ]
        )

        let registry = ChromeMV3ContentScriptEndpointRegistry()
        let session = try makeSharedLifecycleSession()
        let harness = ChromeMV3ServiceWorkerJSExecutionHarness(
            request:
                ChromeMV3ServiceWorkerJSExecutionRequest(
                    manifest: manifest,
                    generatedBundleRecord: generated.record,
                    extensionID: extensionID,
                    profileID: profileID,
                    moduleState: .enabled,
                    extensionEnabled: true,
                    localExperimentalGateAllowed: true,
                    dynamicImportRewriteExperimentAllowed: true
                )
        )
        let start = harness.start()
        XCTAssertTrue(
            start.status == .running || harness.canDispatchCapturedListeners,
            start.diagnostics.joined(separator: "\n")
        )
        XCTAssertTrue(
            harness.capturedListener(for: .runtimeOnConnect),
            harness.snapshot.capturedListeners
                .map { $0.event.rawValue }
                .joined(separator: ",")
        )
        harness.attachCapturedListenerDispatchers(
            to: session,
            clearingExisting: true
        )
        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration = true
        let attachment =
            ChromeMV3ContentScriptWKAttachmentExecutor.attachIfAllowed(
                configuration: configuration,
                preflight: preflight,
                permissionBroker: broker,
                endpointRegistry: registry,
                sharedLifecycleSession: session
            )
        XCTAssertTrue(attachment.result.attached)
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            configuration: configuration
        )
        attachment.handle?.bindWebViewForMessageDispatch(webView)
        try await loadURL(pageURL, html: contentScriptLoginHTML, into: webView)

        for _ in 0..<70 {
            let endpoint = registry.targetEndpoint(
                extensionID: extensionID,
                profileID: profileID,
                tabID: 7,
                frameID: 0,
                documentID: "bitwarden-real-document"
            )
            let listenerRegistered =
                endpoint?.messageListenerRegistered == true
            let activeKeepalive =
                session.runtimeOwner.snapshot.activeKeepaliveRecords
                    .isEmpty == false
            let serviceWorkerPortOpen =
                harness.snapshot.ports.contains {
                    $0.connected && $0.nativeFixturePort == false
                }
            if listenerRegistered && activeKeepalive && serviceWorkerPortOpen {
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let capturedEndpoint = try XCTUnwrap(registry.targetEndpoint(
            extensionID: extensionID,
            profileID: profileID,
            tabID: 7,
            frameID: 0,
            documentID: "bitwarden-real-document"
        ))
        XCTAssertTrue(capturedEndpoint.diagnostics.contains {
            $0.contains("runtime.onMessage listener registration observed")
        })
        XCTAssertFalse(capturedEndpoint.diagnostics.contains {
            $0.contains("runtime.onMessage listener removal observed")
        })
        XCTAssertTrue(capturedEndpoint.messageListenerRegistered)
        XCTAssertEqual(
            session.runtimeOwner.snapshot.activeKeepaliveRecords.count,
            1
        )
        let connectedPort = try XCTUnwrap(
            harness.snapshot.ports.first { $0.connected }
        )
        XCTAssertEqual(
            connectedPort.name,
            "autofill-injected-script-port"
        )
        XCTAssertEqual(connectedPort.sender.tabID, 7)
        XCTAssertEqual(connectedPort.sender.frameID, 0)
        XCTAssertEqual(
            connectedPort.sender.documentID,
            "bitwarden-real-document"
        )
        XCTAssertEqual(
            connectedPort.sender.sourceURL,
            pageURL.absoluteString
        )
        XCTAssertEqual(connectedPort.sender.urlRedacted, false)

        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                popupConfiguration(hostPermissions: ["https://example.com/*"]),
            contentScriptEndpointRegistry: registry
        )
        let response = await handler.handleAsync(request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [
                .number(7),
                .object(["command": .string("sumiSyntheticNoResponseProbe")]),
                .object([
                    "frameId": .number(0),
                    "documentId": .string("bitwarden-real-document"),
                ]),
            ]
        ))

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorCode, "noReceivingEnd")
        XCTAssertFalse(response.nativeHostLaunchAttempted)
        let diagnostics = response.diagnostics.joined(separator: "\n")
        XCTAssertTrue(
            diagnostics.contains("listenerCount=1"),
            diagnostics
        )
        XCTAssertTrue(
            diagnostics.contains(
                "evaluating real content-script runtime.onMessage listeners"
            ),
            diagnostics
        )
        XCTAssertTrue(
            diagnostics.contains("dispatchResult=noResponse"),
            diagnostics
        )
        XCTAssertTrue(
            diagnostics.contains("resultClassifier=wrongMessageContract"),
            diagnostics
        )
        XCTAssertTrue(
            diagnostics.contains(
                "runtime.onMessage listener(s) returned without sendResponse"
            ),
            diagnostics
        )
        XCTAssertFalse(
            diagnostics.contains("falling back to modeled endpoint delivery"),
            diagnostics
        )

        attachment.handle?.tearDown(reason: "Bitwarden declared listener teardown")
        harness.reset()
        session.reset()
        XCTAssertEqual(registry.summary.activeEndpointCount, 0)
        XCTAssertEqual(registry.summary.activeJSDispatcherCount, 0)
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
        tabID: Int = 7,
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
                    tabID: tabID,
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

    private func registerRuntimePortEchoDispatchers(
        on session: ChromeMV3ServiceWorkerSharedLifecycleSession,
        onConnectInput:
            ((ChromeMV3ServiceWorkerJSListenerDispatchInput) -> Void)? = nil,
        onPortMessageInput:
            ((ChromeMV3ServiceWorkerRuntimePortDeliveryInput) -> Void)? = nil
    ) {
        session.registerJSListenerDispatcher(
            event: .runtimeOnConnect,
            listenerID: "content-js-runtime-on-connect"
        ) { input in
            onConnectInput?(input)
            let name: String
            if case .object(let object)? = input.arguments.first,
               case .string(let portName)? = object["name"]
            {
                name = portName
            } else {
                name = ""
            }
            let responsePayload: ChromeMV3StorageValue = .object([
                "name": .string(name),
                "portID": .string(input.portID ?? ""),
            ])
            session.registerListener(
                event: input.event,
                listenerID: "content-js-runtime-on-connect-executed",
                outcome: .modelDispatched(responsePayload)
            )
            let wake = session.routeEvent(
                reason: input.source.wakeReason,
                listenerEvent: input.event,
                sourceComponentID: input.sourceComponentID,
                sourceComponentKind: input.sourceComponentKind,
                payload: input.arguments.first,
                payloadSummary: input.payloadSummary,
                sourceContext: input.source.sourceContext,
                keepaliveKind: input.keepaliveKind,
                portID: input.portID
            )
            session.registerRuntimePortMessageDispatcher(
                dispatcherID: "content-test-runtime-port-message"
            ) { portInput in
                onPortMessageInput?(portInput)
                let wake = session.routeEvent(
                    reason: portInput.source.wakeReason,
                    listenerEvent: .runtimeOnConnect,
                    sourceComponentID: portInput.sourceComponentID,
                    sourceComponentKind: portInput.sourceComponentKind,
                    payload: portInput.message,
                    payloadSummary: portInput.payloadSummary,
                    sourceContext: portInput.source.sourceContext,
                    portID: portInput.portID
                )
                return ChromeMV3ServiceWorkerRuntimePortDeliveryResult(
                    portID: portInput.portID,
                    delivered: true,
                    connected: true,
                    postedMessages: [
                        .object([
                            "echo": portInput.message ?? .null,
                            "portID": .string(portInput.portID),
                        ]),
                    ],
                    onMessageListenerCount: 1,
                    onDisconnectListenerCount: 1,
                    disconnectReason: nil,
                    lastErrorMessage: nil,
                    lifecycleWakeResult: wake,
                    diagnostics: [
                        "Test runtime Port message dispatcher echoed a service-worker Port.postMessage response.",
                    ]
                )
            }
            session.registerRuntimePortDisconnectDispatcher(
                dispatcherID: "content-test-runtime-port-disconnect"
            ) { portInput in
                _ = session.disconnectKeepalive(portID: portInput.portID)
                return ChromeMV3ServiceWorkerRuntimePortDeliveryResult(
                    portID: portInput.portID,
                    delivered: true,
                    connected: false,
                    postedMessages: [],
                    onMessageListenerCount: 1,
                    onDisconnectListenerCount: 1,
                    disconnectReason: portInput.disconnectReason,
                    lastErrorMessage: nil,
                    lifecycleWakeResult: nil,
                    diagnostics: [
                        "Test runtime Port disconnect dispatcher released keepalive state.",
                    ]
                )
            }
            return ChromeMV3ServiceWorkerJSListenerDispatchResult(
                event: input.event,
                listenerID: "content-js-runtime-on-connect",
                resultKind: wake.dispatched ? .delivered : .noReceiver,
                responsePayload: wake.responsePayload,
                lastErrorMessage: wake.lastErrorMessage,
                lifecycleWakeResult: wake,
                diagnostics: [
                    "Content-script test JS onConnect dispatcher routed through shared lifecycle.",
                ]
            )
        }
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

    @MainActor
    private func makeTabsMessageHarness(
        fixture: PreflightFixture
    ) async throws -> (
        registry: ChromeMV3ContentScriptEndpointRegistry,
        attachment: (
            result: ChromeMV3ContentScriptWKAttachmentResult,
            handle: ChromeMV3ContentScriptWKAttachmentHandle?
        ),
        handler: ChromeMV3PopupOptionsJSBridgeHandler,
        webView: WKWebView
    ) {
        let registry = ChromeMV3ContentScriptEndpointRegistry()
        let configuration = WKWebViewConfiguration()
        configuration.sumiIsNormalTabWebViewConfiguration = true
        let attachment =
            ChromeMV3ContentScriptWKAttachmentExecutor.attachIfAllowed(
                configuration: configuration,
                preflight: fixture.preflight,
                permissionBroker:
                    permissionBroker(hostPermissions: ["https://example.com/*"]),
                endpointRegistry: registry
            )
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 240),
            configuration: configuration
        )
        attachment.handle?.bindWebViewForMessageDispatch(webView)
        try await loadURL(
            URL(string: "https://example.com/login")!,
            html: contentScriptLoginHTML,
            into: webView
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                popupConfiguration(hostPermissions: ["https://example.com/*"]),
            contentScriptEndpointRegistry: registry
        )
        return (registry, attachment, handler, webView)
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

    private func sourceFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
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
