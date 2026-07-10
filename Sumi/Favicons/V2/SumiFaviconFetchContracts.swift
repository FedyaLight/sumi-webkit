import Foundation
import WebKit

final class SumiFaviconWebViewReference: @unchecked Sendable {
    @MainActor weak var webView: WKWebView?

    @MainActor
    init(_ webView: WKWebView?) {
        self.webView = webView
    }
}

struct SumiFaviconFetchContext: Sendable {
    enum Kind: Sendable {
        case sessionProfileAware
        case publicRootFallback
    }

    let kind: Kind
    let webViewReference: SumiFaviconWebViewReference?
    let sourceDocumentURL: URL?

    static func session(
        webView: WKWebView?,
        sourceDocumentURL: URL
    ) -> SumiFaviconFetchContext {
        MainActor.assumeIsolated {
            SumiFaviconFetchContext(
                kind: .sessionProfileAware,
                webViewReference: SumiFaviconWebViewReference(webView),
                sourceDocumentURL: sourceDocumentURL
            )
        }
    }

    static let publicRootFallback = SumiFaviconFetchContext(
        kind: .publicRootFallback,
        webViewReference: nil,
        sourceDocumentURL: nil
    )
}

struct SumiFaviconFetchResponse: Sendable {
    let data: Data
    let mimeType: String?
    let statusCode: Int?
}

enum SumiFaviconFetchResult: Sendable {
    case success(SumiFaviconFetchResponse)
    case failure(SumiFaviconValidationFailureKind)
    case cancelled
}

protocol SumiFaviconNetworkFetching: Sendable {
    func fetch(
        url: URL,
        context: SumiFaviconFetchContext
    ) async -> SumiFaviconFetchResult
}

typealias SumiFaviconWebKitDownloadHandler =
    @MainActor @Sendable (URL, WKWebView) async -> SumiFaviconFetchResult
