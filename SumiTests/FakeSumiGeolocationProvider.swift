import Foundation

@testable import Sumi

@MainActor
final class FakeSumiGeolocationProvider: SumiGeolocationProviding {
    var currentState: SumiGeolocationProviderState {
        didSet { emitStateChange() }
    }
    var providerAvailable: Bool
    private(set) var registeredRequests: [(pageId: String, tabId: String?)] = []
    private(set) var cancelledPageIds: [String] = []
    private(set) var cancelledTabIds: [String] = []
    private(set) var pauseCallCount = 0
    private(set) var resumeCallCount = 0
    private(set) var revokeCallCount = 0
    private(set) var stopCallCount = 0
    private var observers: [UUID: @MainActor (SumiGeolocationProviderState) -> Void] = [:]

    init(
        currentState: SumiGeolocationProviderState = .inactive,
        providerAvailable: Bool = true
    ) {
        self.currentState = currentState
        self.providerAvailable = providerAvailable
    }

    var isAvailable: Bool {
        providerAvailable && currentState != .unavailable
    }

    func registerAllowedRequest(pageId: String, tabId: String?) {
        registeredRequests.append((pageId, tabId))
        if currentState == .revoked {
            currentState = .inactive
        }
        if case .failed = currentState {
            currentState = .inactive
        }
    }

    func cancelAllowedRequest(pageId: String) {
        cancelledPageIds.append(pageId)
        if registeredRequests.contains(where: { $0.pageId == pageId }) {
            registeredRequests.removeAll { $0.pageId == pageId }
        }
        if registeredRequests.isEmpty {
            _ = stop()
        }
    }

    func cancelAllowedRequests(tabId: String) {
        cancelledTabIds.append(tabId)
        registeredRequests.removeAll { $0.tabId == tabId }
        if registeredRequests.isEmpty {
            _ = stop()
        }
    }

    @discardableResult
    func pause() -> SumiGeolocationProviderState {
        pauseCallCount += 1
        if currentState == .active {
            currentState = .paused
        }
        return currentState
    }

    @discardableResult
    func resume() -> SumiGeolocationProviderState {
        resumeCallCount += 1
        if currentState == .paused || currentState == .inactive {
            currentState = .active
        }
        return currentState
    }

    @discardableResult
    func revoke() -> SumiGeolocationProviderState {
        revokeCallCount += 1
        currentState = .revoked
        registeredRequests.removeAll()
        return currentState
    }

    @discardableResult
    func stop(pageId: String?) -> SumiGeolocationProviderState {
        stopCallCount += 1
        if let pageId {
            registeredRequests.removeAll { $0.pageId == pageId }
        } else {
            registeredRequests.removeAll()
        }
        if registeredRequests.isEmpty {
            currentState = .inactive
        }
        return currentState
    }

    @discardableResult
    func stop() -> SumiGeolocationProviderState {
        stop(pageId: nil)
    }

    func observeState(
        _ handler: @escaping @MainActor (SumiGeolocationProviderState) -> Void
    ) -> SumiGeolocationProviderObservation {
        let id = UUID()
        observers[id] = handler
        handler(currentState)
        return SumiGeolocationProviderObservation { [weak self] in
            self?.observers.removeValue(forKey: id)
        }
    }

    private func emitStateChange() {
        for observer in observers.values {
            observer(currentState)
        }
    }
}
