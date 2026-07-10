import Foundation

protocol SumiSuspensionClock {
    var liveUptime: TimeInterval { get }
}

struct SumiSystemSuspensionClock: SumiSuspensionClock {
    var liveUptime: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

@MainActor
final class ProactiveTabSuspensionTimerScheduler {
    struct DueTimer: Equatable {
        let tabID: UUID
        let hiddenStartedAtLiveUptime: TimeInterval
        let requestedDelay: TimeInterval
    }

    private struct TimerState {
        let requestedDelay: TimeInterval
    }

    private let suspensionClock: SumiSuspensionClock
    private let timerSleep: (TimeInterval) async throws -> Void
    private let handleDueTimers: @MainActor () -> Void
    private var timers: [UUID: TimerState] = [:]
    private var schedulerTask: Task<Void, Never>?
    private var schedulerDeadlineLiveUptime: TimeInterval?
    private var schedulerGeneration = 0

    var activeTimerCount: Int {
        timers.count
    }

    var isIdle: Bool {
        timers.isEmpty && schedulerTask == nil
    }

    var timerIDs: [UUID] {
        Array(timers.keys)
    }

#if DEBUG
    var hasScheduledTaskForTesting: Bool {
        schedulerTask != nil
    }

    var scheduledDeadlineLiveUptimeForTesting: TimeInterval? {
        schedulerDeadlineLiveUptime
    }
#endif

    init(
        suspensionClock: SumiSuspensionClock,
        timerSleep: @escaping (TimeInterval) async throws -> Void,
        handleDueTimers: @escaping @MainActor () -> Void
    ) {
        self.suspensionClock = suspensionClock
        self.timerSleep = timerSleep
        self.handleDueTimers = handleDueTimers
    }

    deinit {
        schedulerTask?.cancel()
    }

    func containsTimer(for tabID: UUID) -> Bool {
        timers[tabID] != nil
    }

    func armTimer(
        for tabID: UUID,
        requestedDelay: TimeInterval,
        hiddenStartedAtLiveUptime: (UUID) -> TimeInterval?
    ) {
        timers[tabID] = TimerState(requestedDelay: requestedDelay)
        schedule(hiddenStartedAtLiveUptime: hiddenStartedAtLiveUptime)
    }

    @discardableResult
    func cancelTimer(
        for tabID: UUID,
        hiddenStartedAtLiveUptime: (UUID) -> TimeInterval?
    ) -> Bool {
        guard timers.removeValue(forKey: tabID) != nil else { return false }
        schedule(hiddenStartedAtLiveUptime: hiddenStartedAtLiveUptime)
        return true
    }

    func cancelAllTimers() {
        timers.removeAll()
        cancelSchedulerTask()
    }

    func removeTimerWithoutScheduling(for tabID: UUID) {
        timers.removeValue(forKey: tabID)
    }

    func dueTimers(
        hiddenStartedAtLiveUptime: (UUID) -> TimeInterval?
    ) -> [DueTimer] {
        removeOrphanedTimers(hiddenStartedAtLiveUptime: hiddenStartedAtLiveUptime)

        let now = suspensionClock.liveUptime
        return timers.compactMap { tabID, timerState -> DueTimer? in
            guard let hiddenStartedAt = hiddenStartedAtLiveUptime(tabID) else { return nil }
            let deadline = hiddenStartedAt + timerState.requestedDelay
            guard now + 0.001 >= deadline else { return nil }
            return DueTimer(
                tabID: tabID,
                hiddenStartedAtLiveUptime: hiddenStartedAt,
                requestedDelay: timerState.requestedDelay
            )
        }
    }

    func schedule(hiddenStartedAtLiveUptime: (UUID) -> TimeInterval?) {
        guard let nextDeadline = nextDeadline(
            hiddenStartedAtLiveUptime: hiddenStartedAtLiveUptime
        ) else {
            cancelSchedulerTask()
            return
        }

        if schedulerTask != nil,
           schedulerDeadlineLiveUptime == nextDeadline {
            return
        }

        schedulerTask?.cancel()
        schedulerGeneration += 1
        schedulerDeadlineLiveUptime = nextDeadline

        let generation = schedulerGeneration
        let sleepDelay = max(0, nextDeadline - suspensionClock.liveUptime)
        schedulerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.timerSleep(sleepDelay)
            } catch {
                return
            }
            guard !Task.isCancelled,
                  self.schedulerGeneration == generation
            else { return }

            self.schedulerTask = nil
            self.schedulerDeadlineLiveUptime = nil
            self.handleDueTimers()
        }
    }

    private func nextDeadline(
        hiddenStartedAtLiveUptime: (UUID) -> TimeInterval?
    ) -> TimeInterval? {
        timers.compactMap { tabID, timerState in
            guard let hiddenStartedAt = hiddenStartedAtLiveUptime(tabID) else { return nil }
            return hiddenStartedAt + timerState.requestedDelay
        }
        .min()
    }

    private func removeOrphanedTimers(
        hiddenStartedAtLiveUptime: (UUID) -> TimeInterval?
    ) {
        let orphanedTimerIDs = timers.keys.filter {
            hiddenStartedAtLiveUptime($0) == nil
        }
        for tabID in orphanedTimerIDs {
            timers.removeValue(forKey: tabID)
        }
    }

    private func cancelSchedulerTask() {
        schedulerTask?.cancel()
        schedulerTask = nil
        schedulerDeadlineLiveUptime = nil
        schedulerGeneration += 1
    }
}
