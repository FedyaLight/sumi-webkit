import Foundation

@MainActor
final class GlancePromotionCompletionOwner {
    static let fallbackDelay: TimeInterval = 1

    private struct PendingPromotion: Equatable {
        let sessionID: UUID
        let generation: UInt64
    }

    private let delayedActions: MainActorDelayedActionScheduler
    private var pendingPromotion: PendingPromotion?
    private var cancelFallback: MainActorDelayedActionScheduler.Cancellation?
    private var nextGeneration: UInt64 = 0

    init(delayedActions: MainActorDelayedActionScheduler = .live) {
        self.delayedActions = delayedActions
    }

    var isAwaitingAttachment: Bool {
        pendingPromotion != nil
    }

    isolated deinit {
        cancelFallback?()
    }

    func beginAwaitingAttachment(
        sessionID: UUID,
        onFallback: @escaping @MainActor () -> Void
    ) {
        nextGeneration &+= 1
        let pendingPromotion = PendingPromotion(
            sessionID: sessionID,
            generation: nextGeneration
        )
        self.pendingPromotion = pendingPromotion
        cancelFallback?()
        cancelFallback = delayedActions.schedule(
            after: Self.fallbackDelay
        ) { [weak self] in
            guard let self,
                  self.pendingPromotion == pendingPromotion
            else { return }

            self.pendingPromotion = nil
            self.cancelFallback = nil
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
        cancelFallback?()
        cancelFallback = nil
    }
}
