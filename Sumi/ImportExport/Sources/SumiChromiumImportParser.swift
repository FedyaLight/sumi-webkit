import Foundation

struct SumiChromiumImportResult {
    var data: SumiPortableData
    var warnings: [String]
}

/// Maps a Chromium-derived browser (Chrome, Edge, Brave, Vivaldi, Opera, …)
/// onto Sumi's model.
///
/// Chromium has no concept of spaces, so each of its profiles becomes one Sumi
/// profile plus one same-named space. Pinned and open tabs come from the SNSS
/// session; bookmarks come from the `Bookmarks` JSON. Those are deliberately
/// separate channels — deriving sidebar tabs from bookmarks would put every
/// bookmark the user ever made into the sidebar.
struct SumiChromiumImportParser {
    var browserName: String
    /// Stable catalog id ("chrome", "edge", …). It namespaces portable ids so
    /// profiles with the same on-disk name from different browsers never merge.
    var sourceIdentifier: String
    var userDataURL: URL
    /// Restricts the import to a single profile directory; `nil` imports all.
    var profileDirectoryName: String?

    init(
        browserName: String,
        sourceIdentifier: String,
        userDataURL: URL,
        profileDirectoryName: String? = nil
    ) {
        self.browserName = browserName
        self.sourceIdentifier = sourceIdentifier
        self.userDataURL = userDataURL
        self.profileDirectoryName = profileDirectoryName
    }

    func parseWithDiagnostics() throws -> SumiChromiumImportResult {
        var profiles = SumiChromiumProfileCatalogReader.profiles(userDataURL: userDataURL)
        if let profileDirectoryName {
            profiles = profiles.filter { $0.directoryName == profileDirectoryName }
        }
        guard profiles.isEmpty == false else {
            throw SumiImportExportError.importFailed("No \(browserName) profiles were found.")
        }

        var warnings: [String] = []
        var portableProfiles: [SumiPortableProfile] = []
        var spaces: [SumiPortableSpace] = []
        var pinned: [SumiPortableLauncher] = []
        var regularTabs: [SumiPortableRegularTab] = []
        var bookmarkRoots: [SumiPortableBookmarkNode] = []

        for (index, profile) in profiles.enumerated() {
            let profileId = "chromium-\(sourceIdentifier)-profile-\(profile.directoryName)"
            let spaceId = "chromium-\(sourceIdentifier)-space-\(profile.directoryName)"
            portableProfiles.append(
                SumiPortableProfile(
                    id: profileId,
                    name: profile.displayName,
                    index: index,
                    sourceDirectoryKey: profile.directoryName
                )
            )
            spaces.append(
                SumiPortableSpace(
                    id: spaceId,
                    name: profile.displayName,
                    icon: "",
                    index: index,
                    profileId: profileId,
                    themeDataBase64: nil,
                    color: nil
                )
            )

            let tabs = sessionTabs(for: profile, warnings: &warnings)
            var pinnedIndex = 0
            var regularIndex = 0
            for tab in tabs {
                let id = "chromium-\(sourceIdentifier)-tab-\(profile.directoryName)-\(tab.windowID)-\(tab.tabID)"
                let title = SumiImportTextNormalization.nilIfBlank(tab.title) ?? tab.url
                if tab.isPinned {
                    pinned.append(
                        SumiPortableLauncher(
                            id: id,
                            title: title,
                            urlString: tab.url,
                            index: pinnedIndex,
                            profileId: nil,
                            executionProfileId: profileId,
                            spaceId: spaceId,
                            folderId: nil,
                            iconAsset: nil,
                            sourceSpaceId: spaceId
                        )
                    )
                    pinnedIndex += 1
                } else {
                    regularTabs.append(
                        SumiPortableRegularTab(
                            id: id,
                            title: title,
                            urlString: tab.url,
                            index: regularIndex,
                            spaceId: spaceId,
                            profileId: profileId,
                            folderId: nil
                        )
                    )
                    regularIndex += 1
                }
            }

            if let node = bookmarkNode(for: profile, multipleProfiles: profiles.count > 1, warnings: &warnings) {
                bookmarkRoots.append(node)
            }
        }

        return SumiChromiumImportResult(
            data: SumiPortableData(
                profiles: portableProfiles,
                spaces: spaces,
                folders: [],
                favorite: [],
                pinnedLaunchers: pinned,
                regularTabs: regularTabs,
                bookmarks: bookmarkRoots
            ),
            warnings: warnings
        )
    }

    /// Session recovery is best effort by design: the format is undocumented,
    /// so a browser that changed it costs the user their open tabs, not the
    /// whole import.
    private func sessionTabs(
        for profile: SumiChromiumProfile,
        warnings: inout [String]
    ) -> [SumiChromiumSessionTab] {
        guard let sessionURL = SumiChromiumSessionReader.sessionFileURL(inProfile: profile.directoryURL) else {
            warnings.append("\(browserName) — \(profile.displayName): no open or pinned tabs were found to import.")
            return []
        }
        let tabs = SumiChromiumSessionReader.readTabs(from: sessionURL)
        if tabs.isEmpty {
            warnings.append(
                "\(browserName) — \(profile.displayName): the session file could not be read, "
                    + "so open and pinned tabs were skipped. Bookmarks are unaffected."
            )
        }
        return tabs
    }

    private func bookmarkNode(
        for profile: SumiChromiumProfile,
        multipleProfiles: Bool,
        warnings: inout [String]
    ) -> SumiPortableBookmarkNode? {
        let fileURL = profile.directoryURL.appendingPathComponent("Bookmarks")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let roots: [String: Any]
        do {
            let raw = try Data(contentsOf: fileURL)
            guard let object = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
                  let decoded = object["roots"] as? [String: Any]
            else {
                warnings.append("\(browserName) — \(profile.displayName): bookmarks were skipped because the file has no roots object.")
                return nil
            }
            roots = decoded
        } catch {
            warnings.append("\(browserName) — \(profile.displayName): bookmarks were skipped (\(error.localizedDescription)).")
            return nil
        }

        var children: [SumiPortableBookmarkNode] = []
        for (key, label) in [
            ("bookmark_bar", "Bookmarks Bar"),
            ("other", "Other Bookmarks"),
            ("synced", "Mobile Bookmarks"),
        ] {
            guard let root = roots[key] as? [String: Any] else { continue }
            let contents = Self.bookmarkChildren(root)
            guard contents.isEmpty == false else { continue }
            children.append(
                SumiPortableBookmarkNode(name: label, kind: .folder, urlString: nil, children: contents)
            )
        }
        guard children.isEmpty == false else { return nil }

        // One profile imports flat; several are namespaced so their bookmark
        // bars do not merge into an indistinguishable pile.
        guard multipleProfiles else {
            return SumiPortableBookmarkNode(name: browserName, kind: .folder, urlString: nil, children: children)
        }
        return SumiPortableBookmarkNode(
            name: "\(browserName) — \(profile.displayName)",
            kind: .folder,
            urlString: nil,
            children: children
        )
    }

    static func bookmarkChildren(_ node: [String: Any]) -> [SumiPortableBookmarkNode] {
        (node["children"] as? [[String: Any]] ?? []).compactMap { child in
            let name = SumiImportTextNormalization.nilIfBlank(child["name"] as? String) ?? "Untitled"
            if child["type"] as? String == "url" {
                guard let url = SumiImportTextNormalization.nilIfBlank(child["url"] as? String),
                      Self.isImportableBookmarkURL(url)
                else { return nil }
                return SumiPortableBookmarkNode(name: name, kind: .bookmark, urlString: url, children: [])
            }
            let children = bookmarkChildren(child)
            return children.isEmpty
                ? nil
                : SumiPortableBookmarkNode(name: name, kind: .folder, urlString: nil, children: children)
        }
    }

    /// Chromium stores internal pages (`chrome://`) alongside real bookmarks;
    /// they would not resolve in Sumi.
    private static func isImportableBookmarkURL(_ string: String) -> Bool {
        guard let scheme = URL(string: string)?.scheme?.lowercased() else { return false }
        return ["http", "https", "ftp", "file"].contains(scheme)
    }
}
