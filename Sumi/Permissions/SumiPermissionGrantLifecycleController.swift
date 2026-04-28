import Foundation

@MainActor
final class SumiPermissionGrantLifecycleController {
    private let coordinator: any SumiPermissionCoordinating
    private weak var geolocationProvider: (any SumiGeolocationProviding)?
    private weak var filePickerBridge: SumiFilePickerPermissionBridge?
    private let indicatorEventStore: SumiPermissionIndicatorEventStore
    private let blockedPopupStore: SumiBlockedPopupStore
    private let externalSchemeSessionStore: SumiExternalSchemeSessionStore

    init(
        coordinator: any SumiPermissionCoordinating,
        geolocationProvider: (any SumiGeolocationProviding)?,
        filePickerBridge: SumiFilePickerPermissionBridge?,
        indicatorEventStore: SumiPermissionIndicatorEventStore,
        blockedPopupStore: SumiBlockedPopupStore,
        externalSchemeSessionStore: SumiExternalSchemeSessionStore
    ) {
        self.coordinator = coordinator
        self.geolocationProvider = geolocationProvider
        self.filePickerBridge = filePickerBridge
        self.indicatorEventStore = indicatorEventStore
        self.blockedPopupStore = blockedPopupStore
        self.externalSchemeSessionStore = externalSchemeSessionStore
    }

    func handle(_ event: SumiPermissionLifecycleEvent) {
        switch event {
        case .mainFrameNavigation(let pageId, _, _, _, let reason):
            clearPageRuntime(pageId: pageId, reason: reason)
            geolocationProvider?.stop(pageId: pageId)
            Task { [coordinator] in
                await coordinator.cancelNavigation(pageId: pageId, reason: reason)
            }

        case .webViewReplaced(let pageId, let tabId, _, let reason),
             .webViewDeallocated(let pageId, let tabId, _, let reason),
             .tabClosed(let pageId, let tabId, _, let reason):
            clearPageRuntime(pageId: pageId, reason: reason)
            clearTabRuntime(tabId: tabId, reason: reason)
            geolocationProvider?.stop(pageId: pageId)
            geolocationProvider?.cancelAllowedRequests(tabId: tabId)
            Task { [coordinator] in
                await coordinator.cancel(pageId: pageId, reason: reason)
                await coordinator.cancelTab(tabId: tabId, reason: reason)
            }

        case .profileClosed(let profilePartitionId, let reason):
            Task { [coordinator] in
                await coordinator.cancelProfile(
                    profilePartitionId: profilePartitionId,
                    reason: reason
                )
            }

        case .sessionClosed(let ownerId, let reason):
            Task { [coordinator] in
                await coordinator.cancelSession(ownerId: ownerId, reason: reason)
            }

        case .currentSiteReset(
            let pageId,
            let tabId,
            let profilePartitionId,
            let requestingOrigin,
            let topOrigin,
            let reason
        ):
            if let pageId {
                clearPageRuntime(pageId: pageId, reason: reason)
                geolocationProvider?.stop(pageId: pageId)
            }
            if let tabId {
                clearTabRuntime(tabId: tabId, reason: reason)
            }
            Task { [coordinator] in
                await coordinator.resetTransientDecisions(
                    profilePartitionId: profilePartitionId,
                    pageId: pageId,
                    requestingOrigin: requestingOrigin,
                    topOrigin: topOrigin,
                    reason: reason
                )
            }
        }
    }

    private func clearPageRuntime(pageId: String, reason: String) {
        blockedPopupStore.clear(pageId: pageId)
        externalSchemeSessionStore.clear(pageId: pageId)
        indicatorEventStore.clear(pageId: pageId)
        filePickerBridge?.cancel(pageId: pageId, reason: reason)
    }

    private func clearTabRuntime(tabId: String, reason: String) {
        blockedPopupStore.clear(tabId: tabId)
        externalSchemeSessionStore.clear(tabId: tabId)
        indicatorEventStore.clear(tabId: tabId)
        filePickerBridge?.cancel(tabId: tabId, reason: reason)
    }
}
