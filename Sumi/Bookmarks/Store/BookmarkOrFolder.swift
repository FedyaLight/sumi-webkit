//
//  BookmarkOrFolder.swift
//
//
//  Derived from DuckDuckGo BrowserServicesKit (https://github.com/duckduckgo/apple-browsers),
//  Copyright © DuckDuckGo. Licensed under the Apache License, Version 2.0;
//  see http://www.apache.org/licenses/LICENSE-2.0. Adapted for Sumi.
//

import Foundation

final class BookmarkOrFolder {
    enum BookmarkType: String {
        case bookmark
        case favorite
        case folder
    }

    let name: String
    let type: BookmarkType
    let urlString: String?
    var children: [BookmarkOrFolder]?

    var url: URL? {
        urlString.flatMap(URL.init(string:))
    }

    var isInvalidBookmark: Bool {
        switch type {
        case .bookmark, .favorite:
            return urlString == nil
        case .folder:
            return false
        }
    }

    init(name: String, type: BookmarkType, urlString: String?, children: [BookmarkOrFolder]?) {
        self.name = name
        self.type = type
        self.urlString = urlString
        self.children = children
    }

    static func bookmark(name: String, url: URL) -> BookmarkOrFolder {
        BookmarkOrFolder(name: name, type: .bookmark, urlString: url.absoluteString, children: nil)
    }

    static func folder(name: String, children: [BookmarkOrFolder]) -> BookmarkOrFolder {
        BookmarkOrFolder(name: name, type: .folder, urlString: nil, children: children)
    }
}
