//
//  SafariExtensionPermissionLifecycleDiagnostics.swift
//  Sumi
//
//  Sanitized diagnostics for Safari Web Extension permission, tab, message, and
//  rebuild lifecycle boundaries. Never logs URL queries/fragments, message bodies,
//  cookies, tokens, auth payloads, or DOM content.
//

import Foundation

enum SafariExtensionPermissionSurface: String, Codable, CaseIterable, Sendable {
    case contentScripts
    case hostPermissions
    case optionalPermissions
    case externallyConnectable
    case activeTab
    case currentSite
    case defaultOtherWebsites
    case unknown
}

enum SafariExtensionSiteAccessDecisionSource: String, Codable, Sendable {
    case explicitAllow
    case explicitDeny
    case askOrUnknown
    case defaultOtherWebsites
    case currentSiteOrPage
    case activeTabTemporaryGrant
}

enum SafariExtensionPermissionAPIPath: String, Codable, Sendable {
    case global
    case tabAware
    case notApplicable
}

enum SafariExtensionExternalTabRoute: String, Codable, Sendable {
    case normalBrowserTab
    case auxiliaryPopup
    case extensionInternal
    case blocked
    case unknown
}

enum SafariExtensionDidOpenTabTiming: String, Codable, Sendable {
    case beforeNavigation
    case afterNavigationStarted
    case deferred
    case missing
    case unknown
}

enum SafariExtensionRebuildAction: String, Codable, Sendable {
    case boundedReload
    case destructiveRebuild
    case rebindOnly
    case none
}

struct SafariExtensionManifestAccessSurfaces: Codable, Equatable, Sendable {
    let contentScriptHosts: [String]
    let hostPermissionHosts: [String]
    let optionalPermissionHosts: [String]
    let externallyConnectableHosts: [String]

    static func from(manifest: [String: Any]) -> SafariExtensionManifestAccessSurfaces {
        let permissions = stringArray(from: manifest["permissions"])
        let optionalPermissions = stringArray(from: manifest["optional_permissions"])
        let contentScriptMatches =
            (manifest["content_scripts"] as? [[String: Any]] ?? [])
                .flatMap { stringArray(from: $0["matches"]) }
        let externallyConnectableMatches =
            (manifest["externally_connectable"] as? [String: Any])
                .map { stringArray(from: $0["matches"]) } ?? []

        return SafariExtensionManifestAccessSurfaces(
            contentScriptHosts: hosts(from: contentScriptMatches),
            hostPermissionHosts: hosts(
                from: stringArray(from: manifest["host_permissions"])
                    + permissions.filter(isManifestHostPermissionPattern)
            ),
            optionalPermissionHosts: hosts(
                from: stringArray(from: manifest["optional_host_permissions"])
                    + optionalPermissions.filter(isManifestHostPermissionPattern)
            ),
            externallyConnectableHosts: hosts(from: externallyConnectableMatches)
        )
    }

    func surfaces(forHost host: String?) -> [SafariExtensionPermissionSurface] {
        guard let host = host?.lowercased(), host.isEmpty == false else {
            return [.unknown]
        }
        var surfaces: [SafariExtensionPermissionSurface] = []
        if contentScriptHosts.contains(host) { surfaces.append(.contentScripts) }
        if hostPermissionHosts.contains(host) { surfaces.append(.hostPermissions) }
        if optionalPermissionHosts.contains(host) { surfaces.append(.optionalPermissions) }
        if externallyConnectableHosts.contains(host) { surfaces.append(.externallyConnectable) }
        return surfaces.isEmpty ? [.unknown] : surfaces
    }

    private static func stringArray(from value: Any?) -> [String] {
        value as? [String] ?? []
    }

    private static func isManifestHostPermissionPattern(_ value: String) -> Bool {
        value == "<all_urls>"
            || value.hasPrefix("http://")
            || value.hasPrefix("https://")
            || value.hasPrefix("*://")
    }

    private static func hosts(from patterns: [String]) -> [String] {
        Array(Set(patterns.compactMap(hostBucket(from:)))).sorted()
    }

    private static func hostBucket(from pattern: String) -> String? {
        guard pattern != "<all_urls>" else { return "<all_urls>" }
        let normalized = pattern.replacingOccurrences(of: "*://", with: "https://")
        guard let url = URL(string: normalized),
              let host = url.host?.lowercased(),
              host.isEmpty == false
        else {
            return nil
        }
        return host.replacingOccurrences(of: "*.", with: "")
    }
}

struct SafariExtensionPolicySnapshot: Codable, Equatable, Sendable {
    let extensionEnabled: Bool
    let extensionBucket: String?
    let profileBucket: String?
    let tabBucket: String?
    let isPrivate: Bool
    let originHost: String?
    let decisionSource: SafariExtensionSiteAccessDecisionSource
    let declaredSurfaces: [SafariExtensionPermissionSurface]
    let externallyConnectableReportedSeparately: Bool
}

struct SafariExtensionContextApplicationSnapshot: Codable, Equatable, Sendable {
    let contextLoaded: Bool
    let extensionBucket: String?
    let profileBucket: String?
    let controllerBucket: String?
    let appliedBeforeNavigation: Bool?
    let permissionAPIPath: SafariExtensionPermissionAPIPath
    let persistedPolicyDivergenceObserved: Bool?
}

struct SafariExtensionTabBindingSnapshot: Codable, Equatable, Sendable {
    let route: SafariExtensionExternalTabRoute
    let profileBucket: String?
    let tabBucket: String?
    let dataStoreMatched: Bool?
    let controllerMatched: Bool?
    let tabAdapterCreated: Bool
    let didOpenTabTiming: SafariExtensionDidOpenTabTiming
    let firstNavigationHost: String?
    let firstCommitHost: String?
}

struct SafariExtensionReloadRebuildSnapshot: Codable, Equatable, Sendable {
    let triggerReason: String
    let profileBucket: String?
    let tabBucket: String?
    let host: String?
    let userActionCaused: Bool
    let action: SafariExtensionRebuildAction
}

enum SafariExtensionPermissionLifecycleDiagnostics {
    static let category = "SafariExtensionPermissions"

    static func bucket(_ value: String?) -> String? {
        guard let value, value.isEmpty == false else { return nil }
        return "b\(String(format: "%08x", stableHash(value)))"
    }

    static func bucket(_ value: UUID?) -> String? {
        bucket(value?.uuidString.lowercased())
    }

    static func host(from url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "http" || scheme == "https" {
            return url.host?.lowercased()
        }
        return scheme
    }

    static func sanitizedURL(_ url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "http" || scheme == "https" {
            return [scheme, "://", url.host?.lowercased() ?? "<host>", redactedPath(url.path)].joined()
        }
        return "\(scheme):<redacted>"
    }

    static func logPolicySnapshot(_ snapshot: SafariExtensionPolicySnapshot) {
        log("policy", snapshot)
    }

    static func logContextApplication(_ snapshot: SafariExtensionContextApplicationSnapshot) {
        log("context", snapshot)
    }

    static func logTabBinding(_ snapshot: SafariExtensionTabBindingSnapshot) {
        log("tabBinding", snapshot)
    }

    static func logReloadRebuild(_ snapshot: SafariExtensionReloadRebuildSnapshot) {
        log("reloadRebuild", snapshot)
    }

    private static func log<T: Encodable>(_ label: String, _ snapshot: T) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(snapshot),
                  let json = String(data: data, encoding: .utf8)
            else {
                RuntimeDiagnostics.debug(
                    "SafariExtensionPermissionLifecycle \(label) encodeFailed",
                    category: category
                )
                return
            }
            RuntimeDiagnostics.debug(
                "SafariExtensionPermissionLifecycle \(label) \(json)",
                category: category
            )
        #else
            _ = label
            _ = snapshot
        #endif
    }

    private static func redactedPath(_ path: String) -> String {
        guard path.isEmpty == false, path != "/" else { return "/" }
        return "/<path>"
    }

    private static func stableHash(_ value: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }
}
