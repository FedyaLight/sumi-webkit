import Foundation

public struct SumiNavigationResponse {
    public let url: URL
    public let isForMainFrame: Bool
    public let canShowMIMEType: Bool
    public let shouldDownload: Bool
    public let httpResponse: HTTPURLResponse?
    public let mimeType: String?
    public let mainFrameNavigation: SumiNavigationMainFrameNavigation?

    public init(
        url: URL,
        isForMainFrame: Bool,
        canShowMIMEType: Bool,
        shouldDownload: Bool,
        httpResponse: HTTPURLResponse?,
        mimeType: String?,
        mainFrameNavigation: SumiNavigationMainFrameNavigation?
    ) {
        self.url = url
        self.isForMainFrame = isForMainFrame
        self.canShowMIMEType = canShowMIMEType
        self.shouldDownload = shouldDownload
        self.httpResponse = httpResponse
        self.mimeType = mimeType
        self.mainFrameNavigation = mainFrameNavigation
    }

    public var isHTTPStatusSuccessful: Bool? {
        httpResponse.map { (200..<300).contains($0.statusCode) }
    }
}
