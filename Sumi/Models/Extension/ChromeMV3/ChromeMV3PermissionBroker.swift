//
//  ChromeMV3PermissionBroker.swift
//  Sumi
//
//  Host-side Chrome MV3 permission and activeTab broker skeleton. This file is
//  a deterministic model only: it does not create WebKit contexts, prompt the
//  user, persist grants, inject scripts, dispatch messages, open ports, launch
//  native messaging, or schedule work.
//

import CryptoKit
import Foundation

enum ChromeMV3HostMatchPatternStatus:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case valid
    case unsupportedNeedsVerification
    case invalid
}

enum ChromeMV3HostMatchPatternKind:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case allURLs
    case schemeAndHost
}

enum ChromeMV3HostMatchPatternScheme:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case http
    case https
    case httpOrHTTPS
}

struct ChromeMV3HostMatchPattern:
    Codable,
    Equatable,
    Sendable
{
    var rawValue: String
    var status: ChromeMV3HostMatchPatternStatus
    var kind: ChromeMV3HostMatchPatternKind?
    var scheme: ChromeMV3HostMatchPatternScheme?
    var hostPattern: String?
    var pathPattern: String?
    var pathIgnoredForHostPermission: Bool
    var diagnostics: [String]

    init(_ rawValue: String) {
        let parsed = Self.parse(rawValue)
        self.rawValue = rawValue
        self.status = parsed.status
        self.kind = parsed.kind
        self.scheme = parsed.scheme
        self.hostPattern = parsed.hostPattern
        self.pathPattern = parsed.pathPattern
        self.pathIgnoredForHostPermission = parsed.pathIgnoredForHostPermission
        self.diagnostics = parsed.diagnostics
    }

    var isValid: Bool {
        status == .valid
    }

    var isUnsupported: Bool {
        status == .unsupportedNeedsVerification
    }

    var isInvalid: Bool {
        status == .invalid
    }

    func matches(url urlString: String?) -> Bool {
        guard let urlString,
              status == .valid,
              let components = URLComponents(string: urlString),
              let urlScheme = components.scheme?.lowercased()
        else { return false }

        switch kind {
        case .allURLs:
            return Self.supportedURLSchemes.contains(urlScheme)
        case .schemeAndHost:
            guard let host = components.host?.lowercased(),
                  schemeMatches(urlScheme),
                  hostMatches(host)
            else { return false }
            return true
        case nil:
            return false
        }
    }

    func matches(origin originString: String?) -> Bool {
        matches(url: originString)
    }

    private func schemeMatches(_ urlScheme: String) -> Bool {
        switch scheme {
        case .http:
            return urlScheme == "http"
        case .https:
            return urlScheme == "https"
        case .httpOrHTTPS:
            return Self.supportedURLSchemes.contains(urlScheme)
        case nil:
            return false
        }
    }

    private func hostMatches(_ host: String) -> Bool {
        guard let hostPattern else { return false }
        if hostPattern == "*" {
            return true
        }
        if hostPattern.hasPrefix("*.") {
            let suffix = String(hostPattern.dropFirst(2))
            return host == suffix || host.hasSuffix(".\(suffix)")
        }
        return host == hostPattern
    }

    private static let supportedURLSchemes = Set(["http", "https"])

    private static func parse(
        _ rawValue: String
    ) -> (
        status: ChromeMV3HostMatchPatternStatus,
        kind: ChromeMV3HostMatchPatternKind?,
        scheme: ChromeMV3HostMatchPatternScheme?,
        hostPattern: String?,
        pathPattern: String?,
        pathIgnoredForHostPermission: Bool,
        diagnostics: [String]
    ) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else {
            return (
                .invalid,
                nil,
                nil,
                nil,
                nil,
                false,
                ["Match pattern is empty."]
            )
        }

        if value == "<all_urls>" {
            return (
                .valid,
                .allURLs,
                .httpOrHTTPS,
                "*",
                "/*",
                true,
                [
                    "<all_urls> is modeled for http and https host access only.",
                ]
            )
        }

        let parts = value.split(separator: "://", maxSplits: 1)
        guard parts.count == 2 else {
            return (
                .invalid,
                nil,
                nil,
                nil,
                nil,
                false,
                ["Match pattern must contain a scheme followed by ://."]
            )
        }

        let schemeValue = String(parts[0]).lowercased()
        let scheme: ChromeMV3HostMatchPatternScheme
        switch schemeValue {
        case "http":
            scheme = .http
        case "https":
            scheme = .https
        case "*":
            scheme = .httpOrHTTPS
        case "file":
            return (
                .unsupportedNeedsVerification,
                nil,
                nil,
                nil,
                nil,
                false,
                [
                    "file match patterns require separate user file-access policy and are not modeled by this broker.",
                ]
            )
        default:
            return (
                .unsupportedNeedsVerification,
                nil,
                nil,
                nil,
                nil,
                false,
                [
                    "Only http, https, and * schemes are modeled for host access.",
                ]
            )
        }

        let hostAndPath = String(parts[1])
        guard let slashIndex = hostAndPath.firstIndex(of: "/") else {
            return (
                .invalid,
                nil,
                nil,
                nil,
                nil,
                false,
                ["Match pattern must include a path beginning with /."]
            )
        }

        let hostValue = String(hostAndPath[..<slashIndex]).lowercased()
        let pathValue = String(hostAndPath[slashIndex...])
        guard hostValue.isEmpty == false else {
            return (
                .invalid,
                nil,
                nil,
                nil,
                nil,
                false,
                ["Host pattern is empty."]
            )
        }
        guard pathValue.hasPrefix("/") else {
            return (
                .invalid,
                nil,
                nil,
                nil,
                nil,
                false,
                ["Path pattern must begin with /."]
            )
        }
        guard hostValue.contains(":") == false else {
            return (
                .unsupportedNeedsVerification,
                nil,
                nil,
                nil,
                nil,
                false,
                [
                    "Port-specific host patterns are not modeled by this broker.",
                ]
            )
        }
        guard hostWildcardIsValid(hostValue) else {
            return (
                .invalid,
                nil,
                nil,
                nil,
                nil,
                false,
                [
                    "Host wildcard must be the whole host or the leading *. prefix.",
                ]
            )
        }
        if hostValue.hasPrefix("*."),
           hostValue.dropFirst(2).contains(".") == false
        {
            return (
                .unsupportedNeedsVerification,
                nil,
                nil,
                nil,
                nil,
                false,
                [
                    "Top-level domain wildcard patterns are not modeled.",
                ]
            )
        }

        return (
            .valid,
            .schemeAndHost,
            scheme,
            hostValue,
            pathValue,
            true,
            [
                "Pattern is valid for modeled host access; path is recorded but ignored for host-permission decisions.",
            ]
        )
    }

    private static func hostWildcardIsValid(_ host: String) -> Bool {
        guard host.contains("*") else { return true }
        return host == "*" || host.hasPrefix("*.") && host.dropFirst(2)
            .contains("*") == false
    }
}

enum ChromeMV3PermissionBrokerGrantSource:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case none
    case requiredPermission
    case optionalPermissionModeledGrant
    case requiredHostPermission
    case optionalHostPermissionModeledGrant
    case activeTabGrant
}

enum ChromeMV3PermissionBrokerDecisionStatus:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case allowed
    case blocked
    case promptRequired
    case denied
    case revoked
    case deferred
    case unsupported
}

enum ChromeMV3HostAccessMissingReason:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case none
    case invalidURL
    case permissionDenied
    case permissionRevoked
    case hostPermissionMissing
    case activeTabMissing
    case unsupportedPattern
    case deferredPermission
}

struct ChromeMV3APIPermissionDecision:
    Codable,
    Equatable,
    Sendable
{
    var permission: String
    var status: ChromeMV3PermissionBrokerDecisionStatus
    var grantSource: ChromeMV3PermissionBrokerGrantSource
    var hasPermission: Bool
    var declaredRequired: Bool
    var declaredOptional: Bool
    var grantedOptional: Bool
    var denied: Bool
    var revoked: Bool
    var unsupported: Bool
    var deferred: Bool
    var wouldNeedPrompt: Bool
    var diagnostics: [String]
}

struct ChromeMV3HostAccessDecision:
    Codable,
    Equatable,
    Sendable
{
    var url: String?
    var origin: String?
    var status: ChromeMV3PermissionBrokerDecisionStatus
    var grantSource: ChromeMV3PermissionBrokerGrantSource
    var hasHostAccess: Bool
    var allowedByHostPermission: Bool
    var allowedByOptionalHostPermission: Bool
    var allowedByActiveTab: Bool
    var matchingHostPatterns: [String]
    var optionalHostPatternsThatCouldPrompt: [String]
    var invalidHostPatterns: [String]
    var unsupportedHostPatterns: [String]
    var deniedByPattern: Bool
    var revokedByPattern: Bool
    var wouldNeedPrompt: Bool
    var missingReason: ChromeMV3HostAccessMissingReason
    var diagnostics: [String]
}

enum ChromeMV3ActiveTabGrantReason:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case actionClick
    case contextMenu
    case command
    case extensionPageHostFixture
    case testFixture
    case futureUserGesture
}

enum ChromeMV3ActiveTabExpiryTrigger:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case explicitReset
    case tabClose
    case tabNavigation
    case profileClose
    case extensionDisable
    case permissionRevoke

    static func < (
        lhs: ChromeMV3ActiveTabExpiryTrigger,
        rhs: ChromeMV3ActiveTabExpiryTrigger
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ActiveTabGrantScope:
    Codable,
    Equatable,
    Sendable
{
    case origin(String)
    case exactURL(String)

    var diagnosticValue: String {
        switch self {
        case .origin(let origin):
            return origin
        case .exactURL(let url):
            return url
        }
    }

    func matches(url urlString: String?) -> Bool {
        guard let urlString else { return false }
        switch self {
        case .origin(let origin):
            return ChromeMV3PermissionBrokerURL.origin(from: urlString)
                == origin
        case .exactURL(let url):
            return url == urlString
        }
    }

    func expiresOnNavigation(oldURL: String?, newURL: String?) -> Bool {
        guard matches(url: oldURL) else { return false }
        switch self {
        case .origin(let origin):
            return ChromeMV3PermissionBrokerURL.origin(from: newURL) != origin
        case .exactURL(let url):
            return newURL != url
        }
    }
}

struct ChromeMV3ActiveTabExpiryRecord:
    Codable,
    Equatable,
    Sendable
{
    var trigger: ChromeMV3ActiveTabExpiryTrigger
    var sequence: Int
    var reason: String
}

struct ChromeMV3ActiveTabGrant:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var tabID: Int
    var scope: ChromeMV3ActiveTabGrantScope
    var reason: ChromeMV3ActiveTabGrantReason
    var userGestureModeled: Bool
    var createdSequence: Int
    var expiryTriggers: [ChromeMV3ActiveTabExpiryTrigger]
    var expiryRecord: ChromeMV3ActiveTabExpiryRecord?
    var diagnostics: [String]

    init(
        extensionID: String,
        profileID: String,
        tabID: Int,
        scope: ChromeMV3ActiveTabGrantScope,
        reason: ChromeMV3ActiveTabGrantReason,
        userGestureModeled: Bool,
        createdSequence: Int,
        expiryTriggers: [ChromeMV3ActiveTabExpiryTrigger] =
            ChromeMV3ActiveTabExpiryTrigger.allCases.sorted(),
        expiryRecord: ChromeMV3ActiveTabExpiryRecord? = nil,
        diagnostics: [String] = []
    ) {
        self.extensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
        self.profileID = profileID.isEmpty ? "unknown-profile" : profileID
        self.tabID = tabID
        self.scope = scope
        self.reason = reason
        self.userGestureModeled = userGestureModeled
        self.createdSequence = createdSequence
        self.expiryTriggers = Array(Set(expiryTriggers)).sorted()
        self.expiryRecord = expiryRecord
        self.diagnostics = diagnostics
    }

    var active: Bool {
        userGestureModeled && expiryRecord == nil
    }

    func matches(
        extensionID: String,
        profileID: String,
        tabID: Int?,
        url: String?
    ) -> Bool {
        guard active,
              self.extensionID == extensionID,
              self.profileID == profileID,
              self.tabID == tabID
        else { return false }
        return scope.matches(url: url)
    }

    func expiring(
        trigger: ChromeMV3ActiveTabExpiryTrigger,
        sequence: Int,
        reason: String
    ) -> ChromeMV3ActiveTabGrant {
        guard expiryTriggers.contains(trigger), expiryRecord == nil else {
            return self
        }
        var copy = self
        copy.expiryRecord = ChromeMV3ActiveTabExpiryRecord(
            trigger: trigger,
            sequence: sequence,
            reason: reason
        )
        copy.diagnostics = Array(Set(
            diagnostics + ["activeTab grant expired: \(reason)"]
        )).sorted()
        return copy
    }
}

struct ChromeMV3ActiveTabGestureEvent:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var tabID: Int
    var url: String
    var reason: ChromeMV3ActiveTabGrantReason
    var userGestureModeled: Bool
    var sequence: Int
}

struct ChromeMV3ActiveTabAccessDecision:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var tabID: Int?
    var url: String?
    var hasGrant: Bool
    var matchingGrant: ChromeMV3ActiveTabGrant?
    var missingReason: ChromeMV3RuntimeMessagingMissingGrantReason
    var diagnostics: [String]
}

struct ChromeMV3ActiveTabGrantBroker:
    Codable,
    Equatable,
    Sendable
{
    var grants: [ChromeMV3ActiveTabGrant]

    init(grants: [ChromeMV3ActiveTabGrant] = []) {
        self.grants = grants.sorted {
            if $0.extensionID != $1.extensionID {
                return $0.extensionID < $1.extensionID
            }
            if $0.profileID != $1.profileID {
                return $0.profileID < $1.profileID
            }
            if $0.tabID != $1.tabID {
                return $0.tabID < $1.tabID
            }
            return $0.createdSequence < $1.createdSequence
        }
    }

    func hasActiveTabGrant(
        extensionID: String,
        profileID: String,
        tabID: Int?,
        url: String?
    ) -> Bool {
        activeTabDecision(
            extensionID: extensionID,
            profileID: profileID,
            tabID: tabID,
            url: url,
            activeTabPermissionDeclared: true,
            userGestureAvailable: false
        ).hasGrant
    }

    func activeTabDecision(
        extensionID: String,
        profileID: String,
        tabID: Int?,
        url: String?,
        activeTabPermissionDeclared: Bool,
        userGestureAvailable: Bool
    ) -> ChromeMV3ActiveTabAccessDecision {
        let normalizedExtensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
        let normalizedProfileID = profileID.isEmpty
            ? "unknown-profile"
            : profileID
        let match = grants.first {
            $0.matches(
                extensionID: normalizedExtensionID,
                profileID: normalizedProfileID,
                tabID: tabID,
                url: url
            )
        }
        let missingReason: ChromeMV3RuntimeMessagingMissingGrantReason
        if match != nil {
            missingReason = .none
        } else if activeTabPermissionDeclared == false {
            missingReason = .missingActiveTabGrant
        } else if userGestureAvailable {
            missingReason = .missingActiveTabGrant
        } else {
            missingReason = .userGestureRequired
        }

        return ChromeMV3ActiveTabAccessDecision(
            extensionID: normalizedExtensionID,
            profileID: normalizedProfileID,
            tabID: tabID,
            url: url,
            hasGrant: match != nil,
            matchingGrant: match,
            missingReason: missingReason,
            diagnostics: match.map {
                [
                    "Modeled activeTab grant \(String(describing: $0.scope.diagnosticValue)) grants temporary host access.",
                ]
            } ?? [
                activeTabPermissionDeclared
                    ? "No activeTab grant matches the target tab and origin."
                    : "activeTab permission is not declared."
            ]
        )
    }

    func wouldGrantFromGesture(
        _ event: ChromeMV3ActiveTabGestureEvent,
        activeTabPermissionDeclared: Bool
    ) -> Bool {
        activeTabPermissionDeclared && event.userGestureModeled
    }

    func grantFromGesture(
        _ event: ChromeMV3ActiveTabGestureEvent,
        activeTabPermissionDeclared: Bool
    ) -> ChromeMV3ActiveTabGrant? {
        guard wouldGrantFromGesture(
            event,
            activeTabPermissionDeclared: activeTabPermissionDeclared
        ), let origin = ChromeMV3PermissionBrokerURL.origin(from: event.url)
        else { return nil }
        return ChromeMV3ActiveTabGrant(
            extensionID: event.extensionID,
            profileID: event.profileID,
            tabID: event.tabID,
            scope: .origin(origin),
            reason: event.reason,
            userGestureModeled: event.userGestureModeled,
            createdSequence: event.sequence,
            diagnostics: [
                "Modeled activeTab grant created from \(event.reason.rawValue).",
            ]
        )
    }

    func expiresOnNavigation(
        grant: ChromeMV3ActiveTabGrant,
        oldURL: String?,
        newURL: String?
    ) -> Bool {
        grant.expiryTriggers.contains(.tabNavigation)
            && grant.scope.expiresOnNavigation(oldURL: oldURL, newURL: newURL)
    }

    func expiresOnTabClose(
        grant: ChromeMV3ActiveTabGrant,
        tabID: Int
    ) -> Bool {
        grant.expiryTriggers.contains(.tabClose) && grant.tabID == tabID
    }

    func expiresOnExtensionDisable(
        grant: ChromeMV3ActiveTabGrant,
        extensionID: String
    ) -> Bool {
        grant.expiryTriggers.contains(.extensionDisable)
            && grant.extensionID == extensionID
    }

    func applyingNavigation(
        extensionID: String,
        profileID: String,
        tabID: Int,
        oldURL: String?,
        newURL: String?,
        sequence: Int
    ) -> ChromeMV3ActiveTabGrantBroker {
        ChromeMV3ActiveTabGrantBroker(
            grants: grants.map { grant in
                guard grant.extensionID == extensionID,
                      grant.profileID == profileID,
                      grant.tabID == tabID,
                      expiresOnNavigation(
                        grant: grant,
                        oldURL: oldURL,
                        newURL: newURL
                      )
                else { return grant }
                return grant.expiring(
                    trigger: .tabNavigation,
                    sequence: sequence,
                    reason: "Tab navigated away from the granted scope."
                )
            }
        )
    }

    func applyingTabClose(
        profileID: String,
        tabID: Int,
        sequence: Int
    ) -> ChromeMV3ActiveTabGrantBroker {
        ChromeMV3ActiveTabGrantBroker(
            grants: grants.map { grant in
                guard grant.profileID == profileID,
                      expiresOnTabClose(grant: grant, tabID: tabID)
                else { return grant }
                return grant.expiring(
                    trigger: .tabClose,
                    sequence: sequence,
                    reason: "Tab was closed."
                )
            }
        )
    }

    func applyingExtensionDisable(
        extensionID: String,
        profileID: String,
        sequence: Int
    ) -> ChromeMV3ActiveTabGrantBroker {
        ChromeMV3ActiveTabGrantBroker(
            grants: grants.map { grant in
                guard grant.profileID == profileID,
                      expiresOnExtensionDisable(
                        grant: grant,
                        extensionID: extensionID
                      )
                else { return grant }
                return grant.expiring(
                    trigger: .extensionDisable,
                    sequence: sequence,
                    reason: "Extension was disabled."
                )
            }
        )
    }

    func applyingProfileClose(
        profileID: String,
        sequence: Int
    ) -> ChromeMV3ActiveTabGrantBroker {
        ChromeMV3ActiveTabGrantBroker(
            grants: grants.map { grant in
                guard grant.profileID == profileID,
                      grant.expiryTriggers.contains(.profileClose)
                else { return grant }
                return grant.expiring(
                    trigger: .profileClose,
                    sequence: sequence,
                    reason: "Profile was closed."
                )
            }
        )
    }

    func applyingPermissionRevoke(
        extensionID: String,
        profileID: String,
        sequence: Int,
        permission: String? = nil
    ) -> ChromeMV3ActiveTabGrantBroker {
        ChromeMV3ActiveTabGrantBroker(
            grants: grants.map { grant in
                guard grant.extensionID == extensionID,
                      grant.profileID == profileID,
                      grant.expiryTriggers.contains(.permissionRevoke)
                else { return grant }
                return grant.expiring(
                    trigger: .permissionRevoke,
                    sequence: sequence,
                    reason:
                        "Permission revoke expired activeTab grant"
                        + (permission.map { " for \($0)." } ?? ".")
                )
            }
        )
    }

    func missingActiveTabReason(
        extensionID: String,
        profileID: String,
        tabID: Int?,
        url: String?,
        activeTabPermissionDeclared: Bool
    ) -> ChromeMV3RuntimeMessagingMissingGrantReason {
        activeTabDecision(
            extensionID: extensionID,
            profileID: profileID,
            tabID: tabID,
            url: url,
            activeTabPermissionDeclared: activeTabPermissionDeclared,
            userGestureAvailable: false
        ).missingReason
    }
}

struct ChromeMV3PermissionBrokerState:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var requiredPermissions: [String]
    var optionalPermissions: [String]
    var grantedOptionalPermissions: [String]
    var hostPermissions: [String]
    var optionalHostPermissions: [String]
    var grantedOptionalHostPermissions: [String]
    var deniedPermissions: [String]
    var revokedPermissions: [String]
    var unavailablePermissions: [String]
    var unsupportedPermissions: [String]
    var activeTabGrants: [ChromeMV3ActiveTabGrant]
    var diagnostics: [String]

    init(
        extensionID: String,
        profileID: String,
        requiredPermissions: [String] = [],
        optionalPermissions: [String] = [],
        grantedOptionalPermissions: [String] = [],
        hostPermissions: [String] = [],
        optionalHostPermissions: [String] = [],
        grantedOptionalHostPermissions: [String] = [],
        deniedPermissions: [String] = [],
        revokedPermissions: [String] = [],
        unavailablePermissions: [String] = [],
        unsupportedPermissions: [String] = [],
        activeTabGrants: [ChromeMV3ActiveTabGrant] = [],
        diagnostics: [String] = []
    ) {
        self.extensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
        self.profileID = profileID.isEmpty ? "unknown-profile" : profileID
        self.requiredPermissions = Self.uniqueSorted(requiredPermissions)
        self.optionalPermissions = Self.uniqueSorted(optionalPermissions)
        self.grantedOptionalPermissions = Self.uniqueSorted(
            grantedOptionalPermissions
        )
        self.hostPermissions = Self.uniqueSorted(hostPermissions)
        self.optionalHostPermissions = Self.uniqueSorted(optionalHostPermissions)
        self.grantedOptionalHostPermissions = Self.uniqueSorted(
            grantedOptionalHostPermissions
        )
        self.deniedPermissions = Self.uniqueSorted(deniedPermissions)
        self.revokedPermissions = Self.uniqueSorted(revokedPermissions)
        self.unavailablePermissions = Self.uniqueSorted(unavailablePermissions)
        self.unsupportedPermissions = Self.uniqueSorted(unsupportedPermissions)
        self.activeTabGrants = ChromeMV3ActiveTabGrantBroker(
            grants: activeTabGrants
        ).grants
        self.diagnostics = Self.uniqueSorted(diagnostics)
    }

    static func from(
        manifestFacts: ChromeMV3RuntimeBridgeManifestFacts,
        extensionID: String,
        profileID: String,
        activeTabGrants: [ChromeMV3ActiveTabGrant] = []
    ) -> ChromeMV3PermissionBrokerState {
        var unavailable = manifestFacts.declaredPermissions.filter {
            ["nativeMessaging", "storage"].contains($0)
        }
        if manifestFacts.permissionsAPIPresent {
            unavailable.append("permissions")
        }
        return ChromeMV3PermissionBrokerState(
            extensionID: extensionID,
            profileID: profileID,
            requiredPermissions: manifestFacts.declaredPermissions,
            optionalPermissions: manifestFacts.optionalPermissions,
            hostPermissions: manifestFacts.hostPermissions,
            optionalHostPermissions: manifestFacts.optionalHostPermissions,
            unavailablePermissions: unavailable,
            activeTabGrants: activeTabGrants,
            diagnostics: manifestFacts.warnings
        )
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

struct ChromeMV3PermissionBroker:
    Codable,
    Equatable,
    Sendable
{
    var state: ChromeMV3PermissionBrokerState
    var activeTabBroker: ChromeMV3ActiveTabGrantBroker

    init(state: ChromeMV3PermissionBrokerState) {
        self.state = state
        self.activeTabBroker = ChromeMV3ActiveTabGrantBroker(
            grants: state.activeTabGrants
        )
    }

    var extensionID: String { state.extensionID }
    var profileID: String { state.profileID }

    var activeTabPermissionDeclared: Bool {
        state.requiredPermissions.contains("activeTab")
            || state.optionalPermissions.contains("activeTab")
            || state.grantedOptionalPermissions.contains("activeTab")
    }

    func hasAPIPermission(_ permission: String) -> Bool {
        apiPermissionDecision(permission).hasPermission
    }

    func hasOptionalPermission(_ permission: String) -> Bool {
        apiPermissionDecision(permission).grantedOptional
    }

    func hasHostPermission(url: String?) -> Bool {
        hostAccessDecision(url: url, tabID: nil).hasHostAccess
    }

    func hasHostPermission(origin: String?) -> Bool {
        hostAccessDecision(origin: origin, tabID: nil).hasHostAccess
    }

    func wouldNeedPrompt(permission: String) -> Bool {
        apiPermissionDecision(permission).wouldNeedPrompt
    }

    func wouldNeedPrompt(host urlOrOrigin: String?) -> Bool {
        hostAccessDecision(url: urlOrOrigin, tabID: nil).wouldNeedPrompt
    }

    func isPermissionUnsupported(_ permission: String) -> Bool {
        state.unsupportedPermissions.contains(permission)
    }

    func isPermissionDeferred(_ permission: String) -> Bool {
        state.unavailablePermissions.contains(permission)
    }

    func isPermissionRevoked(_ permission: String) -> Bool {
        state.revokedPermissions.contains(permission)
    }

    func apiPermissionDecision(
        _ permission: String
    ) -> ChromeMV3APIPermissionDecision {
        let declaredRequired = state.requiredPermissions.contains(permission)
        let declaredOptional = state.optionalPermissions.contains(permission)
        let grantedOptional =
            state.grantedOptionalPermissions.contains(permission)
        let denied = state.deniedPermissions.contains(permission)
        let revoked = state.revokedPermissions.contains(permission)
        let unsupported = state.unsupportedPermissions.contains(permission)
        let deferred = state.unavailablePermissions.contains(permission)
        let hasPermission = (declaredRequired || grantedOptional)
            && denied == false
            && revoked == false
            && unsupported == false
            && deferred == false
        let wouldNeedPrompt = declaredOptional
            && grantedOptional == false
            && denied == false
            && revoked == false
            && unsupported == false
            && deferred == false
        let status: ChromeMV3PermissionBrokerDecisionStatus
        let source: ChromeMV3PermissionBrokerGrantSource
        if unsupported {
            status = .unsupported
            source = .none
        } else if deferred {
            status = .deferred
            source = .none
        } else if denied {
            status = .denied
            source = .none
        } else if revoked {
            status = .revoked
            source = .none
        } else if hasPermission {
            status = .allowed
            source = declaredRequired
                ? .requiredPermission
                : .optionalPermissionModeledGrant
        } else if wouldNeedPrompt {
            status = .promptRequired
            source = .none
        } else {
            status = .blocked
            source = .none
        }

        return ChromeMV3APIPermissionDecision(
            permission: permission,
            status: status,
            grantSource: source,
            hasPermission: hasPermission,
            declaredRequired: declaredRequired,
            declaredOptional: declaredOptional,
            grantedOptional: grantedOptional,
            denied: denied,
            revoked: revoked,
            unsupported: unsupported,
            deferred: deferred,
            wouldNeedPrompt: wouldNeedPrompt,
            diagnostics: diagnostics(
                permission: permission,
                status: status,
                declaredRequired: declaredRequired,
                declaredOptional: declaredOptional,
                grantedOptional: grantedOptional
            )
        )
    }

    func hostAccessDecision(
        url: String?,
        tabID: Int?,
        userGestureAvailable: Bool = false
    ) -> ChromeMV3HostAccessDecision {
        hostAccessDecision(
            url: url,
            origin: ChromeMV3PermissionBrokerURL.origin(from: url),
            tabID: tabID,
            userGestureAvailable: userGestureAvailable
        )
    }

    func hostAccessDecision(
        origin: String?,
        tabID: Int?,
        userGestureAvailable: Bool = false
    ) -> ChromeMV3HostAccessDecision {
        hostAccessDecision(
            url: origin,
            origin: ChromeMV3PermissionBrokerURL.origin(from: origin),
            tabID: tabID,
            userGestureAvailable: userGestureAvailable
        )
    }

    func hasActiveTabGrant(tabID: Int?, url: String?) -> Bool {
        activeTabBroker.hasActiveTabGrant(
            extensionID: extensionID,
            profileID: profileID,
            tabID: tabID,
            url: url
        )
    }

    func activeTabDecision(
        tabID: Int?,
        url: String?,
        userGestureAvailable: Bool = false
    ) -> ChromeMV3ActiveTabAccessDecision {
        activeTabBroker.activeTabDecision(
            extensionID: extensionID,
            profileID: profileID,
            tabID: tabID,
            url: url,
            activeTabPermissionDeclared: activeTabPermissionDeclared,
            userGestureAvailable: userGestureAvailable
        )
    }

    func wouldGrantFromGesture(_ event: ChromeMV3ActiveTabGestureEvent)
        -> Bool
    {
        activeTabBroker.wouldGrantFromGesture(
            event,
            activeTabPermissionDeclared: activeTabPermissionDeclared
        )
    }

    private func hostAccessDecision(
        url: String?,
        origin: String?,
        tabID: Int?,
        userGestureAvailable: Bool
    ) -> ChromeMV3HostAccessDecision {
        guard url != nil || origin != nil else {
            return ChromeMV3HostAccessDecision(
                url: url,
                origin: origin,
                status: .blocked,
                grantSource: .none,
                hasHostAccess: false,
                allowedByHostPermission: false,
                allowedByOptionalHostPermission: false,
                allowedByActiveTab: false,
                matchingHostPatterns: [],
                optionalHostPatternsThatCouldPrompt: [],
                invalidHostPatterns: [],
                unsupportedHostPatterns: [],
                deniedByPattern: false,
                revokedByPattern: false,
                wouldNeedPrompt: false,
                missingReason: .invalidURL,
                diagnostics: ["No URL or origin was available for host access evaluation."]
            )
        }

        let requiredPatterns = state.hostPermissions.map(
            ChromeMV3HostMatchPattern.init
        )
        let grantedOptionalPatterns =
            state.grantedOptionalHostPermissions.map(
                ChromeMV3HostMatchPattern.init
            )
        let optionalPatterns = state.optionalHostPermissions.map(
            ChromeMV3HostMatchPattern.init
        )
        let deniedPatterns = state.deniedPermissions
            .filter { $0.contains("://") || $0 == "<all_urls>" }
            .map(ChromeMV3HostMatchPattern.init)
        let revokedPatterns = state.revokedPermissions
            .filter { $0.contains("://") || $0 == "<all_urls>" }
            .map(ChromeMV3HostMatchPattern.init)
        let target = url ?? origin
        let deniedByPattern = deniedPatterns.contains {
            $0.matches(url: target)
        }
        let revokedByPattern = revokedPatterns.contains {
            $0.matches(url: target)
        }
        let requiredMatches = requiredPatterns.filter {
            $0.matches(url: target)
        }.map(\.rawValue)
        let optionalGrantMatches = grantedOptionalPatterns.filter {
            $0.matches(url: target)
        }.map(\.rawValue)
        let optionalCouldPrompt = optionalPatterns.filter {
            $0.matches(url: target)
        }.map(\.rawValue)
        let invalid = (requiredPatterns + grantedOptionalPatterns
            + optionalPatterns).filter(\.isInvalid).map(\.rawValue)
        let unsupported = (requiredPatterns + grantedOptionalPatterns
            + optionalPatterns).filter(\.isUnsupported).map(\.rawValue)
        let activeDecision = activeTabDecision(
            tabID: tabID,
            url: target,
            userGestureAvailable: userGestureAvailable
        )
        let allowedByRequired = requiredMatches.isEmpty == false
        let allowedByOptional = optionalGrantMatches.isEmpty == false
        let allowedByActiveTab = activeDecision.hasGrant
        let hasHostAccess = deniedByPattern == false
            && revokedByPattern == false
            && (allowedByRequired || allowedByOptional || allowedByActiveTab)
        let wouldPrompt = hasHostAccess == false
            && deniedByPattern == false
            && revokedByPattern == false
            && optionalCouldPrompt.isEmpty == false
        let status: ChromeMV3PermissionBrokerDecisionStatus
        let source: ChromeMV3PermissionBrokerGrantSource
        let missingReason: ChromeMV3HostAccessMissingReason

        if deniedByPattern {
            status = .denied
            source = .none
            missingReason = .permissionDenied
        } else if revokedByPattern {
            status = .revoked
            source = .none
            missingReason = .permissionRevoked
        } else if allowedByRequired {
            status = .allowed
            source = .requiredHostPermission
            missingReason = .none
        } else if allowedByOptional {
            status = .allowed
            source = .optionalHostPermissionModeledGrant
            missingReason = .none
        } else if allowedByActiveTab {
            status = .allowed
            source = .activeTabGrant
            missingReason = .none
        } else if wouldPrompt {
            status = .promptRequired
            source = .none
            missingReason = .hostPermissionMissing
        } else if unsupported.isEmpty == false {
            status = .unsupported
            source = .none
            missingReason = .unsupportedPattern
        } else {
            status = .blocked
            source = .none
            missingReason = activeTabPermissionDeclared
                ? .activeTabMissing
                : .hostPermissionMissing
        }

        return ChromeMV3HostAccessDecision(
            url: url,
            origin: origin,
            status: status,
            grantSource: source,
            hasHostAccess: hasHostAccess,
            allowedByHostPermission: allowedByRequired,
            allowedByOptionalHostPermission: allowedByOptional,
            allowedByActiveTab: allowedByActiveTab,
            matchingHostPatterns:
                Array(Set(requiredMatches + optionalGrantMatches)).sorted(),
            optionalHostPatternsThatCouldPrompt:
                Array(Set(optionalCouldPrompt)).sorted(),
            invalidHostPatterns: Array(Set(invalid)).sorted(),
            unsupportedHostPatterns: Array(Set(unsupported)).sorted(),
            deniedByPattern: deniedByPattern,
            revokedByPattern: revokedByPattern,
            wouldNeedPrompt: wouldPrompt,
            missingReason: missingReason,
            diagnostics: hostDiagnostics(
                status: status,
                target: target,
                requiredMatches: requiredMatches,
                optionalGrantMatches: optionalGrantMatches,
                optionalCouldPrompt: optionalCouldPrompt,
                activeDecision: activeDecision,
                invalid: invalid,
                unsupported: unsupported,
                revokedByPattern: revokedByPattern
            )
        )
    }

    private func diagnostics(
        permission: String,
        status: ChromeMV3PermissionBrokerDecisionStatus,
        declaredRequired: Bool,
        declaredOptional: Bool,
        grantedOptional: Bool
    ) -> [String] {
        var values = ["Permission \(permission) decision: \(status.rawValue)."]
        if declaredRequired {
            values.append("Permission is declared as required.")
        }
        if declaredOptional {
            values.append("Permission is declared as optional.")
        }
        if grantedOptional {
            values.append("Optional permission has a modeled grant.")
        }
        if state.unavailablePermissions.contains(permission) {
            values.append("Permission runtime is unavailable or deferred in Sumi.")
        }
        if state.unsupportedPermissions.contains(permission) {
            values.append("Permission is unsupported by this broker.")
        }
        if state.deniedPermissions.contains(permission) {
            values.append("Permission is explicitly denied by broker state.")
        }
        if state.revokedPermissions.contains(permission) {
            values.append("Permission has been revoked by broker state.")
        }
        return Array(Set(values)).sorted()
    }

    private func hostDiagnostics(
        status: ChromeMV3PermissionBrokerDecisionStatus,
        target: String?,
        requiredMatches: [String],
        optionalGrantMatches: [String],
        optionalCouldPrompt: [String],
        activeDecision: ChromeMV3ActiveTabAccessDecision,
        invalid: [String],
        unsupported: [String],
        revokedByPattern: Bool
    ) -> [String] {
        var values = [
            "Host access decision for \(target ?? "unknown-target"): \(status.rawValue).",
        ]
        if requiredMatches.isEmpty == false {
            values.append("Required host permission matched.")
        }
        if optionalGrantMatches.isEmpty == false {
            values.append("Modeled optional host permission grant matched.")
        }
        if optionalCouldPrompt.isEmpty == false {
            values.append("Optional host permission could require a future prompt.")
        }
        if activeDecision.hasGrant {
            values.append("Modeled activeTab grant matched.")
        }
        if invalid.isEmpty == false {
            values.append("Invalid host match patterns were reported.")
        }
        if unsupported.isEmpty == false {
            values.append("Unsupported host match patterns require verification.")
        }
        if revokedByPattern {
            values.append("Host access was revoked by broker state.")
        }
        values.append(contentsOf: activeDecision.diagnostics)
        return Array(Set(values)).sorted()
    }
}

enum ChromeMV3PermissionDecisionSubjectKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case apiPermission
    case hostPermission

    static func < (
        lhs: ChromeMV3PermissionDecisionSubjectKind,
        rhs: ChromeMV3PermissionDecisionSubjectKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ModeledPermissionDecisionRecord:
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var extensionID: String
    var profileID: String
    var subjectKind: ChromeMV3PermissionDecisionSubjectKind
    var value: String
    var status: ChromeMV3PermissionBrokerDecisionStatus
    var grantSource: ChromeMV3PermissionBrokerGrantSource
    var sequence: Int
    var diagnostics: [String]

    init(
        extensionID: String,
        profileID: String,
        subjectKind: ChromeMV3PermissionDecisionSubjectKind,
        value: String,
        status: ChromeMV3PermissionBrokerDecisionStatus,
        grantSource: ChromeMV3PermissionBrokerGrantSource,
        sequence: Int,
        diagnostics: [String]
    ) {
        self.extensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
        self.profileID = profileID.isEmpty ? "unknown-profile" : profileID
        self.subjectKind = subjectKind
        self.value = value
        self.status = status
        self.grantSource = grantSource
        self.sequence = sequence
        self.diagnostics = Self.uniqueSorted(diagnostics)
        self.id = ChromeMV3PermissionBrokerStableID.make(
            prefix: "permission-decision",
            parts: [
                self.extensionID,
                self.profileID,
                subjectKind.rawValue,
                value,
                status.rawValue,
                grantSource.rawValue,
                String(sequence),
            ]
        )
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

struct ChromeMV3PermissionDecisionStoreSnapshotSummary:
    Codable,
    Equatable,
    Sendable
{
    var storeID: String
    var extensionID: String
    var profileID: String
    var declaredAPIPermissions: [String]
    var declaredHostPermissions: [String]
    var optionalAPIPermissions: [String]
    var optionalHostPermissions: [String]
    var grantedOptionalAPIPermissions: [String]
    var grantedOptionalHostPermissions: [String]
    var deniedPermissions: [String]
    var revokedPermissions: [String]
    var deferredPermissions: [String]
    var unsupportedPermissions: [String]
    var decisionRecordIDs: [String]
}

struct ChromeMV3PermissionDecisionStoreSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var storeID: String
    var extensionID: String
    var profileID: String
    var declaredAPIPermissions: [String]
    var declaredHostPermissions: [String]
    var optionalAPIPermissions: [String]
    var optionalHostPermissions: [String]
    var grantedOptionalAPIPermissions: [String]
    var grantedOptionalHostPermissions: [String]
    var deniedPermissions: [String]
    var revokedPermissions: [String]
    var deferredPermissions: [String]
    var unsupportedPermissions: [String]
    var decisionRecords: [ChromeMV3ModeledPermissionDecisionRecord]
    var diagnostics: [String]

    init(
        schemaVersion: Int = 1,
        extensionID: String,
        profileID: String,
        declaredAPIPermissions: [String] = [],
        declaredHostPermissions: [String] = [],
        optionalAPIPermissions: [String] = [],
        optionalHostPermissions: [String] = [],
        grantedOptionalAPIPermissions: [String] = [],
        grantedOptionalHostPermissions: [String] = [],
        deniedPermissions: [String] = [],
        revokedPermissions: [String] = [],
        deferredPermissions: [String] = [],
        unsupportedPermissions: [String] = [],
        decisionRecords: [ChromeMV3ModeledPermissionDecisionRecord] = [],
        diagnostics: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.extensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
        self.profileID = profileID.isEmpty ? "unknown-profile" : profileID
        self.declaredAPIPermissions =
            Self.uniqueSorted(declaredAPIPermissions)
        self.declaredHostPermissions =
            Self.uniqueSorted(declaredHostPermissions)
        self.optionalAPIPermissions =
            Self.uniqueSorted(optionalAPIPermissions)
        self.optionalHostPermissions =
            Self.uniqueSorted(optionalHostPermissions)
        self.grantedOptionalAPIPermissions =
            Self.uniqueSorted(grantedOptionalAPIPermissions)
        self.grantedOptionalHostPermissions =
            Self.uniqueSorted(grantedOptionalHostPermissions)
        self.deniedPermissions = Self.uniqueSorted(deniedPermissions)
        self.revokedPermissions = Self.uniqueSorted(revokedPermissions)
        self.deferredPermissions = Self.uniqueSorted(deferredPermissions)
        self.unsupportedPermissions = Self.uniqueSorted(unsupportedPermissions)
        self.decisionRecords = decisionRecords.sorted {
            if $0.sequence != $1.sequence {
                return $0.sequence < $1.sequence
            }
            return $0.id < $1.id
        }
        self.diagnostics = Self.uniqueSorted(diagnostics)
        self.storeID = ChromeMV3PermissionBrokerStableID.make(
            prefix: "permission-decision-store",
            parts: [
                self.extensionID,
                self.profileID,
                self.declaredAPIPermissions.joined(separator: ","),
                self.declaredHostPermissions.joined(separator: ","),
                self.optionalAPIPermissions.joined(separator: ","),
                self.optionalHostPermissions.joined(separator: ","),
                self.grantedOptionalAPIPermissions.joined(separator: ","),
                self.grantedOptionalHostPermissions.joined(separator: ","),
                self.deniedPermissions.joined(separator: ","),
                self.revokedPermissions.joined(separator: ","),
                self.deferredPermissions.joined(separator: ","),
                self.unsupportedPermissions.joined(separator: ","),
            ]
        )
    }

    var summary: ChromeMV3PermissionDecisionStoreSnapshotSummary {
        ChromeMV3PermissionDecisionStoreSnapshotSummary(
            storeID: storeID,
            extensionID: extensionID,
            profileID: profileID,
            declaredAPIPermissions: declaredAPIPermissions,
            declaredHostPermissions: declaredHostPermissions,
            optionalAPIPermissions: optionalAPIPermissions,
            optionalHostPermissions: optionalHostPermissions,
            grantedOptionalAPIPermissions: grantedOptionalAPIPermissions,
            grantedOptionalHostPermissions: grantedOptionalHostPermissions,
            deniedPermissions: deniedPermissions,
            revokedPermissions: revokedPermissions,
            deferredPermissions: deferredPermissions,
            unsupportedPermissions: unsupportedPermissions,
            decisionRecordIDs: decisionRecords.map(\.id).sorted()
        )
    }

    fileprivate func with(
        grantedOptionalAPIPermissions: [String]? = nil,
        grantedOptionalHostPermissions: [String]? = nil,
        deniedPermissions: [String]? = nil,
        revokedPermissions: [String]? = nil,
        decisionRecords: [ChromeMV3ModeledPermissionDecisionRecord]? = nil,
        diagnostics: [String]? = nil
    ) -> ChromeMV3PermissionDecisionStoreSnapshot {
        ChromeMV3PermissionDecisionStoreSnapshot(
            schemaVersion: schemaVersion,
            extensionID: extensionID,
            profileID: profileID,
            declaredAPIPermissions: declaredAPIPermissions,
            declaredHostPermissions: declaredHostPermissions,
            optionalAPIPermissions: optionalAPIPermissions,
            optionalHostPermissions: optionalHostPermissions,
            grantedOptionalAPIPermissions:
                grantedOptionalAPIPermissions
                    ?? self.grantedOptionalAPIPermissions,
            grantedOptionalHostPermissions:
                grantedOptionalHostPermissions
                    ?? self.grantedOptionalHostPermissions,
            deniedPermissions: deniedPermissions ?? self.deniedPermissions,
            revokedPermissions: revokedPermissions ?? self.revokedPermissions,
            deferredPermissions: deferredPermissions,
            unsupportedPermissions: unsupportedPermissions,
            decisionRecords: decisionRecords ?? self.decisionRecords,
            diagnostics: diagnostics ?? self.diagnostics
        )
    }

    fileprivate static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

struct ChromeMV3PermissionDecisionStore:
    Codable,
    Equatable,
    Sendable
{
    var snapshot: ChromeMV3PermissionDecisionStoreSnapshot

    init(snapshot: ChromeMV3PermissionDecisionStoreSnapshot) {
        self.snapshot = snapshot
    }

    static func from(
        manifestFacts: ChromeMV3RuntimeBridgeManifestFacts,
        extensionID: String,
        profileID: String,
        deferredPermissions explicitDeferredPermissions: [String] = [],
        unsupportedPermissions: [String] = []
    ) -> ChromeMV3PermissionDecisionStore {
        var deferred = explicitDeferredPermissions
        deferred.append(
            contentsOf: manifestFacts.declaredPermissions.filter {
                ["nativeMessaging", "storage"].contains($0)
            }
        )
        if manifestFacts.permissionsAPIPresent {
            deferred.append("permissions")
        }
        let snapshot = ChromeMV3PermissionDecisionStoreSnapshot(
            extensionID: extensionID,
            profileID: profileID,
            declaredAPIPermissions: manifestFacts.declaredPermissions,
            declaredHostPermissions: manifestFacts.hostPermissions,
            optionalAPIPermissions: manifestFacts.optionalPermissions,
            optionalHostPermissions: manifestFacts.optionalHostPermissions,
            deferredPermissions: deferred,
            unsupportedPermissions: unsupportedPermissions,
            diagnostics: manifestFacts.warnings
        )
        return ChromeMV3PermissionDecisionStore(
            snapshot: snapshot.with(
                decisionRecords:
                    Self.derivedDecisionRecords(from: snapshot)
            )
        )
    }

    func exportSnapshot()
        -> ChromeMV3PermissionDecisionStoreSnapshot
    {
        if snapshot.decisionRecords.isEmpty {
            return snapshot.with(
                decisionRecords:
                    Self.derivedDecisionRecords(from: snapshot)
            )
        }
        return snapshot
    }

    func applyingModeledGrant(
        _ permission: String,
        sequence: Int
    ) -> ChromeMV3PermissionDecisionStore {
        let value = permission.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else {
            return appendingRecord(
                value: value,
                status: .blocked,
                grantSource: .none,
                sequence: sequence,
                diagnostics: ["Empty permission grant was ignored."]
            )
        }

        var apiGrants = snapshot.grantedOptionalAPIPermissions
        var hostGrants = snapshot.grantedOptionalHostPermissions
        var denied = snapshot.deniedPermissions.filter { $0 != value }
        var revoked = snapshot.revokedPermissions.filter { $0 != value }
        let subjectKind = Self.subjectKind(for: value)
        let status: ChromeMV3PermissionBrokerDecisionStatus
        let source: ChromeMV3PermissionBrokerGrantSource
        let diagnostics: [String]

        if subjectKind == .hostPermission {
            if snapshot.declaredHostPermissions.contains(value) {
                status = .allowed
                source = .requiredHostPermission
                diagnostics = [
                    "Required host permission is already declared; modeled grant records current allowance.",
                ]
            } else if snapshot.optionalHostPermissions.contains(value) {
                hostGrants.append(value)
                status = .allowed
                source = .optionalHostPermissionModeledGrant
                diagnostics = [
                    "Modeled optional host permission grant was recorded.",
                ]
            } else {
                status = .blocked
                source = .none
                diagnostics = [
                    "Host permission is not declared as required or optional.",
                ]
            }
        } else if snapshot.declaredAPIPermissions.contains(value) {
            status = .allowed
            source = .requiredPermission
            diagnostics = [
                "Required API permission is already declared; modeled grant records current allowance.",
            ]
        } else if snapshot.optionalAPIPermissions.contains(value) {
            apiGrants.append(value)
            status = .allowed
            source = .optionalPermissionModeledGrant
            diagnostics = [
                "Modeled optional API permission grant was recorded.",
            ]
        } else {
            status = .blocked
            source = .none
            diagnostics = [
                "API permission is not declared as required or optional.",
            ]
        }

        if status != .allowed {
            denied = snapshot.deniedPermissions
            revoked = snapshot.revokedPermissions
        }

        return appendingRecord(
            value: value,
            status: status,
            grantSource: source,
            sequence: sequence,
            grantedOptionalAPIPermissions: apiGrants,
            grantedOptionalHostPermissions: hostGrants,
            deniedPermissions: denied,
            revokedPermissions: revoked,
            diagnostics: diagnostics
        )
    }

    func applyingModeledDenial(
        _ permission: String,
        sequence: Int
    ) -> ChromeMV3PermissionDecisionStore {
        let value = permission.trimmingCharacters(in: .whitespacesAndNewlines)
        return appendingRecord(
            value: value,
            status: .denied,
            grantSource: .none,
            sequence: sequence,
            grantedOptionalAPIPermissions:
                snapshot.grantedOptionalAPIPermissions.filter { $0 != value },
            grantedOptionalHostPermissions:
                snapshot.grantedOptionalHostPermissions.filter { $0 != value },
            deniedPermissions: snapshot.deniedPermissions + [value],
            revokedPermissions:
                snapshot.revokedPermissions.filter { $0 != value },
            diagnostics: ["Modeled permission denial was recorded."]
        )
    }

    func applyingRevoke(
        _ permission: String,
        sequence: Int
    ) -> ChromeMV3PermissionDecisionStore {
        let value = permission.trimmingCharacters(in: .whitespacesAndNewlines)
        return appendingRecord(
            value: value,
            status: .revoked,
            grantSource: .none,
            sequence: sequence,
            grantedOptionalAPIPermissions:
                snapshot.grantedOptionalAPIPermissions.filter { $0 != value },
            grantedOptionalHostPermissions:
                snapshot.grantedOptionalHostPermissions.filter { $0 != value },
            deniedPermissions:
                snapshot.deniedPermissions.filter { $0 != value },
            revokedPermissions: snapshot.revokedPermissions + [value],
            diagnostics: ["Modeled permission revoke was recorded."]
        )
    }

    func apiPermissionDecision(
        _ permission: String
    ) -> ChromeMV3APIPermissionDecision {
        permissionBroker().apiPermissionDecision(permission)
    }

    func optionalPermissionDecision(
        _ permission: String
    ) -> ChromeMV3APIPermissionDecision {
        apiPermissionDecision(permission)
    }

    func hostAccessDecision(
        url: String?,
        tabID: Int? = nil,
        activeTabStore: ChromeMV3ActiveTabGrantStore? = nil,
        userGestureAvailable: Bool = false
    ) -> ChromeMV3HostAccessDecision {
        permissionBroker(activeTabStore: activeTabStore)
            .hostAccessDecision(
                url: url,
                tabID: tabID,
                userGestureAvailable: userGestureAvailable
            )
    }

    func isPermissionUnsupported(_ permission: String) -> Bool {
        snapshot.unsupportedPermissions.contains(permission)
    }

    func isPermissionDeferred(_ permission: String) -> Bool {
        snapshot.deferredPermissions.contains(permission)
    }

    func permissionBroker(
        activeTabStore: ChromeMV3ActiveTabGrantStore? = nil
    ) -> ChromeMV3PermissionBroker {
        ChromeMV3PermissionBroker(
            state: ChromeMV3PermissionBrokerState(
                extensionID: snapshot.extensionID,
                profileID: snapshot.profileID,
                requiredPermissions: snapshot.declaredAPIPermissions,
                optionalPermissions: snapshot.optionalAPIPermissions,
                grantedOptionalPermissions:
                    snapshot.grantedOptionalAPIPermissions,
                hostPermissions: snapshot.declaredHostPermissions,
                optionalHostPermissions: snapshot.optionalHostPermissions,
                grantedOptionalHostPermissions:
                    snapshot.grantedOptionalHostPermissions,
                deniedPermissions: snapshot.deniedPermissions,
                revokedPermissions: snapshot.revokedPermissions,
                unavailablePermissions: snapshot.deferredPermissions,
                unsupportedPermissions: snapshot.unsupportedPermissions,
                activeTabGrants:
                    activeTabStore?.snapshot.grantRecords.map(\.grant) ?? []
            )
        )
    }

    private func appendingRecord(
        value: String,
        status: ChromeMV3PermissionBrokerDecisionStatus,
        grantSource: ChromeMV3PermissionBrokerGrantSource,
        sequence: Int,
        grantedOptionalAPIPermissions: [String]? = nil,
        grantedOptionalHostPermissions: [String]? = nil,
        deniedPermissions: [String]? = nil,
        revokedPermissions: [String]? = nil,
        diagnostics: [String]
    ) -> ChromeMV3PermissionDecisionStore {
        let record = ChromeMV3ModeledPermissionDecisionRecord(
            extensionID: snapshot.extensionID,
            profileID: snapshot.profileID,
            subjectKind: Self.subjectKind(for: value),
            value: value,
            status: status,
            grantSource: grantSource,
            sequence: sequence,
            diagnostics: diagnostics
        )
        return ChromeMV3PermissionDecisionStore(
            snapshot: snapshot.with(
                grantedOptionalAPIPermissions:
                    grantedOptionalAPIPermissions,
                grantedOptionalHostPermissions:
                    grantedOptionalHostPermissions,
                deniedPermissions: deniedPermissions,
                revokedPermissions: revokedPermissions,
                decisionRecords: snapshot.decisionRecords + [record],
                diagnostics: snapshot.diagnostics + diagnostics
            )
        )
    }

    private static func subjectKind(
        for value: String
    ) -> ChromeMV3PermissionDecisionSubjectKind {
        value == "<all_urls>" || value.contains("://")
            ? .hostPermission
            : .apiPermission
    }

    private static func derivedDecisionRecords(
        from snapshot: ChromeMV3PermissionDecisionStoreSnapshot
    ) -> [ChromeMV3ModeledPermissionDecisionRecord] {
        let apiValues = Array(Set(
            snapshot.declaredAPIPermissions
                + snapshot.optionalAPIPermissions
                + snapshot.grantedOptionalAPIPermissions
                + snapshot.deniedPermissions.filter {
                    subjectKind(for: $0) == .apiPermission
                }
                + snapshot.revokedPermissions.filter {
                    subjectKind(for: $0) == .apiPermission
                }
                + snapshot.deferredPermissions
                + snapshot.unsupportedPermissions
        )).sorted()
        let hostValues = Array(Set(
            snapshot.declaredHostPermissions
                + snapshot.optionalHostPermissions
                + snapshot.grantedOptionalHostPermissions
                + snapshot.deniedPermissions.filter {
                    subjectKind(for: $0) == .hostPermission
                }
                + snapshot.revokedPermissions.filter {
                    subjectKind(for: $0) == .hostPermission
                }
        )).sorted()

        let apiRecords = apiValues.enumerated().map { index, value in
            record(
                snapshot: snapshot,
                subjectKind: .apiPermission,
                value: value,
                sequence: index
            )
        }
        let hostRecords = hostValues.enumerated().map { index, value in
            record(
                snapshot: snapshot,
                subjectKind: .hostPermission,
                value: value,
                sequence: apiValues.count + index
            )
        }
        return (apiRecords + hostRecords).sorted {
            if $0.sequence != $1.sequence {
                return $0.sequence < $1.sequence
            }
            return $0.id < $1.id
        }
    }

    private static func record(
        snapshot: ChromeMV3PermissionDecisionStoreSnapshot,
        subjectKind: ChromeMV3PermissionDecisionSubjectKind,
        value: String,
        sequence: Int
    ) -> ChromeMV3ModeledPermissionDecisionRecord {
        let status: ChromeMV3PermissionBrokerDecisionStatus
        let source: ChromeMV3PermissionBrokerGrantSource
        if snapshot.unsupportedPermissions.contains(value) {
            status = .unsupported
            source = .none
        } else if snapshot.deferredPermissions.contains(value) {
            status = .deferred
            source = .none
        } else if snapshot.deniedPermissions.contains(value) {
            status = .denied
            source = .none
        } else if snapshot.revokedPermissions.contains(value) {
            status = .revoked
            source = .none
        } else if subjectKind == .hostPermission,
                  snapshot.declaredHostPermissions.contains(value)
        {
            status = .allowed
            source = .requiredHostPermission
        } else if subjectKind == .hostPermission,
                  snapshot.grantedOptionalHostPermissions.contains(value)
        {
            status = .allowed
            source = .optionalHostPermissionModeledGrant
        } else if subjectKind == .hostPermission,
                  snapshot.optionalHostPermissions.contains(value)
        {
            status = .promptRequired
            source = .none
        } else if snapshot.declaredAPIPermissions.contains(value) {
            status = .allowed
            source = .requiredPermission
        } else if snapshot.grantedOptionalAPIPermissions.contains(value) {
            status = .allowed
            source = .optionalPermissionModeledGrant
        } else if snapshot.optionalAPIPermissions.contains(value) {
            status = .promptRequired
            source = .none
        } else {
            status = .blocked
            source = .none
        }

        return ChromeMV3ModeledPermissionDecisionRecord(
            extensionID: snapshot.extensionID,
            profileID: snapshot.profileID,
            subjectKind: subjectKind,
            value: value,
            status: status,
            grantSource: source,
            sequence: sequence,
            diagnostics: [
                "Permission store derived \(value) as \(status.rawValue).",
            ]
        )
    }
}

struct ChromeMV3ActiveTabGrantRecord:
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var grant: ChromeMV3ActiveTabGrant

    init(grant: ChromeMV3ActiveTabGrant) {
        self.grant = grant
        self.id = ChromeMV3PermissionBrokerStableID.make(
            prefix: "active-tab-grant",
            parts: [
                grant.extensionID,
                grant.profileID,
                String(grant.tabID),
                grant.scope.diagnosticValue,
                grant.reason.rawValue,
                String(grant.createdSequence),
            ]
        )
    }
}

struct ChromeMV3ActiveTabGrantStoreSnapshotSummary:
    Codable,
    Equatable,
    Sendable
{
    var storeID: String
    var extensionID: String
    var profileID: String
    var activeGrantCount: Int
    var inactiveGrantCount: Int
    var grantRecordIDs: [String]
    var activeGrantScopes: [String]
    var nextSequence: Int
}

struct ChromeMV3ActiveTabGrantStoreSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var storeID: String
    var extensionID: String
    var profileID: String
    var grantRecords: [ChromeMV3ActiveTabGrantRecord]
    var nextSequence: Int
    var diagnostics: [String]

    init(
        schemaVersion: Int = 1,
        extensionID: String,
        profileID: String,
        grantRecords: [ChromeMV3ActiveTabGrantRecord] = [],
        nextSequence: Int = 1,
        diagnostics: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.extensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
        self.profileID = profileID.isEmpty ? "unknown-profile" : profileID
        self.grantRecords = grantRecords.sorted {
            if $0.grant.createdSequence != $1.grant.createdSequence {
                return $0.grant.createdSequence < $1.grant.createdSequence
            }
            return $0.id < $1.id
        }
        self.nextSequence = max(
            nextSequence,
            (self.grantRecords.map(\.grant.createdSequence).max() ?? 0) + 1
        )
        self.diagnostics = Array(Set(
            diagnostics.filter { $0.isEmpty == false }
        )).sorted()
        self.storeID = ChromeMV3PermissionBrokerStableID.make(
            prefix: "active-tab-grant-store",
            parts: [
                self.extensionID,
                self.profileID,
                self.grantRecords.map(\.id).joined(separator: ","),
                String(self.nextSequence),
            ]
        )
    }

    var summary: ChromeMV3ActiveTabGrantStoreSnapshotSummary {
        ChromeMV3ActiveTabGrantStoreSnapshotSummary(
            storeID: storeID,
            extensionID: extensionID,
            profileID: profileID,
            activeGrantCount:
                grantRecords.filter { $0.grant.active }.count,
            inactiveGrantCount:
                grantRecords.filter { $0.grant.active == false }.count,
            grantRecordIDs: grantRecords.map(\.id).sorted(),
            activeGrantScopes:
                grantRecords
                    .filter { $0.grant.active }
                    .map(\.grant.scope.diagnosticValue)
                    .sorted(),
            nextSequence: nextSequence
        )
    }
}

struct ChromeMV3ActiveTabGrantStore:
    Codable,
    Equatable,
    Sendable
{
    var snapshot: ChromeMV3ActiveTabGrantStoreSnapshot

    init(snapshot: ChromeMV3ActiveTabGrantStoreSnapshot) {
        self.snapshot = snapshot
    }

    static func empty(
        extensionID: String,
        profileID: String
    ) -> ChromeMV3ActiveTabGrantStore {
        ChromeMV3ActiveTabGrantStore(
            snapshot: ChromeMV3ActiveTabGrantStoreSnapshot(
                extensionID: extensionID,
                profileID: profileID,
                diagnostics: [
                    "No activeTab grants are modeled.",
                ]
            )
        )
    }

    static func from(
        extensionID: String,
        profileID: String,
        grants: [ChromeMV3ActiveTabGrant]
    ) -> ChromeMV3ActiveTabGrantStore {
        ChromeMV3ActiveTabGrantStore(
            snapshot: ChromeMV3ActiveTabGrantStoreSnapshot(
                extensionID: extensionID,
                profileID: profileID,
                grantRecords: grants.map(ChromeMV3ActiveTabGrantRecord.init)
            )
        )
    }

    func exportSnapshot() -> ChromeMV3ActiveTabGrantStoreSnapshot {
        snapshot
    }

    func addingModeledGrant(
        tabID: Int,
        url: String,
        reason: ChromeMV3ActiveTabGrantReason,
        sequence: Int? = nil
    ) -> ChromeMV3ActiveTabGrantStore {
        guard let origin = ChromeMV3PermissionBrokerURL.origin(from: url)
        else {
            return with(
                diagnostics: snapshot.diagnostics + [
                    "activeTab grant was not created because URL origin is invalid.",
                ]
            )
        }
        let createdSequence = sequence ?? snapshot.nextSequence
        let grant = ChromeMV3ActiveTabGrant(
            extensionID: snapshot.extensionID,
            profileID: snapshot.profileID,
            tabID: tabID,
            scope: .origin(origin),
            reason: reason,
            userGestureModeled: true,
            createdSequence: createdSequence,
            diagnostics: [
                "Modeled activeTab grant created by \(reason.rawValue).",
            ]
        )
        return ChromeMV3ActiveTabGrantStore(
            snapshot: ChromeMV3ActiveTabGrantStoreSnapshot(
                extensionID: snapshot.extensionID,
                profileID: snapshot.profileID,
                grantRecords:
                    snapshot.grantRecords
                        + [ChromeMV3ActiveTabGrantRecord(grant: grant)],
                nextSequence: createdSequence + 1,
                diagnostics: snapshot.diagnostics + grant.diagnostics
            )
        )
    }

    func activeTabDecision(
        tabID: Int?,
        url: String?,
        activeTabPermissionDeclared: Bool = true,
        userGestureAvailable: Bool = false
    ) -> ChromeMV3ActiveTabAccessDecision {
        ChromeMV3ActiveTabGrantBroker(
            grants: snapshot.grantRecords.map(\.grant)
        )
        .activeTabDecision(
            extensionID: snapshot.extensionID,
            profileID: snapshot.profileID,
            tabID: tabID,
            url: url,
            activeTabPermissionDeclared: activeTabPermissionDeclared,
            userGestureAvailable: userGestureAvailable
        )
    }

    func hasActiveTabGrant(tabID: Int?, url: String?) -> Bool {
        activeTabDecision(tabID: tabID, url: url).hasGrant
    }

    func expiringForTabClose(
        tabID: Int,
        sequence: Int
    ) -> (
        store: ChromeMV3ActiveTabGrantStore,
        expired: [ChromeMV3ActiveTabGrantRecord],
        retained: [ChromeMV3ActiveTabGrantRecord]
    ) {
        expiring(
            trigger: .tabClose,
            sequence: sequence,
            reason: "Tab was closed.",
            shouldExpire: { $0.profileID == snapshot.profileID && $0.tabID == tabID }
        )
    }

    func expiringForNavigation(
        tabID: Int,
        oldURL: String?,
        newURL: String?,
        sequence: Int
    ) -> (
        store: ChromeMV3ActiveTabGrantStore,
        expired: [ChromeMV3ActiveTabGrantRecord],
        retained: [ChromeMV3ActiveTabGrantRecord]
    ) {
        expiring(
            trigger: .tabNavigation,
            sequence: sequence,
            reason: "Tab navigated away from the granted scope.",
            shouldExpire: {
                $0.profileID == snapshot.profileID
                    && $0.tabID == tabID
                    && $0.scope.expiresOnNavigation(
                        oldURL: oldURL,
                        newURL: newURL
                    )
            }
        )
    }

    func expiringForProfileClose(
        profileID: String,
        sequence: Int
    ) -> (
        store: ChromeMV3ActiveTabGrantStore,
        expired: [ChromeMV3ActiveTabGrantRecord],
        retained: [ChromeMV3ActiveTabGrantRecord]
    ) {
        expiring(
            trigger: .profileClose,
            sequence: sequence,
            reason: "Profile was closed.",
            shouldExpire: { $0.profileID == profileID }
        )
    }

    func expiringForExtensionDisable(
        extensionID: String,
        profileID: String,
        sequence: Int
    ) -> (
        store: ChromeMV3ActiveTabGrantStore,
        expired: [ChromeMV3ActiveTabGrantRecord],
        retained: [ChromeMV3ActiveTabGrantRecord]
    ) {
        expiring(
            trigger: .extensionDisable,
            sequence: sequence,
            reason: "Extension was disabled.",
            shouldExpire: {
                $0.extensionID == extensionID && $0.profileID == profileID
            }
        )
    }

    func expiringForPermissionRevoke(
        extensionID: String,
        profileID: String,
        permission: String?,
        sequence: Int
    ) -> (
        store: ChromeMV3ActiveTabGrantStore,
        expired: [ChromeMV3ActiveTabGrantRecord],
        retained: [ChromeMV3ActiveTabGrantRecord]
    ) {
        expiring(
            trigger: .permissionRevoke,
            sequence: sequence,
            reason:
                "Permission revoke expired activeTab grant"
                + (permission.map { " for \($0)." } ?? "."),
            shouldExpire: {
                $0.extensionID == extensionID && $0.profileID == profileID
            }
        )
    }

    private func expiring(
        trigger: ChromeMV3ActiveTabExpiryTrigger,
        sequence: Int,
        reason: String,
        shouldExpire: (ChromeMV3ActiveTabGrant) -> Bool
    ) -> (
        store: ChromeMV3ActiveTabGrantStore,
        expired: [ChromeMV3ActiveTabGrantRecord],
        retained: [ChromeMV3ActiveTabGrantRecord]
    ) {
        let before = snapshot.grantRecords
        let after = before.map { record -> ChromeMV3ActiveTabGrantRecord in
            guard record.grant.active,
                  record.grant.expiryTriggers.contains(trigger),
                  shouldExpire(record.grant)
            else { return record }
            return ChromeMV3ActiveTabGrantRecord(
                grant: record.grant.expiring(
                    trigger: trigger,
                    sequence: sequence,
                    reason: reason
                )
            )
        }
        let expired = zip(before, after).compactMap { old, new in
            old.grant.active && new.grant.active == false ? new : nil
        }
        let retained = after.filter { $0.grant.active }
        let diagnostics = expired.isEmpty
            ? ["No activeTab grants expired for \(trigger.rawValue)."]
            : expired.flatMap(\.grant.diagnostics)
        let store = ChromeMV3ActiveTabGrantStore(
            snapshot: ChromeMV3ActiveTabGrantStoreSnapshot(
                extensionID: snapshot.extensionID,
                profileID: snapshot.profileID,
                grantRecords: after,
                nextSequence: max(snapshot.nextSequence, sequence + 1),
                diagnostics: snapshot.diagnostics + diagnostics
            )
        )
        return (store, expired.sorted { $0.id < $1.id }, retained.sorted { $0.id < $1.id })
    }

    private func with(
        diagnostics: [String]
    ) -> ChromeMV3ActiveTabGrantStore {
        ChromeMV3ActiveTabGrantStore(
            snapshot: ChromeMV3ActiveTabGrantStoreSnapshot(
                extensionID: snapshot.extensionID,
                profileID: snapshot.profileID,
                grantRecords: snapshot.grantRecords,
                nextSequence: snapshot.nextSequence,
                diagnostics: diagnostics
            )
        )
    }
}

enum ChromeMV3PermissionLifecycleEventKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case extensionDisabled
    case permissionRevoked
    case profileClosed
    case tabClosed
    case tabCreated
    case tabNavigated
    case tabReplaced

    static func < (
        lhs: ChromeMV3PermissionLifecycleEventKind,
        rhs: ChromeMV3PermissionLifecycleEventKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PermissionLifecycleEvent:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3PermissionLifecycleEventKind
    var extensionID: String
    var profileID: String
    var tabID: Int?
    var replacementTabID: Int?
    var oldURL: String?
    var newURL: String?
    var permission: String?
    var sequence: Int

    init(
        kind: ChromeMV3PermissionLifecycleEventKind,
        extensionID: String,
        profileID: String,
        tabID: Int? = nil,
        replacementTabID: Int? = nil,
        oldURL: String? = nil,
        newURL: String? = nil,
        permission: String? = nil,
        sequence: Int
    ) {
        self.kind = kind
        self.extensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
        self.profileID = profileID.isEmpty ? "unknown-profile" : profileID
        self.tabID = tabID
        self.replacementTabID = replacementTabID
        self.oldURL = oldURL
        self.newURL = newURL
        self.permission = permission
        self.sequence = sequence
    }
}

struct ChromeMV3PermissionLifecycleEventResult:
    Codable,
    Equatable,
    Sendable
{
    var event: ChromeMV3PermissionLifecycleEvent
    var grantsExpired: [ChromeMV3ActiveTabGrantRecord]
    var grantsRetained: [ChromeMV3ActiveTabGrantRecord]
    var permissionStoreSummary:
        ChromeMV3PermissionDecisionStoreSnapshotSummary
    var activeTabStoreSummary:
        ChromeMV3ActiveTabGrantStoreSnapshotSummary
    var readinessImpact: [String]
    var diagnostics: [String]
}

struct ChromeMV3PermissionLifecycleAdapter:
    Codable,
    Equatable,
    Sendable
{
    var permissionStore: ChromeMV3PermissionDecisionStore
    var activeTabStore: ChromeMV3ActiveTabGrantStore
    var appliedEvents: [ChromeMV3PermissionLifecycleEvent]
    var eventResults: [ChromeMV3PermissionLifecycleEventResult]

    init(
        permissionStore: ChromeMV3PermissionDecisionStore,
        activeTabStore: ChromeMV3ActiveTabGrantStore,
        appliedEvents: [ChromeMV3PermissionLifecycleEvent] = [],
        eventResults: [ChromeMV3PermissionLifecycleEventResult] = []
    ) {
        self.permissionStore = permissionStore
        self.activeTabStore = activeTabStore
        self.appliedEvents = appliedEvents.sorted {
            if $0.sequence != $1.sequence {
                return $0.sequence < $1.sequence
            }
            return $0.kind < $1.kind
        }
        self.eventResults = eventResults.sorted {
            if $0.event.sequence != $1.event.sequence {
                return $0.event.sequence < $1.event.sequence
            }
            return $0.event.kind < $1.event.kind
        }
    }

    func applying(
        _ event: ChromeMV3PermissionLifecycleEvent
    ) -> ChromeMV3PermissionLifecycleAdapter {
        var nextPermissionStore = permissionStore
        let expiry: (
            store: ChromeMV3ActiveTabGrantStore,
            expired: [ChromeMV3ActiveTabGrantRecord],
            retained: [ChromeMV3ActiveTabGrantRecord]
        )

        switch event.kind {
        case .tabCreated:
            expiry = (activeTabStore, [], activeTabStore.snapshot.grantRecords.filter { $0.grant.active })
        case .tabClosed:
            if let tabID = event.tabID {
                expiry = activeTabStore.expiringForTabClose(
                    tabID: tabID,
                    sequence: event.sequence
                )
            } else {
                expiry = (activeTabStore, [], activeTabStore.snapshot.grantRecords.filter { $0.grant.active })
            }
        case .tabNavigated:
            if let tabID = event.tabID {
                expiry = activeTabStore.expiringForNavigation(
                    tabID: tabID,
                    oldURL: event.oldURL,
                    newURL: event.newURL,
                    sequence: event.sequence
                )
            } else {
                expiry = (activeTabStore, [], activeTabStore.snapshot.grantRecords.filter { $0.grant.active })
            }
        case .tabReplaced:
            if let tabID = event.tabID {
                expiry = activeTabStore.expiringForTabClose(
                    tabID: tabID,
                    sequence: event.sequence
                )
            } else {
                expiry = (activeTabStore, [], activeTabStore.snapshot.grantRecords.filter { $0.grant.active })
            }
        case .profileClosed:
            expiry = activeTabStore.expiringForProfileClose(
                profileID: event.profileID,
                sequence: event.sequence
            )
        case .extensionDisabled:
            expiry = activeTabStore.expiringForExtensionDisable(
                extensionID: event.extensionID,
                profileID: event.profileID,
                sequence: event.sequence
            )
        case .permissionRevoked:
            if let permission = event.permission {
                nextPermissionStore = permissionStore.applyingRevoke(
                    permission,
                    sequence: event.sequence
                )
            }
            expiry = activeTabStore.expiringForPermissionRevoke(
                extensionID: event.extensionID,
                profileID: event.profileID,
                permission: event.permission,
                sequence: event.sequence
            )
        }

        let result = ChromeMV3PermissionLifecycleEventResult(
            event: event,
            grantsExpired: expiry.expired,
            grantsRetained: expiry.retained,
            permissionStoreSummary:
                nextPermissionStore.exportSnapshot().summary,
            activeTabStoreSummary:
                expiry.store.exportSnapshot().summary,
            readinessImpact: readinessImpact(
                event: event,
                expired: expiry.expired
            ),
            diagnostics: diagnostics(
                event: event,
                expired: expiry.expired,
                retained: expiry.retained
            )
        )

        return ChromeMV3PermissionLifecycleAdapter(
            permissionStore: nextPermissionStore,
            activeTabStore: expiry.store,
            appliedEvents: appliedEvents + [event],
            eventResults: eventResults + [result]
        )
    }

    func applying(
        _ events: [ChromeMV3PermissionLifecycleEvent]
    ) -> ChromeMV3PermissionLifecycleAdapter {
        events.sorted {
            if $0.sequence != $1.sequence {
                return $0.sequence < $1.sequence
            }
            return $0.kind < $1.kind
        }.reduce(self) { adapter, event in
            adapter.applying(event)
        }
    }

    private func readinessImpact(
        event: ChromeMV3PermissionLifecycleEvent,
        expired: [ChromeMV3ActiveTabGrantRecord]
    ) -> [String] {
        var impact = [
            "canPromptUserNow remains false.",
            "canDispatchMessagesNow remains false.",
            "canRegisterListenersNow remains false.",
            "canWakeServiceWorkerNow remains false.",
            "canLoadContextNow remains false.",
            "runtimeLoadable remains false.",
        ]
        if expired.isEmpty == false {
            impact.append(
                "activeTab access was reduced by \(event.kind.rawValue)."
            )
        }
        if event.kind == .permissionRevoked {
            impact.append(
                "Permission revoke updates modeled store state only."
            )
        }
        return Array(Set(impact)).sorted()
    }

    private func diagnostics(
        event: ChromeMV3PermissionLifecycleEvent,
        expired: [ChromeMV3ActiveTabGrantRecord],
        retained: [ChromeMV3ActiveTabGrantRecord]
    ) -> [String] {
        [
            "Lifecycle event \(event.kind.rawValue) was applied deterministically.",
            "Expired activeTab grants: \(expired.map(\.id).sorted().joined(separator: ","))",
            "Retained activeTab grants: \(retained.map(\.id).sorted().joined(separator: ","))",
            "No observer, scheduler, context, listener, or dispatch path is installed.",
        ]
    }
}

struct ChromeMV3PermissionBrokerStateSummary:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var requiredPermissions: [String]
    var optionalPermissions: [String]
    var grantedOptionalPermissions: [String]
    var hostPermissions: [String]
    var optionalHostPermissions: [String]
    var grantedOptionalHostPermissions: [String]
    var deniedPermissions: [String]
    var revokedPermissions: [String]
    var unavailablePermissions: [String]
    var unsupportedPermissions: [String]
}

struct ChromeMV3HostPatternSupportSummary:
    Codable,
    Equatable,
    Sendable
{
    var supportedPatterns: [String]
    var unsupportedPatterns: [String]
    var invalidPatterns: [String]
    var allURLsPatternModeled: Bool
    var wildcardSubdomainPatterns: [String]
    var pathIgnoredForHostPermissions: Bool
    var diagnostics: [String]
}

struct ChromeMV3ActiveTabGrantSummary:
    Codable,
    Equatable,
    Sendable
{
    var activeTabPermissionDeclared: Bool
    var activeGrantCount: Int
    var inactiveGrantCount: Int
    var activeGrantScopes: [String]
    var expiryTriggersModeled: [ChromeMV3ActiveTabExpiryTrigger]
    var diagnostics: [String]
}

struct ChromeMV3PermissionBrokerRouteScenario:
    Codable,
    Equatable,
    Sendable
{
    var routeKind: ChromeMV3RuntimeMessagingRouteKind
    var hostAccessDecision: ChromeMV3HostAccessDecision
    var messagingPermissionDecision:
        ChromeMV3RuntimeMessagingPermissionDecision
    var senderMetadataRedaction:
        ChromeMV3RuntimeMessagingMetadataRedaction
    var canDispatchMessagesNow: Bool
}

struct ChromeMV3PasswordManagerPermissionReadiness:
    Codable,
    Equatable,
    Sendable
{
    var hostPermissionsDeclared: [String]
    var hostPermissionsDetected: Bool
    var loginPageURL: String
    var loginPageTabID: Int
    var loginPageHostAccessDecision: ChromeMV3HostAccessDecision
    var loginPageActiveTabDecision: ChromeMV3ActiveTabAccessDecision
    var contentScriptHostAccessRequired: Bool
    var contentScriptHostAccessRequirement: String
    var actionPopupUserGestureMayCreateActiveTabGrantInFuture: Bool
    var nativeMessagingPermissionDetectedButBlocked: Bool
    var nativeMessagingPermissionStillBlockedByNativeMessagingLayer: Bool
    var storagePermissionDetectedButRuntimeMissing: Bool
    var storagePermissionStillBlockedByStorageRuntime: Bool
    var runtimeMessagingBlocked: Bool
    var runtimeMessagingStillBlockedByDispatcherListenerServiceWorker: Bool
    var permissionBrokerSkeletonPresent: Bool
    var realPermissionPromptsImplemented: Bool
    var permissionPromptsNotImplemented: Bool
    var passwordManagerPermissionReady: Bool
    var blockers: [String]
}

struct ChromeMV3PermissionLifecycleReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var permissionStoreID: String
    var activeTabGrantStoreID: String
    var lifecycleEventCount: Int
    var expiredGrantCount: Int
    var canPromptUserNow: Bool
    var canDispatchMessagesNow: Bool
    var canRegisterListenersNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var passwordManagerPermissionReady: Bool
    var permissionsAPIContractReportSummary:
        ChromeMV3PermissionsAPIContractReportSummary? = nil
    var serviceWorkerLifecycleReportSummary:
        ChromeMV3ServiceWorkerLifecycleReportSummary? = nil
}

struct ChromeMV3PermissionLifecycleReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var candidateID: String
    var extensionID: String
    var profileID: String
    var permissionStoreSnapshotSummary:
        ChromeMV3PermissionDecisionStoreSnapshotSummary
    var activeTabGrantSnapshotSummary:
        ChromeMV3ActiveTabGrantStoreSnapshotSummary
    var lifecycleEventsApplied: [ChromeMV3PermissionLifecycleEvent]
    var lifecycleEventResults: [ChromeMV3PermissionLifecycleEventResult]
    var expiredGrantDiagnostics: [String]
    var routePermissionDecisions:
        [ChromeMV3PermissionBrokerRouteScenario]
    var listenerPermissionDecisions:
        [ChromeMV3RuntimeEventSurfaceCapability]
    var senderMetadataRedactionDecisions:
        [ChromeMV3RuntimeMessagingRouteKind:
            ChromeMV3RuntimeMessagingMetadataRedaction]
    var unsupportedPermissions: [String]
    var deferredPermissions: [String]
    var passwordManagerPermissionReadiness:
        ChromeMV3PasswordManagerPermissionReadiness
    var permissionsAPIContractReportSummary:
        ChromeMV3PermissionsAPIContractReportSummary? = nil
    var serviceWorkerLifecycleReportSummary:
        ChromeMV3ServiceWorkerLifecycleReportSummary? = nil
    var canPromptUserNow: Bool
    var canDispatchMessagesNow: Bool
    var canRegisterListenersNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var documentationSources: [ChromeMV3ManifestRewritePreviewSource]
    var diagnostics: [String]

    var summary: ChromeMV3PermissionLifecycleReportSummary {
        ChromeMV3PermissionLifecycleReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            permissionStoreID:
                permissionStoreSnapshotSummary.storeID,
            activeTabGrantStoreID:
                activeTabGrantSnapshotSummary.storeID,
            lifecycleEventCount: lifecycleEventsApplied.count,
            expiredGrantCount:
                lifecycleEventResults.flatMap(\.grantsExpired).count,
            canPromptUserNow: false,
            canDispatchMessagesNow: false,
            canRegisterListenersNow: false,
            canWakeServiceWorkerNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            passwordManagerPermissionReady: false,
            permissionsAPIContractReportSummary:
                permissionsAPIContractReportSummary,
            serviceWorkerLifecycleReportSummary:
                serviceWorkerLifecycleReportSummary
        )
    }
}

struct ChromeMV3PermissionBrokerReadinessReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var permissionBrokerSkeletonPresent: Bool
    var activeTabGrantModelPresent: Bool
    var hostPatternSupportModeled: Bool
    var canGrantPermissionsNow: Bool
    var canPromptUserNow: Bool
    var canDispatchMessagesNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var passwordManagerPermissionReady: Bool
    var permissionsAPIContractReportSummary:
        ChromeMV3PermissionsAPIContractReportSummary? = nil
    var serviceWorkerLifecycleReportSummary:
        ChromeMV3ServiceWorkerLifecycleReportSummary? = nil
}

struct ChromeMV3PermissionBrokerReadinessReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var candidateID: String
    var extensionID: String
    var profileID: String
    var permissionDecisionStoreSummary:
        ChromeMV3PermissionDecisionStoreSnapshotSummary
    var activeTabGrantStoreSnapshotSummary:
        ChromeMV3ActiveTabGrantStoreSnapshotSummary
    var brokerStateSummary: ChromeMV3PermissionBrokerStateSummary
    var hostPatternSupportSummary: ChromeMV3HostPatternSupportSummary
    var activeTabGrantSummary: ChromeMV3ActiveTabGrantSummary
    var permissionDecisionsForKeyRoutes:
        [ChromeMV3PermissionBrokerRouteScenario]
    var senderMetadataRedactionDecisions:
        [ChromeMV3RuntimeMessagingRouteKind:
            ChromeMV3RuntimeMessagingMetadataRedaction]
    var unsupportedPermissions: [String]
    var deferredPermissions: [String]
    var passwordManagerPermissionReadiness:
        ChromeMV3PasswordManagerPermissionReadiness
    var permissionsAPIContractReportSummary:
        ChromeMV3PermissionsAPIContractReportSummary? = nil
    var serviceWorkerLifecycleReportSummary:
        ChromeMV3ServiceWorkerLifecycleReportSummary? = nil
    var canGrantPermissionsNow: Bool
    var canPromptUserNow: Bool
    var canDispatchMessagesNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var documentationSources: [ChromeMV3ManifestRewritePreviewSource]
    var diagnostics: [String]

    var summary: ChromeMV3PermissionBrokerReadinessReportSummary {
        ChromeMV3PermissionBrokerReadinessReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            permissionBrokerSkeletonPresent: true,
            activeTabGrantModelPresent: true,
            hostPatternSupportModeled: true,
            canGrantPermissionsNow: false,
            canPromptUserNow: false,
            canDispatchMessagesNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            passwordManagerPermissionReady: false,
            permissionsAPIContractReportSummary:
                permissionsAPIContractReportSummary,
            serviceWorkerLifecycleReportSummary:
                serviceWorkerLifecycleReportSummary
        )
    }
}

enum ChromeMV3PermissionLifecycleReportWriter {
    static let reportFileName = "runtime-permission-lifecycle-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3PermissionLifecycleReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3PermissionLifecycleReport {
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

enum ChromeMV3PermissionLifecycleReportGenerator {
    static func makeReport(
        prerequisitesReport prerequisites:
            ChromeMV3RuntimeBridgePrerequisitesReport,
        profileID: String = "diagnostic-profile",
        modeledActiveTabGrants: [ChromeMV3ActiveTabGrant] = [],
        lifecycleEvents: [ChromeMV3PermissionLifecycleEvent] = []
    ) -> ChromeMV3PermissionLifecycleReport {
        let extensionID = prerequisites.candidateID
        let permissionStore = permissionStore(
            prerequisites: prerequisites,
            extensionID: extensionID,
            profileID: profileID
        )
        let activeTabStore = ChromeMV3ActiveTabGrantStore.from(
            extensionID: extensionID,
            profileID: profileID,
            grants: modeledActiveTabGrants
        )
        let adapter = ChromeMV3PermissionLifecycleAdapter(
            permissionStore: permissionStore,
            activeTabStore: activeTabStore
        ).applying(lifecycleEvents)
        let broker = adapter.permissionStore.permissionBroker(
            activeTabStore: adapter.activeTabStore
        )
        let routes = routeScenarios(
            extensionID: extensionID,
            profileID: profileID,
            broker: broker
        )
        let surfaces = ChromeMV3RuntimeListenerSurface.allModeledSurfaces(
            extensionID: extensionID,
            profileID: profileID
        )
        let listenerDecisions = ChromeMV3RuntimeEventSurfaceCapability.matrix(
            surfaces: surfaces,
            permissionBroker: broker
        )
        let password = passwordManagerPermissionReadiness(
            prerequisites: prerequisites,
            broker: broker
        )
        let permissionSnapshot = adapter.permissionStore.exportSnapshot()
        let activeTabSnapshot = adapter.activeTabStore.exportSnapshot()
        let permissionsAPISummary =
            ChromeMV3PermissionsAPIContractReportGenerator.makeSummary(
                prerequisitesReport: prerequisites,
                profileID: profileID,
                modeledActiveTabGrants: modeledActiveTabGrants
            )
        let serviceWorkerLifecycleSummary =
            ChromeMV3ServiceWorkerLifecycleReportGenerator.makeReport(
                prerequisitesReport: prerequisites,
                profileID: profileID
            ).summary

        return ChromeMV3PermissionLifecycleReport(
            schemaVersion: 1,
            id: id(
                candidateID: prerequisites.candidateID,
                prerequisiteReportID: prerequisites.id,
                permissionStoreID: permissionSnapshot.storeID,
                activeTabStoreID: activeTabSnapshot.storeID,
                events: adapter.appliedEvents
            ),
            reportFileName:
                ChromeMV3PermissionLifecycleReportWriter.reportFileName,
            candidateID: prerequisites.candidateID,
            extensionID: extensionID,
            profileID: profileID,
            permissionStoreSnapshotSummary: permissionSnapshot.summary,
            activeTabGrantSnapshotSummary: activeTabSnapshot.summary,
            lifecycleEventsApplied: adapter.appliedEvents,
            lifecycleEventResults: adapter.eventResults,
            expiredGrantDiagnostics:
                adapter.eventResults
                    .flatMap(\.grantsExpired)
                    .flatMap(\.grant.diagnostics)
                    .sorted(),
            routePermissionDecisions: routes,
            listenerPermissionDecisions: listenerDecisions,
            senderMetadataRedactionDecisions:
                Dictionary(uniqueKeysWithValues: routes.map {
                    ($0.routeKind, $0.senderMetadataRedaction)
                }),
            unsupportedPermissions: permissionSnapshot.unsupportedPermissions,
            deferredPermissions: permissionSnapshot.deferredPermissions,
            passwordManagerPermissionReadiness: password,
            permissionsAPIContractReportSummary: permissionsAPISummary,
            serviceWorkerLifecycleReportSummary:
                serviceWorkerLifecycleSummary,
            canPromptUserNow: false,
            canDispatchMessagesNow: false,
            canRegisterListenersNow: false,
            canWakeServiceWorkerNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            documentationSources:
                ChromeMV3PermissionBrokerReadinessReportGenerator
                .documentationSourcesForPermissionReports(),
            diagnostics: [
                "Permission lifecycle report is deterministic and host-side only.",
                "Permission store state is modeled but no real prompt is shown.",
                "activeTab grant expiry is modeled from explicit lifecycle inputs.",
                "Messaging and listener readiness consume store-backed decisions.",
                "No extension context, script, listener, worker, port, native host, or scheduler is started.",
                "runtimeLoadable remains false.",
            ]
        )
    }

    static func makeReport(
        loadingPrerequisitesReportFrom rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> ChromeMV3PermissionLifecycleReport {
        let rootURL = rootURL.standardizedFileURL
        let prerequisitesURL = rootURL.appendingPathComponent(
            ChromeMV3RuntimeBridgePrerequisitesReportWriter.reportFileName
        )
        let data = try Data(contentsOf: prerequisitesURL)
        let prerequisites = try JSONDecoder().decode(
            ChromeMV3RuntimeBridgePrerequisitesReport.self,
            from: data
        )
        return makeReport(prerequisitesReport: prerequisites)
    }

    static func permissionStore(
        prerequisites: ChromeMV3RuntimeBridgePrerequisitesReport,
        extensionID: String,
        profileID: String
    ) -> ChromeMV3PermissionDecisionStore {
        ChromeMV3PermissionDecisionStore.from(
            manifestFacts: prerequisites.manifestFacts,
            extensionID: extensionID,
            profileID: profileID,
            deferredPermissions:
                prerequisites.unsupportedDeferredAPIs.deferredAPIs
                    .map(\.rawValue),
            unsupportedPermissions:
                prerequisites.unsupportedDeferredAPIs.unsupportedAPIs
                    .map(\.rawValue)
        )
    }

    fileprivate static func routeScenarios(
        extensionID: String,
        profileID: String,
        broker: ChromeMV3PermissionBroker
    ) -> [ChromeMV3PermissionBrokerRouteScenario] {
        [
            ChromeMV3RuntimeMessagingRouteKind.contentScriptToServiceWorker,
            .serviceWorkerToTab,
            .tabsSendMessage,
        ].map {
            ChromeMV3RuntimeMessagingRoute.make(
                kind: $0,
                extensionID: extensionID,
                profileID: profileID,
                tabID: 1,
                frameID: 0,
                documentID: "document-0",
                sourceURL: "https://example.com/login",
                targetURL: "https://example.com/login"
            )
        }
        .map { route in
            let hostDecision = broker.hostAccessDecision(
                url: route.source.url ?? route.target.url,
                tabID: route.tabID
            )
            let permissionDecision =
                ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
                    route: route,
                    permissionBroker: broker
                )
            return ChromeMV3PermissionBrokerRouteScenario(
                routeKind: route.kind,
                hostAccessDecision: hostDecision,
                messagingPermissionDecision: permissionDecision,
                senderMetadataRedaction:
                    permissionDecision.senderMetadataRedaction,
                canDispatchMessagesNow: false
            )
        }.sorted { $0.routeKind < $1.routeKind }
    }

    fileprivate static func passwordManagerPermissionReadiness(
        prerequisites: ChromeMV3RuntimeBridgePrerequisitesReport,
        broker: ChromeMV3PermissionBroker
    ) -> ChromeMV3PasswordManagerPermissionReadiness {
        let summary = prerequisites.passwordManagerPrerequisiteSummary
        let loginPageURL = "https://example.com/login"
        let loginPageTabID = 1
        let hostDecision = broker.hostAccessDecision(
            url: loginPageURL,
            tabID: loginPageTabID
        )
        let activeDecision = broker.activeTabDecision(
            tabID: loginPageTabID,
            url: loginPageURL
        )
        let hostDetected = summary.hostPermissionsPresent
            || prerequisites.manifestFacts.hostPermissions.isEmpty == false
        let nativeDetected = summary.nativeMessagingPermissionPresent
            || broker.apiPermissionDecision("nativeMessaging").deferred
        let storageDetected = summary.storagePermissionPresent
            || prerequisites.manifestFacts.storagePermissionPresent
        let contentScriptRequiresHost =
            prerequisites.manifestFacts.contentScriptsPresent
                || summary.contentScriptsPresent
        return ChromeMV3PasswordManagerPermissionReadiness(
            hostPermissionsDeclared:
                prerequisites.manifestFacts.hostPermissions,
            hostPermissionsDetected: hostDetected,
            loginPageURL: loginPageURL,
            loginPageTabID: loginPageTabID,
            loginPageHostAccessDecision: hostDecision,
            loginPageActiveTabDecision: activeDecision,
            contentScriptHostAccessRequired: contentScriptRequiresHost,
            contentScriptHostAccessRequirement:
                contentScriptRequiresHost
                    ? "Password-manager content scripts require modeled host access for the login page before any future injection."
                    : "No content script host access requirement was detected.",
            actionPopupUserGestureMayCreateActiveTabGrantInFuture:
                prerequisites.manifestFacts.actionPopupPresent
                    || summary.actionPopupPresent,
            nativeMessagingPermissionDetectedButBlocked: nativeDetected,
            nativeMessagingPermissionStillBlockedByNativeMessagingLayer:
                nativeDetected,
            storagePermissionDetectedButRuntimeMissing: storageDetected,
            storagePermissionStillBlockedByStorageRuntime: storageDetected,
            runtimeMessagingBlocked: true,
            runtimeMessagingStillBlockedByDispatcherListenerServiceWorker:
                true,
            permissionBrokerSkeletonPresent: true,
            realPermissionPromptsImplemented: false,
            permissionPromptsNotImplemented: true,
            passwordManagerPermissionReady: false,
            blockers: Array(Set(
                summary.blockers
                    + hostDecision.diagnostics
                    + activeDecision.diagnostics
                    + [
                        "Password-manager content scripts still require authorized injection.",
                        "Action popup user gestures are modeled but not connected to real UI.",
                        "Native messaging permission is detected but native messaging remains blocked.",
                        "storage permission is detected but storage runtime is not implemented.",
                        "Runtime messaging remains blocked by dispatcher, listener, and service-worker gates.",
                        "Real permission prompts are not implemented.",
                    ]
            )).sorted()
        )
    }

    private static func id(
        candidateID: String,
        prerequisiteReportID: String,
        permissionStoreID: String,
        activeTabStoreID: String,
        events: [ChromeMV3PermissionLifecycleEvent]
    ) -> String {
        ChromeMV3PermissionBrokerStableID.make(
            prefix: "runtime-permission-lifecycle",
            parts: [
                candidateID,
                prerequisiteReportID,
                permissionStoreID,
                activeTabStoreID,
                events.map {
                    "\($0.sequence):\($0.kind.rawValue):\($0.tabID.map(String.init) ?? "no-tab"):\($0.permission ?? "no-permission")"
                }.joined(separator: ","),
            ]
        )
    }
}

enum ChromeMV3PermissionBrokerReadinessReportWriter {
    static let reportFileName =
        "runtime-permission-broker-readiness-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3PermissionBrokerReadinessReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3PermissionBrokerReadinessReport {
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

enum ChromeMV3PermissionBrokerReadinessReportGenerator {
    static func makeReport(
        prerequisitesReport prerequisites:
            ChromeMV3RuntimeBridgePrerequisitesReport,
        profileID: String = "diagnostic-profile",
        modeledActiveTabGrants: [ChromeMV3ActiveTabGrant] = []
    ) -> ChromeMV3PermissionBrokerReadinessReport {
        let extensionID = prerequisites.candidateID
        let permissionStore = ChromeMV3PermissionLifecycleReportGenerator
            .permissionStore(
                prerequisites: prerequisites,
                extensionID: extensionID,
                profileID: profileID
            )
        let activeTabStore = ChromeMV3ActiveTabGrantStore.from(
            extensionID: extensionID,
            profileID: profileID,
            grants: modeledActiveTabGrants
        )
        let broker = permissionStore.permissionBroker(
            activeTabStore: activeTabStore
        )
        let state = broker.state
        let permissionSnapshot = permissionStore.exportSnapshot()
        let activeTabSnapshot = activeTabStore.exportSnapshot()
        let scenarios = ChromeMV3PermissionLifecycleReportGenerator
            .routeScenarios(
                extensionID: extensionID,
                profileID: profileID,
                broker: broker
            )
        let permissionsAPISummary =
            ChromeMV3PermissionsAPIContractReportGenerator.makeSummary(
                prerequisitesReport: prerequisites,
                profileID: profileID,
                modeledActiveTabGrants: modeledActiveTabGrants
            )
        let serviceWorkerLifecycleSummary =
            ChromeMV3ServiceWorkerLifecycleReportGenerator.makeReport(
                prerequisitesReport: prerequisites,
                profileID: profileID
            ).summary

        return ChromeMV3PermissionBrokerReadinessReport(
            schemaVersion: 1,
            id: id(
                candidateID: prerequisites.candidateID,
                prerequisiteReportID: prerequisites.id,
                state: state
            ),
            reportFileName:
                ChromeMV3PermissionBrokerReadinessReportWriter.reportFileName,
            candidateID: prerequisites.candidateID,
            extensionID: extensionID,
            profileID: profileID,
            permissionDecisionStoreSummary: permissionSnapshot.summary,
            activeTabGrantStoreSnapshotSummary: activeTabSnapshot.summary,
            brokerStateSummary: brokerStateSummary(state),
            hostPatternSupportSummary:
                hostPatternSupportSummary(state: state),
            activeTabGrantSummary:
                activeTabGrantSummary(broker: broker),
            permissionDecisionsForKeyRoutes: scenarios,
            senderMetadataRedactionDecisions:
                Dictionary(uniqueKeysWithValues: scenarios.map {
                    ($0.routeKind, $0.senderMetadataRedaction)
                }),
            unsupportedPermissions: state.unsupportedPermissions,
            deferredPermissions: state.unavailablePermissions,
            passwordManagerPermissionReadiness:
                ChromeMV3PermissionLifecycleReportGenerator
                .passwordManagerPermissionReadiness(
                    prerequisites: prerequisites,
                    broker: broker
                ),
            permissionsAPIContractReportSummary: permissionsAPISummary,
            serviceWorkerLifecycleReportSummary:
                serviceWorkerLifecycleSummary,
            canGrantPermissionsNow: false,
            canPromptUserNow: false,
            canDispatchMessagesNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            documentationSources: documentationSources(),
            diagnostics: [
                "Permission decision store is present and deterministic.",
                "Host access decisions are modeled from store-backed state.",
                "activeTab grants are modeled from a deterministic grant store.",
                "Permission prompts are not implemented.",
                "Runtime dispatch remains disabled.",
                "Context loading remains disabled.",
                "runtimeLoadable remains false.",
            ]
        )
    }

    static func makeReport(
        loadingPrerequisitesReportFrom rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> ChromeMV3PermissionBrokerReadinessReport {
        let rootURL = rootURL.standardizedFileURL
        let prerequisitesURL = rootURL.appendingPathComponent(
            ChromeMV3RuntimeBridgePrerequisitesReportWriter.reportFileName
        )
        let data = try Data(contentsOf: prerequisitesURL)
        let prerequisites = try JSONDecoder().decode(
            ChromeMV3RuntimeBridgePrerequisitesReport.self,
            from: data
        )
        return makeReport(prerequisitesReport: prerequisites)
    }

    private static func brokerStateSummary(
        _ state: ChromeMV3PermissionBrokerState
    ) -> ChromeMV3PermissionBrokerStateSummary {
        ChromeMV3PermissionBrokerStateSummary(
            extensionID: state.extensionID,
            profileID: state.profileID,
            requiredPermissions: state.requiredPermissions,
            optionalPermissions: state.optionalPermissions,
            grantedOptionalPermissions: state.grantedOptionalPermissions,
            hostPermissions: state.hostPermissions,
            optionalHostPermissions: state.optionalHostPermissions,
            grantedOptionalHostPermissions:
                state.grantedOptionalHostPermissions,
            deniedPermissions: state.deniedPermissions,
            revokedPermissions: state.revokedPermissions,
            unavailablePermissions: state.unavailablePermissions,
            unsupportedPermissions: state.unsupportedPermissions
        )
    }

    private static func hostPatternSupportSummary(
        state: ChromeMV3PermissionBrokerState
    ) -> ChromeMV3HostPatternSupportSummary {
        let patterns = (
            state.hostPermissions + state.optionalHostPermissions
                + state.grantedOptionalHostPermissions
        )
        .map(ChromeMV3HostMatchPattern.init)
        let supported = patterns.filter(\.isValid).map(\.rawValue)
        let unsupported = patterns.filter(\.isUnsupported).map(\.rawValue)
        let invalid = patterns.filter(\.isInvalid).map(\.rawValue)
        return ChromeMV3HostPatternSupportSummary(
            supportedPatterns: Array(Set(supported)).sorted(),
            unsupportedPatterns: Array(Set(unsupported)).sorted(),
            invalidPatterns: Array(Set(invalid)).sorted(),
            allURLsPatternModeled:
                patterns.contains { $0.rawValue == "<all_urls>" },
            wildcardSubdomainPatterns:
                Array(Set(patterns.compactMap {
                    ($0.hostPattern?.hasPrefix("*.") == true)
                        ? $0.rawValue
                        : nil
                })).sorted(),
            pathIgnoredForHostPermissions:
                patterns.contains { $0.pathIgnoredForHostPermission },
            diagnostics:
                Array(Set(patterns.flatMap(\.diagnostics))).sorted()
        )
    }

    private static func activeTabGrantSummary(
        broker: ChromeMV3PermissionBroker
    ) -> ChromeMV3ActiveTabGrantSummary {
        let grants = broker.activeTabBroker.grants
        return ChromeMV3ActiveTabGrantSummary(
            activeTabPermissionDeclared:
                broker.activeTabPermissionDeclared,
            activeGrantCount: grants.filter(\.active).count,
            inactiveGrantCount: grants.filter { $0.active == false }.count,
            activeGrantScopes:
                grants.filter(\.active).map(\.scope.diagnosticValue).sorted(),
            expiryTriggersModeled:
                ChromeMV3ActiveTabExpiryTrigger.allCases.sorted(),
            diagnostics: [
                "activeTab grants are tab-scoped and origin-scoped unless a fixture uses an exact URL scope.",
                "activeTab expiry triggers are modeled for navigation, tab close, profile close, extension disable, permission revoke, and explicit reset.",
            ]
        )
    }

    private static func passwordManagerPermissionReadiness(
        prerequisites: ChromeMV3RuntimeBridgePrerequisitesReport,
        broker: ChromeMV3PermissionBroker
    ) -> ChromeMV3PasswordManagerPermissionReadiness {
        ChromeMV3PermissionLifecycleReportGenerator
            .passwordManagerPermissionReadiness(
                prerequisites: prerequisites,
                broker: broker
            )
    }

    fileprivate static func documentationSourcesForPermissionReports()
        -> [ChromeMV3ManifestRewritePreviewSource]
    {
        [
            source(
                title: "Chrome declare permissions",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/declare-permissions",
                note: "Defines required permissions, optional permissions, host permissions, and optional host permissions."
            ),
            source(
                title: "Chrome permissions API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/permissions",
                note: "Defines runtime optional permission request and contains checks."
            ),
            source(
                title: "Chrome activeTab",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/activeTab",
                note: "Defines temporary user-gesture-bound tab access and revocation on navigation or close."
            ),
            source(
                title: "Chrome match patterns",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/match-patterns",
                note: "Defines match pattern syntax, wildcard hosts, <all_urls>, and host-permission path behavior."
            ),
            source(
                title: "Chrome runtime API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/runtime",
                note: "Defines MessageSender URL and origin fields."
            ),
            source(
                title: "Chrome tabs API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/tabs",
                note: "Defines host permission and activeTab behavior for tab-sensitive operations."
            ),
            source(
                title: "Chrome content scripts",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts",
                note: "Defines host permissions and activeTab requirements for programmatic content script injection."
            ),
        ]
    }

    private static func documentationSources()
        -> [ChromeMV3ManifestRewritePreviewSource]
    {
        documentationSourcesForPermissionReports()
    }

    private static func source(
        title: String,
        url: String,
        note: String
    ) -> ChromeMV3ManifestRewritePreviewSource {
        ChromeMV3ManifestRewritePreviewSource(
            kind: .chromeDocumentation,
            title: title,
            url: url,
            note: note
        )
    }

    private static func id(
        candidateID: String,
        prerequisiteReportID: String,
        state: ChromeMV3PermissionBrokerState
    ) -> String {
        ChromeMV3PermissionBrokerStableID.make(
            prefix: "runtime-permission-broker-readiness",
            parts: [
                candidateID,
                prerequisiteReportID,
                state.requiredPermissions.joined(separator: ","),
                state.hostPermissions.joined(separator: ","),
                state.optionalPermissions.joined(separator: ","),
                state.optionalHostPermissions.joined(separator: ","),
            ]
        )
    }
}

enum ChromeMV3PermissionBrokerURL {
    static func origin(from urlString: String?) -> String? {
        guard let urlString,
              let components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased()
        else { return nil }
        if let port = components.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }
}

private enum ChromeMV3PermissionBrokerStableID {
    static func make(prefix: String, parts: [String]) -> String {
        let seed = parts.joined(separator: "|")
        return "\(prefix)-\(sha256Hex(Data(seed.utf8)).prefix(32))"
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
