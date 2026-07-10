import AppKit
import Foundation

@MainActor
struct TabRestoreRuntimeState {
    let spaces: [Space]
    let tabsBySpace: [UUID: [Tab]]
    let foldersBySpace: [UUID: [TabFolder]]
    let pinnedByProfile: [UUID: [ShortcutPin]]
    let pendingPinnedWithoutProfile: [ShortcutPin]
    let spacePinnedShortcuts: [UUID: [ShortcutPin]]
    let repairReasons: [String]
}

@MainActor
struct TabRestoreRuntimeStateBuilder {
    let tabFactory: TabFactory

    func makeState(from payload: TabRestorePayload) -> TabRestoreRuntimeState {
        var repairReasons = payload.repairReasons
        let restoredSpaces = payload.spaces.map { dto in
            let space = Space(
                id: dto.id,
                name: dto.name,
                icon: dto.icon,
                workspaceTheme: dto.workspaceTheme,
                profileId: dto.profileId
            )
            if space.icon != dto.icon {
                repairReasons.append("normalized space icon")
            }
            return space
        }

        var restoredTabsBySpace: [UUID: [Tab]] = [:]
        for space in restoredSpaces {
            restoredTabsBySpace[space.id] = []
        }
        for (spaceId, tabDTOs) in payload.regularTabsBySpace {
            restoredTabsBySpace[spaceId] = tabDTOs.map(makeRestoredTab)
        }

        var restoredFoldersBySpace: [UUID: [TabFolder]] = [:]
        for (spaceId, folderDTOs) in payload.foldersBySpace {
            restoredFoldersBySpace[spaceId] = folderDTOs.map { dto in
                let folder = TabFolder(
                    id: dto.id,
                    name: dto.name,
                    spaceId: dto.spaceId,
                    parentFolderId: dto.parentFolderId,
                    icon: dto.icon,
                    color: NSColor(hex: dto.color) ?? .controlAccentColor,
                    index: dto.index
                )
                folder.isOpen = dto.isOpen
                if folder.icon != dto.icon {
                    repairReasons.append("normalized folder icon")
                }
                return folder
            }
        }

        var restoredPinnedByProfile: [UUID: [ShortcutPin]] = [:]
        for (profileId, shortcutDTOs) in payload.pinnedShortcutsByProfile {
            restoredPinnedByProfile[profileId] = shortcutDTOs.map { dto in
                let pin = makeRestoredShortcut(dto)
                if pin.iconAsset != dto.iconAsset {
                    repairReasons.append("normalized launcher icon")
                }
                return pin
            }
        }

        let restoredPendingPinned = payload.pendingPinnedShortcuts.map { dto in
            let pin = makeRestoredShortcut(dto)
            if pin.iconAsset != dto.iconAsset {
                repairReasons.append("normalized launcher icon")
            }
            return pin
        }

        var restoredSpacePinnedShortcuts: [UUID: [ShortcutPin]] = [:]
        for (spaceId, shortcutDTOs) in payload.spacePinnedShortcutsBySpace {
            restoredSpacePinnedShortcuts[spaceId] = shortcutDTOs.map { dto in
                let pin = makeRestoredShortcut(dto)
                if pin.iconAsset != dto.iconAsset {
                    repairReasons.append("normalized launcher icon")
                }
                return pin
            }
        }

        return TabRestoreRuntimeState(
            spaces: restoredSpaces,
            tabsBySpace: restoredTabsBySpace,
            foldersBySpace: restoredFoldersBySpace,
            pinnedByProfile: restoredPinnedByProfile,
            pendingPinnedWithoutProfile: restoredPendingPinned,
            spacePinnedShortcuts: restoredSpacePinnedShortcuts,
            repairReasons: repairReasons
        )
    }

    private func makeRestoredTab(_ dto: TabRestoreTabDTO) -> Tab {
        let tab = tabFactory.makeTab(
            id: dto.id,
            url: dto.url,
            name: dto.name,
            favicon: "globe",
            spaceId: dto.spaceId,
            index: dto.index,
            loadsCachedFaviconOnInit: false
        )
        tab.folderId = dto.folderId
        tab.profileId = dto.profileId
        tab.isPinned = false
        tab.isSpacePinned = false
        tab.canGoBack = dto.canGoBack
        tab.canGoForward = dto.canGoForward
        return tab
    }

    private func makeRestoredShortcut(_ dto: TabRestoreShortcutDTO) -> ShortcutPin {
        ShortcutPin(
            id: dto.id,
            role: dto.role,
            profileId: dto.profileId,
            executionProfileId: dto.executionProfileId,
            spaceId: dto.spaceId,
            index: dto.index,
            folderId: dto.folderId,
            launchURL: dto.launchURL,
            title: dto.title,
            iconAsset: dto.iconAsset
        )
    }
}
