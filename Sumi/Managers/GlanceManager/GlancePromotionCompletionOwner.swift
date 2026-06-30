import Foundation

@MainActor
final class GlancePromotionCompletionOwner {
    static let fallbackDelayNanoseconds: UInt64 = 1_000_000_000

    private struct PendingPromotion: Equatable {
        let sessionID: UUID
        let generation: UInt64
    }

    private var pendingPromotion: PendingPromotion?
    private var fallbackTask: Task<Void, Never>?
    private var nextGeneration: UInt64 = 0

    var isAwaitingAttachment: Bool {
        pendingPromotion != nil
    }

    deinit {
        fallbackTask?.cancel()
    }

    func beginAwaitingAttachment(
        sessionID: UUID,
        fallbackDelayNanoseconds: UInt64 = GlancePromotionCompletionOwner.fallbackDelayNanoseconds,
        onFallback: @escaping @MainActor () -> Void
    ) {
        nextGeneration &+= 1
        let pendingPromotion = PendingPromotion(
            sessionID: sessionID,
            generation: nextGeneration
        )
        self.pendingPromotion = pendingPromotion
        fallbackTask?.cancel()
        fallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: fallbackDelayNanoseconds)
            guard !Task.isCancelled,
                  let self,
                  self.pendingPromotion == pendingPromotion
            else { return }

            self.pendingPromotion = nil
            self.fallbackTask = nil
            onFallback()
        }
    }

    @discardableResult
    func completeAttachment(sessionID: UUID) -> Bool {
        guard pendingPromotion?.sessionID == sessionID else { return false }
        cancel()
        return true
    }

    func cancel() {
        nextGeneration &+= 1
        pendingPromotion = nil
        fallbackTask?.cancel()
        fallbackTask = nil
    }
}
