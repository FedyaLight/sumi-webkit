import Foundation

@MainActor
protocol SumiImportBookmarkMutating: AnyObject {
    func checkpoint() -> SumiBookmarksSnapshot
    func commit(_ mutation: SumiImportBookmarkMutation) throws -> SumiBookmarksImportSummary?
    func restore(_ checkpoint: SumiBookmarksSnapshot) throws
}

@MainActor
final class SumiImportBookmarkStore: SumiImportBookmarkMutating {
    private let bookmarkManager: SumiBookmarkManager

    init(bookmarkManager: SumiBookmarkManager) {
        self.bookmarkManager = bookmarkManager
    }

    func checkpoint() -> SumiBookmarksSnapshot {
        bookmarkManager.snapshot(sortMode: .manual)
    }

    func commit(_ mutation: SumiImportBookmarkMutation) throws -> SumiBookmarksImportSummary? {
        switch mutation {
        case .none:
            return nil
        case .merge(let portableNodes):
            let nodes = SumiBookmarkPortableBridge.importNodes(from: portableNodes)
            guard !nodes.isEmpty else { return nil }
            return try bookmarkManager.importBookmarks(nodes)
        case .replace(let portableNodes):
            return try bookmarkManager.replaceBookmarks(
                SumiBookmarkPortableBridge.importNodes(from: portableNodes)
            )
        }
    }

    func restore(_ checkpoint: SumiBookmarksSnapshot) throws {
        try bookmarkManager.restoreSnapshot(checkpoint)
    }
}
