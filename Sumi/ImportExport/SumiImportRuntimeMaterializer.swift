import AppKit
import Foundation
import SumiDomain

enum SumiImportMaterializationError: LocalizedError {
    case invalidIdentifier(String)
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier(let value):
            return "The import plan contains an invalid identifier: \(value)."
        case .invalidURL(let value):
            return "The import plan contains an invalid URL: \(value)."
        }
    }
}

@MainActor
final class SumiImportRuntimeMaterializer: SumiImportRuntimeMaterializing {
    private let tabFactory: TabFactory
    private let tabBrowserRuntime: TabBrowserRuntime

    init(tabFactory: TabFactory, tabBrowserRuntime: TabBrowserRuntime) {
        self.tabFactory = tabFactory
        self.tabBrowserRuntime = tabBrowserRuntime
    }

    func materialize(
        _ plan: SumiImportPlan,
        preserving checkpoint: SumiImportRuntimeState
    ) throws -> SumiImportRuntimeState {
        let data = plan.targetRuntimeData
        let baseline = plan.baseline
        let profilesChanged = data.profiles != baseline.profiles
        let spacesChanged = data.spaces != baseline.spaces
        let foldersChanged = data.folders != baseline.folders
        let tabsChanged = data.regularTabs != baseline.regularTabs
        let essentialsChanged = data.essentials != baseline.essentials
        let spacePinsChanged = data.pinnedLaunchers != baseline.pinnedLaunchers
        let profileIdentitiesChanged = data.profiles.map(\.id) != baseline.profiles.map(\.id)
        let structuralIdentitiesChanged = data.spaces.map(\.id) != baseline.spaces.map(\.id)
            || data.regularTabs.map { "\($0.id)|\($0.spaceId)" }
                != baseline.regularTabs.map { "\($0.id)|\($0.spaceId)" }

        let profiles = try profilesChanged
            ? makeProfiles(data.profiles, checkpoint: checkpoint)
            : checkpoint.profiles
        let currentProfile = profilesChanged
            ? checkpoint.currentProfile.flatMap { current in
                profiles.first { $0.id == current.id }
            } ?? profiles.first
            : checkpoint.currentProfile
        let validProfileIds = Set(profiles.map(\.id))

        let spaces = try spacesChanged
            ? makeSpaces(
                data.spaces,
                profiles: profiles,
                validProfileIds: validProfileIds,
                checkpoint: checkpoint
            )
            : checkpoint.spaces

        let foldersBySpace = try foldersChanged
            ? makeFolders(data.folders, spaces: spaces, checkpoint: checkpoint)
            : checkpoint.foldersBySpace
        let folderSpaceById = Dictionary(
            foldersBySpace.flatMap { spaceId, folders in folders.map { ($0.id, spaceId) } },
            uniquingKeysWith: { first, _ in first }
        )
        let tabsBySpace = try tabsChanged
            ? makeTabs(
                data.regularTabs,
                spaces: spaces,
                folderSpaceById: folderSpaceById,
                checkpoint: checkpoint
            )
            : checkpoint.tabsBySpace
        let pinnedByProfile = try essentialsChanged
            ? makeEssentials(data.essentials, profiles: profiles, checkpoint: checkpoint)
            : checkpoint.pinnedByProfile
        let spacePinnedShortcuts = try spacePinsChanged
            ? makeSpacePins(
                data.pinnedLaunchers,
                spaces: spaces,
                folderSpaceById: folderSpaceById,
                checkpoint: checkpoint
            )
            : checkpoint.spacePinnedShortcuts

        let currentSpace = spacesChanged
            ? checkpoint.currentSpace.flatMap { current in
                spaces.first { $0.id == current.id }
            } ?? spaces.first
            : checkpoint.currentSpace
        let currentTab = tabsChanged
            ? checkpoint.currentTab.flatMap { selected in
                tabsBySpace.values.lazy.joined().first { $0.id == selected.id }
            } ?? currentSpace.flatMap { tabsBySpace[$0.id]?.first }
            : checkpoint.currentTab
        let replacesStructuralIdentity = plan.mode == .replace && structuralIdentitiesChanged
        let replacesProfileIdentity = plan.mode == .replace && profileIdentitiesChanged

        return SumiImportRuntimeState(
            profiles: profiles,
            currentProfile: currentProfile,
            spaces: spaces,
            tabsBySpace: tabsBySpace,
            foldersBySpace: foldersBySpace,
            pinnedByProfile: pinnedByProfile,
            spacePinnedShortcuts: spacePinnedShortcuts,
            pendingPinnedWithoutProfile: replacesProfileIdentity
                ? []
                : checkpoint.pendingPinnedWithoutProfile,
            splitGroups: replacesStructuralIdentity ? [] : checkpoint.splitGroups,
            currentSpace: currentSpace,
            currentTab: currentTab
        )
    }

    private func makeProfiles(
        _ records: [SumiPortableProfile],
        checkpoint: SumiImportRuntimeState
    ) throws -> [Profile] {
        let existingById = Dictionary(
            uniqueKeysWithValues: checkpoint.profiles.map { ($0.id, $0) }
        )
        return try records.sorted { $0.index < $1.index }.map { record in
            let id = try requiredUUID(record.id)
            if let existing = existingById[id],
               existing.name == record.name,
               existing.icon == record.icon {
                return existing
            }
            return Profile(id: id, name: record.name, icon: record.icon)
        }
    }

    private func makeSpaces(
        _ records: [SumiPortableSpace],
        profiles: [Profile],
        validProfileIds: Set<UUID>,
        checkpoint: SumiImportRuntimeState
    ) throws -> [Space] {
        let existingById = Dictionary(
            uniqueKeysWithValues: checkpoint.spaces.map { ($0.id, $0) }
        )
        return try records.sorted { $0.index < $1.index }.map { record in
            let id = try requiredUUID(record.id)
            let requestedProfileId = try record.profileId.map(requiredUUID(_:))
            let profileId = requestedProfileId.flatMap {
                validProfileIds.contains($0) ? $0 : nil
            } ?? profiles.first?.id
            let theme = SumiImportedThemeDecoder.theme(from: record)
            if let existing = existingById[id],
               existing.name == record.name,
               existing.icon == SumiPersistentGlyph.normalizedSpaceIconValue(record.icon),
               existing.profileId == profileId,
               existing.workspaceTheme == theme {
                return existing
            }
            return Space(
                id: id,
                name: record.name,
                icon: record.icon,
                workspaceTheme: theme,
                profileId: profileId
            )
        }
    }

    private func makeFolders(
        _ records: [SumiPortableFolder],
        spaces: [Space],
        checkpoint: SumiImportRuntimeState
    ) throws -> [UUID: [TabFolder]] {
        let recordsBySpace = Dictionary(
            grouping: SumiPortableFolderHierarchyRepair.repaired(records),
            by: \.spaceId
        )
        let existingById = Dictionary(
            checkpoint.foldersBySpace.values.joined().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return try Dictionary(uniqueKeysWithValues: spaces.map { space in
            let folders = try (recordsBySpace[space.id.uuidString] ?? [])
                .sorted { $0.index < $1.index }
                .map { record in
                    let id = try requiredUUID(record.id)
                    let parentId = try record.parentFolderId.map(requiredUUID(_:))
                    let color = NSColor(hex: record.colorHex) ?? .controlAccentColor
                    if let existing = existingById[id],
                       existing.name == record.name,
                       existing.spaceId == space.id,
                       existing.parentFolderId == parentId,
                       existing.icon == SumiZenFolderIconCatalog.normalizedFolderIconValue(record.icon),
                       existing.color.toHexString() == color.toHexString(),
                       existing.index == record.index,
                       existing.isOpen == record.isOpen {
                        return existing
                    }
                    let folder = TabFolder(
                        id: id,
                        name: record.name,
                        spaceId: space.id,
                        parentFolderId: parentId,
                        icon: record.icon,
                        color: color,
                        index: record.index
                    )
                    folder.isOpen = record.isOpen
                    return folder
                }
            return (space.id, folders)
        })
    }

    private func makeTabs(
        _ records: [SumiPortableRegularTab],
        spaces: [Space],
        folderSpaceById: [UUID: UUID],
        checkpoint: SumiImportRuntimeState
    ) throws -> [UUID: [Tab]] {
        let recordsBySpace = Dictionary(grouping: records, by: \.spaceId)
        let existingById = Dictionary(
            checkpoint.tabsBySpace.values.joined().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return try Dictionary(uniqueKeysWithValues: spaces.map { space in
            let tabs = try (recordsBySpace[space.id.uuidString] ?? [])
                .sorted { $0.index < $1.index }
                .map { record in
                    let url = try requiredURL(record.urlString)
                    let id = try requiredUUID(record.id)
                    let profileId = try record.profileId.map(requiredUUID(_:))
                    let folderId = try record.folderId.map(requiredUUID(_:)).flatMap {
                        folderSpaceById[$0] == space.id ? $0 : nil
                    }
                    let title = record.title.isEmpty ? url.absoluteString : record.title
                    if let existing = existingById[id],
                       existing.url == url,
                       existing.name == title,
                       existing.spaceId == space.id,
                       existing.index == record.index,
                       existing.profileId == profileId,
                       existing.folderId == folderId {
                        return existing
                    }
                    let tab = tabFactory.makeTab(
                        id: id,
                        url: url,
                        name: title,
                        favicon: "globe",
                        spaceId: space.id,
                        index: record.index,
                        loadsCachedFaviconOnInit: false
                    )
                    tab.profileId = profileId
                    tab.folderId = folderId
                    tab.attachBrowserRuntime(tabBrowserRuntime)
                    return tab
                }
            return (space.id, tabs)
        })
    }

    private func makeEssentials(
        _ records: [SumiPortableLauncher],
        profiles: [Profile],
        checkpoint: SumiImportRuntimeState
    ) throws -> [UUID: [ShortcutPin]] {
        let recordsByProfile = Dictionary(grouping: records, by: { $0.profileId ?? "" })
        let existingById = Dictionary(
            checkpoint.pinnedByProfile.values.joined().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return try Dictionary(uniqueKeysWithValues: profiles.map { profile in
            let pins = try (recordsByProfile[profile.id.uuidString] ?? [])
                .sorted { $0.index < $1.index }
                .map { record in
                    let id = try requiredUUID(record.id)
                    let executionProfileId = try record.executionProfileId
                        .map(requiredUUID(_:)) ?? profile.id
                    let url = try requiredURL(record.urlString)
                    let title = record.title.isEmpty ? record.urlString : record.title
                    if let existing = existingById[id],
                       pinMatches(
                           existing,
                           role: .essential,
                           profileId: profile.id,
                           executionProfileId: executionProfileId,
                           spaceId: nil,
                           index: record.index,
                           folderId: nil,
                           url: url,
                           title: title,
                           iconAsset: record.iconAsset
                       ) {
                        return existing
                    }
                    return ShortcutPin(
                        id: id,
                        role: .essential,
                        profileId: profile.id,
                        executionProfileId: executionProfileId,
                        index: record.index,
                        launchURL: url,
                        title: title,
                        iconAsset: record.iconAsset
                    )
                }
            return (profile.id, pins)
        })
    }

    private func makeSpacePins(
        _ records: [SumiPortableLauncher],
        spaces: [Space],
        folderSpaceById: [UUID: UUID],
        checkpoint: SumiImportRuntimeState
    ) throws -> [UUID: [ShortcutPin]] {
        let recordsBySpace = Dictionary(grouping: records, by: { $0.spaceId ?? "" })
        let existingById = Dictionary(
            checkpoint.spacePinnedShortcuts.values.joined().map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return try Dictionary(uniqueKeysWithValues: spaces.map { space in
            let pins = try (recordsBySpace[space.id.uuidString] ?? [])
                .sorted { $0.index < $1.index }
                .map { record in
                    let folderId = try record.folderId.map(requiredUUID(_:)).flatMap {
                        folderSpaceById[$0] == space.id ? $0 : nil
                    }
                    let url = try requiredURL(record.urlString)
                    let id = try requiredUUID(record.id)
                    let executionProfileId = try record.executionProfileId.map(requiredUUID(_:))
                        ?? space.profileId
                    let title = record.title.isEmpty ? url.absoluteString : record.title
                    if let existing = existingById[id],
                       pinMatches(
                           existing,
                           role: .spacePinned,
                           profileId: nil,
                           executionProfileId: executionProfileId,
                           spaceId: space.id,
                           index: record.index,
                           folderId: folderId,
                           url: url,
                           title: title,
                           iconAsset: record.iconAsset
                       ) {
                        return existing
                    }
                    return ShortcutPin(
                        id: id,
                        role: .spacePinned,
                        executionProfileId: executionProfileId,
                        spaceId: space.id,
                        index: record.index,
                        folderId: folderId,
                        launchURL: url,
                        title: title,
                        iconAsset: record.iconAsset
                    )
                }
            return (space.id, pins)
        })
    }

    private func pinMatches(
        _ pin: ShortcutPin,
        role: ShortcutPinRole,
        profileId: UUID?,
        executionProfileId: UUID?,
        spaceId: UUID?,
        index: Int,
        folderId: UUID?,
        url: URL,
        title: String,
        iconAsset: String?
    ) -> Bool {
        pin.role == role
            && pin.profileId == profileId
            && pin.executionProfileId == executionProfileId
            && pin.spaceId == spaceId
            && pin.index == index
            && pin.folderId == folderId
            && pin.launchURL == url
            && pin.title == title
            && pin.iconAsset == normalizedLauncherIconAsset(iconAsset)
    }

    private func normalizedLauncherIconAsset(_ iconAsset: String?) -> String? {
        guard let iconAsset else { return nil }
        let normalized = SumiPersistentGlyph.normalizedLauncherIconValue(iconAsset)
        return normalized == SumiPersistentGlyph.launcherSystemImageFallback ? nil : normalized
    }

    private func requiredUUID(_ value: String) throws -> UUID {
        guard let value = UUID(uuidString: value) else {
            throw SumiImportMaterializationError.invalidIdentifier(value)
        }
        return value
    }

    private func requiredURL(_ value: String) throws -> URL {
        guard let url = URL(string: value) else {
            throw SumiImportMaterializationError.invalidURL(value)
        }
        return url
    }
}

private enum SumiImportedThemeDecoder {
    static func theme(from record: SumiPortableSpace) -> WorkspaceTheme {
        if let encoded = record.themeDataBase64.flatMap({ Data(base64Encoded: $0) }),
           let theme = WorkspaceTheme.decode(encoded) {
            return theme
        }

        let stops = record.colors ?? record.color.map { [$0] } ?? []
        guard !stops.isEmpty else { return .default }
        let limited = Array(stops.prefix(WorkspaceResolvedGradient.maxStops))
        let positions = positions(stopCount: limited.count)
        let opacity = record.themeOpacity.map {
            max($0, WorkspaceGradientTheme.customChromeThemeDisableThreshold)
        } ?? 0.62
        return WorkspaceTheme(
            gradientTheme: WorkspaceGradientTheme(
                colors: limited.enumerated().map { index, stop in
                    WorkspaceThemeColor(
                        hex: stop.hex,
                        isCustom: false,
                        isPrimary: index == 0,
                        algorithm: limited.count > 1 ? .analogous : .floating,
                        position: positions[index]
                    )
                },
                opacity: opacity,
                texture: 1.0 / 16.0
            ),
            usesExplicitColorScheme: true
        )
    }

    private static func positions(stopCount: Int) -> [WorkspaceThemePosition] {
        switch stopCount {
        case ...1: return [.monochrome]
        case 2: return [.topLeft, .bottom]
        default: return [.topLeft, .bottom, .monochrome]
        }
    }
}
