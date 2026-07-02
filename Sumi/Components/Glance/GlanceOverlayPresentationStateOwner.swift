import Foundation

@MainActor
final class GlanceOverlayPresentationStateOwner {
    struct PendingPresentation {
        let session: GlanceSession
        let configuration: GlanceOverlayConfiguration
    }

    private(set) var displayedSessionID: UUID?
    private(set) var isAnimatingClose = false
    private(set) var isPresentationVisible = false
    private var pendingPresentation: PendingPresentation?
    private var closeConfirmationWorkItem: DispatchWorkItem?
    private var postAnimationCompletionTask: Task<Void, Never>?

    var pendingPresentationSessionID: UUID? {
        pendingPresentation?.session.id
    }

    func display(sessionID: UUID) {
        displayedSessionID = sessionID
    }

    func resetForMissingSession() {
        cancelPostAnimationCompletion()
        clearPendingPresentation()
        isAnimatingClose = false
        isPresentationVisible = false
        displayedSessionID = nil
    }

    func prepareForTearDown() {
        cancelPostAnimationCompletion()
        cancelCloseConfirmationReset()
        clearPendingPresentation()
        isAnimatingClose = false
    }

    func queuePendingPresentation(
        session: GlanceSession,
        configuration: GlanceOverlayConfiguration
    ) {
        pendingPresentation = PendingPresentation(session: session, configuration: configuration)
    }

    func takePendingPresentation() -> PendingPresentation? {
        defer { pendingPresentation = nil }
        return pendingPresentation
    }

    func clearPendingPresentation() {
        pendingPresentation = nil
    }

    func beginOpening() {
        cancelPostAnimationCompletion()
        isAnimatingClose = false
        isPresentationVisible = true
    }

    func beginClosing() {
        cancelPostAnimationCompletion()
        isAnimatingClose = true
    }

    func finishClosing() {
        isAnimatingClose = false
    }

    func setPresentationVisible(_ isVisible: Bool) {
        isPresentationVisible = isVisible
        if !isVisible {
            cancelPostAnimationCompletion()
            isAnimatingClose = false
        }
    }

    func schedulePostAnimationCompletion(
        sessionID: UUID,
        after duration: TimeInterval,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        cancelPostAnimationCompletion()
        postAnimationCompletionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.nanoseconds(for: duration))
            guard !Task.isCancelled,
                  let self,
                  self.displayedSessionID == sessionID
            else { return }

            completion()
            self.postAnimationCompletionTask = nil
        }
    }

    func cancelPostAnimationCompletion() {
        postAnimationCompletionTask?.cancel()
        postAnimationCompletionTask = nil
    }

    func installCloseConfirmationReset(_ item: DispatchWorkItem) {
        closeConfirmationWorkItem = item
    }

    func cancelCloseConfirmationReset() {
        closeConfirmationWorkItem?.cancel()
        closeConfirmationWorkItem = nil
    }

    private static func nanoseconds(for duration: TimeInterval) -> UInt64 {
        UInt64(max(0, duration) * 1_000_000_000)
    }
}
