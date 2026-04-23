import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import WebKit

@MainActor
final class SumiWebKitDownloadTask: NSObject, WKDownloadDelegate {
    private let download: WKDownload
    private let item: DownloadItem
    private weak var coordinator: DownloadListCoordinator?
    private let progress: DownloadProgress
    private var progressPresenter: DownloadFileProgressPresenter?
    private var tempFilePresenter: DownloadFilePresenter?
    private var isCancelling = false
    private var lastReceivedBytes: UInt64 = 0
    private var progressCancellables = Set<AnyCancellable>()
    private let flyAnimationOriginalRect: NSRect?

    init(
        download: WKDownload,
        item: DownloadItem,
        coordinator: DownloadListCoordinator,
        flyAnimationOriginalRect: NSRect?
    ) {
        self.download = download
        self.item = item
        self.coordinator = coordinator
        self.flyAnimationOriginalRect = flyAnimationOriginalRect
        self.progress = DownloadProgress(download: download)
        super.init()
        self.progress.cancellationHandler = { [weak self] in
            Task { @MainActor in
                self?.cancel()
            }
        }
    }

    func start() {
        coordinator?.didAttachProgress(progress, for: item)
        subscribeToProgress()
        download.delegate = self
    }

    func cancel() {
        guard !isCancelling else { return }
        isCancelling = true
        download.cancel { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cleanupTempFile(deletePartialFile: true)
                self.coordinator?.didFail(self.item, error: .cancelled)
            }
        }
    }

    func download(
        _: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        guard !isCancelling else { return nil }

        let reservation = coordinator?.reserveDestination(
            for: item,
            response: response,
            suggestedFilename: suggestedFilename
        )
        guard let reservation else { return nil }

        coordinator?.didChooseDestination(reservation, for: item, response: response)
        progress.fileURL = reservation.tempURL
        configureSystemPresentation(for: reservation.destinationURL, response: response)
        progressPresenter = DownloadFileProgressPresenter(progress: progress)
        progressPresenter?.displayProgress(at: reservation.tempURL)
        tempFilePresenter = DownloadFilePresenter(url: reservation.tempURL) { [weak self] in
            Task { @MainActor in
                guard let self, self.item.isActive else { return }
                self.coordinator?.didFail(
                    self.item,
                    error: .failed(
                        message: "The temporary download file was removed.",
                        resumeData: nil,
                        isRetryable: false
                    )
                )
            }
        }
        return reservation.tempURL
    }

    func download(_: WKDownload, didReceive response: URLResponse) {
        coordinator?.didReceiveResponse(response, for: item)
        if response.expectedContentLength > 0 {
            progress.updateProgress(
                totalUnitCount: response.expectedContentLength,
                completedUnitCount: progress.completedUnitCount
            )
            coordinator?.didUpdateProgress(progress, for: item)
        }
    }

    func download(_: WKDownload, didReceive bytes: UInt64) {
        lastReceivedBytes = bytes
        let sourceProgress = download.progress
        let total = sourceProgress.totalUnitCount
        let completed = sourceProgress.completedUnitCount
        progress.updateProgress(totalUnitCount: total, completedUnitCount: completed)
        coordinator?.didUpdateProgress(progress, for: item)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let sourceCompleted = download.progress.completedUnitCount
        let knownBytes = max(sourceCompleted, Int64(lastReceivedBytes), progress.completedUnitCount)
        progress.markCompleted(byteCount: knownBytes)
        coordinator?.didUpdateProgress(progress, for: item)

        guard let tempURL = item.tempURL,
              let destinationURL = item.destinationURL
        else {
            coordinator?.didFail(
                item,
                error: .moveFailed(message: "Download finished without a destination.")
            )
            return
        }

        let itemID = item.id
        let moveTask = Task.detached(priority: .utility) {
            let finalURL = DownloadFileUtilities.uniqueURL(for: destinationURL)
            do {
                let fm = FileManager.default
                try fm.createDirectory(
                    at: finalURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fm.fileExists(atPath: finalURL.path) {
                    try fm.removeItem(at: finalURL)
                }
                try fm.moveItem(at: tempURL, to: finalURL)
                return Result<URL, Error>.success(finalURL)
            } catch {
                await MainActor.run {
                    RuntimeDiagnostics.debug(
                        "Download move failed id=\(itemID.uuidString): \(String(describing: error))",
                        category: "DownloadManager"
                    )
                }
                return Result<URL, Error>.failure(error)
            }
        }

        Task { @MainActor [weak self] in
            let result = await moveTask.value
            guard let self else { return }
            switch result {
            case .success(let finalURL):
                self.progressCancellables.removeAll()
                self.progressPresenter = nil
                self.tempFilePresenter = nil
                self.coordinator?.didFinish(self.item, finalURL: finalURL)
            case .failure(let error):
                self.coordinator?.didFail(
                    self.item,
                    error: .moveFailed(message: error.localizedDescription)
                )
            }
        }
    }

    func download(_: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let nsError = error as NSError
        let cancelled = isCancelling || nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled

        if cancelled {
            cleanupTempFile(deletePartialFile: true)
            coordinator?.didFail(item, error: .cancelled)
            return
        }

        let retryable = resumeData != nil
        if !retryable {
            cleanupTempFile(deletePartialFile: true)
        }
        coordinator?.didFail(
            item,
            error: .failed(
                message: error.localizedDescription,
                resumeData: resumeData,
                isRetryable: retryable
            )
        )
    }

    func downloadWillPerformHTTPRedirection(
        _: WKDownload,
        navigationResponse _: HTTPURLResponse,
        newRequest request: URLRequest,
        decisionHandler: @escaping (URLRequest?) -> Void
    ) {
        decisionHandler(request)
    }

    func download(
        _: WKDownload,
        didReceive _: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }

    private func cleanupTempFile(deletePartialFile: Bool) {
        progressCancellables.removeAll()
        progressPresenter = nil
        tempFilePresenter = nil
        guard deletePartialFile, let tempURL = item.tempURL else { return }
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    private func subscribeToProgress() {
        progressCancellables.removeAll(keepingCapacity: true)
        progress.publisher(for: \.totalUnitCount)
            .combineLatest(progress.publisher(for: \.completedUnitCount))
            .dropFirst()
            .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.coordinator?.didUpdateProgress(self.progress, for: self.item)
                }
            }
            .store(in: &progressCancellables)
    }

    private func configureSystemPresentation(for destinationURL: URL, response: URLResponse) {
        guard let flyAnimationOriginalRect else { return }

        let fileType = UTType(filenameExtension: destinationURL.pathExtension)
            ?? response.sumiSuggestedFileType
            ?? .data
        let icon = NSWorkspace.shared.icon(for: fileType)
        progress.flyToImage = icon
        progress.fileIcon = icon
        progress.fileIconOriginalRect = flyAnimationOriginalRect
    }
}

private extension URLResponse {
    var sumiSuggestedFileType: UTType? {
        guard var mimeType else { return nil }
        if let charsetRange = mimeType.range(of: ";charset=") {
            mimeType = String(mimeType[..<charsetRange.lowerBound])
        }
        return UTType(mimeType: mimeType)
    }
}
