import Foundation

@MainActor
final class TabSuspensionController {
    private enum LifecycleState: Equatable {
        case awaitingRuntime
        case running
        case stopped
    }

    private let contextSource: TabSuspensionContextSource
    private let executor: TabSuspensionExecutor
    private let proactiveLifecycle: ProactiveTabSuspensionLifecycle
    private let memoryPressureHandler: MemoryPressureTabSuspensionHandler
    private let memoryMonitor: SumiMemoryPressureMonitoring?
    private var lifecycleState: LifecycleState = .awaitingRuntime
    private var participantsAreRunning = false
    private var catalogRuntime: TabSuspensionCatalogRuntime = .inactive

#if DEBUG
    var scheduledTimerDeadlineForTesting: TimeInterval? {
        proactiveLifecycle.scheduledTimerDeadlineForTesting
    }

    var currentPolicyForTesting: TabSuspensionPolicy {
        contextSource.context().policy
    }
#endif

    init(
        memoryMonitor: SumiMemoryPressureMonitoring?,
        dateProvider: @escaping () -> Date = Date.init,
        suspensionClock: SumiSuspensionClock = SumiSystemSuspensionClock(),
        timerSleep: @escaping (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(
                nanoseconds: UInt64(max(interval, 0) * 1_000_000_000)
            )
        }
    ) {
        let contextSource = TabSuspensionContextSource()
        let executor = TabSuspensionExecutor(
            contextSource: contextSource,
            eligibilityEvaluator: TabSuspensionEligibilityEvaluator(),
            dateProvider: dateProvider
        )
        let proactiveLifecycle = ProactiveTabSuspensionLifecycle(
            contextSource: contextSource,
            executor: executor,
            suspensionClock: suspensionClock,
            timerSleep: timerSleep
        )

        self.contextSource = contextSource
        self.executor = executor
        self.proactiveLifecycle = proactiveLifecycle
        self.memoryPressureHandler = MemoryPressureTabSuspensionHandler(
            contextSource: contextSource,
            executor: executor,
            proactiveLifecycle: proactiveLifecycle,
            dateProvider: dateProvider
        )
        self.memoryMonitor = memoryMonitor
    }

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }

    func configurePolicy(
        using currentPolicy: @escaping @MainActor () -> TabSuspensionPolicy
    ) {
        contextSource.configurePolicy(using: currentPolicy)
        guard lifecycleState == .running else { return }
        applyPolicyActivation(reason: "policy-source-configured")
    }

    func install(runtime: TabSuspensionRuntimePorts) {
        precondition(
            lifecycleState == .awaitingRuntime,
            "Tab suspension runtime can only be installed once"
        )

        contextSource.attach(runtime: runtime.context)
        executor.attach(runtime: runtime.webView)
        memoryPressureHandler.install(runtime: runtime.catalog)
        catalogRuntime = runtime.catalog
        lifecycleState = .running
        applyPolicyActivation(reason: "runtime-installed")
    }

    func policyDidChange(reason: String) {
        guard lifecycleState == .running else { return }
        applyPolicyActivation(reason: reason)
    }

    func scheduleReconciliation(reason: String) {
        guard lifecycleState == .running, participantsAreRunning else { return }
        proactiveLifecycle.scheduleReconcile(reason: reason)
    }

    func reconcileNow(reason: String) {
        guard lifecycleState == .running, participantsAreRunning else { return }
        proactiveLifecycle.reconcile(reason: reason)
    }

    func navigationDidStart(for tab: Tab) {
        guard lifecycleState == .running, participantsAreRunning else { return }
        proactiveLifecycle.resetRevisitProtection(for: tab)
    }

    func globallyVisibleTabIDs() -> Set<UUID> {
        contextSource.globallyVisibleTabIDs()
    }

    private func startParticipants() {
        guard participantsAreRunning == false else { return }
        participantsAreRunning = true
        proactiveLifecycle.start(runtime: catalogRuntime)
        memoryMonitor?.eventHandler = { [weak self] level in
            guard self?.lifecycleState == .running,
                  self?.participantsAreRunning == true else { return }
            self?.memoryPressureHandler.handle(level)
        }
        memoryMonitor?.start()
    }

    private func stopParticipants() {
        guard participantsAreRunning else { return }
        participantsAreRunning = false
        memoryMonitor?.eventHandler = nil
        memoryMonitor?.stop()
        proactiveLifecycle.stop()
    }

    private func applyPolicyActivation(reason: String) {
        if contextSource.context().policy.isEnabled {
            if participantsAreRunning {
                proactiveLifecycle.rebuild(reason: reason)
            } else {
                startParticipants()
            }
        } else {
            stopParticipants()
        }
    }

    private func stop() {
        guard lifecycleState == .running else { return }
        lifecycleState = .stopped
        stopParticipants()
    }
}
