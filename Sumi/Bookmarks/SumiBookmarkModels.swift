import Foundation

struct SumiBookmark: Equatable, Identifiable, Sendable {
    let id: String
    var title: String
    var url: URL
    var folderID: String?
}

struct SumiBookmarkFolder: Equatable, Identifiable, Sendable {
    let id: String
    var title: String
    var depth: Int
}

enum SumiBookmarkEntityKind: String, Equatable, Sendable {
    case bookmark
    case folder
}

struct SumiBookmarkEntity: Equatable, Identifiable, Sendable {
    let id: String
    var kind: SumiBookmarkEntityKind
    var title: String
    var url: URL?
    var parentID: String?
    var parentTitle: String?
    var children: [SumiBookmarkEntity]
    var childBookmarkCount: Int

    var isFolder: Bool {
        kind == .folder
    }

    var isBookmark: Bool {
        kind == .bookmark
    }

    var displayURL: String {
        url?.absoluteString ?? ""
    }

    func matchesSearch(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if title.localizedCaseInsensitiveContains(trimmed) {
            return true
        }
        return url?.absoluteString.localizedCaseInsensitiveContains(trimmed) == true
    }
}

struct SumiBookmarksSnapshot: Equatable, Sendable {
    var root: SumiBookmarkEntity
    var flattenedFolders: [SumiBookmarkFolder]
    var entitiesByID: [String: SumiBookmarkEntity]

    var hasBookmarks: Bool {
        root.childBookmarkCount > 0
    }
}

enum SumiBookmarkSortMode: String, CaseIterable, Identifiable, Sendable {
    case manual
    case nameAscending
    case nameDescending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return "Manual Order"
        case .nameAscending:
            return "Name A-Z"
        case .nameDescending:
            return "Name Z-A"
        }
    }

    var allowsManualMove: Bool {
        self == .manual
    }
}

struct SumiBookmarkImportSummary: Equatable, Sendable {
    var imported: Int
    var duplicates: Int
    var failed: Int

    var message: String {
        "\(imported) imported, \(duplicates) duplicate, \(failed) failed."
    }
}

struct SumiBookmarkAllTabsResult: Equatable, Sendable {
    var created: Int
    var duplicates: Int
    var skipped: Int
    var folderTitle: String
}

enum SumiBookmarkEditorMode: Equatable, Sendable {
    case add
    case edit

    var primaryActionTitle: String {
        switch self {
        case .add:
            return "Add"
        case .edit:
            return "Save"
        }
    }
}

struct SumiBookmarkEditorState: Equatable, Identifiable, Sendable {
    let mode: SumiBookmarkEditorMode
    let bookmarkID: String?
    let tabID: UUID
    let pageURL: URL
    var title: String
    var urlString: String
    var folderID: String?

    var id: String {
        "\(bookmarkID ?? "draft")-\(mode)-\(pageURL.absoluteString)"
    }
}

struct SumiBookmarkEditorPresentationRequest: Equatable, Identifiable, Sendable {
    let id = UUID()
    let windowID: UUID
    let tabID: UUID
}

enum SumiBookmarkError: LocalizedError, Equatable {
    case emptyTitle
    case invalidURL
    case unsupportedURL
    case missingBookmark
    case missingFolder
    case cannotDeleteRootFolder
    case cannotMoveFolderIntoDescendant
    case duplicateURL
    case missingRootFolder
    case saveFailed(String)
    case importFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "Enter a bookmark name."
        case .invalidURL:
            return "Enter a valid URL."
        case .unsupportedURL:
            return "This page cannot be bookmarked."
        case .missingBookmark:
            return "The bookmark could not be found."
        case .missingFolder:
            return "The bookmark folder could not be found."
        case .cannotDeleteRootFolder:
            return "The root bookmarks folder cannot be deleted."
        case .cannotMoveFolderIntoDescendant:
            return "A folder cannot be moved into itself or one of its subfolders."
        case .duplicateURL:
            return "That URL is already bookmarked."
        case .missingRootFolder:
            return "Bookmarks storage is not ready."
        case .saveFailed(let message):
            return message
        case .importFailed(let message):
            return message
        case .exportFailed(let message):
            return message
        }
    }
}

struct SumiImportedBookmarkNode: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case bookmark(URL)
        case folder
    }

    var title: String
    var kind: Kind
    var children: [SumiImportedBookmarkNode]

    static func bookmark(title: String, url: URL) -> SumiImportedBookmarkNode {
        SumiImportedBookmarkNode(title: title, kind: .bookmark(url), children: [])
    }

    static func folder(title: String, children: [SumiImportedBookmarkNode]) -> SumiImportedBookmarkNode {
        SumiImportedBookmarkNode(title: title, kind: .folder, children: children)
    }
}
