import Bookmarks
import Foundation

extension SumiBookmarkImportSource {
    func readBookmarks() throws -> [SumiBookmarkImportNode] {
        try ddgSource.readBookmarks().map(SumiBookmarkImportNode.init(ddgBookmarkOrFolder:))
    }

    static func detectedBrowserSources(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [SumiBookmarkImportSource] {
        BookmarkImportSource.detectedBrowserSources(homeDirectory: homeDirectory)
            .map(SumiBookmarkImportSource.init(ddgImportSource:))
    }

    init(ddgImportSource: BookmarkImportSource) {
        self.init(
            id: ddgImportSource.id,
            title: ddgImportSource.title,
            fileURL: ddgImportSource.fileURL,
            kind: SumiBookmarkImportReaderKind(ddgReaderKind: ddgImportSource.kind)
        )
    }

    var ddgSource: BookmarkImportSource {
        BookmarkImportSource(
            id: id,
            title: title,
            fileURL: fileURL,
            kind: kind.ddgReaderKind
        )
    }
}

extension SumiBookmarkImportNode {
    init(ddgBookmarkOrFolder: BookmarkOrFolder) {
        self.init(
            name: ddgBookmarkOrFolder.name,
            type: SumiBookmarkImportNode.NodeType(ddgBookmarkType: ddgBookmarkOrFolder.type),
            urlString: ddgBookmarkOrFolder.urlString,
            children: ddgBookmarkOrFolder.children?.map(SumiBookmarkImportNode.init(ddgBookmarkOrFolder:))
        )
    }

    var ddgBookmarkOrFolder: BookmarkOrFolder {
        BookmarkOrFolder(
            name: name,
            type: type.ddgBookmarkType,
            urlString: urlString,
            children: children?.map(\.ddgBookmarkOrFolder)
        )
    }
}

extension SumiBookmarksImportSummary {
    init(ddgImportSummary: BookmarksImportSummary) {
        self.init(
            successful: ddgImportSummary.successful,
            duplicates: ddgImportSummary.duplicates,
            failed: ddgImportSummary.failed
        )
    }
}

private extension SumiBookmarkImportReaderKind {
    init(ddgReaderKind: BookmarkImportReaderKind) {
        switch ddgReaderKind {
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

    var ddgReaderKind: BookmarkImportReaderKind {
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
    init(ddgBookmarkType: BookmarkOrFolder.BookmarkType) {
        switch ddgBookmarkType {
        case .bookmark:
            self = .bookmark
        case .favorite:
            self = .favorite
        case .folder:
            self = .folder
        }
    }

    var ddgBookmarkType: BookmarkOrFolder.BookmarkType {
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
