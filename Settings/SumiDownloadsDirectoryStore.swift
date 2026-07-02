//
//  SumiDownloadsDirectoryStore.swift
//  Sumi
//
//  Owns the user-selected downloads directory: security-scoped bookmark
//  persistence, stale bookmark refresh, and the fallback path record.
//

import Foundation

@MainActor
@Observable
final class SumiDownloadsDirectoryStore {
    private let userDefaults: UserDefaults
    private let bookmarkKey = "settings.downloads.directoryBookmark"
    private let pathKey = "settings.downloads.directoryPath"

    private(set) var directoryURL: URL? {
        didSet {
            userDefaults.set(directoryURL?.path, forKey: pathKey)
        }
    }

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        self.directoryURL = userDefaults.string(forKey: pathKey).flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true)
        }
    }

    func setDirectory(_ url: URL) {
        guard !DownloadsDirectoryResolver.usesIsolatedDirectory else {
            directoryURL = url
            return
        }
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            userDefaults.set(bookmark, forKey: bookmarkKey)
            directoryURL = url
        } catch {
            RuntimeDiagnostics.debug(
                "Failed to save downloads directory bookmark: \(String(describing: error))",
                category: "DownloadManager"
            )
        }
    }

    func clear() {
        userDefaults.removeObject(forKey: bookmarkKey)
        userDefaults.removeObject(forKey: pathKey)
        directoryURL = nil
    }

    func resolvedDirectoryURL() -> URL? {
        guard !DownloadsDirectoryResolver.usesIsolatedDirectory else {
            return nil
        }
        guard let bookmark = userDefaults.data(forKey: bookmarkKey) else {
            return directoryURL
        }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale {
                setDirectory(url)
            }
            return url
        } catch {
            return directoryURL
        }
    }
}
