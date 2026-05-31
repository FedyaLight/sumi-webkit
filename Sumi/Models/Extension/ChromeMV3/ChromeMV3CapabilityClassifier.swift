//
//  ChromeMV3CapabilityClassifier.swift
//  Sumi
//
//  Conservative install-time API classification. This is a registry, not a
//  runtime support claim.
//

import Foundation

enum ChromeMV3API: String, Codable, CaseIterable, Comparable, Sendable {
    case runtime
    case storage
    case tabs
    case scripting
    case action
    case permissions
    case activeTab
    case contextMenus
    case cookies
    case alarms
    case webNavigation
    case webRequest
    case declarativeNetRequest
    case nativeMessaging
    case sidePanel
    case offscreen
    case identity
    case debugger
    case devtools
    case enterprise
    case i18n
    case notifications
    case downloads
    case bookmarks
    case history

    static func < (lhs: ChromeMV3API, rhs: ChromeMV3API) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3CapabilityStatus: String, Codable, CaseIterable, Comparable, Sendable {
    case nativeWebKit
    case shim
    case nativeHost
    case unsupported
    case deferred
    case needsVerification

    static func < (
        lhs: ChromeMV3CapabilityStatus,
        rhs: ChromeMV3CapabilityStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3CapabilityEvidenceKind: String, Codable, CaseIterable, Sendable {
    case chromeDocumentation
    case appleDocumentation
    case localAppleSDKHeaders
    case currentSumiCode
    case fixtureVerificationNeeded
    case deferredUnknown
}

struct ChromeMV3CapabilityEvidence: Codable, Equatable, Sendable {
    var kind: ChromeMV3CapabilityEvidenceKind
    var source: String
    var note: String
}

struct ChromeMV3CapabilityClassification: Codable, Equatable, Sendable {
    var api: ChromeMV3API
    var statuses: [ChromeMV3CapabilityStatus]
    var evidence: [ChromeMV3CapabilityEvidence]
    var detectedByManifest: Bool
}

private struct ChromeMV3CapabilityDefinition: Sendable {
    var api: ChromeMV3API
    var statuses: [ChromeMV3CapabilityStatus]
    var evidence: [ChromeMV3CapabilityEvidence]
    var detection: ChromeMV3CapabilityDetection

    func classification(
        for manifest: ChromeMV3Manifest
    ) -> ChromeMV3CapabilityClassification {
        ChromeMV3CapabilityClassification(
            api: api,
            statuses: statuses.sorted(),
            evidence: evidence,
            detectedByManifest: detection.isDetected(in: manifest)
        )
    }
}

private enum ChromeMV3CapabilityDetection: Sendable {
    case always
    case permission(String)
    case permissionPrefix(String)
    case anyPermission([String])
    case permissionsAPI
    case scripting
    case action
    case declarativeNetRequest
    case sidePanel
    case offscreen
    case identity
    case devtools
    case enterprise
    case i18n

    func isDetected(in manifest: ChromeMV3Manifest) -> Bool {
        switch self {
        case .always:
            return true
        case .permission(let permission):
            return manifest.declaresPermission(permission)
        case .permissionPrefix(let prefix):
            return manifest.declaresPermission(withPrefix: prefix)
        case .anyPermission(let permissions):
            return permissions.contains { manifest.declaresPermission($0) }
        case .permissionsAPI:
            return manifest.declaresPermission("permissions")
                || manifest.optionalPermissions.isEmpty == false
                || manifest.hostPermissions.isEmpty == false
        case .scripting:
            return manifest.declaresPermission("scripting")
                || manifest.contentScripts.isEmpty == false
        case .action:
            return manifest.action != nil
        case .declarativeNetRequest:
            return manifest.declarativeNetRequest != nil
                || manifest.declaresPermission("declarativeNetRequest")
                || manifest.declaresPermission("declarativeNetRequestWithHostAccess")
                || manifest.declaresPermission("declarativeNetRequestFeedback")
        case .sidePanel:
            return manifest.sidePanel != nil
                || manifest.declaresPermission("sidePanel")
        case .offscreen:
            return manifest.declaresPermission("offscreen")
        case .identity:
            return manifest.declaresPermission("identity")
                || manifest.declaresPermission("identity.email")
                || manifest.oauth2 != nil
        case .devtools:
            return manifest.devtoolsPage != nil
                || manifest.topLevelKeys.contains("devtools_page")
        case .enterprise:
            return manifest.declaresPermission("enterprise")
                || manifest.declaresPermission(withPrefix: "enterprise.")
        case .i18n:
            return manifest.topLevelKeys.contains("default_locale")
                || manifest.name.hasPrefix("__MSG_")
                || (manifest.description?.hasPrefix("__MSG_") ?? false)
        }
    }
}

enum ChromeMV3CapabilityClassifier {
    static func classify(
        manifest: ChromeMV3Manifest
    ) -> [ChromeMV3CapabilityClassification] {
        definitions
            .map { $0.classification(for: manifest) }
            .filter(\.detectedByManifest)
            .sorted { $0.api < $1.api }
    }

    static func allKnownClassifications() -> [ChromeMV3CapabilityClassification] {
        definitions
            .map {
                ChromeMV3CapabilityClassification(
                    api: $0.api,
                    statuses: $0.statuses.sorted(),
                    evidence: $0.evidence,
                    detectedByManifest: false
                )
            }
            .sorted { $0.api < $1.api }
    }

    private static let chromeAPIReference =
        "https://developer.chrome.com/docs/extensions/reference/api"
    private static let chromeServiceWorkers =
        "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers"
    private static let chromeContentScripts =
        "https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts"
    private static let chromeActiveTab =
        "https://developer.chrome.com/docs/extensions/develop/concepts/activeTab"
    private static let chromeNativeMessaging =
        "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging"
    private static let chromePermissions =
        "https://developer.chrome.com/docs/extensions/develop/concepts/declare-permissions"
    private static let localSDKHeaders =
        "MacOSX26.5.sdk/System/Library/Frameworks/WebKit.framework/Headers"
    private static let currentSumiExtensions =
        "Sumi/Managers/ExtensionManager"

    // Evidence is intentionally attached to every definition so future runtime
    // work can update a single matrix instead of spreading ad hoc checks.
    private static let definitions: [ChromeMV3CapabilityDefinition] = [
        ChromeMV3CapabilityDefinition(
            api: .runtime,
            statuses: [.nativeWebKit, .shim, .needsVerification],
            evidence: [
                chrome("runtime API and MV3 service-worker lifecycle are Chrome-defined.", chromeAPIReference + "/runtime"),
                chrome("MV3 background execution is service-worker based.", chromeServiceWorkers),
                sdk("WKWebExtensionContext exposes extension identity, unsupportedAPIs, and app-message delegates; exact Chrome messaging parity needs fixtures."),
                fixture("Verify sendMessage/connect, wake behavior, and lifecycle event parity.")
            ],
            detection: .always
        ),
        ChromeMV3CapabilityDefinition(
            api: .storage,
            statuses: [.nativeWebKit, .shim, .needsVerification],
            evidence: [
                chrome("Chrome storage API defines local/session/sync semantics.", chromeAPIReference + "/storage"),
                sdk("WKWebExtensionDataType exposes Local, Session, and Synchronized storage buckets."),
                fixture("Verify local/session/sync persistence and quota behavior before claiming parity.")
            ],
            detection: .permission("storage")
        ),
        ChromeMV3CapabilityDefinition(
            api: .tabs,
            statuses: [.nativeWebKit, .nativeHost, .needsVerification],
            evidence: [
                chrome("Chrome tabs API is a browser tab/window API.", chromeAPIReference + "/tabs"),
                sdk("WKWebExtensionController and WKWebExtensionTab expose tab lifecycle callbacks and tab operations."),
                sumi("Current Sumi ExtensionBridge maps Sumi tabs/windows to WebKit extension protocols."),
                fixture("Verify query/update/create/remove behavior against Chrome expectations.")
            ],
            detection: .permission("tabs")
        ),
        ChromeMV3CapabilityDefinition(
            api: .scripting,
            statuses: [.nativeWebKit, .nativeHost, .needsVerification],
            evidence: [
                chrome("Chrome scripting API and content-script matching are Chrome-defined.", chromeAPIReference + "/scripting"),
                chrome("Content script frame and match behavior requires Chrome fixture parity.", chromeContentScripts),
                sdk("WKWebExtension reports injectable content and requested match patterns."),
                fixture("Verify all_frames, match_about_blank, isolated worlds, and dynamic injection.")
            ],
            detection: .scripting
        ),
        ChromeMV3CapabilityDefinition(
            api: .action,
            statuses: [.nativeWebKit, .nativeHost, .needsVerification],
            evidence: [
                chrome("Chrome action API owns toolbar action state and popups.", chromeAPIReference + "/action"),
                sdk("WKWebExtensionAction exposes action labels, badges, icons, popup web views, and popup presentation callbacks."),
                sumi("Current Sumi action UI surfaces WebKit action state, but Chrome parity still needs fixtures.")
            ],
            detection: .action
        ),
        ChromeMV3CapabilityDefinition(
            api: .permissions,
            statuses: [.nativeHost, .needsVerification],
            evidence: [
                chrome("Chrome permissions and optional permissions require user-grant semantics.", chromePermissions),
                sdk("WKWebExtensionControllerDelegate exposes permission and match-pattern prompts."),
                fixture("Verify optional permission request/revoke and host grant expiry behavior.")
            ],
            detection: .permissionsAPI
        ),
        ChromeMV3CapabilityDefinition(
            api: .activeTab,
            statuses: [.shim, .nativeHost, .needsVerification],
            evidence: [
                chrome("Chrome activeTab creates temporary tab-scoped grants from user gestures.", chromeActiveTab),
                sdk("WKWebExtensionTab exposes shouldGrantPermissionsOnUserGesture."),
                fixture("Verify grant creation and expiry on tab/navigation boundaries.")
            ],
            detection: .permission("activeTab")
        ),
        ChromeMV3CapabilityDefinition(
            api: .contextMenus,
            statuses: [.nativeHost, .deferred],
            evidence: [
                chrome("Chrome contextMenus API creates browser-owned menus.", chromeAPIReference + "/contextMenus"),
                deferred("Needs a Sumi menu ownership spec before runtime support.")
            ],
            detection: .permission("contextMenus")
        ),
        ChromeMV3CapabilityDefinition(
            api: .cookies,
            statuses: [.deferred, .needsVerification],
            evidence: [
                chrome("Chrome cookies API exposes browser cookie stores.", chromeAPIReference + "/cookies"),
                deferred("Do not infer Chrome cookie parity from WKWebsiteDataStore without a profile/privacy design."),
                fixture("Verify store selection, partitioning, and permission behavior.")
            ],
            detection: .permission("cookies")
        ),
        ChromeMV3CapabilityDefinition(
            api: .alarms,
            statuses: [.nativeHost, .shim, .needsVerification],
            evidence: [
                chrome("Chrome alarms API schedules extension events.", chromeAPIReference + "/alarms"),
                fixture("Verify alarms with service-worker wake/unload policy.")
            ],
            detection: .permission("alarms")
        ),
        ChromeMV3CapabilityDefinition(
            api: .webNavigation,
            statuses: [.nativeHost, .needsVerification],
            evidence: [
                chrome("Chrome webNavigation API exposes navigation event ordering.", chromeAPIReference + "/webNavigation"),
                fixture("Verify Sumi/WebKit event mapping and ordering.")
            ],
            detection: .permission("webNavigation")
        ),
        ChromeMV3CapabilityDefinition(
            api: .webRequest,
            statuses: [.unsupported, .deferred],
            evidence: [
                chrome("Chrome webRequest and blocking behavior are constrained in MV3.", chromeAPIReference + "/webRequest"),
                sumi("Current network compatibility layer classifies webRequest events for internal synthetic fixtures only."),
                deferred("No product webRequest blocking, request modification, or product network subscription is implemented.")
            ],
            detection: .anyPermission([
                "webRequest",
                "webRequestBlocking",
                "webRequestAuthProvider",
            ])
        ),
        ChromeMV3CapabilityDefinition(
            api: .declarativeNetRequest,
            statuses: [.shim, .deferred, .needsVerification],
            evidence: [
                chrome("Chrome declarativeNetRequest has Chrome-specific rule semantics.", chromeAPIReference + "/declarativeNetRequest"),
                sumi("Current network compatibility layer parses static rulesets and evaluates static/dynamic/session rules in internal synthetic scope only."),
                deferred("Possible content-rule-list or adblock-rust mapping is not implemented or proven."),
                fixture("Verify rule compatibility before claiming any product enforcement subset.")
            ],
            detection: .declarativeNetRequest
        ),
        ChromeMV3CapabilityDefinition(
            api: .nativeMessaging,
            statuses: [.nativeHost, .deferred],
            evidence: [
                chrome("Chrome native messaging uses host manifests and framed native-process messaging.", chromeNativeMessaging),
                sumi("Current Sumi native messaging bridge exists but needs Chrome MV3 host validation redesign."),
                deferred("Deferred until host validation, consent, and lifecycle rules are specified.")
            ],
            detection: .permission("nativeMessaging")
        ),
        ChromeMV3CapabilityDefinition(
            api: .sidePanel,
            statuses: [.shim, .nativeHost, .deferred],
            evidence: [
                chrome("Chrome sidePanel API requires browser UI ownership and local extension page resources.", chromeAPIReference + "/sidePanel"),
                sumi("Current compatibility layer can resolve side_panel.default_path, model selected sidePanel methods, and run WebKit-executed synthetic JS only in a gated internal harness."),
                deferred("No Sumi side-panel product UI or normal-tab runtime host is implemented.")
            ],
            detection: .sidePanel
        ),
        ChromeMV3CapabilityDefinition(
            api: .offscreen,
            statuses: [.shim, .deferred, .needsVerification],
            evidence: [
                chrome("Chrome offscreen API creates bounded extension-local offscreen documents with URL, reasons, and justification.", chromeAPIReference + "/offscreen"),
                sumi("Current compatibility layer validates offscreen requests, records model-only state, and verifies synthetic JS calls in a gated WebKit harness."),
                deferred("No hidden offscreen document product runtime is allowed by this task."),
                fixture("Verify if a bounded host is ever justified; never emulate persistent background pages.")
            ],
            detection: .offscreen
        ),
        ChromeMV3CapabilityDefinition(
            api: .identity,
            statuses: [.shim, .nativeHost, .deferred],
            evidence: [
                chrome("Chrome identity API owns redirect URL generation, OAuth WebAuth flows, token cache, and profile account behavior.", chromeAPIReference + "/identity"),
                sumi("Current compatibility layer returns deterministic redirect URLs and verifies identity JS calls in WebKit with blocked defaults and explicit synthetic fixtures only."),
                deferred("Requires product privacy and account-flow design before any real OAuth UI or network path.")
            ],
            detection: .identity
        ),
        ChromeMV3CapabilityDefinition(
            api: .debugger,
            statuses: [.unsupported],
            evidence: [
                chrome("Chrome debugger API exposes debugging protocol access.", chromeAPIReference + "/debugger"),
                deferred("Not a Sumi consumer-extension target.")
            ],
            detection: .permission("debugger")
        ),
        ChromeMV3CapabilityDefinition(
            api: .devtools,
            statuses: [.unsupported],
            evidence: [
                chrome("Chrome DevTools extension APIs are DevTools-panel specific.", chromeAPIReference + "/devtools"),
                deferred("No Sumi DevTools extension host exists in this foundation.")
            ],
            detection: .devtools
        ),
        ChromeMV3CapabilityDefinition(
            api: .enterprise,
            statuses: [.unsupported],
            evidence: [
                chrome("Chrome enterprise APIs are managed-environment APIs.", chromeAPIReference + "/enterprise_platformKeys"),
                deferred("Enterprise extension APIs are outside Sumi's v1 consumer target.")
            ],
            detection: .enterprise
        ),
        ChromeMV3CapabilityDefinition(
            api: .i18n,
            statuses: [.shim, .needsVerification],
            evidence: [
                chrome("Chrome i18n API resolves extension locale messages and exposes the browser UI language.", chromeAPIReference + "/i18n"),
                sumi("The local experimental MV3 service-worker harness implements only chrome.i18n.getUILanguage with a deterministic locale source; message catalogs and detection remain blocked."),
                fixture("Verify Chrome placeholder, fallback, and message formatting behavior before expanding beyond getUILanguage.")
            ],
            detection: .i18n
        ),
        ChromeMV3CapabilityDefinition(
            api: .notifications,
            statuses: [.nativeHost, .deferred],
            evidence: [
                chrome("Chrome notifications API creates browser-mediated notifications.", chromeAPIReference + "/notifications"),
                deferred("Needs Sumi notification permission and UX policy.")
            ],
            detection: .permission("notifications")
        ),
        ChromeMV3CapabilityDefinition(
            api: .downloads,
            statuses: [.nativeHost, .deferred],
            evidence: [
                chrome("Chrome downloads API controls browser downloads.", chromeAPIReference + "/downloads"),
                deferred("Needs Sumi download manager permission and UX design.")
            ],
            detection: .permission("downloads")
        ),
        ChromeMV3CapabilityDefinition(
            api: .bookmarks,
            statuses: [.nativeHost, .deferred],
            evidence: [
                chrome("Chrome bookmarks API exposes browser bookmarks.", chromeAPIReference + "/bookmarks"),
                deferred("Needs Sumi bookmarks API and privacy design.")
            ],
            detection: .permission("bookmarks")
        ),
        ChromeMV3CapabilityDefinition(
            api: .history,
            statuses: [.nativeHost, .deferred],
            evidence: [
                chrome("Chrome history API exposes browser history.", chromeAPIReference + "/history"),
                deferred("Needs Sumi history API and privacy design.")
            ],
            detection: .permission("history")
        )
    ]

    private static func chrome(
        _ note: String,
        _ source: String
    ) -> ChromeMV3CapabilityEvidence {
        ChromeMV3CapabilityEvidence(
            kind: .chromeDocumentation,
            source: source,
            note: note
        )
    }

    private static func sdk(_ note: String) -> ChromeMV3CapabilityEvidence {
        ChromeMV3CapabilityEvidence(
            kind: .localAppleSDKHeaders,
            source: localSDKHeaders,
            note: note
        )
    }

    private static func apple(_ note: String) -> ChromeMV3CapabilityEvidence {
        ChromeMV3CapabilityEvidence(
            kind: .appleDocumentation,
            source: "https://developer.apple.com/documentation/webkit",
            note: note
        )
    }

    private static func sumi(_ note: String) -> ChromeMV3CapabilityEvidence {
        ChromeMV3CapabilityEvidence(
            kind: .currentSumiCode,
            source: currentSumiExtensions,
            note: note
        )
    }

    private static func fixture(_ note: String) -> ChromeMV3CapabilityEvidence {
        ChromeMV3CapabilityEvidence(
            kind: .fixtureVerificationNeeded,
            source: "future Chrome MV3 fixture suite",
            note: note
        )
    }

    private static func deferred(_ note: String) -> ChromeMV3CapabilityEvidence {
        ChromeMV3CapabilityEvidence(
            kind: .deferredUnknown,
            source: "deferred until a future Chrome MV3 runtime task",
            note: note
        )
    }
}
