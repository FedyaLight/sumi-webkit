import AppKit
import Foundation

@MainActor
enum SumiImportExportSnapshot {
    static func makeData(from browserManager: BrowserManager) -> SumiPortableData {
        let profileManager = browserManager.profileManager
        let tabManager = browserManager.tabManager

        let profiles = profileManager.profiles.enumerated().map { index, profile in
            SumiPortableProfile(
                id: profile.id.uuidString,
                name: profile.name,
                icon: profile.icon,
                index: index
            )
        }

        let spaces = tabManager.spaces.enumerated().map { index, space in
            SumiPortableSpace(
                id: space.id.uuidString,
                name: space.name,
                icon: space.icon,
                index: index,
                profileId: space.profileId?.uuidString,
                themeDataBase64: space.workspaceTheme.encoded?.base64EncodedString(),
                color: nil
            )
        }

        let folders = tabManager.spaces.flatMap { space -> [SumiPortableFolder] in
            (tabManager.foldersBySpace[space.id] ?? [])
                .sorted { $0.index < $1.index }
                .map { folder in
                    SumiPortableFolder(
                        id: folder.id.uuidString,
                        name: folder.name,
                        icon: folder.icon,
                        colorHex: folder.color.toHexString() ?? "#000000",
                        spaceId: space.id.uuidString,
                        parentFolderId: folder.parentFolderId?.uuidString,
                        isOpen: folder.isOpen,
                        index: folder.index,
                        sourcePath: [folder.name]
                    )
                }
        }

        let essentials = tabManager.pinnedByProfile
            .sorted { $0.key.uuidString < $1.key.uuidString }
            .flatMap { profileId, pins -> [SumiPortableLauncher] in
                pins.sorted { $0.index < $1.index }.map { pin in
                    SumiPortableLauncher(
                        id: pin.id.uuidString,
                        title: pin.title,
                        urlString: pin.launchURL.absoluteString,
                        index: pin.index,
                        profileId: profileId.uuidString,
                        executionProfileId: pin.executionProfileId?.uuidString,
                        spaceId: nil,
                        folderId: nil,
                        iconAsset: pin.iconAsset,
                        sourceSpaceId: nil
                    )
                }
            }

        let pinnedLaunchers = tabManager.spaces.flatMap { space -> [SumiPortableLauncher] in
            (tabManager.spacePinnedShortcuts[space.id] ?? [])
                .sorted { $0.index < $1.index }
                .map { pin in
                    SumiPortableLauncher(
                        id: pin.id.uuidString,
                        title: pin.title,
                        urlString: pin.launchURL.absoluteString,
                        index: pin.index,
                        profileId: pin.profileId?.uuidString,
                        executionProfileId: pin.executionProfileId?.uuidString,
                        spaceId: space.id.uuidString,
                        folderId: pin.folderId?.uuidString,
                        iconAsset: pin.iconAsset,
                        sourceSpaceId: space.id.uuidString
                    )
                }
        }

        let regularTabs = tabManager.spaces.flatMap { space -> [SumiPortableRegularTab] in
            (tabManager.tabsBySpace[space.id] ?? [])
                .sorted { $0.index < $1.index }
                .map { tab in
                    SumiPortableRegularTab(
                        id: tab.id.uuidString,
                        title: tab.name,
                        urlString: tab.url.absoluteString,
                        index: tab.index,
                        spaceId: space.id.uuidString,
                        profileId: tab.profileId?.uuidString,
                        folderId: tab.folderId?.uuidString
                    )
                }
        }

        let bookmarks = portableBookmarks(from: browserManager.bookmarkManager.snapshot(sortMode: .manual).root.children)

        return SumiPortableData(
            profiles: profiles,
            spaces: spaces,
            folders: folders,
            essentials: essentials,
            pinnedLaunchers: pinnedLaunchers,
            regularTabs: regularTabs,
            bookmarks: bookmarks
        )
    }

    private static func portableBookmarks(from entities: [SumiBookmarkEntity]) -> [SumiPortableBookmarkNode] {
        entities.compactMap { entity in
            switch entity.kind {
            case .bookmark:
                guard let url = entity.url else { return nil }
                return SumiPortableBookmarkNode(
                    name: entity.title,
                    kind: .bookmark,
                    urlString: url.absoluteString,
                    children: []
                )
            case .folder:
                return SumiPortableBookmarkNode(
                    name: entity.title,
                    kind: .folder,
                    urlString: nil,
                    children: portableBookmarks(from: entity.children)
                )
            }
        }
    }
}

enum SumiBookmarkPortableBridge {
    static func portableNodes(from nodes: [SumiBookmarkImportNode]) -> [SumiPortableBookmarkNode] {
        nodes.map(portableNode(from:))
    }

    static func importNodes(from nodes: [SumiPortableBookmarkNode]) -> [SumiBookmarkImportNode] {
        nodes.compactMap(importNode(from:))
    }

    private static func portableNode(from node: SumiBookmarkImportNode) -> SumiPortableBookmarkNode {
        SumiPortableBookmarkNode(
            name: node.name,
            kind: SumiPortableBookmarkNode.Kind(importKind: node.type),
            urlString: node.urlString,
            children: portableNodes(from: node.children ?? [])
        )
    }

    private static func importNode(from node: SumiPortableBookmarkNode) -> SumiBookmarkImportNode? {
        switch node.kind {
        case .bookmark:
            guard let urlString = node.urlString else { return nil }
            return SumiBookmarkImportNode(
                name: node.name,
                type: .bookmark,
                urlString: urlString,
                children: nil
            )
        case .favorite:
            guard let urlString = node.urlString else { return nil }
            return SumiBookmarkImportNode(
                name: node.name,
                type: .favorite,
                urlString: urlString,
                children: nil
            )
        case .folder:
            return SumiBookmarkImportNode(
                name: node.name,
                type: .folder,
                urlString: nil,
                children: importNodes(from: node.children)
            )
        }
    }
}

private extension SumiPortableBookmarkNode.Kind {
    init(importKind: SumiBookmarkImportNode.NodeType) {
        switch importKind {
        case .bookmark:
            self = .bookmark
        case .favorite:
            self = .favorite
        case .folder:
            self = .folder
        }
    }
}
