import Foundation

/// A profile directory inside a Chromium user-data root.
struct SumiChromiumProfile: Equatable, Sendable {
    /// The on-disk directory name ("Default", "Profile 1"). This is the join
    /// key bulk extractors use.
    var directoryName: String
    /// The name the user sees, from `Local State`; falls back to the directory.
    var displayName: String
    var directoryURL: URL
}

/// Enumerates the profiles of any Chromium-derived browser, including Arc.
enum SumiChromiumProfileCatalogReader {
    /// Directories that hold a `Bookmarks` or `History` file are profiles;
    /// everything else in the user-data root is support state.
    static func profiles(userDataURL: URL) -> [SumiChromiumProfile] {
        let fileManager = FileManager.default
        let children = (try? fileManager.contentsOfDirectory(
            at: userDataURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let names = displayNames(userDataURL: userDataURL)

        return children
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    && ["Bookmarks", "History"].contains { fileManager.fileExists(atPath: url.appendingPathComponent($0).path) }
            }
            .map { url in
                let directoryName = url.lastPathComponent
                return SumiChromiumProfile(
                    directoryName: directoryName,
                    displayName: names[directoryName] ?? directoryName,
                    directoryURL: url
                )
            }
            .sorted { $0.directoryName.localizedStandardCompare($1.directoryName) == .orderedAscending }
    }

    static func displayNames(userDataURL: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: userDataURL.appendingPathComponent("Local State")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (root["profile"] as? [String: Any])?["info_cache"] as? [String: Any]
        else { return [:] }
        return cache.compactMapValues { entry in
            guard let entry = entry as? [String: Any] else { return nil }
            return SumiImportTextNormalization.nilIfBlank(entry["name"] as? String)
        }
    }

    /// Chromium moved its cookie jar under `Network/` in M96; older profiles and
    /// some forks still keep it at the profile root.
    static func cookiesURL(inProfile profileURL: URL) -> URL? {
        [profileURL.appendingPathComponent("Network/Cookies"), profileURL.appendingPathComponent("Cookies")]
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
