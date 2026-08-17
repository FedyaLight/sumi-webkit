//
//  SumiNativeMessagingDiagnosticsRecorder.swift
//  Sumi
//
//  Owns native messaging diagnostics: enrichment, session-state resolution,
//  coalesced emission, and routing probe logging for relay entry points.
//

import Foundation

@MainActor
final class SumiNativeMessagingDiagnosticsRecorder {
    private let adapterRegistry: SumiNativeMessagingAdapterRegistry
    private let launchPolicy: SumiCompanionAppLaunchPolicy
    private let loopGuard: SumiNativeMessagingRelayLoopGuard
    private let profileRuntimeLoaded: @MainActor () -> Bool
    private let coalescer: SumiNativeMessagingDiagnosticCoalescer

    init(
        adapterRegistry: SumiNativeMessagingAdapterRegistry,
        launchPolicy: SumiCompanionAppLaunchPolicy,
        loopGuard: SumiNativeMessagingRelayLoopGuard,
        profileRuntimeLoaded: @escaping @MainActor () -> Bool,
        logDiagnostic: (@MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void)?
    ) {
        self.adapterRegistry = adapterRegistry
        self.launchPolicy = launchPolicy
        self.loopGuard = loopGuard
        self.profileRuntimeLoaded = profileRuntimeLoaded
        let resolvedLogger = logDiagnostic ?? Self.defaultDiagnosticLogger
        self.coalescer = SumiNativeMessagingDiagnosticCoalescer(
            downstream: { diagnostic, style in
                switch style {
                case .detailed:
                    resolvedLogger(diagnostic)
                case .summarized(let repeatCount, let retryCountBucket):
                    SumiNativeMessagingRuntimeCounters.recordCoalescedDiagnosticEmit(
                        repeatCount: repeatCount
                    )
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
                            launchReason: diagnostic.launchReason,
                            launchRequestedByAdapter: diagnostic.launchRequestedByAdapter,
                            launchCooldownBucket: diagnostic.launchCooldownBucket,
                            extensionContextActive: diagnostic.extensionContextActive,
                            isContainingApp: diagnostic.isContainingApp,
                            protocolAdapterAvailable: diagnostic.protocolAdapterAvailable,
                            launchAllowed: diagnostic.launchAllowed,
                            sessionState: diagnostic.sessionState,
                            adapterSelected: diagnostic.adapterSelected,
                            adapterIdentifier: diagnostic.adapterIdentifier,
                            appResolved: diagnostic.appResolved,
                            appLaunched: diagnostic.appLaunched,
                            protocolStatus: diagnostic.protocolStatus,
                            handshakeStatus: diagnostic.handshakeStatus,
                            autofillPathStatus: diagnostic.autofillPathStatus,
                            failureBucket: diagnostic.failureBucket
                        )
                    )
                    RuntimeDiagnostics.debug(category: "SafariNativeMessaging") {
                        """
                        coalesced extBucket=\(SafariExtensionNativeMessagingRoutingProbe.extensionIdBucket(diagnostic.extensionId)) \
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

    func record(
        _ diagnostic: SafariExtensionNativeMessagingDiagnostic,
        profileId: UUID? = nil,
        policyDenial: SumiNativeMessagingRelayPolicyDenial? = nil,
        evaluation: SumiCompanionAppResolverResult? = nil,
        loopKey: SumiNativeMessagingRelayLoopGuard.SessionKey? = nil,
        hostBundleIdentifier: String? = nil
    ) {
        guard RuntimeDiagnostics.supportsVerboseDiagnostics else { return }
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

        let hostForAdapter = hostBundleIdentifier ?? diagnostic.hostBundleIdentifier
        let adapter = hostForAdapter.flatMap {
            adapterRegistry.adapter(
                forApplicationIdentifier: diagnostic.requestedApplicationIdentifier,
                hostBundleIdentifier: $0
            )
        }
        let enrichedBase: SafariExtensionNativeMessagingDiagnostic
        if diagnostic.extensionContextActive == nil {
            enrichedBase = SafariExtensionNativeMessagingDiagnostic(
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
                launchReason: diagnostic.launchReason,
                launchRequestedByAdapter: diagnostic.launchRequestedByAdapter,
                launchCooldownBucket: diagnostic.launchCooldownBucket
                    ?? hostForAdapter.flatMap { host -> SumiNativeMessagingRetryCountBucket? in
                        guard loopKey != nil else { return nil }
                        return launchPolicy.launchCooldownBucket(
                            hostBundleIdentifier: host,
                            sessionKey: SumiCompanionAppLaunchPolicy.sessionKey(
                                profileId: profileId,
                                extensionId: diagnostic.extensionId,
                                requestedApplicationIdentifier: diagnostic.requestedApplicationIdentifier,
                                hostBundleIdentifier: host
                            )
                        )
                    },
                extensionContextActive: profileRuntimeLoaded(),
                isContainingApp: diagnostic.isContainingApp,
                protocolAdapterAvailable: diagnostic.protocolAdapterAvailable,
                launchAllowed: diagnostic.launchAllowed,
                sessionState: diagnostic.sessionState,
                adapterSelected: diagnostic.adapterSelected,
                adapterIdentifier: diagnostic.adapterIdentifier,
                appResolved: diagnostic.appResolved,
                appLaunched: diagnostic.appLaunched,
                protocolStatus: diagnostic.protocolStatus,
                handshakeStatus: diagnostic.handshakeStatus,
                autofillPathStatus: diagnostic.autofillPathStatus,
                failureBucket: diagnostic.failureBucket
            )
        } else {
            enrichedBase = diagnostic
        }

        let enriched = SafariExtensionNativeMessagingDiagnosticEnrichment.enrich(
            enrichedBase,
            adapter: adapter,
            adapterIdentifier: adapter?.protocolIdentifier,
            evaluation: evaluation,
            policyDenial: policyDenial,
            sessionState: sessionState
        )
        coalescer.record(enriched, profileId: profileId)
    }

    func makeConnectionLogger(
        profileId: UUID?
    ) -> @MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void {
        { [weak self] diagnostic in
            self?.record(diagnostic, profileId: profileId)
        }
    }

    func logRoutingEntry(
        delegateMethod: String,
        direction: SafariExtensionNativeMessagingDirection,
        applicationIdentifier: String?,
        extensionId: String?,
        extensionDisplayName: String?,
        profileId: UUID?,
        messageShape: SafariExtensionNativeMessagingMessageShape?
    ) {
        SafariExtensionNativeMessagingRoutingProbe.logDelegateObserved(
            delegateMethod: delegateMethod,
            direction: direction,
            extensionId: extensionId,
            extensionDisplayName: extensionDisplayName,
            applicationIdentifier: applicationIdentifier,
            profileId: profileId,
            messageShape: messageShape
        )
    }

    func logRoutingOutcome(
        delegateMethod: String,
        direction: SafariExtensionNativeMessagingDirection,
        applicationIdentifier: String?,
        extensionId: String?,
        profileId: UUID?,
        resolvedHostBundleIdentifier: String?,
        registryLookupAttempted: Bool,
        adapter: SumiNativeMessagingProtocolAdapter?,
        adapterByApplicationIdentifier: SumiNativeMessagingProtocolAdapter? = nil,
        fallbackReason: String?
    ) {
        let byApplication = adapterByApplicationIdentifier
            ?? adapterRegistry.adapter(forApplicationIdentifier: applicationIdentifier)
        let routingBucket = SafariExtensionNativeMessagingRoutingProbe.classify(
            direction: direction,
            applicationIdentifier: applicationIdentifier,
            resolvedHostBundleIdentifier: resolvedHostBundleIdentifier,
            adapter: adapter,
            adapterByApplicationIdentifier: byApplication,
            registryLookupAttempted: registryLookupAttempted,
            fallbackReason: fallbackReason
        )
        SafariExtensionNativeMessagingRoutingProbe.log(
            delegateMethod: delegateMethod,
            direction: direction,
            extensionId: extensionId,
            applicationIdentifier: applicationIdentifier,
            profileId: profileId,
            resolvedHostBundleIdentifier: resolvedHostBundleIdentifier,
            registryLookupAttempted: registryLookupAttempted,
            registryLookupResult: adapter != nil,
            adapter: adapter,
            routingBucket: routingBucket,
            fallbackReason: fallbackReason
        )
    }

    func clear(forExtensionId extensionId: String, profileId: UUID?) {
        coalescer.clear(forExtensionId: extensionId, profileId: profileId)
    }

    func clearAll() {
        coalescer.clearAll()
    }

    private static let defaultDiagnosticLogger: @MainActor (
        SafariExtensionNativeMessagingDiagnostic
    ) -> Void = { diagnostic in
        guard RuntimeDiagnostics.isVerboseEnabled else { return }
        if diagnostic.outcome == .relayCancelled,
           SafariExtensionAutofillFillDiagnostics.shouldRecordRelayCancellation() {
            SafariExtensionAutofillFillDiagnostics.recordNativeMessagingRelayCancelled(
                extensionId: diagnostic.extensionId
            )
        }
        RuntimeDiagnostics.debug(category: "SafariNativeMessaging") {
            """
            extBucket=\(SafariExtensionNativeMessagingRoutingProbe.extensionIdBucket(diagnostic.extensionId)) \
            dir=\(diagnostic.direction.rawValue) \
            req=\(diagnostic.requestedApplicationIdentifier ?? "(nil)") \
            host=\(diagnostic.hostBundleIdentifier ?? "(nil)") \
            containing=\(diagnostic.isContainingApp.map(String.init) ?? "-") \
            adapter=\(diagnostic.protocolAdapterAvailable.map(String.init) ?? "-") \
            adapterSelected=\(diagnostic.adapterSelected.map(String.init) ?? "-") \
            adapterId=\(diagnostic.adapterIdentifier ?? "-") \
            launchAllowed=\(diagnostic.launchAllowed.map(String.init) ?? "-") \
            resolved=\(diagnostic.appResolved.map(String.init) ?? "-") \
            launched=\(diagnostic.appLaunched.map(String.init) ?? "-") \
            resolver=\(diagnostic.resolverBucket?.rawValue ?? "-") \
            outcome=\(diagnostic.outcome.rawValue) \
            launch=\(diagnostic.launchAttempted.map(String.init) ?? "-") \
            suppressed=\(diagnostic.launchSuppressed.map(String.init) ?? "-") \
            reason=\(diagnostic.launchReason?.rawValue ?? "-") \
            adapterLaunch=\(diagnostic.launchRequestedByAdapter.map(String.init) ?? "-") \
            retry=\(diagnostic.retryCountBucket?.rawValue ?? "-") \
            cooldown=\(diagnostic.launchCooldownBucket?.rawValue ?? "-") \
            context=\(diagnostic.extensionContextActive.map(String.init) ?? "-") \
            state=\(diagnostic.sessionState?.rawValue ?? "-") \
            protocol=\(diagnostic.protocolStatus?.rawValue ?? "-") \
            handshake=\(diagnostic.handshakeStatus?.rawValue ?? "-") \
            autofill=\(diagnostic.autofillPathStatus?.rawValue ?? "-") \
            failure=\(diagnostic.failureBucket?.rawValue ?? "-") \
            err=\(diagnostic.errorDomain ?? "-")/\(diagnostic.errorCode.map(String.init) ?? "-")
            """
        }
    }
}
