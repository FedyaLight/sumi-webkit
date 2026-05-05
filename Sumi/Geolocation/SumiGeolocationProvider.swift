import CoreLocation
import Darwin
import Foundation
import WebKit

@MainActor
protocol SumiGeolocationProviding: AnyObject {
    var currentState: SumiGeolocationProviderState { get }
    var isAvailable: Bool { get }

    func registerAllowedRequest(pageId: String, tabId: String?)
    func containsAllowedRequest(pageId: String) -> Bool
    func cancelAllowedRequest(pageId: String)
    func cancelAllowedRequests(tabId: String)

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

    deinit {
        cancellation?()
    }
}

@MainActor
final class SumiGeolocationProvider: NSObject, SumiGeolocationProviding {
    private let geolocationService: any SumiGeolocationServicing
    private let manager: SumiWebKitGeolocationManagerHandle
    private var providerCallbacks: UnsafeMutablePointer<SumiWKGeolocationProviderV1>?
    private var allowedPageIds: Set<String> = []
    private var tabIdsByPageId: [String: String] = [:]
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

    deinit {
        manager.clearProvider()
        providerCallbacks?.deinitialize(count: 1)
        providerCallbacks?.deallocate()
        providerCallbacks = nil
    }

    func registerAllowedRequest(pageId: String, tabId: String?) {
        let normalizedPageId = Self.normalizedId(pageId)
        guard !normalizedPageId.isEmpty else { return }
        allowedPageIds.insert(normalizedPageId)
        if let tabId = tabId.map(Self.normalizedId), !tabId.isEmpty {
            tabIdsByPageId[normalizedPageId] = tabId
        }

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

    func cancelAllowedRequest(pageId: String) {
        let normalizedPageId = Self.normalizedId(pageId)
        allowedPageIds.remove(normalizedPageId)
        tabIdsByPageId.removeValue(forKey: normalizedPageId)
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

private struct SumiWebKitGeolocationManagerHandle {
    typealias ContextGetGeolocationManager = @convention(c) (UnsafeRawPointer?) -> UnsafeRawPointer?
    typealias ManagerSetProvider = @convention(c) (UnsafeRawPointer?, UnsafePointer<SumiWKGeolocationProviderBase>?) -> Void
    typealias ProviderDidChangePosition = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> Void
    typealias ProviderDidFail = @convention(c) (UnsafeRawPointer?) -> Void
    typealias ProviderDidFailWithMessage = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> Void
    typealias PositionCreate = @convention(c) (
        Double,
        Double,
        Double,
        Double,
        Bool,
        Double,
        Bool,
        Double,
        Bool,
        Double,
        Bool,
        Double,
        Bool,
        Double
    ) -> UnsafeRawPointer?
    typealias WKRelease = @convention(c) (UnsafeRawPointer?) -> Void

    private static let getGeolocationManager: ContextGetGeolocationManager? =
        symbol(named: "WKContextGetGeolocationManager")
    private static let setProviderSymbol: ManagerSetProvider? =
        symbol(named: "WKGeolocationManagerSetProvider")
    private static let didChangePosition: ProviderDidChangePosition? =
        symbol(named: "WKGeolocationManagerProviderDidChangePosition")
    private static let didFail: ProviderDidFail? =
        symbol(named: "WKGeolocationManagerProviderDidFailToDeterminePosition")
    private static let didFailWithMessage: ProviderDidFailWithMessage? =
        symbol(named: "WKGeolocationManagerProviderDidFailToDeterminePositionWithErrorMessage")
    private static let positionCreate: PositionCreate? =
        symbol(named: "WKGeolocationPositionCreate_c")
    private static let release: WKRelease? =
        symbol(named: "WKRelease")

    private let manager: UnsafeRawPointer

    init?(webKitProcessPoolContext: SumiWebKitProcessPoolContext) {
        guard let getGeolocationManager = Self.getGeolocationManager,
              Self.setProviderSymbol != nil,
              Self.didChangePosition != nil,
              Self.didFail != nil,
              Self.positionCreate != nil,
              let manager = getGeolocationManager(webKitProcessPoolContext.opaquePointer)
        else {
            return nil
        }
        self.manager = manager
    }

    func setProvider(_ provider: UnsafePointer<SumiWKGeolocationProviderBase>?) {
        Self.setProviderSymbol?(manager, provider)
    }

    func clearProvider() {
        Self.setProviderSymbol?(manager, nil)
    }

    func providerDidChangePosition(_ location: CLLocation) {
        guard let position = Self.positionCreate?(
            location.timestamp.timeIntervalSinceReferenceDate,
            location.coordinate.latitude,
            location.coordinate.longitude,
            max(location.horizontalAccuracy, 0),
            false,
            0,
            false,
            0,
            location.course >= 0,
            location.course >= 0 ? location.course : 0,
            location.speed >= 0,
            location.speed >= 0 ? location.speed : 0,
            location.floor != nil,
            location.floor.map { Double($0.level) } ?? 0
        ) else {
            providerDidFailToDeterminePosition(.unavailable)
            return
        }
        Self.didChangePosition?(manager, position)
        Self.release?(position)
    }

    func providerDidFailToDeterminePosition(_ error: SumiGeolocationProviderError) {
        if let didFailWithMessage = Self.didFailWithMessage,
           let message = Self.webKitString(error.reason) {
            didFailWithMessage(manager, message)
            Self.release?(message)
            return
        }
        Self.didFail?(manager)
    }

    private static func webKitString(_ value: String) -> UnsafeRawPointer? {
        typealias StringCreate = @convention(c) (CFString) -> UnsafeRawPointer?
        let create: StringCreate? = symbol(named: "WKStringCreateWithCFString")
        return create?(value as CFString)
    }

    private static func symbol<T>(named name: String) -> T? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}

private func sumiGeolocationProviderStartUpdating(
    _: UnsafeRawPointer?,
    clientInfo: UnsafeRawPointer?
) {
    guard let clientInfo else { return }
    Task { @MainActor in
        Unmanaged<SumiGeolocationProvider>
            .fromOpaque(clientInfo)
            .takeUnretainedValue()
            .webKitDidStartUpdatingLocation()
    }
}

private func sumiGeolocationProviderStopUpdating(
    _: UnsafeRawPointer?,
    clientInfo: UnsafeRawPointer?
) {
    guard let clientInfo else { return }
    Task { @MainActor in
        Unmanaged<SumiGeolocationProvider>
            .fromOpaque(clientInfo)
            .takeUnretainedValue()
            .webKitDidStopUpdatingLocation()
    }
}

private func sumiGeolocationProviderSetEnableHighAccuracy(
    _: UnsafeRawPointer?,
    enabled: Bool,
    clientInfo: UnsafeRawPointer?
) {
    guard let clientInfo else { return }
    Task { @MainActor in
        Unmanaged<SumiGeolocationProvider>
            .fromOpaque(clientInfo)
            .takeUnretainedValue()
            .webKitDidSetEnableHighAccuracy(enabled)
    }
}
