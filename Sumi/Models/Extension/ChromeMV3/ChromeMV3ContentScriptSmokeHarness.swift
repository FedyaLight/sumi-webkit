//
//  ChromeMV3ContentScriptSmokeHarness.swift
//  Sumi
//
//  DEBUG/internal synthetic-WebView smoke diagnostics for controlled Chrome
//  MV3 content-script fixtures. This is not product runtime support.
//

import CryptoKit
import Foundation

enum ChromeMV3ContentScriptSmokeOutcome:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case blocked
    case passed
    case unverified
    case failed
}

enum ChromeMV3ContentScriptSmokeObservationState:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case notRequested
    case blocked
    case unverified
    case observed
    case notObserved
}

enum ChromeMV3ContentScriptObservationStrategy:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case none
    case testDOMInspection
    case webKitSupportedInspection = "WebKitSupportedInspection"
    case blockedRequiresSumiInjection
    case blockedRequiresScriptMessageHandler
    case blockedRequiresJSBridge
    case unsupportedByCurrentSDK
}

enum ChromeMV3ContentScriptObservationRiskLevel:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case none
    case low
    case unsupported
    case forbidden
}

struct ChromeMV3ContentScriptObservationStrategyScope:
    Codable,
    Equatable,
    Sendable
{
    var debugBuild: Bool
    var internalSyntheticWebViewOnly: Bool
    var explicitTestDOMInspectionAllowed: Bool
    var sameControllerSyntheticConfiguration: Bool
    var syntheticNavigationAllowed: Bool
    var productNormalTabAttachmentCount: Int
    var registersPersistentScripts: Bool
    var registersScriptMessageHandlers: Bool
    var exposesJSBridge: Bool
    var dispatchesRuntimeMessages: Bool
    var opensRuntimePorts: Bool
    var launchesNativeMessaging: Bool
    var launchesNativeHost: Bool
    var usesScheduledClockOrRepeatedChecks: Bool
    var currentSDKSupportsOneShotDOMEvaluation: Bool
    var currentSDKSupportsWebKitContentScriptInspection: Bool

    static func contentScriptSmoke(
        explicitTestDOMInspectionAllowed: Bool,
        sameControllerSyntheticConfiguration: Bool,
        syntheticNavigationAllowed: Bool,
        productNormalTabAttachmentCount: Int
    ) -> ChromeMV3ContentScriptObservationStrategyScope {
        let isDebugBuild: Bool
#if DEBUG
        isDebugBuild = true
#else
        isDebugBuild = false
#endif
        return ChromeMV3ContentScriptObservationStrategyScope(
            debugBuild: isDebugBuild,
            internalSyntheticWebViewOnly: true,
            explicitTestDOMInspectionAllowed:
                explicitTestDOMInspectionAllowed,
            sameControllerSyntheticConfiguration:
                sameControllerSyntheticConfiguration,
            syntheticNavigationAllowed: syntheticNavigationAllowed,
            productNormalTabAttachmentCount:
                productNormalTabAttachmentCount,
            registersPersistentScripts: false,
            registersScriptMessageHandlers: false,
            exposesJSBridge: false,
            dispatchesRuntimeMessages: false,
            opensRuntimePorts: false,
            launchesNativeMessaging: false,
            launchesNativeHost: false,
            usesScheduledClockOrRepeatedChecks: false,
            currentSDKSupportsOneShotDOMEvaluation: true,
            currentSDKSupportsWebKitContentScriptInspection: false
        )
    }
}

struct ChromeMV3ContentScriptObservationStrategyClassification:
    Codable,
    Equatable,
    Sendable
{
    var strategy: ChromeMV3ContentScriptObservationStrategy
    var allowedInThisPrompt: Bool
    var reason: String
    var riskLevel: ChromeMV3ContentScriptObservationRiskLevel
    var sourceDocBasis: [String]
    var productExposure: Bool
}

enum ChromeMV3ContentScriptObservationStrategyClassifier {
    static func classifyAll(
        scope: ChromeMV3ContentScriptObservationStrategyScope
    ) -> [ChromeMV3ContentScriptObservationStrategyClassification] {
        ChromeMV3ContentScriptObservationStrategy.allCases.map {
            classify($0, scope: scope)
        }
    }

    static func classify(
        _ strategy: ChromeMV3ContentScriptObservationStrategy,
        scope: ChromeMV3ContentScriptObservationStrategyScope
    ) -> ChromeMV3ContentScriptObservationStrategyClassification {
        let forbiddenReasons = forbiddenScopeReasons(scope)
        switch strategy {
        case .none:
            return classification(
                strategy: strategy,
                allowed: true,
                reason:
                    "No observation is performed; WebKit-owned content-script effects remain unverified.",
                risk: .none,
                basis: [
                    "Safe fallback when no explicit DEBUG/internal inspection flag is present.",
                ]
            )
        case .testDOMInspection:
            var blockers: [String] = []
            if scope.debugBuild == false {
                blockers.append("DEBUG build scope is required.")
            }
            if scope.internalSyntheticWebViewOnly == false {
                blockers.append("Only the internal synthetic WebView scope is allowed.")
            }
            if scope.explicitTestDOMInspectionAllowed == false {
                blockers.append("The explicit test DOM inspection flag is not enabled.")
            }
            if scope.sameControllerSyntheticConfiguration == false {
                blockers.append("The synthetic configuration must use the loaded context controller.")
            }
            if scope.syntheticNavigationAllowed == false {
                blockers.append("Synthetic navigation must be explicitly allowed.")
            }
            if scope.currentSDKSupportsOneShotDOMEvaluation == false {
                blockers.append("The current SDK does not expose one-shot DOM evaluation.")
            }
            blockers.append(contentsOf: forbiddenReasons)
            return classification(
                strategy: strategy,
                allowed: blockers.isEmpty,
                reason: blockers.isEmpty
                    ? "A one-shot page-world DOM read after deterministic synthetic navigation is allowed for DEBUG/internal observation."
                    : blockers.joined(separator: " "),
                risk: blockers.isEmpty ? .low : .forbidden,
                basis: [
                    "Apple WKWebView evaluation API executes a supplied script and calls a completion handler with the result or error.",
                    "Local WebKit headers state the default evaluation targets the main frame in WKContentWorld.pageWorld.",
                    "Local WebKit headers state DOM changes are visible across content worlds; this harness reads DOM state only.",
                    "Chrome content-script documentation states content scripts can read and modify the DOM and that isolated worlds share access to the page DOM.",
                ]
            )
        case .webKitSupportedInspection:
            return classification(
                strategy: strategy,
                allowed:
                    scope.currentSDKSupportsWebKitContentScriptInspection
                        && forbiddenReasons.isEmpty,
                reason:
                    scope.currentSDKSupportsWebKitContentScriptInspection
                        ? "A dedicated WebKit content-script inspection API is available in this SDK."
                        : "The checked WebKit SDK headers expose controller load and WebView association APIs, but no dedicated content-script marker inspection API.",
                risk:
                    scope.currentSDKSupportsWebKitContentScriptInspection
                        ? .low
                        : .unsupported,
                basis: [
                    "Local WebKit headers checked: WKWebExtensionController, WKWebViewConfiguration, WKWebExtensionContext, WKWebExtensionTab, and WKWebView.",
                ]
            )
        case .blockedRequiresSumiInjection:
            return classification(
                strategy: strategy,
                allowed: false,
                reason:
                    "Rejected because it would require Sumi-owned persistent script registration or product bridge code.",
                risk: .forbidden,
                basis: [
                    "Prompt boundary forbids Sumi-owned script injection for this observation task.",
                ]
            )
        case .blockedRequiresScriptMessageHandler:
            return classification(
                strategy: strategy,
                allowed: false,
                reason:
                    "Rejected because it would require native script-message handler registration.",
                risk: .forbidden,
                basis: [
                    "Prompt boundary forbids script-message handler registration for this observation task.",
                ]
            )
        case .blockedRequiresJSBridge:
            return classification(
                strategy: strategy,
                allowed: false,
                reason:
                    "Rejected because it would expose or rely on the Sumi JavaScript bridge.",
                risk: .forbidden,
                basis: [
                    "The Chrome MV3 JS bridge contract remains unavailable in this smoke scope.",
                ]
            )
        case .unsupportedByCurrentSDK:
            return classification(
                strategy: strategy,
                allowed: false,
                reason:
                    "The current SDK does not expose a first-class WebKit-owned content-script effect inspection surface.",
                risk: .unsupported,
                basis: [
                    "Local WebKit headers provide WebView evaluation and extension controller association, not a marker-specific content-script observation API.",
                ]
            )
        }
    }

    private static func forbiddenScopeReasons(
        _ scope: ChromeMV3ContentScriptObservationStrategyScope
    ) -> [String] {
        [
            scope.productNormalTabAttachmentCount > 0
                ? "Product normal-tab attachment is present."
                : nil,
            scope.registersPersistentScripts
                ? "Persistent script registration is requested."
                : nil,
            scope.registersScriptMessageHandlers
                ? "Script-message handler registration is requested."
                : nil,
            scope.exposesJSBridge
                ? "Sumi JavaScript bridge exposure is requested."
                : nil,
            scope.dispatchesRuntimeMessages
                ? "Runtime message dispatch is requested."
                : nil,
            scope.opensRuntimePorts
                ? "Runtime port opening is requested."
                : nil,
            scope.launchesNativeMessaging
                ? "Native messaging is requested."
                : nil,
            scope.launchesNativeHost
                ? "Native host launch is requested."
                : nil,
            scope.usesScheduledClockOrRepeatedChecks
                ? "Scheduled-clock or repeated observation checks are requested."
                : nil,
        ].compactMap { $0 }
    }

    private static func classification(
        strategy: ChromeMV3ContentScriptObservationStrategy,
        allowed: Bool,
        reason: String,
        risk: ChromeMV3ContentScriptObservationRiskLevel,
        basis: [String]
    ) -> ChromeMV3ContentScriptObservationStrategyClassification {
        ChromeMV3ContentScriptObservationStrategyClassification(
            strategy: strategy,
            allowedInThisPrompt: allowed,
            reason: reason,
            riskLevel: risk,
            sourceDocBasis: uniqueSorted(basis),
            productExposure: false
        )
    }
}

enum ChromeMV3ContentScriptSmokeFixtureKind:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case minimalInertNonContentScript
    case controlledInertContentScript
    case unsupported
}

enum ChromeMV3ContentScriptSmokeFixtureBlocker:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case generatedBundleMissing
    case manifestMissing
    case manifestUnreadable
    case manifestJSONInvalid
    case manifestVersionNotMV3
    case webKitObjectNotAccepted
    case detachedContextMissing
    case contentScriptsMissing
    case contentScriptsNotArray
    case contentScriptJSResourceMissing
    case contentScriptCSSPresent
    case contentScriptNotInertMarker
    case contentScriptRuntimeMessagingDetected
    case contentScriptDynamicScriptInjectionDetected
    case contentScriptRemoteResourceDetected
    case contentScriptMissingExplicitMatches
    case contentScriptBroadMatchPattern
    case contentScriptMatchPatternOutsideTestOrigins
    case hostPermissionBroadPattern
    case hostPermissionOutsideTestOrigins
    case nativeMessagingPermissionPresent
    case backgroundServiceWorkerPresent
    case actionPresent
    case optionsPagePresent
    case externallyConnectablePresent
    case extensionPageDependencyPresent
    case webAccessibleResourcesPresent
    case declarativeNetRequestPresent
    case commandsPresent
    case unsupportedRunAt
    case unsupportedWorld

    var reason: String {
        switch self {
        case .generatedBundleMissing:
            return "The generated-rewritten bundle directory is missing."
        case .manifestMissing:
            return "manifest.json is missing."
        case .manifestUnreadable:
            return "manifest.json could not be read."
        case .manifestJSONInvalid:
            return "manifest.json is not a JSON object."
        case .manifestVersionNotMV3:
            return "The content-script smoke fixture must declare manifest_version 3."
        case .webKitObjectNotAccepted:
            return "The fixture does not have an accepted WKWebExtension object."
        case .detachedContextMissing:
            return "A detached WKWebExtensionContext must exist before the smoke run."
        case .contentScriptsMissing:
            return "The fixture has no content_scripts entry and is classified as non-content-script inert."
        case .contentScriptsNotArray:
            return "content_scripts must be an array for this smoke fixture."
        case .contentScriptJSResourceMissing:
            return "Every content script must reference an existing local JavaScript marker file."
        case .contentScriptCSSPresent:
            return "CSS content scripts are outside the inert marker fixture."
        case .contentScriptNotInertMarker:
            return "Content script files must be inert marker scripts."
        case .contentScriptRuntimeMessagingDetected:
            return "The marker script appears to use runtime messaging, which is forbidden."
        case .contentScriptDynamicScriptInjectionDetected:
            return "The marker script appears to perform dynamic script injection."
        case .contentScriptRemoteResourceDetected:
            return "The marker script appears to reference remote resources."
        case .contentScriptMissingExplicitMatches:
            return "Every content script must declare explicit test-origin matches."
        case .contentScriptBroadMatchPattern:
            return "Broad content-script match patterns are blocked unless explicitly allowed for a test fixture."
        case .contentScriptMatchPatternOutsideTestOrigins:
            return "Content-script matches must stay inside explicit smoke-test origins."
        case .hostPermissionBroadPattern:
            return "Broad host permissions are blocked unless explicitly allowed for a test fixture."
        case .hostPermissionOutsideTestOrigins:
            return "Host permissions must stay inside explicit smoke-test origins."
        case .nativeMessagingPermissionPresent:
            return "nativeMessaging would open a native runtime path and is forbidden."
        case .backgroundServiceWorkerPresent:
            return "Background service workers can wake extension code and are forbidden."
        case .actionPresent:
            return "Action UI is product/runtime UI and is forbidden."
        case .optionsPagePresent:
            return "Options UI is an extension page dependency and is forbidden."
        case .externallyConnectablePresent:
            return "externally_connectable would open external runtime messaging."
        case .extensionPageDependencyPresent:
            return "Extension page dependencies are outside the content-script smoke fixture."
        case .webAccessibleResourcesPresent:
            return "web_accessible_resources expose extension resources and are non-inert."
        case .declarativeNetRequestPresent:
            return "declarative_net_request can modify browsing behavior and is non-inert."
        case .commandsPresent:
            return "Commands can dispatch extension events and are non-inert."
        case .unsupportedRunAt:
            return "run_at must be one of document_start, document_end, or document_idle."
        case .unsupportedWorld:
            return "world must be omitted, ISOLATED, or MAIN for this manifest model."
        }
    }
}

struct ChromeMV3ContentScriptSmokeFixturePolicyOptions:
    Codable,
    Equatable,
    Sendable
{
    var allowedTestOriginHosts: [String]
    var allowBroadPatternsForExplicitTestFixture: Bool

    static let `default` = ChromeMV3ContentScriptSmokeFixturePolicyOptions(
        allowedTestOriginHosts: [
            "sumi.test",
            "same.sumi.test",
            "cross.sumi.test",
        ],
        allowBroadPatternsForExplicitTestFixture: false
    )
}

struct ChromeMV3ContentScriptSmokeManifestSummary:
    Codable,
    Equatable,
    Sendable
{
    var contentScriptMetadata:
        [ChromeMV3ContentScriptSmokeManifestContentScriptMetadata]
    var contentScriptCount: Int
    var jsPaths: [String]
    var cssPaths: [String]
    var matchPatterns: [String]
    var excludeMatchPatterns: [String]
    var includeGlobs: [String]
    var excludeGlobs: [String]
    var allFramesValues: [Bool]
    var matchAboutBlankValues: [Bool]
    var matchOriginAsFallbackValues: [Bool]
    var runAtValues: [String]
    var worldValues: [String]
    var hostPermissions: [String]
    var declaredPermissions: [String]
}

struct ChromeMV3ContentScriptSmokeManifestContentScriptMetadata:
    Codable,
    Equatable,
    Sendable
{
    var contentScriptIndex: Int
    var jsPaths: [String]
    var cssPaths: [String]
    var matchPatterns: [String]
    var excludeMatchPatterns: [String]
    var includeGlobs: [String]
    var excludeGlobs: [String]
    var allFrames: Bool
    var matchAboutBlank: Bool
    var matchOriginAsFallback: Bool
    var runAt: String
    var world: String?
}

struct ChromeMV3ContentScriptSmokeScriptResource:
    Codable,
    Equatable,
    Sendable
{
    var relativePath: String
    var exists: Bool
    var byteCount: Int
    var markerTokenPresent: Bool
    var inertMarker: Bool
    var runtimeMessagingDetected: Bool
    var dynamicScriptInjectionDetected: Bool
    var remoteResourceDetected: Bool
    var warnings: [String]
}

struct ChromeMV3ContentScriptSmokeFixturePolicyResult:
    Codable,
    Equatable,
    Sendable
{
    var generatedRewrittenRootPath: String
    var manifestPath: String
    var manifestReadStatus: ChromeMV3RuntimeBridgeManifestReadStatus
    var manifestVersion: Int?
    var acceptedWebExtensionObjectAvailable: Bool
    var detachedContextCreated: Bool
    var fixtureKind: ChromeMV3ContentScriptSmokeFixtureKind
    var manifestSummary: ChromeMV3ContentScriptSmokeManifestSummary
    var scriptResources: [ChromeMV3ContentScriptSmokeScriptResource]
    var loadSafeForContentScriptSmokeFixture: Bool
    var blockers: [ChromeMV3ContentScriptSmokeFixtureBlocker]
    var blockingReasons: [String]
    var warnings: [String]
}

enum ChromeMV3ContentScriptSmokeFixturePolicy {
    static let markerToken =
        "sumiChromeMV3ContentScriptSmokeMarker"

    static func evaluate(
        generatedRewrittenRootPath rootPath: String,
        acceptedWebExtensionObjectAvailable: Bool,
        detachedContextCreated: Bool,
        options: ChromeMV3ContentScriptSmokeFixturePolicyOptions = .default,
        fileManager: FileManager = .default
    ) -> ChromeMV3ContentScriptSmokeFixturePolicyResult {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            .standardizedFileURL
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        var blockers: [ChromeMV3ContentScriptSmokeFixtureBlocker] = []
        var warnings: [String] = []

        if directoryExists(rootURL, fileManager: fileManager) == false {
            blockers.append(.generatedBundleMissing)
        }
        if acceptedWebExtensionObjectAvailable == false {
            blockers.append(.webKitObjectNotAccepted)
        }
        if detachedContextCreated == false {
            blockers.append(.detachedContextMissing)
        }

        let manifestObject: [String: Any]
        let manifestReadStatus: ChromeMV3RuntimeBridgeManifestReadStatus
        if fileManager.fileExists(atPath: manifestURL.path) == false {
            blockers.append(.manifestMissing)
            manifestObject = [:]
            manifestReadStatus = .missing
        } else {
            do {
                let data = try Data(contentsOf: manifestURL)
                if let object = try JSONSerialization.jsonObject(
                    with: data
                ) as? [String: Any] {
                    manifestObject = object
                    manifestReadStatus = .loaded
                } else {
                    blockers.append(.manifestJSONInvalid)
                    manifestObject = [:]
                    manifestReadStatus = .corrupt
                }
            } catch is DecodingError {
                blockers.append(.manifestJSONInvalid)
                manifestObject = [:]
                manifestReadStatus = .corrupt
            } catch {
                blockers.append(.manifestUnreadable)
                manifestObject = [:]
                manifestReadStatus = .unreadable
            }
        }

        let manifestVersion = intValue(manifestObject["manifest_version"])
        if manifestReadStatus == .loaded, manifestVersion != 3 {
            blockers.append(.manifestVersionNotMV3)
        }

        if manifestObject.keys.contains("content_scripts"),
           (manifestObject["content_scripts"] as? [[String: Any]]) == nil
        {
            blockers.append(.contentScriptsNotArray)
        }

        let contentScripts =
            manifestObject["content_scripts"] as? [[String: Any]] ?? []
        if contentScripts.isEmpty {
            blockers.append(.contentScriptsMissing)
        }

        let declaredPermissions = stringArray(manifestObject["permissions"])
        let optionalPermissions =
            stringArray(manifestObject["optional_permissions"])
        let hostPermissions = stringArray(manifestObject["host_permissions"])
        let optionalHostPermissions =
            stringArray(manifestObject["optional_host_permissions"])
        let background = dictionaryValue(manifestObject["background"])
        let action = dictionaryValue(manifestObject["action"])
        let optionsPage = stringValue(manifestObject["options_page"])
            ?? stringValue(dictionaryValue(manifestObject["options_ui"])?["page"])

        if declaredPermissions.contains("nativeMessaging")
            || optionalPermissions.contains("nativeMessaging")
        {
            blockers.append(.nativeMessagingPermissionPresent)
        }
        if stringValue(background?["service_worker"])?.isEmpty == false {
            blockers.append(.backgroundServiceWorkerPresent)
        }
        if action != nil {
            blockers.append(.actionPresent)
        }
        if optionsPage?.isEmpty == false {
            blockers.append(.optionsPagePresent)
        }
        if manifestObject["externally_connectable"] != nil {
            blockers.append(.externallyConnectablePresent)
        }
        if manifestObject["devtools_page"] != nil
            || manifestObject["side_panel"] != nil
            || manifestObject["chrome_url_overrides"] != nil
        {
            blockers.append(.extensionPageDependencyPresent)
        }
        if manifestObject["web_accessible_resources"] != nil {
            blockers.append(.webAccessibleResourcesPresent)
        }
        if manifestObject["declarative_net_request"] != nil {
            blockers.append(.declarativeNetRequestPresent)
        }
        if manifestObject["commands"] != nil {
            blockers.append(.commandsPresent)
        }

        for permission in hostPermissions + optionalHostPermissions {
            if isBroadPattern(permission) {
                blockers.append(.hostPermissionBroadPattern)
            } else if isAllowedTestPattern(permission, options: options) == false {
                blockers.append(.hostPermissionOutsideTestOrigins)
            }
        }

        var scriptResources: [ChromeMV3ContentScriptSmokeScriptResource] = []
        var jsPaths: [String] = []
        var cssPaths: [String] = []
        var matches: [String] = []
        var excludeMatches: [String] = []
        var includeGlobs: [String] = []
        var excludeGlobs: [String] = []
        var allFramesValues: [Bool] = []
        var matchAboutBlankValues: [Bool] = []
        var matchOriginAsFallbackValues: [Bool] = []
        var runAtValues: [String] = []
        var worldValues: [String] = []
        var contentScriptMetadata:
            [ChromeMV3ContentScriptSmokeManifestContentScriptMetadata] = []

        for (index, script) in contentScripts.enumerated() {
            let scriptMatches = stringArray(script["matches"])
            if scriptMatches.isEmpty {
                blockers.append(.contentScriptMissingExplicitMatches)
            }
            for match in scriptMatches {
                if isBroadPattern(match),
                   options.allowBroadPatternsForExplicitTestFixture == false {
                    blockers.append(.contentScriptBroadMatchPattern)
                } else if isAllowedTestPattern(match, options: options) == false,
                          isBroadPattern(match) == false {
                    blockers.append(.contentScriptMatchPatternOutsideTestOrigins)
                }
            }

            let runAt = stringValue(script["run_at"]) ?? "document_idle"
            if ["document_start", "document_end", "document_idle"]
                .contains(runAt) == false {
                blockers.append(.unsupportedRunAt)
            }
            if let world = stringValue(script["world"]),
               ["ISOLATED", "MAIN"].contains(world) == false {
                blockers.append(.unsupportedWorld)
            }

            let js = stringArray(script["js"])
            let css = stringArray(script["css"])
            let scriptExcludeMatches = stringArray(script["exclude_matches"])
            let scriptIncludeGlobs = stringArray(script["include_globs"])
            let scriptExcludeGlobs = stringArray(script["exclude_globs"])
            let scriptAllFrames = boolValue(script["all_frames"]) ?? false
            let scriptMatchAboutBlank =
                boolValue(script["match_about_blank"]) ?? false
            let scriptMatchOriginAsFallback =
                boolValue(script["match_origin_as_fallback"]) ?? false
            let scriptWorld = stringValue(script["world"])
            if css.isEmpty == false {
                blockers.append(.contentScriptCSSPresent)
            }
            for path in js {
                let resource = inspectScriptResource(
                    relativePath: path,
                    rootURL: rootURL,
                    fileManager: fileManager
                )
                scriptResources.append(resource)
                if resource.exists == false {
                    blockers.append(.contentScriptJSResourceMissing)
                }
                if resource.inertMarker == false {
                    blockers.append(.contentScriptNotInertMarker)
                }
                if resource.runtimeMessagingDetected {
                    blockers.append(.contentScriptRuntimeMessagingDetected)
                }
                if resource.dynamicScriptInjectionDetected {
                    blockers.append(.contentScriptDynamicScriptInjectionDetected)
                }
                if resource.remoteResourceDetected {
                    blockers.append(.contentScriptRemoteResourceDetected)
                }
            }

            jsPaths.append(contentsOf: js)
            cssPaths.append(contentsOf: css)
            matches.append(contentsOf: scriptMatches)
            excludeMatches.append(contentsOf: scriptExcludeMatches)
            includeGlobs.append(contentsOf: scriptIncludeGlobs)
            excludeGlobs.append(contentsOf: scriptExcludeGlobs)
            allFramesValues.append(scriptAllFrames)
            matchAboutBlankValues.append(scriptMatchAboutBlank)
            matchOriginAsFallbackValues.append(scriptMatchOriginAsFallback)
            runAtValues.append(runAt)
            if let world = scriptWorld {
                worldValues.append(world)
            }
            contentScriptMetadata.append(
                ChromeMV3ContentScriptSmokeManifestContentScriptMetadata(
                    contentScriptIndex: index,
                    jsPaths: uniqueSorted(js),
                    cssPaths: uniqueSorted(css),
                    matchPatterns: uniqueSorted(scriptMatches),
                    excludeMatchPatterns: uniqueSorted(scriptExcludeMatches),
                    includeGlobs: uniqueSorted(scriptIncludeGlobs),
                    excludeGlobs: uniqueSorted(scriptExcludeGlobs),
                    allFrames: scriptAllFrames,
                    matchAboutBlank: scriptMatchAboutBlank,
                    matchOriginAsFallback: scriptMatchOriginAsFallback,
                    runAt: runAt,
                    world: scriptWorld
                )
            )
        }

        warnings.append(
            "Only DEBUG/internal inert marker content scripts for explicit smoke-test origins are eligible."
        )
        warnings.append(
            "The fixture policy does not expose chrome.runtime, native messaging, product UI, or normal-tab attachment."
        )

        let uniqueBlockers = Array(Set(blockers)).sorted {
            $0.rawValue < $1.rawValue
        }
        let fixtureKind: ChromeMV3ContentScriptSmokeFixtureKind
        if contentScripts.isEmpty {
            fixtureKind = .minimalInertNonContentScript
        } else if uniqueBlockers.isEmpty {
            fixtureKind = .controlledInertContentScript
        } else {
            fixtureKind = .unsupported
        }

        return ChromeMV3ContentScriptSmokeFixturePolicyResult(
            generatedRewrittenRootPath: rootURL.path,
            manifestPath: manifestURL.path,
            manifestReadStatus: manifestReadStatus,
            manifestVersion: manifestVersion,
            acceptedWebExtensionObjectAvailable:
                acceptedWebExtensionObjectAvailable,
            detachedContextCreated: detachedContextCreated,
            fixtureKind: fixtureKind,
            manifestSummary:
                ChromeMV3ContentScriptSmokeManifestSummary(
                    contentScriptMetadata:
                        contentScriptMetadata.sorted {
                            $0.contentScriptIndex
                                < $1.contentScriptIndex
                        },
                    contentScriptCount: contentScripts.count,
                    jsPaths: uniqueSorted(jsPaths),
                    cssPaths: uniqueSorted(cssPaths),
                    matchPatterns: uniqueSorted(matches),
                    excludeMatchPatterns: uniqueSorted(excludeMatches),
                    includeGlobs: uniqueSorted(includeGlobs),
                    excludeGlobs: uniqueSorted(excludeGlobs),
                    allFramesValues: uniqueSorted(allFramesValues),
                    matchAboutBlankValues:
                        uniqueSorted(matchAboutBlankValues),
                    matchOriginAsFallbackValues:
                        uniqueSorted(matchOriginAsFallbackValues),
                    runAtValues: uniqueSorted(runAtValues),
                    worldValues: uniqueSorted(worldValues),
                    hostPermissions: uniqueSorted(hostPermissions),
                    declaredPermissions: uniqueSorted(declaredPermissions)
                ),
            scriptResources: scriptResources.sorted {
                $0.relativePath < $1.relativePath
            },
            loadSafeForContentScriptSmokeFixture:
                uniqueBlockers.isEmpty && contentScripts.isEmpty == false,
            blockers: uniqueBlockers,
            blockingReasons: uniqueSorted(uniqueBlockers.map(\.reason)),
            warnings: uniqueSorted(warnings)
        )
    }

    static var inertMarkerScriptSource: String {
        """
        (() => {
          const marker = "sumiChromeMV3ContentScriptSmokeMarker";
          const root = document.documentElement;
          if (!root) { return; }
          const frame = window.top === window ? "top" : "frame";
          const existing = root.getAttribute("data-sumi-mv3-content-script-smoke") || "";
          root.setAttribute("data-sumi-mv3-content-script-smoke", existing ? existing + "," + frame : frame);
          root.setAttribute("data-sumi-mv3-content-script-smoke-marker", marker);
        })();

        """
    }

    static func manifest(
        matches: [String] = ["https://sumi.test/*"],
        allFrames: Bool = false,
        matchAboutBlank: Bool = false,
        matchOriginAsFallback: Bool = false,
        runAt: String = "document_idle",
        world: String? = "ISOLATED"
    ) -> [String: Any] {
        var contentScript: [String: Any] = [
            "matches": matches,
            "js": ["content-smoke-marker.js"],
            "all_frames": allFrames,
            "match_about_blank": matchAboutBlank,
            "match_origin_as_fallback": matchOriginAsFallback,
            "run_at": runAt,
        ]
        if let world {
            contentScript["world"] = world
        }
        return [
            "manifest_version": 3,
            "name": "Sumi Content Script Smoke",
            "version": "1.0.0",
            "content_scripts": [contentScript],
        ]
    }

    private static func inspectScriptResource(
        relativePath: String,
        rootURL: URL,
        fileManager: FileManager
    ) -> ChromeMV3ContentScriptSmokeScriptResource {
        let warnings: [String]
        let url = rootURL.appendingPathComponent(relativePath)
            .standardizedFileURL
        guard url.path.hasPrefix(rootURL.path + "/"),
              fileManager.fileExists(atPath: url.path)
        else {
            return ChromeMV3ContentScriptSmokeScriptResource(
                relativePath: relativePath,
                exists: false,
                byteCount: 0,
                markerTokenPresent: false,
                inertMarker: false,
                runtimeMessagingDetected: false,
                dynamicScriptInjectionDetected: false,
                remoteResourceDetected: false,
                warnings: ["Script resource is missing or escapes the bundle root."]
            )
        }

        let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let lower = contents.lowercased()
        let runtimeMessagingDetected =
            lower.contains("chrome.runtime")
                || lower.contains("browser.runtime")
                || lower.contains("sendmessage")
                || lower.contains("runtime.connect")
                || lower.contains("postmessage")
                || lower.contains("connect" + "native")
        let dynamicScriptInjectionDetected =
            lower.contains("executescript")
                || lower.contains("createelement('script")
                || lower.contains("createelement(\"script")
                || lower.contains("appendchild(script")
                || lower.contains("eval(")
                || lower.contains("function(")
        let remoteResourceDetected =
            lower.contains("https://")
                || lower.contains("http://")
                || lower.contains("fetch(")
                || lower.contains("xmlhttprequest")
                || lower.contains("import(")
        let markerTokenPresent = contents.contains(markerToken)
        let inertMarker = markerTokenPresent
            && runtimeMessagingDetected == false
            && dynamicScriptInjectionDetected == false
            && remoteResourceDetected == false
        warnings = inertMarker
            ? []
            : ["Only the inert marker script shape is accepted."]

        return ChromeMV3ContentScriptSmokeScriptResource(
            relativePath: relativePath,
            exists: true,
            byteCount: Data(contents.utf8).count,
            markerTokenPresent: markerTokenPresent,
            inertMarker: inertMarker,
            runtimeMessagingDetected: runtimeMessagingDetected,
            dynamicScriptInjectionDetected: dynamicScriptInjectionDetected,
            remoteResourceDetected: remoteResourceDetected,
            warnings: warnings
        )
    }

    private static func directoryExists(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}

enum ChromeMV3ContentScriptFrameKind:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case topFrame
    case sameOriginIframe
    case crossOriginIframe
    case aboutBlankIframe
    case dataIframe
    case blobIframe
}

enum ChromeMV3ContentScriptFrameExpectation:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case eligible
    case blocked
    case unsupportedNeedsVerification
}

struct ChromeMV3ContentScriptFrameScenario:
    Codable,
    Equatable,
    Sendable
{
    var frameID: String
    var kind: ChromeMV3ContentScriptFrameKind
    var urlString: String
    var parentURLString: String?
    var safeToInstantiateWithoutNetwork: Bool
    var fixtureElementID: String?
    var safeToObserveWithTestDOMInspection: Bool
    var syntheticFixtureDiagnostic: String?
}

struct ChromeMV3ContentScriptFrameObservationBlockers:
    Codable,
    Equatable,
    Sendable
{
    var blockedByWebKitBehavior: Bool
    var blockedByCurrentSDKShape: Bool
    var blockedByUnsafeObservationMechanism: Bool
    var needsManualWebKitVerification: Bool
    var diagnostics: [String]

    static let none = ChromeMV3ContentScriptFrameObservationBlockers(
        blockedByWebKitBehavior: false,
        blockedByCurrentSDKShape: false,
        blockedByUnsafeObservationMechanism: false,
        needsManualWebKitVerification: false,
        diagnostics: []
    )

    var hasBlockingObservationConstraint: Bool {
        blockedByWebKitBehavior
            || blockedByCurrentSDKShape
            || blockedByUnsafeObservationMechanism
    }
}

struct ChromeMV3ContentScriptFrameDecision:
    Codable,
    Equatable,
    Sendable
{
    var frameID: String
    var kind: ChromeMV3ContentScriptFrameKind
    var urlString: String
    var expected: ChromeMV3ContentScriptFrameExpectation
    var reason: String
    var runAt: String
    var world: String?
    var allFrames: Bool
    var matchAboutBlank: Bool
    var matchOriginAsFallback: Bool
    var safeToObserveWithTestDOMInspection: Bool
    var observationBlockers:
        ChromeMV3ContentScriptFrameObservationBlockers
}

struct ChromeMV3ContentScriptFrameMatrixResult:
    Codable,
    Equatable,
    Sendable
{
    var scenarioID: String
    var expectedEligibleFrames: [ChromeMV3ContentScriptFrameDecision]
    var expectedBlockedFrames: [ChromeMV3ContentScriptFrameDecision]
    var unsupportedOrNeedsVerificationFrames:
        [ChromeMV3ContentScriptFrameDecision]
    var allDecisions: [ChromeMV3ContentScriptFrameDecision]
    var frameScenarios: [ChromeMV3ContentScriptFrameScenario]
}

enum ChromeMV3ContentScriptFrameMatrix {
    static let defaultScenarios: [ChromeMV3ContentScriptFrameScenario] = [
        ChromeMV3ContentScriptFrameScenario(
            frameID: "top",
            kind: .topFrame,
            urlString: "https://sumi.test/index.html",
            parentURLString: nil,
            safeToInstantiateWithoutNetwork: true,
            fixtureElementID: nil,
            safeToObserveWithTestDOMInspection: true,
            syntheticFixtureDiagnostic: nil
        ),
        ChromeMV3ContentScriptFrameScenario(
            frameID: "same-origin",
            kind: .sameOriginIframe,
            urlString: "https://sumi.test/frame.html",
            parentURLString: "https://sumi.test/index.html",
            safeToInstantiateWithoutNetwork: false,
            fixtureElementID: "same-origin-frame",
            safeToObserveWithTestDOMInspection: false,
            syntheticFixtureDiagnostic:
                "No public WKWebView API in this harness serves deterministic http(s) subframe URLs without network; srcdoc/about:blank would exercise a different frame-matching path."
        ),
        ChromeMV3ContentScriptFrameScenario(
            frameID: "cross-origin",
            kind: .crossOriginIframe,
            urlString: "https://cross.sumi.test/frame.html",
            parentURLString: "https://sumi.test/index.html",
            safeToInstantiateWithoutNetwork: false,
            fixtureElementID: "cross-origin-frame",
            safeToObserveWithTestDOMInspection: false,
            syntheticFixtureDiagnostic:
                "No no-network deterministic cross-origin http(s) iframe fixture is installed; top-page DOM inspection cannot safely read a real cross-origin frame."
        ),
        ChromeMV3ContentScriptFrameScenario(
            frameID: "about-blank",
            kind: .aboutBlankIframe,
            urlString: "about:blank",
            parentURLString: "https://sumi.test/index.html",
            safeToInstantiateWithoutNetwork: true,
            fixtureElementID: "about-blank-frame",
            safeToObserveWithTestDOMInspection: true,
            syntheticFixtureDiagnostic: nil
        ),
        ChromeMV3ContentScriptFrameScenario(
            frameID: "data",
            kind: .dataIframe,
            urlString: "data:text/html,%3C!doctype%20html%3E",
            parentURLString: "https://sumi.test/index.html",
            safeToInstantiateWithoutNetwork: true,
            fixtureElementID: "data-frame",
            safeToObserveWithTestDOMInspection: false,
            syntheticFixtureDiagnostic:
                "A data: frame is deterministic and network-free, but page-world top-frame DOM inspection cannot safely read opaque-origin frame DOM."
        ),
        ChromeMV3ContentScriptFrameScenario(
            frameID: "blob",
            kind: .blobIframe,
            urlString: "blob:https://sumi.test/synthetic",
            parentURLString: "https://sumi.test/index.html",
            safeToInstantiateWithoutNetwork: true,
            fixtureElementID: "blob-frame",
            safeToObserveWithTestDOMInspection: true,
            syntheticFixtureDiagnostic:
                "A same-origin blob: frame can be generated by deterministic synthetic HTML; exact WebKit initiator-origin behavior still needs marker observation."
        ),
    ]

    static func evaluate(
        scenarioID: String,
        manifestSummary: ChromeMV3ContentScriptSmokeManifestSummary,
        scenarios: [ChromeMV3ContentScriptFrameScenario] = defaultScenarios
    ) -> ChromeMV3ContentScriptFrameMatrixResult {
        let decisions = scenarios.map {
            decision(
                frame: $0,
                manifestSummary: manifestSummary
            )
        }.sorted { $0.frameID < $1.frameID }
        return ChromeMV3ContentScriptFrameMatrixResult(
            scenarioID: scenarioID,
            expectedEligibleFrames:
                decisions.filter { $0.expected == .eligible },
            expectedBlockedFrames:
                decisions.filter { $0.expected == .blocked },
            unsupportedOrNeedsVerificationFrames:
                decisions.filter {
                    $0.expected == .unsupportedNeedsVerification
                },
            allDecisions: decisions,
            frameScenarios: scenarios.sorted { $0.frameID < $1.frameID }
        )
    }

    private static func decision(
        frame: ChromeMV3ContentScriptFrameScenario,
        manifestSummary: ChromeMV3ContentScriptSmokeManifestSummary
    ) -> ChromeMV3ContentScriptFrameDecision {
        let allFrames = manifestSummary.allFramesValues.contains(true)
        let matchAboutBlank =
            manifestSummary.matchAboutBlankValues.contains(true)
        let matchOriginAsFallback =
            manifestSummary.matchOriginAsFallbackValues.contains(true)
        let runAt = manifestSummary.runAtValues.first ?? "document_idle"
        let world = manifestSummary.worldValues.first
        let directMatch = manifestSummary.matchPatterns.contains {
            matches(pattern: $0, urlString: frame.urlString)
        }
        let parentMatch = frame.parentURLString.map { parent in
            manifestSummary.matchPatterns.contains {
                matches(pattern: $0, urlString: parent)
            }
        } ?? false

        let expected: ChromeMV3ContentScriptFrameExpectation
        let reason: String
        let observationBlockers: ChromeMV3ContentScriptFrameObservationBlockers
        switch frame.kind {
        case .topFrame:
            expected = directMatch ? .eligible : .blocked
            reason = directMatch
                ? "Top frame URL matches the content_scripts matches list."
                : "Top frame URL does not match the content_scripts matches list."
            observationBlockers = .none
        case .sameOriginIframe:
            if allFrames && directMatch {
                expected = .eligible
                reason = "all_frames is true and the same-origin iframe URL matches; execution is eligible, but the no-network fixture cannot instantiate that http(s) subframe URL."
                observationBlockers = blockers(
                    currentSDK: true,
                    unsafe: false,
                    manual: true,
                    diagnostics: [
                        frame.syntheticFixtureDiagnostic,
                        "A deterministic same-origin http(s) iframe would require local request interception outside the current safe fixture shape.",
                    ]
                )
            } else if allFrames {
                expected = .blocked
                reason = "all_frames is true, but the same-origin iframe URL does not match."
                observationBlockers = .none
            } else {
                expected = .blocked
                reason = "all_frames is false, so matching is top-frame only."
                observationBlockers = .none
            }
        case .crossOriginIframe:
            if allFrames && directMatch {
                expected = .eligible
                reason = "all_frames is true and the cross-origin iframe URL matches; observation is blocked without a deterministic no-network cross-origin subframe fixture."
                observationBlockers = blockers(
                    currentSDK: frame.safeToInstantiateWithoutNetwork == false,
                    unsafe: true,
                    manual: true,
                    diagnostics: [
                        frame.syntheticFixtureDiagnostic,
                        "Reading a real cross-origin iframe from the top page would require an unsafe observation mechanism or a frame-specific WebKit verification path not installed here.",
                    ]
                )
            } else if allFrames {
                expected = .blocked
                reason = "all_frames is true, but the cross-origin iframe URL does not match."
                observationBlockers = .none
            } else {
                expected = .blocked
                reason = "all_frames is false, so matching is top-frame only."
                observationBlockers = .none
            }
        case .aboutBlankIframe:
            if allFrames && matchOriginAsFallback && parentMatch {
                expected = .eligible
                reason = "match_origin_as_fallback is true, takes priority over match_about_blank, and the initiator parent frame matches."
                observationBlockers = .none
            } else if allFrames && matchAboutBlank && parentMatch {
                expected = .eligible
                reason = "match_about_blank is true and the parent frame matches."
                observationBlockers = .none
            } else {
                expected = .blocked
                reason = "about:blank requires all_frames plus match_about_blank or match_origin_as_fallback with a matching parent frame."
                observationBlockers = .none
            }
        case .dataIframe:
            if allFrames && matchOriginAsFallback && parentMatch {
                expected = .eligible
                reason = "match_origin_as_fallback maps this data: frame to the initiator origin; top-page DOM inspection cannot safely observe the opaque-origin frame."
                observationBlockers = blockers(
                    webKit: true,
                    unsafe: true,
                    manual: true,
                    diagnostics: [
                        frame.syntheticFixtureDiagnostic,
                        "Chrome documents initiator-origin matching for data: frames; WebKit-owned behavior needs manual verification or a safe frame-targeted inspection path.",
                    ]
                )
            } else {
                expected = .blocked
                reason = "Opaque-origin frames require match_origin_as_fallback and a matching initiator origin."
                observationBlockers = .none
            }
        case .blobIframe:
            if allFrames && matchOriginAsFallback && parentMatch {
                expected = .eligible
                reason = "match_origin_as_fallback maps this blob: frame to the initiator origin; the fixture can instantiate it without network."
                observationBlockers = .none
            } else {
                expected = .blocked
                reason = "blob: frames require match_origin_as_fallback and a matching initiator origin."
                observationBlockers = .none
            }
        }

        return ChromeMV3ContentScriptFrameDecision(
            frameID: frame.frameID,
            kind: frame.kind,
            urlString: frame.urlString,
            expected: expected,
            reason: reason,
            runAt: runAt,
            world: world,
            allFrames: allFrames,
            matchAboutBlank: matchAboutBlank,
            matchOriginAsFallback: matchOriginAsFallback,
            safeToObserveWithTestDOMInspection:
                frame.safeToObserveWithTestDOMInspection
                    && observationBlockers
                    .hasBlockingObservationConstraint == false,
            observationBlockers: observationBlockers
        )
    }

    private static func blockers(
        webKit: Bool = false,
        currentSDK: Bool = false,
        unsafe: Bool = false,
        manual: Bool = false,
        diagnostics: [String?]
    ) -> ChromeMV3ContentScriptFrameObservationBlockers {
        ChromeMV3ContentScriptFrameObservationBlockers(
            blockedByWebKitBehavior: webKit,
            blockedByCurrentSDKShape: currentSDK,
            blockedByUnsafeObservationMechanism: unsafe,
            needsManualWebKitVerification: manual,
            diagnostics: uniqueSorted(diagnostics.compactMap { $0 })
        )
    }

    static func matches(pattern: String, urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host,
              let scheme = url.scheme,
              let parsedPattern = parseMatchPattern(pattern)
        else {
            return false
        }

        let schemeMatches = parsedPattern.scheme == "*"
            || parsedPattern.scheme == scheme
        let hostMatches = parsedPattern.host == "*"
            || parsedPattern.host == host
            || (parsedPattern.host.hasPrefix("*.") &&
                host.hasSuffix(String(parsedPattern.host.dropFirst(1))))
        let path = url.path.isEmpty ? "/" : url.path
        let pathMatches = parsedPattern.path == "/*"
            || parsedPattern.path == "*"
            || path.hasPrefix(
                parsedPattern.path.replacingOccurrences(of: "*", with: "")
            )

        return schemeMatches && hostMatches && pathMatches
    }
}

struct ChromeMV3ContentScriptSyntheticFrameHTML:
    Codable,
    Equatable,
    Sendable
{
    var frameID: String
    var kind: ChromeMV3ContentScriptFrameKind
    var html: String
    var includedInTopHTML: Bool
    var blockedReason: String?
}

struct ChromeMV3ContentScriptSyntheticHTMLFixture:
    Codable,
    Equatable,
    Sendable
{
    var topURLString: String
    var topHTML: String
    var frames: [ChromeMV3ContentScriptSyntheticFrameHTML]
    var networkDependency: Bool
    var productTabRequired: Bool
    var userVisibleWindowRequired: Bool

    static func generate(
        matrix: ChromeMV3ContentScriptFrameMatrixResult
    ) -> ChromeMV3ContentScriptSyntheticHTMLFixture {
        let frames = matrix.allDecisions.map { decision -> ChromeMV3ContentScriptSyntheticFrameHTML in
            switch decision.kind {
            case .sameOriginIframe:
                return ChromeMV3ContentScriptSyntheticFrameHTML(
                    frameID: decision.frameID,
                    kind: decision.kind,
                    html: "",
                    includedInTopHTML: false,
                    blockedReason:
                        "Same-origin http(s) iframe URL execution is matrix-modeled but not instantiated because the safe synthetic fixture has no network-free http(s) subframe server."
                )
            case .aboutBlankIframe:
                return ChromeMV3ContentScriptSyntheticFrameHTML(
                    frameID: decision.frameID,
                    kind: decision.kind,
                    html: "",
                    includedInTopHTML: true,
                    blockedReason: nil
                )
            case .dataIframe:
                return ChromeMV3ContentScriptSyntheticFrameHTML(
                    frameID: decision.frameID,
                    kind: decision.kind,
                    html: "<!doctype html><html><body><main id=\"data-frame\"></main></body></html>",
                    includedInTopHTML: true,
                    blockedReason: nil
                )
            case .topFrame:
                return ChromeMV3ContentScriptSyntheticFrameHTML(
                    frameID: decision.frameID,
                    kind: decision.kind,
                    html: "",
                    includedInTopHTML: true,
                    blockedReason: nil
                )
            case .crossOriginIframe, .blobIframe:
                return ChromeMV3ContentScriptSyntheticFrameHTML(
                    frameID: decision.frameID,
                    kind: decision.kind,
                    html: decision.kind == .blobIframe
                        ? "<!doctype html><html><body><main id=\"blob-frame-marker\"></main></body></html>"
                        : "",
                    includedInTopHTML: decision.kind == .blobIframe,
                    blockedReason:
                        decision.kind == .blobIframe
                            ? nil
                            : "Cross-origin http(s) iframe URL execution is matrix-modeled but not instantiated because the safe synthetic fixture has no network-free cross-origin subframe server."
                )
            }
        }

        let html = """
        <!doctype html>
        <html>
        <head><meta charset="utf-8"><title>Sumi MV3 Content Script Smoke</title></head>
        <body>
          <main id="top-frame-marker"></main>
          <iframe id="same-origin-frame" data-sumi-fixture-blocked="no-network-same-origin-http-subframe"></iframe>
          <iframe id="cross-origin-frame" data-sumi-fixture-blocked="no-network-cross-origin-http-subframe"></iframe>
          <iframe id="about-blank-frame"></iframe>
          <iframe id="data-frame" src="data:text/html,%3C!doctype%20html%3E%3Chtml%3E%3Cbody%3E%3Cmain%20id%3D%22data-frame-marker%22%3E%3C%2Fmain%3E%3C%2Fbody%3E%3C%2Fhtml%3E"></iframe>
          <iframe id="blob-frame"></iframe>
          <script>
          (() => {
            const frame = document.getElementById("blob-frame");
            if (!frame) { return; }
            const html = "<!doctype html><html><body><main id='blob-frame-marker'></main></body></html>";
            const url = URL.createObjectURL(new Blob([html], { type: "text/html" }));
            frame.setAttribute("data-sumi-blob-frame-url-created", "true");
            frame.src = url;
          })();
          </script>
        </body>
        </html>

        """

        return ChromeMV3ContentScriptSyntheticHTMLFixture(
            topURLString: "https://sumi.test/index.html",
            topHTML: html,
            frames: frames.sorted { $0.frameID < $1.frameID },
            networkDependency: false,
            productTabRequired: false,
            userVisibleWindowRequired: false
        )
    }
}

struct ChromeMV3ContentScriptMarkerFixtureFacts:
    Codable,
    Equatable,
    Sendable
{
    var markerToken: String
    var markerAttributeName: String
    var markerTokenAttributeName: String
    var deterministic: Bool
    var runtimeMessaging: Bool
    var serviceWorkerWake: Bool
    var externalResources: Bool
    var nativeMessaging: Bool
    var dynamicCodeExecution: Bool
    var pageVisibleDOMMarkerExpected: Bool
    var pageVisibleDOMMarkerBasis: [String]

    static let inertMarker =
        ChromeMV3ContentScriptMarkerFixtureFacts(
            markerToken:
                ChromeMV3ContentScriptSmokeFixturePolicy.markerToken,
            markerAttributeName:
                "data-sumi-mv3-content-script-smoke",
            markerTokenAttributeName:
                "data-sumi-mv3-content-script-smoke-marker",
            deterministic: true,
            runtimeMessaging: false,
            serviceWorkerWake: false,
            externalResources: false,
            nativeMessaging: false,
            dynamicCodeExecution: false,
            pageVisibleDOMMarkerExpected: true,
            pageVisibleDOMMarkerBasis: [
                "The marker writes only static DOM attributes on document.documentElement.",
                "Chrome documentation states content scripts can read and modify the DOM and isolated worlds share page DOM access.",
                "Local WebKit headers state DOM changes are visible to script in all content worlds.",
            ]
        )
}

struct ChromeMV3ContentScriptRunAtClassification:
    Codable,
    Equatable,
    Sendable
{
    var runAt: String
    var observedMarkerAfterLoad: Bool
    var exactRunAtTiming: String
    var reason: String
    var sourceDocBasis: [String]

    static func classify(
        runAt: String,
        observedMarkerAfterLoad: Bool
    ) -> ChromeMV3ContentScriptRunAtClassification {
        ChromeMV3ContentScriptRunAtClassification(
            runAt: runAt,
            observedMarkerAfterLoad: observedMarkerAfterLoad,
            exactRunAtTiming: "unverified",
            reason:
                "The smoke reads DOM marker state only after synthetic navigation completion; it does not observe exact \(runAt) scheduling without adding forbidden hooks or repeated checks.",
            sourceDocBasis: [
                "Chrome documents document_start, document_end, and document_idle timing, but this harness records only observedMarkerAfterLoad.",
                "WKWebView.evaluateJavaScript default evaluation targets the main frame in pageWorld and is used only after navigation completion.",
            ]
        )
    }
}

struct ChromeMV3ContentScriptWorldBehaviorClassification:
    Codable,
    Equatable,
    Sendable
{
    var declaredWorld: String?
    var effectiveWorld: String
    var supportedByCurrentModel: Bool
    var pageVisibleDOMMarkerExpected: Bool
    var testDOMInspectionCanSeeMarker: Bool
    var exactWorldExecutionVerified: Bool
    var reason: String
    var sourceDocBasis: [String]

    static func classify(
        declaredWorld: String?,
        markerFacts: ChromeMV3ContentScriptMarkerFixtureFacts = .inertMarker
    ) -> ChromeMV3ContentScriptWorldBehaviorClassification {
        let effectiveWorld = declaredWorld ?? "ISOLATED"
        let supported = ["ISOLATED", "MAIN"].contains(effectiveWorld)
        return ChromeMV3ContentScriptWorldBehaviorClassification(
            declaredWorld: declaredWorld,
            effectiveWorld: effectiveWorld,
            supportedByCurrentModel: supported,
            pageVisibleDOMMarkerExpected:
                supported && markerFacts.pageVisibleDOMMarkerExpected,
            testDOMInspectionCanSeeMarker:
                supported && markerFacts.pageVisibleDOMMarkerExpected,
            exactWorldExecutionVerified: false,
            reason:
                supported
                    ? "The marker uses DOM attributes, so page-world testDOMInspection can see the DOM effect; the harness does not prove whether WebKit executed the content script in \(effectiveWorld) world."
                    : "The current manifest model supports omitted world, ISOLATED, and MAIN only.",
            sourceDocBasis: [
                "Chrome documents ISOLATED as the default content-script world and MAIN as the page-shared world.",
                "Chrome documents that isolated content scripts share DOM access with the page.",
                "Local WebKit headers state DOM changes are visible to script executing in all WKContentWorlds.",
            ]
        )
    }
}

enum ChromeMV3ContentScriptFrameMarkerObservationState:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case observed
    case notObserved
    case unverified
    case blocked
}

struct ChromeMV3ContentScriptFrameMarkerObservation:
    Codable,
    Equatable,
    Sendable
{
    var frameID: String
    var kind: ChromeMV3ContentScriptFrameKind
    var expectedEligibility: ChromeMV3ContentScriptFrameExpectation
    var observedMarker: ChromeMV3ContentScriptFrameMarkerObservationState
    var markerAttributeValue: String?
    var markerTokenValue: String?
    var reason: String
    var observationStrategy: ChromeMV3ContentScriptObservationStrategy
    var observationBlockers:
        ChromeMV3ContentScriptFrameObservationBlockers
    var webKitUncertaintyNotes: [String]
}

struct ChromeMV3ContentScriptTestDOMInspectionSummary:
    Codable,
    Equatable,
    Sendable
{
    var attempted: Bool
    var navigationCompletionState: String
    var javaScriptEvaluationCompleted: Bool
    var readOnlyDOMInspection: Bool
    var persistentScriptRegistered: Bool
    var scriptMessageHandlerRegistered: Bool
    var jsBridgeUsed: Bool
    var scheduledClockOrRepeatedChecksUsed: Bool
    var inspectedFrameIDs: [String]
    var diagnostics: [String]

    static let notAttempted =
        ChromeMV3ContentScriptTestDOMInspectionSummary(
            attempted: false,
            navigationCompletionState: "notAttempted",
            javaScriptEvaluationCompleted: false,
            readOnlyDOMInspection: true,
            persistentScriptRegistered: false,
            scriptMessageHandlerRegistered: false,
            jsBridgeUsed: false,
            scheduledClockOrRepeatedChecksUsed: false,
            inspectedFrameIDs: [],
            diagnostics: []
        )
}

struct ChromeMV3ContentScriptTestDOMFrameSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var frameID: String
    var accessible: Bool
    var markerObserved: Bool
    var markerAttributeValue: String?
    var markerTokenValue: String?
    var reason: String?
}

enum ChromeMV3ContentScriptSmokeNextRecommendedAction:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case proceedToActionPopupHost
    case broadenManualWebKitVerification
    case blockedByUnsafeObservationMechanism
}

enum ChromeMV3ContentScriptFrameObservationModel {
    static func blockedOrUnverifiedRecords(
        matrix: ChromeMV3ContentScriptFrameMatrixResult,
        strategy: ChromeMV3ContentScriptObservationStrategy,
        eligibleState:
            ChromeMV3ContentScriptFrameMarkerObservationState = .unverified,
        reason: String
    ) -> [ChromeMV3ContentScriptFrameMarkerObservation] {
        matrix.allDecisions.map { decision in
            let state: ChromeMV3ContentScriptFrameMarkerObservationState
            let recordReason: String
            switch decision.expected {
            case .eligible:
                if decision.observationBlockers
                    .hasBlockingObservationConstraint {
                    state = .blocked
                    recordReason = uniqueSorted(
                        decision.observationBlockers.diagnostics
                    ).joined(separator: " ")
                } else {
                    state = eligibleState
                    recordReason = reason
                }
            case .blocked:
                state = .blocked
                recordReason = decision.reason
            case .unsupportedNeedsVerification:
                state = .blocked
                recordReason = decision.reason
            }
            return ChromeMV3ContentScriptFrameMarkerObservation(
                frameID: decision.frameID,
                kind: decision.kind,
                expectedEligibility: decision.expected,
                observedMarker: state,
                markerAttributeValue: nil,
                markerTokenValue: nil,
                reason: recordReason,
                observationStrategy: strategy,
                observationBlockers: decision.observationBlockers,
                webKitUncertaintyNotes:
                    notes(
                        decision: decision,
                        state: state
                    )
            )
        }.sorted { $0.frameID < $1.frameID }
    }

    static func records(
        matrix: ChromeMV3ContentScriptFrameMatrixResult,
        strategy: ChromeMV3ContentScriptObservationStrategy,
        snapshots:
            [String: ChromeMV3ContentScriptTestDOMFrameSnapshot]
    ) -> [ChromeMV3ContentScriptFrameMarkerObservation] {
        matrix.allDecisions.map { decision in
            let snapshot = snapshots[decision.frameID]
            let state: ChromeMV3ContentScriptFrameMarkerObservationState
            let reason: String
            switch decision.expected {
            case .eligible:
                if decision.observationBlockers
                    .hasBlockingObservationConstraint {
                    state = .blocked
                    reason = uniqueSorted(
                        decision.observationBlockers.diagnostics
                    ).joined(separator: " ")
                } else if snapshot?.markerObserved == true {
                    state = .observed
                    reason = "The inert marker DOM attributes were observed in the expected eligible frame."
                } else if snapshot?.accessible == true {
                    state = .notObserved
                    reason = "The eligible frame was DOM-accessible, but the inert marker attributes were absent."
                } else {
                    state = .unverified
                    reason =
                        snapshot?.reason
                            ?? "No DOM snapshot was available for this eligible frame."
                }
            case .blocked:
                state = .blocked
                reason = decision.reason
            case .unsupportedNeedsVerification:
                state = .blocked
                reason = decision.reason
            }

            return ChromeMV3ContentScriptFrameMarkerObservation(
                frameID: decision.frameID,
                kind: decision.kind,
                expectedEligibility: decision.expected,
                observedMarker: state,
                markerAttributeValue: snapshot?.markerAttributeValue,
                markerTokenValue: snapshot?.markerTokenValue,
                reason: reason,
                observationStrategy: strategy,
                observationBlockers: decision.observationBlockers,
                webKitUncertaintyNotes:
                    notes(
                        decision: decision,
                        state: state
                    )
            )
        }.sorted { $0.frameID < $1.frameID }
    }

    private static func notes(
        decision: ChromeMV3ContentScriptFrameDecision,
        state: ChromeMV3ContentScriptFrameMarkerObservationState
    ) -> [String] {
        var notes: [String] = []
        if decision.world == "ISOLATED" {
            notes.append(
                "The content script is modeled as isolated-world; DOM markers should still be page-visible, but JavaScript globals are not used for observation."
            )
        }
        if decision.kind == .sameOriginIframe {
            notes.append(
                "The no-network synthetic fixture uses embedded frame HTML; direct same-origin URL matching remains matrix-modeled."
            )
        }
        if decision.kind == .dataIframe || decision.kind == .blobIframe {
            notes.append(
                "Opaque-origin related-frame behavior remains WebKit-verified only."
            )
        }
        if decision.observationBlockers.blockedByCurrentSDKShape {
            notes.append("blockedByCurrentSDKShape")
        }
        if decision.observationBlockers.blockedByUnsafeObservationMechanism {
            notes.append("blockedByUnsafeObservationMechanism")
        }
        if decision.observationBlockers.blockedByWebKitBehavior {
            notes.append("blockedByWebKitBehavior")
        }
        if decision.observationBlockers.needsManualWebKitVerification {
            notes.append("needsManualWebKitVerification")
        }
        if state == .notObserved {
            notes.append(
                "This is a test DOM inspection result, not a claim about Chrome parity or product runtime support."
            )
        }
        return uniqueSorted(notes)
    }
}

enum ChromeMV3ContentScriptSmokeGateBlocker:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case extensionsModuleDisabled
    case explicitContentScriptSmokeNotAllowed
    case acceptedExtensionObjectUnavailable
    case detachedContextMissing
    case controllerLoadGateMissing
    case controllerLoadGateBlocked
    case loadedContextMissing
    case sameControllerMissing
    case contentScriptFixturePolicyFailed
    case realNormalTabAttachmentObserved
    case jsBridgeExposed
    case runtimeDispatchAvailable
    case serviceWorkerWakeAvailable
    case nativeMessagingAvailable
    case productRuntimeExposureRequested
    case syntheticWebViewCreationNotAllowed
    case syntheticNavigationNotAllowed
    case runtimeLoadabilityInvariantViolation

    var reason: String {
        switch self {
        case .extensionsModuleDisabled:
            return "The extensions module is disabled."
        case .explicitContentScriptSmokeNotAllowed:
            return "Explicit DEBUG/internal content-script smoke mode is not enabled."
        case .acceptedExtensionObjectUnavailable:
            return "An accepted WKWebExtension object is not available."
        case .detachedContextMissing:
            return "A detached WKWebExtensionContext is not available."
        case .controllerLoadGateMissing:
            return "Controller-load gate diagnostics are missing."
        case .controllerLoadGateBlocked:
            return "The controller-load gate did not allow the content-script fixture load."
        case .loadedContextMissing:
            return "A loaded WKWebExtensionContext was not observed."
        case .sameControllerMissing:
            return "The synthetic WebView configuration does not prove the same-controller requirement."
        case .contentScriptFixturePolicyFailed:
            return "The content-script smoke fixture policy did not pass."
        case .realNormalTabAttachmentObserved:
            return "A real normal-tab attachment was observed; this smoke must remain synthetic."
        case .jsBridgeExposed:
            return "The Sumi JS bridge is exposed or injectable, which is forbidden."
        case .runtimeDispatchAvailable:
            return "Runtime message dispatch is available or was requested."
        case .serviceWorkerWakeAvailable:
            return "A service-worker wake path is available or was requested."
        case .nativeMessagingAvailable:
            return "Native messaging launch or port opening is available or was requested."
        case .productRuntimeExposureRequested:
            return "Product runtime exposure, JS bridge injection, native messaging, or UI was requested."
        case .syntheticWebViewCreationNotAllowed:
            return "Synthetic WKWebView creation requires its explicit DEBUG/internal flag."
        case .syntheticNavigationNotAllowed:
            return "Synthetic navigation is not enabled for this content-script smoke run."
        case .runtimeLoadabilityInvariantViolation:
            return "runtimeLoadable and runtime availability must remain false."
        }
    }
}

struct ChromeMV3ContentScriptSmokeScenario:
    Codable,
    Equatable,
    Sendable
{
    var scenarioID: String
    var fixtureID: String
    var extensionID: String
    var profileID: String
}

struct ChromeMV3ContentScriptSmokeGateInput:
    Codable,
    Equatable,
    Sendable
{
    var scenario: ChromeMV3ContentScriptSmokeScenario
    var generatedRewrittenRootPath: String
    var extensionsModuleEnabled: Bool
    var explicitInternalContentScriptSmokeAllowed: Bool
    var explicitSyntheticWebViewCreationAllowed: Bool
    var explicitSyntheticNavigationAllowed: Bool
    var explicitTestDOMInspectionAllowed: Bool
    var acceptedWebExtensionObjectAvailable: Bool
    var detachedContextAvailable: Bool
    var loadedContextAvailable: Bool
    var sameControllerAvailable: Bool
    var contentScriptFixturePolicy:
        ChromeMV3ContentScriptSmokeFixturePolicyResult
    var controllerLoadGateDecision:
        ChromeMV3ControllerLoadGateDecision?
    var controllerLoadOwnerDiagnostics:
        ChromeMV3ControllerLoadOwnerDiagnostics?
    var liveNormalTabAttachmentSnapshot:
        ChromeMV3LiveNormalTabAttachmentRecorderSnapshot?
    var runtimeBridgeReadinessReport:
        ChromeMV3RuntimeBridgeReadinessReport?
    var requestedProductRuntimeExposure: Bool
    var requestedExtensionCodeExecution: Bool
    var requestedUserScriptRegistration: Bool
    var requestedNativeMessagingLaunch: Bool
    var requestedServiceWorkerWake: Bool
    var requestedRuntimeDispatch: Bool
    var requestedProductUI: Bool
}

struct ChromeMV3ContentScriptSmokeGateDecision:
    Codable,
    Equatable,
    Sendable
{
    var input: ChromeMV3ContentScriptSmokeGateInput
    var canRunContentScriptSmokeNow: Bool
    var canCreateSyntheticConfigurationNow: Bool
    var canCreateSyntheticWebViewNow: Bool
    var canNavigateSyntheticWebViewNow: Bool
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var productRuntimeExposed: Bool
    var blockers: [ChromeMV3ContentScriptSmokeGateBlocker]
    var blockingReasons: [String]
    var warnings: [String]
}

enum ChromeMV3ContentScriptSmokeGate {
    static func evaluate(
        input: ChromeMV3ContentScriptSmokeGateInput
    ) -> ChromeMV3ContentScriptSmokeGateDecision {
        var blockers: [ChromeMV3ContentScriptSmokeGateBlocker] = []
        var warnings = input.contentScriptFixturePolicy.warnings

        if input.extensionsModuleEnabled == false {
            blockers.append(.extensionsModuleDisabled)
        }
        if input.explicitInternalContentScriptSmokeAllowed == false {
            blockers.append(.explicitContentScriptSmokeNotAllowed)
        }
        if input.acceptedWebExtensionObjectAvailable == false {
            blockers.append(.acceptedExtensionObjectUnavailable)
        }
        if input.detachedContextAvailable == false {
            blockers.append(.detachedContextMissing)
        }
        if input.contentScriptFixturePolicy
            .loadSafeForContentScriptSmokeFixture == false {
            blockers.append(.contentScriptFixturePolicyFailed)
        }
        guard let controllerLoadDecision =
            input.controllerLoadGateDecision
        else {
            blockers.append(.controllerLoadGateMissing)
            return decision(input: input, blockers: blockers, warnings: warnings)
        }
        if controllerLoadDecision.loadAttemptAllowed == false {
            blockers.append(.controllerLoadGateBlocked)
        }
        if input.loadedContextAvailable == false
            || input.controllerLoadOwnerDiagnostics?
            .contextLoadedIntoController != true {
            blockers.append(.loadedContextMissing)
        }
        if input.sameControllerAvailable == false {
            blockers.append(.sameControllerMissing)
        }

        let liveSnapshot = input.liveNormalTabAttachmentSnapshot
            ?? controllerLoadDecision.input.liveNormalTabAttachmentSnapshot
        if (liveSnapshot?.attachedConfigurationCount ?? 0) > 0
            || (liveSnapshot?.createdAttachedWebViewCount ?? 0) > 0 {
            blockers.append(.realNormalTabAttachmentObserved)
        }

        let readiness = input.runtimeBridgeReadinessReport
        let jsBridge = readiness?.jsBridgeContractReportSummary
        if isSet(jsBridge?.jsBridgeAvailableNow)
            || isSet(jsBridge?.exposedToJSNow)
            || isSet(jsBridge?.canInjectScriptsNow) {
            blockers.append(.jsBridgeExposed)
        }
        if isSet(readiness?.messagingGate.dispatchImplemented)
            || input.requestedRuntimeDispatch {
            blockers.append(.runtimeDispatchAvailable)
        }
        if isSet(
            readiness?.serviceWorkerLifecycleGate
                .serviceWorkerWakeImplemented
        )
            || (input.controllerLoadOwnerDiagnostics?
                .serviceWorkerWakeCount ?? 0) > 0
            || input.requestedServiceWorkerWake {
            blockers.append(.serviceWorkerWakeAvailable)
        }
        if isSet(
            readiness?.nativeMessagingGate
                .nativeMessagingRuntimeImplemented
        )
            || isSet(
                readiness?.nativeMessagingGate
                    .processLaunchImplemented
            )
            || (input.controllerLoadOwnerDiagnostics?
                .nativeMessagingPortCount ?? 0) > 0
            || input.requestedNativeMessagingLaunch {
            blockers.append(.nativeMessagingAvailable)
        }
        if input.requestedProductRuntimeExposure
            || input.requestedExtensionCodeExecution
            || input.requestedUserScriptRegistration
            || input.requestedProductUI {
            blockers.append(.productRuntimeExposureRequested)
        }
        if isSet(input.controllerLoadOwnerDiagnostics?.runtimeLoadable)
            || isSet(
                input.controllerLoadOwnerDiagnostics?
                    .chromeRuntimeAvailableNow
            )
            || isSet(
                input.controllerLoadOwnerDiagnostics?
                    .jsBridgeAvailableNow
            )
            || isSet(readiness?.runtimeLoadable)
            || controllerLoadDecision.runtimeLoadable
            || controllerLoadDecision.chromeRuntimeAvailableNow
            || controllerLoadDecision.jsBridgeAvailableNow
            || controllerLoadDecision.canExecuteExtensionCodeNow {
            blockers.append(.runtimeLoadabilityInvariantViolation)
        }

        warnings.append(
            "This content-script smoke path is DEBUG/internal, synthetic, and does not expose product Chrome MV3 runtime."
        )
        warnings.append(
            "WebKit-owned content-script execution can remain unverified when observation would require forbidden Sumi injection or message handlers."
        )
        if input.explicitSyntheticWebViewCreationAllowed == false {
            warnings.append(
                "Synthetic WKWebView creation is skipped unless explicitly allowed for this smoke run."
            )
        }
        if input.explicitSyntheticNavigationAllowed == false {
            warnings.append(
                "Synthetic navigation is skipped unless explicitly allowed for this smoke run."
            )
        }

        return decision(input: input, blockers: blockers, warnings: warnings)
    }

    private static func decision(
        input: ChromeMV3ContentScriptSmokeGateInput,
        blockers: [ChromeMV3ContentScriptSmokeGateBlocker],
        warnings: [String]
    ) -> ChromeMV3ContentScriptSmokeGateDecision {
        let uniqueBlockers = Array(Set(blockers)).sorted {
            $0.rawValue < $1.rawValue
        }
        let canRun = uniqueBlockers.isEmpty
        let canCreateWebView =
            canRun && input.explicitSyntheticWebViewCreationAllowed
        let canNavigate =
            canCreateWebView && input.explicitSyntheticNavigationAllowed
        return ChromeMV3ContentScriptSmokeGateDecision(
            input: input,
            canRunContentScriptSmokeNow: canRun,
            canCreateSyntheticConfigurationNow: canRun,
            canCreateSyntheticWebViewNow: canCreateWebView,
            canNavigateSyntheticWebViewNow: canNavigate,
            runtimeLoadable: false,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            productRuntimeExposed: false,
            blockers: uniqueBlockers,
            blockingReasons: uniqueSorted(uniqueBlockers.map(\.reason)),
            warnings: uniqueSorted(warnings)
        )
    }
}

struct ChromeMV3ContentScriptSmokeRuntimeCounters:
    Codable,
    Equatable,
    Sendable
{
    var sumiWKUserScriptCount: Int
    var sumiAddUserScriptCount: Int
    var scriptMessageHandlerCount: Int
    var jsBridgeAvailableNow: Bool
    var serviceWorkerWakeCount: Int
    var runtimeDispatchCount: Int
    var runtimePortCount: Int
    var nativeMessagingPortCount: Int
    var processLaunchCount: Int
    var productNormalTabAttachmentCount: Int
    var syntheticConfigurationAttached: Int
    var syntheticWebViewCreated: Int
    var syntheticNavigationAttempted: Int
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var productRuntimeExposed: Bool

    static func zero(
        syntheticConfigurationAttached: Bool,
        syntheticWebViewCreated: Bool,
        syntheticNavigationAttempted: Bool
    ) -> ChromeMV3ContentScriptSmokeRuntimeCounters {
        ChromeMV3ContentScriptSmokeRuntimeCounters(
            sumiWKUserScriptCount: 0,
            sumiAddUserScriptCount: 0,
            scriptMessageHandlerCount: 0,
            jsBridgeAvailableNow: false,
            serviceWorkerWakeCount: 0,
            runtimeDispatchCount: 0,
            runtimePortCount: 0,
            nativeMessagingPortCount: 0,
            processLaunchCount: 0,
            productNormalTabAttachmentCount: 0,
            syntheticConfigurationAttached:
                syntheticConfigurationAttached ? 1 : 0,
            syntheticWebViewCreated: syntheticWebViewCreated ? 1 : 0,
            syntheticNavigationAttempted:
                syntheticNavigationAttempted ? 1 : 0,
            runtimeLoadable: false,
            chromeRuntimeAvailableNow: false,
            productRuntimeExposed: false
        )
    }
}

struct ChromeMV3ContentScriptSmokeSyntheticWebViewResult:
    Codable,
    Equatable,
    Sendable
{
    var syntheticConfigurationCreated: Bool
    var syntheticConfigurationAttached: Bool
    var syntheticConfigurationUsesSameController: Bool
    var syntheticWebViewCreated: Bool
    var syntheticWebViewUsesSameController: Bool
    var syntheticNavigationAttempted: Bool
    var syntheticHTMLLoaded: Bool
    var userVisibleWindowCreated: Bool
    var productTabRegistered: Bool
    var userScriptCount: Int
    var blockingReasons: [String]
    var warnings: [String]
}

struct ChromeMV3ContentScriptSmokeObservationResult:
    Codable,
    Equatable,
    Sendable
{
    var state: ChromeMV3ContentScriptSmokeObservationState
    var webKitOwnedContentScriptObserved: String
    var observedFrames: [String]
    var observationStrategy: ChromeMV3ContentScriptObservationStrategy
    var observationMethod: String
    var frameResults: [ChromeMV3ContentScriptFrameMarkerObservation]
    var testDOMInspection:
        ChromeMV3ContentScriptTestDOMInspectionSummary
    var blockedReasons: [String]
    var unverifiedWebKitInternalSideEffects: [String]
}

struct ChromeMV3ContentScriptExpandedMatrixRecord:
    Codable,
    Equatable,
    Sendable
{
    var fixtureID: String
    var manifestContentScriptMetadata:
        ChromeMV3ContentScriptSmokeManifestContentScriptMetadata
    var frameScenario: ChromeMV3ContentScriptFrameScenario
    var frameDecision: ChromeMV3ContentScriptFrameDecision
    var runAt: String
    var allFrames: Bool
    var matchAboutBlank: Bool
    var matchOriginAsFallback: Bool
    var world: String?
    var expectedEligibility: ChromeMV3ContentScriptFrameExpectation
    var observationStrategy: ChromeMV3ContentScriptObservationStrategy
    var resultClassification:
        ChromeMV3ContentScriptFrameMarkerObservationState
    var markerAttributeValue: String?
    var markerTokenValue: String?
    var resultReason: String
    var runAtClassification: ChromeMV3ContentScriptRunAtClassification
    var worldClassification:
        ChromeMV3ContentScriptWorldBehaviorClassification
    var observationBlockers:
        ChromeMV3ContentScriptFrameObservationBlockers
}

struct ChromeMV3ContentScriptSmokeReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var scenarioID: String
    var outcome: ChromeMV3ContentScriptSmokeOutcome
    var fixtureKind: ChromeMV3ContentScriptSmokeFixtureKind
    var contentScriptCount: Int
    var expectedEligibleFrameIDs: [String]
    var expectedBlockedFrameIDs: [String]
    var unsupportedFrameIDs: [String]
    var observedFrameIDs: [String]
    var notObservedFrameIDs: [String]
    var blockedFrameIDs: [String]
    var unverifiedFrameIDs: [String]
    var observationState: ChromeMV3ContentScriptSmokeObservationState
    var observationStrategy: ChromeMV3ContentScriptObservationStrategy
    var nextRecommendedAction:
        ChromeMV3ContentScriptSmokeNextRecommendedAction
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var productRuntimeExposed: Bool
}

struct ChromeMV3ContentScriptSmokeReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var generatedRewrittenRootPath: String
    var scenario: ChromeMV3ContentScriptSmokeScenario
    var fixturePolicyResult:
        ChromeMV3ContentScriptSmokeFixturePolicyResult
    var contentScriptManifestSummary:
        ChromeMV3ContentScriptSmokeManifestSummary
    var frameMatrixResult:
        ChromeMV3ContentScriptFrameMatrixResult
    var syntheticHTMLFixture:
        ChromeMV3ContentScriptSyntheticHTMLFixture
    var controllerLoadResult:
        ChromeMV3RuntimeMinimalSmokeControllerLoadSummary
    var gateDecision: ChromeMV3ContentScriptSmokeGateDecision
    var syntheticWebViewResult:
        ChromeMV3ContentScriptSmokeSyntheticWebViewResult
    var observationStrategyClassifications:
        [ChromeMV3ContentScriptObservationStrategyClassification]
    var markerFixtureFacts: ChromeMV3ContentScriptMarkerFixtureFacts
    var frameObservationResults:
        [ChromeMV3ContentScriptFrameMarkerObservation]
    var expandedMatrixResults: [ChromeMV3ContentScriptExpandedMatrixRecord]
    var observationResult:
        ChromeMV3ContentScriptSmokeObservationResult
    var nextRecommendedAction:
        ChromeMV3ContentScriptSmokeNextRecommendedAction
    var sideEffectCounters:
        ChromeMV3ContentScriptSmokeRuntimeCounters
    var webKitUncertaintyNotes: [String]
    var blockedOrUnsupportedCases: [String]
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var whyRuntimeLoadableRemainsFalse: [String]
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]

    var summary: ChromeMV3ContentScriptSmokeReportSummary {
        ChromeMV3ContentScriptSmokeReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            scenarioID: scenario.scenarioID,
            outcome: summaryOutcome,
            fixtureKind: fixturePolicyResult.fixtureKind,
            contentScriptCount:
                contentScriptManifestSummary.contentScriptCount,
            expectedEligibleFrameIDs:
                frameMatrixResult.expectedEligibleFrames.map(\.frameID),
            expectedBlockedFrameIDs:
                frameMatrixResult.expectedBlockedFrames.map(\.frameID),
            unsupportedFrameIDs:
                frameMatrixResult.unsupportedOrNeedsVerificationFrames
                .map(\.frameID),
            observedFrameIDs:
                frameObservationResults
                .filter { $0.observedMarker == .observed }
                .map(\.frameID),
            notObservedFrameIDs:
                frameObservationResults
                .filter { $0.observedMarker == .notObserved }
                .map(\.frameID),
            blockedFrameIDs:
                frameObservationResults
                .filter { $0.observedMarker == .blocked }
                .map(\.frameID),
            unverifiedFrameIDs:
                frameObservationResults
                .filter { $0.observedMarker == .unverified }
                .map(\.frameID),
            observationState: observationResult.state,
            observationStrategy: observationResult.observationStrategy,
            nextRecommendedAction: nextRecommendedAction,
            runtimeLoadable: false,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            productRuntimeExposed: false
        )
    }

    private var summaryOutcome: ChromeMV3ContentScriptSmokeOutcome {
        if gateDecision.canRunContentScriptSmokeNow == false {
            return .blocked
        }
        switch observationResult.state {
        case .observed:
            return .passed
        case .blocked, .notRequested:
            return .blocked
        case .unverified:
            return .unverified
        case .notObserved:
            return .failed
        }
    }
}

enum ChromeMV3ContentScriptSmokeReportWriter {
    static let reportFileName =
        "runtime-content-script-smoke-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3ContentScriptSmokeReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3ContentScriptSmokeReport {
        guard directoryExists(rootURL.standardizedFileURL) else {
            return report
        }
        try ChromeMV3DeterministicJSON.write(
            report,
            to: rootURL.standardizedFileURL
                .appendingPathComponent(Self.reportFileName)
        )
        return report
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}

enum ChromeMV3ContentScriptSmokeReportGenerator {
    static func makeReport(
        gateDecision: ChromeMV3ContentScriptSmokeGateDecision,
        frameMatrixResult: ChromeMV3ContentScriptFrameMatrixResult,
        syntheticHTMLFixture: ChromeMV3ContentScriptSyntheticHTMLFixture,
        syntheticWebViewResult:
            ChromeMV3ContentScriptSmokeSyntheticWebViewResult,
        observationResult:
            ChromeMV3ContentScriptSmokeObservationResult,
        observationStrategyClassifications:
            [ChromeMV3ContentScriptObservationStrategyClassification] = [],
        markerFixtureFacts: ChromeMV3ContentScriptMarkerFixtureFacts =
            .inertMarker
    ) -> ChromeMV3ContentScriptSmokeReport {
        let input = gateDecision.input
        let loadDiagnostics = input.controllerLoadOwnerDiagnostics
        let contextLoaded = isSet(
            loadDiagnostics?.contextLoadedIntoController
        )
        let outcome: ChromeMV3ContentScriptSmokeOutcome
        if gateDecision.canRunContentScriptSmokeNow == false {
            outcome = .blocked
        } else if observationResult.state == .observed {
            outcome = .passed
        } else if observationResult.state == .blocked {
            outcome = .blocked
        } else if observationResult.state == .unverified {
            outcome = .unverified
        } else {
            outcome = .failed
        }
        let frameObservationResults = observationResult.frameResults
            .isEmpty
            ? ChromeMV3ContentScriptFrameObservationModel
                .blockedOrUnverifiedRecords(
                    matrix: frameMatrixResult,
                    strategy: observationResult.observationStrategy,
                    reason:
                        "No frame-specific marker observation record was supplied."
                )
            : observationResult.frameResults
        let nextAction = nextRecommendedAction(
            outcome: outcome,
            frameMatrixResult: frameMatrixResult,
            frameObservationResults: frameObservationResults
        )
        let classifications =
            observationStrategyClassifications.isEmpty
                ? ChromeMV3ContentScriptObservationStrategyClassifier
                    .classifyAll(
                        scope:
                            ChromeMV3ContentScriptObservationStrategyScope
                            .contentScriptSmoke(
                                explicitTestDOMInspectionAllowed:
                                    input.explicitTestDOMInspectionAllowed,
                                sameControllerSyntheticConfiguration:
                                    syntheticWebViewResult
                                    .syntheticConfigurationUsesSameController,
                                syntheticNavigationAllowed:
                                    syntheticWebViewResult
                                    .syntheticNavigationAttempted,
                                productNormalTabAttachmentCount: 0
                            )
                    )
                : observationStrategyClassifications

        let unsupported = frameMatrixResult
            .unsupportedOrNeedsVerificationFrames
            .map { "\($0.frameID): \($0.reason)" }
        let blocked = gateDecision.blockingReasons
            + input.contentScriptFixturePolicy.blockingReasons
            + observationResult.blockedReasons
            + unsupported
        let expandedMatrixResults = expandedMatrixRecords(
            fixtureID: input.scenario.fixtureID,
            manifestSummary: input.contentScriptFixturePolicy
                .manifestSummary,
            frameMatrixResult: frameMatrixResult,
            frameObservationResults: frameObservationResults,
            markerFixtureFacts: markerFixtureFacts,
            strategy: observationResult.observationStrategy
        )

        return ChromeMV3ContentScriptSmokeReport(
            schemaVersion: 1,
            id: reportID(
                scenario: input.scenario,
                rootPath: input.generatedRewrittenRootPath,
                outcome: outcome,
                observationState: observationResult.state
            ),
            reportFileName:
                ChromeMV3ContentScriptSmokeReportWriter.reportFileName,
            generatedRewrittenRootPath:
                input.generatedRewrittenRootPath,
            scenario: input.scenario,
            fixturePolicyResult: input.contentScriptFixturePolicy,
            contentScriptManifestSummary:
                input.contentScriptFixturePolicy.manifestSummary,
            frameMatrixResult: frameMatrixResult,
            syntheticHTMLFixture: syntheticHTMLFixture,
            controllerLoadResult:
                ChromeMV3RuntimeMinimalSmokeControllerLoadSummary(
                    controllerLoadGateReportSummary:
                        loadDiagnostics?.gateDecision
                        .contentScriptSmokeSummaryLikeReportSummary(),
                    loadOwnerState: loadDiagnostics?.state,
                    controllerLoadAttempted:
                        loadDiagnostics?.controllerLoadAttempted ?? false,
                    contextLoadedIntoController: contextLoaded,
                    controllerLoadCount:
                        loadDiagnostics?.controllerLoadCount ?? 0,
                    runtimeLoadable: false,
                    chromeRuntimeAvailableNow: false,
                    jsBridgeAvailableNow: false
                ),
            gateDecision: gateDecision,
            syntheticWebViewResult: syntheticWebViewResult,
            observationStrategyClassifications:
                classifications,
            markerFixtureFacts: markerFixtureFacts,
            frameObservationResults: frameObservationResults,
            expandedMatrixResults: expandedMatrixResults,
            observationResult: observationResult,
            nextRecommendedAction: nextAction,
            sideEffectCounters:
                .zero(
                    syntheticConfigurationAttached:
                        syntheticWebViewResult
                        .syntheticConfigurationAttached,
                    syntheticWebViewCreated:
                        syntheticWebViewResult.syntheticWebViewCreated,
                    syntheticNavigationAttempted:
                        syntheticWebViewResult
                        .syntheticNavigationAttempted
                ),
            webKitUncertaintyNotes:
                webKitUncertaintyNotes(
                    contextLoaded: contextLoaded,
                    webViewResult: syntheticWebViewResult,
                    observationResult: observationResult
                ),
            blockedOrUnsupportedCases: uniqueSorted(blocked),
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            whyRuntimeLoadableRemainsFalse: [
                "This is a DEBUG/internal synthetic content-script smoke harness, not product runtime support.",
                "Sumi does not expose chrome.runtime, register Sumi user scripts, add script handlers, dispatch extension messages, open ports, launch native hosts, or attach normal tabs.",
                "The fixture contains only inert marker content scripts and no background service worker, action UI, options UI, external connectability, or native messaging.",
                "runtimeLoadable, chromeRuntimeAvailableNow, jsBridgeAvailableNow, and productRuntimeExposed remain false by invariant.",
            ],
            documentationSources: documentationSources()
        )
    }

    static func syntheticWebViewResult(
        syntheticConfigurationCreated: Bool,
        syntheticConfigurationAttached: Bool,
        syntheticConfigurationUsesSameController: Bool,
        syntheticWebViewCreated: Bool,
        syntheticWebViewUsesSameController: Bool,
        syntheticNavigationAttempted: Bool,
        syntheticHTMLLoaded: Bool,
        userScriptCount: Int,
        blockingReasons: [String],
        warnings: [String]
    ) -> ChromeMV3ContentScriptSmokeSyntheticWebViewResult {
        ChromeMV3ContentScriptSmokeSyntheticWebViewResult(
            syntheticConfigurationCreated: syntheticConfigurationCreated,
            syntheticConfigurationAttached: syntheticConfigurationAttached,
            syntheticConfigurationUsesSameController:
                syntheticConfigurationUsesSameController,
            syntheticWebViewCreated: syntheticWebViewCreated,
            syntheticWebViewUsesSameController:
                syntheticWebViewUsesSameController,
            syntheticNavigationAttempted: syntheticNavigationAttempted,
            syntheticHTMLLoaded: syntheticHTMLLoaded,
            userVisibleWindowCreated: false,
            productTabRegistered: false,
            userScriptCount: userScriptCount,
            blockingReasons: uniqueSorted(blockingReasons),
            warnings: uniqueSorted(warnings)
        )
    }

    static func observationResult(
        state: ChromeMV3ContentScriptSmokeObservationState,
        strategy: ChromeMV3ContentScriptObservationStrategy = .none,
        observedFrames: [String] = [],
        frameResults: [ChromeMV3ContentScriptFrameMarkerObservation] = [],
        testDOMInspection:
            ChromeMV3ContentScriptTestDOMInspectionSummary = .notAttempted,
        blockedReasons: [String],
        unverifiedNotes: [String]
    ) -> ChromeMV3ContentScriptSmokeObservationResult {
        let observedString: String
        switch state {
        case .observed:
            observedString = "true"
        case .notObserved:
            observedString = "false"
        case .notRequested, .blocked, .unverified:
            observedString = "unverified"
        }
        return ChromeMV3ContentScriptSmokeObservationResult(
            state: state,
            webKitOwnedContentScriptObserved: observedString,
            observedFrames: uniqueSorted(observedFrames),
            observationStrategy: strategy,
            observationMethod:
                observationMethod(strategy: strategy),
            frameResults: frameResults,
            testDOMInspection: testDOMInspection,
            blockedReasons: uniqueSorted(blockedReasons),
            unverifiedWebKitInternalSideEffects:
                uniqueSorted(unverifiedNotes)
        )
    }

    private static func observationMethod(
        strategy: ChromeMV3ContentScriptObservationStrategy
    ) -> String {
        switch strategy {
        case .testDOMInspection:
            return "testDOMInspection: one-shot page-world DOM read after synthetic navigation; no Sumi-owned persistent script, script handler, JS bridge, runtime message dispatch, port, native host launch, product tab, or product UI is used."
        case .none:
            return "No page-state observation is performed; no Sumi-owned persistent script, script handler, JS bridge, runtime message dispatch, port, native host launch, product tab, or product UI is used."
        case .webKitSupportedInspection:
            return "WebKitSupportedInspection is reserved for a future public WebKit marker-inspection surface."
        case .blockedRequiresSumiInjection:
            return "Rejected Sumi-owned injection strategy."
        case .blockedRequiresScriptMessageHandler:
            return "Rejected script-message handler strategy."
        case .blockedRequiresJSBridge:
            return "Rejected Sumi JavaScript bridge strategy."
        case .unsupportedByCurrentSDK:
            return "No public SDK marker-inspection surface is available."
        }
    }

    private static func reportID(
        scenario: ChromeMV3ContentScriptSmokeScenario,
        rootPath: String,
        outcome: ChromeMV3ContentScriptSmokeOutcome,
        observationState: ChromeMV3ContentScriptSmokeObservationState
    ) -> String {
        let input = [
            scenario.scenarioID,
            scenario.fixtureID,
            scenario.extensionID,
            scenario.profileID,
            rootPath,
            outcome.rawValue,
            observationState.rawValue,
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func nextRecommendedAction(
        outcome: ChromeMV3ContentScriptSmokeOutcome,
        frameMatrixResult: ChromeMV3ContentScriptFrameMatrixResult,
        frameObservationResults:
            [ChromeMV3ContentScriptFrameMarkerObservation]
    ) -> ChromeMV3ContentScriptSmokeNextRecommendedAction {
        guard outcome == .passed else {
            return .blockedByUnsafeObservationMechanism
        }
        let eligibleIDs = Set(
            frameMatrixResult.expectedEligibleFrames
                .filter {
                    $0.observationBlockers
                        .hasBlockingObservationConstraint == false
                }
                .map(\.frameID)
        )
        let observedIDs = Set(
            frameObservationResults
                .filter { $0.observedMarker == .observed }
                .map(\.frameID)
        )
        let needsManualVerification = frameObservationResults.contains {
            $0.observationBlockers.needsManualWebKitVerification
        }
        if eligibleIDs.isSubset(of: observedIDs),
           needsManualVerification == false {
            return .proceedToActionPopupHost
        }
        return .broadenManualWebKitVerification
    }

    private static func expandedMatrixRecords(
        fixtureID: String,
        manifestSummary: ChromeMV3ContentScriptSmokeManifestSummary,
        frameMatrixResult: ChromeMV3ContentScriptFrameMatrixResult,
        frameObservationResults:
            [ChromeMV3ContentScriptFrameMarkerObservation],
        markerFixtureFacts: ChromeMV3ContentScriptMarkerFixtureFacts,
        strategy: ChromeMV3ContentScriptObservationStrategy
    ) -> [ChromeMV3ContentScriptExpandedMatrixRecord] {
        let metadata =
            manifestSummary.contentScriptMetadata.first
                ?? ChromeMV3ContentScriptSmokeManifestContentScriptMetadata(
                    contentScriptIndex: 0,
                    jsPaths: manifestSummary.jsPaths,
                    cssPaths: manifestSummary.cssPaths,
                    matchPatterns: manifestSummary.matchPatterns,
                    excludeMatchPatterns:
                        manifestSummary.excludeMatchPatterns,
                    includeGlobs: manifestSummary.includeGlobs,
                    excludeGlobs: manifestSummary.excludeGlobs,
                    allFrames:
                        manifestSummary.allFramesValues.contains(true),
                    matchAboutBlank:
                        manifestSummary.matchAboutBlankValues
                        .contains(true),
                    matchOriginAsFallback:
                        manifestSummary.matchOriginAsFallbackValues
                        .contains(true),
                    runAt:
                        manifestSummary.runAtValues.first
                            ?? "document_idle",
                    world: manifestSummary.worldValues.first
                )
        let scenarios = Dictionary(
            uniqueKeysWithValues:
                frameMatrixResult.frameScenarios.map {
                    ($0.frameID, $0)
                }
        )
        let observations = Dictionary(
            uniqueKeysWithValues:
                frameObservationResults.map {
                    ($0.frameID, $0)
                }
        )

        return frameMatrixResult.allDecisions.map { decision in
            let observation = observations[decision.frameID]
            let state =
                observation?.observedMarker
                    ?? (decision.expected == .blocked
                        ? ChromeMV3ContentScriptFrameMarkerObservationState
                            .blocked
                        : .unverified)
            let blockers = observation?.observationBlockers
                ?? decision.observationBlockers
            let observedAfterLoad = state == .observed
            return ChromeMV3ContentScriptExpandedMatrixRecord(
                fixtureID: fixtureID,
                manifestContentScriptMetadata: metadata,
                frameScenario:
                    scenarios[decision.frameID]
                        ?? ChromeMV3ContentScriptFrameScenario(
                            frameID: decision.frameID,
                            kind: decision.kind,
                            urlString: decision.urlString,
                            parentURLString: nil,
                            safeToInstantiateWithoutNetwork: false,
                            fixtureElementID: nil,
                            safeToObserveWithTestDOMInspection: false,
                            syntheticFixtureDiagnostic:
                                "Frame scenario was not present in the matrix scenario list."
                        ),
                frameDecision: decision,
                runAt: decision.runAt,
                allFrames: decision.allFrames,
                matchAboutBlank: decision.matchAboutBlank,
                matchOriginAsFallback: decision.matchOriginAsFallback,
                world: decision.world,
                expectedEligibility: decision.expected,
                observationStrategy:
                    observation?.observationStrategy ?? strategy,
                resultClassification: state,
                markerAttributeValue: observation?.markerAttributeValue,
                markerTokenValue: observation?.markerTokenValue,
                resultReason:
                    observation?.reason
                        ?? "No frame-specific observation was supplied.",
                runAtClassification:
                    ChromeMV3ContentScriptRunAtClassification.classify(
                        runAt: decision.runAt,
                        observedMarkerAfterLoad: observedAfterLoad
                    ),
                worldClassification:
                    ChromeMV3ContentScriptWorldBehaviorClassification
                    .classify(
                        declaredWorld: decision.world,
                        markerFacts: markerFixtureFacts
                    ),
                observationBlockers: blockers
            )
        }.sorted { $0.frameDecision.frameID < $1.frameDecision.frameID }
    }

    private static func webKitUncertaintyNotes(
        contextLoaded: Bool,
        webViewResult:
            ChromeMV3ContentScriptSmokeSyntheticWebViewResult,
        observationResult:
            ChromeMV3ContentScriptSmokeObservationResult
    ) -> [String] {
        var notes = [
            "Observable Sumi-side counters are deterministic; private WebKit internals are not fully observable from Sumi.",
        ]
        if contextLoaded {
            notes.append(
                "The WKWebExtensionController load path was observed; WebKit-owned content-script scheduling remains internal."
            )
        }
        if webViewResult.syntheticWebViewCreated {
            notes.append(
                "A hidden synthetic WKWebView was created without normal-tab registration or product UI."
            )
        }
        if observationResult.state != .observed {
            notes.append(
                "Content-script marker observation is reported as \(observationResult.state.rawValue) rather than claimed as Chrome parity."
            )
        }
        return uniqueSorted(
            notes + observationResult.unverifiedWebKitInternalSideEffects
        )
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            source(
                kind: "chromeDocumentation",
                title: "Manifest content scripts",
                url: "https://developer.chrome.com/docs/extensions/reference/manifest/content-scripts",
                note: "Used for content_scripts, matches, exclude_matches, include_globs, exclude_globs, all_frames, match_about_blank, match_origin_as_fallback, run_at, and world metadata."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Content scripts",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts",
                note: "Used for content-script isolation and messaging boundary terminology."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebView.evaluateJavaScript",
                url: "https://developer.apple.com/documentation/webkit/wkwebview/evaluatejavascript%28_%3Acompletionhandler%3A%29",
                note: "Used only to classify the DEBUG/internal one-shot testDOMInspection DOM read; it is not persistent script registration or bridge communication."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionController",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensioncontroller",
                note: "A controller manages loaded extension contexts."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebViewConfiguration.webExtensionController",
                url: "https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/webextensioncontroller",
                note: "The property associates the synthetic WebView configuration with the loaded extension controller."
            ),
            source(
                kind: "localAppleSDKHeaders",
                title: "MacOSX26.5 WebKit headers",
                url: nil,
                note: "Headers state that controller load starts background content and injects content into relevant tabs, and that tab WebViews need the same controller for content injection or modification."
            ),
        ]
    }

    private static func source(
        kind: String,
        title: String,
        url: String?,
        note: String
    ) -> ChromeMV3WebKitObjectAcceptanceDocumentationSource {
        ChromeMV3WebKitObjectAcceptanceDocumentationSource(
            kind: kind,
            title: title,
            url: url,
            note: note
        )
    }
}

#if DEBUG
import WebKit

enum ChromeMV3ContentScriptSmokeNavigationCompletionState:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case notStarted
    case finished
    case failed
}

struct ChromeMV3ContentScriptSmokeNavigationCompletion:
    Codable,
    Equatable,
    Sendable
{
    var state: ChromeMV3ContentScriptSmokeNavigationCompletionState
    var errorDescription: String?

    static let notStarted =
        ChromeMV3ContentScriptSmokeNavigationCompletion(
            state: .notStarted,
            errorDescription: nil
        )
}

@MainActor
private final class ChromeMV3ContentScriptSmokeNavigationObserver:
    NSObject,
    WKNavigationDelegate
{
    private var completion:
        ChromeMV3ContentScriptSmokeNavigationCompletion?
    private var continuation:
        CheckedContinuation<
            ChromeMV3ContentScriptSmokeNavigationCompletion,
            Never
        >?

    func waitForCompletion(
        navigation: WKNavigation?
    ) async -> ChromeMV3ContentScriptSmokeNavigationCompletion {
        guard navigation != nil else {
            return .notStarted
        }
        if let completion {
            return completion
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        _ = webView
        finish(
            ChromeMV3ContentScriptSmokeNavigationCompletion(
                state: .finished,
                errorDescription: nil
            )
        )
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        _ = navigation
        finish(
            ChromeMV3ContentScriptSmokeNavigationCompletion(
                state: .failed,
                errorDescription: error.localizedDescription
            )
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        _ = navigation
        finish(
            ChromeMV3ContentScriptSmokeNavigationCompletion(
                state: .failed,
                errorDescription: error.localizedDescription
            )
        )
    }

    private func finish(
        _ completion:
            ChromeMV3ContentScriptSmokeNavigationCompletion
    ) {
        guard self.completion == nil else { return }
        self.completion = completion
        continuation?.resume(returning: completion)
        continuation = nil
    }
}

@available(macOS 15.5, *)
@MainActor
private enum ChromeMV3ContentScriptTestDOMInspection {
    static func inspect(
        webView: WKWebView,
        navigationCompletion:
            ChromeMV3ContentScriptSmokeNavigationCompletion,
        matrix: ChromeMV3ContentScriptFrameMatrixResult
    ) async -> (
        result: ChromeMV3ContentScriptSmokeObservationResult,
        snapshots: [String: ChromeMV3ContentScriptTestDOMFrameSnapshot]
    ) {
        guard navigationCompletion.state == .finished else {
            let records =
                ChromeMV3ContentScriptFrameObservationModel
                .blockedOrUnverifiedRecords(
                    matrix: matrix,
                    strategy: .testDOMInspection,
                    eligibleState: .unverified,
                    reason:
                        "Synthetic navigation did not finish before test DOM inspection."
                )
            let summary = ChromeMV3ContentScriptTestDOMInspectionSummary(
                attempted: true,
                navigationCompletionState:
                    navigationCompletion.state.rawValue,
                javaScriptEvaluationCompleted: false,
                readOnlyDOMInspection: true,
                persistentScriptRegistered: false,
                scriptMessageHandlerRegistered: false,
                jsBridgeUsed: false,
                scheduledClockOrRepeatedChecksUsed: false,
                inspectedFrameIDs: [],
                diagnostics:
                    uniqueSorted(
                        [
                            navigationCompletion.errorDescription,
                            "Navigation completion is required before DOM marker inspection.",
                        ].compactMap { $0 }
                    )
            )
            return (
                ChromeMV3ContentScriptSmokeReportGenerator
                    .observationResult(
                        state: .unverified,
                        strategy: .testDOMInspection,
                        frameResults: records,
                        testDOMInspection: summary,
                        blockedReasons: [],
                        unverifiedNotes: summary.diagnostics
                    ),
                [:]
            )
        }

        do {
            let json = try await evaluateMarkerReadScript(in: webView)
            let snapshots = decodeSnapshots(json)
            let records = ChromeMV3ContentScriptFrameObservationModel
                .records(
                    matrix: matrix,
                    strategy: .testDOMInspection,
                    snapshots: snapshots
                )
            let observedFrames = records
                .filter { $0.observedMarker == .observed }
                .map(\.frameID)
            let eligibleRecords = records.filter {
                $0.expectedEligibility == .eligible
            }
            let allEligibleObserved = eligibleRecords.isEmpty == false
                && eligibleRecords.allSatisfy {
                    $0.observedMarker == .observed
                }
            let anyEligibleMissing = eligibleRecords.contains {
                $0.observedMarker == .notObserved
            }
            let state: ChromeMV3ContentScriptSmokeObservationState
            if allEligibleObserved {
                state = .observed
            } else if anyEligibleMissing {
                state = .notObserved
            } else {
                state = .unverified
            }
            let summary = ChromeMV3ContentScriptTestDOMInspectionSummary(
                attempted: true,
                navigationCompletionState:
                    navigationCompletion.state.rawValue,
                javaScriptEvaluationCompleted: true,
                readOnlyDOMInspection: true,
                persistentScriptRegistered: false,
                scriptMessageHandlerRegistered: false,
                jsBridgeUsed: false,
                scheduledClockOrRepeatedChecksUsed: false,
                inspectedFrameIDs: uniqueSorted(Array(snapshots.keys)),
                diagnostics: []
            )
            return (
                ChromeMV3ContentScriptSmokeReportGenerator
                    .observationResult(
                        state: state,
                        strategy: .testDOMInspection,
                        observedFrames: observedFrames,
                        frameResults: records,
                        testDOMInspection: summary,
                        blockedReasons: [],
                        unverifiedNotes:
                            state == .observed
                                ? [
                                    "WebKit-owned content-script marker DOM attributes were observed by testDOMInspection.",
                                ]
                                : [
                                    "testDOMInspection completed without forbidden Sumi runtime paths, but not every eligible marker was observed.",
                                ]
                    ),
                snapshots
            )
        } catch {
            let records =
                ChromeMV3ContentScriptFrameObservationModel
                .blockedOrUnverifiedRecords(
                    matrix: matrix,
                    strategy: .testDOMInspection,
                    eligibleState: .unverified,
                    reason:
                        "One-shot DOM inspection failed: \(error.localizedDescription)"
                )
            let summary = ChromeMV3ContentScriptTestDOMInspectionSummary(
                attempted: true,
                navigationCompletionState:
                    navigationCompletion.state.rawValue,
                javaScriptEvaluationCompleted: false,
                readOnlyDOMInspection: true,
                persistentScriptRegistered: false,
                scriptMessageHandlerRegistered: false,
                jsBridgeUsed: false,
                scheduledClockOrRepeatedChecksUsed: false,
                inspectedFrameIDs: [],
                diagnostics: [error.localizedDescription]
            )
            return (
                ChromeMV3ContentScriptSmokeReportGenerator
                    .observationResult(
                        state: .unverified,
                        strategy: .testDOMInspection,
                        frameResults: records,
                        testDOMInspection: summary,
                        blockedReasons: [],
                        unverifiedNotes: summary.diagnostics
                    ),
                [:]
            )
        }
    }

    private static func evaluateMarkerReadScript(
        in webView: WKWebView
    ) async throws -> String {
        let script = """
        (() => {
          const marker = "sumiChromeMV3ContentScriptSmokeMarker";
          const readRoot = (root) => {
            if (!root) {
              return {
                accessible: false,
                markerObserved: false,
                markerAttributeValue: null,
                markerTokenValue: null,
                reason: "missing-document-root"
              };
            }
            const markerAttributeValue = root.getAttribute("data-sumi-mv3-content-script-smoke") || "";
            const markerTokenValue = root.getAttribute("data-sumi-mv3-content-script-smoke-marker") || "";
            return {
              accessible: true,
              markerObserved: markerAttributeValue.length > 0 && markerTokenValue === marker,
              markerAttributeValue,
              markerTokenValue,
              reason: null
            };
          };
          const readFrame = (id) => {
            const frame = document.getElementById(id);
            if (!frame) {
              return {
                accessible: false,
                markerObserved: false,
                markerAttributeValue: null,
                markerTokenValue: null,
                reason: "missing-frame-element"
              };
            }
            try {
              return readRoot(frame.contentDocument && frame.contentDocument.documentElement);
            } catch (error) {
              return {
                accessible: false,
                markerObserved: false,
                markerAttributeValue: null,
                markerTokenValue: null,
                reason: "frame-dom-inaccessible:" + error.name
              };
            }
          };
          return JSON.stringify({
            "top": readRoot(document.documentElement),
            "same-origin": readFrame("same-origin-frame"),
            "cross-origin": readFrame("cross-origin-frame"),
            "about-blank": readFrame("about-blank-frame"),
            "data": readFrame("data-frame"),
            "blob": readFrame("blob-frame")
          });
        })();
        """
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<String, Error>) in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let string = result as? String {
                    continuation.resume(returning: string)
                } else {
                    continuation.resume(
                        throwing:
                            NSError(
                                domain:
                                    "Sumi.ChromeMV3ContentScriptTestDOMInspection",
                                code: 1,
                                userInfo: [
                                    NSLocalizedDescriptionKey:
                                        "DOM inspection did not return a JSON string.",
                                ]
                            )
                    )
                }
            }
        }
    }

    private static func decodeSnapshots(
        _ json: String
    ) -> [String: ChromeMV3ContentScriptTestDOMFrameSnapshot] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: [String: Any]]
        else {
            return [:]
        }

        return object.reduce(into: [:]) { result, entry in
            let value = entry.value
            result[entry.key] =
                ChromeMV3ContentScriptTestDOMFrameSnapshot(
                    frameID: entry.key,
                    accessible: boolValue(value["accessible"]) ?? false,
                    markerObserved:
                        boolValue(value["markerObserved"]) ?? false,
                    markerAttributeValue:
                        stringValue(value["markerAttributeValue"]),
                    markerTokenValue: stringValue(value["markerTokenValue"]),
                    reason: stringValue(value["reason"])
                )
        }
    }
}

@available(macOS 15.5, *)
enum ChromeMV3ContentScriptSmokeHarness {
    @MainActor
    static func run(
        scenarioID: String = "runtime-content-script-smoke",
        fixtureID: String? = nil,
        candidate: ChromeMV3RewrittenVariantCandidate,
        extensionsModuleEnabled: Bool,
        explicitInternalContentScriptSmokeAllowed: Bool,
        explicitSyntheticWebViewCreationAllowed: Bool,
        explicitSyntheticNavigationAllowed: Bool = false,
        explicitTestDOMInspectionAllowed: Bool = false,
        objectAcceptanceReport:
            ChromeMV3WebKitObjectAcceptanceReport?,
        runtimeBridgeReadinessReport:
            ChromeMV3RuntimeBridgeReadinessReport?,
        emptyControllerOwner:
            ChromeMV3EmptyControllerOwner?,
        detachedContextOwner:
            ChromeMV3DetachedContextOwner?,
        controllerLoadOwner:
            ChromeMV3ControllerLoadOwner?,
        liveNormalTabAttachmentSnapshot:
            ChromeMV3LiveNormalTabAttachmentRecorderSnapshot? = nil,
        tearDownLoadedContextAndControllerAfterRun: Bool = true
    ) -> ChromeMV3ContentScriptSmokeReport {
        let rootPath = URL(
            fileURLWithPath: candidate.rewrittenVariantRootPath,
            isDirectory: true
        ).standardizedFileURL.path
        let loadDiagnostics = controllerLoadOwner?.diagnostics()
        let controller = emptyControllerOwner?.controller
        let context = detachedContextOwner?.detachedContext
        let accepted =
            objectAcceptanceReport?.objectAcceptedByWebKit == true
        let detachedAvailable =
            context != nil
                || isSet(loadDiagnostics?.contextLoadedIntoController)
        let sameController =
            controller != nil
                && context?.webExtensionController === controller
                && isSet(loadDiagnostics?.contextLoadedIntoController)
        let policy = ChromeMV3ContentScriptSmokeFixturePolicy.evaluate(
            generatedRewrittenRootPath: rootPath,
            acceptedWebExtensionObjectAvailable: accepted,
            detachedContextCreated: detachedAvailable
        )
        let scenario = ChromeMV3ContentScriptSmokeScenario(
            scenarioID: scenarioID,
            fixtureID:
                fixtureID
                    ?? "content-script-smoke-fixture:\(candidate.id)",
            extensionID:
                objectAcceptanceReport?.generatedBundleID
                    ?? candidate.id,
            profileID:
                loadDiagnostics?
                .gateDecision
                .input
                .profileIdentifier
                    ?? "unknown-profile"
        )
        let gateInput = ChromeMV3ContentScriptSmokeGateInput(
            scenario: scenario,
            generatedRewrittenRootPath: rootPath,
            extensionsModuleEnabled: extensionsModuleEnabled,
            explicitInternalContentScriptSmokeAllowed:
                explicitInternalContentScriptSmokeAllowed,
            explicitSyntheticWebViewCreationAllowed:
                explicitSyntheticWebViewCreationAllowed,
            explicitSyntheticNavigationAllowed:
                explicitSyntheticNavigationAllowed,
            explicitTestDOMInspectionAllowed:
                explicitTestDOMInspectionAllowed,
            acceptedWebExtensionObjectAvailable: accepted,
            detachedContextAvailable: detachedAvailable,
            loadedContextAvailable:
                isSet(loadDiagnostics?.contextLoadedIntoController),
            sameControllerAvailable: sameController,
            contentScriptFixturePolicy: policy,
            controllerLoadGateDecision: loadDiagnostics?.gateDecision,
            controllerLoadOwnerDiagnostics: loadDiagnostics,
            liveNormalTabAttachmentSnapshot:
                liveNormalTabAttachmentSnapshot,
            runtimeBridgeReadinessReport:
                runtimeBridgeReadinessReport,
            requestedProductRuntimeExposure: false,
            requestedExtensionCodeExecution: false,
            requestedUserScriptRegistration: false,
            requestedNativeMessagingLaunch: false,
            requestedServiceWorkerWake: false,
            requestedRuntimeDispatch: false,
            requestedProductUI: false
        )
        let gateDecision = ChromeMV3ContentScriptSmokeGate.evaluate(
            input: gateInput
        )
        let frameMatrix = ChromeMV3ContentScriptFrameMatrix.evaluate(
            scenarioID: scenarioID,
            manifestSummary: policy.manifestSummary
        )
        let htmlFixture = ChromeMV3ContentScriptSyntheticHTMLFixture.generate(
            matrix: frameMatrix
        )

        var syntheticConfiguration: WKWebViewConfiguration?
        var syntheticWebView: WKWebView?
        var syntheticConfigurationAttached = false
        var syntheticConfigurationUsesSameController = false
        var syntheticWebViewUsesSameController = false
        var syntheticNavigationAttempted = false
        var syntheticHTMLLoaded = false
        var userScriptCount = 0
        var webViewWarnings: [String] = []
        var webViewBlockingReasons: [String] = []

        if gateDecision.canCreateSyntheticConfigurationNow,
           let controller {
            syntheticConfiguration = WKWebViewConfiguration()
            syntheticConfiguration?
                .sumiIsNormalTabWebViewConfiguration = false
            syntheticConfiguration?.webExtensionController = controller
            syntheticConfigurationAttached =
                syntheticConfiguration?.webExtensionController === controller
            syntheticConfigurationUsesSameController =
                syntheticConfigurationAttached && sameController
            userScriptCount =
                syntheticConfiguration?.userContentController
                .userScripts
                .count ?? 0
        } else {
            webViewBlockingReasons.append(
                "Synthetic configuration was not created because the content-script smoke gate is blocked."
            )
        }

        if gateDecision.canCreateSyntheticWebViewNow,
           syntheticConfigurationAttached,
           let syntheticConfiguration,
           let controller {
            syntheticWebView = WKWebView(
                frame: .zero,
                configuration: syntheticConfiguration
            )
            syntheticWebViewUsesSameController =
                syntheticWebView?.configuration
                .webExtensionController === controller
            webViewWarnings.append(
                "Hidden synthetic WKWebView was created without a user-visible window or product tab registration."
            )
        } else {
            webViewBlockingReasons.append(
                "Synthetic WKWebView creation is blocked unless all content-script smoke gates pass."
            )
        }

        if gateDecision.canNavigateSyntheticWebViewNow,
           let syntheticWebView,
           let baseURL = URL(string: htmlFixture.topURLString) {
            syntheticNavigationAttempted = true
            syntheticHTMLLoaded =
                syntheticWebView.loadHTMLString(
                    htmlFixture.topHTML,
                    baseURL: baseURL
                ) != nil
            webViewWarnings.append(
                "Synthetic HTML navigation was started only on the hidden synthetic WebView."
            )
        } else {
            webViewBlockingReasons.append(
                "Synthetic HTML navigation is blocked unless its explicit DEBUG/internal flag passes."
            )
        }

        let webViewResult =
            ChromeMV3ContentScriptSmokeReportGenerator
            .syntheticWebViewResult(
                syntheticConfigurationCreated:
                    syntheticConfiguration != nil,
                syntheticConfigurationAttached:
                    syntheticConfigurationAttached,
                syntheticConfigurationUsesSameController:
                    syntheticConfigurationUsesSameController,
                syntheticWebViewCreated: syntheticWebView != nil,
                syntheticWebViewUsesSameController:
                    syntheticWebViewUsesSameController,
                syntheticNavigationAttempted:
                    syntheticNavigationAttempted,
                syntheticHTMLLoaded: syntheticHTMLLoaded,
                userScriptCount: userScriptCount,
                blockingReasons:
                    gateDecision.blockingReasons
                        + webViewBlockingReasons,
                warnings: webViewWarnings
            )

        let observationScope =
            ChromeMV3ContentScriptObservationStrategyScope
            .contentScriptSmoke(
                explicitTestDOMInspectionAllowed:
                    explicitTestDOMInspectionAllowed,
                sameControllerSyntheticConfiguration:
                    syntheticConfigurationUsesSameController,
                syntheticNavigationAllowed: syntheticNavigationAttempted,
                productNormalTabAttachmentCount:
                    liveNormalTabAttachmentSnapshot?
                    .attachedConfigurationCount ?? 0
            )
        let observationStrategies =
            ChromeMV3ContentScriptObservationStrategyClassifier
            .classifyAll(scope: observationScope)
        let testDOMInspectionClassification = observationStrategies
            .first { $0.strategy == .testDOMInspection }
        let frameObservationReason =
            testDOMInspectionClassification?.reason
                ?? "No test DOM inspection strategy classification was available."
        let observation: ChromeMV3ContentScriptSmokeObservationResult
        if gateDecision.canRunContentScriptSmokeNow == false {
            let records =
                ChromeMV3ContentScriptFrameObservationModel
                .blockedOrUnverifiedRecords(
                    matrix: frameMatrix,
                    strategy: .none,
                    eligibleState: .blocked,
                    reason:
                        "No WebKit-owned content-script observation is attempted while the smoke gate is blocked."
                )
            observation =
                ChromeMV3ContentScriptSmokeReportGenerator
                .observationResult(
                    state: .blocked,
                    strategy: .none,
                    frameResults: records,
                    blockedReasons: gateDecision.blockingReasons,
                    unverifiedNotes: [
                        "No WebKit-owned content-script observation is attempted while the smoke gate is blocked.",
                    ]
                )
        } else if testDOMInspectionClassification?
            .allowedInThisPrompt != true {
            let records =
                ChromeMV3ContentScriptFrameObservationModel
                .blockedOrUnverifiedRecords(
                    matrix: frameMatrix,
                    strategy: .testDOMInspection,
                    eligibleState: .blocked,
                    reason: frameObservationReason
                )
            observation =
                ChromeMV3ContentScriptSmokeReportGenerator
                .observationResult(
                    state: .blocked,
                    strategy: .testDOMInspection,
                    frameResults: records,
                    blockedReasons: [frameObservationReason],
                    unverifiedNotes: [
                        "testDOMInspection is the only currently allowed observation strategy, and it is blocked by scope or explicit flag.",
                    ]
                )
        } else {
            let records =
                ChromeMV3ContentScriptFrameObservationModel
                .blockedOrUnverifiedRecords(
                    matrix: frameMatrix,
                    strategy: .testDOMInspection,
                    reason:
                        "Use the async content-script smoke path to wait for navigation completion and perform testDOMInspection."
                )
            observation =
                ChromeMV3ContentScriptSmokeReportGenerator
                .observationResult(
                    state: .unverified,
                    strategy: .testDOMInspection,
                    frameResults: records,
                    blockedReasons:
                        syntheticNavigationAttempted
                            ? []
                            : [
                                "No forbidden Sumi script injection, add-user-script path, script handler, or JS bridge is used to inspect page state.",
                                "The harness does not claim marker execution without a safe WebKit-owned observation channel.",
                            ],
                    unverifiedNotes: [
                        "WebKit-owned content-script execution is not claimed unless a marker is observed without forbidden Sumi injection.",
                    ]
                )
        }

        syntheticWebView = nil
        syntheticConfiguration?.webExtensionController = nil
        syntheticConfiguration = nil

        if tearDownLoadedContextAndControllerAfterRun {
            _ = controllerLoadOwner?.tearDown()
            _ = detachedContextOwner?.tearDown()
            _ = emptyControllerOwner?.tearDown(trigger: .explicitReset)
        }

        return ChromeMV3ContentScriptSmokeReportGenerator.makeReport(
            gateDecision: gateDecision,
            frameMatrixResult: frameMatrix,
            syntheticHTMLFixture: htmlFixture,
            syntheticWebViewResult: webViewResult,
            observationResult: observation,
            observationStrategyClassifications:
                observationStrategies
        )
    }

    @MainActor
    static func runWithTestDOMInspection(
        scenarioID: String = "runtime-content-script-smoke",
        fixtureID: String? = nil,
        candidate: ChromeMV3RewrittenVariantCandidate,
        extensionsModuleEnabled: Bool,
        explicitInternalContentScriptSmokeAllowed: Bool,
        explicitSyntheticWebViewCreationAllowed: Bool,
        explicitSyntheticNavigationAllowed: Bool,
        explicitTestDOMInspectionAllowed: Bool,
        objectAcceptanceReport:
            ChromeMV3WebKitObjectAcceptanceReport?,
        runtimeBridgeReadinessReport:
            ChromeMV3RuntimeBridgeReadinessReport?,
        emptyControllerOwner:
            ChromeMV3EmptyControllerOwner?,
        detachedContextOwner:
            ChromeMV3DetachedContextOwner?,
        controllerLoadOwner:
            ChromeMV3ControllerLoadOwner?,
        liveNormalTabAttachmentSnapshot:
            ChromeMV3LiveNormalTabAttachmentRecorderSnapshot? = nil,
        tearDownLoadedContextAndControllerAfterRun: Bool = true
    ) async -> ChromeMV3ContentScriptSmokeReport {
        let rootPath = URL(
            fileURLWithPath: candidate.rewrittenVariantRootPath,
            isDirectory: true
        ).standardizedFileURL.path
        let loadDiagnostics = controllerLoadOwner?.diagnostics()
        let controller = emptyControllerOwner?.controller
        let context = detachedContextOwner?.detachedContext
        let accepted =
            objectAcceptanceReport?.objectAcceptedByWebKit == true
        let detachedAvailable =
            context != nil
                || isSet(loadDiagnostics?.contextLoadedIntoController)
        let sameController =
            controller != nil
                && context?.webExtensionController === controller
                && isSet(loadDiagnostics?.contextLoadedIntoController)
        let policy = ChromeMV3ContentScriptSmokeFixturePolicy.evaluate(
            generatedRewrittenRootPath: rootPath,
            acceptedWebExtensionObjectAvailable: accepted,
            detachedContextCreated: detachedAvailable
        )
        let scenario = ChromeMV3ContentScriptSmokeScenario(
            scenarioID: scenarioID,
            fixtureID:
                fixtureID
                    ?? "content-script-smoke-fixture:\(candidate.id)",
            extensionID:
                objectAcceptanceReport?.generatedBundleID
                    ?? candidate.id,
            profileID:
                loadDiagnostics?
                .gateDecision
                .input
                .profileIdentifier
                    ?? "unknown-profile"
        )
        let gateInput = ChromeMV3ContentScriptSmokeGateInput(
            scenario: scenario,
            generatedRewrittenRootPath: rootPath,
            extensionsModuleEnabled: extensionsModuleEnabled,
            explicitInternalContentScriptSmokeAllowed:
                explicitInternalContentScriptSmokeAllowed,
            explicitSyntheticWebViewCreationAllowed:
                explicitSyntheticWebViewCreationAllowed,
            explicitSyntheticNavigationAllowed:
                explicitSyntheticNavigationAllowed,
            explicitTestDOMInspectionAllowed:
                explicitTestDOMInspectionAllowed,
            acceptedWebExtensionObjectAvailable: accepted,
            detachedContextAvailable: detachedAvailable,
            loadedContextAvailable:
                isSet(loadDiagnostics?.contextLoadedIntoController),
            sameControllerAvailable: sameController,
            contentScriptFixturePolicy: policy,
            controllerLoadGateDecision: loadDiagnostics?.gateDecision,
            controllerLoadOwnerDiagnostics: loadDiagnostics,
            liveNormalTabAttachmentSnapshot:
                liveNormalTabAttachmentSnapshot,
            runtimeBridgeReadinessReport:
                runtimeBridgeReadinessReport,
            requestedProductRuntimeExposure: false,
            requestedExtensionCodeExecution: false,
            requestedUserScriptRegistration: false,
            requestedNativeMessagingLaunch: false,
            requestedServiceWorkerWake: false,
            requestedRuntimeDispatch: false,
            requestedProductUI: false
        )
        let gateDecision = ChromeMV3ContentScriptSmokeGate.evaluate(
            input: gateInput
        )
        let frameMatrix = ChromeMV3ContentScriptFrameMatrix.evaluate(
            scenarioID: scenarioID,
            manifestSummary: policy.manifestSummary
        )
        let htmlFixture = ChromeMV3ContentScriptSyntheticHTMLFixture.generate(
            matrix: frameMatrix
        )

        var syntheticConfiguration: WKWebViewConfiguration?
        var syntheticWebView: WKWebView?
        var syntheticConfigurationAttached = false
        var syntheticConfigurationUsesSameController = false
        var syntheticWebViewUsesSameController = false
        var syntheticNavigationAttempted = false
        var syntheticHTMLLoaded = false
        var userScriptCount = 0
        var webViewWarnings: [String] = []
        var webViewBlockingReasons: [String] = []
        var navigationObserver:
            ChromeMV3ContentScriptSmokeNavigationObserver?
        var navigation: WKNavigation?

        if gateDecision.canCreateSyntheticConfigurationNow,
           let controller {
            syntheticConfiguration = WKWebViewConfiguration()
            syntheticConfiguration?
                .sumiIsNormalTabWebViewConfiguration = false
            syntheticConfiguration?.webExtensionController = controller
            syntheticConfigurationAttached =
                syntheticConfiguration?.webExtensionController === controller
            syntheticConfigurationUsesSameController =
                syntheticConfigurationAttached && sameController
            userScriptCount =
                syntheticConfiguration?.userContentController
                .userScripts
                .count ?? 0
        } else {
            webViewBlockingReasons.append(
                "Synthetic configuration was not created because the content-script smoke gate is blocked."
            )
        }

        if gateDecision.canCreateSyntheticWebViewNow,
           syntheticConfigurationAttached,
           let syntheticConfiguration,
           let controller {
            syntheticWebView = WKWebView(
                frame: .zero,
                configuration: syntheticConfiguration
            )
            syntheticWebViewUsesSameController =
                syntheticWebView?.configuration
                .webExtensionController === controller
            webViewWarnings.append(
                "Hidden synthetic WKWebView was created without a user-visible window or product tab registration."
            )
        } else {
            webViewBlockingReasons.append(
                "Synthetic WKWebView creation is blocked unless all content-script smoke gates pass."
            )
        }

        if gateDecision.canNavigateSyntheticWebViewNow,
           let syntheticWebView,
           let baseURL = URL(string: htmlFixture.topURLString) {
            syntheticNavigationAttempted = true
            navigationObserver =
                ChromeMV3ContentScriptSmokeNavigationObserver()
            syntheticWebView.navigationDelegate = navigationObserver
            navigation = syntheticWebView.loadHTMLString(
                htmlFixture.topHTML,
                baseURL: baseURL
            )
            syntheticHTMLLoaded = navigation != nil
            webViewWarnings.append(
                "Synthetic HTML navigation was started only on the hidden synthetic WebView."
            )
        } else {
            webViewBlockingReasons.append(
                "Synthetic HTML navigation is blocked unless its explicit DEBUG/internal flag passes."
            )
        }

        let webViewResult =
            ChromeMV3ContentScriptSmokeReportGenerator
            .syntheticWebViewResult(
                syntheticConfigurationCreated:
                    syntheticConfiguration != nil,
                syntheticConfigurationAttached:
                    syntheticConfigurationAttached,
                syntheticConfigurationUsesSameController:
                    syntheticConfigurationUsesSameController,
                syntheticWebViewCreated: syntheticWebView != nil,
                syntheticWebViewUsesSameController:
                    syntheticWebViewUsesSameController,
                syntheticNavigationAttempted:
                    syntheticNavigationAttempted,
                syntheticHTMLLoaded: syntheticHTMLLoaded,
                userScriptCount: userScriptCount,
                blockingReasons:
                    gateDecision.blockingReasons
                        + webViewBlockingReasons,
                warnings: webViewWarnings
            )

        let observationScope =
            ChromeMV3ContentScriptObservationStrategyScope
            .contentScriptSmoke(
                explicitTestDOMInspectionAllowed:
                    explicitTestDOMInspectionAllowed,
                sameControllerSyntheticConfiguration:
                    syntheticConfigurationUsesSameController,
                syntheticNavigationAllowed: syntheticNavigationAttempted,
                productNormalTabAttachmentCount:
                    liveNormalTabAttachmentSnapshot?
                    .attachedConfigurationCount ?? 0
            )
        let observationStrategies =
            ChromeMV3ContentScriptObservationStrategyClassifier
            .classifyAll(scope: observationScope)
        let testDOMInspectionClassification = observationStrategies
            .first { $0.strategy == .testDOMInspection }
        let observation: ChromeMV3ContentScriptSmokeObservationResult
        if gateDecision.canRunContentScriptSmokeNow == false {
            let records =
                ChromeMV3ContentScriptFrameObservationModel
                .blockedOrUnverifiedRecords(
                    matrix: frameMatrix,
                    strategy: .none,
                    eligibleState: .blocked,
                    reason:
                        "No WebKit-owned content-script observation is attempted while the smoke gate is blocked."
                )
            observation =
                ChromeMV3ContentScriptSmokeReportGenerator
                .observationResult(
                    state: .blocked,
                    strategy: .none,
                    frameResults: records,
                    blockedReasons: gateDecision.blockingReasons,
                    unverifiedNotes: [
                        "No WebKit-owned content-script observation is attempted while the smoke gate is blocked.",
                    ]
                )
        } else if testDOMInspectionClassification?
            .allowedInThisPrompt != true {
            let reason =
                testDOMInspectionClassification?.reason
                    ?? "testDOMInspection was not classified as allowed."
            let records =
                ChromeMV3ContentScriptFrameObservationModel
                .blockedOrUnverifiedRecords(
                    matrix: frameMatrix,
                    strategy: .testDOMInspection,
                    eligibleState: .blocked,
                    reason: reason
                )
            observation =
                ChromeMV3ContentScriptSmokeReportGenerator
                .observationResult(
                    state: .blocked,
                    strategy: .testDOMInspection,
                    frameResults: records,
                    blockedReasons: [reason],
                    unverifiedNotes: [
                        "testDOMInspection is blocked by scope or explicit flag.",
                    ]
                )
        } else if let syntheticWebView,
                  let navigationObserver {
            let navigationCompletion =
                await navigationObserver.waitForCompletion(
                    navigation: navigation
                )
            observation =
                await ChromeMV3ContentScriptTestDOMInspection
                .inspect(
                    webView: syntheticWebView,
                    navigationCompletion: navigationCompletion,
                    matrix: frameMatrix
                ).result
        } else {
            let records =
                ChromeMV3ContentScriptFrameObservationModel
                .blockedOrUnverifiedRecords(
                    matrix: frameMatrix,
                    strategy: .testDOMInspection,
                    eligibleState: .unverified,
                    reason:
                        "Synthetic WebView or navigation observer was unavailable for testDOMInspection."
                )
            observation =
                ChromeMV3ContentScriptSmokeReportGenerator
                .observationResult(
                    state: .unverified,
                    strategy: .testDOMInspection,
                    frameResults: records,
                    blockedReasons: [],
                    unverifiedNotes: [
                        "Synthetic WebView or navigation observer was unavailable for testDOMInspection.",
                    ]
                )
        }

        syntheticWebView?.navigationDelegate = nil
        syntheticWebView = nil
        syntheticConfiguration?.webExtensionController = nil
        syntheticConfiguration = nil

        if tearDownLoadedContextAndControllerAfterRun {
            _ = controllerLoadOwner?.tearDown()
            _ = detachedContextOwner?.tearDown()
            _ = emptyControllerOwner?.tearDown(trigger: .explicitReset)
        }

        return ChromeMV3ContentScriptSmokeReportGenerator.makeReport(
            gateDecision: gateDecision,
            frameMatrixResult: frameMatrix,
            syntheticHTMLFixture: htmlFixture,
            syntheticWebViewResult: webViewResult,
            observationResult: observation,
            observationStrategyClassifications:
                observationStrategies
        )
    }
}
#endif

private func intValue(_ value: Any?) -> Int? {
    if let int = value as? Int {
        return int
    }
    if let double = value as? Double {
        return Int(double)
    }
    if let number = value as? NSNumber {
        return number.intValue
    }
    return nil
}

private func stringValue(_ value: Any?) -> String? {
    value as? String
}

private func boolValue(_ value: Any?) -> Bool? {
    if let bool = value as? Bool {
        return bool
    }
    if let number = value as? NSNumber {
        return number.boolValue
    }
    return nil
}

private func stringArray(_ value: Any?) -> [String] {
    (value as? [String] ?? []).filter { $0.isEmpty == false }
}

private func dictionaryValue(_ value: Any?) -> [String: Any]? {
    value as? [String: Any]
}

private func uniqueSorted<T: Hashable & Comparable>(_ values: [T]) -> [T] {
    Array(Set(values)).sorted()
}

private func uniqueSorted(_ values: [Bool]) -> [Bool] {
    Array(Set(values)).sorted {
        ($0 ? 1 : 0) < ($1 ? 1 : 0)
    }
}

private func uniqueSorted(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

private func isBroadPattern(_ pattern: String) -> Bool {
    pattern == "<all_urls>"
        || pattern == "*://*/*"
        || pattern == "http://*/*"
        || pattern == "https://*/*"
}

private func isAllowedTestPattern(
    _ pattern: String,
    options: ChromeMV3ContentScriptSmokeFixturePolicyOptions
) -> Bool {
    if isBroadPattern(pattern) {
        return options.allowBroadPatternsForExplicitTestFixture
    }
    guard let host = hostFromMatchPattern(pattern) else { return false }
    return options.allowedTestOriginHosts.contains(host)
}

private func hostFromMatchPattern(_ pattern: String) -> String? {
    parseMatchPattern(pattern)?.host
}

private func isSet(_ value: Bool?) -> Bool {
    value ?? false
}

private func parseMatchPattern(
    _ pattern: String
) -> (scheme: String, host: String, path: String)? {
    guard let separator = pattern.range(of: "://") else { return nil }
    let scheme = String(pattern[..<separator.lowerBound])
    let remainder = pattern[separator.upperBound...]
    let hostAndPath = remainder.split(
        separator: "/",
        maxSplits: 1,
        omittingEmptySubsequences: false
    )
    guard let hostPart = hostAndPath.first, hostPart.isEmpty == false else {
        return nil
    }
    let path = hostAndPath.count > 1
        ? "/" + String(hostAndPath[1])
        : "/*"
    return (scheme, String(hostPart), path)
}

private extension ChromeMV3ControllerLoadGateDecision {
    func contentScriptSmokeSummaryLikeReportSummary()
        -> ChromeMV3ControllerLoadGateReportSummary
    {
        ChromeMV3ControllerLoadGateReportSummary(
            reportID: "controller-load-gate:\(input.candidateID)",
            reportFileName:
                ChromeMV3ControllerLoadGateReportWriter.reportFileName,
            candidateID: input.candidateID,
            minimalFixtureLoadSafe:
                input.minimalInertFixturePolicy
                .loadSafeForMinimalInertFixture,
            canLoadContextIntoControllerNow:
                canLoadContextIntoControllerNow,
            loadAttemptAllowed: loadAttemptAllowed,
            controllerLoadAttempted: false,
            contextLoadedIntoController: false,
            runtimeLoadable: false,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            canExecuteExtensionCodeNow: false
        )
    }
}
