import CoreLocation
import Darwin
import Foundation

struct SumiWebKitGeolocationManagerHandle {
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
