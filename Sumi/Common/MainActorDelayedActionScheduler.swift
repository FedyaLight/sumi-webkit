import Foundation

@MainActor
struct MainActorDelayedActionScheduler {
    typealias Cancellation = @MainActor () -> Void
    typealias Schedule = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> Cancellation

    private let scheduleAction: Schedule

    init(schedule: @escaping Schedule) {
        scheduleAction = schedule
    }

    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> Cancellation {
        scheduleAction(delay, action)
    }

    static var live: MainActorDelayedActionScheduler {
        MainActorDelayedActionScheduler { delay, action in
            let task = Task { @MainActor in
                let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
                if nanoseconds > 0 {
                    do {
                        try await Task.sleep(nanoseconds: nanoseconds)
                    } catch {
                        return
                    }
                }
                guard !Task.isCancelled else { return }
                action()
            }
            return {
                task.cancel()
            }
        }
    }
}
