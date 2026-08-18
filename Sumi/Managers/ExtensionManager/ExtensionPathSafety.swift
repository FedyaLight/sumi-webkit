import Foundation
import OSLog
import SumiDomain

enum ExtensionPathSafety {
    private static let log = Logger.sumi(category: "Extensions")

    /// Joins a package root with a manifest-relative path. Absolute paths and
    /// traversal segments are rejected before Foundation performs resolution.
    static func manifestRelativeURL(_ root: URL, path relative: String) -> URL? {
        var path = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.isEmpty == false, path.hasPrefix("/") == false else {
            return nil
        }
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }
        guard path.isEmpty == false else { return nil }
        for segment in path.split(separator: "/", omittingEmptySubsequences: true)
        where segment == ".." || segment == "." {
            return nil
        }
        return root.appending(path: path)
    }

    static func applicationSupportRoot() -> URL {
        SumiApplicationSupportDirectory.appRootURL()
    }

    static func extensionsDirectory() -> URL {
        let directory = applicationSupportRoot().appendingPathComponent(
            "Extensions",
            isDirectory: true
        )
        createDirectoryIfNeeded(at: directory)
        return directory
    }

    @discardableResult
    static func validatedExtensionID(_ extensionID: String) throws -> String {
        let separators = CharacterSet(charactersIn: "/\\:")
        guard extensionID.isEmpty == false,
              extensionID == extensionID.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ), extensionID != ".", extensionID != "..",
              extensionID.rangeOfCharacter(from: separators) == nil,
              extensionID.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) == false
        else {
            throw ExtensionError.installationFailed(
                "Extension identifier is not a safe path component."
            )
        }
        return extensionID
    }

    static func extensionDirectory(
        for extensionID: String,
        under root: URL
    ) throws -> URL {
        let extensionID = try validatedExtensionID(extensionID)
        let standardizedRoot = root.standardizedFileURL
        let directory = standardizedRoot.appendingPathComponent(
            extensionID,
            isDirectory: true
        ).standardizedFileURL

        guard directory.deletingLastPathComponent().standardizedFileURL.path
            == standardizedRoot.path
        else {
            throw ExtensionError.installationFailed(
                "Extension directory escapes the expected storage root."
            )
        }
        return directory
    }

    static func validatedPageURL(
        _ candidateURL: URL,
        within extensionRoot: URL
    ) throws -> URL {
        let root = extensionRoot.resolvingSymlinksInPath().standardizedFileURL
        let candidate = candidateURL.resolvingSymlinksInPath()
            .standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path == root.path || candidate.path.hasPrefix(rootPath)
        else {
            throw ExtensionManagerCallbackError
                .optionsURLOutsideExtensionDirectory.nsError()
        }
        return candidate
    }

    static func relativePath(for pageURL: URL, within extensionRoot: URL) -> String? {
        let root = extensionRoot.resolvingSymlinksInPath().standardizedFileURL
        let page = pageURL.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard page.path.hasPrefix(rootPath) else { return nil }
        let relativePath = String(page.path.dropFirst(rootPath.count))
        return relativePath.isEmpty ? nil : relativePath
    }

    private static func createDirectoryIfNeeded(at directory: URL) {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            log.error(
                "Failed to create extension support directory \(directory.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
