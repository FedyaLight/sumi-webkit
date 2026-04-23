import AppKit
import Combine
import Foundation
import WebKit

struct DownloadDestinationReservation: Equatable {
    let fileName: String
    let destinationURL: URL
    let tempURL: URL
}

@MainActor
final class DownloadListCoordinator {
    private var tasks: [UUID: SumiWebKitDownloadTask] = [:]
    private var progressSubscriptions: [UUID: AnyCancellable] = [:]
    private var reservedDestinationPaths: Set<String> = []

    private(set) var items: [DownloadItem]
    var onChange: (() -> Void)?

    init() {
        self.items = []
    }

    var activeItems: [DownloadItem] {
        items.filter(\.isActive)
    }

    var activeCount: Int {
        activeItems.count
    }

    var combinedProgressFraction: Double? {
        let active = activeItems
        guard !active.isEmpty else { return nil }

        var knownCompleted: Int64 = 0
        var knownTotal: Int64 = 0
        var hasIndeterminate = false

        for item in active {
            if item.totalUnitCount > 0 {
                knownCompleted += max(item.completedUnitCount, 0)
                knownTotal += item.totalUnitCount
            } else {
                hasIndeterminate = true
            }
        }

        guard knownTotal > 0 else { return -1 }
        if hasIndeterminate, knownCompleted == 0 { return -1 }
        return min(max(Double(knownCompleted) / Double(knownTotal), 0), 1)
    }

    func start(
        download: WKDownload,
        originalURL: URL,
        websiteURL: URL?,
        suggestedFilename: String,
        flyAnimationOriginalRect: NSRect?
    ) -> DownloadItem {
        let item = DownloadItem(
            downloadURL: originalURL,
            websiteURL: websiteURL,
            fileName: DownloadFileUtilities.sanitizedFilename(suggestedFilename)
        )
        upsert(item)
        attach(download: download, to: item, flyAnimationOriginalRect: flyAnimationOriginalRect)
        notify()
        return item
    }

    func attach(download: WKDownload, to item: DownloadItem, flyAnimationOriginalRect: NSRect? = nil) {
        let task = SumiWebKitDownloadTask(
            download: download,
            item: item,
            coordinator: self,
            flyAnimationOriginalRect: flyAnimationOriginalRect
        )
        tasks[item.id] = task
        task.start()
    }

    func track(_ item: DownloadItem) {
        upsert(item)
        notify()
    }

    func track(_ item: DownloadItem, progress: DownloadProgress) {
        item.progress = progress
        mirrorProgress(progress, to: item)
        item.state = .downloading
        upsert(item)
        observeRuntimeProgress(progress, for: item)
        notify()
    }

    func cancel(_ item: DownloadItem) {
        tasks[item.id]?.cancel()
    }

    func prepareRetry(_ item: DownloadItem) {
        releaseReservation(for: item)
        progressSubscriptions[item.id] = nil
        item.state = .pending
        item.error = nil
        item.progress = nil
        item.completedUnitCount = 0
        if item.totalUnitCount <= 0 {
            item.totalUnitCount = -1
        }
        item.throughput = nil
        item.estimatedTimeRemaining = nil
        upsert(item)
        notify()
    }

    func didAttachProgress(_ progress: DownloadProgress, for item: DownloadItem) {
        item.progress = progress
        mirrorProgress(progress, to: item)
        item.state = .downloading
        notify()
    }

    func reserveDestination(
        for item: DownloadItem,
        response: URLResponse?,
        suggestedFilename: String
    ) -> DownloadDestinationReservation {
        if let destinationURL = item.destinationURL,
           let tempURL = item.tempURL,
           !reservedDestinationPaths.contains(destinationURL.path) {
            reservedDestinationPaths.insert(destinationURL.path)
            return DownloadDestinationReservation(
                fileName: destinationURL.lastPathComponent,
                destinationURL: destinationURL,
                tempURL: tempURL
            )
        }

        let responseFilename = DownloadFileUtilities.suggestedFilename(
            response: response,
            requestURL: item.downloadURL,
            fallback: suggestedFilename.isEmpty ? item.fileName : suggestedFilename
        )
        let cleanName = DownloadFileUtilities.sanitizedFilename(responseFilename)
        let destinationURL = uniqueReservedDestination(for: cleanName)
        reservedDestinationPaths.insert(destinationURL.path)

        return DownloadDestinationReservation(
            fileName: destinationURL.lastPathComponent,
            destinationURL: destinationURL,
            tempURL: DownloadFileUtilities.incompleteURL(for: destinationURL)
        )
    }

    func didChooseDestination(
        _ reservation: DownloadDestinationReservation,
        for item: DownloadItem,
        response: URLResponse?
    ) {
        item.fileName = reservation.fileName
        item.destinationURL = reservation.destinationURL
        item.tempURL = reservation.tempURL
        item.state = .downloading
        if let response, response.expectedContentLength > 0 {
            item.totalUnitCount = response.expectedContentLength
        }
        notify()
    }

    func didReceiveResponse(_ response: URLResponse, for item: DownloadItem) {
        item.state = .downloading
        if response.expectedContentLength > 0 {
            item.totalUnitCount = response.expectedContentLength
        }
        notify()
    }

    func didUpdateProgress(_ progress: Progress, for item: DownloadItem) {
        if let downloadProgress = progress as? DownloadProgress {
            item.progress = downloadProgress
        }
        item.state = .downloading
        mirrorProgress(progress, to: item)
        notify()
    }

    func didUpdateProgress(
        totalUnitCount: Int64,
        completedUnitCount: Int64,
        throughput: Int?,
        estimatedTimeRemaining: TimeInterval?,
        for item: DownloadItem
    ) {
        item.state = .downloading
        item.totalUnitCount = totalUnitCount
        item.completedUnitCount = completedUnitCount
        item.throughput = throughput
        item.estimatedTimeRemaining = estimatedTimeRemaining
        notify()
    }

    func didFinish(_ item: DownloadItem, finalURL: URL) {
        let reservedDestinationURL = item.destinationURL
        item.destinationURL = finalURL
        item.tempURL = nil
        item.fileName = finalURL.lastPathComponent
        item.completedUnitCount = max(item.completedUnitCount, item.totalUnitCount)
        if item.totalUnitCount <= 0,
           let size = try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            item.totalUnitCount = Int64(size)
            item.completedUnitCount = Int64(size)
        }
        item.state = .completed
        item.error = nil
        item.progress = nil
        tasks[item.id] = nil
        progressSubscriptions[item.id] = nil
        releaseReservation(for: reservedDestinationURL)
        notify()
    }

    func didFail(_ item: DownloadItem, error: DownloadError) {
        switch error {
        case .cancelled:
            item.state = .cancelled
        case .failed, .moveFailed:
            item.state = .failed
        }
        item.error = error
        item.progress = nil
        tasks[item.id] = nil
        progressSubscriptions[item.id] = nil
        releaseReservation(for: item)
        notify()
    }

    func remove(_ item: DownloadItem) {
        tasks[item.id]?.cancel()
        tasks[item.id] = nil
        progressSubscriptions[item.id] = nil
        releaseReservation(for: item)
        cleanupTemporaryFile(for: item)
        items.removeAll { $0.id == item.id }
        notify()
    }

    func clearInactiveDownloads() {
        let inactiveIDs = Set(items.filter { !$0.isActive }.map(\.id))
        guard !inactiveIDs.isEmpty else { return }

        for item in items where inactiveIDs.contains(item.id) {
            tasks[item.id] = nil
            progressSubscriptions[item.id] = nil
            releaseReservation(for: item)
            cleanupTemporaryFile(for: item)
        }

        items.removeAll { inactiveIDs.contains($0.id) }
        notify()
    }

    private func upsert(_ item: DownloadItem) {
        if items.contains(where: { $0.id == item.id }) == false {
            items.insert(item, at: 0)
        }
        sortItems()
    }

    private func mirrorProgress(_ progress: Progress, to item: DownloadItem) {
        item.totalUnitCount = progress.totalUnitCount
        item.completedUnitCount = progress.completedUnitCount
        item.throughput = progress.throughput
        item.estimatedTimeRemaining = progress.estimatedTimeRemaining
    }

    private func observeRuntimeProgress(_ progress: DownloadProgress, for item: DownloadItem) {
        progressSubscriptions[item.id] = Publishers.CombineLatest(
            progress.publisher(for: \.totalUnitCount),
            progress.publisher(for: \.completedUnitCount)
        )
        .dropFirst()
        .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self, weak item] _, _ in
            Task { @MainActor in
                guard let self, let item else { return }
                self.didUpdateProgress(progress, for: item)
            }
        }
    }

    private func sortItems() {
        items.sort { lhs, rhs in
            if lhs.added != rhs.added {
                return lhs.added > rhs.added
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func uniqueReservedDestination(for filename: String) -> URL {
        let directory = DownloadsDirectoryResolver.resolvedDownloadsDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let cleanName = DownloadFileUtilities.sanitizedFilename(filename)
        let desired = directory.appendingPathComponent(cleanName)
        guard FileManager.default.fileExists(atPath: desired.path) || reservedDestinationPaths.contains(desired.path) else {
            return desired
        }

        let ext = desired.pathExtension
        let base = desired.deletingPathExtension().lastPathComponent
        var counter = 1
        while true {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path),
               !reservedDestinationPaths.contains(candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    private func releaseReservation(for item: DownloadItem) {
        releaseReservation(for: item.destinationURL)
    }

    private func releaseReservation(for destinationURL: URL?) {
        if let destinationURL {
            reservedDestinationPaths.remove(destinationURL.path)
        }
    }

    private func cleanupTemporaryFile(for item: DownloadItem) {
        guard !item.isActive, item.state != .completed, let tempURL = item.tempURL else { return }
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func notify() {
        onChange?()
    }
}
