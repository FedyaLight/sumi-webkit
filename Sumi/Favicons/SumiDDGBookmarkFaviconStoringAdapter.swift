import Bookmarks
import Foundation

@MainActor
final class SumiDDGBookmarkFaviconStoringAdapter: Bookmarks.FaviconStoring {
    private let storage: any SumiFaviconStoring

    init(storage: any SumiFaviconStoring) {
        self.storage = storage
    }

    func hasFavicon(for domain: String) -> Bool {
        storage.hasFavicon(for: domain)
    }

    func storeFavicon(_ imageData: Data, with url: URL?, for documentURL: URL) async throws {
        try await storage.storeFavicon(imageData, with: url, for: documentURL)
    }
}
