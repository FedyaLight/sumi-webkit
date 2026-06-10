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
    private let adapterRegistry: SumiNativeMessagingAdapterRegistry
    private let launchPolicy: SumiCompanionAppLaunchPolicy
    private let loopGuard: SumiNativeMessagingRelayLoopGuard
    private let extensionsModuleEnabled: () -> Bool
    private let isPrivateBrowsing: () -> Bool
    private let logDiagnostic: @MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void

    init(
        importStore: SafariExtensionImportStore = .shared,
        launcher: SumiHostApplicationLaunching = SumiNSWorkspaceHostApplicationLauncher(),
        adapterRegistry: SumiNativeMessagingAdapterRegistry = .shared,
        launchPolicy: SumiCompanionAppLaunchPolicy = .shared,
        loopGuard: SumiNativeMessagingRelayLoopGuard = SumiNativeMessagingRelayLoopGuard(),
        extensionsModuleEnabled: @escaping @MainActor () -> Bool = { SumiExtensionsModule.shared.isEnabled },
        isPrivateBrowsing: @escaping @MainActor () -> Bool = { false },
        logDiagnostic: (@MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void)? = nil
    ) {
        self.importStore = importStore
        self.launcher = launcher
        self.adapterRegistry = adapterRegistry
        self.launchPolicy = launchPolicy
        self.loopGuard = loopGuard
        self.extensionsModuleEnabled = extensionsModuleEnabled
        self.isPrivateBrowsing = isPrivateBrowsing
        self.logDiagnostic = logDiagnostic ?? Self.defaultDiagnosticLogger
    }

    func handleSendMessage(
        applicationIdentifier: String?,
        message: Any,
        extensionId: String?,
        profileId: UUID? = nil,
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
            replyHandler(
                nil,
                SumiNativeMessagingErrorMapper.relayError(
                    code: .extensionContextMissing,
                    diagnostic: diagnostic
                )
            )
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
            replyHandler(
                nil,
                SumiNativeMessagingErrorMapper.relayError(code: .policyDenied, diagnostic: diagnostic)
            )
            return
        case .success:
            break
        }

        if extensionsModuleEnabled() == false {
            launchPolicy.clearPendingState()
            loopGuard.clearAll()
        }

        let evaluation = SumiCompanionAppResolver.evaluate(
            requestedApplicationIdentifier: applicationIdentifier,
            extensionId: extensionId,
            installedExtensions: installedExtensions,
            importStore: importStore,
            launcher: launcher,
            adapterRegistry: adapterRegistry,
            launchPolicy: launchPolicy
        )

        guard let detail = evaluation.detail else {
            let diagnostic = SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation
            )
            logDiagnostic(diagnostic)
            replyHandler(
                nil,
                SumiNativeMessagingErrorMapper.relayError(
                    code: SumiCompanionAppResolver.relayErrorCode(for: evaluation),
                    diagnostic: diagnostic
                )
            )
            return
        }

        if case .appNotFound = evaluation {
            let diagnostic = SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation,
                outcome: .hostNotFound
            )
            logDiagnostic(diagnostic)
            replyHandler(
                nil,
                SumiNativeMessagingErrorMapper.relayError(code: .hostNotFound, diagnostic: diagnostic)
            )
            return
        }

        let loopKey = SumiNativeMessagingRelayLoopGuard.SessionKey(
            profileId: profileId,
            extensionId: extensionId,
            applicationIdentifier: SumiNativeMessagingRelayLoopGuard.canonicalApplicationIdentifier(
                requested: applicationIdentifier,
                hostBundleIdentifier: detail.resolvedBundleIdentifier
            )
        )
        let loopEvaluation = loopGuard.evaluate(
            key: loopKey,
            hostBundleIdentifier: detail.resolvedBundleIdentifier
        )

        if loopEvaluation.launchSuppressed {
            let diagnostic = SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: .launchSuppressed(detail),
                outcome: .launchSuppressed,
                launchSuppressed: true,
                retryCountBucket: loopEvaluation.retryCountBucket
            )
            logDiagnostic(diagnostic)
            replyHandler(
                nil,
                SumiNativeMessagingErrorMapper.relayError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: diagnostic
                )
            )
            return
        }

        guard let adapter = adapterRegistry.adapter(
            forHostBundleIdentifier: detail.resolvedBundleIdentifier
        ) else {
            loopGuard.recordCompanionAppProtocolUnknown(key: loopKey, launchAttempted: false)
            let diagnostic = SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation,
                outcome: .companionAppProtocolUnknown,
                launchSuppressed: false,
                retryCountBucket: loopEvaluation.retryCountBucket
            )
            logDiagnostic(diagnostic)
            replyHandler(
                nil,
                SumiNativeMessagingErrorMapper.relayError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: diagnostic
                )
            )
            return
        }

        guard SumiCompanionAppResolver.shouldLaunchApp(for: evaluation) else {
            loopGuard.recordCompanionAppProtocolUnknown(key: loopKey, launchAttempted: false)
            let rateLimited: Bool = {
                if case .launchRateLimited = evaluation { return true }
                return false
            }()
            let diagnostic = SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation,
                launchSuppressed: rateLimited,
                retryCountBucket: loopEvaluation.retryCountBucket
            )
            logDiagnostic(diagnostic)
            replyHandler(
                nil,
                SumiNativeMessagingErrorMapper.relayError(
                    code: SumiCompanionAppResolver.relayErrorCode(for: evaluation),
                    diagnostic: diagnostic
                )
            )
            return
        }

        let once = OnceReplyHandler(replyHandler)
        SumiNativeMessagingConnection.relayOneShot(
            applicationIdentifier: applicationIdentifier,
            message: message,
            extensionId: extensionId,
            evaluation: evaluation,
            adapter: adapter,
            launcher: launcher,
            launchPolicy: launchPolicy,
            launchSuppressed: loopEvaluation.launchSuppressed,
            retryCountBucket: loopEvaluation.retryCountBucket,
            logDiagnostic: logDiagnostic,
            replyHandler: { [self] value, error in
                if error != nil {
                    self.loopGuard.recordCompanionAppProtocolUnknown(
                        key: loopKey,
                        launchAttempted: true
                    )
                }
                once.call(value, error)
            }
        )
    }

    @discardableResult
    func handleConnect(
        port: any SumiNativeMessagingPortControlling,
        extensionId: String?,
        profileId: UUID? = nil,
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
            completionHandler(
                SumiNativeMessagingErrorMapper.relayError(
                    code: .extensionContextMissing,
                    diagnostic: diagnostic
                )
            )
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
            completionHandler(
                SumiNativeMessagingErrorMapper.relayError(code: .policyDenied, diagnostic: diagnostic)
            )
            return nil
        case .success:
            break
        }

        let evaluation = SumiCompanionAppResolver.evaluate(
            requestedApplicationIdentifier: applicationIdentifier,
            extensionId: extensionId,
            installedExtensions: installedExtensions,
            importStore: importStore,
            launcher: launcher,
            adapterRegistry: adapterRegistry,
            launchPolicy: launchPolicy
        )

        guard let detail = evaluation.detail else {
            let diagnostic = SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation
            )
            logDiagnostic(diagnostic)
            port.disconnect()
            completionHandler(
                SumiNativeMessagingErrorMapper.relayError(
                    code: SumiCompanionAppResolver.relayErrorCode(for: evaluation),
                    diagnostic: diagnostic
                )
            )
            return nil
        }

        let hostBundleIdentifier = detail.resolvedBundleIdentifier
        let resolverBucket = evaluation.legacyResolverBucket

        logDiagnostic(
            SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation,
                outcome: .hostResolved
            )
        )

        let loopKey = SumiNativeMessagingRelayLoopGuard.SessionKey(
            profileId: profileId,
            extensionId: extensionId,
            applicationIdentifier: SumiNativeMessagingRelayLoopGuard.canonicalApplicationIdentifier(
                requested: applicationIdentifier,
                hostBundleIdentifier: hostBundleIdentifier
            )
        )
        let loopEvaluation = loopGuard.evaluate(
            key: loopKey,
            hostBundleIdentifier: hostBundleIdentifier
        )

        if loopEvaluation.launchSuppressed {
            let diagnostic = SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: .launchSuppressed(detail),
                outcome: .launchSuppressed,
                launchSuppressed: true,
                retryCountBucket: loopEvaluation.retryCountBucket
            )
            logDiagnostic(diagnostic)
            port.disconnect(
                throwing: SumiNativeMessagingErrorMapper.messagePortDisconnectError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: diagnostic
                )
            )
            completionHandler(
                SumiNativeMessagingErrorMapper.relayError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: diagnostic
                )
            )
            return nil
        }

        guard let adapter = adapterRegistry.adapter(forHostBundleIdentifier: hostBundleIdentifier) else {
            loopGuard.recordCompanionAppProtocolUnknown(key: loopKey, launchAttempted: false)
            let diagnostic = SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation,
                outcome: .companionAppProtocolUnknown
            )
            logDiagnostic(diagnostic)
            port.disconnect(
                throwing: SumiNativeMessagingErrorMapper.messagePortDisconnectError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: diagnostic
                )
            )
            completionHandler(
                SumiNativeMessagingErrorMapper.relayError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: diagnostic
                )
            )
            return nil
        }

        let session = SumiNativeMessagingPortSession(
            port: port,
            adapter: adapter,
            extensionId: extensionId,
            hostBundleIdentifier: hostBundleIdentifier,
            resolverBucket: resolverBucket,
            logDiagnostic: logDiagnostic,
            companionProtocolErrorProvider: {
                SumiNativeMessagingErrorMapper.messagePortDisconnectError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: SafariExtensionNativeMessagingDiagnostic(
                        extensionId: extensionId,
                        direction: .portRelay,
                        requestedApplicationIdentifier: applicationIdentifier,
                        hostBundleIdentifier: hostBundleIdentifier,
                        resolverBucket: resolverBucket,
                        outcome: .companionAppProtocolUnknown,
                        errorDomain: Self.errorDomain,
                        errorCode: ErrorCode.companionAppProtocolUnknown.rawValue,
                        isContainingApp: detail.isContainingApp,
                        protocolAdapterAvailable: detail.protocolAdapterAvailable,
                        launchAllowed: detail.launchAllowed
                    )
                )
            }
        )
        registerHandler(session)

        guard launcher.urlForApplication(withBundleIdentifier: hostBundleIdentifier) != nil else {
            let diagnostic = SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: .appNotFound(detail),
                outcome: .hostNotFound
            )
            logDiagnostic(diagnostic)
            session.disconnect()
            completionHandler(
                SumiNativeMessagingErrorMapper.relayError(code: .hostNotFound, diagnostic: diagnostic)
            )
            return session
        }

        let gatedLauncher = SumiLaunchPolicyGatedHostApplicationLauncher(
            underlying: launcher,
            launchPolicy: launchPolicy,
            hostBundleIdentifier: hostBundleIdentifier,
            protocolAdapterAvailable: detail.protocolAdapterAvailable
        )

        adapter.connectPort(session: session, launcher: gatedLauncher) { [self] error in
            if let error {
                let nsError = error as NSError
                let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                    extensionId: extensionId,
                    direction: .connect,
                    requestedApplicationIdentifier: applicationIdentifier,
                    hostBundleIdentifier: hostBundleIdentifier,
                    resolverBucket: resolverBucket,
                    outcome: nsError.code == ErrorCode.hostNotFound.rawValue
                        ? .hostNotFound
                        : .hostLaunchFailed,
                    errorDomain: nsError.domain,
                    errorCode: nsError.code,
                    isContainingApp: detail.isContainingApp,
                    protocolAdapterAvailable: detail.protocolAdapterAvailable,
                    launchAllowed: detail.launchAllowed
                )
                self.logDiagnostic(diagnostic)
                session.disconnect()
                completionHandler(error)
                return
            }

            self.logDiagnostic(
                SafariExtensionNativeMessagingDiagnostic(
                    extensionId: extensionId,
                    direction: .connect,
                    requestedApplicationIdentifier: applicationIdentifier,
                    hostBundleIdentifier: hostBundleIdentifier,
                    resolverBucket: resolverBucket,
                    outcome: .portConnected,
                    errorDomain: nil,
                    errorCode: nil,
                    isContainingApp: detail.isContainingApp,
                    protocolAdapterAvailable: detail.protocolAdapterAvailable,
                    launchAllowed: detail.launchAllowed
                )
            )
            completionHandler(nil)
        }

        return session
    }

    func clearCompanionState(forExtensionId extensionId: String, profileId: UUID? = nil) {
        launchPolicy.clearPendingState()
        loopGuard.clear(forExtensionId: extensionId, profileId: profileId)
    }

    func clearLoopGuard(forExtensionId extensionId: String, profileId: UUID? = nil) {
        clearCompanionState(forExtensionId: extensionId, profileId: profileId)
    }

    func clearAllLoopGuardState() {
        launchPolicy.clearPendingState()
        loopGuard.clearAll()
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
            containing=\(diagnostic.isContainingApp.map(String.init) ?? "-") \
            adapter=\(diagnostic.protocolAdapterAvailable.map(String.init) ?? "-") \
            launchAllowed=\(diagnostic.launchAllowed.map(String.init) ?? "-") \
            resolver=\(diagnostic.resolverBucket?.rawValue ?? "-") \
            outcome=\(diagnostic.outcome.rawValue) \
            launch=\(diagnostic.launchAttempted.map(String.init) ?? "-") \
            suppressed=\(diagnostic.launchSuppressed.map(String.init) ?? "-") \
            retry=\(diagnostic.retryCountBucket?.rawValue ?? "-") \
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
