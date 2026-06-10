//
//  SumiNativeMessagingFakePublicAdapter.swift
//  SumiTests
//
//  Reusable fake public companion-app protocol adapter for native messaging tests.
//

import Foundation
@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SumiNativeMessagingFakePublicAdapter: SumiNativeMessagingProtocolAdapter {
    static let defaultProtocolIdentifier = "sumi.tests.fake-public"

    let protocolIdentifier: String
    var supportedHosts: Set<String>
    var oneShotReply: (Any?, (any Error)?)
    var shouldLaunchOnOneShot: Bool
    var shouldLaunchOnConnect: Bool
    var connectCompletion: @Sendable ((any Error)?) -> (any Error)?
    var relayPortMessageResult: Bool
    private(set) var portMessageRelayed = false
    private(set) var oneShotRequestCount = 0
    private(set) var connectRequestCount = 0

    init(
        protocolIdentifier: String = SumiNativeMessagingFakePublicAdapter.defaultProtocolIdentifier,
        supportedHosts: Set<String> = [],
        oneShotReply: (Any?, (any Error)?) = (["ok": true], nil),
        shouldLaunchOnOneShot: Bool = true,
        shouldLaunchOnConnect: Bool = true,
        connectCompletion: @Sendable @escaping ((any Error)?) -> (any Error)? = { $0 },
        relayPortMessageResult: Bool = true
    ) {
        self.protocolIdentifier = protocolIdentifier
        self.supportedHosts = supportedHosts
        self.oneShotReply = oneShotReply
        self.shouldLaunchOnOneShot = shouldLaunchOnOneShot
        self.shouldLaunchOnConnect = shouldLaunchOnConnect
        self.connectCompletion = connectCompletion
        self.relayPortMessageResult = relayPortMessageResult
    }

    func supports(hostBundleIdentifier: String) -> Bool {
        supportedHosts.contains(hostBundleIdentifier)
    }

    func relayOneShotMessage(
        request: SumiNativeMessagingOneShotRequest,
        launcher: SumiHostApplicationLaunching,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        _ = request.message
        oneShotRequestCount += 1
        Task { @MainActor in
            if self.shouldLaunchOnOneShot {
                do {
                    try await launcher.openApplication(
                        withBundleIdentifier: request.hostBundleIdentifier
                    )
                } catch {
                    replyHandler(nil, error)
                    return
                }
            }
            replyHandler(self.oneShotReply.0, self.oneShotReply.1)
        }
    }

    func connectPort(
        session: SumiNativeMessagingPortSession,
        launcher: SumiHostApplicationLaunching,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        connectRequestCount += 1
        Task { @MainActor in
            if self.shouldLaunchOnConnect {
                do {
                    try await launcher.openApplication(
                        withBundleIdentifier: session.resolvedHostBundleIdentifier
                    )
                } catch {
                    completionHandler(error)
                    return
                }
            }
            completionHandler(self.connectCompletion(nil))
        }
    }

    func relayPortMessage(
        session: SumiNativeMessagingPortSession,
        message: Any
    ) -> Bool {
        _ = session
        _ = message
        portMessageRelayed = true
        return relayPortMessageResult
    }
}
