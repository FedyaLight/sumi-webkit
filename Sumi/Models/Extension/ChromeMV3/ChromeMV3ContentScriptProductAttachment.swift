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
    case missingJSFile
    case moduleDisabled
    case noEligibleDeclaredContentScript
    case normalTabGeneralRuntimeUnavailable
    case productGateBlocked
    case publicProductUnavailable
    case tabSurfaceIneligible
    case teardownPending
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
    var matchAboutBlank: Bool
    var matchOriginAsFallback: Bool
    var world: ChromeMV3ContentScriptWorld?
    var validatedJSFilePaths: [String]
    var supported: Bool
    var blockers: [ChromeMV3ContentScriptBlockedReason]
    var diagnostics: [String]

    var canAttachIfURLAndPermissionMatch: Bool {
        supported && blockers.isEmpty
    }

    func matchesURL(_ urlString: String) -> Bool {
        guard matches.isEmpty == false else { return false }
        let includedByMatch = matches.contains {
            ChromeMV3ContentScriptMatchPattern($0).matches(urlString)
        }
        guard includedByMatch else { return false }
        let excludedByMatch = excludeMatches.contains {
            ChromeMV3ContentScriptMatchPattern($0).matches(urlString)
        }
        guard excludedByMatch == false else { return false }
        guard includeGlobs.isEmpty
                || includeGlobs.contains(where: {
                    ChromeMV3ContentScriptGlob($0).matches(urlString)
                })
        else { return false }
        guard excludeGlobs.contains(where: {
            ChromeMV3ContentScriptGlob($0).matches(urlString)
        }) == false
        else { return false }
        return true
    }
}

struct ChromeMV3ContentScriptAttachmentPlan:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var generatedBundleRootPath: String
    var declaredScripts: [ChromeMV3DeclaredContentScriptAttachmentRecord]
    var diagnostics: [String]

    var supportedScripts: [ChromeMV3DeclaredContentScriptAttachmentRecord] {
        declaredScripts.filter(\.canAttachIfURLAndPermissionMatch)
    }

    static func make(
        manifest: ChromeMV3Manifest,
        generatedBundleRootURL: URL,
        extensionID: String,
        profileID: String
    ) -> ChromeMV3ContentScriptAttachmentPlan {
        let root = generatedBundleRootURL.standardizedFileURL
        let records = manifest.contentScripts.enumerated().map { index, script in
            record(
                script,
                index: index,
                root: root,
                extensionID: extensionID,
                profileID: profileID
            )
        }
        return ChromeMV3ContentScriptAttachmentPlan(
            extensionID: extensionID,
            profileID: profileID,
            generatedBundleRootPath: root.path,
            declaredScripts: records.sorted {
                $0.contentScriptIndex < $1.contentScriptIndex
            },
            diagnostics:
                uniqueSortedContentScripts(
                    records.flatMap(\.diagnostics)
                        + [
                            "Attachment plan was built only from manifest-declared content_scripts.",
                            "scripting.executeScript remains outside this plan.",
                        ]
                )
        )
    }

    private static func record(
        _ script: ChromeMV3ContentScript,
        index: Int,
        root: URL,
        extensionID: String,
        profileID: String
    ) -> ChromeMV3DeclaredContentScriptAttachmentRecord {
        var blockers: [ChromeMV3ContentScriptBlockedReason] = []
        var diagnostics: [String] = []
        let normalizedJS = script.js.map {
            ChromeMV3ContentScriptResourcePath.normalize($0)
        }
        let normalizedCSS = script.css.map {
            ChromeMV3ContentScriptResourcePath.normalize($0)
        }
        var validatedJSPaths: [String] = []

        if script.matches.isEmpty {
            blockers.append(.manifestContentScriptInvalid)
            diagnostics.append("content_scripts[\(index)] has no matches.")
        }
        if normalizedJS.isEmpty {
            blockers.append(.manifestContentScriptInvalid)
            diagnostics.append("content_scripts[\(index)] has no JS files.")
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
        for normalized in normalizedCSS {
            switch normalized {
            case .success(let path):
                blockers.append(.cssUnsupported)
                diagnostics.append(
                    "content_scripts[\(index)] CSS file \(path) is blocked; no safe product CSS attachment path is enabled."
                )
            case .failure(let diagnostic):
                blockers.append(.cssUnsupported)
                diagnostics.append(diagnostic.message)
            }
        }
        for pattern in script.matches + script.excludeMatches {
            let parsed = ChromeMV3ContentScriptMatchPattern(pattern)
            if parsed.status != .valid {
                blockers.append(.unsupportedMatchPattern)
                diagnostics.append(contentsOf: parsed.diagnostics)
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
                validatedJSPaths: validatedJSPaths,
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
                validatedJSPaths: validatedJSPaths,
                blockers: blockers,
                diagnostics: diagnostics
            )
        }
        if world == .main {
            blockers.append(.unsupportedWorld)
            diagnostics.append(
                "content_scripts[\(index)] MAIN world is blocked by Sumi developer-preview policy."
            )
        }
        if script.allFrames {
            blockers.append(.frameBehaviorUnsupported)
            diagnostics.append(
                "content_scripts[\(index)] all_frames=true is blocked until per-frame URL eligibility is wired."
            )
        }
        if script.matchAboutBlank {
            blockers.append(.frameBehaviorUnsupported)
            diagnostics.append(
                "content_scripts[\(index)] match_about_blank requires parent-frame matching that is not wired."
            )
        }
        if script.matchOriginAsFallback {
            blockers.append(.frameBehaviorUnsupported)
            diagnostics.append(
                "content_scripts[\(index)] match_origin_as_fallback requires origin fallback matching that is not wired."
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
            validatedJSPaths: validatedJSPaths,
            blockers: blockers,
            diagnostics: diagnostics
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
        validatedJSPaths: [String],
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
            matchAboutBlank: script.matchAboutBlank,
            matchOriginAsFallback: script.matchOriginAsFallback,
            world: world,
            validatedJSFilePaths: validatedJSPaths.sorted(),
            supported: normalizedBlockers.isEmpty,
            blockers: normalizedBlockers,
            diagnostics:
                uniqueSortedContentScripts(
                    diagnostics
                        + [
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
    var canAttachDeclaredContentScriptsNow: Bool
    var canExposeContentScriptBridgeNow: Bool
    var canRegisterEndpointNow: Bool
    var matchedScripts: [ChromeMV3DeclaredContentScriptAttachmentRecord]
    var skippedScripts: [ChromeMV3DeclaredContentScriptAttachmentRecord]
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

        let matched = input.attachmentPlan.declaredScripts.filter {
            $0.canAttachIfURLAndPermissionMatch && $0.matchesURL(input.urlString)
        }
        let skipped = input.attachmentPlan.declaredScripts.filter {
            matched.contains($0) == false
        }
        if matched.isEmpty {
            blockers.append(.noEligibleDeclaredContentScript)
            if input.attachmentPlan.declaredScripts.contains(where: {
                $0.matchesURL(input.urlString)
            }) == false
            {
                blockers.append(.urlNotMatched)
            }
            diagnostics.append(
                "No declared content script matched the target URL with current support and permission gates."
            )
        }
        for script in skipped {
            diagnostics.append(contentsOf: script.diagnostics)
        }

        let normalizedBlockers = Array(Set(blockers)).sorted()
        let canAttach = normalizedBlockers.isEmpty && matched.isEmpty == false
        return ChromeMV3NormalTabContentScriptPreflight(
            profileID: input.attachmentPlan.profileID,
            extensionID: input.attachmentPlan.extensionID,
            tabID: input.tabID,
            frameID: input.frameID,
            documentID: input.documentID,
            navigationSequence: input.navigationSequence,
            urlString: input.urlString,
            canAttachDeclaredContentScriptsNow: canAttach,
            canExposeContentScriptBridgeNow: canAttach,
            canRegisterEndpointNow: canAttach,
            matchedScripts: matched.sorted {
                $0.contentScriptIndex < $1.contentScriptIndex
            },
            skippedScripts: skipped.sorted {
                $0.contentScriptIndex < $1.contentScriptIndex
            },
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
                            "scripting.executeScript remains blocked and is not part of this preflight.",
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
    case navigationInvalidated
    case navigationStarted
    case resetWhileAttached
    case tabClosed
    case teardownComplete
    case uninstalledWhileAttached

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
    var tabID: Int
    var frameID: Int
    var documentID: String
    var url: String
    var origin: String?
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
    var attachedScriptIDs: [String]
    var messageListenerRegistered: Bool
    var connectListenerRegistered: Bool
    var endpointState: ChromeMV3ContentScriptEndpointLifecycleState
    var senderMetadata: ChromeMV3ContentScriptSenderMetadata
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
    var diagnostics: [String]
}

struct ChromeMV3ContentScriptEndpointRegistrySummary:
    Codable,
    Equatable,
    Sendable
{
    var endpointCount: Int
    var activeEndpointCount: Int
    var messageListenerEndpointCount: Int
    var connectListenerEndpointCount: Int
    var portCount: Int
    var endpointIDs: [String]
    var tabsWithEndpoints: [Int]
    var lifecycleStates: [ChromeMV3ContentScriptEndpointLifecycleState]
    var diagnostics: [String]
}

final class ChromeMV3ContentScriptEndpointRegistry {
    private var endpoints: [ChromeMV3ContentScriptEndpointRecord] = []
    private var lifecycleRecords:
        [ChromeMV3ContentScriptEndpointLifecycleRecord] = []
    private var ports: [ChromeMV3ContentScriptModeledPortRecord] = []
    private var nextSequence = 1

    init() {}

    var summary: ChromeMV3ContentScriptEndpointRegistrySummary {
        let active = endpoints.filter(\.active)
        return ChromeMV3ContentScriptEndpointRegistrySummary(
            endpointCount: endpoints.count,
            activeEndpointCount: active.count,
            messageListenerEndpointCount:
                active.filter(\.messageListenerRegistered).count,
            connectListenerEndpointCount:
                active.filter(\.connectListenerRegistered).count,
            portCount: ports.count,
            endpointIDs: endpoints.map(\.endpointID).sorted(),
            tabsWithEndpoints:
                Array(Set(active.map(\.tabID))).sorted(),
            lifecycleStates:
                Array(Set(lifecycleRecords.map(\.state))).sorted(),
            diagnostics:
                uniqueSortedContentScripts(
                    endpoints.flatMap(\.diagnostics)
                        + lifecycleRecords.map(\.reason)
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
            attachedScriptIDs:
                preflight.matchedScripts.map(\.contentScriptID).sorted(),
            messageListenerRegistered: messageListenerRegistered,
            connectListenerRegistered: connectListenerRegistered,
            endpointState:
                (messageListenerRegistered || connectListenerRegistered)
                    ? .listenerRegistered
                    : .endpointRegistered,
            senderMetadata: ChromeMV3ContentScriptSenderMetadata(
                tabID: preflight.tabID,
                frameID: preflight.frameID,
                documentID: preflight.documentID,
                url: preflight.urlString,
                origin:
                    ChromeMV3RuntimeMessagingURL.origin(
                        from: preflight.urlString
                    )
            ),
            teardownReason: nil,
            diagnostics:
                uniqueSortedContentScripts(
                    preflight.diagnostics
                        + [
                            "Content-script endpoint registered for extension/tab/frame/navigation scope.",
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

    func targetEndpoint(
        extensionID: String,
        profileID: String,
        tabID: Int,
        frameID: Int?,
        documentID: String?
    ) -> ChromeMV3ContentScriptEndpointRecord? {
        endpoints
            .filter {
                $0.active
                    && $0.extensionID == extensionID
                    && $0.profileID == profileID
                    && $0.tabID == tabID
                    && (frameID == nil || $0.frameID == frameID)
                    && (documentID == nil || $0.documentID == documentID)
            }
            .sorted {
                if $0.navigationSequence != $1.navigationSequence {
                    return $0.navigationSequence > $1.navigationSequence
                }
                return $0.endpointID < $1.endpointID
            }
            .first
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
            diagnostics: [
                "tabs.connect opened a modeled Port to a registered content-script endpoint.",
                "No service-worker keepalive or native messaging path was used.",
            ]
        )
        ports.append(port)
        return port
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

    func tearDownAll(reason: String = "Content-script registry reset.") {
        for index in endpoints.indices where endpoints[index].active {
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
        ports.removeAll { port in
            endpoints.contains {
                $0.endpointID == port.endpointID && $0.active == false
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
            appendLifecycle(
                endpointID: endpointID,
                state: .navigationInvalidated,
                reason: "Duplicate endpoint registration invalidated stale endpoint."
            )
        }
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
            "nativeHostLaunchAttempted": nativeHostLaunchAttempted,
            "diagnostics": diagnostics,
        ]
    }
}

private extension ChromeMV3StorageValue {
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

    init(
        extensionID: String,
        profileID: String,
        tabID: Int,
        frameID: Int,
        documentID: String,
        urlString: String,
        permissionBroker: ChromeMV3PermissionBroker,
        endpointRegistry: ChromeMV3ContentScriptEndpointRegistry
    ) {
        self.extensionID = extensionID
        self.profileID = profileID
        self.tabID = tabID
        self.frameID = frameID
        self.documentID = documentID
        self.urlString = urlString
        self.permissionBroker = permissionBroker
        self.endpointRegistry = endpointRegistry
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
            return runtimeSendMessage(bridgeCallID: bridgeCallID)
        case ("runtime", "connect"):
            return blocked(
                bridgeCallID: bridgeCallID,
                code: .routeNotImplemented,
                diagnostics: [
                    "runtime.connect from content scripts remains blocked until Port delivery to extension surfaces is safe."
                ]
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

    private func runtimeSendMessage(
        bridgeCallID: String
    ) -> ChromeMV3ContentScriptBridgeResponse {
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

    private func success(
        bridgeCallID: String,
        payload: ChromeMV3StorageValue,
        diagnostics: [String]
    ) -> ChromeMV3ContentScriptBridgeResponse {
        ChromeMV3ContentScriptBridgeResponse(
            bridgeCallID: bridgeCallID,
            succeeded: true,
            resultPayload: payload,
            lastErrorCode: nil,
            lastErrorMessage: nil,
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false,
            diagnostics: uniqueSortedContentScripts(diagnostics)
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
    private var messageHandlerName: String?
    private var contentWorld: WKContentWorld
    private var scriptHandler: ChromeMV3ContentScriptWKScriptMessageHandler?
    private let endpointRegistry: ChromeMV3ContentScriptEndpointRegistry
    private var endpointID: String?
    private var tornDown = false

    init(
        configuration: WKWebViewConfiguration,
        installedScripts: [WKUserScript],
        messageHandlerName: String?,
        contentWorld: WKContentWorld,
        scriptHandler: ChromeMV3ContentScriptWKScriptMessageHandler?,
        endpointRegistry: ChromeMV3ContentScriptEndpointRegistry,
        endpointID: String?
    ) {
        self.configuration = configuration
        self.installedScripts = installedScripts
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
            removeInstalledUserScripts(
                installedScripts,
                from: configuration.userContentController
            )
        }
        endpointRegistry.tearDownAll(reason: reason)
        installedScripts.removeAll()
        scriptHandler = nil
        messageHandlerName = nil
        tornDown = true
    }

    private func removeInstalledUserScripts(
        _ scripts: [WKUserScript],
        from userContentController: WKUserContentController
    ) {
        guard scripts.isEmpty == false else { return }
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
        endpointRegistry: ChromeMV3ContentScriptEndpointRegistry
    ) -> (
        result: ChromeMV3ContentScriptWKAttachmentResult,
        handle: ChromeMV3ContentScriptWKAttachmentHandle?
    ) {
        guard preflight.canAttachDeclaredContentScriptsNow,
              preflight.canExposeContentScriptBridgeNow
        else {
            return (
                ChromeMV3ContentScriptWKAttachmentResult(
                    attemptedAttachment: true,
                    attached: false,
                    installedUserScriptCount: 0,
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
        let host = ChromeMV3ContentScriptBridgeHost(
            extensionID: preflight.extensionID,
            profileID: preflight.profileID,
            tabID: preflight.tabID,
            frameID: preflight.frameID,
            documentID: preflight.documentID,
            urlString: preflight.urlString,
            permissionBroker: permissionBroker,
            endpointRegistry: endpointRegistry
        )
        let handler = ChromeMV3ContentScriptWKScriptMessageHandler(host: host)
        configuration.userContentController.addScriptMessageHandler(
            handler,
            contentWorld: contentWorld,
            name: messageHandlerName
        )

        var installedScripts: [WKUserScript] = []
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

        for script in preflight.matchedScripts {
            guard let runAt = script.runAt else { continue }
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

        let endpoint = endpointRegistry.registerEndpoint(preflight: preflight)
        let handle = ChromeMV3ContentScriptWKAttachmentHandle(
            configuration: configuration,
            installedScripts: installedScripts,
            messageHandlerName: messageHandlerName,
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
                installedScriptMessageHandlerCount: 1,
                endpointRegistered: endpoint != nil,
                endpointID: endpoint?.endpointID,
                blockers: [],
                diagnostics:
                    uniqueSortedContentScripts(
                        preflight.diagnostics
                            + [
                                "WKUserScript attachment installed a scoped content-script bridge and declared JS files.",
                                "document_idle maps to WKUserScript atDocumentEnd in this developer-preview path.",
                            ]
                    )
            ),
            handle
        )
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
              const port = {
                name,
                onMessage: makeEvent("registerPortOnMessage"),
                onDisconnect: makeEvent("registerPortOnDisconnect"),
                postMessage(message) {
                  return callbackOrPromise("runtime", "connect", [message], null);
                },
                disconnect() {}
              };
              post("runtime", "connect", { arguments: [connectInfo || {}] });
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
    var diagnostics: [String]

    init(_ rawValue: String) {
        self.rawValue = rawValue
        let hostPattern = ChromeMV3HostMatchPattern(rawValue)
        self.status = hostPattern.status
        self.pathPattern = hostPattern.pathPattern
        self.diagnostics = hostPattern.diagnostics
    }

    func matches(_ urlString: String) -> Bool {
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
        let fileURL = root.appendingPathComponent(relativePath)
            .standardizedFileURL
        guard fileURL.path.hasPrefix(root.path + "/") else {
            return (
                false,
                .unsafeJSPath,
                ["Content-script JS path escapes generated bundle root: \(relativePath)."]
            )
        }
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else {
            return (
                false,
                .missingJSFile,
                ["Content-script JS file is missing: \(relativePath)."]
            )
        }
        if (try? manager.destinationOfSymbolicLink(atPath: fileURL.path)) != nil {
            return (
                false,
                .unsafeJSPath,
                ["Content-script JS file is a symbolic link: \(relativePath)."]
            )
        }
        guard let values = try? fileURL.resourceValues(
            forKeys: [.isRegularFileKey]
        ), values.isRegularFile == true
        else {
            return (
                false,
                .unsafeJSPath,
                ["Content-script JS path is not a regular file: \(relativePath)."]
            )
        }
        return (
            true,
            nil,
            ["Content-script JS file validated: \(relativePath)."]
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
