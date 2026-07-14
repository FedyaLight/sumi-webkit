import Foundation

enum ExtensionManifestIconResolver {
    static func iconPath(
        forOwnedURL url: URL?,
        installedExtensions: [InstalledExtension]
    ) -> String? {
        guard let extensionID = ExtensionURLIdentity.extensionID(from: url),
              let extensionRecord = installedExtensions.first(where: {
                  $0.id == extensionID
              })
        else { return nil }
        return iconPath(for: extensionRecord)
    }

    static func iconPath(for extensionRecord: InstalledExtension) -> String? {
        if let iconPath = extensionRecord.iconPath,
           FileManager.default.fileExists(atPath: iconPath) {
            return iconPath
        }
        let root = URL(
            fileURLWithPath: extensionRecord.packagePath,
            isDirectory: true
        )
        return iconPath(in: root, manifest: extensionRecord.manifest)
    }

    static func iconPath(
        in extensionRoot: URL,
        manifest: [String: Any]
    ) -> String? {
        for relativePath in iconCandidates(from: manifest) {
            let resourcePath = relativePath
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .drop(while: { $0 == "/" })
            guard let candidate = ExtensionPathSafety.manifestRelativeURL(
                extensionRoot,
                path: String(resourcePath)
            ), FileManager.default.fileExists(atPath: candidate.path)
            else { continue }
            return candidate.path
        }
        return nil
    }

    private static func iconCandidates(
        from manifest: [String: Any]
    ) -> [String] {
        var candidates: [String] = []

        func appendIconMap(_ value: Any?) {
            guard let map = value as? [String: Any] else { return }
            let sortedKeys = map.keys.sorted { lhs, rhs in
                switch (Int(lhs), Int(rhs)) {
                case let (lhsSize?, rhsSize?):
                    return lhsSize > rhsSize
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs > rhs
                }
            }
            for key in sortedKeys {
                if let path = map[key] as? String, path.isEmpty == false {
                    candidates.append(path)
                }
            }
        }

        appendIconMap(manifest["icons"])
        for key in ["action", "browser_action"] {
            guard let action = manifest[key] as? [String: Any] else { continue }
            appendIconMap(action["default_icon"])
            if let path = action["default_icon"] as? String,
               path.isEmpty == false {
                candidates.append(path)
            }
        }
        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }
}
