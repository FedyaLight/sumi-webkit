import Foundation
import SumiDomain

@MainActor
protocol SumiGeolocationProviding: AnyObject {
    var currentState: SumiGeolocationProviderState { get }
    var isAvailable: Bool { get }

    func registerAllowedRequest(
        pageId: String,
        tabId: String?,
        profilePartitionId: String
    )
    func containsAllowedRequest(pageId: String) -> Bool
    func containsAllowedRequest(profilePartitionId: String) -> Bool
    func cancelAllowedRequest(pageId: String)
    func cancelAllowedRequests(tabId: String)
    func retireProfile(profilePartitionId: String)

    @discardableResult
    func pause() -> SumiGeolocationProviderState

    @discardableResult
    func resume() -> SumiGeolocationProviderState

    @discardableResult
    func stop(pageId: String?) -> SumiGeolocationProviderState

    func observeState(
        _ handler: @escaping @MainActor (SumiGeolocationProviderState) -> Void
    ) -> SumiGeolocationProviderObservation
}

@MainActor
final class SumiGeolocationProviderObservation {
    private var cancellation: (() -> Void)?

    init(_ cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        cancellation?()
        cancellation = nil
    }

    isolated deinit {
        cancellation?()
    }
}

@MainActor
final class SumiLazyGeolocationProvider: SumiGeolocationProviding {
    private let makeProvider: () -> (any SumiGeolocationProviding)?
    private var provider: (any SumiGeolocationProviding)?
    private var didAttemptProviderCreation = false
    private var observers: [UUID: @MainActor (SumiGeolocationProviderState) -> Void] = [:]
    private var providerObservations: [UUID: SumiGeolocationProviderObservation] = [:]
    private var retiredProfileIDs: Set<String> = []

    init(makeProvider: @escaping () -> (any SumiGeolocationProviding)?) {
        self.makeProvider = makeProvider
    }

    var currentState: SumiGeolocationProviderState {
        if let provider {
            return provider.currentState
        }
        return didAttemptProviderCreation ? .unavailable : .inactive
    }

    var isAvailable: Bool {
        resolveProvider()?.isAvailable == true
    }

    func registerAllowedRequest(
        pageId: String,
        tabId: String?,
        profilePartitionId: String
    ) {
        let profileID = SumiPermissionKey.normalizedProfilePartitionId(
            profilePartitionId
        )
        guard retiredProfileIDs.contains(profileID) == false else { return }
        resolveProvider()?.registerAllowedRequest(
            pageId: pageId,
            tabId: tabId,
            profilePartitionId: profileID
        )
    }

    func containsAllowedRequest(pageId: String) -> Bool {
        provider?.containsAllowedRequest(pageId: pageId) == true
    }

    func containsAllowedRequest(profilePartitionId: String) -> Bool {
        provider?.containsAllowedRequest(
            profilePartitionId: profilePartitionId
        ) == true
    }

    func cancelAllowedRequest(pageId: String) {
        provider?.cancelAllowedRequest(pageId: pageId)
    }

    func cancelAllowedRequests(tabId: String) {
        provider?.cancelAllowedRequests(tabId: tabId)
    }

    func retireProfile(profilePartitionId: String) {
        let profileID = SumiPermissionKey.normalizedProfilePartitionId(
            profilePartitionId
        )
        retiredProfileIDs.insert(profileID)
        provider?.retireProfile(profilePartitionId: profileID)
    }

    @discardableResult
    func pause() -> SumiGeolocationProviderState {
        provider?.pause() ?? currentState
    }

    @discardableResult
    func resume() -> SumiGeolocationProviderState {
        provider?.resume() ?? currentState
    }

    @discardableResult
    func stop(pageId: String?) -> SumiGeolocationProviderState {
        provider?.stop(pageId: pageId) ?? currentState
    }

    func observeState(
        _ handler: @escaping @MainActor (SumiGeolocationProviderState) -> Void
    ) -> SumiGeolocationProviderObservation {
        let id = UUID()
        observers[id] = handler
        if let provider {
            providerObservations[id] = provider.observeState(handler)
        } else {
            handler(currentState)
        }
        return SumiGeolocationProviderObservation { [weak self] in
            self?.observers.removeValue(forKey: id)
            self?.providerObservations.removeValue(forKey: id)?.cancel()
        }
    }

    private func resolveProvider() -> (any SumiGeolocationProviding)? {
        if let provider {
            return provider
        }
        guard !didAttemptProviderCreation else {
            return nil
        }

        didAttemptProviderCreation = true
        guard let provider = makeProvider() else {
            notifyObservers(.unavailable)
            return nil
        }

        self.provider = provider
        for (id, handler) in observers {
            providerObservations[id] = provider.observeState(handler)
        }
        return provider
    }

    private func notifyObservers(_ state: SumiGeolocationProviderState) {
        for observer in observers.values {
            observer(state)
        }
    }
}
