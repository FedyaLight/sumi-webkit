import Foundation

@MainActor
final class MemoryPressureTabSuspensionHandler {
    private static let minimumInactiveInterval: TimeInterval = 10 * 60

    private let dateProvider: () -> Date
    private let contextSource: TabSuspensionContextSource
    private let executor: TabSuspensionExecutor
    private let candidateRanker: TabSuspensionCandidateRanker
    private let proactiveLifecycle: ProactiveTabSuspensionLifecycle
    private var catalogRuntime: TabSuspensionCatalogRuntime = .inactive

    init(
        contextSource: TabSuspensionContextSource,
        executor: TabSuspensionExecutor,
        proactiveLifecycle: ProactiveTabSuspensionLifecycle,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.dateProvider = dateProvider
        self.contextSource = contextSource
        self.executor = executor
        self.candidateRanker = TabSuspensionCandidateRanker(executor: executor)
        self.proactiveLifecycle = proactiveLifecycle
    }

    func install(runtime: TabSuspensionCatalogRuntime) {
        catalogRuntime = runtime
    }

    func handle(_ level: SumiMemoryPressureLevel) {
        let signpostState = PerformanceTrace.beginInterval("TabSuspension.memoryPressure")
        defer {
            PerformanceTrace.endInterval("TabSuspension.memoryPressure", signpostState)
        }

        PerformanceTrace.emitEvent("TabSuspension.memoryPressureEvent")
        NotificationCenter.default.post(
            name: .sumiMemoryPressureReceived,
            object: self,
            userInfo: ["level": level.rawValue]
        )

        guard executor.isWebViewRuntimeAvailable else {
            PerformanceTrace.emitEvent("TabSuspension.candidatesRanked")
            PerformanceTrace.emitEvent("TabSuspension.tabsSuspended")
            RuntimeDiagnostics.debug(category: "TabSuspension") {
                "memoryPressure level=\(level.rawValue) candidates=0 suspended=0"
            }
            return
        }

        let inactiveCutoff = dateProvider().addingTimeInterval(
            -Self.minimumInactiveInterval
        )
        let context = contextSource.context()
        let candidates = candidateRanker.rankedTabs(
            from: catalogRuntime.allKnownTabs(),
            inactiveBefore: inactiveCutoff,
            context: context
        )
        PerformanceTrace.emitEvent("TabSuspension.candidatesRanked")

        let suspensionLimit: Int
        switch level {
        case .warning:
            suspensionLimit = min(1, candidates.count)
        case .critical:
            suspensionLimit = candidates.count
        }

        var suspendedCount = 0
        for tab in candidates.prefix(suspensionLimit) {
            guard executor.suspend(
                tab,
                reason: "memory-pressure-\(level.rawValue)",
                context: context
            ) else { continue }
            proactiveLifecycle.discardHiddenTrackingAfterSuspension(tabID: tab.id)
            suspendedCount += 1
        }

        PerformanceTrace.emitEvent("TabSuspension.tabsSuspended")
        RuntimeDiagnostics.debug(category: "TabSuspension") {
            "memoryPressure level=\(level.rawValue) candidates=\(candidates.count) suspended=\(suspendedCount)"
        }
    }
}
