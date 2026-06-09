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
    private let port: WKWebExtension.MessagePort
    private let extensionId: String
    private let hostBundleIdentifier: String
    private let resolverBucket: SumiNativeMessagingResolverBucket
    private let logDiagnostic: (SafariExtensionNativeMessagingDiagnostic) -> Void
    private let companionProtocolErrorProvider: () -> NSError

    init(
        port: WKWebExtension.MessagePort,
        extensionId: String,
        hostBundleIdentifier: String,
        resolverBucket: SumiNativeMessagingResolverBucket,
        logDiagnostic: @escaping (SafariExtensionNativeMessagingDiagnostic) -> Void,
        companionProtocolErrorProvider: @escaping () -> NSError
    ) {
        self.port = port
        self.extensionId = extensionId
        self.hostBundleIdentifier = hostBundleIdentifier
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

    private func wirePort() {
        port.messageHandler = { [weak self] _, error in
            guard let self else { return }
            if let error {
                let nsError = error as NSError
                self.logDiagnostic(
                    SafariExtensionNativeMessagingDiagnostic(
                        extensionId: self.extensionId,
                        direction: .portReceive,
                        requestedApplicationIdentifier: self.port.applicationIdentifier,
                        hostBundleIdentifier: self.hostBundleIdentifier,
                        resolverBucket: self.resolverBucket,
                        outcome: .companionAppProtocolUnknown,
                        errorDomain: nsError.domain,
                        errorCode: nsError.code
                    )
                )
                return
            }

            self.logDiagnostic(
                SafariExtensionNativeMessagingDiagnostic(
                    extensionId: self.extensionId,
                    direction: .portRelay,
                    requestedApplicationIdentifier: self.port.applicationIdentifier,
                    hostBundleIdentifier: self.hostBundleIdentifier,
                    resolverBucket: self.resolverBucket,
                    outcome: .companionAppProtocolUnknown,
                    errorDomain: SumiNativeMessagingRelay.errorDomain,
                    errorCode: SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
                )
            )
            self.port.disconnect(throwing: self.companionProtocolErrorProvider())
        }

        port.disconnectHandler = { [weak self] error in
            guard let self else { return }
            let nsError = error as NSError?
            self.logDiagnostic(
                SafariExtensionNativeMessagingDiagnostic(
                    extensionId: self.extensionId,
                    direction: .portReceive,
                    requestedApplicationIdentifier: self.port.applicationIdentifier,
                    hostBundleIdentifier: self.hostBundleIdentifier,
                    resolverBucket: self.resolverBucket,
                    outcome: .companionAppProtocolUnknown,
                    errorDomain: nsError?.domain,
                    errorCode: nsError?.code
                )
            )
        }
    }
}

// Legacy handler name retained for ExtensionManager port registry.
typealias NativeMessagingHandler = SumiNativeMessagingPortSession
