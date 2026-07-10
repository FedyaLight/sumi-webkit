import Foundation

@MainActor
final class ProactiveTabSuspensionLifecycle {
    private let contextSource: TabSuspensionContextSource
    private let executor: TabSuspensionExecutor
    private let suspensionClock: SumiSuspensionClock
    private let timerSleep: (TimeInterval) async throws -> Void
    private var catalogRuntime: TabSuspensionCatalogRuntime = .inactive
    private var isAttached = false
    private var visibilityLedger = TabSuspensionVisibilityLedger()
    private var timerScheduler: ProactiveTabSuspensionTimerScheduler?
    private var reconcileScheduler: TabSuspensionReconcileScheduler?

#if DEBUG
    var scheduledTimerDeadlineForTesting: TimeInterval? {
        timerScheduler?.scheduledDeadlineLiveUptimeForTesting
    }
#endif

    init(
        contextSource: TabSuspensionContextSource,
        executor: TabSuspensionExecutor,
        suspensionClock: SumiSuspensionClock = SumiSystemSuspensionClock(),
        timerSleep: @escaping (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(
                nanoseconds: UInt64(max(interval, 0) * 1_000_000_000)
            )
        }
    ) {
        self.contextSource = contextSource
        self.executor = executor
        self.suspensionClock = suspensionClock
        self.timerSleep = timerSleep
    }

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }

    func start(runtime: TabSuspensionCatalogRuntime) {
        precondition(!isAttached, "Proactive tab suspension runtime can only start once")
        catalogRuntime = runtime
        isAttached = true
        reconcile(reason: "attach")
    }

    func stop() {
        guard isAttached || reconcileScheduler != nil || timerScheduler != nil else { return }
        isAttached = false
        reconcileScheduler?.cancel()
        reconcileScheduler = nil
        cancelAllTimers()
        visibilityLedger = TabSuspensionVisibilityLedger()
        catalogRuntime = .inactive
    }

    func scheduleReconcile(reason: String) {
        guard isAttached else { return }
        ensureReconcileScheduler().schedule(reason: reason)
    }

    func reconcile(reason: String) {
        guard isAttached else { return }
        let tabs = catalogRuntime.allKnownTabs()
        let knownTabIDs = Set(tabs.map(\.id))
        for tabID in timerScheduler?.timerIDs ?? [] where !knownTabIDs.contains(tabID) {
            cancelTimer(for: tabID)
        }
        visibilityLedger.retainTabs(withIDs: knownTabIDs)

        let context = contextSource.context()
        for tab in tabs {
            if context.selectedTabIDs.contains(tab.id) || context.visibleTabIDs.contains(tab.id) {
                noteVisible(tab)
            } else {
                noteHidden(tab, context: context)
            }
        }
        catalogRuntime.refreshLazyRestoreQueue(context)

        RuntimeDiagnostics.debug(category: "TabSuspension") {
            "reconciled proactive timers reason=\(reason) active=\(activeTimerCount)"
        }
    }

    func rebuild(reason: String) {
        guard isAttached else { return }
        cancelAllTimers()

        let tabs = catalogRuntime.allKnownTabs()
        let knownTabIDs = Set(tabs.map(\.id))
        visibilityLedger.retainTabs(withIDs: knownTabIDs)

        let now = suspensionClock.liveUptime
        let context = contextSource.context()
        for tab in tabs {
            if context.selectedTabIDs.contains(tab.id) || context.visibleTabIDs.contains(tab.id) {
                noteVisible(tab)
                continue
            }
            visibilityLedger.restartHiddenInterval(for: tab.id, at: now)
            noteHidden(tab, context: context)
        }

        RuntimeDiagnostics.debug(category: "TabSuspension") {
            "rebuilt proactive timers reason=\(reason) active=\(activeTimerCount)"
        }
    }

    func resetRevisitProtection(for tab: Tab) {
        guard isAttached else { return }
        visibilityLedger.resetRevisitCount(for: tab.id)
        cancelTimer(for: tab.id)

        let context = contextSource.context()
        guard !context.selectedTabIDs.contains(tab.id),
              !context.visibleTabIDs.contains(tab.id)
        else { return }

        visibilityLedger.restartHiddenInterval(
            for: tab.id,
            at: suspensionClock.liveUptime
        )
        noteHidden(tab, context: context)
    }

    func discardHiddenTrackingAfterSuspension(tabID: UUID) {
        cancelTimer(for: tabID)
        visibilityLedger.removeHiddenState(for: tabID)
    }

    private func noteVisible(_ tab: Tab) {
        cancelTimer(for: tab.id)
        visibilityLedger.noteVisible(tabID: tab.id)
    }

    private func noteHidden(
        _ tab: Tab,
        context: TabSuspensionEvaluationContext
    ) {
        let hiddenStartedAt = visibilityLedger.hiddenStart(
            for: tab.id,
            defaultingTo: suspensionClock.liveUptime
        )

        guard timerScheduler?.containsTimer(for: tab.id) != true else { return }
        guard visibilityLedger.revisitCount(for: tab.id)
            <= context.policy.revisitProtectionLimit
        else { return }
        guard executor.eligibility(for: tab, context: context).isEligible else { return }

        armTimer(
            for: tab.id,
            hiddenStartedAtLiveUptime: hiddenStartedAt,
            requestedDelay: context.policy.proactiveDeactivationDelay
        )
    }

    private func armTimer(
        for tabID: UUID,
        hiddenStartedAtLiveUptime: TimeInterval,
        requestedDelay: TimeInterval
    ) {
        cancelTimer(for: tabID)
        visibilityLedger.restartHiddenInterval(
            for: tabID,
            at: hiddenStartedAtLiveUptime
        )
        ensureTimerScheduler().armTimer(
            for: tabID,
            requestedDelay: requestedDelay,
            hiddenStartedAtLiveUptime: visibilityLedger.hiddenStart(for:)
        )
    }

    private func handleDueTimers() {
        guard let timerScheduler else { return }
        let dueTimers = timerScheduler.dueTimers(
            hiddenStartedAtLiveUptime: visibilityLedger.hiddenStart(for:)
        )

        for dueTimer in dueTimers {
            handleTimerFired(dueTimer)
        }

        timerScheduler.schedule(
            hiddenStartedAtLiveUptime: visibilityLedger.hiddenStart(for:)
        )
        releaseTimerSchedulerIfIdle()
    }

    private func handleTimerFired(_ dueTimer: ProactiveTabSuspensionTimerScheduler.DueTimer) {
        timerScheduler?.removeTimerWithoutScheduling(for: dueTimer.tabID)

        let elapsed = max(
            0,
            suspensionClock.liveUptime - dueTimer.hiddenStartedAtLiveUptime
        )
        if elapsed + 0.001 < dueTimer.requestedDelay {
            armTimer(
                for: dueTimer.tabID,
                hiddenStartedAtLiveUptime: dueTimer.hiddenStartedAtLiveUptime,
                requestedDelay: dueTimer.requestedDelay
            )
            return
        }

        guard let tab = catalogRuntime.allKnownTabs().first(where: {
            $0.id == dueTimer.tabID
        }) else { return }

        let context = contextSource.context()
        guard !context.selectedTabIDs.contains(tab.id),
              !context.visibleTabIDs.contains(tab.id)
        else {
            noteVisible(tab)
            return
        }
        guard executor.eligibility(for: tab, context: context).isEligible else { return }

        if executor.suspend(
            tab,
            reason: "proactive-\(context.policy.memoryMode.rawValue)",
            context: context
        ) {
            visibilityLedger.removeHiddenState(for: tab.id)
        }
    }

    private func cancelTimer(for tabID: UUID) {
        guard let timerScheduler,
              timerScheduler.cancelTimer(
                  for: tabID,
                  hiddenStartedAtLiveUptime: visibilityLedger.hiddenStart(for:)
              )
        else { return }
        releaseTimerSchedulerIfIdle()
    }

    private func cancelAllTimers() {
        timerScheduler?.cancelAllTimers()
        timerScheduler = nil
    }

    private var activeTimerCount: Int {
        timerScheduler?.activeTimerCount ?? 0
    }

    private func ensureTimerScheduler() -> ProactiveTabSuspensionTimerScheduler {
        if let timerScheduler {
            return timerScheduler
        }
        let scheduler = ProactiveTabSuspensionTimerScheduler(
            suspensionClock: suspensionClock,
            timerSleep: timerSleep,
            handleDueTimers: { [weak self] in
                self?.handleDueTimers()
            }
        )
        timerScheduler = scheduler
        return scheduler
    }

    private func releaseTimerSchedulerIfIdle() {
        if timerScheduler?.isIdle == true {
            timerScheduler = nil
        }
    }

    private func ensureReconcileScheduler() -> TabSuspensionReconcileScheduler {
        if let reconcileScheduler {
            return reconcileScheduler
        }
        let scheduler = TabSuspensionReconcileScheduler { [weak self] reason in
            self?.reconcile(reason: reason)
        }
        reconcileScheduler = scheduler
        return scheduler
    }

}
