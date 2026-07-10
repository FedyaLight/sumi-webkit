import Foundation
import WebKit

/// URLSession transport with profile-aware cookie projection. WebKit download
/// fallback is delegated to the main-actor downloader.
final class SumiFaviconNetworkClient: SumiFaviconNetworkFetching, @unchecked Sendable {
    private let publicSession: URLSession
    private let webKitDownload: SumiFaviconWebKitDownloadHandler

    init(
        publicSession: URLSession = URLSession(configuration: .ephemeral),
        webKitDownload: @escaping SumiFaviconWebKitDownloadHandler =
            SumiFaviconWebKitDownloaderDefaults.download
    ) {
        self.publicSession = publicSession
        self.webKitDownload = webKitDownload
    }

    func fetch(
        url: URL,
        context: SumiFaviconFetchContext
    ) async -> SumiFaviconFetchResult {
        switch context.kind {
        case .publicRootFallback:
            return await perform(request: baseRequest(url: url))
        case .sessionProfileAware:
            if let reference = context.webViewReference,
               let webView = await reference.webView {
                let result = await fetchSessionAware(
                    url: url,
                    webView: webView,
                    sourceDocumentURL: context.sourceDocumentURL
                )
                if case .success = result {
                    return result
                }
                if case .cancelled = result {
                    return .cancelled
                }
                return await webKitDownload(url, webView)
            }
            return await perform(request: baseRequest(url: url))
        }
    }

    private func fetchSessionAware(
        url: URL,
        webView: WKWebView,
        sourceDocumentURL: URL?
    ) async -> SumiFaviconFetchResult {
        var request = baseRequest(url: url)
        let cookies = await sessionCookies(for: webView)
        let matchingCookies = SumiCookieMatcher.cookies(
            cookies,
            matching: url,
            sourceDocumentURL: sourceDocumentURL
        )
        for (header, value) in HTTPCookie.requestHeaderFields(with: matchingCookies) {
            request.setValue(value, forHTTPHeaderField: header)
        }
        return await perform(request: request)
    }

    private func baseRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "image/avif,image/webp,image/png,image/svg+xml,image/*,*/*;q=0.5",
            forHTTPHeaderField: "Accept"
        )
        return request
    }

    private func perform(request: URLRequest) async -> SumiFaviconFetchResult {
        do {
            let (data, response) = try await publicSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .success(
                    SumiFaviconFetchResponse(
                        data: data,
                        mimeType: response.mimeType,
                        statusCode: nil
                    )
                )
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                return .failure(
                    httpResponse.statusCode == 404 ? .notFound : .transport
                )
            }
            return .success(
                SumiFaviconFetchResponse(
                    data: data,
                    mimeType: httpResponse.mimeType,
                    statusCode: httpResponse.statusCode
                )
            )
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(.transport)
        }
    }

    @MainActor
    private func sessionCookies(for webView: WKWebView) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies {
                continuation.resume(returning: $0)
            }
        }
    }
}
