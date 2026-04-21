//
//  UserScriptBundledCompatResources.swift
//  Sumi
//
//  Bundled optional compatibility preludes for userscripts in WKWebView.
//

import Foundation

/// Type anchor for `Bundle(for:)` — must live in the Sumi app target alongside `UserScriptCompat/*.js`.
final class UserScriptBundledCompatBundleLocator {}

enum UserScriptBundledCompatScript {
    private static var bundle: Bundle { Bundle(for: UserScriptBundledCompatBundleLocator.self) }

    /// Loads a file from the `UserScriptCompat` subdirectory (e.g. `webkit-media.js`).
    static func source(fileName: String) -> String? {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let base = (trimmed as NSString).deletingPathExtension
        let ext = (trimmed as NSString).pathExtension.isEmpty ? "js" : (trimmed as NSString).pathExtension
        let subdir = "UserScriptCompat"
        guard let url = bundle.url(forResource: base, withExtension: ext, subdirectory: subdir)
            ?? bundle.url(forResource: base, withExtension: ext)
        else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Maps `@sumi-compat webkit-media` → `UserScriptCompat/webkit-media.js`.
    static func source(moduleID: String) -> String? {
        let id = moduleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.isEmpty == false else { return nil }
        return source(fileName: "\(id).js")
    }
}

/// Built-in `@require` URLs that resolve to bundled scripts (no network).
enum UserScriptInternalRequireURL {
    static let scheme = "sumi-internal"
    static let host = "userscript-compat"

    static func content(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host
        else {
            return nil
        }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path.isEmpty == false else { return nil }
        return UserScriptBundledCompatScript.source(fileName: path)
    }
}

enum UserScriptCompatAssembly {
    /// Ordered compat prelude fragments from `// @sumi-compat` only (opt-in).
    static func preludeFragments(for metadata: UserScriptMetadata) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for raw in metadata.sumiCompat {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard id.isEmpty == false, seen.insert(id).inserted else { continue }
            guard let src = UserScriptBundledCompatScript.source(moduleID: id) else { continue }
            out.append(src)
        }
        return out
    }
}
