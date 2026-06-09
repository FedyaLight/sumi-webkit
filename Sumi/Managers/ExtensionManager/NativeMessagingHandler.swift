//
//  NativeMessagingHandler.swift
//  Sumi
//
//  Retains a WKWebExtension.MessagePort for Safari native messaging sessions.
//  Never logs message bodies or credentials.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class NativeMessagingHandler: NSObject {
    private let port: WKWebExtension.MessagePort
    private let extensionId: String
    private let hostBundleIdentifier: String
    private let logDiagnostic: (SafariExtensionNativeMessagingDiagnostic) -> Void
    private let hostRelayErrorProvider: () -> NSError

    init(
        port: WKWebExtension.MessagePort,
        extensionId: String,
        hostBundleIdentifier: String,
        logDiagnostic: @escaping (SafariExtensionNativeMessagingDiagnostic) -> Void,
        hostRelayErrorProvider: @escaping () -> NSError
    ) {
        self.port = port
        self.extensionId = extensionId
        self.hostBundleIdentifier = hostBundleIdentifier
        self.logDiagnostic = logDiagnostic
        self.hostRelayErrorProvider = hostRelayErrorProvider
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
                        outcome: .hostRelayUnavailable,
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
                    outcome: .hostRelayUnavailable,
                    errorDomain: SafariExtensionNativeMessagingHost.errorDomain,
                    errorCode: SafariExtensionNativeMessagingHost.ErrorCode.hostRelayUnavailable.rawValue
                )
            )
            self.port.disconnect(throwing: self.hostRelayErrorProvider())
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
                    outcome: .hostRelayUnavailable,
                    errorDomain: nsError?.domain,
                    errorCode: nsError?.code
                )
            )
        }
    }
}
