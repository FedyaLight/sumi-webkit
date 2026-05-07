import Foundation

struct SumiNavigationResponse {
    let url: URL
    let isForMainFrame: Bool
    let canShowMIMEType: Bool
    let shouldDownload: Bool
    let httpResponse: HTTPURLResponse?
    let mimeType: String?
    let mainFrameNavigation: SumiNavigationMainFrameNavigation?

    var isHTTPStatusSuccessful: Bool? {
        httpResponse.map { (200..<300).contains($0.statusCode) }
    }
}
