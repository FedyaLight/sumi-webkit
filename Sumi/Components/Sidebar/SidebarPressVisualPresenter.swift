//
//  SidebarPressVisualPresenter.swift
//  Sumi
//

import Foundation

/// Main-queue scheduling seam for press-visual timing, so tests can drive it
/// without real delays.
@MainActor
protocol SidebarPressVisualScheduling: AnyObject {
    /// Runs `work` on the next main-queue turn.
    func enqueue(_ work: @escaping @MainActor () -> Void)
    /// Runs `work` after `delay` seconds.
    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void)
}

@MainActor
final class SidebarMainQueuePressVisualScheduler: SidebarPressVisualScheduling {
    func enqueue(_ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated(work)
        }
    }

    func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated(work)
        }
    }
}

/// Window-local owner of the sidebar press visual and its minimum visibility.
///
/// Page Activation materializes a Cold Page synchronously inside the same
/// `mouseDown` that accepts the press, so no frame can be committed while that
/// work runs. The minimum-visibility clock therefore starts on the first
/// main-queue turn after the press is published — the earliest moment the
/// pressed frame can actually reach the screen — rather than at publication.
/// A release before that budget elapses is honored late; a drag, cancellation,
/// or a press on another item ends the visual at once.
@MainActor
final class SidebarPressVisualPresenter {
    var onChange: ((String?) -> Void)?

    private let minimumVisibleDuration: TimeInterval
    private let scheduler: any SidebarPressVisualScheduling
    private var publishedSourceID: String?
    private var isEndRequested = false
    private var hasMetMinimumVisibility = false
    private var generation = 0

    init(
        minimumVisibleDuration: TimeInterval =
            SidebarMotionPolicy.rowPressMinimumVisibleDuration,
        scheduler: any SidebarPressVisualScheduling =
            SidebarMainQueuePressVisualScheduler()
    ) {
        self.minimumVisibleDuration = minimumVisibleDuration
        self.scheduler = scheduler
    }

    /// Accepts a press visual for `sourceID`, replacing whatever is presented.
    func present(_ sourceID: String?) {
        invalidateScheduledWork()
        guard let sourceID else {
            publish(nil)
            return
        }
        publish(sourceID)
        startMinimumVisibilityClock()
    }

    /// Ends the press visual, but never before it has been presentable for the
    /// minimum visible duration.
    func endAfterMinimumVisibility() {
        guard publishedSourceID != nil else { return }
        guard !hasMetMinimumVisibility else {
            present(nil)
            return
        }
        isEndRequested = true
    }

    /// Ends the press visual now, discarding any pending minimum-visibility
    /// budget.
    func endImmediately() {
        present(nil)
    }

    private func startMinimumVisibilityClock() {
        let token = generation
        scheduler.enqueue { [weak self] in
            guard let self, self.generation == token else { return }
            self.scheduler.after(self.minimumVisibleDuration) { [weak self] in
                guard let self, self.generation == token else { return }
                self.hasMetMinimumVisibility = true
                guard self.isEndRequested else { return }
                self.present(nil)
            }
        }
    }

    private func invalidateScheduledWork() {
        generation &+= 1
        isEndRequested = false
        hasMetMinimumVisibility = false
    }

    private func publish(_ sourceID: String?) {
        guard publishedSourceID != sourceID else { return }
        publishedSourceID = sourceID
        onChange?(sourceID)
    }
}
