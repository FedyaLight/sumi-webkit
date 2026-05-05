//
//  BookmarkOrFolder.swift
//

import Foundation

public final class BookmarkOrFolder {
    public enum BookmarkType: String {
        case bookmark
        case favorite
        case folder
    }

    public let name: String
    public let type: BookmarkType
    public let urlString: String?
    public var children: [BookmarkOrFolder]?

    public var url: URL? {
        urlString.flatMap(URL.init(string:))
    }

    public var isInvalidBookmark: Bool {
        switch type {
        case .bookmark, .favorite:
            return urlString == nil
        case .folder:
            return false
        }
    }

    public init(name: String, type: BookmarkType, urlString: String?, children: [BookmarkOrFolder]?) {
        self.name = name
        self.type = type
        self.urlString = urlString
        self.children = children
    }

    public static func bookmark(name: String, url: URL) -> BookmarkOrFolder {
        BookmarkOrFolder(name: name, type: .bookmark, urlString: url.absoluteString, children: nil)
    }

    public static func folder(name: String, children: [BookmarkOrFolder]) -> BookmarkOrFolder {
        BookmarkOrFolder(name: name, type: .folder, urlString: nil, children: children)
    }
}
