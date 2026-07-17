import CoreLocation
import Foundation
import SumiDomain

@MainActor
final class SumiGeolocationProvider: NSObject, SumiGeolocationProviding {
    private let geolocationService: any SumiGeolocationServicing
    private let manager: SumiWebKitGeolocationManagerHandle
    private var providerCallbacks: UnsafeMutablePointer<SumiWKGeolocationProviderV1>?
    private var allowedPageIds: Set<String> = []
    private var tabIdsByPageId: [String: String] = [:]
    private var profilePartitionIdsByPageId: [String: String] = [:]
    private var retiredProfileIDs: Set<String> = []
    private var webKitIsUpdating = false
    private var enableHighAccuracy = false
    private var observers: [UUID: @MainActor (SumiGeolocationProviderState) -> Void] = [:]

    private(set) var currentState: SumiGeolocationProviderState = .inactive {
        didSet {
            guard currentState != oldValue else { return }
            notifyObservers()
        }
    }

    var isAvailable: Bool {
        currentState != .unavailable
    }

    convenience init?(
        browserConfiguration: BrowserConfiguration
    ) {
        self.init(
            webKitProcessPoolContext: browserConfiguration.webKitProcessPoolContext,
            geolocationService: SumiGeolocationService()
        )
    }

    init?(
        webKitProcessPoolContext: SumiWebKitProcessPoolContext,
        geolocationService: any SumiGeolocationServicing
    ) {
        guard let manager = SumiWebKitGeolocationManagerHandle(
            webKitProcessPoolContext: webKitProcessPoolContext
        ) else {
            return nil
        }
        self.manager = manager
        self.geolocationService = geolocationService
        super.init()
        installProviderCallbacks()
    }

    isolated deinit {
        manager.clearProvider()
        providerCallbacks?.deinitialize(count: 1)
        providerCallbacks?.deallocate()
        providerCallbacks = nil
    }

    func registerAllowedRequest(
        pageId: String,
        tabId: String?,
        profilePartitionId: String
    ) {
        let normalizedPageId = Self.normalizedId(pageId)
        let profileID = SumiPermissionKey.normalizedProfilePartitionId(
            profilePartitionId
        )
        guard !normalizedPageId.isEmpty,
              retiredProfileIDs.contains(profileID) == false
        else { return }
        allowedPageIds.insert(normalizedPageId)
        if let tabId = tabId.map(Self.normalizedId), !tabId.isEmpty {
            tabIdsByPageId[normalizedPageId] = tabId
        }
        profilePartitionIdsByPageId[normalizedPageId] = profileID

        if currentState == .revoked {
            currentState = .inactive
        }
        if case .failed = currentState {
            currentState = .inactive
        }
    }

    func containsAllowedRequest(pageId: String) -> Bool {
        let normalizedPageId = Self.normalizedId(pageId)
        guard !normalizedPageId.isEmpty else { return false }
        return allowedPageIds.contains(normalizedPageId)
    }

    func containsAllowedRequest(profilePartitionId: String) -> Bool {
        let profileID = SumiPermissionKey.normalizedProfilePartitionId(
            profilePartitionId
        )
        return profilePartitionIdsByPageId.values.contains(profileID)
    }

    func cancelAllowedRequest(pageId: String) {
        let normalizedPageId = Self.normalizedId(pageId)
        allowedPageIds.remove(normalizedPageId)
        tabIdsByPageId.removeValue(forKey: normalizedPageId)
        profilePartitionIdsByPageId.removeValue(forKey: normalizedPageId)
        if allowedPageIds.isEmpty {
            _ = stop()
        }
    }

    func cancelAllowedRequests(tabId: String) {
        let normalizedTabId = Self.normalizedId(tabId)
        let matchingPageIds = tabIdsByPageId
            .filter { $0.value == normalizedTabId }
            .map(\.key)
        for pageId in matchingPageIds {
            allowedPageIds.remove(pageId)
            tabIdsByPageId.removeValue(forKey: pageId)
            profilePartitionIdsByPageId.removeValue(forKey: pageId)
        }
        if allowedPageIds.isEmpty {
            _ = stop()
        }
    }

    func retireProfile(profilePartitionId: String) {
        let profileID = SumiPermissionKey.normalizedProfilePartitionId(
            profilePartitionId
        )
        retiredProfileIDs.insert(profileID)
        let matchingPageIDs = profilePartitionIdsByPageId
            .filter { $0.value == profileID }
            .map(\.key)
        for pageID in matchingPageIDs {
            allowedPageIds.remove(pageID)
            tabIdsByPageId.removeValue(forKey: pageID)
            profilePartitionIdsByPageId.removeValue(forKey: pageID)
        }
        if allowedPageIds.isEmpty {
            _ = stop()
        }
    }

    @discardableResult
    func pause() -> SumiGeolocationProviderState {
        switch currentState {
        case .active:
            geolocationService.stopUpdatingLocation()
            currentState = .paused
        case .inactive, .paused, .revoked, .unavailable, .failed:
            break
        }
        return currentState
    }

    @discardableResult
    func resume() -> SumiGeolocationProviderState {
        switch currentState {
        case .paused:
            currentState = .inactive
            if webKitIsUpdating {
                beginServiceUpdatesIfAllowed()
            }
        case .inactive:
            if webKitIsUpdating {
                beginServiceUpdatesIfAllowed()
            }
        case .active, .revoked, .unavailable, .failed:
            break
        }
        return currentState
    }

    @discardableResult
    func stop(pageId: String?) -> SumiGeolocationProviderState {
        if let pageId {
            cancelAllowedRequest(pageId: pageId)
            return currentState
        }
        return stop()
    }

    @discardableResult
    private func stop() -> SumiGeolocationProviderState {
        geolocationService.stopUpdatingLocation()
        webKitIsUpdating = false
        enableHighAccuracy = false
        allowedPageIds.removeAll()
        tabIdsByPageId.removeAll()
        profilePartitionIdsByPageId.removeAll()
        currentState = .inactive
        return currentState
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

    fileprivate func webKitDidStartUpdatingLocation() {
        webKitIsUpdating = true
        beginServiceUpdatesIfAllowed()
    }

    fileprivate func webKitDidStopUpdatingLocation() {
        webKitIsUpdating = false
        geolocationService.stopUpdatingLocation()
        if currentState != .revoked && currentState != .unavailable {
            currentState = .inactive
        }
    }

    fileprivate func webKitDidSetEnableHighAccuracy(_ enabled: Bool) {
        enableHighAccuracy = enabled
        guard webKitIsUpdating,
              currentState == .active || currentState == .inactive
        else { return }
        beginServiceUpdatesIfAllowed()
    }

    private func installProviderCallbacks() {
        let callbacks = UnsafeMutablePointer<SumiWKGeolocationProviderV1>.allocate(capacity: 1)
        callbacks.initialize(
            to: SumiWKGeolocationProviderV1(
                base: SumiWKGeolocationProviderBase(
                    version: 1,
                    clientInfo: Unmanaged.passUnretained(self).toOpaque()
                ),
                startUpdating: sumiGeolocationProviderStartUpdating,
                stopUpdating: sumiGeolocationProviderStopUpdating,
                setEnableHighAccuracy: sumiGeolocationProviderSetEnableHighAccuracy
            )
        )
        manager.setProvider(&callbacks.pointee.base)
        providerCallbacks = callbacks
    }

    private func beginServiceUpdatesIfAllowed() {
        guard !allowedPageIds.isEmpty else {
            geolocationService.stopUpdatingLocation()
            currentState = .failed(reason: SumiGeolocationProviderError.permissionDenied.reason)
            manager.providerDidFailToDeterminePosition(.permissionDenied)
            return
        }
        guard currentState != .revoked else {
            manager.providerDidFailToDeterminePosition(.providerRevoked)
            return
        }
        guard currentState != .paused else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let error = await self.geolocationService.startUpdatingLocation(
                highAccuracy: self.enableHighAccuracy
            ) { [weak self] result in
                self?.handleLocationResult(result)
            }
            if let error {
                self.currentState = .failed(reason: error.reason)
                self.manager.providerDidFailToDeterminePosition(error)
            } else if self.currentState != .revoked && self.currentState != .paused {
                self.currentState = .active
            }
        }
    }

    private func handleLocationResult(
        _ result: Result<CLLocation, SumiGeolocationProviderError>
    ) {
        guard webKitIsUpdating else { return }
        switch result {
        case .success(let location):
            guard currentState != .paused else { return }
            guard currentState != .revoked else {
                manager.providerDidFailToDeterminePosition(.providerRevoked)
                return
            }
            currentState = .active
            manager.providerDidChangePosition(location)
        case .failure(let error):
            currentState = .failed(reason: error.reason)
            manager.providerDidFailToDeterminePosition(error)
        }
    }

    private func notifyObservers() {
        for observer in observers.values {
            observer(currentState)
        }
    }

    private static func normalizedId(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private func sumiGeolocationProviderStartUpdating(
    _: UnsafeRawPointer?,
    clientInfo: UnsafeRawPointer?
) {
    guard let clientInfo else { return }
    let provider = Unmanaged<SumiGeolocationProvider>
        .fromOpaque(clientInfo)
        .takeUnretainedValue()
    Task { @MainActor in
        provider.webKitDidStartUpdatingLocation()
    }
}

private func sumiGeolocationProviderStopUpdating(
    _: UnsafeRawPointer?,
    clientInfo: UnsafeRawPointer?
) {
    guard let clientInfo else { return }
    let provider = Unmanaged<SumiGeolocationProvider>
        .fromOpaque(clientInfo)
        .takeUnretainedValue()
    Task { @MainActor in
        provider.webKitDidStopUpdatingLocation()
    }
}

private func sumiGeolocationProviderSetEnableHighAccuracy(
    _: UnsafeRawPointer?,
    enabled: Bool,
    clientInfo: UnsafeRawPointer?
) {
    guard let clientInfo else { return }
    let provider = Unmanaged<SumiGeolocationProvider>
        .fromOpaque(clientInfo)
        .takeUnretainedValue()
    Task { @MainActor in
        provider.webKitDidSetEnableHighAccuracy(enabled)
    }
}
