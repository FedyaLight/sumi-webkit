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
    private let extensionId: String
    private(set) var resolvedHostBundleIdentifier: String
    private let resolverBucket: SumiNativeMessagingResolverBucket
    private let logDiagnostic: (SafariExtensionNativeMessagingDiagnostic) -> Void
    private let companionProtocolErrorProvider: () -> NSError

    init(
        port: any SumiNativeMessagingPortControlling,
        adapter: SumiNativeMessagingProtocolAdapter?,
        extensionId: String,
        hostBundleIdentifier: String,
        resolverBucket: SumiNativeMessagingResolverBucket,
        logDiagnostic: @escaping (SafariExtensionNativeMessagingDiagnostic) -> Void,
        companionProtocolErrorProvider: @escaping () -> NSError
    ) {
        self.port = port
        self.adapter = adapter
        self.extensionId = extensionId
        self.resolvedHostBundleIdentifier = hostBundleIdentifier
        self.resolverBucket = resolverBucket
        self.logDiagnostic = logDiagnostic
        self.companionProtocolErrorProvider = companionProtocolErrorProvider
        super.init()
        wirePort()
    }

    func disconnect() {
        guard port.isDisconnected == false else { return }
        port.disconnect()
    }

    func disconnectDueToUnsupportedProtocol() {
        guard port.isDisconnected == false else { return }
        port.disconnect(throwing: companionProtocolErrorProvider())
    }

    private func wirePort() {
        port.messageHandler = { [weak self] message, error in
            guard let self else { return }
            if let error {
                let nsError = error as NSError
                self.logDiagnostic(
                    SafariExtensionNativeMessagingDiagnostic(
                        extensionId: self.extensionId,
                        direction: .portReceive,
                        requestedApplicationIdentifier: self.port.applicationIdentifier,
                        hostBundleIdentifier: self.resolvedHostBundleIdentifier,
                        resolverBucket: self.resolverBucket,
                        outcome: .companionAppProtocolUnknown,
                        errorDomain: nsError.domain,
                        errorCode: nsError.code
                    )
                )
                return
            }

            guard let adapter = self.adapter else {
                self.logDiagnostic(
                    SafariExtensionNativeMessagingDiagnostic(
                        extensionId: self.extensionId,
                        direction: .portRelay,
                        requestedApplicationIdentifier: self.port.applicationIdentifier,
                        hostBundleIdentifier: self.resolvedHostBundleIdentifier,
                        resolverBucket: self.resolverBucket,
                        outcome: .companionAppProtocolUnknown,
                        errorDomain: SumiNativeMessagingRelay.errorDomain,
                        errorCode: SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
                    )
                )
                self.disconnectDueToUnsupportedProtocol()
                return
            }

            _ = message
            let relayed = adapter.relayPortMessage(session: self, message: message)
            if relayed == false {
                self.logDiagnostic(
                    SafariExtensionNativeMessagingDiagnostic(
                        extensionId: self.extensionId,
                        direction: .portRelay,
                        requestedApplicationIdentifier: self.port.applicationIdentifier,
                        hostBundleIdentifier: self.resolvedHostBundleIdentifier,
                        resolverBucket: self.resolverBucket,
                        outcome: .companionAppProtocolUnknown,
                        errorDomain: SumiNativeMessagingRelay.errorDomain,
                        errorCode: SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
                    )
                )
                self.disconnectDueToUnsupportedProtocol()
            }
        }

        port.disconnectHandler = { [weak self] error in
            guard let self else { return }
            let nsError = error as NSError?
            self.logDiagnostic(
                SafariExtensionNativeMessagingDiagnostic(
                    extensionId: self.extensionId,
                    direction: .portReceive,
                    requestedApplicationIdentifier: self.port.applicationIdentifier,
                    hostBundleIdentifier: self.resolvedHostBundleIdentifier,
                    resolverBucket: self.resolverBucket,
                    outcome: .relayCancelled,
                    errorDomain: nsError?.domain,
                    errorCode: nsError?.code
                )
            )
        }
    }
}

// Legacy handler name retained for ExtensionManager port registry.
typealias NativeMessagingHandler = SumiNativeMessagingPortSession
