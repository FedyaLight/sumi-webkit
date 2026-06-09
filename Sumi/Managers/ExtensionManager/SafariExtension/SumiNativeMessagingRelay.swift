//
//  SumiNativeMessagingRelay.swift
//  Sumi
//
//  Sumi-owned native/app messaging relay on public WKWebExtensionControllerDelegate hooks.
//

import Foundation
import WebKit

@MainActor
final class SumiNativeMessagingRelay {
    enum ErrorCode: Int {
        case hostNotFound = 1
        case hostLaunchFailed = 2
        case companionAppProtocolUnknown = 3
        case extensionContextMissing = 4
        case policyDenied = 5
        case relayTimeout = 6
        case relayCancelled = 7
    }

    static let errorDomain = "Sumi.SafariNativeMessaging"
    static let delegateMethodsRegistered = true

    private let importStore: SafariExtensionImportStore
    private let launcher: SumiHostApplicationLaunching
    private let extensionsModuleEnabled: () -> Bool
    private let isPrivateBrowsing: () -> Bool
    private let logDiagnostic: @MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void

    init(
        importStore: SafariExtensionImportStore = .shared,
        launcher: SumiHostApplicationLaunching = SumiNSWorkspaceHostApplicationLauncher(),
        extensionsModuleEnabled: @escaping @MainActor () -> Bool = { SumiExtensionsModule.shared.isEnabled },
        isPrivateBrowsing: @escaping @MainActor () -> Bool = { false },
        logDiagnostic: (@MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void)? = nil
    ) {
        self.importStore = importStore
        self.launcher = launcher
        self.extensionsModuleEnabled = extensionsModuleEnabled
        self.isPrivateBrowsing = isPrivateBrowsing
        self.logDiagnostic = logDiagnostic ?? Self.defaultDiagnosticLogger
    }

    func handleSendMessage(
        applicationIdentifier: String?,
        message: Any,
        extensionId: String?,
        installedExtensions: [InstalledExtension],
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        guard let extensionId else {
            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: "unknown",
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: nil,
                resolverBucket: nil,
                outcome: .extensionContextMissing,
                errorDomain: Self.errorDomain,
                errorCode: ErrorCode.extensionContextMissing.rawValue
            )
            logDiagnostic(diagnostic)
            replyHandler(nil, Self.makeError(code: .extensionContextMissing, diagnostic: diagnostic))
            return
        }

        let installed = installedExtensions.first { $0.id == extensionId }
        switch evaluatePolicy(
            extensionId: extensionId,
            installed: installed,
            requestedApplicationIdentifier: applicationIdentifier
        ) {
        case .failure(let denial):
            let diagnostic = policyDeniedDiagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                denial: denial
            )
            logDiagnostic(diagnostic)
            replyHandler(nil, Self.makeError(code: .policyDenied, diagnostic: diagnostic))
            return
        case .success:
            break
        }

        guard let resolution = SumiNativeMessagingAppResolver.resolve(
            requestedApplicationIdentifier: applicationIdentifier,
            extensionId: extensionId,
            installedExtensions: installedExtensions,
            importStore: importStore
        ) else {
            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: nil,
                resolverBucket: .noMatch,
                outcome: .hostNotFound,
                errorDomain: Self.errorDomain,
                errorCode: ErrorCode.hostNotFound.rawValue
            )
            logDiagnostic(diagnostic)
            replyHandler(nil, Self.makeError(code: .hostNotFound, diagnostic: diagnostic))
            return
        }

        let once = OnceReplyHandler(replyHandler)
        SumiNativeMessagingConnection.relayOneShot(
            applicationIdentifier: applicationIdentifier,
            message: message,
            extensionId: extensionId,
            hostResolution: resolution,
            launcher: launcher,
            logDiagnostic: logDiagnostic,
            replyHandler: once.call
        )
    }

    @discardableResult
    func handleConnect(
        port: WKWebExtension.MessagePort,
        extensionId: String?,
        installedExtensions: [InstalledExtension],
        registerHandler: (SumiNativeMessagingPortSession) -> Void,
        completionHandler: @escaping ((any Error)?) -> Void
    ) -> SumiNativeMessagingPortSession? {
        let applicationIdentifier = port.applicationIdentifier

        guard let extensionId else {
            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: "unknown",
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: nil,
                resolverBucket: nil,
                outcome: .extensionContextMissing,
                errorDomain: Self.errorDomain,
                errorCode: ErrorCode.extensionContextMissing.rawValue
            )
            logDiagnostic(diagnostic)
            port.disconnect()
            completionHandler(Self.makeError(code: .extensionContextMissing, diagnostic: diagnostic))
            return nil
        }

        let installed = installedExtensions.first { $0.id == extensionId }
        switch evaluatePolicy(
            extensionId: extensionId,
            installed: installed,
            requestedApplicationIdentifier: applicationIdentifier
        ) {
        case .failure(let denial):
            let diagnostic = policyDeniedDiagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                denial: denial
            )
            logDiagnostic(diagnostic)
            port.disconnect()
            completionHandler(Self.makeError(code: .policyDenied, diagnostic: diagnostic))
            return nil
        case .success:
            break
        }

        guard let resolution = SumiNativeMessagingAppResolver.resolve(
            requestedApplicationIdentifier: applicationIdentifier,
            extensionId: extensionId,
            installedExtensions: installedExtensions,
            importStore: importStore
        ) else {
            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: nil,
                resolverBucket: .noMatch,
                outcome: .hostNotFound,
                errorDomain: Self.errorDomain,
                errorCode: ErrorCode.hostNotFound.rawValue
            )
            logDiagnostic(diagnostic)
            port.disconnect()
            completionHandler(Self.makeError(code: .hostNotFound, diagnostic: diagnostic))
            return nil
        }

        let hostBundleIdentifier = resolution.hostBundleIdentifier

        logDiagnostic(
            SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: hostBundleIdentifier,
                resolverBucket: resolution.bucket,
                outcome: .hostResolved,
                errorDomain: nil,
                errorCode: nil
            )
        )

        let session = SumiNativeMessagingPortSession(
            port: port,
            extensionId: extensionId,
            hostBundleIdentifier: hostBundleIdentifier,
            resolverBucket: resolution.bucket,
            logDiagnostic: logDiagnostic,
            companionProtocolErrorProvider: {
                Self.makeError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: SafariExtensionNativeMessagingDiagnostic(
                        extensionId: extensionId,
                        direction: .portRelay,
                        requestedApplicationIdentifier: applicationIdentifier,
                        hostBundleIdentifier: hostBundleIdentifier,
                        resolverBucket: resolution.bucket,
                        outcome: .companionAppProtocolUnknown,
                        errorDomain: Self.errorDomain,
                        errorCode: ErrorCode.companionAppProtocolUnknown.rawValue
                    )
                )
            }
        )
        registerHandler(session)

        guard launcher.urlForApplication(withBundleIdentifier: hostBundleIdentifier) != nil else {
            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: hostBundleIdentifier,
                resolverBucket: resolution.bucket,
                outcome: .hostNotFound,
                errorDomain: Self.errorDomain,
                errorCode: ErrorCode.hostNotFound.rawValue
            )
            logDiagnostic(diagnostic)
            session.disconnect()
            completionHandler(Self.makeError(code: .hostNotFound, diagnostic: diagnostic))
            return session
        }

        Task { @MainActor in
            do {
                try await launcher.openApplication(withBundleIdentifier: hostBundleIdentifier)
                logDiagnostic(
                    SafariExtensionNativeMessagingDiagnostic(
                        extensionId: extensionId,
                        direction: .connect,
                        requestedApplicationIdentifier: applicationIdentifier,
                        hostBundleIdentifier: hostBundleIdentifier,
                        resolverBucket: resolution.bucket,
                        outcome: .hostLaunched,
                        errorDomain: nil,
                        errorCode: nil
                    )
                )
            } catch {
                let nsError = error as NSError
                let launchCode: ErrorCode =
                    nsError.domain == Self.errorDomain
                    && nsError.code == ErrorCode.hostNotFound.rawValue
                    ? .hostNotFound
                    : .hostLaunchFailed
                let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                    extensionId: extensionId,
                    direction: .connect,
                    requestedApplicationIdentifier: applicationIdentifier,
                    hostBundleIdentifier: hostBundleIdentifier,
                    resolverBucket: resolution.bucket,
                    outcome: launchCode == .hostNotFound ? .hostNotFound : .hostLaunchFailed,
                    errorDomain: nsError.domain,
                    errorCode: nsError.code
                )
                logDiagnostic(diagnostic)
                session.disconnect()
                completionHandler(Self.makeError(code: launchCode, diagnostic: diagnostic))
                return
            }

            logDiagnostic(
                SafariExtensionNativeMessagingDiagnostic(
                    extensionId: extensionId,
                    direction: .connect,
                    requestedApplicationIdentifier: applicationIdentifier,
                    hostBundleIdentifier: hostBundleIdentifier,
                    resolverBucket: resolution.bucket,
                    outcome: .portConnected,
                    errorDomain: nil,
                    errorCode: nil
                )
            )
            completionHandler(nil)
        }

        return session
    }

    static func makeError(
        code: ErrorCode,
        description: String? = nil,
        diagnostic: SafariExtensionNativeMessagingDiagnostic?
    ) -> NSError {
        let message: String
        switch code {
        case .hostNotFound:
            message = description
                ?? "The native messaging host application could not be resolved."
        case .hostLaunchFailed:
            message = description
                ?? "The native messaging host application could not be launched."
        case .companionAppProtocolUnknown:
            message = description
                ?? "Companion host application messaging protocol is not implemented in Sumi."
        case .extensionContextMissing:
            message = description
                ?? "The extension context for native messaging could not be resolved."
        case .policyDenied:
            message = description
                ?? "Native messaging is not permitted for this extension session."
        case .relayTimeout:
            message = description
                ?? "Native messaging relay timed out."
        case .relayCancelled:
            message = description
                ?? "Native messaging relay was cancelled."
        }

        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let diagnostic {
            userInfo["SumiNativeMessagingDiagnostic"] = diagnostic.outcome.rawValue
            if let hostBundleIdentifier = diagnostic.hostBundleIdentifier {
                userInfo["SumiNativeMessagingHostBundleIdentifier"] = hostBundleIdentifier
            }
            if let resolverBucket = diagnostic.resolverBucket {
                userInfo["SumiNativeMessagingResolverBucket"] = resolverBucket.rawValue
            }
        }
        return NSError(domain: errorDomain, code: code.rawValue, userInfo: userInfo)
    }

    private func evaluatePolicy(
        extensionId: String,
        installed: InstalledExtension?,
        requestedApplicationIdentifier: String?
    ) -> Result<Void, SumiNativeMessagingRelayPolicyDenial> {
        SumiNativeMessagingRelayPolicy.evaluate(
            SumiNativeMessagingRelayPolicyContext(
                extensionsModuleEnabled: extensionsModuleEnabled(),
                extensionId: extensionId,
                installedExtension: installed,
                isPrivateBrowsing: isPrivateBrowsing(),
                requestedApplicationIdentifier: requestedApplicationIdentifier
            )
        )
    }

    private func policyDeniedDiagnostic(
        extensionId: String,
        direction: SafariExtensionNativeMessagingDirection,
        requestedApplicationIdentifier: String?,
        denial: SumiNativeMessagingRelayPolicyDenial
    ) -> SafariExtensionNativeMessagingDiagnostic {
        SafariExtensionNativeMessagingDiagnostic(
            extensionId: extensionId,
            direction: direction,
            requestedApplicationIdentifier: requestedApplicationIdentifier,
            hostBundleIdentifier: nil,
            resolverBucket: nil,
            outcome: .policyDenied,
            errorDomain: Self.errorDomain,
            errorCode: ErrorCode.policyDenied.rawValue
        )
    }

    private static let defaultDiagnosticLogger: @MainActor (
        SafariExtensionNativeMessagingDiagnostic
    ) -> Void = { diagnostic in
        guard RuntimeDiagnostics.isVerboseEnabled else { return }
        RuntimeDiagnostics.debug(category: "SafariNativeMessaging") {
            """
            ext=\(diagnostic.extensionId) \
            dir=\(diagnostic.direction.rawValue) \
            req=\(diagnostic.requestedApplicationIdentifier ?? "(nil)") \
            host=\(diagnostic.hostBundleIdentifier ?? "(nil)") \
            resolver=\(diagnostic.resolverBucket?.rawValue ?? "-") \
            outcome=\(diagnostic.outcome.rawValue) \
            err=\(diagnostic.errorDomain ?? "-")/\(diagnostic.errorCode.map(String.init) ?? "-")
            """
        }
    }
}

@MainActor
private final class OnceReplyHandler {
    private var handler: ((Any?, (any Error)?) -> Void)?
    private var fulfilled = false

    init(_ handler: @escaping (Any?, (any Error)?) -> Void) {
        self.handler = handler
    }

    func call(_ value: Any?, _ error: (any Error)?) {
        guard fulfilled == false else { return }
        fulfilled = true
        handler?(value, error)
        handler = nil
    }
}
