import Combine
import Foundation

@MainActor
final class DownloadFileProgressPresenter {
    private let progress: Progress
    private(set) var fileProgress: Progress? {
        willSet {
            fileProgress?.unpublish()
        }
    }
    private var cancellables = Set<AnyCancellable>()

    init(progress: Progress) {
        self.progress = progress
    }

    func displayProgress(at url: URL?) {
        cancellables.removeAll(keepingCapacity: true)
        fileProgress = nil

        guard let url else { return }

        let published = Progress(copy: progress)
        published.fileURL = url
        published.cancellationHandler = { [weak progress] in
            progress?.cancel()
        }
        swap(&published.fileIconOriginalRect, &progress.fileIconOriginalRect)
        swap(&published.flyToImage, &progress.flyToImage)
        published.fileIcon = progress.fileIcon

        progress.publisher(for: \.totalUnitCount)
            .sink { [weak published] value in
                published?.totalUnitCount = value
            }
            .store(in: &cancellables)

        progress.publisher(for: \.completedUnitCount)
            .sink { [weak published] value in
                published?.completedUnitCount = value
            }
            .store(in: &cancellables)

        fileProgress = published
        published.publish()
    }

    deinit {
        fileProgress?.unpublish()
    }
}
