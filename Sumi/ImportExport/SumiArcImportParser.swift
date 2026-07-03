import Foundation

struct SumiArcImportResult {
    var data: SumiPortableData
    var warnings: [String]
}

struct SumiArcImportParser {
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

        let spacesInfo = parseSpacesInfo(root)
        guard spacesInfo.isEmpty == false else {
            throw SumiImportExportError.importFailed("Arc spaces were not found in StorableSidebar.json.")
        }
        let local = localSidebar(root)
        let itemLookup = alternatingDictionary(local["items"] as? [Any] ?? [])
        let sidebarSpaces = local["spaces"] as? [Any] ?? []

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
            let info = spacesInfo[spaceId] ?? ArcSpaceInfo(name: "Space \(spaceId)", icon: nil, profile: "Default", color: nil)
            let profileName = SumiImportTextNormalization.nilIfBlank(info.profile) ?? "Default"
            let profileId = "arc-profile-\(profileName)"
            if profileRecordsByName[profileName] == nil {
                profileRecordsByName[profileName] = SumiPortableProfile(
                    id: profileId,
                    name: profileName,
                    icon: SumiProfileIcon.defaultIcon,
                    index: profileRecordsByName.count
                )
            }
            spaceProfileName[spaceId] = profileName
            portableSpaces.append(
                SumiPortableSpace(
                    id: spaceId,
                    name: info.name,
                    icon: info.icon ?? "🌐",
                    index: portableSpaces.count,
                    profileId: profileId,
                    themeDataBase64: nil,
                    color: info.color
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
            for tabId in unpinnedOrder {
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

        let essentials = parseEssentials(
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
            essentials: essentials,
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

    private func parseSpacesInfo(_ root: [String: Any]) -> [String: ArcSpaceInfo] {
        let spaceModels = (((root["firebaseSyncState"] as? [String: Any])?["syncData"] as? [String: Any])?["spaceModels"] as? [Any]) ?? []
        var output: [String: ArcSpaceInfo] = [:]
        for idx in stride(from: 0, to: spaceModels.count, by: 2) {
            guard idx + 1 < spaceModels.count,
                  let id = spaceModels[idx] as? String,
                  let wrapped = spaceModels[idx + 1] as? [String: Any],
                  let value = wrapped["value"] as? [String: Any]
            else { continue }
            let customInfo = value["customInfo"] as? [String: Any] ?? [:]
            let icon = ((customInfo["iconType"] as? [String: Any])?["emoji_v2"] as? String)
            let profile = (((value["profile"] as? [String: Any])?["custom"] as? [String: Any])?["_0"] as? [String: Any])?["directoryBasename"] as? String
            let color = (((customInfo["windowTheme"] as? [String: Any])?["primaryColorPalette"] as? [String: Any])?["midTone"] as? [String: Any])
                .flatMap(rgbColor(fromArcMidTone:))
            output[id] = ArcSpaceInfo(
                name: value["title"] as? String ?? "Space \(id)",
                icon: icon,
                profile: profile ?? "Default",
                color: color
            )
        }
        return output
    }

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
        for itemId in itemIds {
            guard let item = itemLookup[itemId],
                  let data = item["data"] as? [String: Any]
            else { continue }
            if let tab = data["tab"] as? [String: Any],
               let url = tab["savedURL"] as? String,
               url.isEmpty == false {
                pinned.append(
                    SumiPortableLauncher(
                        id: itemId,
                        title: (item["title"] as? String) ?? (tab["savedTitle"] as? String) ?? url,
                        urlString: url,
                        index: nextIndex,
                        profileId: nil,
                        executionProfileId: profileId,
                        spaceId: spaceId,
                        folderId: SumiImportTextNormalization.nilIfBlank(item["parentID"] as? String) ?? parentFolderId,
                        iconAsset: nil,
                        sourceSpaceId: spaceId
                    )
                )
                nextIndex += 1
            } else if data["list"] != nil {
                let title = item["title"] as? String ?? "Untitled Folder"
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

    private func parseEssentials(
        itemLookup: [String: [String: Any]],
        spaceProfileName: [String: String],
        profileRecordsByName: [String: SumiPortableProfile]
    ) -> [SumiPortableLauncher] {
        var output: [SumiPortableLauncher] = []
        let profileToSpace = Dictionary(
            spaceProfileName.map { ($0.value, $0.key) },
            uniquingKeysWith: { first, _ in first }
        )
        for (_, item) in itemLookup {
            guard let containerType = (((item["data"] as? [String: Any])?["itemContainer"] as? [String: Any])?["containerType"] as? [String: Any]),
                  let topApps = (containerType["topApps"] as? [String: Any])?["_0"] as? [String: Any]
            else { continue }
            let profileName = ((((topApps["custom"] as? [String: Any])?["_0"] as? [String: Any])?["directoryBasename"] as? String)
                ?? ((topApps["default"] as? [String: Any]) == nil ? nil : "Default")
                ?? "Default")
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

    private func parseArcBookmarks(warnings: inout [String]) -> [SumiPortableBookmarkNode] {
        let userData = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Arc/User Data", isDirectory: true)
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
        var containerIds: [String] = []
        for idx in stride(from: 0, to: sidebarSpaces.count, by: 2) {
            guard idx + 1 < sidebarSpaces.count,
                  sidebarSpaces[idx] as? String == spaceId,
                  let spaceData = sidebarSpaces[idx + 1] as? [String: Any]
            else { continue }
            containerIds = spaceData["containerIDs"] as? [String] ?? []
            break
        }
        guard let markerIndex = containerIds.firstIndex(of: marker),
              markerIndex + 1 < containerIds.count
        else {
            return []
        }
        let containerId = containerIds[markerIndex + 1]
        return itemLookup[containerId]?["childrenIds"] as? [String] ?? []
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

    private func rgbColor(fromArcMidTone midTone: [String: Any]) -> SumiPortableRGBColor? {
        guard let r = midTone["red"] as? Double,
              let g = midTone["green"] as? Double,
              let b = midTone["blue"] as? Double
        else { return nil }
        return SumiPortableRGBColor(r: r, g: g, b: b)
    }
}

private struct ArcSpaceInfo {
    var name: String
    var icon: String?
    var profile: String?
    var color: SumiPortableRGBColor?
}
