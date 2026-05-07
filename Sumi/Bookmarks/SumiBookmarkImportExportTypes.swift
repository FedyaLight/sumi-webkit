import Foundation

enum SumiBookmarkImportReaderKind: Equatable, Sendable {
    case html
    case safariPlist
    case chromiumJSON
    case firefoxSQLite
}

struct SumiBookmarkImportSource: Equatable, Identifiable, Sendable {
    let id: String
    var title: String
    var fileURL: URL
    var kind: SumiBookmarkImportReaderKind
}

struct SumiBookmarkImportNode: Equatable, Sendable {
    enum NodeType: String, Equatable, Sendable {
        case bookmark
        case favorite
        case folder
    }

    let name: String
    let type: NodeType
    let urlString: String?
    var children: [SumiBookmarkImportNode]?

    var url: URL? {
        urlString.flatMap(URL.init(string:))
    }

    init(
        name: String,
        type: NodeType,
        urlString: String?,
        children: [SumiBookmarkImportNode]?
    ) {
        self.name = name
        self.type = type
        self.urlString = urlString
        self.children = children
    }

    static func bookmark(name: String, url: URL) -> SumiBookmarkImportNode {
        SumiBookmarkImportNode(
            name: name,
            type: .bookmark,
            urlString: url.absoluteString,
            children: nil
        )
    }

    static func favorite(name: String, url: URL) -> SumiBookmarkImportNode {
        SumiBookmarkImportNode(
            name: name,
            type: .favorite,
            urlString: url.absoluteString,
            children: nil
        )
    }

    static func folder(name: String, children: [SumiBookmarkImportNode]) -> SumiBookmarkImportNode {
        SumiBookmarkImportNode(
            name: name,
            type: .folder,
            urlString: nil,
            children: children
        )
    }
}

struct SumiBookmarksImportSummary: Equatable, Sendable {
    var successful: Int
    var duplicates: Int
    var failed: Int

    var message: String {
        "\(successful) imported, \(duplicates) duplicate, \(failed) failed."
    }
}
