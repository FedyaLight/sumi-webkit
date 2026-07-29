import Foundation

struct SumiFirefoxProfile: Equatable, Sendable {
    var directoryName: String
    var displayName: String
    var directoryURL: URL
}

struct SumiFirefoxImportResult {
    var data: SumiPortableData
    var warnings: [String]
}

/// Maps Firefox (and Firefox-derived browsers other than Zen, which has its own
/// richer parser) onto Sumi's model.
///
/// A Firefox profile becomes one Sumi profile plus one space. Firefox's
/// contextual identities — its containers — become additional Sumi profiles,
/// because that is what they are: isolated cookie jars.
struct SumiFirefoxImportParser {
    var browserName: String
    var profileURL: URL
    var directoryName: String

    /// Reads `profiles.ini`, falling back to globbing `Profiles/` for anything
    /// holding a `places.sqlite`.
    static func profiles(rootURL: URL) -> [SumiFirefoxProfile] {
        let fileManager = FileManager.default
        var found: [SumiFirefoxProfile] = []

        if let text = try? String(contentsOf: rootURL.appendingPathComponent("profiles.ini"), encoding: .utf8) {
            var path: String?
            var isRelative = true
            func flush() {
                defer { path = nil; isRelative = true }
                guard let path else { return }
                let url = isRelative ? rootURL.appendingPathComponent(path) : URL(fileURLWithPath: path)
                guard fileManager.fileExists(atPath: url.appendingPathComponent("places.sqlite").path) else { return }
                found.append(profile(at: url))
            }
            for rawLine in text.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("[") {
                    flush()
                } else if line.hasPrefix("Path=") {
                    path = String(line.dropFirst("Path=".count))
                } else if line.hasPrefix("IsRelative=") {
                    isRelative = line.hasSuffix("1")
                }
            }
            flush()
        }

        if found.isEmpty {
            let profilesRoot = rootURL.appendingPathComponent("Profiles", isDirectory: true)
            let children = (try? fileManager.contentsOfDirectory(
                at: profilesRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            found = children
                .filter { fileManager.fileExists(atPath: $0.appendingPathComponent("places.sqlite").path) }
                .map(profile(at:))
        }

        // Ordered by directory name, not display name: Mozilla profile folders
        // are `<salt>.<name>`, and several can derive the same display name
        // ("default"), which would make the order depend on directory-listing
        // order and change between runs.
        return found.sorted { $0.directoryName.localizedStandardCompare($1.directoryName) == .orderedAscending }
    }

    private static func profile(at url: URL) -> SumiFirefoxProfile {
        let directoryName = url.lastPathComponent
        // Profile directories are named `<salt>.<name>`; the salt is noise.
        let display = directoryName.contains(".")
            ? String(directoryName.drop(while: { $0 != "." }).dropFirst())
            : directoryName
        return SumiFirefoxProfile(
            directoryName: directoryName,
            displayName: SumiImportTextNormalization.nilIfBlank(display) ?? directoryName,
            directoryURL: url
        )
    }

    func parseWithDiagnostics() throws -> SumiFirefoxImportResult {
        var warnings: [String] = []
        let baseProfileId = "firefox-profile-\(directoryName)"
        let spaceId = "firefox-space-\(directoryName)"
        let displayName = Self.profile(at: profileURL).displayName
        let tabs = sessionTabs(warnings: &warnings)
        // Contextual identities are persistent user-facing cookie jars. Import
        // all of them even when none of their tabs or cookies currently exist.
        let containers = (try? SumiMozillaContainerCatalog.read(profileURL: profileURL)) ?? []

        var portableProfiles = [
            SumiPortableProfile(
                id: baseProfileId,
                name: displayName,
                index: 0,
                sourceDirectoryKey: SumiMozillaCookiePartition.sourceProfileKey(
                    directoryName: directoryName,
                    userContextId: 0
                )
            ),
        ]
        for (offset, container) in containers.enumerated() {
            portableProfiles.append(
                SumiPortableProfile(
                    id: "firefox-container-\(directoryName)-\(container.id)",
                    name: container.name,
                    index: offset + 1,
                    sourceDirectoryKey: SumiMozillaCookiePartition.sourceProfileKey(
                        directoryName: directoryName,
                        userContextId: container.id
                    )
                )
            )
        }
        let profileIdByContainer = Dictionary(
            uniqueKeysWithValues: containers.map {
                ($0.id, "firefox-container-\(directoryName)-\($0.id)")
            }
        )

        let spaces = [
            SumiPortableSpace(
                id: spaceId,
                name: displayName,
                icon: "",
                index: 0,
                profileId: baseProfileId,
                themeDataBase64: nil,
                color: nil
            ),
        ]

        var pinned: [SumiPortableLauncher] = []
        var regularTabs: [SumiPortableRegularTab] = []
        for (index, tab) in tabs.enumerated() {
            let id = "firefox-tab-\(directoryName)-\(index)"
            let profileId = profileIdByContainer[tab.userContextId] ?? baseProfileId
            if tab.isPinned {
                pinned.append(
                    SumiPortableLauncher(
                        id: id,
                        title: tab.title,
                        urlString: tab.url,
                        index: pinned.count,
                        profileId: nil,
                        executionProfileId: profileId,
                        spaceId: spaceId,
                        folderId: nil,
                        iconAsset: nil,
                        sourceSpaceId: spaceId
                    )
                )
            } else {
                regularTabs.append(
                    SumiPortableRegularTab(
                        id: id,
                        title: tab.title,
                        urlString: tab.url,
                        index: regularTabs.count,
                        spaceId: spaceId,
                        profileId: profileId,
                        folderId: nil
                    )
                )
            }
        }

        return SumiFirefoxImportResult(
            data: SumiPortableData(
                profiles: portableProfiles,
                spaces: spaces,
                folders: [],
                essentials: [],
                pinnedLaunchers: pinned,
                regularTabs: regularTabs,
                bookmarks: bookmarks(warnings: &warnings)
            ),
            warnings: warnings
        )
    }

    // MARK: - Sources

    private struct SessionTab {
        var url: String
        var title: String
        var isPinned: Bool
        var userContextId: Int
    }

    private func sessionTabs(warnings: inout [String]) -> [SessionTab] {
        let candidates = [
            "sessionstore.jsonlz4",
            "sessionstore-backups/recovery.jsonlz4",
            "sessionstore-backups/recovery.baklz4",
        ].map(profileURL.appendingPathComponent)
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return []
        }

        let root: [String: Any]
        do {
            let decoded = try SumiMozillaLZ4Decoder.decode(Data(contentsOf: url))
            guard let object = try JSONSerialization.jsonObject(with: decoded) as? [String: Any] else {
                warnings.append("\(browserName): the session file did not decode to JSON, so open tabs were skipped.")
                return []
            }
            root = object
        } catch {
            warnings.append("\(browserName): open tabs were skipped (\(error.localizedDescription)).")
            return []
        }

        var output: [SessionTab] = []
        for window in root["windows"] as? [[String: Any]] ?? [] {
            for tab in window["tabs"] as? [[String: Any]] ?? [] {
                guard let entry = SumiZenImportParser.currentEntry(of: tab),
                      let urlString = SumiImportTextNormalization.nilIfBlank(entry["url"] as? String),
                      urlString.hasPrefix("about:") == false
                else { continue }
                output.append(
                    SessionTab(
                        url: urlString,
                        title: SumiImportTextNormalization.nilIfBlank(entry["title"] as? String) ?? urlString,
                        isPinned: tab["pinned"] as? Bool ?? false,
                        userContextId: tab["userContextId"] as? Int ?? 0
                    )
                )
            }
        }
        return output
    }

    private func bookmarks(warnings: inout [String]) -> [SumiPortableBookmarkNode] {
        let placesURL = profileURL.appendingPathComponent("places.sqlite")
        guard FileManager.default.fileExists(atPath: placesURL.path) else { return [] }
        do {
            let nodes = try SumiBookmarkImportSource(
                id: "firefox-\(directoryName)",
                title: browserName,
                fileURL: placesURL,
                kind: .firefoxSQLite
            ).readBookmarks()
            let converted = SumiBookmarkPortableBridge.portableNodes(from: nodes)
            guard converted.isEmpty == false else { return [] }
            return [SumiPortableBookmarkNode(name: browserName, kind: .folder, urlString: nil, children: converted)]
        } catch {
            warnings.append("\(browserName): bookmarks were skipped (\(error.localizedDescription)).")
            return []
        }
    }
}
