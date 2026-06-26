import Foundation

@MainActor
final class SumiPermissionEventOwner {
    typealias EventHandler = @MainActor (SumiPermissionCoordinatorEvent) async -> Void

    private let recentActivityStore: SumiPermissionRecentActivityStore
    private let siteActivityStore: SumiPermissionSiteActivityStore
    private let onEvent: EventHandler
    private var eventTask: Task<Void, Never>?

    init(
        coordinator: any SumiPermissionCoordinating,
        recentActivityStore: SumiPermissionRecentActivityStore,
        siteActivityStore: SumiPermissionSiteActivityStore,
        onEvent: @escaping EventHandler
    ) {
        self.recentActivityStore = recentActivityStore
        self.siteActivityStore = siteActivityStore
        self.onEvent = onEvent
        eventTask = Task { @MainActor [weak self, coordinator] in
            let events = await coordinator.events()
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    func cancel() {
        eventTask?.cancel()
        eventTask = nil
    }

    isolated deinit {
        eventTask?.cancel()
    }

    private func handle(_ event: SumiPermissionCoordinatorEvent) async {
        recentActivityStore.record(event)
        siteActivityStore.record(event: event)
        await onEvent(event)
    }
}
