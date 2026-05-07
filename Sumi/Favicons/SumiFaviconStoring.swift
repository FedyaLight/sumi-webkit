import Foundation

@MainActor
protocol SumiFaviconStoring: AnyObject {
    func hasFavicon(for domain: String) -> Bool
    func storeFavicon(_ imageData: Data, with url: URL?, for documentURL: URL) async throws
}
