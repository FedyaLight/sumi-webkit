import Foundation

@MainActor
protocol PageLoadingIndicatorScheduling: AnyObject {
    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void)
}

@MainActor
final class MainQueuePageLoadingIndicatorScheduler: PageLoadingIndicatorScheduling {
    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated(work)
        }
    }
}

/// Keeps one browser-visible loading presentation alive across a short chain
/// of successive document navigations without changing their lifecycle truth.
@MainActor
final class PageLoadingIndicatorSession {
    static let defaultContinuationInterval: TimeInterval = 0.2

    private(set) var isPresenting = false

    private var sourceIsLoading = false
    private let continuationInterval: TimeInterval
    private let scheduler: any PageLoadingIndicatorScheduling
    private let onPresentationChange: @MainActor (Bool) -> Void
    private var generation = 0

    init(
        continuationInterval: TimeInterval = defaultContinuationInterval,
        scheduler: any PageLoadingIndicatorScheduling =
            MainQueuePageLoadingIndicatorScheduler(),
        onPresentationChange: @escaping @MainActor (Bool) -> Void
    ) {
        self.continuationInterval = continuationInterval
        self.scheduler = scheduler
        self.onPresentationChange = onPresentationChange
    }

    func observe(isLoading: Bool) {
        guard sourceIsLoading != isLoading else { return }

        sourceIsLoading = isLoading
        generation &+= 1

        if isLoading {
            publishPresentation(true)
            return
        }

        let settlementGeneration = generation
        scheduler.after(continuationInterval) { [weak self] in
            guard let self,
                  self.generation == settlementGeneration,
                  !self.sourceIsLoading
            else { return }

            self.publishPresentation(false)
        }
    }

    func invalidate() {
        generation &+= 1
        sourceIsLoading = false
        isPresenting = false
    }

    private func publishPresentation(_ isPresenting: Bool) {
        guard self.isPresenting != isPresenting else { return }
        self.isPresenting = isPresenting
        onPresentationChange(isPresenting)
    }
}
