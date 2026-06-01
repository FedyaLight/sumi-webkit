//
//  ChromeMV3ContentScriptProductAttachment.swift
//  Sumi
//
//  Developer-preview Chrome MV3 static content-script attachment model.
//  This file keeps public product runtime off: it attaches only manifest
//  declared scripts to explicitly preflighted normal-tab configurations.
//

import CryptoKit
import Foundation

#if canImport(WebKit)
import ObjectiveC.runtime
import WebKit
#endif

enum ChromeMV3ContentScriptBlockedReason:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case activeTabMissing
    case contentScriptGateBlocked
    case cssUnsupported
    case dynamicScriptingBlocked
    case extensionDisabled
    case frameBehaviorUnsupported
    case generatedBundleMissing
    case hostPermissionMissing
    case manifestContentScriptInvalid
    case missingCSSFile
    case missingJSFile
    case moduleDisabled
    case noEligibleDeclaredContentScript
    case normalTabGeneralRuntimeUnavailable
    case productGateBlocked
    case publicProductUnavailable
    case tabSurfaceIneligible
    case teardownPending
    case unsafeCSSPath
    case unsafeJSPath
    case unsupportedMatchPattern
    case unsupportedRunAt
    case unsupportedWorld
    case urlNotMatched
    case webKitUserContentControllerUnavailable

    static func < (
        lhs: ChromeMV3ContentScriptBlockedReason,
        rhs: ChromeMV3ContentScriptBlockedReason
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ContentScriptRunAt:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case documentStart = "document_start"
    case documentEnd = "document_end"
    case documentIdle = "document_idle"

    static func < (
        lhs: ChromeMV3ContentScriptRunAt,
        rhs: ChromeMV3ContentScriptRunAt
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func normalized(
        _ rawValue: String?
    ) -> ChromeMV3ContentScriptRunAt? {
        guard let rawValue, rawValue.isEmpty == false else {
            return .documentIdle
        }
        return ChromeMV3ContentScriptRunAt(rawValue: rawValue)
    }
}

enum ChromeMV3ContentScriptWorld:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case isolated = "ISOLATED"
    case main = "MAIN"

    static func < (
        lhs: ChromeMV3ContentScriptWorld,
        rhs: ChromeMV3ContentScriptWorld
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func normalized(_ rawValue: String?) -> ChromeMV3ContentScriptWorld? {
        guard let rawValue, rawValue.isEmpty == false else {
            return .isolated
        }
        return ChromeMV3ContentScriptWorld(rawValue: rawValue)
    }
}

enum ChromeMV3ContentScriptURLClassification:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case aboutBlank = "about:blank"
    case aboutSrcdoc = "about:srcdoc"
    case blob
    case data
    case extensionPage
    case file
    case httpFamily
    case opaqueAbout
    case other
    case unknown

    static func < (
        lhs: ChromeMV3ContentScriptURLClassification,
        rhs: ChromeMV3ContentScriptURLClassification
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func classify(_ urlString: String?) -> Self {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false
        else { return .unknown }
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased()
        else { return .unknown }
        switch scheme {
        case "http", "https":
            return .httpFamily
        case "about":
            let normalized = raw.lowercased()
            if normalized == "about:blank" { return .aboutBlank }
            if normalized == "about:srcdoc" { return .aboutSrcdoc }
            return .opaqueAbout
        case "data":
            return .data
        case "blob":
            return .blob
        case "file":
            return .file
        case "chrome-extension", "webkit-extension", "safari-web-extension":
            return .extensionPage
        default:
            return .other
        }
    }
}

enum ChromeMV3ContentScriptFrameSupport:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case topFrameOnly

    static func < (
        lhs: ChromeMV3ContentScriptFrameSupport,
        rhs: ChromeMV3ContentScriptFrameSupport
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ContentScriptOriginRelationship:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case mainFrame
    case sameOriginWithParent
    case crossOriginWithParent
    case opaqueOrUnknown
    case parentUnavailable

    static func < (
        lhs: ChromeMV3ContentScriptOriginRelationship,
        rhs: ChromeMV3ContentScriptOriginRelationship
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ContentScriptFrameTarget:
    Codable,
    Equatable,
    Sendable
{
    var tabID: Int
    var frameID: Int
    var parentFrameID: Int?
    var documentID: String
    var navigationSequence: Int
    var urlString: String
    var parentURLString: String?
    var isMainFrame: Bool
    var urlClassification: ChromeMV3ContentScriptURLClassification
    var originRelationship: ChromeMV3ContentScriptOriginRelationship
    var eligibleForCurrentDeveloperPreview: Bool
    var diagnostics: [String]

    static func make(
        tabID: Int,
        frameID: Int,
        parentFrameID: Int? = nil,
        documentID: String,
        navigationSequence: Int,
        urlString: String,
        parentURLString: String? = nil,
        isMainFrame: Bool
    ) -> ChromeMV3ContentScriptFrameTarget {
        let classification =
            ChromeMV3ContentScriptURLClassification.classify(urlString)
        let parentOrigin = parentURLString.flatMap {
            ChromeMV3RuntimeMessagingURL.origin(from: $0)
        }
        let ownOrigin = ChromeMV3RuntimeMessagingURL.origin(from: urlString)
        let relationship: ChromeMV3ContentScriptOriginRelationship
        if isMainFrame {
            relationship = .mainFrame
        } else if parentURLString == nil {
            relationship = .parentUnavailable
        } else if let ownOrigin, let parentOrigin {
            relationship =
                ownOrigin == parentOrigin
                    ? .sameOriginWithParent
                    : .crossOriginWithParent
        } else {
            relationship = .opaqueOrUnknown
        }

        var diagnostics = [
            isMainFrame
                ? "Frame target is the top-level frame."
                : "Frame target is a subframe; developer-preview attachment is blocked until per-frame WebKit routing is proven.",
            "Frame URL classification: \(classification.rawValue).",
            "Frame origin relationship: \(relationship.rawValue).",
        ]
        if classification == .aboutBlank || classification == .aboutSrcdoc {
            diagnostics.append(
                "about: frame targeting requires match_about_blank parent/opener matching and is blocked."
            )
        }
        if classification == .data || classification == .blob {
            diagnostics.append(
                "\(classification.rawValue) frame targeting requires match_origin_as_fallback initiator matching and is blocked."
            )
        }

        return ChromeMV3ContentScriptFrameTarget(
            tabID: tabID,
            frameID: frameID,
            parentFrameID: parentFrameID,
            documentID: documentID,
            navigationSequence: navigationSequence,
            urlString: urlString,
            parentURLString: parentURLString,
            isMainFrame: isMainFrame,
            urlClassification: classification,
            originRelationship: relationship,
            eligibleForCurrentDeveloperPreview:
                isMainFrame && classification == .httpFamily,
            diagnostics: uniqueSortedContentScripts(diagnostics)
        )
    }

    static let unknownMainFrame = ChromeMV3ContentScriptFrameTarget.make(
        tabID: -1,
        frameID: 0,
        documentID: "unknown-document",
        navigationSequence: 0,
        urlString: "about:blank",
        isMainFrame: true
    )
}

enum ChromeMV3ContentScriptCSSPolicyStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case notDeclared
    case blockedScopedRemovalUnavailable
    case supportedPrivateUserStyleSheet

    static func < (
        lhs: ChromeMV3ContentScriptCSSPolicyStatus,
        rhs: ChromeMV3ContentScriptCSSPolicyStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ContentScriptCSSInjectionStrategy:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case none
    case privateWKUserStyleSheet

    static func < (
        lhs: ChromeMV3ContentScriptCSSInjectionStrategy,
        rhs: ChromeMV3ContentScriptCSSInjectionStrategy
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ContentScriptCSSRemovalStrategy:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case none
    case removeAssociatedContentWorldStyleSheets

    static func < (
        lhs: ChromeMV3ContentScriptCSSRemovalStrategy,
        rhs: ChromeMV3ContentScriptCSSRemovalStrategy
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ContentScriptCSSScopeGuarantee:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case none
    case extensionProfileNormalTabMainFrameDocumentNavigation

    static func < (
        lhs: ChromeMV3ContentScriptCSSScopeGuarantee,
        rhs: ChromeMV3ContentScriptCSSScopeGuarantee
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ContentScriptCSSLeakageRisk:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blocked
    case noKnownCrossDocumentLeakageAfterContentWorldTeardown

    static func < (
        lhs: ChromeMV3ContentScriptCSSLeakageRisk,
        rhs: ChromeMV3ContentScriptCSSLeakageRisk
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ContentScriptCSSSupportPolicy:
    Codable,
    Equatable,
    Sendable
{
    var cssContentScriptsAvailableInDeveloperPreview: Bool
    var cssContentScriptsAvailableInPublicProduct: Bool
    var cssInjectionStrategy: ChromeMV3ContentScriptCSSInjectionStrategy
    var cssRemovalStrategy: ChromeMV3ContentScriptCSSRemovalStrategy
    var cssScopeGuarantee: ChromeMV3ContentScriptCSSScopeGuarantee
    var cssLeakageRisk: ChromeMV3ContentScriptCSSLeakageRisk
    var cssBlockedReason: String?
    var diagnostics: [String]

    var allowsManifestCSSAttachment: Bool {
        cssContentScriptsAvailableInDeveloperPreview
            && cssContentScriptsAvailableInPublicProduct == false
            && cssInjectionStrategy == .privateWKUserStyleSheet
            && cssRemovalStrategy == .removeAssociatedContentWorldStyleSheets
            && cssBlockedReason == nil
    }

    static func developerPreviewPrivateUserStyleSheet()
        -> ChromeMV3ContentScriptCSSSupportPolicy
    {
        ChromeMV3ContentScriptCSSSupportPolicy(
            cssContentScriptsAvailableInDeveloperPreview: true,
            cssContentScriptsAvailableInPublicProduct: false,
            cssInjectionStrategy: .privateWKUserStyleSheet,
            cssRemovalStrategy: .removeAssociatedContentWorldStyleSheets,
            cssScopeGuarantee:
                .extensionProfileNormalTabMainFrameDocumentNavigation,
            cssLeakageRisk:
                .noKnownCrossDocumentLeakageAfterContentWorldTeardown,
            cssBlockedReason: nil,
            diagnostics: [
                "Manifest-declared CSS is allowed only in the developer-preview static content-script path.",
                "CSS is installed through extension-owned generated-bundle resources only.",
                "CSS attachment is scoped by the same extension/profile/tab/frame/document/navigation preflight used for static JS content scripts.",
                "Chrome content-script match patterns are translated to WebKit user-content URL patterns; unsupported schemes remain blocked before attachment.",
                "The private WebKit stylesheet is installed at user style level because local SDK verification did not apply author-level user stylesheets; this is not Chrome parity.",
                "WebKit removal uses the extension/profile named WKContentWorld stylesheet teardown path; no DOM style element is left behind by Sumi.",
                "Public product CSS content-script support remains unavailable.",
            ]
        )
    }

    static func blocked(_ reason: String)
        -> ChromeMV3ContentScriptCSSSupportPolicy
    {
        ChromeMV3ContentScriptCSSSupportPolicy(
            cssContentScriptsAvailableInDeveloperPreview: false,
            cssContentScriptsAvailableInPublicProduct: false,
            cssInjectionStrategy: .none,
            cssRemovalStrategy: .none,
            cssScopeGuarantee: .none,
            cssLeakageRisk: .blocked,
            cssBlockedReason: reason,
            diagnostics: [
                reason,
                "Manifest-declared CSS remains blocked because Sumi could not prove scoped WebKit stylesheet removal.",
            ]
        )
    }
}

enum ChromeMV3ContentScriptLifecycleEntrypoint:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case initialPageLoadEligibility
    case navigationStarted
    case navigationCommitted
    case navigationFinished
    case navigationFailed
    case sameDocumentNavigation
    case tabClosed
    case webViewDiscarded
    case webViewReplaced
    case webViewSuspended

    static func < (
        lhs: ChromeMV3ContentScriptLifecycleEntrypoint,
        rhs: ChromeMV3ContentScriptLifecycleEntrypoint
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ContentScriptProductGateRecord:
    Codable,
    Equatable,
    Sendable
{
    var contentScriptAttachmentAvailableInDeveloperPreview: Bool
    var contentScriptAttachmentAvailableInPublicProduct: Bool
    var contentScriptBridgeAvailableInDeveloperPreview: Bool
    var contentScriptBridgeAvailableInPublicProduct: Bool
    var staticContentScriptsAllowed: Bool
    var dynamicScriptingAllowed: Bool
    var normalTabGeneralRuntimeAvailable: Bool
    var contentScriptBlockedReason: String?
    var blockers: [ChromeMV3ContentScriptBlockedReason]
    var diagnostics: [String]

    var allowsStaticContentScriptAttachment: Bool {
        contentScriptAttachmentAvailableInDeveloperPreview
            && contentScriptBridgeAvailableInDeveloperPreview
            && staticContentScriptsAllowed
            && blockers.isEmpty
    }

    static func defaultBlocked() -> ChromeMV3ContentScriptProductGateRecord {
        ChromeMV3ContentScriptProductGateRecord(
            contentScriptAttachmentAvailableInDeveloperPreview: false,
            contentScriptAttachmentAvailableInPublicProduct: false,
            contentScriptBridgeAvailableInDeveloperPreview: false,
            contentScriptBridgeAvailableInPublicProduct: false,
            staticContentScriptsAllowed: false,
            dynamicScriptingAllowed: false,
            normalTabGeneralRuntimeAvailable: false,
            contentScriptBlockedReason:
                "Content-script attachment requires an explicit developer-preview gate.",
            blockers: [
                .contentScriptGateBlocked,
                .dynamicScriptingBlocked,
                .normalTabGeneralRuntimeUnavailable,
                .publicProductUnavailable,
            ],
            diagnostics: [
                "Content-script attachment is blocked by default.",
                "Public product content-script attachment remains unavailable.",
                "Dynamic scripting remains blocked.",
                "General normal-tab runtime remains unavailable.",
            ]
        )
    }

    static func developerPreviewAllowed(
        normalTabRuntimeBridgeScopedToContentScriptsOnly: Bool = true
    ) -> ChromeMV3ContentScriptProductGateRecord {
        ChromeMV3ContentScriptProductGateRecord(
            contentScriptAttachmentAvailableInDeveloperPreview: true,
            contentScriptAttachmentAvailableInPublicProduct: false,
            contentScriptBridgeAvailableInDeveloperPreview: true,
            contentScriptBridgeAvailableInPublicProduct: false,
            staticContentScriptsAllowed: true,
            dynamicScriptingAllowed: false,
            normalTabGeneralRuntimeAvailable: false,
            contentScriptBlockedReason: nil,
            blockers:
                normalTabRuntimeBridgeScopedToContentScriptsOnly
                    ? []
                    : [.normalTabGeneralRuntimeUnavailable],
            diagnostics: [
                "Static manifest-declared content scripts are allowed only in developer-preview scope.",
                "The normal-tab bridge is scoped to content-script endpoints only.",
                "Public product content-script attachment remains unavailable.",
                "Dynamic scripting remains blocked.",
                "General normal-tab runtime remains unavailable.",
            ]
        )
    }
}

struct ChromeMV3ContentScriptCSSResourceRecord:
    Codable,
    Equatable,
    Sendable
{
    var resourceID: String
    var extensionID: String
    var profileID: String
    var contentScriptIndex: Int
    var cssIndex: Int
    var injectionOrder: Int
    var cssFilePath: String
    var generatedBundlePath: String?
    var fileExists: Bool
    var pathSafe: Bool
    var contentByteCount: Int?
    var contentSHA256: String?
    var matches: [String]
    var excludeMatches: [String]
    var includeGlobs: [String]
    var excludeGlobs: [String]
    var runAt: ChromeMV3ContentScriptRunAt?
    var world: ChromeMV3ContentScriptWorld?
    var allFrames: Bool
    var matchAboutBlank: Bool
    var matchOriginAsFallback: Bool
    var blockers: [ChromeMV3ContentScriptBlockedReason]
    var diagnostics: [String]

    var validForAttachment: Bool {
        pathSafe && fileExists && blockers.isEmpty
    }
}

struct ChromeMV3DeclaredContentScriptAttachmentRecord:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var contentScriptIndex: Int
    var contentScriptID: String
    var generatedBundleRootPath: String
    var jsFiles: [String]
    var cssFiles: [String]
    var matches: [String]
    var excludeMatches: [String]
    var includeGlobs: [String]
    var excludeGlobs: [String]
    var runAt: ChromeMV3ContentScriptRunAt?
    var allFrames: Bool
    var allFramesDeclared: Bool
    var frameSupport: ChromeMV3ContentScriptFrameSupport
    var multiFrameDeferred: Bool
    var matchAboutBlank: Bool
    var matchOriginAsFallback: Bool
    var world: ChromeMV3ContentScriptWorld?
    var cssPolicyStatus: ChromeMV3ContentScriptCSSPolicyStatus
    var cssResources: [ChromeMV3ContentScriptCSSResourceRecord]
    var validatedJSFilePaths: [String]
    var validatedCSSFilePaths: [String]
    var supported: Bool
    var blockers: [ChromeMV3ContentScriptBlockedReason]
    var diagnostics: [String]

    var canAttachIfURLAndPermissionMatch: Bool {
        supported && blockers.isEmpty
    }

    func matchesURL(_ urlString: String) -> Bool {
        targetDecision(urlString: urlString).matched
    }

    func targetDecision(
        urlString: String
    ) -> ChromeMV3DeclaredContentScriptTargetDecision {
        var diagnostics: [String] = []
        var unsupportedButNonBlocking: [String] = []
        var excludeIgnoredForTarget: [String] = []
        var targetBlockers = blockers
        let targetClassification =
            ChromeMV3ContentScriptURLClassification.classify(urlString)

        let matchPatterns = matches.map(ChromeMV3ContentScriptMatchPattern.init)
        let excludePatterns =
            excludeMatches.map(ChromeMV3ContentScriptMatchPattern.init)

        for pattern in matchPatterns
            where pattern.nonBlockingForNonFileTarget
                && targetClassification != .file
        {
            unsupportedButNonBlocking.append(pattern.rawValue)
            diagnostics.append(
                "content_scripts[\(contentScriptIndex)] match pattern \(pattern.rawValue) is Chrome-valid file-scheme syntax and is ignored for non-file target \(urlString)."
            )
        }

        for pattern in excludePatterns
            where pattern.nonBlockingForNonFileTarget
                && targetClassification != .file
        {
            excludeIgnoredForTarget.append(pattern.rawValue)
            unsupportedButNonBlocking.append(pattern.rawValue)
            diagnostics.append(
                "content_scripts[\(contentScriptIndex)] exclude_match \(pattern.rawValue) cannot match non-file target \(urlString) and was ignored for this target."
            )
        }

        for pattern in matchPatterns where pattern.status == .invalid {
            targetBlockers.append(.unsupportedMatchPattern)
            diagnostics.append(contentsOf: pattern.diagnostics)
        }
        for pattern in matchPatterns
            where pattern.status == .unsupportedNeedsVerification
        {
            targetBlockers.append(.unsupportedMatchPattern)
            diagnostics.append(contentsOf: pattern.diagnostics)
        }
        for pattern in excludePatterns where pattern.status == .invalid {
            targetBlockers.append(.unsupportedMatchPattern)
            diagnostics.append(contentsOf: pattern.diagnostics)
        }
        for pattern in excludePatterns
            where pattern.status == .unsupportedNeedsVerification
        {
            targetBlockers.append(.unsupportedMatchPattern)
            diagnostics.append(contentsOf: pattern.diagnostics)
        }

        let includedByMatch =
            matches.isEmpty == false
                && matchPatterns.contains { $0.matches(urlString) }
        let includedByGlob =
            includeGlobs.isEmpty
                || includeGlobs.contains {
                    ChromeMV3ContentScriptGlob($0).matches(urlString)
                }
        let excludedByMatch =
            excludePatterns.contains { $0.matches(urlString) }
        let excludedByGlob =
            excludeGlobs.contains {
                ChromeMV3ContentScriptGlob($0).matches(urlString)
            }
        let excluded = excludedByMatch || excludedByGlob
        let normalizedBlockers = Array(Set(targetBlockers)).sorted()
        let matched =
            includedByMatch
                && includedByGlob
                && excluded == false
                && normalizedBlockers.isEmpty
                && canAttachIfURLAndPermissionMatch

        if allFramesDeclared {
            diagnostics.append(
                "content_scripts[\(contentScriptIndex)] declares all_frames=true; Sumi records this as topFrameOnly and defers subframe attachment."
            )
        }
        if matchAboutBlank {
            diagnostics.append(
                "content_scripts[\(contentScriptIndex)] match_about_blank remains blocked."
            )
        }
        if matchOriginAsFallback {
            diagnostics.append(
                "content_scripts[\(contentScriptIndex)] match_origin_as_fallback remains blocked."
            )
        }
        diagnostics.append(
            "content_scripts[\(contentScriptIndex)] target decision: matched=\(matched), matchPatternMatched=\(includedByMatch), includeGlobsMatched=\(includedByGlob), excluded=\(excluded), blockers=\(normalizedBlockers.map(\.rawValue).joined(separator: ",")), frameSupport=\(frameSupport.rawValue), multiFrameDeferred=\(multiFrameDeferred)."
        )

        return ChromeMV3DeclaredContentScriptTargetDecision(
            contentScriptIndex: contentScriptIndex,
            contentScriptID: contentScriptID,
            matches: matches,
            excludeMatches: excludeMatches,
            includeGlobs: includeGlobs,
            excludeGlobs: excludeGlobs,
            runAt: runAt,
            allFramesDeclared: allFramesDeclared,
            frameSupport: frameSupport,
            multiFrameDeferred: multiFrameDeferred,
            matchAboutBlank: matchAboutBlank,
            matchOriginAsFallback: matchOriginAsFallback,
            world: world,
            jsFiles: jsFiles,
            cssFiles: cssFiles,
            targetURL: urlString,
            matchPatternMatched: includedByMatch,
            includeGlobsMatched: includedByGlob,
            excluded: excluded,
            matched: matched,
            excludeIgnoredForTarget:
                uniqueSortedContentScripts(excludeIgnoredForTarget),
            unsupportedButNonBlocking:
                uniqueSortedContentScripts(unsupportedButNonBlocking),
            blockers: normalizedBlockers,
            blocker: normalizedBlockers.first?.rawValue,
            diagnostics: uniqueSortedContentScripts(diagnostics)
        )
    }
}

struct ChromeMV3DeclaredContentScriptTargetDecision:
    Codable,
    Equatable,
    Sendable
{
    var contentScriptIndex: Int
    var contentScriptID: String
    var matches: [String]
    var excludeMatches: [String]
    var includeGlobs: [String]
    var excludeGlobs: [String]
    var runAt: ChromeMV3ContentScriptRunAt?
    var allFramesDeclared: Bool
    var frameSupport: ChromeMV3ContentScriptFrameSupport
    var multiFrameDeferred: Bool
    var matchAboutBlank: Bool
    var matchOriginAsFallback: Bool
    var world: ChromeMV3ContentScriptWorld?
    var jsFiles: [String]
    var cssFiles: [String]
    var targetURL: String
    var matchPatternMatched: Bool
    var includeGlobsMatched: Bool
    var excluded: Bool
    var matched: Bool
    var excludeIgnoredForTarget: [String]
    var unsupportedButNonBlocking: [String]
    var blockers: [ChromeMV3ContentScriptBlockedReason]
    var blocker: String?
    var diagnostics: [String]
}

struct ChromeMV3ContentScriptAttachmentPlan:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var generatedBundleRootPath: String
    var cssSupportPolicy: ChromeMV3ContentScriptCSSSupportPolicy
    var declaredScripts: [ChromeMV3DeclaredContentScriptAttachmentRecord]
    var diagnostics: [String]

    var supportedScripts: [ChromeMV3DeclaredContentScriptAttachmentRecord] {
        declaredScripts.filter(\.canAttachIfURLAndPermissionMatch)
    }

    static func make(
        manifest: ChromeMV3Manifest,
        generatedBundleRootURL: URL,
        extensionID: String,
        profileID: String,
        cssSupportPolicy: ChromeMV3ContentScriptCSSSupportPolicy =
            .developerPreviewPrivateUserStyleSheet()
    ) -> ChromeMV3ContentScriptAttachmentPlan {
        let root = generatedBundleRootURL.standardizedFileURL
        let records = manifest.contentScripts.enumerated().map { index, script in
            record(
                script,
                index: index,
                root: root,
                extensionID: extensionID,
                profileID: profileID,
                cssSupportPolicy: cssSupportPolicy
            )
        }
        return ChromeMV3ContentScriptAttachmentPlan(
            extensionID: extensionID,
            profileID: profileID,
            generatedBundleRootPath: root.path,
            cssSupportPolicy: cssSupportPolicy,
            declaredScripts: records.sorted {
                $0.contentScriptIndex < $1.contentScriptIndex
            },
            diagnostics:
                uniqueSortedContentScripts(
                    records.flatMap(\.diagnostics)
                        + cssSupportPolicy.diagnostics
                        + [
                            "Attachment plan was built only from manifest-declared content_scripts.",
                            "scripting.executeScript remains outside this plan.",
                            "scripting.insertCSS remains outside this plan.",
                        ]
                )
        )
    }

    private static func record(
        _ script: ChromeMV3ContentScript,
        index: Int,
        root: URL,
        extensionID: String,
        profileID: String,
        cssSupportPolicy: ChromeMV3ContentScriptCSSSupportPolicy
    ) -> ChromeMV3DeclaredContentScriptAttachmentRecord {
        var blockers: [ChromeMV3ContentScriptBlockedReason] = []
        var diagnostics: [String] = []
        let normalizedJS = script.js.map {
            ChromeMV3ContentScriptResourcePath.normalize($0)
        }
        var validatedJSPaths: [String] = []
        var cssResources: [ChromeMV3ContentScriptCSSResourceRecord] = []
        var validatedCSSPaths: [String] = []

        if script.matches.isEmpty {
            blockers.append(.manifestContentScriptInvalid)
            diagnostics.append("content_scripts[\(index)] has no matches.")
        }
        if normalizedJS.isEmpty && script.css.isEmpty {
            blockers.append(.manifestContentScriptInvalid)
            diagnostics.append(
                "content_scripts[\(index)] has no JS or CSS files."
            )
        }
        for normalized in normalizedJS {
            switch normalized {
            case .success(let relativePath):
                let validation = ChromeMV3ContentScriptResourcePath
                    .validateExistingFile(
                        relativePath,
                        root: root
                    )
                if validation.valid {
                    validatedJSPaths.append(relativePath)
                } else {
                    blockers.append(validation.reason ?? .missingJSFile)
                    diagnostics.append(contentsOf: validation.diagnostics)
                }
            case .failure(let diagnostic):
                blockers.append(.unsafeJSPath)
                diagnostics.append(diagnostic.message)
            }
        }
        for (cssIndex, rawPath) in script.css.enumerated() {
            let resource = cssResourceRecord(
                rawPath: rawPath,
                cssIndex: cssIndex,
                script: script,
                contentScriptIndex: index,
                root: root,
                extensionID: extensionID,
                profileID: profileID,
                cssSupportPolicy: cssSupportPolicy
            )
            cssResources.append(resource)
            blockers.append(contentsOf: resource.blockers)
            diagnostics.append(contentsOf: resource.diagnostics)
            if resource.validForAttachment {
                validatedCSSPaths.append(resource.cssFilePath)
            }
        }
        for pattern in script.matches {
            let parsed = ChromeMV3ContentScriptMatchPattern(pattern)
            if parsed.status == .invalid
                || parsed.status == .unsupportedNeedsVerification
            {
                blockers.append(.unsupportedMatchPattern)
                diagnostics.append(contentsOf: parsed.diagnostics)
            } else if parsed.nonBlockingForNonFileTarget {
                diagnostics.append(
                    "content_scripts[\(index)] file match pattern \(pattern) is Chrome-valid syntax, but actual file:// content-script attachment remains blocked by frame preflight."
                )
            }
        }
        for pattern in script.excludeMatches {
            let parsed = ChromeMV3ContentScriptMatchPattern(pattern)
            if parsed.status == .invalid
                || parsed.status == .unsupportedNeedsVerification
            {
                blockers.append(.unsupportedMatchPattern)
                diagnostics.append(contentsOf: parsed.diagnostics)
            } else if parsed.nonBlockingForNonFileTarget {
                diagnostics.append(
                    "content_scripts[\(index)] file exclude_match \(pattern) is recorded and ignored only for non-file targets where it cannot match."
                )
            }
        }
        guard let runAt = ChromeMV3ContentScriptRunAt.normalized(script.runAt)
        else {
            blockers.append(.unsupportedRunAt)
            diagnostics.append(
                "content_scripts[\(index)] run_at \(script.runAt ?? "nil") is unsupported."
            )
            return baseRecord(
                script,
                index: index,
                root: root,
                extensionID: extensionID,
                profileID: profileID,
                runAt: nil,
                world: ChromeMV3ContentScriptWorld.normalized(script.world),
                cssResources: cssResources,
                validatedJSPaths: validatedJSPaths,
                validatedCSSPaths: validatedCSSPaths,
                blockers: blockers,
                diagnostics: diagnostics
            )
        }
        guard let world = ChromeMV3ContentScriptWorld.normalized(script.world)
        else {
            blockers.append(.unsupportedWorld)
            diagnostics.append(
                "content_scripts[\(index)] world \(script.world ?? "nil") is unsupported."
            )
            return baseRecord(
                script,
                index: index,
                root: root,
                extensionID: extensionID,
                profileID: profileID,
                runAt: runAt,
                world: nil,
                cssResources: cssResources,
                validatedJSPaths: validatedJSPaths,
                validatedCSSPaths: validatedCSSPaths,
                blockers: blockers,
                diagnostics: diagnostics
            )
        }
        if world == .main {
            blockers.append(.unsupportedWorld)
            diagnostics.append(
                "content_scripts[\(index)] MAIN world is blocked by Sumi developer-preview policy; isolated named WKContentWorld remains the only supported path."
            )
            diagnostics.append(
                "MAIN world is not silently downgraded to ISOLATED."
            )
        }
        if script.allFrames {
            diagnostics.append(
                "content_scripts[\(index)] all_frames=true is accepted only as top-frame-only in the developer-preview attachment model; subframes remain deferred."
            )
        }
        if script.matchAboutBlank {
            blockers.append(.frameBehaviorUnsupported)
            diagnostics.append(
                "content_scripts[\(index)] match_about_blank is blocked because parent/opener frame URL matching is not available from the current safe WebKit attachment path."
            )
        }
        if script.matchOriginAsFallback {
            blockers.append(.frameBehaviorUnsupported)
            diagnostics.append(
                "content_scripts[\(index)] match_origin_as_fallback is blocked because initiator-origin fallback matching is not available from the current safe WebKit attachment path."
            )
        }

        return baseRecord(
            script,
            index: index,
            root: root,
            extensionID: extensionID,
            profileID: profileID,
            runAt: runAt,
            world: world,
            cssResources: cssResources,
            validatedJSPaths: validatedJSPaths,
            validatedCSSPaths: validatedCSSPaths,
            blockers: blockers,
            diagnostics: diagnostics
        )
    }

    private static func cssResourceRecord(
        rawPath: String,
        cssIndex: Int,
        script: ChromeMV3ContentScript,
        contentScriptIndex: Int,
        root: URL,
        extensionID: String,
        profileID: String,
        cssSupportPolicy: ChromeMV3ContentScriptCSSSupportPolicy
    ) -> ChromeMV3ContentScriptCSSResourceRecord {
        let resourceID = stableIDContentScripts(
            prefix: "declared-content-script-css",
            parts: [
                profileID,
                extensionID,
                String(contentScriptIndex),
                String(cssIndex),
                rawPath,
            ]
        )
        let normalized = ChromeMV3ContentScriptResourcePath.normalize(rawPath)
        var blockers: [ChromeMV3ContentScriptBlockedReason] = []
        var diagnostics: [String] = []
        var normalizedPath = rawPath
        var generatedBundlePath: String?
        var fileExists = false
        var pathSafe = false
        var contentByteCount: Int?
        var contentSHA256: String?

        switch normalized {
        case .success(let path):
            normalizedPath = path
            let validation = ChromeMV3ContentScriptResourcePath
                .validateExistingCSSFile(path, root: root)
            fileExists = validation.fileExists
            pathSafe = validation.pathSafe
            generatedBundlePath = validation.fileURL?.path
            contentByteCount = validation.byteCount
            contentSHA256 = validation.sha256
            if validation.valid == false {
                blockers.append(validation.reason ?? .missingCSSFile)
            } else if cssSupportPolicy.allowsManifestCSSAttachment == false {
                blockers.append(.cssUnsupported)
                diagnostics.append(
                    cssSupportPolicy.cssBlockedReason
                        ?? "Manifest CSS is blocked by CSS support policy."
                )
            }
            diagnostics.append(contentsOf: validation.diagnostics)
        case .failure(let diagnostic):
            blockers.append(.unsafeCSSPath)
            diagnostics.append(diagnostic.message)
        }

        if cssSupportPolicy.allowsManifestCSSAttachment {
            diagnostics.append(
                "content_scripts[\(contentScriptIndex)] CSS file \(normalizedPath) is eligible for developer-preview WebKit user stylesheet attachment after preflight."
            )
        } else if let reason = cssSupportPolicy.cssBlockedReason {
            diagnostics.append(reason)
        }

        return ChromeMV3ContentScriptCSSResourceRecord(
            resourceID: resourceID,
            extensionID: extensionID,
            profileID: profileID,
            contentScriptIndex: contentScriptIndex,
            cssIndex: cssIndex,
            injectionOrder: cssIndex,
            cssFilePath: normalizedPath,
            generatedBundlePath: generatedBundlePath,
            fileExists: fileExists,
            pathSafe: pathSafe,
            contentByteCount: contentByteCount,
            contentSHA256: contentSHA256,
            matches: script.matches.sorted(),
            excludeMatches: script.excludeMatches.sorted(),
            includeGlobs: script.includeGlobs.sorted(),
            excludeGlobs: script.excludeGlobs.sorted(),
            runAt: ChromeMV3ContentScriptRunAt.normalized(script.runAt),
            world: ChromeMV3ContentScriptWorld.normalized(script.world),
            allFrames: script.allFrames,
            matchAboutBlank: script.matchAboutBlank,
            matchOriginAsFallback: script.matchOriginAsFallback,
            blockers: Array(Set(blockers)).sorted(),
            diagnostics: uniqueSortedContentScripts(diagnostics)
        )
    }

    private static func baseRecord(
        _ script: ChromeMV3ContentScript,
        index: Int,
        root: URL,
        extensionID: String,
        profileID: String,
        runAt: ChromeMV3ContentScriptRunAt?,
        world: ChromeMV3ContentScriptWorld?,
        cssResources: [ChromeMV3ContentScriptCSSResourceRecord],
        validatedJSPaths: [String],
        validatedCSSPaths: [String],
        blockers: [ChromeMV3ContentScriptBlockedReason],
        diagnostics: [String]
    ) -> ChromeMV3DeclaredContentScriptAttachmentRecord {
        let normalizedBlockers = Array(Set(blockers)).sorted()
        return ChromeMV3DeclaredContentScriptAttachmentRecord(
            extensionID: extensionID,
            profileID: profileID,
            contentScriptIndex: index,
            contentScriptID:
                stableIDContentScripts(
                    prefix: "declared-content-script",
                    parts: [profileID, extensionID, String(index)]
                ),
            generatedBundleRootPath: root.path,
            jsFiles:
                script.js.compactMap {
                    try? ChromeMV3ContentScriptResourcePath
                        .normalize($0).get()
                },
            cssFiles:
                script.css.compactMap {
                    try? ChromeMV3ContentScriptResourcePath
                        .normalize($0).get()
                },
            matches: script.matches.sorted(),
            excludeMatches: script.excludeMatches.sorted(),
            includeGlobs: script.includeGlobs.sorted(),
            excludeGlobs: script.excludeGlobs.sorted(),
            runAt: runAt,
            allFrames: script.allFrames,
            allFramesDeclared: script.allFrames,
            frameSupport: .topFrameOnly,
            multiFrameDeferred: script.allFrames,
            matchAboutBlank: script.matchAboutBlank,
            matchOriginAsFallback: script.matchOriginAsFallback,
            world: world,
            cssPolicyStatus:
                script.css.isEmpty
                    ? .notDeclared
                    : (
                        cssResources.allSatisfy(\.validForAttachment)
                            ? .supportedPrivateUserStyleSheet
                            : .blockedScopedRemovalUnavailable
                    ),
            cssResources: cssResources.sorted {
                $0.injectionOrder < $1.injectionOrder
            },
            validatedJSFilePaths: validatedJSPaths.sorted(),
            validatedCSSFilePaths: validatedCSSPaths,
            supported: normalizedBlockers.isEmpty,
            blockers: normalizedBlockers,
            diagnostics:
                uniqueSortedContentScripts(
                    diagnostics
                        + [
                            script.css.isEmpty
                                ? "content_scripts[\(index)] declares no CSS files."
                                : "content_scripts[\(index)] CSS resources are recorded in deterministic manifest order.",
                            normalizedBlockers.isEmpty
                                ? "content_scripts[\(index)] is eligible for URL and permission preflight."
                                : "content_scripts[\(index)] is blocked before URL and permission preflight.",
                        ]
                )
        )
    }
}

struct ChromeMV3NormalTabContentScriptPreflightInput:
    Sendable
{
    var moduleEnabled: Bool
    var extensionEnabled: Bool
    var productRuntimePreflightAllowsNormalTabAttachment: Bool
    var contentScriptGate: ChromeMV3ContentScriptProductGateRecord
    var attachmentPlan: ChromeMV3ContentScriptAttachmentPlan
    var permissionBroker: ChromeMV3PermissionBroker
    var tabID: Int
    var frameID: Int
    var documentID: String
    var navigationSequence: Int
    var urlString: String
    var frameTarget: ChromeMV3ContentScriptFrameTarget = .unknownMainFrame
    var tabSurface: ChromeMV3WebViewSurface
    var generatedBundleActive: Bool
    var webKitUserContentControllerAvailable: Bool
    var teardownPending: Bool
}

struct ChromeMV3NormalTabContentScriptPreflight:
    Codable,
    Equatable,
    Sendable
{
    var profileID: String
    var extensionID: String
    var tabID: Int
    var frameID: Int
    var documentID: String
    var navigationSequence: Int
    var urlString: String
    var frameTarget: ChromeMV3ContentScriptFrameTarget
    var canAttachDeclaredContentScriptsNow: Bool
    var canExposeContentScriptBridgeNow: Bool
    var canRegisterEndpointNow: Bool
    var matchedScripts: [ChromeMV3DeclaredContentScriptAttachmentRecord]
    var skippedScripts: [ChromeMV3DeclaredContentScriptAttachmentRecord]
    var targetDecisions: [ChromeMV3DeclaredContentScriptTargetDecision]
    var contentScriptGate: ChromeMV3ContentScriptProductGateRecord
    var hostAccessDecision: ChromeMV3HostAccessDecision
    var blockers: [ChromeMV3ContentScriptBlockedReason]
    var diagnostics: [String]
}

enum ChromeMV3NormalTabContentScriptPreflightEvaluator {
    static func evaluate(
        input: ChromeMV3NormalTabContentScriptPreflightInput
    ) -> ChromeMV3NormalTabContentScriptPreflight {
        var blockers: [ChromeMV3ContentScriptBlockedReason] = []
        var diagnostics: [String] = []
        let frameTarget =
            input.frameTarget.tabID == -1
                ? ChromeMV3ContentScriptFrameTarget.make(
                    tabID: input.tabID,
                    frameID: input.frameID,
                    documentID: input.documentID,
                    navigationSequence: input.navigationSequence,
                    urlString: input.urlString,
                    isMainFrame: input.frameID == 0
                )
                : input.frameTarget

        if input.moduleEnabled == false {
            blockers.append(.moduleDisabled)
            diagnostics.append(
                "The extensions module is disabled; content-script attachment is blocked."
            )
        }
        if input.extensionEnabled == false {
            blockers.append(.extensionDisabled)
            diagnostics.append(
                "The extension is disabled; content-script attachment is blocked."
            )
        }
        if input.productRuntimePreflightAllowsNormalTabAttachment == false {
            blockers.append(.productGateBlocked)
            diagnostics.append(
                "Product runtime preflight did not allow this normal-tab attachment."
            )
        }
        if input.contentScriptGate.allowsStaticContentScriptAttachment == false {
            blockers.append(.contentScriptGateBlocked)
            diagnostics.append(contentsOf: input.contentScriptGate.diagnostics)
        }
        if input.generatedBundleActive == false {
            blockers.append(.generatedBundleMissing)
            diagnostics.append(
                "An active generated bundle is required for declared content scripts."
            )
        }
        if input.tabSurface.isRealNormalBrowsingSurfaceForChromeMV3Attachment
            == false
        {
            blockers.append(.tabSurfaceIneligible)
            diagnostics.append(
                "Surface \(input.tabSurface.rawValue) is not eligible for content-script attachment."
            )
        }
        if input.webKitUserContentControllerAvailable == false {
            blockers.append(.webKitUserContentControllerUnavailable)
            diagnostics.append(
                "WKUserContentController is unavailable for this WebView configuration."
            )
        }
        if input.teardownPending {
            blockers.append(.teardownPending)
            diagnostics.append(
                "Content-script teardown is pending; new attachment is blocked."
            )
        }
        diagnostics.append(contentsOf: frameTarget.diagnostics)
        if frameTarget.eligibleForCurrentDeveloperPreview == false {
            blockers.append(.frameBehaviorUnsupported)
            diagnostics.append(
                "Frame target is not eligible for the current developer-preview content-script attachment path."
            )
        }

        let hostDecision = input.permissionBroker.hostAccessDecision(
            url: input.urlString,
            tabID: input.tabID
        )
        if hostDecision.hasHostAccess == false {
            switch hostDecision.missingReason {
            case .activeTabMissing:
                blockers.append(.activeTabMissing)
            default:
                blockers.append(.hostPermissionMissing)
            }
            diagnostics.append(contentsOf: hostDecision.diagnostics)
        }

        let targetDecisions =
            input.attachmentPlan.declaredScripts.map {
                $0.targetDecision(urlString: input.urlString)
            }
            .sorted { $0.contentScriptIndex < $1.contentScriptIndex }
        let targetDecisionByID = Dictionary(
            uniqueKeysWithValues:
                targetDecisions.map { ($0.contentScriptID, $0) }
        )
        let matched = input.attachmentPlan.declaredScripts.filter { script in
            script.canAttachIfURLAndPermissionMatch
                && targetDecisionByID[script.contentScriptID]?.matched == true
        }
        let skipped = input.attachmentPlan.declaredScripts.filter {
            matched.contains($0) == false
        }
        if matched.isEmpty {
            blockers.append(.noEligibleDeclaredContentScript)
            if targetDecisions.contains(where: { $0.matched }) == false {
                blockers.append(.urlNotMatched)
            }
            diagnostics.append(
                "No declared content script matched the target URL with current support and permission gates."
            )
        }
        for script in skipped {
            diagnostics.append(contentsOf: script.diagnostics)
        }
        for decision in targetDecisions {
            diagnostics.append(contentsOf: decision.diagnostics)
        }

        let normalizedBlockers = Array(Set(blockers)).sorted()
        let canAttach = normalizedBlockers.isEmpty && matched.isEmpty == false
        let canExposeBridge =
            canAttach && matched.contains {
                $0.validatedJSFilePaths.isEmpty == false
            }
        return ChromeMV3NormalTabContentScriptPreflight(
            profileID: input.attachmentPlan.profileID,
            extensionID: input.attachmentPlan.extensionID,
            tabID: input.tabID,
            frameID: input.frameID,
            documentID: input.documentID,
            navigationSequence: input.navigationSequence,
            urlString: input.urlString,
            frameTarget: frameTarget,
            canAttachDeclaredContentScriptsNow: canAttach,
            canExposeContentScriptBridgeNow: canExposeBridge,
            canRegisterEndpointNow: canExposeBridge,
            matchedScripts: matched.sorted {
                $0.contentScriptIndex < $1.contentScriptIndex
            },
            skippedScripts: skipped.sorted {
                $0.contentScriptIndex < $1.contentScriptIndex
            },
            targetDecisions: targetDecisions,
            contentScriptGate: input.contentScriptGate,
            hostAccessDecision: hostDecision,
            blockers: normalizedBlockers,
            diagnostics:
                uniqueSortedContentScripts(
                    diagnostics
                        + input.attachmentPlan.diagnostics
                        + [
                            canAttach
                                ? "Declared content-script preflight passed for this extension/tab/frame/navigation sequence."
                                : "Declared content-script preflight is blocked.",
                            canExposeBridge
                                ? "Content-script JS bridge exposure is allowed for matched JS resources."
                                : "Content-script JS bridge exposure is unavailable because no matched JS resource passed validation.",
                            "Manifest CSS, when present, follows the same preflight and is not a scripting.insertCSS path.",
                            "scripting.executeScript remains blocked and is not part of this preflight.",
                            "scripting.insertCSS remains blocked and is not part of this preflight.",
                        ]
                )
        )
    }
}

enum ChromeMV3ContentScriptEndpointLifecycleState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case attached
    case detached
    case disabledWhileAttached
    case endpointRegistered
    case listenerRegistered
    case navigationCommitted
    case navigationFailed
    case navigationFinished
    case navigationInvalidated
    case navigationStarted
    case resetWhileAttached
    case sameDocumentNavigation
    case tabClosed
    case teardownComplete
    case uninstalledWhileAttached
    case webViewDiscarded
    case webViewReplaced
    case webViewSuspended

    static func < (
        lhs: ChromeMV3ContentScriptEndpointLifecycleState,
        rhs: ChromeMV3ContentScriptEndpointLifecycleState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ContentScriptEndpointLifecycleRecord:
    Codable,
    Equatable,
    Sendable
{
    var sequence: Int
    var endpointID: String
    var state: ChromeMV3ContentScriptEndpointLifecycleState
    var reason: String
}

struct ChromeMV3ContentScriptSenderMetadata:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var tabID: Int
    var frameID: Int
    var parentFrameID: Int?
    var documentID: String
    var navigationSequence: Int
    var lifecycleSessionID: String
    var endpointID: String
    var url: String?
    var origin: String?
    var urlRedacted: Bool
    var originRedacted: Bool
    var redactionReason: String?
}

struct ChromeMV3ContentScriptEndpointMetadata:
    Codable,
    Equatable,
    Sendable
{
    var endpointID: String
    var extensionID: String
    var profileID: String
    var tabID: Int
    var frameID: Int
    var parentFrameID: Int?
    var documentID: String
    var navigationSequence: Int
    var frameScope: ChromeMV3ContentScriptFrameSupport
    var url: String?
    var origin: String?
    var urlRedacted: Bool
    var originRedacted: Bool
    var redactionReason: String?
    var hostPermissionStatus: ChromeMV3PermissionBrokerDecisionStatus
    var hostPermissionSource: ChromeMV3PermissionBrokerGrantSource
    var matchedHostPatterns: [String]
    var allowedByActiveTab: Bool
    var teardownPolicy: String
    var active: Bool
    var messageListenerRegistered: Bool
    var connectListenerRegistered: Bool
    var attachedScriptIDs: [String]
    var attachedCSSResourceIDs: [String]
}

struct ChromeMV3ContentScriptEndpointRecord:
    Codable,
    Equatable,
    Sendable
{
    var endpointID: String
    var extensionID: String
    var profileID: String
    var tabID: Int
    var frameID: Int
    var documentID: String
    var navigationSequence: Int
    var frameTarget: ChromeMV3ContentScriptFrameTarget
    var frameScope: ChromeMV3ContentScriptFrameSupport
    var attachedScriptIDs: [String]
    var attachedCSSResourceIDs: [String]
    var messageListenerRegistered: Bool
    var connectListenerRegistered: Bool
    var endpointState: ChromeMV3ContentScriptEndpointLifecycleState
    var senderMetadata: ChromeMV3ContentScriptSenderMetadata
    var hostPermissionStatus: ChromeMV3PermissionBrokerDecisionStatus
    var hostPermissionSource: ChromeMV3PermissionBrokerGrantSource
    var matchedHostPatterns: [String]
    var allowedByActiveTab: Bool
    var teardownPolicy: String
    var teardownReason: String?
    var diagnostics: [String]

    var active: Bool {
        switch endpointState {
        case .attached, .endpointRegistered, .listenerRegistered,
             .navigationCommitted:
            return teardownReason == nil
        default:
            return false
        }
    }

    var metadata: ChromeMV3ContentScriptEndpointMetadata {
        ChromeMV3ContentScriptEndpointMetadata(
            endpointID: endpointID,
            extensionID: extensionID,
            profileID: profileID,
            tabID: tabID,
            frameID: frameID,
            parentFrameID: senderMetadata.parentFrameID,
            documentID: documentID,
            navigationSequence: navigationSequence,
            frameScope: frameScope,
            url: senderMetadata.url,
            origin: senderMetadata.origin,
            urlRedacted: senderMetadata.urlRedacted,
            originRedacted: senderMetadata.originRedacted,
            redactionReason: senderMetadata.redactionReason,
            hostPermissionStatus: hostPermissionStatus,
            hostPermissionSource: hostPermissionSource,
            matchedHostPatterns: matchedHostPatterns,
            allowedByActiveTab: allowedByActiveTab,
            teardownPolicy: teardownPolicy,
            active: active,
            messageListenerRegistered: messageListenerRegistered,
            connectListenerRegistered: connectListenerRegistered,
            attachedScriptIDs: attachedScriptIDs,
            attachedCSSResourceIDs: attachedCSSResourceIDs
        )
    }
}

struct ChromeMV3ContentScriptModeledPortRecord:
    Codable,
    Equatable,
    Sendable
{
    var portID: String
    var endpointID: String
    var name: String
    var opened: Bool
    var disconnectReason: String?
    var sender: ChromeMV3ContentScriptSenderMetadata
    var popupOptionsMessageCount: Int
    var contentScriptMessageCount: Int
    var disconnectNotifiedPopupOptions: Bool
    var disconnectNotifiedContentScript: Bool
    var diagnostics: [String]
}

enum ChromeMV3ContentScriptPortMessageDirection:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case popupOptionsToContentScript
    case contentScriptToPopupOptions

    static func < (
        lhs: ChromeMV3ContentScriptPortMessageDirection,
        rhs: ChromeMV3ContentScriptPortMessageDirection
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ContentScriptPortMessageRecord:
    Codable,
    Equatable,
    Sendable
{
    var sequence: Int
    var portID: String
    var endpointID: String
    var direction: ChromeMV3ContentScriptPortMessageDirection
    var payload: ChromeMV3StorageValue
    var delivered: Bool
    var diagnostics: [String]
}

struct ChromeMV3ContentScriptPortDeliveryResult:
    Codable,
    Equatable,
    Sendable
{
    var portID: String
    var endpointID: String?
    var direction: ChromeMV3ContentScriptPortMessageDirection
    var delivered: Bool
    var disconnectReason: String?
    var payload: ChromeMV3StorageValue?
    var diagnostics: [String]
}

struct ChromeMV3ContentScriptEndpointRegistrySummary:
    Codable,
    Equatable,
    Sendable
{
    var endpointCount: Int
    var activeEndpointCount: Int
    var cssAttachmentCount: Int
    var activeCSSAttachmentCount: Int
    var messageListenerEndpointCount: Int
    var connectListenerEndpointCount: Int
    var portCount: Int
    var activePortCount: Int
    var disconnectedPortCount: Int
    var portMessageCount: Int
    var endpointIDs: [String]
    var portIDs: [String]
    var tabsWithEndpoints: [Int]
    var endpointMetadata: [ChromeMV3ContentScriptEndpointMetadata]
    var lifecycleStates: [ChromeMV3ContentScriptEndpointLifecycleState]
    var portDisconnectReasons: [String]
    var diagnostics: [String]
}

enum ChromeMV3ContentScriptEndpointLookupClassification:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case found
    case endpointMissing
    case wrongFrame
    case wrongTab

    static func < (
        lhs: ChromeMV3ContentScriptEndpointLookupClassification,
        rhs: ChromeMV3ContentScriptEndpointLookupClassification
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ContentScriptEndpointLookupResult:
    Codable,
    Equatable,
    Sendable
{
    var classification: ChromeMV3ContentScriptEndpointLookupClassification
    var endpoint: ChromeMV3ContentScriptEndpointRecord?
    var diagnostics: [String]
}

final class ChromeMV3ContentScriptEndpointRegistry {
    private var endpoints: [ChromeMV3ContentScriptEndpointRecord] = []
    private var lifecycleRecords:
        [ChromeMV3ContentScriptEndpointLifecycleRecord] = []
    private var ports: [ChromeMV3ContentScriptModeledPortRecord] = []
    private var portMessages: [ChromeMV3ContentScriptPortMessageRecord] = []
    private var nextSequence = 1

    init() {}

    var summary: ChromeMV3ContentScriptEndpointRegistrySummary {
        let active = endpoints.filter(\.active)
        let activePorts = ports.filter(\.opened)
        return ChromeMV3ContentScriptEndpointRegistrySummary(
            endpointCount: endpoints.count,
            activeEndpointCount: active.count,
            cssAttachmentCount:
                endpoints.flatMap(\.attachedCSSResourceIDs).count,
            activeCSSAttachmentCount:
                active.flatMap(\.attachedCSSResourceIDs).count,
            messageListenerEndpointCount:
                active.filter(\.messageListenerRegistered).count,
            connectListenerEndpointCount:
                active.filter(\.connectListenerRegistered).count,
            portCount: ports.count,
            activePortCount: activePorts.count,
            disconnectedPortCount: ports.filter { $0.opened == false }.count,
            portMessageCount: portMessages.count,
            endpointIDs: endpoints.map(\.endpointID).sorted(),
            portIDs: ports.map(\.portID).sorted(),
            tabsWithEndpoints:
                Array(Set(active.map(\.tabID))).sorted(),
            endpointMetadata:
                endpoints.map(\.metadata).sorted {
                    $0.endpointID < $1.endpointID
                },
            lifecycleStates:
                Array(Set(lifecycleRecords.map(\.state))).sorted(),
            portDisconnectReasons:
                uniqueSortedContentScripts(
                    ports.compactMap(\.disconnectReason)
                ),
            diagnostics:
                uniqueSortedContentScripts(
                    endpoints.flatMap(\.diagnostics)
                        + lifecycleRecords.map(\.reason)
                        + ports.flatMap(\.diagnostics)
                        + portMessages.flatMap(\.diagnostics)
                        + [
                            "Content-script endpoint registry is explicit and instance-local.",
                            "No tab scanning or background scheduling is performed.",
                        ]
                )
        )
    }

    var lifecycleSnapshot: [ChromeMV3ContentScriptEndpointLifecycleRecord] {
        lifecycleRecords
    }

    @discardableResult
    func registerEndpoint(
        preflight: ChromeMV3NormalTabContentScriptPreflight,
        messageListenerRegistered: Bool = false,
        connectListenerRegistered: Bool = false
    ) -> ChromeMV3ContentScriptEndpointRecord? {
        guard preflight.canRegisterEndpointNow else { return nil }
        let endpointID = stableIDContentScripts(
            prefix: "content-script-endpoint",
            parts: [
                preflight.profileID,
                preflight.extensionID,
                String(preflight.tabID),
                String(preflight.frameID),
                preflight.documentID,
                String(preflight.navigationSequence),
            ]
        )
        invalidateDuplicate(endpointID: endpointID)
        let record = ChromeMV3ContentScriptEndpointRecord(
            endpointID: endpointID,
            extensionID: preflight.extensionID,
            profileID: preflight.profileID,
            tabID: preflight.tabID,
            frameID: preflight.frameID,
            documentID: preflight.documentID,
            navigationSequence: preflight.navigationSequence,
            frameTarget: preflight.frameTarget,
            frameScope: .topFrameOnly,
            attachedScriptIDs:
                preflight.matchedScripts.map(\.contentScriptID).sorted(),
            attachedCSSResourceIDs:
                preflight.matchedScripts
                    .flatMap(\.cssResources)
                    .filter(\.validForAttachment)
                    .map(\.resourceID)
                    .sorted(),
            messageListenerRegistered: messageListenerRegistered,
            connectListenerRegistered: connectListenerRegistered,
            endpointState:
                (messageListenerRegistered || connectListenerRegistered)
                    ? .listenerRegistered
                    : .endpointRegistered,
            senderMetadata: ChromeMV3ContentScriptSenderMetadata(
                extensionID: preflight.extensionID,
                profileID: preflight.profileID,
                tabID: preflight.tabID,
                frameID: preflight.frameID,
                parentFrameID: preflight.frameTarget.parentFrameID,
                documentID: preflight.documentID,
                navigationSequence: preflight.navigationSequence,
                lifecycleSessionID:
                    stableIDContentScripts(
                        prefix: "content-script-lifecycle-session",
                        parts: [
                            preflight.profileID,
                            preflight.extensionID,
                            String(preflight.tabID),
                            preflight.documentID,
                            String(preflight.navigationSequence),
                        ]
                    ),
                endpointID: endpointID,
                url:
                    preflight.hostAccessDecision.hasHostAccess
                        ? preflight.urlString
                        : nil,
                origin:
                    preflight.hostAccessDecision.hasHostAccess
                        ? ChromeMV3RuntimeMessagingURL.origin(
                            from: preflight.urlString
                        )
                        : nil,
                urlRedacted: preflight.hostAccessDecision.hasHostAccess == false,
                originRedacted:
                    preflight.hostAccessDecision.hasHostAccess == false,
                redactionReason:
                    preflight.hostAccessDecision.hasHostAccess
                        ? nil
                        : "URL and origin are redacted because host permission or activeTab access is missing."
            ),
            hostPermissionStatus: preflight.hostAccessDecision.status,
            hostPermissionSource: preflight.hostAccessDecision.grantSource,
            matchedHostPatterns:
                preflight.hostAccessDecision.matchingHostPatterns,
            allowedByActiveTab:
                preflight.hostAccessDecision.allowedByActiveTab,
            teardownPolicy:
                "teardown on navigation, tab close, extension disable, uninstall, reset, WebView replacement, WebView suspension, WebView discard, or host-permission revoke",
            teardownReason: nil,
            diagnostics:
                uniqueSortedContentScripts(
                    preflight.diagnostics
                        + [
                            "Content-script endpoint registered for extension/tab/frame/navigation scope.",
                            "Manifest CSS attachment records, if present, are scoped to the same endpoint lifecycle.",
                        ]
                )
        )
        endpoints.append(record)
        appendLifecycle(
            endpointID: endpointID,
            state: .endpointRegistered,
            reason: "Content-script endpoint registered."
        )
        if messageListenerRegistered || connectListenerRegistered {
            appendLifecycle(
                endpointID: endpointID,
                state: .listenerRegistered,
                reason: "Content-script listener registered."
            )
        }
        return record
    }

    func registerRuntimeOnMessageListener(
        extensionID: String,
        profileID: String,
        tabID: Int,
        frameID: Int = 0,
        documentID: String? = nil
    ) {
        updateMatching(
            extensionID: extensionID,
            profileID: profileID,
            tabID: tabID,
            frameID: frameID,
            documentID: documentID
        ) { endpoint in
            endpoint.messageListenerRegistered = true
            endpoint.endpointState = .listenerRegistered
            endpoint.diagnostics.append(
                "runtime.onMessage listener registration observed from content script."
            )
        }
    }

    func registerRuntimeOnConnectListener(
        extensionID: String,
        profileID: String,
        tabID: Int,
        frameID: Int = 0,
        documentID: String? = nil
    ) {
        updateMatching(
            extensionID: extensionID,
            profileID: profileID,
            tabID: tabID,
            frameID: frameID,
            documentID: documentID
        ) { endpoint in
            endpoint.connectListenerRegistered = true
            endpoint.endpointState = .listenerRegistered
            endpoint.diagnostics.append(
                "runtime.onConnect listener registration observed from content script."
            )
        }
    }

    func listenerRegistrySnapshot(
        extensionID: String,
        profileID: String
    ) -> ChromeMV3RuntimeModelListenerRegistrySnapshot {
        var modeled: [ChromeMV3RuntimeModelListenerEndpoint] = []
        for endpoint in endpoints where endpoint.active
            && endpoint.extensionID == extensionID
            && endpoint.profileID == profileID
        {
            if endpoint.messageListenerRegistered {
                modeled.append(
                    modelEndpoint(
                        endpoint: endpoint,
                        surface: .tabsMessageContentScript,
                        handlerOutcome: .response(
                            .object([
                                "ok": .bool(true),
                                "target": .string("contentScriptEndpoint"),
                                "endpointID": .string(endpoint.endpointID),
                                "tabId": .number(Double(endpoint.tabID)),
                                "frameId": .number(Double(endpoint.frameID)),
                                "documentId": .string(endpoint.documentID),
                                "navigationSequence": .number(
                                    Double(endpoint.navigationSequence)
                                ),
                                "listenerCount": .number(1),
                                "sender": senderMetadataPayload(
                                    endpoint.senderMetadata
                                ),
                            ]),
                            diagnostics: [
                                "tabs.sendMessage reached a registered content-script endpoint."
                            ]
                        )
                    )
                )
                modeled.append(
                    modelEndpoint(
                        endpoint: endpoint,
                        surface: .runtimeOnMessageContentScript,
                        handlerOutcome: .response(
                            .object([
                                "ok": .bool(true),
                                "target": .string("contentScriptEndpoint"),
                                "endpointID": .string(endpoint.endpointID),
                                "tabId": .number(Double(endpoint.tabID)),
                                "frameId": .number(Double(endpoint.frameID)),
                                "documentId": .string(endpoint.documentID),
                                "navigationSequence": .number(
                                    Double(endpoint.navigationSequence)
                                ),
                                "listenerCount": .number(1),
                                "sender": senderMetadataPayload(
                                    endpoint.senderMetadata
                                ),
                            ]),
                            diagnostics: [
                                "runtime.onMessage in the content-script endpoint can receive modeled tab messages."
                            ]
                        )
                    )
                )
            }
            if endpoint.connectListenerRegistered {
                modeled.append(
                    modelEndpoint(
                        endpoint: endpoint,
                        surface: .tabsConnectContentScript,
                        handlerOutcome: nil
                    )
                )
                modeled.append(
                    modelEndpoint(
                        endpoint: endpoint,
                        surface: .runtimeOnConnectContentScript,
                        handlerOutcome: nil
                    )
                )
            }
        }
        return ChromeMV3RuntimeModelListenerRegistrySnapshot.make(
            extensionID: extensionID,
            profileID: profileID,
            endpoints: modeled,
            diagnostics: [
                "Content-script endpoint registry adapted active listeners for popup/options dispatch.",
                "Endpoints are scoped by extension, profile, tab, frame, document, and navigation sequence.",
            ]
        )
    }

    private func senderMetadataPayload(
        _ sender: ChromeMV3ContentScriptSenderMetadata
    ) -> ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "id": .string(sender.extensionID),
            "extensionID": .string(sender.extensionID),
            "profileID": .string(sender.profileID),
            "tabId": .number(Double(sender.tabID)),
            "frameId": .number(Double(sender.frameID)),
            "documentId": .string(sender.documentID),
            "navigationSequence": .number(Double(sender.navigationSequence)),
            "lifecycleSessionID": .string(sender.lifecycleSessionID),
            "endpointID": .string(sender.endpointID),
            "urlRedacted": .bool(sender.urlRedacted),
            "originRedacted": .bool(sender.originRedacted),
        ]
        if let parentFrameID = sender.parentFrameID {
            object["parentFrameId"] = .number(Double(parentFrameID))
        }
        if let url = sender.url {
            object["url"] = .string(url)
        }
        if let origin = sender.origin {
            object["origin"] = .string(origin)
        }
        if let redactionReason = sender.redactionReason {
            object["redactionReason"] = .string(redactionReason)
        }
        return .object(object)
    }

    func targetEndpointLookup(
        extensionID: String,
        profileID: String,
        tabID: Int,
        frameID: Int?,
        documentID: String?
    ) -> ChromeMV3ContentScriptEndpointLookupResult {
        let scoped = endpoints.filter {
            $0.active
                && $0.extensionID == extensionID
                && $0.profileID == profileID
        }
        let inTab = scoped.filter { $0.tabID == tabID }
        let inFrame = inTab.filter { frameID == nil || $0.frameID == frameID }
        let matched = inFrame.filter {
            documentID == nil || $0.documentID == documentID
        }
        if let endpoint = (
            matched
            .sorted {
                if $0.navigationSequence != $1.navigationSequence {
                    return $0.navigationSequence > $1.navigationSequence
                }
                return $0.endpointID < $1.endpointID
            }
            .first
        )
        {
            return ChromeMV3ContentScriptEndpointLookupResult(
                classification: .found,
                endpoint: endpoint,
                diagnostics: [
                    "Endpoint lookup classification: found.",
                    "Selected content-script endpoint \(endpoint.endpointID) for tab=\(tabID), frame=\(frameID.map { String($0) } ?? "any"), document=\(documentID ?? "any").",
                ]
            )
        }

        let classification:
            ChromeMV3ContentScriptEndpointLookupClassification
        if scoped.isEmpty {
            classification = .endpointMissing
        } else if inTab.isEmpty {
            classification = .wrongTab
        } else if frameID != nil && inFrame.isEmpty {
            classification = .wrongFrame
        } else {
            classification = .endpointMissing
        }
        return ChromeMV3ContentScriptEndpointLookupResult(
            classification: classification,
            endpoint: nil,
            diagnostics: [
                "Endpoint lookup classification: \(classification.rawValue).",
                "No active content-script endpoint matched tab=\(tabID), frame=\(frameID.map { String($0) } ?? "any"), document=\(documentID ?? "any").",
            ]
        )
    }

    func targetEndpoint(
        extensionID: String,
        profileID: String,
        tabID: Int,
        frameID: Int?,
        documentID: String?
    ) -> ChromeMV3ContentScriptEndpointRecord? {
        targetEndpointLookup(
            extensionID: extensionID,
            profileID: profileID,
            tabID: tabID,
            frameID: frameID,
            documentID: documentID
        ).endpoint
    }

    func openPortIfAvailable(
        extensionID: String,
        profileID: String,
        tabID: Int,
        frameID: Int?,
        documentID: String?,
        name: String
    ) -> ChromeMV3ContentScriptModeledPortRecord? {
        guard let endpoint = targetEndpoint(
            extensionID: extensionID,
            profileID: profileID,
            tabID: tabID,
            frameID: frameID,
            documentID: documentID
        ), endpoint.connectListenerRegistered
        else { return nil }
        let port = ChromeMV3ContentScriptModeledPortRecord(
            portID:
                stableIDContentScripts(
                    prefix: "content-script-port",
                    parts: [
                        endpoint.endpointID,
                        name,
                        String(ports.count + 1),
                    ]
                ),
            endpointID: endpoint.endpointID,
            name: name,
            opened: true,
            disconnectReason: nil,
            sender: endpoint.senderMetadata,
            popupOptionsMessageCount: 0,
            contentScriptMessageCount: 0,
            disconnectNotifiedPopupOptions: false,
            disconnectNotifiedContentScript: false,
            diagnostics: [
                "tabs.connect opened a modeled Port to a registered content-script endpoint.",
                "Port.name and Port.sender metadata were recorded for deterministic delivery.",
                "No service-worker keepalive or native messaging path was used.",
            ]
        )
        ports.append(port)
        return port
    }

    @discardableResult
    func deliverPopupOptionsPortMessage(
        portID: String,
        payload: ChromeMV3StorageValue
    ) -> ChromeMV3ContentScriptPortDeliveryResult {
        deliverPortMessage(
            portID: portID,
            payload: payload,
            direction: .popupOptionsToContentScript
        )
    }

    @discardableResult
    func deliverContentScriptPortMessage(
        portID: String,
        payload: ChromeMV3StorageValue
    ) -> ChromeMV3ContentScriptPortDeliveryResult {
        deliverPortMessage(
            portID: portID,
            payload: payload,
            direction: .contentScriptToPopupOptions
        )
    }

    @discardableResult
    func disconnectPort(
        portID: String,
        reason: String
    ) -> ChromeMV3ContentScriptPortDeliveryResult {
        guard let index = ports.firstIndex(where: { $0.portID == portID })
        else {
            return ChromeMV3ContentScriptPortDeliveryResult(
                portID: portID,
                endpointID: nil,
                direction: .popupOptionsToContentScript,
                delivered: false,
                disconnectReason: "Port not found.",
                payload: nil,
                diagnostics: ["No modeled Port exists for \(portID)."]
            )
        }
        disconnectPort(at: index, reason: reason)
        return ChromeMV3ContentScriptPortDeliveryResult(
            portID: portID,
            endpointID: ports[index].endpointID,
            direction: .popupOptionsToContentScript,
            delivered: false,
            disconnectReason: ports[index].disconnectReason,
            payload: nil,
            diagnostics:
                uniqueSortedContentScripts(
                    ports[index].diagnostics
                        + [
                            "Port disconnect was delivered to both modeled endpoints."
                        ]
                )
        )
    }

    func navigationStarted(
        profileID: String,
        tabID: Int,
        oldNavigationSequence: Int,
        reason: String = "Navigation started."
    ) {
        teardownMatching(
            transitions: [
                (
                    .navigationStarted,
                    reason
                ),
                (
                    .navigationInvalidated,
                    "Navigation invalidated stale content-script endpoints."
                ),
            ],
            profileID: profileID,
            tabID: tabID,
            navigationSequence: oldNavigationSequence
        )
    }

    func navigationCommitted(
        profileID: String,
        tabID: Int,
        navigationSequence: Int,
        reason: String = "Navigation committed."
    ) {
        appendLifecycle(
            endpointID: "tab-\(tabID)-navigation-\(navigationSequence)",
            state: .navigationCommitted,
            reason: reason
        )
    }

    func navigationFinished(
        profileID: String,
        tabID: Int,
        navigationSequence: Int,
        reason: String = "Navigation finished."
    ) {
        _ = profileID
        appendLifecycle(
            endpointID: "tab-\(tabID)-navigation-\(navigationSequence)",
            state: .navigationFinished,
            reason: reason
        )
    }

    func navigationFailed(
        profileID: String,
        tabID: Int,
        navigationSequence: Int,
        reason: String = "Navigation failed."
    ) {
        teardownMatching(
            transitions: [
                (.navigationFailed, reason),
                (
                    .teardownComplete,
                    "Content-script endpoint teardown completed after navigation failure."
                ),
            ],
            profileID: profileID,
            tabID: tabID,
            navigationSequence: navigationSequence
        )
    }

    func sameDocumentNavigation(
        profileID: String,
        tabID: Int,
        navigationSequence: Int,
        reason: String = "Same-document navigation observed."
    ) {
        _ = profileID
        appendLifecycle(
            endpointID: "tab-\(tabID)-navigation-\(navigationSequence)",
            state: .sameDocumentNavigation,
            reason: reason
        )
    }

    func detachForWebViewReplacement(profileID: String, tabID: Int) {
        teardownMatching(
            transitions: [
                (
                    .webViewReplaced,
                    "WebView was replaced while content scripts were attached."
                ),
                (
                    .teardownComplete,
                    "Content-script endpoint teardown completed after WebView replacement."
                ),
            ],
            profileID: profileID,
            tabID: tabID
        )
    }

    func detachForWebViewSuspension(profileID: String, tabID: Int) {
        teardownMatching(
            transitions: [
                (
                    .webViewSuspended,
                    "WebView was suspended while content scripts were attached."
                ),
                (
                    .teardownComplete,
                    "Content-script endpoint teardown completed after WebView suspension."
                ),
            ],
            profileID: profileID,
            tabID: tabID
        )
    }

    func detachForWebViewDiscard(profileID: String, tabID: Int) {
        teardownMatching(
            transitions: [
                (
                    .webViewDiscarded,
                    "WebView was discarded while content scripts were attached."
                ),
                (
                    .teardownComplete,
                    "Content-script endpoint teardown completed after WebView discard."
                ),
            ],
            profileID: profileID,
            tabID: tabID
        )
    }

    func detachForExtensionDisable(
        extensionID: String,
        profileID: String
    ) {
        teardownMatching(
            transitions: [
                (
                    .disabledWhileAttached,
                    "Extension was disabled while content scripts were attached."
                ),
                (
                    .teardownComplete,
                    "Content-script endpoint teardown completed after disable."
                ),
            ],
            extensionID: extensionID,
            profileID: profileID
        )
    }

    func detachForUninstall(extensionID: String, profileID: String) {
        teardownMatching(
            transitions: [
                (
                    .uninstalledWhileAttached,
                    "Extension was uninstalled while content scripts were attached."
                ),
                (
                    .teardownComplete,
                    "Content-script endpoint teardown completed after uninstall."
                ),
            ],
            extensionID: extensionID,
            profileID: profileID
        )
    }

    func detachForReset(profileID: String) {
        teardownMatching(
            transitions: [
                (
                    .resetWhileAttached,
                    "Profile/extension runtime reset while content scripts were attached."
                ),
                (
                    .teardownComplete,
                    "Content-script endpoint teardown completed after reset."
                ),
            ],
            profileID: profileID
        )
    }

    func detachForTabClose(profileID: String, tabID: Int) {
        teardownMatching(
            transitions: [
                (
                    .tabClosed,
                    "Tab was closed."
                ),
                (
                    .teardownComplete,
                    "Content-script endpoint teardown completed after tab close."
                ),
            ],
            profileID: profileID,
            tabID: tabID
        )
    }

    func invalidateForPermissionChange(
        extensionID: String,
        profileID: String,
        permissionBroker: ChromeMV3PermissionBroker,
        reason: String
    ) {
        let matchedIndices = endpoints.indices.filter { index in
            endpoints[index].active
                && endpoints[index].extensionID == extensionID
                && endpoints[index].profileID == profileID
        }
        for index in matchedIndices {
            let decision = permissionBroker.hostAccessDecision(
                url: endpoints[index].frameTarget.urlString,
                tabID: endpoints[index].tabID
            )
            guard decision.hasHostAccess == false else { continue }
            disconnectPorts(
                endpointID: endpoints[index].endpointID,
                reason: reason
            )
            endpoints[index].senderMetadata.url = nil
            endpoints[index].senderMetadata.origin = nil
            endpoints[index].senderMetadata.urlRedacted = true
            endpoints[index].senderMetadata.originRedacted = true
            endpoints[index].senderMetadata.redactionReason =
                "URL and origin were redacted after permission revoke or activeTab expiry."
            endpoints[index].endpointState = .detached
            endpoints[index].teardownReason = reason
            endpoints[index].messageListenerRegistered = false
            endpoints[index].connectListenerRegistered = false
            endpoints[index].diagnostics =
                uniqueSortedContentScripts(
                    endpoints[index].diagnostics
                        + decision.diagnostics
                        + [
                            "Content-script endpoint invalidated by permission state change.",
                            "Sender metadata was redacted before teardown completed.",
                        ]
                )
            appendLifecycle(
                endpointID: endpoints[index].endpointID,
                state: .detached,
                reason: reason
            )
            appendLifecycle(
                endpointID: endpoints[index].endpointID,
                state: .teardownComplete,
                reason: "Content-script endpoint teardown completed after permission state change."
            )
        }
    }

    func tearDownAll(reason: String = "Content-script registry reset.") {
        for index in endpoints.indices where endpoints[index].active {
            disconnectPorts(endpointID: endpoints[index].endpointID, reason: reason)
            endpoints[index].endpointState = .detached
            endpoints[index].teardownReason = reason
            endpoints[index].messageListenerRegistered = false
            endpoints[index].connectListenerRegistered = false
            appendLifecycle(
                endpointID: endpoints[index].endpointID,
                state: .detached,
                reason: reason
            )
            appendLifecycle(
                endpointID: endpoints[index].endpointID,
                state: .teardownComplete,
                reason: "Content-script endpoint teardown completed."
            )
        }
        ports.removeAll()
    }

    private func modelEndpoint(
        endpoint: ChromeMV3ContentScriptEndpointRecord,
        surface: ChromeMV3RuntimeListenerSurfaceKind,
        handlerOutcome: ChromeMV3RuntimeModelHandlerOutcome?
    ) -> ChromeMV3RuntimeModelListenerEndpoint {
        ChromeMV3RuntimeModelListenerEndpoint.make(
            surface:
                ChromeMV3RuntimeListenerSurface.make(
                    surface: surface,
                    extensionID: endpoint.extensionID,
                    profileID: endpoint.profileID,
                    tabID: endpoint.tabID,
                    frameID: endpoint.frameID
                ),
            endpointKind: .contentScriptModel,
            canReceiveModelMessages: true,
            bypassesServiceWorkerWakeForModelOnlyDispatch: true,
            handlerOutcome: handlerOutcome,
            seed: "product-content-script-\(endpoint.endpointID)-\(surface.rawValue)",
            diagnostics: [
                "Product-gated content-script endpoint \(endpoint.endpointID) is active for \(surface.rawValue).",
                "Endpoint is developer-preview gated and not a global normal-tab runtime.",
            ]
        )
    }

    private func updateMatching(
        extensionID: String,
        profileID: String,
        tabID: Int,
        frameID: Int,
        documentID: String?,
        update: (inout ChromeMV3ContentScriptEndpointRecord) -> Void
    ) {
        for index in endpoints.indices {
            guard endpoints[index].active,
                  endpoints[index].extensionID == extensionID,
                  endpoints[index].profileID == profileID,
                  endpoints[index].tabID == tabID,
                  endpoints[index].frameID == frameID,
                  documentID == nil || endpoints[index].documentID == documentID
            else { continue }
            update(&endpoints[index])
            appendLifecycle(
                endpointID: endpoints[index].endpointID,
                state: .listenerRegistered,
                reason: "Content-script listener registration updated."
            )
        }
    }

    private func teardownMatching(
        transitions: [(
            ChromeMV3ContentScriptEndpointLifecycleState,
            String
        )],
        extensionID: String? = nil,
        profileID: String? = nil,
        tabID: Int? = nil,
        navigationSequence: Int? = nil
    ) {
        guard let terminal = transitions.last else { return }
        let matchedIndices = endpoints.indices.filter { index in
            endpoints[index].active
                && (extensionID == nil
                    || endpoints[index].extensionID == extensionID)
                && (profileID == nil
                    || endpoints[index].profileID == profileID)
                && (tabID == nil || endpoints[index].tabID == tabID)
                && (navigationSequence == nil
                    || endpoints[index].navigationSequence
                        == navigationSequence)
        }
        for index in matchedIndices {
            disconnectPorts(
                endpointID: endpoints[index].endpointID,
                reason: terminal.1
            )
            endpoints[index].endpointState = terminal.0
            endpoints[index].teardownReason = terminal.1
            endpoints[index].messageListenerRegistered = false
            endpoints[index].connectListenerRegistered = false
            for transition in transitions {
                appendLifecycle(
                    endpointID: endpoints[index].endpointID,
                    state: transition.0,
                    reason: transition.1
                )
            }
        }
    }

    private func invalidateDuplicate(endpointID: String) {
        for index in endpoints.indices
            where endpoints[index].endpointID == endpointID
                && endpoints[index].active
        {
            endpoints[index].endpointState = .navigationInvalidated
            endpoints[index].teardownReason =
                "Duplicate endpoint registration invalidated stale endpoint."
            disconnectPorts(
                endpointID: endpoints[index].endpointID,
                reason: "Duplicate endpoint registration invalidated stale endpoint."
            )
            appendLifecycle(
                endpointID: endpointID,
                state: .navigationInvalidated,
                reason: "Duplicate endpoint registration invalidated stale endpoint."
            )
        }
    }

    private func deliverPortMessage(
        portID: String,
        payload: ChromeMV3StorageValue,
        direction: ChromeMV3ContentScriptPortMessageDirection
    ) -> ChromeMV3ContentScriptPortDeliveryResult {
        guard let index = ports.firstIndex(where: { $0.portID == portID })
        else {
            return ChromeMV3ContentScriptPortDeliveryResult(
                portID: portID,
                endpointID: nil,
                direction: direction,
                delivered: false,
                disconnectReason: "Port not found.",
                payload: nil,
                diagnostics: ["No modeled Port exists for \(portID)."]
            )
        }
        guard ports[index].opened else {
            return ChromeMV3ContentScriptPortDeliveryResult(
                portID: portID,
                endpointID: ports[index].endpointID,
                direction: direction,
                delivered: false,
                disconnectReason: ports[index].disconnectReason,
                payload: nil,
                diagnostics:
                    uniqueSortedContentScripts(
                        ports[index].diagnostics
                            + [
                                "Port message was rejected because the Port is disconnected."
                            ]
                    )
            )
        }
        guard endpoints.contains(where: {
            $0.endpointID == ports[index].endpointID && $0.active
        }) else {
            disconnectPort(
                at: index,
                reason: "Content-script endpoint is no longer active."
            )
            return ChromeMV3ContentScriptPortDeliveryResult(
                portID: portID,
                endpointID: ports[index].endpointID,
                direction: direction,
                delivered: false,
                disconnectReason: ports[index].disconnectReason,
                payload: nil,
                diagnostics:
                    uniqueSortedContentScripts(
                        ports[index].diagnostics
                            + [
                                "Port message was rejected because the endpoint is stale."
                            ]
                    )
            )
        }

        switch direction {
        case .popupOptionsToContentScript:
            ports[index].popupOptionsMessageCount += 1
        case .contentScriptToPopupOptions:
            ports[index].contentScriptMessageCount += 1
        }
        let message = ChromeMV3ContentScriptPortMessageRecord(
            sequence: nextSequence,
            portID: portID,
            endpointID: ports[index].endpointID,
            direction: direction,
            payload: payload,
            delivered: true,
            diagnostics: [
                "Modeled Port message delivered: \(direction.rawValue)."
            ]
        )
        nextSequence += 1
        portMessages.append(message)
        ports[index].diagnostics.append(
            "Delivered Port message \(direction.rawValue)."
        )
        return ChromeMV3ContentScriptPortDeliveryResult(
            portID: portID,
            endpointID: ports[index].endpointID,
            direction: direction,
            delivered: true,
            disconnectReason: nil,
            payload: payload,
            diagnostics:
                uniqueSortedContentScripts(
                    message.diagnostics
                        + ports[index].diagnostics
                        + [
                            "Delivery is endpoint-modeled and does not wake a service worker.",
                            "No arbitrary scripting.executeScript path was used.",
                        ]
                )
        )
    }

    private func disconnectPorts(endpointID: String, reason: String) {
        for index in ports.indices where ports[index].endpointID == endpointID {
            disconnectPort(at: index, reason: reason)
        }
    }

    private func disconnectPort(at index: Int, reason: String) {
        guard ports.indices.contains(index),
              ports[index].opened
        else { return }
        ports[index].opened = false
        ports[index].disconnectReason = reason
        ports[index].disconnectNotifiedPopupOptions = true
        ports[index].disconnectNotifiedContentScript = true
        ports[index].diagnostics.append(
            "Port disconnected: \(reason)"
        )
    }

    private func appendLifecycle(
        endpointID: String,
        state: ChromeMV3ContentScriptEndpointLifecycleState,
        reason: String
    ) {
        lifecycleRecords.append(
            ChromeMV3ContentScriptEndpointLifecycleRecord(
                sequence: nextSequence,
                endpointID: endpointID,
                state: state,
                reason: reason
            )
        )
        nextSequence += 1
    }
}

enum ChromeMV3ContentScriptRuntimeBridgeBlockedAPI:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case declarativeNetRequest
    case identity
    case nativeMessaging
    case offscreen
    case permissions
    case sidePanel
    case storage
    case tabs
    case webRequest
    case unknown
}

struct ChromeMV3ContentScriptBridgeResponse:
    Codable,
    Equatable,
    Sendable
{
    var bridgeCallID: String
    var succeeded: Bool
    var resultPayload: ChromeMV3StorageValue?
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var serviceWorkerWakeAttempted: Bool
    var serviceWorkerLifecycleWakeResult:
        ChromeMV3ServiceWorkerInternalWakeResult?
    var nativeHostLaunchAttempted: Bool
    var diagnostics: [String]

    var foundationObject: [String: Any] {
        [
            "bridgeCallID": bridgeCallID,
            "succeeded": succeeded,
            "resultPayload": resultPayload?.contentScriptBridgeFoundationObject
                ?? NSNull(),
            "lastErrorCode": lastErrorCode ?? NSNull(),
            "lastErrorMessage": lastErrorMessage ?? NSNull(),
            "serviceWorkerWakeAttempted": serviceWorkerWakeAttempted,
            "serviceWorkerLifecycleWakeResult":
                serviceWorkerLifecycleWakeResultFoundationObject,
            "nativeHostLaunchAttempted": nativeHostLaunchAttempted,
            "diagnostics": diagnostics,
        ]
    }

    private var serviceWorkerLifecycleWakeResultFoundationObject: Any {
        guard let serviceWorkerLifecycleWakeResult,
              let data = try? JSONEncoder().encode(
                serviceWorkerLifecycleWakeResult
              ),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return NSNull() }
        return object
    }
}

private extension ChromeMV3StorageValue {
    init?(contentScriptBridgeWebKitValue value: Any) {
        if value is NSNull {
            self = .null
        } else if let bool = value as? Bool {
            self = .bool(bool)
        } else if let string = value as? String {
            self = .string(string)
        } else if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                let double = number.doubleValue
                guard double.isFinite else { return nil }
                self = .number(double)
            }
        } else if let array = value as? [Any] {
            var values: [ChromeMV3StorageValue] = []
            for entry in array {
                guard let converted = ChromeMV3StorageValue(
                    contentScriptBridgeWebKitValue: entry
                ) else { return nil }
                values.append(converted)
            }
            self = .array(values)
        } else if let object = value as? [String: Any] {
            var mapped: [String: ChromeMV3StorageValue] = [:]
            for (key, entry) in object {
                guard let converted = ChromeMV3StorageValue(
                    contentScriptBridgeWebKitValue: entry
                ) else { return nil }
                mapped[key] = converted
            }
            self = .object(mapped)
        } else {
            return nil
        }
    }

    var stringValue: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    var objectValue: [String: ChromeMV3StorageValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var contentScriptBridgeFoundationObject: Any {
        switch self {
        case .array(let values):
            return values.map(\.contentScriptBridgeFoundationObject)
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .number(let value):
            return value
        case .object(let object):
            return object.mapValues(\.contentScriptBridgeFoundationObject)
        case .string(let value):
            return value
        }
    }
}

final class ChromeMV3ContentScriptBridgeHost {
    private let extensionID: String
    private let profileID: String
    private let tabID: Int
    private let frameID: Int
    private let documentID: String
    private let urlString: String
    private let permissionBroker: ChromeMV3PermissionBroker
    private let endpointRegistry: ChromeMV3ContentScriptEndpointRegistry
    private let sharedLifecycleSession:
        ChromeMV3ServiceWorkerSharedLifecycleSession?
    private let lifecycleComponentID: String
    private var serviceWorkerRuntimePortIDs: Set<String> = []

    init(
        extensionID: String,
        profileID: String,
        tabID: Int,
        frameID: Int,
        documentID: String,
        urlString: String,
        permissionBroker: ChromeMV3PermissionBroker,
        endpointRegistry: ChromeMV3ContentScriptEndpointRegistry,
        sharedLifecycleSession:
            ChromeMV3ServiceWorkerSharedLifecycleSession? = nil
    ) {
        self.extensionID = extensionID
        self.profileID = profileID
        self.tabID = tabID
        self.frameID = frameID
        self.documentID = documentID
        self.urlString = urlString
        self.permissionBroker = permissionBroker
        self.endpointRegistry = endpointRegistry
        self.sharedLifecycleSession = sharedLifecycleSession
        self.lifecycleComponentID =
            stableIDContentScripts(
                prefix: "content-script-service-worker-endpoint",
                parts: [
                    profileID,
                    extensionID,
                    String(tabID),
                    String(frameID),
                    documentID,
                ]
            )
        sharedLifecycleSession?.attachComponent(
            kind: .contentScriptSyntheticEndpoint,
            componentID: lifecycleComponentID,
            eventSurfaces: [
                .runtimeOnMessage,
                .runtimeOnConnect,
            ],
            keepaliveSources: [.runtimePort],
            diagnostics: [
                "Content-script bridge attached to the local experimental shared lifecycle session.",
                "Normal-tab runtime remains limited to the declared content-script attachment path.",
            ]
        )
    }

    deinit {
        for portID in serviceWorkerRuntimePortIDs {
            sharedLifecycleSession?.disconnectKeepalive(
                portID: portID,
                reason: .reset
            )
        }
        sharedLifecycleSession?.detachComponent(
            componentID: lifecycleComponentID,
            reason: .reset
        )
    }

    func handle(_ body: Any) -> ChromeMV3ContentScriptBridgeResponse {
        let object = body as? [String: Any] ?? [:]
        let namespace = object["namespace"] as? String ?? "unsupported"
        let methodName = object["methodName"] as? String ?? "unknown"
        let bridgeCallID = object["bridgeCallID"] as? String
            ?? stableIDContentScripts(
                prefix: "content-script-bridge-call",
                parts: [namespace, methodName]
            )

        switch (namespace, methodName) {
        case ("runtime", "registerOnMessage"):
            endpointRegistry.registerRuntimeOnMessageListener(
                extensionID: extensionID,
                profileID: profileID,
                tabID: tabID,
                frameID: frameID,
                documentID: documentID
            )
            return success(
                bridgeCallID: bridgeCallID,
                payload: .bool(true),
                diagnostics: [
                    "runtime.onMessage listener was registered for the content-script endpoint."
                ]
            )
        case ("runtime", "registerOnConnect"):
            endpointRegistry.registerRuntimeOnConnectListener(
                extensionID: extensionID,
                profileID: profileID,
                tabID: tabID,
                frameID: frameID,
                documentID: documentID
            )
            return success(
                bridgeCallID: bridgeCallID,
                payload: .bool(true),
                diagnostics: [
                    "runtime.onConnect listener was registered for the content-script endpoint."
                ]
            )
        case ("runtime", "getURL"):
            let path = (object["path"] as? String ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return success(
                bridgeCallID: bridgeCallID,
                payload: .string("chrome-extension://\(extensionID)/\(path)"),
                diagnostics: [
                    "runtime.getURL returned a deterministic extension URL."
                ]
            )
        case ("runtime", "sendMessage"):
            return runtimeSendMessage(
                bridgeCallID: bridgeCallID,
                arguments: bridgeArguments(from: object)
            )
        case ("runtime", "connect"):
            return runtimeConnect(
                bridgeCallID: bridgeCallID,
                arguments: bridgeArguments(from: object)
            )
        case ("runtime", "port.postMessage"):
            return runtimePortPostMessage(
                bridgeCallID: bridgeCallID,
                arguments: bridgeArguments(from: object)
            )
        case ("runtime", "port.disconnect"):
            return runtimePortDisconnect(
                bridgeCallID: bridgeCallID,
                arguments: bridgeArguments(from: object)
            )
        case ("storage", _),
             ("permissions", _),
             ("tabs", _),
             ("nativeMessaging", _),
             ("declarativeNetRequest", _),
             ("webRequest", _),
             ("sidePanel", _),
             ("offscreen", _),
             ("identity", _):
            return blocked(
                bridgeCallID: bridgeCallID,
                code: .unsupportedAPI,
                diagnostics: [
                    "\(namespace).\(methodName) is not exposed to content scripts in Sumi developer preview."
                ]
            )
        default:
            return blocked(
                bridgeCallID: bridgeCallID,
                code: .unsupportedAPI,
                diagnostics: [
                    "Unknown content-script chrome API route \(namespace).\(methodName)."
                ]
            )
        }
    }

    private func bridgeArguments(
        from object: [String: Any]
    ) -> [ChromeMV3StorageValue] {
        guard let values = object["arguments"] as? [Any] else { return [] }
        return values.compactMap {
            ChromeMV3StorageValue(contentScriptBridgeWebKitValue: $0)
        }
    }

    private func routeServiceWorkerLifecycleEvent(
        source: ChromeMV3ServiceWorkerEventSource,
        payload: ChromeMV3StorageValue?,
        payloadSummary: String,
        keepaliveKind: ChromeMV3ServiceWorkerInternalKeepaliveKind? = nil,
        portID: String? = nil
    ) -> ChromeMV3ServiceWorkerInternalWakeResult? {
        sharedLifecycleSession?.routeEvent(
            reason: source.wakeReason,
            listenerEvent: source.listenerEvent,
            sourceComponentID: lifecycleComponentID,
            sourceComponentKind: .contentScriptSyntheticEndpoint,
            payload: payload,
            payloadSummary: payloadSummary,
            sourceContext: .contentScript,
            keepaliveKind: keepaliveKind,
            portID: portID
        )
    }

    private func contentScriptSenderLifecyclePayload() -> ChromeMV3StorageValue {
        .object([
            "id": .string(extensionID),
            "extensionID": .string(extensionID),
            "profileID": .string(profileID),
            "tabId": .number(Double(tabID)),
            "frameId": .number(Double(frameID)),
            "documentId": .string(documentID),
            "urlRedacted": .bool(true),
            "redactionState": .string("content-script URL redacted"),
        ])
    }

    private func runtimeSendMessage(
        bridgeCallID: String,
        arguments: [ChromeMV3StorageValue]
    ) -> ChromeMV3ContentScriptBridgeResponse {
        if let lifecycleResult = routeServiceWorkerLifecycleEvent(
            source: .contentScriptRuntimeMessage,
            payload: arguments.first ?? .null,
            payloadSummary: "content-script runtime.sendMessage"
        ) {
            guard lifecycleResult.dispatched else {
                let contract = ChromeMV3RuntimeLastErrorContract
                    .contract(for: .noReceivingEnd)
                return ChromeMV3ContentScriptBridgeResponse(
                    bridgeCallID: bridgeCallID,
                    succeeded: false,
                    resultPayload: nil,
                    lastErrorCode: contract.error.rawValue,
                    lastErrorMessage:
                        lifecycleResult.lastErrorMessage
                        ?? contract.futureLastErrorMessage,
                    serviceWorkerWakeAttempted: true,
                    serviceWorkerLifecycleWakeResult: lifecycleResult,
                    nativeHostLaunchAttempted: false,
                    diagnostics:
                        uniqueSortedContentScripts(
                            lifecycleResult.diagnostics
                                + contract.diagnostics
                                + [
                                    "Content-script runtime.sendMessage reached the local experimental service-worker lifecycle but no listener accepted it.",
                                ]
                        )
                )
            }
            return success(
                bridgeCallID: bridgeCallID,
                payload: lifecycleResult.responsePayload ?? .null,
                serviceWorkerLifecycleWakeResult: lifecycleResult,
                diagnostics:
                    lifecycleResult.diagnostics
                    + [
                        "Content-script runtime.sendMessage routed through the local experimental shared lifecycle session.",
                    ]
            )
        }
        let route = ChromeMV3RuntimeMessagingRoute.make(
            kind: .contentScriptToServiceWorker,
            extensionID: extensionID,
            profileID: profileID,
            tabID: tabID,
            frameID: frameID,
            documentID: documentID,
            sourceURL: urlString,
            targetURL: nil
        )
        let dispatch = ChromeMV3RuntimeMessageDispatcher.dispatch(
            input: ChromeMV3RuntimeMessageDispatcherInput.make(
                route: route,
                listenerRegistrySnapshot:
                    ChromeMV3RuntimeModelListenerRegistrySnapshot.empty(
                        extensionID: extensionID,
                        profileID: profileID
                    ),
                permissionBrokerSnapshot: permissionBroker,
                serviceWorkerLifecycleSnapshot:
                    .blocked(extensionID: extensionID, profileID: profileID),
                moduleState: .enabled,
                dispatchMode: .modelOnly,
                responseMode: .promise,
                expectsResponse: true,
                userGestureAvailable: false,
                seed: bridgeCallID
            )
        )
        if let error = dispatch.selectedLastError {
            return ChromeMV3ContentScriptBridgeResponse(
                bridgeCallID: bridgeCallID,
                succeeded: false,
                resultPayload: nil,
                lastErrorCode: error.error.rawValue,
                lastErrorMessage: error.futureLastErrorMessage,
                serviceWorkerWakeAttempted: false,
                serviceWorkerLifecycleWakeResult: nil,
                nativeHostLaunchAttempted: false,
                diagnostics:
                    uniqueSortedContentScripts(
                        dispatch.diagnostics
                            + [
                                "Content-script runtime.sendMessage did not wake a product service worker."
                            ]
                    )
            )
        }
        return success(
            bridgeCallID: bridgeCallID,
            payload: dispatch.responsePayload ?? .null,
            diagnostics: dispatch.diagnostics
        )
    }

    private func runtimeConnect(
        bridgeCallID: String,
        arguments: [ChromeMV3StorageValue]
    ) -> ChromeMV3ContentScriptBridgeResponse {
        guard sharedLifecycleSession != nil else {
            return blocked(
                bridgeCallID: bridgeCallID,
                code: .routeNotImplemented,
                diagnostics: [
                    "runtime.connect from content scripts targets the extension runtime/service-worker side, which is not available without a local experimental lifecycle session.",
                    "tabs.connect content-script endpoint Ports are still supported when popup/options opens a modeled Port to an attached endpoint.",
                    "No fake runtime Port is returned.",
                ]
            )
        }
        let name = arguments.first?.objectValue?["name"]?.stringValue ?? ""
        let portID = stableIDContentScripts(
            prefix: "content-script-runtime-port",
            parts: [
                extensionID,
                profileID,
                String(tabID),
                String(frameID),
                documentID,
                bridgeCallID,
            ]
        )
        let lifecycleResult = routeServiceWorkerLifecycleEvent(
            source: .contentScriptRuntimeConnect,
            payload: .object([
                "portID": .string(portID),
                "name": .string(name),
                "sender": contentScriptSenderLifecyclePayload(),
            ]),
            payloadSummary: "content-script runtime.connect",
            keepaliveKind: .runtimePort,
            portID: portID
        )
        guard let lifecycleResult, lifecycleResult.dispatched else {
            let contract = ChromeMV3RuntimeLastErrorContract
                .contract(for: .noReceivingEnd)
            return ChromeMV3ContentScriptBridgeResponse(
                bridgeCallID: bridgeCallID,
                succeeded: false,
                resultPayload: nil,
                lastErrorCode: contract.error.rawValue,
                lastErrorMessage:
                    lifecycleResult?.lastErrorMessage
                    ?? contract.futureLastErrorMessage,
                serviceWorkerWakeAttempted: lifecycleResult != nil,
                serviceWorkerLifecycleWakeResult: lifecycleResult,
                nativeHostLaunchAttempted: false,
                diagnostics:
                    uniqueSortedContentScripts(
                        (lifecycleResult?.diagnostics ?? [])
                            + contract.diagnostics
                            + [
                                "Content-script runtime.connect did not open a service-worker Port.",
                            ]
                    )
            )
        }
        serviceWorkerRuntimePortIDs.insert(portID)
        return success(
            bridgeCallID: bridgeCallID,
            payload: .object([
                "portID": .string(portID),
                "portKind": .string("serviceWorkerRuntimePort"),
                "canWakeServiceWorkerNow": .bool(true),
                "runtimeLoadable": .bool(false),
            ]),
            serviceWorkerLifecycleWakeResult: lifecycleResult,
            diagnostics:
                lifecycleResult.diagnostics
                + [
                    "Content-script runtime.connect opened a local experimental service-worker Port keepalive.",
                ]
        )
    }

    private func runtimePortPostMessage(
        bridgeCallID: String,
        arguments: [ChromeMV3StorageValue]
    ) -> ChromeMV3ContentScriptBridgeResponse {
        guard arguments.count == 2,
              let portID = arguments[0].stringValue
        else {
            return blocked(
                bridgeCallID: bridgeCallID,
                code: .unsupportedAPI,
                diagnostics: [
                    "runtime Port postMessage requires portID and message arguments."
                ]
            )
        }
        if serviceWorkerRuntimePortIDs.contains(portID) {
            let lifecycleResult = routeServiceWorkerLifecycleEvent(
                source: .contentScriptRuntimeConnect,
                payload: .object([
                    "portID": .string(portID),
                    "message": arguments[1],
                ]),
                payloadSummary:
                    "content-script service-worker Port.postMessage",
                portID: portID
            )
            guard let lifecycleResult, lifecycleResult.dispatched else {
                let contract = ChromeMV3RuntimeLastErrorContract
                    .contract(for: .noReceivingEnd)
                return ChromeMV3ContentScriptBridgeResponse(
                    bridgeCallID: bridgeCallID,
                    succeeded: false,
                    resultPayload: nil,
                    lastErrorCode: contract.error.rawValue,
                    lastErrorMessage:
                        lifecycleResult?.lastErrorMessage
                        ?? contract.futureLastErrorMessage,
                    serviceWorkerWakeAttempted: lifecycleResult != nil,
                    serviceWorkerLifecycleWakeResult: lifecycleResult,
                    nativeHostLaunchAttempted: false,
                    diagnostics:
                        uniqueSortedContentScripts(
                            (lifecycleResult?.diagnostics ?? [])
                                + contract.diagnostics
                                + [
                                    "Content-script service-worker Port.postMessage was not accepted by the local experimental lifecycle.",
                                ]
                        )
                )
            }
            return success(
                bridgeCallID: bridgeCallID,
                payload: .object([
                    "portID": .string(portID),
                    "delivered": .bool(true),
                    "payload": arguments[1],
                    "direction": .string("contentScriptToServiceWorker"),
                ]),
                serviceWorkerLifecycleWakeResult: lifecycleResult,
                diagnostics:
                    lifecycleResult.diagnostics
                    + [
                        "Content-script Port.postMessage routed to the local experimental service-worker Port.",
                    ]
            )
        }
        let delivery = endpointRegistry.deliverContentScriptPortMessage(
            portID: portID,
            payload: arguments[1]
        )
        guard delivery.delivered else {
            return blocked(
                bridgeCallID: bridgeCallID,
                code: .noReceivingEnd,
                diagnostics: delivery.diagnostics
            )
        }
        return success(
            bridgeCallID: bridgeCallID,
            payload: portDeliveryPayload(delivery),
            diagnostics:
                delivery.diagnostics
                    + [
                        "Content-script Port.postMessage reached the modeled popup/options endpoint.",
                        "No service-worker keepalive was opened for Port delivery.",
                    ]
        )
    }

    private func runtimePortDisconnect(
        bridgeCallID: String,
        arguments: [ChromeMV3StorageValue]
    ) -> ChromeMV3ContentScriptBridgeResponse {
        guard arguments.count == 1,
              let portID = arguments[0].stringValue
        else {
            return blocked(
                bridgeCallID: bridgeCallID,
                code: .unsupportedAPI,
                diagnostics: [
                    "runtime Port disconnect requires one portID argument."
                ]
            )
        }
        if serviceWorkerRuntimePortIDs.remove(portID) != nil {
            sharedLifecycleSession?.disconnectKeepalive(
                portID: portID,
                reason: .reset
            )
            return success(
                bridgeCallID: bridgeCallID,
                payload: .object([
                    "portID": .string(portID),
                    "disconnected": .bool(true),
                    "direction": .string("contentScriptToServiceWorker"),
                ]),
                diagnostics: [
                    "Content-script Port.disconnect released the local experimental service-worker Port keepalive."
                ]
            )
        }
        let delivery = endpointRegistry.disconnectPort(
            portID: portID,
            reason: "Port.disconnect called by content script."
        )
        return success(
            bridgeCallID: bridgeCallID,
            payload: portDeliveryPayload(delivery),
            diagnostics:
                delivery.diagnostics
                    + [
                        "Content-script Port.disconnect deterministically notified both modeled endpoints when present.",
                    ]
        )
    }

    private func portDeliveryPayload(
        _ delivery: ChromeMV3ContentScriptPortDeliveryResult
    ) -> ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "portID": .string(delivery.portID),
            "direction": .string(delivery.direction.rawValue),
            "delivered": .bool(delivery.delivered),
            "payload": delivery.payload ?? .null,
        ]
        if let endpointID = delivery.endpointID {
            object["endpointID"] = .string(endpointID)
        }
        if let reason = delivery.disconnectReason {
            object["disconnectReason"] = .string(reason)
        }
        return .object(object)
    }

    private func success(
        bridgeCallID: String,
        payload: ChromeMV3StorageValue,
        serviceWorkerLifecycleWakeResult:
            ChromeMV3ServiceWorkerInternalWakeResult? = nil,
        diagnostics: [String]
    ) -> ChromeMV3ContentScriptBridgeResponse {
        ChromeMV3ContentScriptBridgeResponse(
            bridgeCallID: bridgeCallID,
            succeeded: true,
            resultPayload: payload,
            lastErrorCode: nil,
            lastErrorMessage: nil,
            serviceWorkerWakeAttempted:
                serviceWorkerLifecycleWakeResult != nil,
            serviceWorkerLifecycleWakeResult:
                serviceWorkerLifecycleWakeResult,
            nativeHostLaunchAttempted: false,
            diagnostics:
                uniqueSortedContentScripts(
                    diagnostics
                    + (serviceWorkerLifecycleWakeResult?.diagnostics ?? [])
                )
        )
    }

    private func blocked(
        bridgeCallID: String,
        code: ChromeMV3RuntimeLastErrorCase,
        diagnostics: [String]
    ) -> ChromeMV3ContentScriptBridgeResponse {
        let contract = ChromeMV3RuntimeLastErrorContract.contract(for: code)
        return ChromeMV3ContentScriptBridgeResponse(
            bridgeCallID: bridgeCallID,
            succeeded: false,
            resultPayload: nil,
            lastErrorCode: code.rawValue,
            lastErrorMessage: contract.futureLastErrorMessage,
            serviceWorkerWakeAttempted: false,
            serviceWorkerLifecycleWakeResult: nil,
            nativeHostLaunchAttempted: false,
            diagnostics:
                uniqueSortedContentScripts(
                    diagnostics + contract.diagnostics
                )
        )
    }
}

#if canImport(WebKit)
struct ChromeMV3ContentScriptWKAttachmentResult:
    Equatable
{
    var attemptedAttachment: Bool
    var attached: Bool
    var installedUserScriptCount: Int
    var installedCSSStyleSheetCount: Int
    var installedScriptMessageHandlerCount: Int
    var endpointRegistered: Bool
    var endpointID: String?
    var blockers: [ChromeMV3ContentScriptBlockedReason]
    var diagnostics: [String]
}

@MainActor
final class ChromeMV3ContentScriptWKScriptMessageHandler:
    NSObject,
    WKScriptMessageHandlerWithReply
{
    private let host: ChromeMV3ContentScriptBridgeHost

    init(host: ChromeMV3ContentScriptBridgeHost) {
        self.host = host
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        _ = userContentController
        let response = host.handle(message.body)
        return (response.foundationObject, nil)
    }
}

@MainActor
final class ChromeMV3ContentScriptWKAttachmentHandle {
    private weak var configuration: WKWebViewConfiguration?
    private var installedScripts: [WKUserScript]
    private var installedCSSStyleSheetCount: Int
    private var messageHandlerName: String?
    private var contentWorld: WKContentWorld
    private var scriptHandler: ChromeMV3ContentScriptWKScriptMessageHandler?
    private let endpointRegistry: ChromeMV3ContentScriptEndpointRegistry
    private var endpointID: String?
    private var tornDown = false

    init(
        configuration: WKWebViewConfiguration,
        installedScripts: [WKUserScript],
        installedCSSStyleSheetCount: Int,
        messageHandlerName: String?,
        contentWorld: WKContentWorld,
        scriptHandler: ChromeMV3ContentScriptWKScriptMessageHandler?,
        endpointRegistry: ChromeMV3ContentScriptEndpointRegistry,
        endpointID: String?
    ) {
        self.configuration = configuration
        self.installedScripts = installedScripts
        self.installedCSSStyleSheetCount = installedCSSStyleSheetCount
        self.messageHandlerName = messageHandlerName
        self.contentWorld = contentWorld
        self.scriptHandler = scriptHandler
        self.endpointRegistry = endpointRegistry
        self.endpointID = endpointID
    }

    func tearDown(reason: String = "Content-script attachment handle teardown.") {
        guard tornDown == false else { return }
        if let configuration {
            if let messageHandlerName {
                configuration.userContentController.removeScriptMessageHandler(
                    forName: messageHandlerName,
                    contentWorld: contentWorld
                )
            }
            if installedCSSStyleSheetCount > 0 {
                SumiRemoveUserStyleSheetsAssociatedWithContentWorld(
                    configuration.userContentController,
                    contentWorld
                )
            }
            removeInstalledUserScripts(
                installedScripts,
                from: configuration.userContentController
            )
        }
        endpointRegistry.tearDownAll(reason: reason)
        installedScripts.removeAll()
        installedCSSStyleSheetCount = 0
        scriptHandler = nil
        messageHandlerName = nil
        tornDown = true
    }

    private func removeInstalledUserScripts(
        _ scripts: [WKUserScript],
        from userContentController: WKUserContentController
    ) {
        guard scripts.isEmpty == false else { return }
        SumiRemoveUserScriptsAssociatedWithContentWorld(
            userContentController,
            contentWorld
        )
        if userContentController.userScripts.contains(where: { script in
            scripts.contains(where: { $0 === script })
        }) == false {
            return
        }
        let selector = NSSelectorFromString("_removeUserScript:")
        if userContentController.responds(to: selector) {
            for script in scripts {
                userContentController.perform(selector, with: script)
            }
        } else {
            userContentController.removeAllUserScripts()
        }
    }
}

@MainActor
enum ChromeMV3ContentScriptWKAttachmentExecutor {
    static func attachIfAllowed(
        configuration: WKWebViewConfiguration,
        preflight: ChromeMV3NormalTabContentScriptPreflight,
        permissionBroker: ChromeMV3PermissionBroker,
        endpointRegistry: ChromeMV3ContentScriptEndpointRegistry,
        sharedLifecycleSession:
            ChromeMV3ServiceWorkerSharedLifecycleSession? = nil
    ) -> (
        result: ChromeMV3ContentScriptWKAttachmentResult,
        handle: ChromeMV3ContentScriptWKAttachmentHandle?
    ) {
        guard preflight.canAttachDeclaredContentScriptsNow else {
            return (
                ChromeMV3ContentScriptWKAttachmentResult(
                    attemptedAttachment: true,
                    attached: false,
                    installedUserScriptCount: 0,
                    installedCSSStyleSheetCount: 0,
                    installedScriptMessageHandlerCount: 0,
                    endpointRegistered: false,
                    endpointID: nil,
                    blockers: preflight.blockers,
                    diagnostics: preflight.diagnostics
                ),
                nil
            )
        }
        guard configuration.sumiIsNormalTabWebViewConfiguration else {
            return (
                ChromeMV3ContentScriptWKAttachmentResult(
                    attemptedAttachment: true,
                    attached: false,
                    installedUserScriptCount: 0,
                    installedCSSStyleSheetCount: 0,
                    installedScriptMessageHandlerCount: 0,
                    endpointRegistered: false,
                    endpointID: nil,
                    blockers: [.tabSurfaceIneligible],
                    diagnostics: [
                        "WKUserScript attachment refused because the configuration is not a normal-tab configuration."
                    ]
                ),
                nil
            )
        }

        let contentWorld = WKContentWorld.world(
            name: "sumi.mv3.content.\(preflight.profileID).\(preflight.extensionID)"
        )
        let messageHandlerName = stableIDContentScripts(
            prefix: "sumiChromeMV3ContentScript",
            parts: [preflight.profileID, preflight.extensionID]
        ).replacingOccurrences(of: "-", with: "_")
        var installedScripts: [WKUserScript] = []
        let installedCSSStyleSheetCount = installCSSStyleSheets(
            preflight: preflight,
            contentWorld: contentWorld,
            configuration: configuration
        )

        let handler: ChromeMV3ContentScriptWKScriptMessageHandler?
        let installedScriptMessageHandlerCount: Int
        if preflight.canExposeContentScriptBridgeNow {
            let host = ChromeMV3ContentScriptBridgeHost(
                extensionID: preflight.extensionID,
                profileID: preflight.profileID,
                tabID: preflight.tabID,
                frameID: preflight.frameID,
                documentID: preflight.documentID,
                urlString: preflight.urlString,
                permissionBroker: permissionBroker,
                endpointRegistry: endpointRegistry,
                sharedLifecycleSession: sharedLifecycleSession
            )
            let bridgeHandler =
                ChromeMV3ContentScriptWKScriptMessageHandler(host: host)
            configuration.userContentController.addScriptMessageHandler(
                bridgeHandler,
                contentWorld: contentWorld,
                name: messageHandlerName
            )
            let bridge = WKUserScript(
                source:
                    ChromeMV3ContentScriptJSBridgeSource.source(
                        extensionID: preflight.extensionID,
                        profileID: preflight.profileID,
                        tabID: preflight.tabID,
                        frameID: preflight.frameID,
                        documentID: preflight.documentID,
                        messageHandlerName: messageHandlerName
                    ),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: contentWorld
            )
            configuration.userContentController.addUserScript(bridge)
            installedScripts.append(bridge)
            handler = bridgeHandler
            installedScriptMessageHandlerCount = 1
        } else {
            handler = nil
            installedScriptMessageHandlerCount = 0
        }

        for script in preflight.matchedScripts {
            guard let runAt = script.runAt else { continue }
            guard script.validatedJSFilePaths.isEmpty == false else { continue }
            let source = bundledSource(script)
            let userScript = WKUserScript(
                source: source,
                injectionTime: injectionTime(runAt),
                forMainFrameOnly: true,
                in: contentWorld
            )
            configuration.userContentController.addUserScript(userScript)
            installedScripts.append(userScript)
        }

        let endpoint =
            preflight.canRegisterEndpointNow
                ? endpointRegistry.registerEndpoint(preflight: preflight)
                : nil
        let handle = ChromeMV3ContentScriptWKAttachmentHandle(
            configuration: configuration,
            installedScripts: installedScripts,
            installedCSSStyleSheetCount: installedCSSStyleSheetCount,
            messageHandlerName:
                installedScriptMessageHandlerCount == 0
                    ? nil
                    : messageHandlerName,
            contentWorld: contentWorld,
            scriptHandler: handler,
            endpointRegistry: endpointRegistry,
            endpointID: endpoint?.endpointID
        )
        return (
            ChromeMV3ContentScriptWKAttachmentResult(
                attemptedAttachment: true,
                attached: true,
                installedUserScriptCount: installedScripts.count,
                installedCSSStyleSheetCount: installedCSSStyleSheetCount,
                installedScriptMessageHandlerCount:
                    installedScriptMessageHandlerCount,
                endpointRegistered: endpoint != nil,
                endpointID: endpoint?.endpointID,
                blockers: [],
                diagnostics:
                    uniqueSortedContentScripts(
                        preflight.diagnostics
                            + [
                                "WebKit attachment installed declared CSS through scoped user stylesheets when present.",
                                "WKUserScript attachment installed a scoped content-script bridge and declared JS files when matched JS resources were present.",
                                "document_idle maps to WKUserScript atDocumentEnd in this developer-preview path.",
                                "No scripting.insertCSS API route was enabled.",
                            ]
                    )
            ),
            handle
        )
    }

    private static func installCSSStyleSheets(
        preflight: ChromeMV3NormalTabContentScriptPreflight,
        contentWorld: WKContentWorld,
        configuration: WKWebViewConfiguration
    ) -> Int {
        var installedCount = 0
        for script in preflight.matchedScripts.sorted(by: {
            $0.contentScriptIndex < $1.contentScriptIndex
        }) {
            for resource in script.cssResources
                .filter(\.validForAttachment)
                .sorted(by: { $0.injectionOrder < $1.injectionOrder })
            {
                guard let generatedBundlePath = resource.generatedBundlePath,
                      let source = try? String(
                        contentsOf: URL(fileURLWithPath: generatedBundlePath),
                        encoding: .utf8
                      )
                else { continue }
                let baseURL = URL(fileURLWithPath: generatedBundlePath)
                    .deletingLastPathComponent()
                let styleSheet = SumiCreatePrivateUserStyleSheet(
                    source,
                    true,
                    webKitUserContentPatterns(script.matches),
                    webKitUserContentPatterns(script.excludeMatches),
                    baseURL,
                    true,
                    contentWorld
                )
                SumiAddPrivateUserStyleSheet(
                    configuration.userContentController,
                    styleSheet
                )
                installedCount += 1
            }
        }
        return installedCount
    }

    private static func webKitUserContentPatterns(
        _ patterns: [String]
    ) -> [String] {
        patterns.map { pattern in
            pattern == "<all_urls>" ? "*://*/*" : pattern
        }
    }

    private static func bundledSource(
        _ script: ChromeMV3DeclaredContentScriptAttachmentRecord
    ) -> String {
        let root = URL(fileURLWithPath: script.generatedBundleRootPath)
        let parts = script.validatedJSFilePaths.compactMap { relativePath in
            try? String(
                contentsOf:
                    root.appendingPathComponent(relativePath),
                encoding: .utf8
            )
        }
        return """
        (() => {
          "use strict";
          if (!globalThis.chrome || !globalThis.chrome.runtime) {
            return;
          }
        \(parts.joined(separator: "\n"))
        })();
        """
    }

    private static func injectionTime(
        _ runAt: ChromeMV3ContentScriptRunAt
    ) -> WKUserScriptInjectionTime {
        switch runAt {
        case .documentStart:
            return .atDocumentStart
        case .documentEnd, .documentIdle:
            return .atDocumentEnd
        }
    }
}
#endif

enum ChromeMV3ContentScriptJSBridgeSource {
    static func source(
        extensionID: String,
        profileID: String,
        tabID: Int,
        frameID: Int,
        documentID: String,
        messageHandlerName: String
    ) -> String {
        let config = jsonString([
            "extensionID": extensionID,
            "profileID": profileID,
            "tabID": String(tabID),
            "frameID": String(frameID),
            "documentID": documentID,
            "messageHandlerName": messageHandlerName,
        ])
        return """
        (() => {
          "use strict";
          const config = \(config);
          const chromeObject = {};
          const runtime = {};
          let lastErrorValue;
          let nextCall = 0;

          function handler() {
            return globalThis.webkit
              && globalThis.webkit.messageHandlers
              && globalThis.webkit.messageHandlers[config.messageHandlerName];
          }

          function post(namespace, methodName, body) {
            const bridge = handler();
            nextCall += 1;
            const request = Object.assign({
              namespace,
              methodName,
              bridgeCallID: [
                "content-script",
                config.extensionID,
                namespace,
                methodName,
                String(nextCall)
              ].join("-")
            }, body || {});
            if (!bridge || typeof bridge.postMessage !== "function") {
              return Promise.resolve({
                succeeded: false,
                lastErrorMessage: "Content-script bridge handler is unavailable."
              });
            }
            return bridge.postMessage(request);
          }

          function toJSONCompatible(value) {
            if (value === undefined) {
              return null;
            }
            return JSON.parse(JSON.stringify(value));
          }

          function invokeCallback(callback, message, args) {
            lastErrorValue = message ? { message } : undefined;
            try {
              callback.apply(undefined, args || []);
            } finally {
              lastErrorValue = undefined;
            }
          }

          function callbackOrPromise(namespace, methodName, args, callback) {
            let safeArgs;
            try {
              safeArgs = (args || []).map(toJSONCompatible);
            } catch (error) {
              const message = "Invalid Chrome MV3 content-script JavaScript arguments.";
              if (callback) {
                invokeCallback(callback, message, []);
                return undefined;
              }
              return Promise.reject(new Error(message));
            }
            const promise = post(namespace, methodName, { arguments: safeArgs });
            if (callback) {
              promise.then((response) => {
                if (response.succeeded) {
                  invokeCallback(callback, null, [response.resultPayload]);
                } else {
                  invokeCallback(callback, response.lastErrorMessage, []);
                }
              });
              return undefined;
            }
            return promise.then((response) => {
              if (response.succeeded) {
                return response.resultPayload;
              }
              return Promise.reject(
                new Error(response.lastErrorMessage || "Content-script bridge call failed.")
              );
            });
          }

          function makeEvent(registerMethod) {
            const listeners = [];
            return Object.freeze({
              addListener(listener) {
                if (typeof listener === "function" && !listeners.includes(listener)) {
                  listeners.push(listener);
                  post("runtime", registerMethod, {});
                }
              },
              removeListener(listener) {
                const index = listeners.indexOf(listener);
                if (index >= 0) {
                  listeners.splice(index, 1);
                }
              },
              hasListener(listener) {
                return listeners.includes(listener);
              },
              hasListeners() {
                return listeners.length > 0;
              }
            });
          }

          function makePortEvent() {
            const listeners = [];
            return Object.freeze({
              addListener(listener) {
                if (typeof listener === "function" && !listeners.includes(listener)) {
                  listeners.push(listener);
                }
              },
              removeListener(listener) {
                const index = listeners.indexOf(listener);
                if (index >= 0) {
                  listeners.splice(index, 1);
                }
              },
              hasListener(listener) {
                return listeners.includes(listener);
              },
              hasListeners() {
                return listeners.length > 0;
              },
              dispatch() {
                const args = Array.prototype.slice.call(arguments);
                listeners.slice().forEach((listener) => listener.apply(undefined, args));
              }
            });
          }

          Object.defineProperty(runtime, "lastError", {
            get() { return lastErrorValue; },
            enumerable: true
          });
          Object.defineProperty(runtime, "id", {
            value: config.extensionID,
            enumerable: true
          });
          Object.defineProperty(runtime, "getURL", {
            value(path) {
              const raw = typeof path === "string" ? path : "";
              return "chrome-extension://" + config.extensionID + "/" + raw.replace(/^\\/+/, "");
            },
            enumerable: true
          });
          Object.defineProperty(runtime, "sendMessage", {
            value(message, options, callback) {
              let cb = null;
              let opts = options;
              if (typeof options === "function") {
                cb = options;
                opts = undefined;
              } else if (typeof callback === "function") {
                cb = callback;
              }
              return callbackOrPromise(
                "runtime",
                "sendMessage",
                opts === undefined ? [message] : [message, opts],
                cb
              );
            },
            enumerable: true
          });
          Object.defineProperty(runtime, "connect", {
            value(connectInfo) {
              const name = connectInfo && typeof connectInfo.name === "string"
                ? connectInfo.name
                : "";
              const onMessage = makePortEvent();
              const onDisconnect = makePortEvent();
              let disconnected = false;
              let portID = null;
              const pendingMessages = [];
              function markDisconnected(port) {
                if (disconnected) {
                  return;
                }
                disconnected = true;
                pendingMessages.splice(0, pendingMessages.length);
                onDisconnect.dispatch(port);
              }
              function postPortMessage(port, message) {
                if (disconnected) {
                  throw new Error("Attempting to use a disconnected port object");
                }
                const payload = toJSONCompatible(message);
                if (!portID) {
                  pendingMessages.push(payload);
                  return;
                }
                post("runtime", "port.postMessage", {
                  arguments: [portID, payload]
                }).then((response) => {
                  if (!response.succeeded) {
                    markDisconnected(port);
                  }
                }).catch(() => markDisconnected(port));
              }
              function flushPendingMessages(port) {
                if (!portID || disconnected || pendingMessages.length === 0) {
                  return;
                }
                const messages = pendingMessages.splice(0, pendingMessages.length);
                messages.forEach((message) => postPortMessage(port, message));
              }
              const port = {
                name,
                onMessage,
                onDisconnect,
                postMessage(message) {
                  postPortMessage(port, message);
                },
                disconnect() {
                  if (disconnected) { return; }
                  if (portID) {
                    post("runtime", "port.disconnect", {
                      arguments: [portID]
                    }).catch(() => {});
                  }
                  markDisconnected(port);
                }
              };
              post("runtime", "connect", { arguments: [connectInfo || {}] })
                .then((response) => {
                  if (!response.succeeded) {
                    markDisconnected(port);
                    return;
                  }
                  const payload = response.resultPayload || {};
                  portID = typeof payload.portID === "string" ? payload.portID : null;
                  if (!portID) {
                    markDisconnected(port);
                    return;
                  }
                  flushPendingMessages(port);
                })
                .catch(() => {
                  markDisconnected(port);
                });
              return port;
            },
            enumerable: true
          });
          Object.defineProperty(runtime, "onMessage", {
            value: makeEvent("registerOnMessage"),
            enumerable: true
          });
          Object.defineProperty(runtime, "onConnect", {
            value: makeEvent("registerOnConnect"),
            enumerable: true
          });

          function blockedNamespace(namespace) {
            return new Proxy({}, {
              get(target, prop) {
                if (typeof prop !== "string") {
                  return undefined;
                }
                if (!Object.prototype.hasOwnProperty.call(target, prop)) {
                  Object.defineProperty(target, prop, {
                    value() {
                      const args = Array.prototype.slice.call(arguments);
                      const callback = typeof args[args.length - 1] === "function"
                        ? args.pop()
                        : null;
                      return callbackOrPromise(namespace, prop, args, callback);
                    },
                    enumerable: true
                  });
                }
                return target[prop];
              }
            });
          }

          Object.defineProperty(chromeObject, "runtime", {
            value: Object.freeze(runtime),
            enumerable: true
          });
          ["storage", "permissions", "tabs", "nativeMessaging", "declarativeNetRequest", "webRequest", "sidePanel", "offscreen", "identity"].forEach((namespace) => {
            Object.defineProperty(chromeObject, namespace, {
              value: blockedNamespace(namespace),
              enumerable: true
            });
          });
          Object.defineProperty(globalThis, "chrome", {
            value: Object.freeze(chromeObject),
            configurable: true
          });
          Object.defineProperty(globalThis, "browser", {
            value: chromeObject,
            configurable: true
          });
        })();
        """
    }

    private static func jsonString(_ object: [String: String]) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

private struct ChromeMV3ContentScriptMatchPattern {
    var rawValue: String
    var status: ChromeMV3HostMatchPatternStatus
    var pathPattern: String?
    var fileSchemePattern: Bool
    var diagnostics: [String]

    init(_ rawValue: String) {
        self.rawValue = rawValue
        if let file = Self.parseFileSchemePattern(rawValue) {
            self.status = file.status
            self.pathPattern = file.pathPattern
            self.fileSchemePattern = file.status == .valid
            self.diagnostics = file.diagnostics
        } else {
            let hostPattern = ChromeMV3HostMatchPattern(rawValue)
            self.status = hostPattern.status
            self.pathPattern = hostPattern.pathPattern
            self.fileSchemePattern = false
            self.diagnostics = hostPattern.diagnostics
        }
    }

    var nonBlockingForNonFileTarget: Bool {
        fileSchemePattern && status == .valid
    }

    func matches(_ urlString: String) -> Bool {
        if fileSchemePattern {
            guard let components = URLComponents(string: urlString),
                  components.scheme?.lowercased() == "file",
                  let pathPattern
            else { return false }
            let path = components.percentEncodedPath.isEmpty
                ? "/"
                : components.percentEncodedPath
            return ChromeMV3ContentScriptGlob(pathPattern).matches(path)
        }

        let hostPattern = ChromeMV3HostMatchPattern(rawValue)
        guard hostPattern.matches(url: urlString) else { return false }
        guard rawValue != "<all_urls>" else { return true }
        guard let pathPattern else { return false }
        guard let components = URLComponents(string: urlString) else {
            return false
        }
        let path = components.percentEncodedPath.isEmpty
            ? "/"
            : components.percentEncodedPath
        return ChromeMV3ContentScriptGlob(pathPattern).matches(path)
    }

    private static func parseFileSchemePattern(
        _ rawValue: String
    ) -> (
        status: ChromeMV3HostMatchPatternStatus,
        pathPattern: String?,
        diagnostics: [String]
    )? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.lowercased().hasPrefix("file://") else { return nil }
        let remainder = String(value.dropFirst("file://".count))
        guard remainder.hasPrefix("/") else {
            return (
                .invalid,
                nil,
                [
                    "file match pattern must use Chrome's file:/// path form.",
                ]
            )
        }
        return (
            .valid,
            remainder,
            [
                "file match pattern is Chrome-valid syntax, but Sumi keeps actual file:// content-script attachment blocked by frame preflight and file-access policy.",
            ]
        )
    }
}

private struct ChromeMV3ContentScriptGlob {
    var pattern: String

    init(_ pattern: String) {
        self.pattern = pattern
    }

    func matches(_ value: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        let regex = "^\(escaped)$"
        guard let expression = try? NSRegularExpression(pattern: regex) else {
            return false
        }
        let range = NSRange(value.startIndex..., in: value)
        return expression.firstMatch(in: value, range: range) != nil
    }
}

private enum ChromeMV3ContentScriptResourcePath {
    struct PathError: Error {
        var message: String
    }

    static func normalize(_ rawPath: String) -> Result<String, PathError> {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutLeadingSlash = String(trimmed.drop { $0 == "/" })
        guard withoutLeadingSlash.isEmpty == false else {
            return .failure(PathError(message: "Content-script resource path is empty."))
        }
        let pathBeforeFragment = withoutLeadingSlash.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? withoutLeadingSlash
        let pathOnly = pathBeforeFragment.split(
            separator: "?",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? pathBeforeFragment
        let decoded = pathOnly.removingPercentEncoding ?? pathOnly
        let unsafe = decoded.hasPrefix("~")
            || decoded.contains("\\")
            || decoded.contains("\0")
            || decoded.localizedCaseInsensitiveContains("://")
            || decoded.contains("*")
        guard unsafe == false else {
            return .failure(PathError(message: "Unsafe content-script resource path: \(rawPath)."))
        }
        let segments = decoded.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard segments.isEmpty == false,
              segments.allSatisfy({
                $0.isEmpty == false && $0 != "." && $0 != ".."
              })
        else {
            return .failure(PathError(message: "Unsafe content-script resource path: \(rawPath)."))
        }
        return .success(decoded)
    }

    static func validateExistingFile(
        _ relativePath: String,
        root: URL
    ) -> (
        valid: Bool,
        reason: ChromeMV3ContentScriptBlockedReason?,
        diagnostics: [String]
    ) {
        let validation = validateExistingResourceFile(
            relativePath,
            root: root,
            kind: "JS",
            unsafeReason: .unsafeJSPath,
            missingReason: .missingJSFile
        )
        return (
            validation.valid,
            validation.reason,
            validation.diagnostics
        )
    }

    static func validateExistingCSSFile(
        _ relativePath: String,
        root: URL
    ) -> (
        valid: Bool,
        reason: ChromeMV3ContentScriptBlockedReason?,
        diagnostics: [String],
        fileURL: URL?,
        fileExists: Bool,
        pathSafe: Bool,
        byteCount: Int?,
        sha256: String?
    ) {
        let validation = validateExistingResourceFile(
            relativePath,
            root: root,
            kind: "CSS",
            unsafeReason: .unsafeCSSPath,
            missingReason: .missingCSSFile
        )
        guard validation.valid,
              let fileURL = validation.fileURL,
              let data = try? Data(contentsOf: fileURL)
        else {
            return (
                validation.valid,
                validation.reason,
                validation.diagnostics,
                validation.fileURL,
                validation.fileExists,
                validation.pathSafe,
                nil,
                nil
            )
        }
        return (
            true,
            nil,
            validation.diagnostics + [
                "Content-script CSS file metadata recorded: \(relativePath) \(data.count) bytes.",
            ],
            fileURL,
            true,
            true,
            data.count,
            sha256HexContentScripts(data)
        )
    }

    static func validateExistingResourceFile(
        _ relativePath: String,
        root: URL,
        kind: String,
        unsafeReason: ChromeMV3ContentScriptBlockedReason = .unsafeJSPath,
        missingReason: ChromeMV3ContentScriptBlockedReason = .missingJSFile
    ) -> (
        valid: Bool,
        reason: ChromeMV3ContentScriptBlockedReason?,
        diagnostics: [String],
        fileURL: URL?,
        fileExists: Bool,
        pathSafe: Bool
    ) {
        let fileURL = root.appendingPathComponent(relativePath)
            .standardizedFileURL
        guard fileURL.path.hasPrefix(root.path + "/") else {
            return (
                false,
                unsafeReason,
                ["Content-script \(kind) path escapes generated bundle root: \(relativePath)."],
                nil,
                false,
                false
            )
        }
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else {
            return (
                false,
                missingReason,
                ["Content-script \(kind) file is missing: \(relativePath)."],
                fileURL,
                false,
                true
            )
        }
        if (try? manager.destinationOfSymbolicLink(atPath: fileURL.path)) != nil {
            return (
                false,
                unsafeReason,
                ["Content-script \(kind) file is a symbolic link: \(relativePath)."],
                fileURL,
                true,
                false
            )
        }
        guard let values = try? fileURL.resourceValues(
            forKeys: [.isRegularFileKey]
        ), values.isRegularFile == true
        else {
            return (
                false,
                unsafeReason,
                ["Content-script \(kind) path is not a regular file: \(relativePath)."],
                fileURL,
                true,
                false
            )
        }
        return (
            true,
            nil,
            ["Content-script \(kind) file validated: \(relativePath)."],
            fileURL,
            true,
            true
        )
    }
}

private func uniqueSortedContentScripts(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

private func stableIDContentScripts(
    prefix: String,
    parts: [String]
) -> String {
    let joined = parts.joined(separator: "\u{1F}")
    let digest = SHA256.hash(data: Data(joined.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-\(String(hex.prefix(16)))"
}

private func sha256HexContentScripts(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}
