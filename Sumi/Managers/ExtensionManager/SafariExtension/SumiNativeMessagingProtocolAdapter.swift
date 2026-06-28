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

    /// Tear down adapter-owned resources for a port session (desktop transports, timers, etc.).
    func disconnectPort(session: SumiNativeMessagingPortSession)
}

extension SumiNativeMessagingProtocolAdapter {
    func disconnectPort(session: SumiNativeMessagingPortSession) {}
}

@MainActor
final class SumiNativeMessagingAdapterRegistry {
    private let adapters: [SumiNativeMessagingProtocolAdapter]
    private let adaptersByProtocolIdentifier: [String: SumiNativeMessagingProtocolAdapter]

    init(adapters: [SumiNativeMessagingProtocolAdapter] = []) {
        self.adapters = adapters
        var byProtocol: [String: SumiNativeMessagingProtocolAdapter] = [:]
        for adapter in adapters {
            byProtocol[adapter.protocolIdentifier] = adapter
        }
        self.adaptersByProtocolIdentifier = byProtocol
    }

    func adapter(forHostBundleIdentifier hostBundleIdentifier: String)
        -> SumiNativeMessagingProtocolAdapter? {
        let normalized = SumiCompanionAppIdentityMetadata
            .normalizedHostBundleIdentifier(hostBundleIdentifier)
        return adapters.first { $0.supports(hostBundleIdentifier: normalized) }
    }

    func adapter(forApplicationIdentifier applicationIdentifier: String?)
        -> SumiNativeMessagingProtocolAdapter? {
        guard let applicationIdentifier else { return nil }
        let normalized = SumiCompanionAppIdentityMetadata
            .normalizedHostBundleIdentifier(applicationIdentifier)
        return adapter(forHostBundleIdentifier: normalized)
    }

    func adapter(
        forApplicationIdentifier applicationIdentifier: String?,
        hostBundleIdentifier: String
    ) -> SumiNativeMessagingProtocolAdapter? {
        if let adapter = adapter(forHostBundleIdentifier: hostBundleIdentifier) {
            return adapter
        }
        return adapter(forApplicationIdentifier: applicationIdentifier)
    }

    func isAdapterAvailable(
        forApplicationIdentifier applicationIdentifier: String?,
        hostBundleIdentifier: String
    ) -> Bool {
        adapter(
            forApplicationIdentifier: applicationIdentifier,
            hostBundleIdentifier: hostBundleIdentifier
        ) != nil
    }

    func adapter(forProtocolIdentifier protocolIdentifier: String)
        -> SumiNativeMessagingProtocolAdapter? {
        adaptersByProtocolIdentifier[protocolIdentifier]
    }

    func isAdapterAvailable(forHostBundleIdentifier hostBundleIdentifier: String) -> Bool {
        adapter(forHostBundleIdentifier: hostBundleIdentifier) != nil
    }

    func isAdapterAvailable(forApplicationIdentifier applicationIdentifier: String?) -> Bool {
        adapter(forApplicationIdentifier: applicationIdentifier) != nil
    }

    var registeredProtocolIdentifiers: [String] {
        adapters.map(\.protocolIdentifier).sorted()
    }
}
