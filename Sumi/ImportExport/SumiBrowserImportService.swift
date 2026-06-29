import Compression
import Foundation

@MainActor
final class SumiBrowserImportService {
    private let transferService: SumiTransferExportService
    private let backupService: SumiBackupService

    init(
        transferService: SumiTransferExportService = SumiTransferExportService(),
        backupService: SumiBackupService = SumiBackupService()
    ) {
        self.transferService = transferService
        self.backupService = backupService
    }

    func previewArcImport() throws -> SumiImportPreview {
        let sidebarURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Arc/StorableSidebar.json")
        let result = try SumiArcImportParser().parseWithDiagnostics(sidebarURL: sidebarURL)
        return SumiImportPreview(
            title: "Arc",
            sourceKind: .arc,
            data: result.data,
            suggestedCategories: result.data.nonEmptyCategories,
            warnings: warnings(for: result.data, source: "Arc") + result.warnings,
            defaultMode: .merge
        )
    }

    func detectedZenProfiles() -> [URL] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/zen/Profiles", isDirectory: true)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return children.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && FileManager.default.fileExists(atPath: url.appendingPathComponent("places.sqlite").path)
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func previewZenImport(profileURL: URL) throws -> SumiImportPreview {
        let result = try SumiZenImportParser().parseWithDiagnostics(profileURL: profileURL)
        return SumiImportPreview(
            title: "Zen: \(profileURL.lastPathComponent)",
            sourceKind: .zen,
            data: result.data,
            suggestedCategories: result.data.nonEmptyCategories,
            warnings: warnings(for: result.data, source: "Zen") + result.warnings,
            defaultMode: .merge
        )
    }

    func previewFileImport(fileURL: URL) throws -> SumiImportPreview {
        let raw = try Data(contentsOf: fileURL)
        if let archive = try? backupService.readBackup(from: fileURL) {
            return SumiImportPreview(
                title: fileURL.lastPathComponent,
                sourceKind: .sumiBackup,
                data: archive.data,
                suggestedCategories: Set(archive.includedCategories),
                warnings: archive.warnings,
                defaultMode: .replace
            )
        }

        let data = try transferService.importBrowser2ZenDocument(from: raw)
        return SumiImportPreview(
            title: fileURL.lastPathComponent,
            sourceKind: .browser2zen,
            data: data,
            suggestedCategories: data.nonEmptyCategories,
            warnings: warnings(for: data, source: "Browser Export"),
            defaultMode: .merge
        )
    }

    private func warnings(for data: SumiPortableData, source: String) -> [String] {
        var warnings: [String] = []
        let overflow = Dictionary(grouping: data.essentials, by: { $0.profileId ?? "" })
            .values
            .reduce(0) { $0 + max(0, $1.count - SumiImportApplier.maxEssentialsPerProfile) }
        if overflow > 0 {
            warnings.append("\(overflow) \(source) essentials exceed Sumi's 12-item profile limit and will become space-pinned launchers.")
        }
        return warnings
    }
}

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
            let profileName = info.profile?.nilIfBlank ?? "Default"
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
                        folderId: (item["parentID"] as? String)?.nilIfBlank ?? parentFolderId,
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

struct SumiZenImportResult {
    var data: SumiPortableData
    var warnings: [String]
}

struct SumiZenImportParser {
    func parse(profileURL: URL) throws -> SumiPortableData {
        var warnings: [String] = []
        return try parse(profileURL: profileURL, warnings: &warnings)
    }

    func parseWithDiagnostics(profileURL: URL) throws -> SumiZenImportResult {
        var warnings: [String] = []
        let data = try parse(profileURL: profileURL, warnings: &warnings)
        return SumiZenImportResult(data: data, warnings: warnings)
    }

    private func parse(profileURL: URL, warnings: inout [String]) throws -> SumiPortableData {
        let sessionsURL = profileURL.appendingPathComponent("zen-sessions.jsonlz4")
        guard FileManager.default.fileExists(atPath: sessionsURL.path) else {
            throw SumiImportExportError.unsupportedFile("This Zen profile does not contain zen-sessions.jsonlz4.")
        }
        let jsonData = try SumiMozLZ4.decode(Data(contentsOf: sessionsURL))
        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw SumiImportExportError.unsupportedFile("Zen sessions file did not decode to JSON.")
        }

        let containers = parseContainers(profileURL: profileURL, warnings: &warnings)
        let zenSpaces = root["spaces"] as? [[String: Any]] ?? []
        let zenFolders = root["folders"] as? [[String: Any]] ?? []
        let zenTabs = root["tabs"] as? [[String: Any]] ?? []

        let defaultProfile = SumiPortableProfile(
            id: "zen-container-0",
            name: "Default",
            icon: SumiProfileIcon.defaultIcon,
            index: 0
        )
        var profilesByContainer: [Int: SumiPortableProfile] = [0: defaultProfile]
        for container in containers.sorted(by: { $0.key < $1.key }) where container.key != 0 {
            profilesByContainer[container.key] = SumiPortableProfile(
                id: "zen-container-\(container.key)",
                name: container.value.nilIfBlank ?? "Container \(container.key)",
                icon: SumiProfileIcon.defaultIcon,
                index: profilesByContainer.count
            )
        }

        let tabsByWorkspace = Dictionary(grouping: zenTabs, by: { ($0["zenWorkspace"] as? String) ?? "" })
        var spaces: [SumiPortableSpace] = []
        var workspaceProfileId: [String: String] = [:]
        for (idx, space) in zenSpaces.enumerated() {
            let workspaceId = (space["uuid"] as? String) ?? UUID().uuidString
            let firstContainerId = tabsByWorkspace[workspaceId]?
                .compactMap { $0["userContextId"] as? Int }
                .first(where: { $0 != 0 }) ?? 0
            let profile = profilesByContainer[firstContainerId] ?? defaultProfile
            workspaceProfileId[workspaceId] = profile.id
            spaces.append(
                SumiPortableSpace(
                    id: workspaceId,
                    name: (space["name"] as? String)?.nilIfBlank ?? "Zen Space",
                    icon: space["icon"] as? String ?? "🌐",
                    index: idx,
                    profileId: profile.id,
                    themeDataBase64: nil,
                    color: zenColor(from: space)
                )
            )
        }

        let folderIds = Set(zenFolders.compactMap { $0["id"] as? String })
        var essentials: [SumiPortableLauncher] = []
        var pinned: [SumiPortableLauncher] = []
        var pinnedSiblingIndexes: [String: Int] = [:]
        var regularTabs: [SumiPortableRegularTab] = []

        for (idx, tab) in zenTabs.enumerated() {
            guard (tab["zenIsEmpty"] as? Bool) != true,
                  let entry = (tab["entries"] as? [[String: Any]])?.last,
                  let url = entry["url"] as? String,
                  url.isEmpty == false,
                  url != "about:blank"
            else { continue }
            let title = (entry["title"] as? String)?.nilIfBlank ?? url
            let workspaceId = (tab["zenWorkspace"] as? String) ?? spaces.first?.id ?? "zen-default-space"
            let profileId = workspaceProfileId[workspaceId] ?? profilesByContainer[0]?.id
            let syncId = (tab["zenSyncId"] as? String) ?? UUID().uuidString
            let isPinned = tab["pinned"] as? Bool ?? false
            let isEssential = tab["zenEssential"] as? Bool ?? false
            if isPinned && isEssential {
                essentials.append(
                    SumiPortableLauncher(
                        id: syncId,
                        title: title,
                        urlString: url,
                        index: idx,
                        profileId: profileId,
                        executionProfileId: profileId,
                        spaceId: nil,
                        folderId: nil,
                        iconAsset: nil,
                        sourceSpaceId: workspaceId
                    )
                )
            } else if isPinned {
                let folderId = (tab["groupId"] as? String).flatMap { folderIds.contains($0) ? $0 : nil }
                let launcher = SumiPortableLauncher(
                    id: syncId,
                    title: title,
                    urlString: url,
                    index: idx,
                    profileId: nil,
                    executionProfileId: profileId,
                    spaceId: workspaceId,
                    folderId: folderId,
                    iconAsset: nil,
                    sourceSpaceId: workspaceId
                )
                pinned.append(launcher)
                for siblingId in zenTabSiblingIdentifiers(from: tab, fallbackId: syncId) {
                    pinnedSiblingIndexes[siblingId] = idx
                }
            } else {
                regularTabs.append(
                    SumiPortableRegularTab(
                        id: syncId,
                        title: title,
                        urlString: url,
                        index: idx,
                        spaceId: workspaceId,
                        profileId: profileId,
                        folderId: nil
                    )
                )
            }
        }

        let bookmarkSource = SumiBookmarkImportSource(
            id: "zen-\(profileURL.lastPathComponent)",
            title: "Zen",
            fileURL: profileURL.appendingPathComponent("places.sqlite"),
            kind: .firefoxSQLite
        )
        let bookmarks: [SumiPortableBookmarkNode]
        if FileManager.default.fileExists(atPath: bookmarkSource.fileURL.path) {
            do {
                bookmarks = try SumiBookmarkPortableBridge.portableNodes(
                    from: bookmarkSource.readBookmarks()
                )
            } catch {
                warnings.append("Zen bookmarks were skipped because places.sqlite could not be imported: \(error.localizedDescription)")
                bookmarks = []
            }
        } else {
            bookmarks = []
        }
        let folderRecords = flattenZenFolders(zenFolders, pinnedSiblingIndexes: pinnedSiblingIndexes)

        return SumiPortableData(
            profiles: Array(profilesByContainer.values).sorted { $0.index < $1.index },
            spaces: spaces,
            folders: folderRecords,
            essentials: essentials,
            pinnedLaunchers: pinned,
            regularTabs: regularTabs,
            bookmarks: bookmarks
        )
    }

    private func parseContainers(profileURL: URL, warnings: inout [String]) -> [Int: String] {
        let url = profileURL.appendingPathComponent("containers.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            warnings.append("Zen containers were skipped because containers.json could not be read: \(error.localizedDescription)")
            return [:]
        }

        let identities: [[String: Any]]
        do {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let decodedIdentities = root["identities"] as? [[String: Any]]
            else {
                warnings.append("Zen containers were skipped because containers.json did not contain identities.")
                return [:]
            }
            identities = decodedIdentities
        } catch {
            warnings.append("Zen containers were skipped because containers.json could not be decoded: \(error.localizedDescription)")
            return [:]
        }

        var output: [Int: String] = [:]
        for identity in identities {
            if let id = identity["userContextId"] as? Int {
                output[id] = identity["name"] as? String ?? "Container \(id)"
            }
        }
        return output
    }

    func flattenZenFolders(
        _ folders: [[String: Any]],
        pinnedSiblingIndexes: [String: Int] = [:]
    ) -> [SumiPortableFolder] {
        var rawById: [String: [String: Any]] = [:]
        for folder in folders {
            if let id = folder["id"] as? String {
                rawById[id] = folder
            }
        }

        var pathCache: [String: [String]] = [:]
        func path(for id: String, visited: Set<String> = []) -> [String] {
            if let cached = pathCache[id] { return cached }
            guard let folder = rawById[id] else { return [] }
            guard visited.contains(id) == false else {
                return [folder["name"] as? String ?? "Untitled Folder"]
            }
            var nextVisited = visited
            nextVisited.insert(id)
            let parent = (folder["parentId"] as? String)
                .flatMap { rawById[$0] == nil ? nil : path(for: $0, visited: nextVisited) } ?? []
            let resolved = parent + [folder["name"] as? String ?? "Untitled Folder"]
            pathCache[id] = resolved
            return resolved
        }

        var previousSiblingInfoById: [String: (type: String, id: String?)] = [:]
        var records = folders.enumerated().compactMap { idx, folder -> SumiPortableFolder? in
            guard let id = folder["id"] as? String else { return nil }
            if let info = folder["prevSiblingInfo"] as? [String: Any],
               let type = info["type"] as? String {
                previousSiblingInfoById[id] = (type: type, id: (info["id"] as? String)?.nilIfBlank)
            }
            let folderPath = path(for: id)
            return SumiPortableFolder(
                id: id,
                name: folderPath.last ?? "Untitled Folder",
                icon: SumiZenFolderIconCatalog.normalizedFolderIconValue(folder["userIcon"] as? String),
                colorHex: "#000000",
                spaceId: folder["workspaceId"] as? String ?? "",
                parentFolderId: (folder["parentId"] as? String)?.nilIfBlank,
                isOpen: !(folder["collapsed"] as? Bool ?? false),
                index: idx,
                sourcePath: folderPath
            )
        }
        applyZenPreviousSiblingOrder(
            to: &records,
            previousSiblingInfoById: previousSiblingInfoById,
            pinnedSiblingIndexes: pinnedSiblingIndexes
        )
        return SumiPortableFolderHierarchyRepair.repaired(records)
    }

    private func applyZenPreviousSiblingOrder(
        to records: inout [SumiPortableFolder],
        previousSiblingInfoById: [String: (type: String, id: String?)],
        pinnedSiblingIndexes: [String: Int]
    ) {
        var folderIndexById = Dictionary(
            records.map { ($0.id, $0.index) },
            uniquingKeysWith: { first, _ in first }
        )
        let folderContainerById = Dictionary(
            records.map { ($0.id, "\($0.spaceId)|\($0.parentFolderId ?? "")") },
            uniquingKeysWith: { first, _ in first }
        )

        func previousIndex(for folder: SumiPortableFolder) -> Int? {
            guard let info = previousSiblingInfoById[folder.id] else { return nil }
            switch info.type {
            case "start":
                return -1
            case "group":
                guard let previousFolderId = info.id,
                      folderContainerById[previousFolderId] == folderContainerById[folder.id],
                      let index = folderIndexById[previousFolderId] else {
                    return nil
                }
                return index
            case "tab":
                guard let previousTabId = info.id,
                      let index = pinnedSiblingIndexes[previousTabId] else {
                    return nil
                }
                return index
            default:
                return nil
            }
        }

        for _ in 0..<max(records.count, 1) {
            var changed = false
            for idx in records.indices {
                guard let index = previousIndex(for: records[idx]).map({ $0 + 1 }),
                      records[idx].index != index else {
                    continue
                }
                records[idx].index = index
                folderIndexById[records[idx].id] = index
                changed = true
            }
            if changed == false { break }
        }
    }

    private func zenTabSiblingIdentifiers(from tab: [String: Any], fallbackId: String) -> [String] {
        var ids: [String] = [fallbackId]
        for key in ["id", "zenSyncId", "tabId"] {
            if let id = (tab[key] as? String)?.nilIfBlank {
                ids.append(id)
            }
        }
        if let attributes = tab["attributes"] as? [String: Any] {
            for key in ["id", "zenSyncId", "tabId"] {
                if let id = (attributes[key] as? String)?.nilIfBlank {
                    ids.append(id)
                }
            }
        }

        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
    }

    private func zenColor(from space: [String: Any]) -> SumiPortableRGBColor? {
        guard let theme = space["theme"] as? [String: Any],
              let colors = theme["gradientColors"] as? [[String: Any]],
              let first = colors.first,
              let components = first["c"] as? [Any],
              components.count >= 3
        else { return nil }
        func component(_ idx: Int) -> Double? {
            if let value = components[idx] as? Double { return value / 255 }
            if let value = components[idx] as? Int { return Double(value) / 255 }
            return nil
        }
        guard let r = component(0), let g = component(1), let b = component(2) else { return nil }
        return SumiPortableRGBColor(r: r, g: g, b: b)
    }
}

private enum SumiMozLZ4 {
    static func decode(_ data: Data) throws -> Data {
        let magic = Data([0x6D, 0x6F, 0x7A, 0x4C, 0x7A, 0x34, 0x30, 0x00])
        guard data.count >= 12, Data(data.prefix(8)) == magic else {
            throw SumiImportExportError.unsupportedFile("Zen sessions file is not Mozilla LZ4.")
        }
        let size = data[8..<12].enumerated().reduce(UInt32(0)) { partial, item in
            partial | (UInt32(item.element) << UInt32(item.offset * 8))
        }
        let compressed = data.dropFirst(12)
        var output = Data(count: Int(size))
        let decoded = output.withUnsafeMutableBytes { outPtr in
            compressed.withUnsafeBytes { inPtr in
                compression_decode_buffer(
                    outPtr.bindMemory(to: UInt8.self).baseAddress!,
                    Int(size),
                    inPtr.bindMemory(to: UInt8.self).baseAddress!,
                    compressed.count,
                    nil,
                    COMPRESSION_LZ4_RAW
                )
            }
        }
        guard decoded == Int(size) else {
            throw SumiImportExportError.unsupportedFile("Sumi could not decode Zen's LZ4 session data.")
        }
        return output
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum SumiPortableFolderHierarchyRepair {
    static func repaired(_ folders: [SumiPortableFolder]) -> [SumiPortableFolder] {
        let folderById = Dictionary(
            folders.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return folders.map { folder in
            var copy = folder
            guard let parentId = folder.parentFolderId else {
                return copy
            }
            guard parentId != folder.id,
                  let parent = folderById[parentId],
                  parent.spaceId == folder.spaceId,
                  createsCycle(folderId: folder.id, parentId: parentId, folderById: folderById) == false else {
                copy.parentFolderId = nil
                return copy
            }
            return copy
        }
    }

    private static func createsCycle(
        folderId: String,
        parentId: String,
        folderById: [String: SumiPortableFolder]
    ) -> Bool {
        var visited: Set<String> = [folderId]
        var cursor: String? = parentId
        while let current = cursor {
            guard visited.insert(current).inserted else { return true }
            cursor = folderById[current]?.parentFolderId
        }
        return false
    }
}
