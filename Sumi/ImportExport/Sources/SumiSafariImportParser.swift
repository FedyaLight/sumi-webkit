import Foundation

struct SumiSafariImportResult {
    var data: SumiPortableData
    var warnings: [String]
}

/// Maps Safari onto Sumi's model.
///
/// Safari's data lives under `~/Library/Safari`, which macOS protects with Full
/// Disk Access. A permission failure is reported as such rather than as a
/// missing file, because the remedy is a System Settings toggle, not a
/// different file.
///
/// `LastSession.plist` has no published schema and has changed shape across
/// releases, so open tabs are recovered by searching the property list for tab
/// records rather than by walking a fixed key path. If Apple changes it again,
/// the import loses open tabs and keeps everything else.
struct SumiSafariImportParser {
    enum ParseError: LocalizedError, Equatable {
        case fullDiskAccessRequired

        var errorDescription: String? {
            "Sumi needs Full Disk Access to read Safari's data."
        }
    }

    var browserName: String = "Safari"
    var safariDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Safari", isDirectory: true)

    /// True when the directory exists but macOS refuses to read it.
    static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.fileReadNoPermission.rawValue {
            return true
        }
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EPERM)
    }

    func parseWithDiagnostics() throws -> SumiSafariImportResult {
        var warnings: [String] = []
        let profileId = "safari-profile-default"
        let spaceId = "safari-space-default"

        let bookmarks = try self.bookmarks(warnings: &warnings)
        let tabs = openTabs(warnings: &warnings)

        var regularTabs: [SumiPortableRegularTab] = []
        for (index, tab) in tabs.enumerated() {
            regularTabs.append(
                SumiPortableRegularTab(
                    id: "safari-tab-\(index)",
                    title: tab.title,
                    urlString: tab.url,
                    index: index,
                    spaceId: spaceId,
                    profileId: profileId,
                    folderId: nil
                )
            )
        }

        return SumiSafariImportResult(
            data: SumiPortableData(
                profiles: [
                    SumiPortableProfile(id: profileId, name: browserName, index: 0, sourceDirectoryKey: "default")
                ],
                spaces: [
                    SumiPortableSpace(
                        id: spaceId,
                        name: browserName,
                        icon: "",
                        index: 0,
                        profileId: profileId,
                        themeDataBase64: nil,
                        color: nil
                    )
                ],
                folders: [],
                essentials: [],
                pinnedLaunchers: [],
                regularTabs: regularTabs,
                bookmarks: bookmarks
            ),
            warnings: warnings
        )
    }

    // MARK: - Sources

    private func bookmarks(warnings: inout [String]) throws -> [SumiPortableBookmarkNode] {
        let fileURL = safariDirectoryURL.appendingPathComponent("Bookmarks.plist")
        do {
            _ = try Data(contentsOf: fileURL)
        } catch {
            if Self.isPermissionError(error) { throw ParseError.fullDiskAccessRequired }
            warnings.append("\(browserName): bookmarks were skipped (\(error.localizedDescription)).")
            return []
        }

        do {
            let nodes = try SumiBookmarkImportSource(
                id: "safari",
                title: browserName,
                fileURL: fileURL,
                kind: .safariPlist
            ).readBookmarks()
            let converted = try SumiBookmarkPortableBridge.portableNodes(from: nodes)
            guard converted.isEmpty == false else { return [] }
            return [SumiPortableBookmarkNode(name: browserName, kind: .folder, urlString: nil, children: converted)]
        } catch {
            warnings.append("\(browserName): bookmarks were skipped (\(error.localizedDescription)).")
            return []
        }
    }

    private func openTabs(warnings: inout [String]) -> [SafariTabRecord] {
        let candidates = ["LastSession.plist", "PersistentTabGroups.plist"]
            .map(safariDirectoryURL.appendingPathComponent)
        guard let fileURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            let tabs = Self.tabRecords(in: plist)
            if tabs.isEmpty {
                warnings.append(
                    "\(browserName): no open tabs were recognised in \(fileURL.lastPathComponent); "
                        + "bookmarks are unaffected."
                )
            }
            return tabs
        } catch {
            warnings.append("\(browserName): open tabs were skipped (\(error.localizedDescription)).")
            return []
        }
    }

    /// Depth-first search for tab records. Safari has spelled the keys
    /// differently across versions, so several spellings are accepted and the
    /// structure around them is not assumed.
    static func tabRecords(in object: Any) -> [SafariTabRecord] {
        var output: [SafariTabRecord] = []
        var seen: Set<String> = []

        func visit(_ node: Any) {
            if let dictionary = node as? [String: Any] {
                if let url = ["TabURL", "URL", "tabURL"].lazy
                    .compactMap({ SumiImportTextNormalization.nilIfBlank(dictionary[$0] as? String) })
                    .first,
                    url.hasPrefix("http") {
                    let title = ["TabTitle", "Title", "tabTitle"].lazy
                        .compactMap { SumiImportTextNormalization.nilIfBlank(dictionary[$0] as? String) }
                        .first ?? url
                    if seen.insert(url).inserted {
                        output.append(SafariTabRecord(url: url, title: title))
                    }
                }
                for value in dictionary.values { visit(value) }
            } else if let array = node as? [Any] {
                for value in array { visit(value) }
            }
        }

        visit(object)
        return output
    }

    struct SafariTabRecord: Equatable, Sendable {
        var url: String
        var title: String
    }
}
