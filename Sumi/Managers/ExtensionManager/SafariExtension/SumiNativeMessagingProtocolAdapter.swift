//
//  SumiNativeMessagingProtocolAdapter.swift
//  Sumi
//
//  Public companion-app protocol adapter registry for native messaging relay.
//

import Foundation

struct SumiNativeMessagingOneShotRequest {
    let applicationIdentifier: String?
    let extensionId: String
    let hostBundleIdentifier: String
    let resolverBucket: SumiNativeMessagingResolverBucket
    /// Opaque payload from WebKit; adapters must not log it.
    let message: Any
}

@MainActor
protocol SumiNativeMessagingProtocolAdapter: AnyObject {
    /// Stable adapter identifier for diagnostics (not a vendor bundle ID).
    var protocolIdentifier: String { get }

    func supports(hostBundleIdentifier: String) -> Bool

    /// Relay a one-time message. Must call `replyHandler` exactly once.
    func relayOneShotMessage(
        request: SumiNativeMessagingOneShotRequest,
        launcher: SumiHostApplicationLaunching,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    )

    /// Establish a persistent port. Must call `completionHandler` exactly once.
    func connectPort(
        session: SumiNativeMessagingPortSession,
        launcher: SumiHostApplicationLaunching,
        completionHandler: @escaping ((any Error)?) -> Void
    )

    /// Route an extension-originated port message. Return `false` when the adapter cannot relay it.
    @discardableResult
    func relayPortMessage(
        session: SumiNativeMessagingPortSession,
        message: Any
    ) -> Bool
}

@MainActor
final class SumiNativeMessagingAdapterRegistry {
    private let adapters: [SumiNativeMessagingProtocolAdapter]

    init(adapters: [SumiNativeMessagingProtocolAdapter] = []) {
        self.adapters = adapters
    }

    func adapter(forHostBundleIdentifier hostBundleIdentifier: String)
        -> SumiNativeMessagingProtocolAdapter?
    {
        adapters.first { $0.supports(hostBundleIdentifier: hostBundleIdentifier) }
    }

    static let shared = SumiNativeMessagingAdapterRegistry()
}
