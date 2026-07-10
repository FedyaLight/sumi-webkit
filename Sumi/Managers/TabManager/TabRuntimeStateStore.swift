import OSLog

struct TabRuntimeStateStore: Sendable {
    private static let log = Logger.sumi(category: "TabPersistence")
    private let writes: TabStoreWriteExecutor

    init(writes: TabStoreWriteExecutor) {
        self.writes = writes
    }

    func persist(_ updates: [TabRuntimeStateUpdate]) async {
        guard updates.isEmpty == false else { return }
        let signpostState = PerformanceTrace.beginInterval("TabRuntimeStateStore.persist")
        defer {
            PerformanceTrace.endInterval("TabRuntimeStateStore.persist", signpostState)
        }

        do {
            try await writes.execute(.runtimeState(updates))
        } catch {
            Self.log.error(
                "Tab runtime-state persistence failed for count=\(updates.count, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }
}
