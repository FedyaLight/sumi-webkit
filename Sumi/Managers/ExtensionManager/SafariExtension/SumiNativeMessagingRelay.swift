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
        case nativeHostManifestMissing = 8
        case nativeHostExecutableMissing = 9
        case nativeHostPermissionDenied = 10
        case nativeHostUnsupportedKind = 11
        case companionApplicationUnsupportedApplicationId = 12
        case companionApplicationUnsupportedExtension = 13
        case companionApplicationUnsupportedBackend = 14
        case companionApplicationInvalidPayload = 15
        case companionApplicationUnsupportedMessageType = 16
        case companionApplicationSecureStoreFailure = 17
        case companionApplicationExactlyOnceReplyViolation = 18
        case companionApplicationSecureStateMissing = 19
    }

    static let errorDomain = "Sumi.SafariNativeMessaging"
    static let delegateMethodsRegistered = true

    private let importStore: SafariExtensionImportStore
    private let launcher: SumiHostApplicationLaunching
    private let adapterRegistry: SumiNativeMessagingAdapterRegistry
    private let companionApplicationRouter: CompanionApplicationMessageRouter
    private let launchPolicy: SumiCompanionAppLaunchPolicy
    private let loopGuard: SumiNativeMessagingRelayLoopGuard
    private let diagnosticCoalescer: SumiNativeMessagingDiagnosticCoalescer
    private let extensionsModuleEnabled: () -> Bool
    private let fallbackIsPrivateBrowsing: () -> Bool
    private let profileRuntimeLoaded: () -> Bool
    private let rawLogDiagnostic: @MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void
    private let sessionStore: SumiNativeMessagingRelaySessionStore
    private let routeResolver: SumiNativeMessagingRelayRouteResolver
    private let oneShotFlow: SumiNativeMessagingOneShotRelayFlow
    private let portConnectFlow: SumiNativeMessagingPortConnectRelayFlow

    init(
        importStore: SafariExtensionImportStore = .shared,
        launcher: SumiHostApplicationLaunching = SumiNSWorkspaceHostApplicationLauncher(),
        adapterRegistry: SumiNativeMessagingAdapterRegistry = .shared,
        companionApplicationRouter: CompanionApplicationMessageRouter =
            CompanionApplicationMessageRouter(),
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
        self.companionApplicationRouter = companionApplicationRouter
        self.launchPolicy = launchPolicy
        self.loopGuard = loopGuard
        self.extensionsModuleEnabled = extensionsModuleEnabled
        self.fallbackIsPrivateBrowsing = isPrivateBrowsing
        self.profileRuntimeLoaded = profileRuntimeLoaded
        let sessionStore = SumiNativeMessagingRelaySessionStore(adapterRegistry: adapterRegistry)
        self.sessionStore = sessionStore
        self.oneShotFlow = SumiNativeMessagingOneShotRelayFlow(
            sessionStore: sessionStore,
            loopGuard: loopGuard,
            profileRuntimeLoaded: profileRuntimeLoaded
        )
        let routeResolver = SumiNativeMessagingRelayRouteResolver(
            importStore: importStore,
            launcher: launcher,
            adapterRegistry: adapterRegistry,
            launchPolicy: launchPolicy,
            loopGuard: loopGuard
        )
        self.routeResolver = routeResolver
        self.portConnectFlow = SumiNativeMessagingPortConnectRelayFlow(
            sessionStore: sessionStore,
            loopGuard: loopGuard,
            routeResolver: routeResolver,
            launcher: launcher,
            launchPolicy: launchPolicy,
            profileRuntimeLoaded: profileRuntimeLoaded
        )
        let resolvedLogger = logDiagnostic ?? Self.defaultDiagnosticLogger
        self.rawLogDiagnostic = resolvedLogger
        self.diagnosticCoalescer = SumiNativeMessagingDiagnosticCoalescer(
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

    func handleSendMessage(
        applicationIdentifier: String?,
        message: Any,
        extensionId: String?,
        profileId: UUID? = nil,
        isPrivateBrowsing: Bool? = nil,
        privateAccessAllowed: Bool? = nil,
        installedExtensions: [InstalledExtension],
        extensionDisplayName: String? = nil,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        SumiNativeMessagingRuntimeCounters.recordSendMessage(
            applicationIdentifier: applicationIdentifier
        )
        logRoutingEntry(
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
            logRoutingOutcome(
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
            extensionId: extensionId,
            installed: installed,
            isPrivateBrowsing: isPrivateBrowsing,
            privateAccessAllowed: privateAccessAllowed,
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
            logRoutingOutcome(
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                policyDenial: nil,
                evaluation: nil,
                loopKey: nil,
                hostBundleIdentifier: nil
            )
            logRoutingOutcome(
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                policyDenial: nil,
                evaluation: nil,
                loopKey: nil,
                hostBundleIdentifier: nil
            )
            logRoutingOutcome(
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                evaluation: evaluation,
                loopKey: loopKey,
                hostBundleIdentifier: hostBundleIdentifier
            )
            logRoutingOutcome(
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                evaluation: evaluation,
                loopKey: loopKey,
                hostBundleIdentifier: hostBundleIdentifier
            )
            logRoutingOutcome(
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

        logRoutingOutcome(
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
            profileId: profileId,
            extensionId: extensionId,
            applicationIdentifier: applicationIdentifier,
            hostBundleIdentifier: hostBundleIdentifier
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
            logDiagnostic: makeConnectionLogger(profileId: profileId),
            replyHandler: replyHandler
        )
    }

    @discardableResult
    func handleConnect(
        port: any SumiNativeMessagingPortControlling,
        extensionId: String?,
        profileId: UUID? = nil,
        isPrivateBrowsing: Bool? = nil,
        privateAccessAllowed: Bool? = nil,
        installedExtensions: [InstalledExtension],
        registerHandler: (SumiNativeMessagingPortSession) -> Void,
        unregisterHandler: @escaping (SumiNativeMessagingPortSession) -> Void = { _ in },
        completionHandler: @escaping ((any Error)?) -> Void
    ) -> SumiNativeMessagingPortSession? {
        portConnectFlow.connect(
            port: port,
            extensionId: extensionId,
            profileId: profileId,
            isPrivateBrowsing: isPrivateBrowsing,
            privateAccessAllowed: privateAccessAllowed,
            installedExtensions: installedExtensions,
            registerHandler: registerHandler,
            unregisterHandler: unregisterHandler,
            evaluatePolicy: evaluatePolicy,
            policyDeniedDiagnostic: policyDeniedDiagnostic,
            recordDiagnostic: recordDiagnostic,
            logRoutingEntry: logRoutingEntry,
            logRoutingOutcome: logRoutingOutcome,
            logConnectionDiagnostic: makeConnectionLogger(profileId: profileId),
            outcomeForAdapterError: Self.outcome(forAdapterError:),
            launchSessionKey: launchSessionKey,
            completionHandler: completionHandler
        )
    }

    func clearCompanionState(forExtensionId extensionId: String, profileId: UUID? = nil) {
        launchPolicy.clear(forExtensionId: extensionId, profileId: profileId)
        loopGuard.clear(forExtensionId: extensionId, profileId: profileId)
        diagnosticCoalescer.clear(forExtensionId: extensionId, profileId: profileId)
        sessionStore.disconnectTrackedPortSessions(forExtensionId: extensionId, profileId: profileId)
    }

    func clearLaunchSessionOnExtensionContextUnload(
        forExtensionId extensionId: String,
        profileId: UUID? = nil
    ) {
        SumiNativeMessagingRuntimeCounters.recordContextUnload(extensionId: extensionId)
        sessionStore.cancelPendingOneShotRelays(forExtensionId: extensionId, profileId: profileId)
        launchPolicy.clearSessionKeys(forExtensionId: extensionId, profileId: profileId)
        loopGuard.clear(forExtensionId: extensionId, profileId: profileId)
        diagnosticCoalescer.clear(forExtensionId: extensionId, profileId: profileId)
        sessionStore.disconnectTrackedPortSessions(forExtensionId: extensionId, profileId: profileId)
        SumiNativeMessagingRuntimeCounters.logSnapshotIfVerbose(
            context: "contextUnload ext=\(extensionId)"
        )
    }

    func clearLoopGuard(forExtensionId extensionId: String, profileId: UUID? = nil) {
        clearCompanionState(forExtensionId: extensionId, profileId: profileId)
    }

    func clearAllLoopGuardState() {
        launchPolicy.clearPendingState()
        loopGuard.clearAll()
        diagnosticCoalescer.clearAll()
        sessionStore.disconnectAllTrackedPortSessions()
    }

    private func launchSessionKey(
        profileId: UUID?,
        extensionId: String,
        applicationIdentifier: String?,
        hostBundleIdentifier: String
    ) -> SumiCompanionAppLaunchSessionKey {
        SumiCompanionAppLaunchPolicy.sessionKey(
            profileId: profileId,
            extensionId: extensionId,
            requestedApplicationIdentifier: applicationIdentifier,
            hostBundleIdentifier: hostBundleIdentifier
        )
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
        case .nativeHostManifestMissing:
            message = description
                ?? "The native messaging host manifest was not found."
        case .nativeHostExecutableMissing:
            message = description
                ?? "The native messaging host executable was not found."
        case .nativeHostPermissionDenied:
            message = description
                ?? "Permission denied when starting the native messaging host."
        case .nativeHostUnsupportedKind:
            message = description
                ?? "The native messaging host kind is unsupported."
        case .companionApplicationUnsupportedApplicationId:
            message = description
                ?? "Safari containing-application messaging only supports application.id."
        case .companionApplicationUnsupportedExtension:
            message = description
                ?? "Safari containing-application messaging is not supported for this extension."
        case .companionApplicationUnsupportedBackend:
            message = description
                ?? "No Sumi companion application backend is registered for this extension."
        case .companionApplicationInvalidPayload:
            message = description
                ?? "The companion application message payload is invalid."
        case .companionApplicationUnsupportedMessageType:
            message = description
                ?? "The companion application message type is unsupported."
        case .companionApplicationSecureStoreFailure:
            message = description
                ?? "The companion application secure store operation failed."
        case .companionApplicationExactlyOnceReplyViolation:
            message = description
                ?? "The companion application backend attempted to reply more than once."
        case .companionApplicationSecureStateMissing:
            message = description
                ?? "The companion application secure state is missing."
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
        isPrivateBrowsing: Bool?,
        privateAccessAllowed: Bool?,
        requestedApplicationIdentifier: String?
    ) -> Result<Void, SumiNativeMessagingRelayPolicyDenial> {
        SumiNativeMessagingRelayPolicy.evaluate(
            SumiNativeMessagingRelayPolicyContext(
                extensionsModuleEnabled: extensionsModuleEnabled(),
                extensionId: extensionId,
                installedExtension: installed,
                isPrivateBrowsing: isPrivateBrowsing ?? fallbackIsPrivateBrowsing(),
                privateAccessAllowed: privateAccessAllowed,
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
        diagnosticCoalescer.record(enriched, profileId: profileId)
    }

    private func makeConnectionLogger(
        profileId: UUID?
    ) -> @MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void {
        { [weak self] diagnostic in
            self?.recordDiagnostic(diagnostic, profileId: profileId)
        }
    }

    private func logRoutingEntry(
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

    private func logRoutingOutcome(
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

    private static func outcome(forAdapterError error: NSError)
        -> SafariExtensionNativeMessagingOutcome {
        guard error.domain == Self.errorDomain,
              let code = ErrorCode(rawValue: error.code)
        else {
            return .hostLaunchFailed
        }

        switch code {
        case .hostNotFound:
            return .hostNotFound
        case .nativeHostManifestMissing:
            return .nativeHostManifestMissing
        case .nativeHostExecutableMissing:
            return .nativeHostExecutableMissing
        case .nativeHostPermissionDenied:
            return .nativeHostPermissionDenied
        case .nativeHostUnsupportedKind:
            return .nativeHostUnsupportedKind
        case .relayTimeout:
            return .relayTimeout
        case .relayCancelled:
            return .relayCancelled
        case .companionAppProtocolUnknown:
            return .companionAppProtocolUnknown
        case .extensionContextMissing:
            return .extensionContextMissing
        case .policyDenied:
            return .policyDenied
        case .hostLaunchFailed:
            return .hostLaunchFailed
        case .companionApplicationUnsupportedApplicationId,
             .companionApplicationUnsupportedExtension,
             .companionApplicationUnsupportedBackend,
             .companionApplicationInvalidPayload,
             .companionApplicationUnsupportedMessageType,
             .companionApplicationSecureStoreFailure,
             .companionApplicationExactlyOnceReplyViolation,
             .companionApplicationSecureStateMissing:
            return .companionAppProtocolUnknown
        }
    }
}
