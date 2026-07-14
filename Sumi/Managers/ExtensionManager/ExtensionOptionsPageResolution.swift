import Foundation
import OSLog

enum ExtensionOptionsPageResolution {
    private static let log = Logger.sumi(category: "Extensions")
    private static let fallbackPaths = [
        "ui/options/index.html",
        "options/index.html",
        "options.html",
        "settings.html",
    ]

    static func storedPath(
        from manifest: [String: Any],
        in extensionRoot: URL
    ) -> String? {
        if let declaredPath = ExtensionManifestSemantics.optionsPagePath(
            from: manifest
        ), let normalizedPath = existingValidatedPath(
            declaredPath,
            in: extensionRoot
        ) {
            return normalizedPath
        }
        for candidate in fallbackPaths {
            if let normalizedPath = existingValidatedPath(
                candidate,
                in: extensionRoot
            ) {
                return normalizedPath
            }
        }
        return nil
    }

    static func resolvedURL(
        sdkURL: URL?,
        persistedPath: String?,
        manifest: [String: Any],
        extensionRoot: URL
    ) throws -> URL {
        if let sdkURL {
            return sdkURL.isFileURL
                ? try ExtensionPathSafety.validatedPageURL(
                    sdkURL,
                    within: extensionRoot
                )
                : sdkURL
        }

        let relativePath = persistedPath
            ?? ExtensionManifestSemantics.optionsPagePath(from: manifest)
            ?? storedPath(from: manifest, in: extensionRoot)
        guard let relativePath,
              let candidate = ExtensionPathSafety.manifestRelativeURL(
                  extensionRoot,
                  path: relativePath
              )
        else { throw notFoundError() }
        return try ExtensionPathSafety.validatedPageURL(
            candidate,
            within: extensionRoot
        )
    }

    static func existingValidatedPath(
        _ relativePath: String,
        in extensionRoot: URL
    ) -> String? {
        let trimmedPath = relativePath.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard trimmedPath.isEmpty == false,
              let candidate = ExtensionPathSafety.manifestRelativeURL(
                  extensionRoot,
                  path: trimmedPath
              )
        else { return nil }

        let validatedURL: URL
        do {
            validatedURL = try ExtensionPathSafety.validatedPageURL(
                candidate,
                within: extensionRoot
            )
        } catch {
            log.error(
                "Rejected extension options page path \(trimmedPath, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
        guard FileManager.default.fileExists(atPath: validatedURL.path) else {
            return nil
        }
        return ExtensionPathSafety.relativePath(
            for: validatedURL,
            within: extensionRoot
        )
    }

    static func notFoundError() -> NSError {
        ExtensionManagerCallbackError.optionsPageNotFound.nsError()
    }
}
