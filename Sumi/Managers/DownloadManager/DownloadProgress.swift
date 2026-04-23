import Combine
import Foundation
import WebKit

final class DownloadProgress: Progress, @unchecked Sendable {
    private enum Constants {
        static let remainingDownloadTimeEstimationDelay: TimeInterval = 1
        static let downloadSpeedSmoothingFactor = 0.1
    }

    private var unitsCompletedCancellable: AnyCancellable?
    private var startDate: Date?

    override init(parent parentProgressOrNil: Progress?, userInfo userInfoOrNil: [ProgressUserInfoKey: Any]? = nil) {
        super.init(parent: parentProgressOrNil, userInfo: userInfoOrNil)
        configureDefaults()
    }

    init(download: WKDownload) {
        super.init(parent: nil, userInfo: nil)
        configureDefaults()
        fileDownloadingSourceURL = download.originalRequest?.url

        bind(to: download.progress)
    }

    init(sourceProgress: Progress, sourceURL: URL?) {
        super.init(parent: nil, userInfo: nil)
        configureDefaults()
        fileDownloadingSourceURL = sourceURL
        bind(to: sourceProgress)
    }

    private func bind(to sourceProgress: Progress) {
        updateProgress(
            totalUnitCount: sourceProgress.totalUnitCount,
            completedUnitCount: sourceProgress.completedUnitCount
        )

        unitsCompletedCancellable = Publishers.CombineLatest(
            sourceProgress.publisher(for: \.totalUnitCount),
            sourceProgress.publisher(for: \.completedUnitCount)
        )
        .dropFirst()
        .sink { [weak self] total, completed in
            self?.updateProgress(totalUnitCount: total, completedUnitCount: completed)
        }
    }

    convenience init(totalUnitCount: Int64, completedUnitCount: Int64 = 0) {
        self.init(parent: nil, userInfo: nil)
        updateProgress(totalUnitCount: totalUnitCount, completedUnitCount: completedUnitCount)
    }

    func updateProgress(totalUnitCount total: Int64, completedUnitCount completed: Int64) {
        if totalUnitCount != total {
            totalUnitCount = total
        }
        completedUnitCount = completed

        guard completed > 0 else { return }
        guard let startDate else {
            startDate = Date()
            return
        }

        let elapsedTime = Date().timeIntervalSince(startDate)
        guard elapsedTime > Constants.remainingDownloadTimeEstimationDelay else { return }

        var smoothedThroughput = Double(completed) / elapsedTime
        if let previous = throughput.map(Double.init) {
            smoothedThroughput = Constants.downloadSpeedSmoothingFactor * smoothedThroughput
                + (1 - Constants.downloadSpeedSmoothingFactor) * previous
        }

        throughput = max(Int(smoothedThroughput), 0)
        if total > 0, smoothedThroughput > 0 {
            estimatedTimeRemaining = Double(total - completed) / smoothedThroughput
        }
    }

    func markCompleted(byteCount: Int64?) {
        let knownByteCount = max(byteCount ?? 0, totalUnitCount, completedUnitCount)
        let completed = max(knownByteCount, 1)
        updateProgress(totalUnitCount: completed, completedUnitCount: completed)
    }

    private func configureDefaults() {
        totalUnitCount = -1
        completedUnitCount = 0
        fileOperationKind = .downloading
        kind = .file
        isCancellable = true
    }
}
