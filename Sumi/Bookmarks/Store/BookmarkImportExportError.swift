//
//  BookmarkImportExportError.swift
//
//
//  Derived from DuckDuckGo BrowserServicesKit (https://github.com/duckduckgo/apple-browsers),
//  Copyright © DuckDuckGo. Licensed under the Apache License, Version 2.0;
//  see http://www.apache.org/licenses/LICENSE-2.0. Adapted for Sumi.
//

import Foundation

enum BookmarkImportExportError: LocalizedError {
    case missingRootFolder
    case unreadableFirefoxDatabase
    case unreadableFirefoxBookmarks
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRootFolder:
            return "Bookmarks storage is not ready."
        case .unreadableFirefoxDatabase:
            return "Could not open Firefox bookmarks database."
        case .unreadableFirefoxBookmarks:
            return "Could not read Firefox bookmarks."
        case .exportFailed(let message):
            return message
        }
    }
}
