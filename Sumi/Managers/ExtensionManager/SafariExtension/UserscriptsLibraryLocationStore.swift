import Foundation

@MainActor
final class UserscriptsLibraryLocationStore {
    private static let bookmarkKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.userscripts.libraryBookmark.v1"

    private let userDefaults: UserDefaults
    private let applicationSupportRoot: URL

    init(
        userDefaults: UserDefaults = .standard,
        applicationSupportRoot: URL = SumiApplicationSupportDirectory.appRootURL()
    ) {
        self.userDefaults = userDefaults
        self.applicationSupportRoot = applicationSupportRoot
    }

    var stateRootURL: URL {
        applicationSupportRoot.appendingPathComponent("Userscripts", isDirectory: true)
    }

    var defaultScriptsURL: URL {
        stateRootURL.appendingPathComponent("scripts", isDirectory: true)
    }

    func scriptsURL() -> URL {
        guard let bookmark = userDefaults.data(forKey: Self.bookmarkKey) else {
            return defaultScriptsURL
        }

        var stale = false
        let resolved: URL
        do {
            resolved = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            userDefaults.removeObject(forKey: Self.bookmarkKey)
            return defaultScriptsURL
        }

        if stale {
            do {
                try storeExternalScriptsURL(resolved)
            } catch {
                userDefaults.removeObject(forKey: Self.bookmarkKey)
                return defaultScriptsURL
            }
        }
        return resolved.standardizedFileURL
    }

    func storeExternalScriptsURL(_ url: URL) throws {
        let standardized = url.standardizedFileURL
        if standardized == defaultScriptsURL.standardizedFileURL {
            userDefaults.removeObject(forKey: Self.bookmarkKey)
            return
        }

        let bookmark = try standardized.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        userDefaults.set(bookmark, forKey: Self.bookmarkKey)
    }

    func resetToDefault() {
        userDefaults.removeObject(forKey: Self.bookmarkKey)
    }
}
