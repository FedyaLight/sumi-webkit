//
//  BookmarkImportExportError.swift
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
