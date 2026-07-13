import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class SumiDownloadProgressPublisher: DownloadProgressPublishing {
    func makePublication(
        source: DownloadProgressSource,
        sourceURL: URL,
        onUpdate: @escaping @MainActor (DownloadProgressSnapshot) -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onTemporaryFileRemoved: @escaping @MainActor () -> Void
    ) -> any DownloadProgressPublication {
        SumiDownloadProgressPublication(
            source: source,
            sourceURL: sourceURL,
            onUpdate: onUpdate,
            onCancel: onCancel,
            onTemporaryFileRemoved: onTemporaryFileRemoved
        )
    }
}

@MainActor
private final class SumiDownloadProgressPublication: DownloadProgressPublication {
    let progress: DownloadProgress

    private let onUpdate: @MainActor (DownloadProgressSnapshot) -> Void
    private let onCancel: @MainActor () -> Void
    private let onTemporaryFileRemoved: @MainActor () -> Void
    private var progressPresenter: DownloadFileProgressPresenter?
    private var temporaryFilePresenter: DownloadFilePresenter?
    private var cancellable: AnyCancellable?
    private var isStopped = false

    init(
        source: DownloadProgressSource,
        sourceURL: URL,
        onUpdate: @escaping @MainActor (DownloadProgressSnapshot) -> Void,
        onCancel: @escaping @MainActor () -> Void,
        onTemporaryFileRemoved: @escaping @MainActor () -> Void
    ) {
        switch source {
        case .progress(let sourceProgress):
            self.progress = DownloadProgress(
                sourceProgress: sourceProgress,
                sourceURL: sourceURL
            )
        case .totalUnitCount(let totalUnitCount):
            self.progress = DownloadProgress(totalUnitCount: totalUnitCount)
            self.progress.fileDownloadingSourceURL = sourceURL
        }
        self.onUpdate = onUpdate
        self.onCancel = onCancel
        self.onTemporaryFileRemoved = onTemporaryFileRemoved
        self.progress.cancellationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isStopped else { return }
                self.onCancel()
            }
        }
        cancellable = Publishers.CombineLatest(
            progress.publisher(for: \.totalUnitCount),
            progress.publisher(for: \.completedUnitCount)
        )
        .dropFirst()
        .throttle(for: .milliseconds(200), scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.publishSnapshot()
            }
        }
    }

    var snapshot: DownloadProgressSnapshot {
        DownloadProgressSnapshot(
            completedUnitCount: progress.completedUnitCount,
            totalUnitCount: progress.totalUnitCount,
            throughput: progress.throughput,
            estimatedTimeRemaining: progress.estimatedTimeRemaining
        )
    }

    func publishFile(
        at temporaryURL: URL,
        destinationURL: URL,
        responseMIMEType: String?,
        flyAnimationOriginalRect: NSRect?
    ) {
        guard !isStopped else { return }
        progress.fileURL = temporaryURL

        if let flyAnimationOriginalRect {
            let fileType = UTType(filenameExtension: destinationURL.pathExtension)
                ?? responseMIMEType.flatMap(Self.fileType(forMIMEType:))
                ?? .data
            let icon = NSWorkspace.shared.icon(for: fileType)
            progress.flyToImage = icon
            progress.fileIcon = icon
            progress.fileIconOriginalRect = flyAnimationOriginalRect
        }

        let presenter = DownloadFileProgressPresenter(progress: progress)
        presenter.displayProgress(at: temporaryURL)
        progressPresenter = presenter
        temporaryFilePresenter = DownloadFilePresenter(url: temporaryURL) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isStopped else { return }
                self.onTemporaryFileRemoved()
            }
        }
    }

    func markCompleted(byteCount: Int64?) {
        guard !isStopped else { return }
        progress.markCompleted(byteCount: byteCount)
        publishSnapshot()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        cancellable?.cancel()
        cancellable = nil
        progressPresenter = nil
        temporaryFilePresenter = nil
    }

    private func publishSnapshot() {
        guard !isStopped else { return }
        onUpdate(snapshot)
    }

    private static func fileType(forMIMEType mimeType: String) -> UTType? {
        let normalized = mimeType
            .split(separator: ";", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, !normalized.isEmpty else { return nil }
        return UTType.types(
            tag: normalized,
            tagClass: .mimeType,
            conformingTo: nil
        ).first
    }
}
