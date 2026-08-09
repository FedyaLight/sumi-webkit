import Foundation
import SumiDomain

struct SumiArcImportResult {
    var data: SumiPortableData
    var warnings: [String]
}

struct SumiArcImportParser {
    /// Arc's Chromium-style profile root. Injectable so tests never depend on a
    /// real Arc install.
    var userDataURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Arc/User Data", isDirectory: true)

    func parse(sidebarURL: URL) throws -> SumiPortableData {
        var warnings: [String] = []
        return try parse(sidebarURL: sidebarURL, warnings: &warnings)
    }

    func parseWithDiagnostics(sidebarURL: URL) throws -> SumiArcImportResult {
        var warnings: [String] = []
        let data = try parse(sidebarURL: sidebarURL, warnings: &warnings)
        return SumiArcImportResult(data: data, warnings: warnings)
    }

    private func parse(sidebarURL: URL, warnings: inout [String]) throws -> SumiPortableData {
        guard FileManager.default.fileExists(atPath: sidebarURL.path) else {
            throw SumiImportExportError.unsupportedFile("Arc StorableSidebar.json was not found.")
        }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: sidebarURL))
        guard let root = object as? [String: Any] else {
            throw SumiImportExportError.unsupportedFile("Arc StorableSidebar.json is not a JSON object.")
        }

        let local = localSidebar(root)
        let itemLookup = alternatingDictionary(local["items"] as? [Any] ?? [])
        let sidebarSpaces = local["spaces"] as? [Any] ?? []
        // The local sidebar is the authority: Arc installs that never completed
        // a Firebase sync carry an empty `spaceModels` array while holding every
        // space here in full. Sync data only fills gaps.
        let spacesInfo = parseSpacesInfo(local: sidebarSpaces, syncRoot: root)
        guard spacesInfo.isEmpty == false else {
            throw SumiImportExportError.importFailed("Arc spaces were not found in StorableSidebar.json.")
        }

        // Arc is Chromium underneath, so its user-visible profile names live in
        // the same `Local State` file as Chrome's.
        let profileDisplayNames = SumiChromiumProfileCatalogReader.displayNames(userDataURL: userDataURL)
        var profileRecordsByName: [String: SumiPortableProfile] = [:]
        var portableSpaces: [SumiPortableSpace] = []
        var folders: [SumiPortableFolder] = []
        var pinned: [SumiPortableLauncher] = []
        var regularTabs: [SumiPortableRegularTab] = []
        var spaceProfileName: [String: String] = [:]

        for pairIndex in stride(from: 0, to: sidebarSpaces.count, by: 2) {
            guard pairIndex + 1 < sidebarSpaces.count,
                  let spaceId = sidebarSpaces[pairIndex] as? String
            else { continue }
            let info = spacesInfo[spaceId] ?? ArcSpaceInfo()
            let profileName = SumiImportTextNormalization.nilIfBlank(info.profile) ?? "Default"
            let profileId = "arc-profile-\(profileName)"
            if profileRecordsByName[profileName] == nil {
                profileRecordsByName[profileName] = SumiPortableProfile(
                    id: profileId,
                    name: profileDisplayNames[profileName] ?? profileName,
                    index: profileRecordsByName.count,
                    sourceDirectoryKey: profileName
                )
            }
            spaceProfileName[spaceId] = profileName
            portableSpaces.append(
                SumiPortableSpace(
                    id: spaceId,
                    name: Self.spaceName(info: info, spaceId: spaceId, ordinal: portableSpaces.count + 1),
                    icon: Self.spaceIcon(info.icon),
                    index: portableSpaces.count,
                    profileId: profileId,
                    themeDataBase64: nil,
                    color: info.colors.first,
                    colors: info.colors.isEmpty ? nil : info.colors
                )
            )

            let pinnedOrder = displayOrder(for: "pinned", spaceId: spaceId, local: local, itemLookup: itemLookup)
            var nextPinnedIndex = 0
            processArcPinnedItems(
                pinnedOrder,
                itemLookup: itemLookup,
                spaceId: spaceId,
                profileId: profileId,
                parentFolderId: nil,
                folderPath: [],
                folders: &folders,
                pinned: &pinned,
                nextIndex: &nextPinnedIndex
            )

            let unpinnedOrder = displayOrder(for: "unpinned", spaceId: spaceId, local: local, itemLookup: itemLookup)
            for tabId in flattenedTabIds(unpinnedOrder, itemLookup: itemLookup) {
                guard let item = itemLookup[tabId],
                      let tab = (item["data"] as? [String: Any])?["tab"] as? [String: Any],
                      let url = tab["savedURL"] as? String,
                      url.isEmpty == false
                else { continue }
                regularTabs.append(
                    SumiPortableRegularTab(
                        id: tabId,
                        title: (item["title"] as? String) ?? (tab["savedTitle"] as? String) ?? url,
                        urlString: url,
                        index: regularTabs.count,
                        spaceId: spaceId,
                        profileId: profileId,
                        folderId: nil
                    )
                )
            }
        }

        let favorite = parseFavorite(
            local: local,
            itemLookup: itemLookup,
            spaceProfileName: spaceProfileName,
            profileRecordsByName: profileRecordsByName
        )

        folders = SumiPortableFolderHierarchyRepair.repaired(folders)
        let bookmarks = parseArcBookmarks(warnings: &warnings)

        return SumiPortableData(
            profiles: Array(profileRecordsByName.values).sorted { $0.index < $1.index },
            spaces: portableSpaces,
            folders: folders,
            favorite: favorite,
            pinnedLaunchers: pinned.map { launcher in
                var copy = launcher
                if let folderId = copy.folderId,
                   folders.contains(where: { $0.id == folderId }) == false {
                    copy.folderId = nil
                }
                return copy
            },
            regularTabs: regularTabs,
            bookmarks: bookmarks
        )
    }

    /// Merges space metadata from the local sidebar (authoritative) with the
    /// Firebase sync mirror (fills gaps only). Either source may be empty.
    private func parseSpacesInfo(local sidebarSpaces: [Any], syncRoot: [String: Any]) -> [String: ArcSpaceInfo] {
        var output: [String: ArcSpaceInfo] = [:]
        for idx in stride(from: 0, to: sidebarSpaces.count, by: 2) {
            guard idx + 1 < sidebarSpaces.count,
                  let id = sidebarSpaces[idx] as? String,
                  let value = sidebarSpaces[idx + 1] as? [String: Any]
            else { continue }
            output[id] = spaceInfo(from: value)
        }

        let spaceModels = (((syncRoot["firebaseSyncState"] as? [String: Any])?["syncData"] as? [String: Any])?["spaceModels"] as? [Any]) ?? []
        for idx in stride(from: 0, to: spaceModels.count, by: 2) {
            guard idx + 1 < spaceModels.count,
                  let id = spaceModels[idx] as? String,
                  let wrapped = spaceModels[idx + 1] as? [String: Any],
                  let value = wrapped["value"] as? [String: Any]
            else { continue }
            let synced = spaceInfo(from: value)
            guard var existing = output[id] else {
                output[id] = synced
                continue
            }
            existing.name = existing.name ?? synced.name
            existing.icon = existing.icon ?? synced.icon
            existing.profile = existing.profile ?? synced.profile
            if existing.colors.isEmpty { existing.colors = synced.colors }
            output[id] = existing
        }
        return output
    }

    private func spaceInfo(from value: [String: Any]) -> ArcSpaceInfo {
        let customInfo = value["customInfo"] as? [String: Any] ?? [:]
        let iconType = customInfo["iconType"] as? [String: Any] ?? [:]
        // Arc has shipped three icon encodings; newest first.
        let icon = SumiImportTextNormalization.nilIfBlank(iconType["emoji_v2"] as? String)
            ?? SumiImportTextNormalization.nilIfBlank(iconType["emoji"] as? String)
            ?? SumiImportTextNormalization.nilIfBlank(iconType["icon"] as? String)
        let profile = (((value["profile"] as? [String: Any])?["custom"] as? [String: Any])?["_0"] as? [String: Any])?["directoryBasename"] as? String
        let palette = (customInfo["windowTheme"] as? [String: Any])?["primaryColorPalette"] as? [String: Any] ?? [:]
        // Arc's palette carries the whole gradient; taking only `midTone` would
        // flatten every imported space to a single colour.
        let colors = ["midTone", "shaded", "tintedLight"]
            .compactMap { palette[$0] as? [String: Any] }
            .compactMap(rgbColor(fromArcComponents:))
        return ArcSpaceInfo(
            name: SumiImportTextNormalization.nilIfBlank(value["title"] as? String),
            icon: icon,
            profile: SumiImportTextNormalization.nilIfBlank(profile),
            colors: dedupedPreservingOrder(colors)
        )
    }

    private func dedupedPreservingOrder(_ colors: [SumiPortableRGBColor]) -> [SumiPortableRGBColor] {
        var seen: Set<String> = []
        return colors.filter { seen.insert($0.hex).inserted }
    }

    /// Arc's default spaces have no `title`; their identifiers spell out the
    /// intent instead. Never surface a raw UUID to the user.
    static func spaceName(info: ArcSpaceInfo, spaceId: String, ordinal: Int) -> String {
        if let name = SumiImportTextNormalization.nilIfBlank(info.name) { return name }
        for (marker, name) in [("PersonalSpace", "Personal"), ("WorkSpace", "Work")]
        where spaceId.localizedCaseInsensitiveContains(marker) {
            return name
        }
        return "Space \(ordinal)"
    }

    /// Arc's non-emoji icons name glyphs from Arc's own set, which mostly does
    /// not overlap SF Symbols. Names confirmed against real installs are
    /// translated; anything else is tried as an SF Symbol and otherwise falls
    /// back to Sumi's default dot rather than rendering a missing-symbol box.
    static func spaceIcon(_ raw: String?) -> String {
        guard let raw = SumiImportTextNormalization.nilIfBlank(raw) else { return "" }
        let translated = arcGlyphNameToSystemSymbol[raw] ?? raw
        return SumiPersistentGlyph.normalizedSpaceIconValue(translated)
    }

    private static let arcGlyphNameToSystemSymbol: [String: String] = [
        "planet": "globe.americas",
    ]

    private func processArcPinnedItems(
        _ itemIds: [String],
        itemLookup: [String: [String: Any]],
        spaceId: String,
        profileId: String,
        parentFolderId: String?,
        folderPath: [String],
        folders: inout [SumiPortableFolder],
        pinned: inout [SumiPortableLauncher],
        nextIndex: inout Int
    ) {
        // Split views are expanded first so the tabs they hold keep their place
        // in the pinned order instead of disappearing with the container.
        for itemId in flattenedTabIds(itemIds, itemLookup: itemLookup) {
            guard let item = itemLookup[itemId],
                  let data = item["data"] as? [String: Any]
            else { continue }
            if let tab = data["tab"] as? [String: Any],
               let url = tab["savedURL"] as? String,
               url.isEmpty == false {
                // A split view's children point at the split view as their
                // parent, which is not a folder; fall back to the folder the
                // walk is actually inside.
                let declaredParent = SumiImportTextNormalization.nilIfBlank(item["parentID"] as? String)
                let isFolderParent = declaredParent.map { (itemLookup[$0]?["data"] as? [String: Any])?["list"] != nil } ?? false
                pinned.append(
                    SumiPortableLauncher(
                        id: itemId,
                        title: (item["title"] as? String) ?? (tab["savedTitle"] as? String) ?? url,
                        urlString: url,
                        index: nextIndex,
                        profileId: nil,
                        executionProfileId: profileId,
                        spaceId: spaceId,
                        folderId: isFolderParent ? declaredParent : parentFolderId,
                        iconAsset: nil,
                        sourceSpaceId: spaceId
                    )
                )
                nextIndex += 1
            } else if data["list"] != nil {
                let title = SumiImportTextNormalization.nilIfBlank(item["title"] as? String)
                    ?? "Folder \(folders.count + 1)"
                let path = folderPath + [title]
                folders.append(
                    SumiPortableFolder(
                        id: itemId,
                        name: title,
                        icon: SumiZenFolderIconCatalog.normalizedFolderIconValue(nil),
                        colorHex: "#000000",
                        spaceId: spaceId,
                        parentFolderId: parentFolderId,
                        isOpen: true,
                        index: nextIndex,
                        sourcePath: path
                    )
                )
                nextIndex += 1
                processArcPinnedItems(
                    item["childrenIds"] as? [String] ?? [],
                    itemLookup: itemLookup,
                    spaceId: spaceId,
                    profileId: profileId,
                    parentFolderId: itemId,
                    folderPath: path,
                    folders: &folders,
                    pinned: &pinned,
                    nextIndex: &nextIndex
                )
            }
        }
    }

    private func parseFavorite(
        local: [String: Any],
        itemLookup: [String: [String: Any]],
        spaceProfileName: [String: String],
        profileRecordsByName: [String: SumiPortableProfile]
    ) -> [SumiPortableLauncher] {
        var output: [SumiPortableLauncher] = []
        let profileToSpace = Dictionary(
            spaceProfileName.map { ($0.value, $0.key) },
            uniquingKeysWith: { first, _ in first }
        )
        // `topAppsContainerIDs` is the ordered authority. Walking `itemLookup`
        // instead would emit favorite in dictionary order, so the same Arc
        // install would import a different pin order on every run.
        for (profileName, containerId) in favoriteContainers(local: local, itemLookup: itemLookup) {
            guard let item = itemLookup[containerId] else { continue }
            let targetSpaceId = profileToSpace[profileName]
            let profileId = profileRecordsByName[profileName]?.id ?? "arc-profile-\(profileName)"
            let children = item["childrenIds"] as? [String] ?? []
            for (idx, childId) in children.enumerated() {
                guard let child = itemLookup[childId],
                      let tab = (child["data"] as? [String: Any])?["tab"] as? [String: Any],
                      let url = tab["savedURL"] as? String,
                      url.isEmpty == false
                else { continue }
                output.append(
                    SumiPortableLauncher(
                        id: childId,
                        title: (child["title"] as? String) ?? (tab["savedTitle"] as? String) ?? url,
                        urlString: url,
                        index: idx,
                        profileId: profileId,
                        executionProfileId: profileId,
                        spaceId: nil,
                        folderId: nil,
                        iconAsset: nil,
                        sourceSpaceId: targetSpaceId
                    )
                )
            }
        }
        return output
    }

    /// Resolves `[marker, containerId, marker, containerId, …]` into ordered
    /// `(profileName, containerId)` pairs. Falls back to scanning items for
    /// `topApps` containers when the marker array is absent.
    private func favoriteContainers(
        local: [String: Any],
        itemLookup: [String: [String: Any]]
    ) -> [(profileName: String, containerId: String)] {
        let markers = local["topAppsContainerIDs"] as? [Any] ?? []
        var output: [(profileName: String, containerId: String)] = []
        for idx in stride(from: 0, to: markers.count, by: 2) {
            guard idx + 1 < markers.count,
                  let containerId = markers[idx + 1] as? String
            else { continue }
            output.append((profileName(fromArcMarker: markers[idx]), containerId))
        }
        guard output.isEmpty else { return output }

        return itemLookup.keys.sorted().compactMap { id in
            guard let containerType = ((itemLookup[id]?["data"] as? [String: Any])?["itemContainer"] as? [String: Any])?["containerType"] as? [String: Any],
                  let topApps = (containerType["topApps"] as? [String: Any])?["_0"]
            else { return nil }
            return (profileName(fromArcMarker: topApps), id)
        }
    }

    private func profileName(fromArcMarker marker: Any) -> String {
        guard let marker = marker as? [String: Any] else { return "Default" }
        if let basename = ((marker["custom"] as? [String: Any])?["_0"] as? [String: Any])?["directoryBasename"] as? String,
           let name = SumiImportTextNormalization.nilIfBlank(basename) {
            return name
        }
        return "Default"
    }

    private func parseArcBookmarks(warnings: inout [String]) -> [SumiPortableBookmarkNode] {
        let userData = userDataURL
        guard FileManager.default.fileExists(atPath: userData.path) else {
            return []
        }

        let profileDirs: [URL]
        do {
            profileDirs = try FileManager.default.contentsOfDirectory(
                at: userData,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            warnings.append("Arc bookmarks were skipped because the User Data directory could not be read: \(error.localizedDescription)")
            return []
        }

        var profileFolders: [SumiPortableBookmarkNode] = []
        for profile in profileDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let file = profile.appendingPathComponent("Bookmarks")
            guard FileManager.default.fileExists(atPath: file.path) else { continue }

            let raw: Data
            do {
                raw = try Data(contentsOf: file)
            } catch {
                warnings.append("Arc bookmarks for \(profile.lastPathComponent) were skipped because Bookmarks could not be read: \(error.localizedDescription)")
                continue
            }

            let object: [String: Any]
            do {
                guard let decoded = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
                    warnings.append("Arc bookmarks for \(profile.lastPathComponent) were skipped because Bookmarks is not a JSON object.")
                    continue
                }
                object = decoded
            } catch {
                warnings.append("Arc bookmarks for \(profile.lastPathComponent) were skipped because Bookmarks could not be decoded: \(error.localizedDescription)")
                continue
            }

            guard let roots = object["roots"] as? [String: Any] else {
                warnings.append("Arc bookmarks for \(profile.lastPathComponent) were skipped because Bookmarks has no roots object.")
                continue
            }
            var children: [SumiPortableBookmarkNode] = []
            for key in ["bookmark_bar", "other", "synced"] {
                if let root = roots[key] as? [String: Any] {
                    children.append(contentsOf: chromiumBookmarkChildren(root))
                }
            }
            guard children.isEmpty == false else { continue }
            profileFolders.append(
                SumiPortableBookmarkNode(
                    name: "Arc \(profile.lastPathComponent)",
                    kind: .folder,
                    urlString: nil,
                    children: children
                )
            )
        }
        return profileFolders
    }

    private func chromiumBookmarkChildren(_ node: [String: Any]) -> [SumiPortableBookmarkNode] {
        (node["children"] as? [[String: Any]] ?? []).compactMap { child in
            let name = child["name"] as? String ?? "Untitled"
            if child["type"] as? String == "url",
               let url = child["url"] as? String,
               url.isEmpty == false {
                return SumiPortableBookmarkNode(name: name, kind: .bookmark, urlString: url, children: [])
            }
            let children = chromiumBookmarkChildren(child)
            return children.isEmpty ? nil : SumiPortableBookmarkNode(name: name, kind: .folder, urlString: nil, children: children)
        }
    }

    private func localSidebar(_ root: [String: Any]) -> [String: Any] {
        let containers = (root["sidebar"] as? [String: Any])?["containers"] as? [[String: Any]] ?? []
        guard containers.count > 1 else { return [:] }
        return containers[1]
    }

    private func displayOrder(
        for marker: String,
        spaceId: String,
        local: [String: Any],
        itemLookup: [String: [String: Any]]
    ) -> [String] {
        let sidebarSpaces = local["spaces"] as? [Any] ?? []
        var spaceData: [String: Any] = [:]
        for idx in stride(from: 0, to: sidebarSpaces.count, by: 2) {
            guard idx + 1 < sidebarSpaces.count,
                  sidebarSpaces[idx] as? String == spaceId,
                  let found = sidebarSpaces[idx + 1] as? [String: Any]
            else { continue }
            spaceData = found
            break
        }
        let containerIds = spaceData["containerIDs"] as? [String] ?? []
        guard let markerIndex = containerIds.firstIndex(of: marker),
              markerIndex + 1 < containerIds.count
        else {
            return newContainerDisplayOrder(for: marker, spaceData: spaceData, itemLookup: itemLookup)
        }
        let containerId = containerIds[markerIndex + 1]
        return itemLookup[containerId]?["childrenIds"] as? [String] ?? []
    }

    /// Newer Arc builds write `newContainerIDs`, where the section marker is an
    /// object key (`{"pinned": {}}`) rather than the bare string used by
    /// `containerIDs`.
    private func newContainerDisplayOrder(
        for marker: String,
        spaceData: [String: Any],
        itemLookup: [String: [String: Any]]
    ) -> [String] {
        let entries = spaceData["newContainerIDs"] as? [Any] ?? []
        for idx in stride(from: 0, to: entries.count, by: 2) {
            guard idx + 1 < entries.count,
                  let markerObject = entries[idx] as? [String: Any],
                  markerObject[marker] != nil,
                  let containerId = entries[idx + 1] as? String
            else { continue }
            return itemLookup[containerId]?["childrenIds"] as? [String] ?? []
        }
        return []
    }


    /// Expands split views in place. A split view is a layout node whose
    /// children are ordinary tabs; Sumi has no sidebar equivalent, so its tabs
    /// are surfaced individually rather than dropped along with the container.
    private func flattenedTabIds(
        _ itemIds: [String],
        itemLookup: [String: [String: Any]],
        visited: Set<String> = []
    ) -> [String] {
        var output: [String] = []
        for itemId in itemIds {
            guard visited.contains(itemId) == false else { continue }
            if (itemLookup[itemId]?["data"] as? [String: Any])?["splitView"] != nil {
                output.append(
                    contentsOf: flattenedTabIds(
                        itemLookup[itemId]?["childrenIds"] as? [String] ?? [],
                        itemLookup: itemLookup,
                        visited: visited.union([itemId])
                    )
                )
            } else {
                output.append(itemId)
            }
        }
        return output
    }

    private func alternatingDictionary(_ items: [Any]) -> [String: [String: Any]] {
        var output: [String: [String: Any]] = [:]
        for idx in stride(from: 0, to: items.count, by: 2) {
            guard idx + 1 < items.count,
                  let id = items[idx] as? String,
                  let value = items[idx + 1] as? [String: Any]
            else { continue }
            output[id] = value
        }
        return output
    }

    /// Arc stores extendedSRGB components, which can fall outside 0...1 for
    /// wide-gamut colours; `SumiPortableRGBColor` clamps them into range.
    private func rgbColor(fromArcComponents components: [String: Any]) -> SumiPortableRGBColor? {
        guard let r = components["red"] as? Double,
              let g = components["green"] as? Double,
              let b = components["blue"] as? Double
        else { return nil }
        return SumiPortableRGBColor(r: r, g: g, b: b)
    }
}

struct ArcSpaceInfo {
    var name: String?
    var icon: String?
    var profile: String?
    var colors: [SumiPortableRGBColor] = []
}
