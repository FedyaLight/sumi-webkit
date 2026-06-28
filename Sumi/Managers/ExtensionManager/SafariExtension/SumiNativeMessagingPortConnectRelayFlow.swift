//
//  SumiNativeMessagingPortConnectRelayFlow.swift
//  Sumi
//
//  Port-based native messaging connection orchestration after WebKit delegate entry.
//

import Foundation

@MainActor
final class SumiNativeMessagingPortConnectRelayFlow {
    typealias PolicyEvaluator = (
        _ extensionId: String,
        _ installed: InstalledExtension?,
        _ isPrivateBrowsing: Bool?,
        _ privateAccessAllowed: Bool?,
        _ requestedApplicationIdentifier: String?
    ) -> Result<Void, SumiNativeMessagingRelayPolicyDenial>

    typealias PolicyDeniedDiagnosticBuilder = (
        _ extensionId: String,
        _ direction: SafariExtensionNativeMessagingDirection,
        _ requestedApplicationIdentifier: String?,
        _ denial: SumiNativeMessagingRelayPolicyDenial
    ) -> SafariExtensionNativeMessagingDiagnostic

    typealias DiagnosticRecorder = (
        _ diagnostic: SafariExtensionNativeMessagingDiagnostic,
        _ profileId: UUID?,
        _ policyDenial: SumiNativeMessagingRelayPolicyDenial?,
        _ evaluation: SumiCompanionAppResolverResult?,
        _ loopKey: SumiNativeMessagingRelayLoopGuard.SessionKey?,
        _ hostBundleIdentifier: String?
    ) -> Void

    typealias RoutingEntryLogger = (
        _ delegateMethod: String,
        _ direction: SafariExtensionNativeMessagingDirection,
        _ applicationIdentifier: String?,
        _ extensionId: String?,
        _ extensionDisplayName: String?,
        _ profileId: UUID?,
        _ messageShape: SafariExtensionNativeMessagingMessageShape?
    ) -> Void

    typealias RoutingOutcomeLogger = (
        _ delegateMethod: String,
        _ direction: SafariExtensionNativeMessagingDirection,
        _ applicationIdentifier: String?,
        _ extensionId: String?,
        _ profileId: UUID?,
        _ resolvedHostBundleIdentifier: String?,
        _ registryLookupAttempted: Bool,
        _ adapter: SumiNativeMessagingProtocolAdapter?,
        _ adapterByApplicationIdentifier: SumiNativeMessagingProtocolAdapter?,
        _ fallbackReason: String?
    ) -> Void

    private let sessionStore: SumiNativeMessagingRelaySessionStore
    private let loopGuard: SumiNativeMessagingRelayLoopGuard
    private let routeResolver: SumiNativeMessagingRelayRouteResolver
    private let launcher: SumiHostApplicationLaunching
    private let launchPolicy: SumiCompanionAppLaunchPolicy
    private let profileRuntimeLoaded: @MainActor () -> Bool

    init(
        sessionStore: SumiNativeMessagingRelaySessionStore,
        loopGuard: SumiNativeMessagingRelayLoopGuard,
        routeResolver: SumiNativeMessagingRelayRouteResolver,
        launcher: SumiHostApplicationLaunching,
        launchPolicy: SumiCompanionAppLaunchPolicy,
        profileRuntimeLoaded: @escaping @MainActor () -> Bool
    ) {
        self.sessionStore = sessionStore
        self.loopGuard = loopGuard
        self.routeResolver = routeResolver
        self.launcher = launcher
        self.launchPolicy = launchPolicy
        self.profileRuntimeLoaded = profileRuntimeLoaded
    }

    @discardableResult
    func connect(
        port: any SumiNativeMessagingPortControlling,
        extensionId: String?,
        profileId: UUID?,
        isPrivateBrowsing: Bool?,
        privateAccessAllowed: Bool?,
        installedExtensions: [InstalledExtension],
        registerHandler: (SumiNativeMessagingPortSession) -> Void,
        unregisterHandler: @escaping (SumiNativeMessagingPortSession) -> Void,
        evaluatePolicy: PolicyEvaluator,
        policyDeniedDiagnostic: PolicyDeniedDiagnosticBuilder,
        recordDiagnostic: @escaping DiagnosticRecorder,
        logRoutingEntry: RoutingEntryLogger,
        logRoutingOutcome: RoutingOutcomeLogger,
        logConnectionDiagnostic: @escaping @MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void,
        outcomeForAdapterError: @escaping (NSError) -> SafariExtensionNativeMessagingOutcome,
        launchSessionKey: (
            _ profileId: UUID?,
            _ extensionId: String,
            _ applicationIdentifier: String?,
            _ hostBundleIdentifier: String
        ) -> SumiCompanionAppLaunchSessionKey,
        completionHandler: @escaping ((any Error)?) -> Void
    ) -> SumiNativeMessagingPortSession? {
        let applicationIdentifier = port.applicationIdentifier

        SumiNativeMessagingRuntimeCounters.recordConnect(
            applicationIdentifier: applicationIdentifier
        )
        logRoutingEntry(
            "connectUsing",
            .connect,
            applicationIdentifier,
            extensionId,
            ExtensionUtils.displayName(
                forExtensionID: extensionId,
                installedExtensions: installedExtensions
            ),
            profileId,
            nil
        )

        guard let extensionId else {
            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: "unknown",
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: nil,
                resolverBucket: nil,
                outcome: .extensionContextMissing,
                errorDomain: SumiNativeMessagingRelay.errorDomain,
                errorCode: SumiNativeMessagingRelay.ErrorCode.extensionContextMissing.rawValue
            )
            recordDiagnostic(diagnostic, profileId, nil, nil, nil, nil)
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
            extensionId,
            installed,
            isPrivateBrowsing,
            privateAccessAllowed,
            applicationIdentifier
        ) {
        case .failure(let denial):
            let diagnostic = policyDeniedDiagnostic(
                extensionId,
                .connect,
                applicationIdentifier,
                denial
            )
            recordDiagnostic(diagnostic, profileId, denial, nil, nil, nil)
            port.disconnect()
            completionHandler(
                SumiNativeMessagingErrorMapper.relayError(code: .policyDenied, diagnostic: diagnostic)
            )
            return nil
        case .success:
            break
        }

        let route: SumiNativeMessagingRelayResolvedRoute
        switch routeResolver.resolve(
            applicationIdentifier: applicationIdentifier,
            extensionId: extensionId,
            profileId: profileId,
            installedExtensions: installedExtensions
        ) {
        case .missingDetail(let evaluation):
            let diagnostic = SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation
            )
            recordDiagnostic(diagnostic, profileId, nil, nil, nil, nil)
            port.disconnect()
            completionHandler(
                SumiNativeMessagingErrorMapper.relayError(
                    code: SumiCompanionAppResolver.relayErrorCode(for: evaluation),
                    diagnostic: diagnostic
                )
            )
            return nil
        case .resolved(let resolvedRoute):
            route = resolvedRoute
        }

        let evaluation = route.evaluation
        let detail = route.detail
        let hostBundleIdentifier = route.hostBundleIdentifier
        let resolverBucket = route.resolverBucket
        let loopKey = route.loopKey
        let loopEvaluation = route.loopEvaluation
        let adapterLookup = route.adapterLookup

        recordDiagnostic(
            SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation,
                outcome: .hostResolved
            ),
            profileId,
            nil,
            evaluation,
            loopKey,
            hostBundleIdentifier
        )

        if loopEvaluation.launchSuppressed, adapterLookup.adapter == nil {
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
            recordDiagnostic(diagnostic, profileId, nil, evaluation, loopKey, hostBundleIdentifier)
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

        guard let adapter = adapterLookup.adapter else {
            loopGuard.recordCompanionAppProtocolUnknown(key: loopKey, launchAttempted: false)
            let diagnostic = SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation,
                outcome: .companionAppProtocolUnknown
            )
            recordDiagnostic(diagnostic, profileId, nil, evaluation, loopKey, hostBundleIdentifier)
            logRoutingOutcome(
                "connectUsing",
                .connect,
                applicationIdentifier,
                extensionId,
                profileId,
                hostBundleIdentifier,
                true,
                nil,
                adapterLookup.adapterByApplicationIdentifier,
                "registryMiss"
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

        logRoutingOutcome(
            "connectUsing",
            .connect,
            applicationIdentifier,
            extensionId,
            profileId,
            hostBundleIdentifier,
            true,
            adapter,
            adapterLookup.adapterByApplicationIdentifier,
            nil
        )

        let session = SumiNativeMessagingPortSession(
            port: port,
            adapter: adapter,
            extensionId: extensionId,
            profileId: profileId,
            hostBundleIdentifier: hostBundleIdentifier,
            resolverBucket: resolverBucket,
            logDiagnostic: logConnectionDiagnostic,
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
                        errorDomain: SumiNativeMessagingRelay.errorDomain,
                        errorCode: SumiNativeMessagingRelay.ErrorCode
                            .companionAppProtocolUnknown.rawValue,
                        isContainingApp: detail.isContainingApp,
                        protocolAdapterAvailable: detail.protocolAdapterAvailable,
                        launchAllowed: detail.launchAllowed
                    )
                )
            },
            disconnectFinalizer: { [weak sessionStore] session, _ in
                sessionStore?.finalizePortSession(
                    session,
                    unregisterHandler: unregisterHandler
                )
            }
        )
        sessionStore.trackPortSession(session)
        SumiNativeMessagingRuntimeCounters.recordPortOpened()
        registerHandler(session)

        guard launcher.urlForApplication(withBundleIdentifier: hostBundleIdentifier) != nil else {
            let diagnostic = SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: .appNotFound(detail),
                outcome: .hostNotFound
            )
            recordDiagnostic(diagnostic, profileId, nil, nil, nil, nil)
            sessionStore.teardownPortSession(session)
            completionHandler(
                SumiNativeMessagingErrorMapper.relayError(code: .hostNotFound, diagnostic: diagnostic)
            )
            return session
        }

        let launchKey = launchSessionKey(
            profileId,
            extensionId,
            applicationIdentifier,
            hostBundleIdentifier
        )
        let gatedLauncher = SumiLaunchPolicyGatedHostApplicationLauncher(
            underlying: launcher,
            launchPolicy: launchPolicy,
            hostBundleIdentifier: hostBundleIdentifier,
            protocolAdapterAvailable: detail.protocolAdapterAvailable,
            sessionKey: launchKey,
            launchReason: .adapterConnect
        )

        adapter.connectPort(session: session, launcher: gatedLauncher) { [self] error in
            if let error {
                let nsError = error as NSError
                self.loopGuard.recordCompanionAppProtocolUnknown(
                    key: loopKey,
                    launchAttempted: gatedLauncher.lastLaunchSuppressed == false
                )
                let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                    extensionId: extensionId,
                    direction: .connect,
                    requestedApplicationIdentifier: applicationIdentifier,
                    hostBundleIdentifier: hostBundleIdentifier,
                    resolverBucket: resolverBucket,
                    outcome: outcomeForAdapterError(nsError),
                    errorDomain: nsError.domain,
                    errorCode: nsError.code,
                    launchAttempted: gatedLauncher.lastLaunchSuppressed == false,
                    launchSuppressed: gatedLauncher.lastLaunchSuppressed,
                    launchReason: .adapterConnect,
                    launchRequestedByAdapter: true,
                    launchCooldownBucket: self.launchPolicy.launchCooldownBucket(
                        hostBundleIdentifier: hostBundleIdentifier,
                        sessionKey: launchKey
                    ),
                    extensionContextActive: self.profileRuntimeLoaded(),
                    isContainingApp: detail.isContainingApp,
                    protocolAdapterAvailable: detail.protocolAdapterAvailable,
                    launchAllowed: detail.launchAllowed
                )
                recordDiagnostic(diagnostic, profileId, nil, evaluation, loopKey, hostBundleIdentifier)
                self.sessionStore.teardownPortSession(session)
                completionHandler(error)
                return
            }

            self.loopGuard.recordSupportedAdapterLaunchAttempt(key: loopKey)
            recordDiagnostic(
                SafariExtensionNativeMessagingDiagnostic(
                    extensionId: extensionId,
                    direction: .connect,
                    requestedApplicationIdentifier: applicationIdentifier,
                    hostBundleIdentifier: hostBundleIdentifier,
                    resolverBucket: resolverBucket,
                    outcome: .portConnected,
                    errorDomain: nil,
                    errorCode: nil,
                    launchAttempted: gatedLauncher.lastLaunchSuppressed == false,
                    launchSuppressed: gatedLauncher.lastLaunchSuppressed,
                    launchReason: .adapterConnect,
                    launchRequestedByAdapter: true,
                    launchCooldownBucket: self.launchPolicy.launchCooldownBucket(
                        hostBundleIdentifier: hostBundleIdentifier,
                        sessionKey: launchKey
                    ),
                    extensionContextActive: self.profileRuntimeLoaded(),
                    isContainingApp: detail.isContainingApp,
                    protocolAdapterAvailable: detail.protocolAdapterAvailable,
                    launchAllowed: detail.launchAllowed
                ),
                profileId,
                nil,
                evaluation,
                loopKey,
                hostBundleIdentifier
            )
            completionHandler(nil)
        }

        return session
    }
}
