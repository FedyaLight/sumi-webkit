import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import WebKit

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var items: [DownloadItem] = []
    @Published private(set) var activeDownloadCount: Int = 0
    @Published private(set) var combinedProgressFraction: Double?

    private let coordinator: DownloadListCoordinator
    weak var browserManager: BrowserManager?

    init() {
        DownloadFileUtilities.removeOrphanedIncompleteDownloads()
        self.coordinator = DownloadListCoordinator()
        self.items = coordinator.items
        self.activeDownloadCount = coordinator.activeCount
        self.combinedProgressFraction = coordinator.combinedProgressFraction

        coordinator.onChange = { [weak self] in
            self?.publishCoordinatorState()
        }
    }

    var hasActiveDownloads: Bool {
        activeDownloadCount > 0
    }

    var hasInactiveDownloads: Bool {
        items.contains { !$0.isActive }
    }

    var activeItems: [DownloadItem] {
        items.filter(\.isActive)
    }

    var completedItems: [DownloadItem] {
        items.filter { $0.state == .completed }
    }

    var failedItems: [DownloadItem] {
        items.filter { $0.state == .failed }
    }

    @discardableResult
    func addDownload(
        _ download: WKDownload,
        originalURL: URL,
        websiteURL: URL? = nil,
        suggestedFilename: String,
        flyAnimationOriginalRect: NSRect? = nil
    ) -> DownloadItem {
        let item = coordinator.start(
            download: download,
            originalURL: originalURL,
            websiteURL: websiteURL,
            suggestedFilename: suggestedFilename,
            flyAnimationOriginalRect: flyAnimationOriginalRect
        )
        publishCoordinatorState()
        return item
    }

    func saveDownloadedData(
        _ data: Data,
        suggestedFilename: String,
        mimeType _: String?,
        originatingURL: URL
    ) {
        let destinationURL = DownloadFileUtilities.uniqueDestination(for: suggestedFilename)
        let tempURL = DownloadFileUtilities.incompleteURL(for: destinationURL)
        let progress = DownloadProgress(totalUnitCount: max(Int64(data.count), 1))
        progress.fileDownloadingSourceURL = originatingURL
        progress.fileURL = tempURL
        let item = DownloadItem(
            downloadURL: originatingURL,
            websiteURL: originatingURL,
            fileName: destinationURL.lastPathComponent,
            destinationURL: destinationURL,
            tempURL: tempURL,
            state: .downloading,
            progress: progress,
            completedUnitCount: 0,
            totalUnitCount: progress.totalUnitCount
        )
        coordinator.track(item, progress: progress)
        publishCoordinatorState()

        let writeTask = Task.detached(priority: .utility) {
            do {
                try data.write(to: tempURL, options: .atomic)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                return Result<URL, Error>.success(destinationURL)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                return Result<URL, Error>.failure(error)
            }
        }

        Task { @MainActor [weak self] in
            let result = await writeTask.value
            if case .success = result {
                progress.markCompleted(byteCount: Int64(data.count))
                self?.coordinator.didUpdateProgress(progress, for: item)
            }
            self?.finishDownloadedData(item, result: result)
        }
    }

    func beginExternalDownload(
        originalURL: URL,
        websiteURL: URL?,
        suggestedFilename: String,
        sourceProgress: Progress?,
        flyAnimationOriginalRect: NSRect? = nil
    ) -> DownloadItem {
        let destinationURL = DownloadFileUtilities.uniqueDestination(for: suggestedFilename)
        let progress = sourceProgress.map {
            DownloadProgress(sourceProgress: $0, sourceURL: originalURL)
        } ?? DownloadProgress(totalUnitCount: -1)
        progress.fileDownloadingSourceURL = originalURL
        configureSystemPresentation(
            progress: progress,
            destinationURL: destinationURL,
            flyAnimationOriginalRect: flyAnimationOriginalRect
        )

        let item = DownloadItem(
            downloadURL: originalURL,
            websiteURL: websiteURL,
            fileName: destinationURL.lastPathComponent,
            destinationURL: destinationURL,
            state: .downloading,
            progress: progress,
            completedUnitCount: progress.completedUnitCount,
            totalUnitCount: progress.totalUnitCount
        )
        coordinator.track(item, progress: progress)
        publishCoordinatorState()
        return item
    }

    func finishExternalDownload(
        _ item: DownloadItem,
        temporaryURL: URL,
        response _: URLResponse?,
        completion: ((Result<URL, Error>) -> Void)? = nil
    ) {
        let destinationURL = item.destinationURL ?? DownloadFileUtilities.uniqueDestination(for: item.fileName)
        let progress = item.progress
        let moveTask = Task.detached(priority: .utility) {
            let finalURL = DownloadFileUtilities.uniqueURL(for: destinationURL)
            do {
                try FileManager.default.createDirectory(
                    at: finalURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try FileManager.default.removeItem(at: finalURL)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
                return Result<URL, Error>.success(finalURL)
            } catch {
                return Result<URL, Error>.failure(error)
            }
        }

        Task { @MainActor [weak self] in
            let result = await moveTask.value
            if case .success(let finalURL) = result {
                let byteCount = (try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
                progress?.markCompleted(byteCount: byteCount)
                if let progress {
                    self?.coordinator.didUpdateProgress(progress, for: item)
                }
            }
            self?.finishDownloadedData(item, result: result)
            completion?(result)
        }
    }

    func failExternalDownload(_ item: DownloadItem?, error: Error) {
        guard let item else { return }
        coordinator.didFail(
            item,
            error: .failed(message: error.localizedDescription, resumeData: nil, isRetryable: false)
        )
        publishCoordinatorState()
    }

    func cancelExternalDownload(_ item: DownloadItem?) {
        guard let item else { return }
        coordinator.didFail(item, error: .cancelled)
        publishCoordinatorState()
    }

    func cancel(_ item: DownloadItem) {
        coordinator.cancel(item)
    }

    func retry(_ item: DownloadItem) {
        guard item.canRetry || item.state == .failed else { return }
        guard let webView = retryWebView() else {
            item.error = .failed(
                message: "Open a browser tab to retry this download.",
                resumeData: item.error?.resumeData,
                isRetryable: item.error?.resumeData != nil
            )
            publishCoordinatorState()
            return
        }

        let resumeData = item.error?.resumeData
        coordinator.prepareRetry(item)
        let callback: @MainActor @Sendable (WKDownload) -> Void = { [weak self, weak webView] download in
            guard let self else { return }
            withExtendedLifetime(webView) {
                self.coordinator.attach(download: download, to: item)
                self.publishCoordinatorState()
            }
        }

        if let resumeData {
            webView.resumeDownload(fromResumeData: resumeData, completionHandler: callback)
        } else {
            webView.startDownload(using: URLRequest(url: item.downloadURL), completionHandler: callback)
        }
    }

    func open(_ item: DownloadItem) {
        guard let url = item.localURL,
              FileManager.default.fileExists(atPath: url.path)
        else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ item: DownloadItem) {
        guard let url = item.destinationURL,
              FileManager.default.fileExists(atPath: url.path)
        else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openDownloadsFolder() {
        DownloadFileUtilities.openDownloadsFolder()
    }

    func clearInactiveDownloads() {
        coordinator.clearInactiveDownloads()
        publishCoordinatorState()
    }

    fileprivate func finishDownloadedData(_ item: DownloadItem, result: Result<URL, Error>) {
        switch result {
        case .success(let destinationURL):
            coordinator.didFinish(item, finalURL: destinationURL)
        case .failure(let error):
            coordinator.didFail(item, error: .moveFailed(message: error.localizedDescription))
        }
        publishCoordinatorState()
    }

    private func retryWebView() -> WKWebView? {
        if let current = browserManager?.currentTabForActiveWindow()?.existingWebView {
            return current
        }
        return browserManager?.currentTabForActiveWindow()?.ensureWebView()
    }

    private func publishCoordinatorState() {
        items = coordinator.items
        publishDerivedState()
    }

    private func publishDerivedState() {
        activeDownloadCount = items.filter(\.isActive).count
        combinedProgressFraction = {
            let active = items.filter(\.isActive)
            guard !active.isEmpty else { return nil }
            var total: Int64 = 0
            var completed: Int64 = 0
            for item in active where item.totalUnitCount > 0 {
                total += item.totalUnitCount
                completed += max(item.completedUnitCount, 0)
            }
            guard total > 0 else { return -1 }
            return min(max(Double(completed) / Double(total), 0), 1)
        }()
    }

    private func configureSystemPresentation(
        progress: DownloadProgress,
        destinationURL: URL,
        flyAnimationOriginalRect: NSRect?
    ) {
        guard let flyAnimationOriginalRect else { return }

        let fileType = UTType(filenameExtension: destinationURL.pathExtension) ?? .data
        let icon = NSWorkspace.shared.icon(for: fileType)
        progress.flyToImage = icon
        progress.fileIcon = icon
        progress.fileIconOriginalRect = flyAnimationOriginalRect
    }
}
