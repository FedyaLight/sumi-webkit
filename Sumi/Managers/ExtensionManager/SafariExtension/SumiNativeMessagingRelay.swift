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
    private let diagnosticCoalescer: SumiNativeMessagingDiagnosticCoalescer
    private let extensionsModuleEnabled: () -> Bool
    private let isPrivateBrowsing: () -> Bool
    private let profileRuntimeLoaded: () -> Bool
    private let rawLogDiagnostic: @MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void

    init(
        importStore: SafariExtensionImportStore = .shared,
        launcher: SumiHostApplicationLaunching = SumiNSWorkspaceHostApplicationLauncher(),
        adapterRegistry: SumiNativeMessagingAdapterRegistry = .shared,
        launchPolicy: SumiCompanionAppLaunchPolicy = .shared,
        loopGuard: SumiNativeMessagingRelayLoopGuard = SumiNativeMessagingRelayLoopGuard(),
        extensionsModuleEnabled: @escaping @MainActor () -> Bool = { SumiExtensionsModule.shared.isEnabled },
        isPrivateBrowsing: @escaping @MainActor () -> Bool = { false },
        profileRuntimeLoaded: @escaping @MainActor () -> Bool = { true },
        logDiagnostic: (@MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void)? = nil
    ) {
        self.importStore = importStore
        self.launcher = launcher
        self.adapterRegistry = adapterRegistry
        self.launchPolicy = launchPolicy
        self.loopGuard = loopGuard
        self.extensionsModuleEnabled = extensionsModuleEnabled
        self.isPrivateBrowsing = isPrivateBrowsing
        self.profileRuntimeLoaded = profileRuntimeLoaded
        let resolvedLogger = logDiagnostic ?? Self.defaultDiagnosticLogger
        self.rawLogDiagnostic = resolvedLogger
        self.diagnosticCoalescer = SumiNativeMessagingDiagnosticCoalescer(
            downstream: { diagnostic, style in
                switch style {
                case .detailed:
                    resolvedLogger(diagnostic)
                case .summarized(let repeatCount, let retryCountBucket):
                    resolvedLogger(
                        SafariExtensionNativeMessagingDiagnostic(
                            extensionId: diagnostic.extensionId,
                            direction: diagnostic.direction,
                            requestedApplicationIdentifier: diagnostic.requestedApplicationIdentifier,
                            hostBundleIdentifier: diagnostic.hostBundleIdentifier,
                            resolverBucket: diagnostic.resolverBucket,
                            outcome: diagnostic.outcome,
                            errorDomain: diagnostic.errorDomain,
                            errorCode: diagnostic.errorCode,
                            launchAttempted: diagnostic.launchAttempted,
                            launchSuppressed: true,
                            retryCountBucket: retryCountBucket,
                            isContainingApp: diagnostic.isContainingApp,
                            protocolAdapterAvailable: diagnostic.protocolAdapterAvailable,
                            launchAllowed: diagnostic.launchAllowed,
                            sessionState: diagnostic.sessionState
                        )
                    )
                    RuntimeDiagnostics.debug(category: "SafariNativeMessaging") {
                        """
                        coalesced ext=\(diagnostic.extensionId) \
                        dir=\(diagnostic.direction.rawValue) \
                        outcome=\(diagnostic.outcome.rawValue) \
                        repeatCount=\(repeatCount) \
                        bucket=\(retryCountBucket.rawValue)
                        """
                    }
                }
            }
        )
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                policyDenial: nil,
                evaluation: nil,
                loopKey: nil,
                hostBundleIdentifier: nil
            )
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                policyDenial: denial
            )
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                policyDenial: nil,
                evaluation: nil,
                loopKey: nil,
                hostBundleIdentifier: nil
            )
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                policyDenial: nil,
                evaluation: nil,
                loopKey: nil,
                hostBundleIdentifier: nil
            )
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
            loopGuard.recordSuppressedRetry(key: loopKey)
            let refreshedLoopEvaluation = loopGuard.evaluate(
                key: loopKey,
                hostBundleIdentifier: detail.resolvedBundleIdentifier
            )
            let diagnostic = SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: .launchSuppressed(detail),
                outcome: .launchSuppressed,
                launchSuppressed: true,
                retryCountBucket: refreshedLoopEvaluation.retryCountBucket
            )
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                evaluation: evaluation,
                loopKey: loopKey,
                hostBundleIdentifier: detail.resolvedBundleIdentifier
            )
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                evaluation: evaluation,
                loopKey: loopKey,
                hostBundleIdentifier: detail.resolvedBundleIdentifier
            )
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                evaluation: evaluation,
                loopKey: loopKey,
                hostBundleIdentifier: detail.resolvedBundleIdentifier
            )
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
            logDiagnostic: makeConnectionLogger(profileId: profileId),
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                policyDenial: nil,
                evaluation: nil,
                loopKey: nil,
                hostBundleIdentifier: nil
            )
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                policyDenial: denial
            )
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                policyDenial: nil,
                evaluation: nil,
                loopKey: nil,
                hostBundleIdentifier: nil
            )
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

        let loopKey = SumiNativeMessagingRelayLoopGuard.SessionKey(
            profileId: profileId,
            extensionId: extensionId,
            applicationIdentifier: SumiNativeMessagingRelayLoopGuard.canonicalApplicationIdentifier(
                requested: applicationIdentifier,
                hostBundleIdentifier: hostBundleIdentifier
            )
        )

        recordDiagnostic(
            SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation,
                outcome: .hostResolved
            ),
            profileId: profileId,
            evaluation: evaluation,
            loopKey: loopKey,
            hostBundleIdentifier: hostBundleIdentifier
        )

        let loopEvaluation = loopGuard.evaluate(
            key: loopKey,
            hostBundleIdentifier: hostBundleIdentifier
        )

        if loopEvaluation.launchSuppressed {
            loopGuard.recordSuppressedRetry(key: loopKey)
            let refreshedLoopEvaluation = loopGuard.evaluate(
                key: loopKey,
                hostBundleIdentifier: hostBundleIdentifier
            )
            let diagnostic = SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: .launchSuppressed(detail),
                outcome: .launchSuppressed,
                launchSuppressed: true,
                retryCountBucket: refreshedLoopEvaluation.retryCountBucket
            )
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                evaluation: evaluation,
                loopKey: loopKey,
                hostBundleIdentifier: hostBundleIdentifier
            )
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                evaluation: evaluation,
                loopKey: loopKey,
                hostBundleIdentifier: hostBundleIdentifier
            )
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
            logDiagnostic: makeConnectionLogger(profileId: profileId),
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                policyDenial: nil,
                evaluation: nil,
                loopKey: nil,
                hostBundleIdentifier: nil
            )
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
                self.recordDiagnostic(
                    diagnostic,
                    profileId: profileId,
                    evaluation: evaluation,
                    loopKey: loopKey,
                    hostBundleIdentifier: hostBundleIdentifier
                )
                session.disconnect()
                completionHandler(error)
                return
            }

            self.recordDiagnostic(
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
                ),
                profileId: profileId,
                evaluation: evaluation,
                loopKey: loopKey,
                hostBundleIdentifier: hostBundleIdentifier
            )
            completionHandler(nil)
        }

        return session
    }

    func clearCompanionState(forExtensionId extensionId: String, profileId: UUID? = nil) {
        launchPolicy.clearPendingState()
        loopGuard.clear(forExtensionId: extensionId, profileId: profileId)
        diagnosticCoalescer.clear(forExtensionId: extensionId, profileId: profileId)
    }

    func clearLoopGuard(forExtensionId extensionId: String, profileId: UUID? = nil) {
        clearCompanionState(forExtensionId: extensionId, profileId: profileId)
    }

    func clearAllLoopGuardState() {
        launchPolicy.clearPendingState()
        loopGuard.clearAll()
        diagnosticCoalescer.clearAll()
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

    private func recordDiagnostic(
        _ diagnostic: SafariExtensionNativeMessagingDiagnostic,
        profileId: UUID? = nil,
        policyDenial: SumiNativeMessagingRelayPolicyDenial? = nil,
        evaluation: SumiCompanionAppResolverResult? = nil,
        loopKey: SumiNativeMessagingRelayLoopGuard.SessionKey? = nil,
        hostBundleIdentifier: String? = nil
    ) {
        let sessionState: SumiNativeMessagingSessionState?
        if let loopKey, let host = hostBundleIdentifier ?? diagnostic.hostBundleIdentifier {
            sessionState = loopGuard.sessionState(
                policyDenial: policyDenial,
                profileRuntimeLoaded: profileRuntimeLoaded(),
                evaluation: evaluation,
                hostBundleIdentifier: host,
                key: loopKey
            )
        } else {
            sessionState = SumiNativeMessagingSessionStateMachine.resolve(
                policyDenial: policyDenial,
                profileRuntimeLoaded: profileRuntimeLoaded(),
                evaluation: evaluation,
                loopEvaluation: nil,
                adapterAvailable: diagnostic.protocolAdapterAvailable ?? false
            )
        }

        let enriched = SafariExtensionNativeMessagingDiagnostic(
            extensionId: diagnostic.extensionId,
            direction: diagnostic.direction,
            requestedApplicationIdentifier: diagnostic.requestedApplicationIdentifier,
            hostBundleIdentifier: diagnostic.hostBundleIdentifier,
            resolverBucket: diagnostic.resolverBucket,
            outcome: diagnostic.outcome,
            errorDomain: diagnostic.errorDomain,
            errorCode: diagnostic.errorCode,
            launchAttempted: diagnostic.launchAttempted,
            launchSuppressed: diagnostic.launchSuppressed,
            retryCountBucket: diagnostic.retryCountBucket,
            isContainingApp: diagnostic.isContainingApp,
            protocolAdapterAvailable: diagnostic.protocolAdapterAvailable,
            launchAllowed: diagnostic.launchAllowed,
            sessionState: sessionState
        )
        diagnosticCoalescer.record(enriched, profileId: profileId)
    }

    private func makeConnectionLogger(
        profileId: UUID?
    ) -> @MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void {
        { [weak self] diagnostic in
            self?.recordDiagnostic(diagnostic, profileId: profileId)
        }
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
            state=\(diagnostic.sessionState?.rawValue ?? "-") \
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
