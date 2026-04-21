//
//  UserScriptOriginPolicy.swift
//  Sumi
//
//  Per-origin allow/deny and run modes for SumiScripts.
//

import Foundation

enum UserScriptRunMode: String, Codable, CaseIterable, Sendable {
    /// Match @match/@include for every enabled script (default).
    case alwaysMatch
    /// Only scripts explicitly allowed for the current host run; no @match until allowed.
    case strictOrigin
}

enum UserScriptOriginPolicy {
    /// Stable key for allow/deny maps (lowercased host, empty for non-http(s) / missing host).
    static func originKey(from url: URL) -> String {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return ""
        }
        return (url.host ?? "").lowercased()
    }

    static func passesOriginGate(
        runMode: UserScriptRunMode,
        filename: String,
        originKey: String,
        originAllow: [String: [String]],
        originDeny: [String: [String]]
    ) -> Bool {
        let deny = originDeny[filename] ?? []
        if deny.contains(originKey) { return false }
        switch runMode {
        case .alwaysMatch:
            return true
        case .strictOrigin:
            let allow = originAllow[filename] ?? []
            return allow.contains(originKey)
        }
    }
}
