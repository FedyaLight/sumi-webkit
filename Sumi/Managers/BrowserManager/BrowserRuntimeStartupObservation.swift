import Combine
import Foundation

@MainActor
final class BrowserRuntimeStartupObservation {
    private let tabStructureEvents: TabStructureEventBus
    private let initialDataSettlement: BrowserInitialTabDataLoadedSettlement
    private let protectionRestore: BrowserStartupProtectionRuntime
    private var initialDataLoadedCancellable: AnyCancellable?

    init(
        tabStructureEvents: TabStructureEventBus,
        initialDataSettlement: BrowserInitialTabDataLoadedSettlement,
        protectionRestore: BrowserStartupProtectionRuntime
    ) {
        self.tabStructureEvents = tabStructureEvents
        self.initialDataSettlement = initialDataSettlement
        self.protectionRestore = protectionRestore
    }

    func start() {
        initialDataLoadedCancellable = tabStructureEvents
            .initialDataLoadedPublisher
            .sink { [weak initialDataSettlement] in
                initialDataSettlement?.settle()
            }
        protectionRestore.beginProtectionRestoreForStartupIfNeeded()
    }

    func cancel() {
        initialDataLoadedCancellable?.cancel()
        initialDataLoadedCancellable = nil
        protectionRestore.cancelProtectionRestoreTask()
    }
}
