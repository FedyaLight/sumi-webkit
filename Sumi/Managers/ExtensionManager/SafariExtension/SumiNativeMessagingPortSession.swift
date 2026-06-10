//
//  SumiNativeMessagingPortSession.swift
//  Sumi
//
//  Persistent WKWebExtension.MessagePort session for Safari native messaging.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class SumiNativeMessagingPortSession: NSObject {
    private let port: any SumiNativeMessagingPortControlling
    private let adapter: SumiNativeMessagingProtocolAdapter?
    let profileId: UUID?
    let extensionId: String
    private(set) var resolvedHostBundleIdentifier: String
    private let resolverBucket: SumiNativeMessagingResolverBucket
    private let logDiagnostic: (SafariExtensionNativeMessagingDiagnostic) -> Void
    private let companionProtocolErrorProvider: () -> NSError
    private let portInactivityTimeout: Duration
    private var inactivityTask: Task<Void, Never>?

    init(
        port: any SumiNativeMessagingPortControlling,
        adapter: SumiNativeMessagingProtocolAdapter?,
        extensionId: String,
        profileId: UUID? = nil,
        hostBundleIdentifier: String,
        resolverBucket: SumiNativeMessagingResolverBucket,
        logDiagnostic: @escaping (SafariExtensionNativeMessagingDiagnostic) -> Void,
        companionProtocolErrorProvider: @escaping () -> NSError,
        portInactivityTimeout: Duration = SumiNativeMessagingConnection.defaultPortInactivityTimeout
    ) {
        self.port = port
        self.adapter = adapter
        self.profileId = profileId
        self.extensionId = extensionId
        self.resolvedHostBundleIdentifier = hostBundleIdentifier
        self.resolverBucket = resolverBucket
        self.logDiagnostic = logDiagnostic
        self.companionProtocolErrorProvider = companionProtocolErrorProvider
        self.portInactivityTimeout = portInactivityTimeout
        super.init()
        wirePort()
        armPortInactivityTimeout()
    }

    func disconnect() {
        cancelPortInactivityTimeout()
        guard port.isDisconnected == false else { return }
        port.disconnect()
    }

    func touchPortActivity() {
        armPortInactivityTimeout()
    }

    func disconnectDueToUnsupportedProtocol() {
        guard port.isDisconnected == false else { return }
        port.disconnect(throwing: companionProtocolErrorProvider())
    }

    func sendReplyToExtension(_ message: Any) {
        guard port.isDisconnected == false else { return }
        if let recordingPort = port as? any SumiNativeMessagingPortReplyRecording {
            recordingPort.recordReplyToExtension(message)
            return
        }
        if let messagePort = port as? WKWebExtension.MessagePort {
            messagePort.sendMessage(message) { _ in }
        }
    }

    private func wirePort() {
        port.messageHandler = { [weak self] message, error in
            guard let self else { return }
            self.touchPortActivity()
            if let error {
                let nsError = error as NSError
                self.logDiagnostic(
                    self.makeDiagnostic(
                        direction: .portReceive,
                        outcome: .companionAppProtocolUnknown,
                        errorDomain: nsError.domain,
                        errorCode: nsError.code
                    )
                )
                return
            }

            guard let adapter = self.adapter else {
                self.logDiagnostic(
                    self.makeDiagnostic(
                        direction: .portRelay,
                        outcome: .companionAppProtocolUnknown,
                        errorDomain: SumiNativeMessagingRelay.errorDomain,
                        errorCode: SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
                    )
                )
                self.disconnectDueToUnsupportedProtocol()
                return
            }

            guard let message else {
                self.logDiagnostic(
                    self.makeDiagnostic(
                        direction: .portRelay,
                        outcome: .companionAppProtocolUnknown,
                        errorDomain: SumiNativeMessagingRelay.errorDomain,
                        errorCode: SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
                    )
                )
                return
            }
            let relayed = adapter.relayPortMessage(session: self, message: message)
            if relayed == false {
                self.logDiagnostic(
                    self.makeDiagnostic(
                        direction: .portRelay,
                        outcome: .companionAppProtocolUnknown,
                        errorDomain: SumiNativeMessagingRelay.errorDomain,
                        errorCode: SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue,
                        adapter: adapter
                    )
                )
                self.disconnectDueToUnsupportedProtocol()
            }
        }

        port.disconnectHandler = { [weak self] error in
            guard let self else { return }
            self.cancelPortInactivityTimeout()
            let nsError = error as NSError?
            self.logDiagnostic(
                self.makeDiagnostic(
                    direction: .portReceive,
                    outcome: .relayCancelled,
                    errorDomain: nsError?.domain,
                    errorCode: nsError?.code
                )
            )
        }
    }

    private func armPortInactivityTimeout() {
        inactivityTask?.cancel()
        inactivityTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.portInactivityTimeout)
            guard self.port.isDisconnected == false else { return }
            self.logDiagnostic(
                self.makeDiagnostic(
                    direction: .portReceive,
                    outcome: .relayCancelled,
                    errorDomain: SumiNativeMessagingRelay.errorDomain,
                    errorCode: SumiNativeMessagingRelay.ErrorCode.relayCancelled.rawValue
                )
            )
            self.disconnect()
        }
    }

    private func cancelPortInactivityTimeout() {
        inactivityTask?.cancel()
        inactivityTask = nil
    }

    private func makeDiagnostic(
        direction: SafariExtensionNativeMessagingDirection,
        outcome: SafariExtensionNativeMessagingOutcome,
        errorDomain: String? = nil,
        errorCode: Int? = nil,
        adapter: SumiNativeMessagingProtocolAdapter? = nil
    ) -> SafariExtensionNativeMessagingDiagnostic {
        let resolvedAdapter = adapter ?? self.adapter
        let base = SafariExtensionNativeMessagingDiagnostic(
            extensionId: extensionId,
            direction: direction,
            requestedApplicationIdentifier: port.applicationIdentifier,
            hostBundleIdentifier: resolvedHostBundleIdentifier,
            resolverBucket: resolverBucket,
            outcome: outcome,
            errorDomain: errorDomain,
            errorCode: errorCode,
            protocolAdapterAvailable: resolvedAdapter != nil,
            appResolved: true
        )
        return SafariExtensionNativeMessagingDiagnosticEnrichment.enrich(
            base,
            adapter: resolvedAdapter,
            adapterIdentifier: resolvedAdapter?.protocolIdentifier
        )
    }
}

// Legacy handler name retained for ExtensionManager port registry.
typealias NativeMessagingHandler = SumiNativeMessagingPortSession
