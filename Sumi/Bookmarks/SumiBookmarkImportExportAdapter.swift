
import Foundation

extension SumiBookmarkImportSource {
    func readBookmarks() throws -> [SumiBookmarkImportNode] {
        try storeSource.readBookmarks().map(SumiBookmarkImportNode.init(storeBookmarkOrFolder:))
    }

    static func detectedBrowserSources(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [SumiBookmarkImportSource] {
        BookmarkImportSource.detectedBrowserSources(homeDirectory: homeDirectory)
            .map(SumiBookmarkImportSource.init(storeImportSource:))
    }

    init(storeImportSource: BookmarkImportSource) {
        self.init(
            id: storeImportSource.id,
            title: storeImportSource.title,
            fileURL: storeImportSource.fileURL,
            kind: SumiBookmarkImportReaderKind(storeReaderKind: storeImportSource.kind)
        )
    }

    var storeSource: BookmarkImportSource {
        BookmarkImportSource(
            id: id,
            title: title,
            fileURL: fileURL,
            kind: kind.storeReaderKind
        )
    }
}

extension SumiBookmarkImportNode {
    init(storeBookmarkOrFolder: BookmarkOrFolder) {
        self.init(
            name: storeBookmarkOrFolder.name,
            type: SumiBookmarkImportNode.NodeType(storeBookmarkType: storeBookmarkOrFolder.type),
            urlString: storeBookmarkOrFolder.urlString,
            children: storeBookmarkOrFolder.children?.map(SumiBookmarkImportNode.init(storeBookmarkOrFolder:))
        )
    }

    var storeBookmarkOrFolder: BookmarkOrFolder {
        BookmarkOrFolder(
            name: name,
            type: type.storeBookmarkType,
            urlString: urlString,
            children: children?.map(\.storeBookmarkOrFolder)
        )
    }
}

extension SumiBookmarksImportSummary {
    init(storeImportSummary: BookmarksImportSummary) {
        self.init(
            successful: storeImportSummary.successful,
            duplicates: storeImportSummary.duplicates,
            failed: storeImportSummary.failed
        )
    }
}

private extension SumiBookmarkImportReaderKind {
    init(storeReaderKind: BookmarkImportReaderKind) {
        switch storeReaderKind {
        case .html:
            self = .html
        case .safariPlist:
            self = .safariPlist
        case .chromiumJSON:
            self = .chromiumJSON
        case .firefoxSQLite:
            self = .firefoxSQLite
        }
    }

    var storeReaderKind: BookmarkImportReaderKind {
        switch self {
        case .html:
            return .html
        case .safariPlist:
            return .safariPlist
        case .chromiumJSON:
            return .chromiumJSON
        case .firefoxSQLite:
            return .firefoxSQLite
        }
    }
}

private extension SumiBookmarkImportNode.NodeType {
    init(storeBookmarkType: BookmarkOrFolder.BookmarkType) {
        switch storeBookmarkType {
        case .bookmark:
            self = .bookmark
        case .favorite:
            self = .favorite
        case .folder:
            self = .folder
        }
    }

    var storeBookmarkType: BookmarkOrFolder.BookmarkType {
        switch self {
        case .bookmark:
            return .bookmark
        case .favorite:
            return .favorite
        case .folder:
            return .folder
        }
    }
}
