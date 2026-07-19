import Foundation

/// Selects the exact origin of a bootstrap URL only when the manifest declares
/// a site-scoped pattern that will need access there. Broad all-site patterns
/// remain demand-driven and never become an install-time prompt.
@MainActor
enum ExtensionBootstrapPermissionTargetPolicy {
    static func earlyPromptTargets(
        in urls: [URL],
        manifest: [String: Any]
    ) -> Set<URL> {
        Set(urls.compactMap { url in
            guard requiresEarlyPrompt(for: url, manifest: manifest) else {
                return nil
            }
            return permissionOriginURL(for: url)
        })
    }

    static func requiresEarlyPrompt(
        for url: URL,
        manifest: [String: Any]
    ) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return false }

        return declaredEarlyAccessPatterns(in: manifest).contains { pattern in
            guard isSiteScopedWebPattern(pattern) else { return false }
            return ExtensionHostPermissionMatcher.matches(pattern, url: url)
        }
    }

    private static func declaredEarlyAccessPatterns(
        in manifest: [String: Any]
    ) -> [String] {
        var patterns = manifest["host_permissions"] as? [String] ?? []
        if (manifest["manifest_version"] as? Int ?? 2) < 3 {
            patterns.append(contentsOf: manifest["permissions"] as? [String] ?? [])
        }
        if let externallyConnectable =
            manifest["externally_connectable"] as? [String: Any] {
            patterns.append(
                contentsOf: externallyConnectable["matches"] as? [String] ?? []
            )
        }
        let contentScripts = manifest["content_scripts"] as? [[String: Any]] ?? []
        for contentScript in contentScripts {
            patterns.append(contentsOf: contentScript["matches"] as? [String] ?? [])
        }
        return patterns
    }

    private static func isSiteScopedWebPattern(_ pattern: String) -> Bool {
        guard let schemeSeparator = pattern.range(of: "://") else {
            return false
        }
        let scheme = pattern[..<schemeSeparator.lowerBound].lowercased()
        guard scheme == "http" || scheme == "https" || scheme == "*" else {
            return false
        }
        let remainder = pattern[schemeSeparator.upperBound...]
        let authority = remainder.split(separator: "/", maxSplits: 1).first
            .map(String.init) ?? ""
        guard authority.isEmpty == false, authority != "*" else { return false }
        if authority.hasPrefix("*.") {
            let scopedHost = authority.dropFirst(2)
            return scopedHost.isEmpty == false && scopedHost.contains("*") == false
        }
        return authority.contains("*") == false
    }

    private static func permissionOriginURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.user = nil
        components.password = nil
        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
