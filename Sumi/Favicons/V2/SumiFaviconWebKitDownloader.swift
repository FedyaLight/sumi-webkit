import Foundation
import OSLog
import WebKit

enum SumiFaviconWebKitDownloaderDefaults {
    @MainActor
    private static let downloader = SumiFaviconWebKitDownloader()

    @MainActor
    static func download(
        url: URL,
        webView: WKWebView
    ) async -> SumiFaviconFetchResult {
        await downloader.download(url: url, webView: webView)
    }
}

@MainActor
private final class SumiFaviconWebKitDownloader: NSObject, WKDownloadDelegate {
    private static let log = Logger.sumi(category: "FaviconWebKitDownloader")

    private struct PendingDownload {
        let continuation: CheckedContinuation<SumiFaviconFetchResult, Never>
        var destinationURL: URL?
        var mimeType: String?
        var statusCode: Int?
    }

    private var pendingDownloads: [WKDownload: PendingDownload] = [:]

    func download(url: URL, webView: WKWebView) async -> SumiFaviconFetchResult {
        let download = await webView.startDownload(using: URLRequest(url: url))
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingDownloads[download] = PendingDownload(
                    continuation: continuation
                )
                download.delegate = self
            }
        } onCancel: {
            Task { @MainActor [weak self, weak download] in
                guard let download else { return }
                self?.cancel(download)
            }
        }
    }

    private func cancel(_ download: WKDownload) {
        let pending = pendingDownloads.removeValue(forKey: download)
        download.delegate = nil
        Task {
            _ = await download.cancel()
        }
        Self.removeTemporaryDownloadIfPresent(pending?.destinationURL)
        pending?.continuation.resume(returning: .cancelled)
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename _: String
    ) async -> URL? {
        guard var pending = pendingDownloads[download] else { return nil }
        if let httpResponse = response as? HTTPURLResponse {
            pending.statusCode = httpResponse.statusCode
            guard (200..<300).contains(httpResponse.statusCode) else {
                pendingDownloads[download] = pending
                return nil
            }
        }
        guard response.expectedContentLength <= SumiFaviconConstants.maxPayloadBytes else {
            pendingDownloads[download] = pending
            return nil
        }
        pending.mimeType = response.mimeType
        let destinationURL = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ).appendingPathComponent(UUID().uuidString)
        pending.destinationURL = destinationURL
        pendingDownloads[download] = pending
        return destinationURL
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let pending = pendingDownloads.removeValue(forKey: download) else {
            return
        }
        defer { Self.removeTemporaryDownloadIfPresent(pending.destinationURL) }
        guard let destinationURL = pending.destinationURL else {
            pending.continuation.resume(returning: .failure(.transport))
            return
        }
        do {
            pending.continuation.resume(
                returning: .success(
                    SumiFaviconFetchResponse(
                        data: try Data(contentsOf: destinationURL),
                        mimeType: pending.mimeType,
                        statusCode: pending.statusCode
                    )
                )
            )
        } catch {
            Self.log.error(
                "Downloaded favicon could not be read: \(error.localizedDescription, privacy: .public)"
            )
            pending.continuation.resume(returning: .failure(.transport))
        }
    }

    func download(
        _ download: WKDownload,
        didFailWithError _: Error,
        resumeData _: Data?
    ) {
        guard let pending = pendingDownloads.removeValue(forKey: download) else {
            return
        }
        Self.removeTemporaryDownloadIfPresent(pending.destinationURL)
        let failure: SumiFaviconValidationFailureKind = pending.statusCode == 404
            ? .notFound
            : .transport
        pending.continuation.resume(returning: .failure(failure))
    }

    private static func removeTemporaryDownloadIfPresent(_ url: URL?) {
        guard let url else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            let nsError = error as NSError
            guard nsError.domain != NSCocoaErrorDomain
                    || nsError.code != NSFileNoSuchFileError
            else {
                return
            }
            log.error(
                "Failed to remove temporary favicon download: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
