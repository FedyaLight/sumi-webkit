import Foundation
import OSLog

struct TabSelectionStore: Sendable {
    private static let log = Logger.sumi(category: "TabPersistence")
    private let writes: TabStoreWriteExecutor

    init(writes: TabStoreWriteExecutor) {
        self.writes = writes
    }

    func persist(currentTabID: UUID?, currentSpaceID: UUID?) async {
        let signpostState = PerformanceTrace.beginInterval("TabSelectionStore.persist")
        defer {
            PerformanceTrace.endInterval("TabSelectionStore.persist", signpostState)
        }

        do {
            try await writes.execute(
                .selection(
                    TabPersistenceSelection(
                        currentTabID: currentTabID,
                        currentSpaceID: currentSpaceID
                    )
                )
            )
        } catch {
            Self.log.error(
                "Tab selection persistence failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
