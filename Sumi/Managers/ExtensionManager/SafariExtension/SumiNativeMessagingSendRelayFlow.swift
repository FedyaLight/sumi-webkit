//
//  SumiNativeMessagingSendRelayFlow.swift
//  Sumi
//
//  One-shot sendMessage relay orchestration after WebKit delegate entry:
//  policy gate, companion app routing, route resolution, loop-guard
//  suppression, and adapter handoff.
//

import Foundation

@MainActor
final class SumiNativeMessagingSendRelayFlow {
    private let companionApplicationRouter: CompanionApplicationMessageRouter
    private let routeResolver: SumiNativeMessagingRelayRouteResolver
    private let oneShotFlow: SumiNativeMessagingOneShotRelayFlow
    private let launcher: SumiHostApplicationLaunching
    private let launchPolicy: SumiCompanionAppLaunchPolicy
    private let loopGuard: SumiNativeMessagingRelayLoopGuard
    private let diagnostics: SumiNativeMessagingDiagnosticsRecorder
    private let extensionsModuleEnabled: @MainActor () -> Bool

    init(
        companionApplicationRouter: CompanionApplicationMessageRouter,
        routeResolver: SumiNativeMessagingRelayRouteResolver,
        oneShotFlow: SumiNativeMessagingOneShotRelayFlow,
        launcher: SumiHostApplicationLaunching,
        launchPolicy: SumiCompanionAppLaunchPolicy,
        loopGuard: SumiNativeMessagingRelayLoopGuard,
        diagnostics: SumiNativeMessagingDiagnosticsRecorder,
        extensionsModuleEnabled: @escaping @MainActor () -> Bool
    ) {
        self.companionApplicationRouter = companionApplicationRouter
        self.routeResolver = routeResolver
        self.oneShotFlow = oneShotFlow
        self.launcher = launcher
        self.launchPolicy = launchPolicy
        self.loopGuard = loopGuard
        self.diagnostics = diagnostics
        self.extensionsModuleEnabled = extensionsModuleEnabled
    }

    func send(
        applicationIdentifier: String?,
        message: Any,
        extensionId: String?,
        profileId: UUID?,
        isPrivateBrowsing: Bool?,
        privateAccessAllowed: Bool?,
        installedExtensions: [InstalledExtension],
        extensionDisplayName: String?,
        evaluatePolicy: SumiNativeMessagingPortConnectRelayFlow.PolicyEvaluator,
        policyDeniedDiagnostic: SumiNativeMessagingPortConnectRelayFlow.PolicyDeniedDiagnosticBuilder,
        launchSessionKey: (
            _ profileId: UUID?,
            _ extensionId: String,
            _ applicationIdentifier: String?,
            _ hostBundleIdentifier: String
        ) -> SumiCompanionAppLaunchSessionKey,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        SumiNativeMessagingRuntimeCounters.recordSendMessage(
            applicationIdentifier: applicationIdentifier
        )
        diagnostics.logRoutingEntry(
            delegateMethod: "sendMessage",
            direction: .send,
            applicationIdentifier: applicationIdentifier,
            extensionId: extensionId,
            extensionDisplayName: extensionDisplayName
                ?? ExtensionUtils.displayName(
                    forExtensionID: extensionId,
                    installedExtensions: installedExtensions
                ),
            profileId: profileId,
            messageShape: SafariExtensionNativeMessagingRoutingProbe
                .sanitizedMessageShape(for: message)
        )

        guard let extensionId else {
            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: "unknown",
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: nil,
                resolverBucket: nil,
                outcome: .extensionContextMissing,
                errorDomain: SumiNativeMessagingRelay.errorDomain,
                errorCode: SumiNativeMessagingRelay.ErrorCode.extensionContextMissing.rawValue
            )
            diagnostics.record(
                diagnostic,
                profileId: profileId,
                policyDenial: nil,
                evaluation: nil,
                loopKey: nil,
                hostBundleIdentifier: nil
            )
            diagnostics.logRoutingOutcome(
                delegateMethod: "sendMessage",
                direction: .send,
                applicationIdentifier: applicationIdentifier,
                extensionId: extensionId,
                profileId: profileId,
                resolvedHostBundleIdentifier: nil,
                registryLookupAttempted: false,
                adapter: nil,
                fallbackReason: "extensionContextMissing"
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
            extensionId,
            installed,
            isPrivateBrowsing,
            privateAccessAllowed,
            applicationIdentifier
        ) {
        case .failure(let denial):
            let diagnostic = policyDeniedDiagnostic(
                extensionId,
                .send,
                applicationIdentifier,
                denial
            )
            diagnostics.record(
                diagnostic,
                profileId: profileId,
                policyDenial: denial
            )
            diagnostics.logRoutingOutcome(
                delegateMethod: "sendMessage",
                direction: .send,
                applicationIdentifier: applicationIdentifier,
                extensionId: extensionId,
                profileId: profileId,
                resolvedHostBundleIdentifier: nil,
                registryLookupAttempted: false,
                adapter: nil,
                fallbackReason: "policyDenied:\(denial.rawValue)"
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

        if companionApplicationRouter.route(
            applicationIdentifier: applicationIdentifier,
            message: message,
            extensionId: extensionId,
            profileId: profileId,
            installedExtension: installed,
            replyHandler: replyHandler
        ) {
            return
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
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation
            )
            diagnostics.record(
                diagnostic,
                profileId: profileId,
                policyDenial: nil,
                evaluation: nil,
                loopKey: nil,
                hostBundleIdentifier: nil
            )
            diagnostics.logRoutingOutcome(
                delegateMethod: "sendMessage",
                direction: .send,
                applicationIdentifier: applicationIdentifier,
                extensionId: extensionId,
                profileId: profileId,
                resolvedHostBundleIdentifier: nil,
                registryLookupAttempted: false,
                adapter: nil,
                fallbackReason: "resolverNoDetail:\(String(describing: evaluation))"
            )
            replyHandler(
                nil,
                SumiNativeMessagingErrorMapper.relayError(
                    code: SumiCompanionAppResolver.relayErrorCode(for: evaluation),
                    diagnostic: diagnostic
                )
            )
            return
        case .resolved(let resolvedRoute):
            route = resolvedRoute
        }

        let evaluation = route.evaluation
        let detail = route.detail
        let hostBundleIdentifier = route.hostBundleIdentifier
        let loopKey = route.loopKey
        let loopEvaluation = route.loopEvaluation
        let adapterLookup = route.adapterLookup

        if case .appNotFound = evaluation {
            let diagnostic = SumiNativeMessagingConnection.diagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation,
                outcome: .hostNotFound
            )
            diagnostics.record(
                diagnostic,
                profileId: profileId,
                policyDenial: nil,
                evaluation: nil,
                loopKey: nil,
                hostBundleIdentifier: nil
            )
            diagnostics.logRoutingOutcome(
                delegateMethod: "sendMessage",
                direction: .send,
                applicationIdentifier: applicationIdentifier,
                extensionId: extensionId,
                profileId: profileId,
                resolvedHostBundleIdentifier: hostBundleIdentifier,
                registryLookupAttempted: false,
                adapter: nil,
                fallbackReason: "hostNotFound"
            )
            replyHandler(
                nil,
                SumiNativeMessagingErrorMapper.relayError(code: .hostNotFound, diagnostic: diagnostic)
            )
            return
        }

        if loopEvaluation.launchSuppressed, adapterLookup.adapter == nil {
            loopGuard.recordSuppressedRetry(key: loopKey)
            let refreshedLoopEvaluation = loopGuard.evaluate(
                key: loopKey,
                hostBundleIdentifier: hostBundleIdentifier
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
            diagnostics.record(
                diagnostic,
                profileId: profileId,
                evaluation: evaluation,
                loopKey: loopKey,
                hostBundleIdentifier: hostBundleIdentifier
            )
            diagnostics.logRoutingOutcome(
                delegateMethod: "sendMessage",
                direction: .send,
                applicationIdentifier: applicationIdentifier,
                extensionId: extensionId,
                profileId: profileId,
                resolvedHostBundleIdentifier: hostBundleIdentifier,
                registryLookupAttempted: false,
                adapter: nil,
                fallbackReason: "launchSuppressed"
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

        guard let adapter = adapterLookup.adapter else {
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
            diagnostics.record(
                diagnostic,
                profileId: profileId,
                evaluation: evaluation,
                loopKey: loopKey,
                hostBundleIdentifier: hostBundleIdentifier
            )
            diagnostics.logRoutingOutcome(
                delegateMethod: "sendMessage",
                direction: .send,
                applicationIdentifier: applicationIdentifier,
                extensionId: extensionId,
                profileId: profileId,
                resolvedHostBundleIdentifier: hostBundleIdentifier,
                registryLookupAttempted: true,
                adapter: nil,
                adapterByApplicationIdentifier: adapterLookup.adapterByApplicationIdentifier,
                fallbackReason: "registryMiss"
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

        diagnostics.logRoutingOutcome(
            delegateMethod: "sendMessage",
            direction: .send,
            applicationIdentifier: applicationIdentifier,
            extensionId: extensionId,
            profileId: profileId,
            resolvedHostBundleIdentifier: hostBundleIdentifier,
            registryLookupAttempted: true,
            adapter: adapter,
            adapterByApplicationIdentifier: adapterLookup.adapterByApplicationIdentifier,
            fallbackReason: nil
        )

        let launchKey = launchSessionKey(
            profileId,
            extensionId,
            applicationIdentifier,
            hostBundleIdentifier
        )
        oneShotFlow.relay(
            applicationIdentifier: applicationIdentifier,
            message: message,
            extensionId: extensionId,
            profileId: profileId,
            evaluation: evaluation,
            adapter: adapter,
            launcher: launcher,
            launchPolicy: launchPolicy,
            launchSessionKey: launchKey,
            loopKey: loopKey,
            loopEvaluation: loopEvaluation,
            logDiagnostic: diagnostics.makeConnectionLogger(profileId: profileId),
            replyHandler: replyHandler
        )
    }
}
