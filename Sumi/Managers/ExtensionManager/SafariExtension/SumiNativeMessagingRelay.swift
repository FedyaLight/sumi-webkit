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
    private var trackedPortSessions: [ObjectIdentifier: SumiNativeMessagingPortSession] = [:]
    private var pendingOneShotRelays: [ObjectIdentifier: PendingOneShotRelay] = [:]

    private struct PendingOneShotRelay {
        let extensionId: String
        let profileId: UUID?
        let coordinator: SumiNativeMessagingOnceReplyCoordinator
    }

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
        SumiNativeMessagingRuntimeCounters.recordSendMessage(
            applicationIdentifier: applicationIdentifier
        )
        logRoutingEntry(
            delegateMethod: "sendMessage",
            direction: .send,
            applicationIdentifier: applicationIdentifier,
            extensionId: extensionId,
            profileId: profileId
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
            logRoutingOutcome(
                delegateMethod: "sendMessage",
                direction: .send,
                applicationIdentifier: applicationIdentifier,
                extensionId: extensionId,
                profileId: profileId,
                resolvedHostBundleIdentifier: detail.resolvedBundleIdentifier,
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

        let adapterLookup = resolveRegisteredAdapter(
            applicationIdentifier: applicationIdentifier,
            hostBundleIdentifier: detail.resolvedBundleIdentifier
        )

        if loopEvaluation.launchSuppressed, adapterLookup.adapter == nil {
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
            logRoutingOutcome(
                delegateMethod: "sendMessage",
                direction: .send,
                applicationIdentifier: applicationIdentifier,
                extensionId: extensionId,
                profileId: profileId,
                resolvedHostBundleIdentifier: detail.resolvedBundleIdentifier,
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
                hostBundleIdentifier: detail.resolvedBundleIdentifier
            )
            logRoutingOutcome(
                delegateMethod: "sendMessage",
                direction: .send,
                applicationIdentifier: applicationIdentifier,
                extensionId: extensionId,
                profileId: profileId,
                resolvedHostBundleIdentifier: detail.resolvedBundleIdentifier,
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
            resolvedHostBundleIdentifier: detail.resolvedBundleIdentifier,
            registryLookupAttempted: true,
            adapter: adapter,
            adapterByApplicationIdentifier: adapterLookup.adapterByApplicationIdentifier,
            fallbackReason: nil
        )

        let launchKey = launchSessionKey(
            profileId: profileId,
            extensionId: extensionId,
            applicationIdentifier: applicationIdentifier,
            hostBundleIdentifier: detail.resolvedBundleIdentifier
        )
        let once = OnceReplyHandler(replyHandler)
        final class PendingOneShotCoordinatorRef {
            var coordinator: SumiNativeMessagingOnceReplyCoordinator?
        }
        let pendingCoordinatorRef = PendingOneShotCoordinatorRef()
        SumiNativeMessagingConnection.relayOneShot(
            applicationIdentifier: applicationIdentifier,
            message: message,
            extensionId: extensionId,
            evaluation: evaluation,
            adapter: adapter,
            launcher: launcher,
            launchPolicy: launchPolicy,
            launchSessionKey: launchKey,
            launchSuppressed: loopEvaluation.launchSuppressed,
            retryCountBucket: loopEvaluation.retryCountBucket,
            extensionContextActive: profileRuntimeLoaded(),
            logDiagnostic: makeConnectionLogger(profileId: profileId),
            replyHandler: { [self] value, error in
                if let coordinator = pendingCoordinatorRef.coordinator {
                    self.untrackPendingOneShot(coordinator)
                }
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == Self.errorDomain,
                       nsError.code == ErrorCode.companionAppProtocolUnknown.rawValue
                    {
                        self.loopGuard.recordCompanionAppProtocolUnknown(
                            key: loopKey,
                            launchAttempted: true
                        )
                    }
                } else {
                    self.loopGuard.recordSupportedAdapterLaunchAttempt(key: loopKey)
                }
                once.call(value, error)
            },
            registerCoordinator: { [self] coordinator in
                pendingCoordinatorRef.coordinator = coordinator
                self.trackPendingOneShot(
                    coordinator,
                    extensionId: extensionId,
                    profileId: profileId
                )
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

        SumiNativeMessagingRuntimeCounters.recordConnect(
            applicationIdentifier: applicationIdentifier
        )
        logRoutingEntry(
            delegateMethod: "connectUsing",
            direction: .connect,
            applicationIdentifier: applicationIdentifier,
            extensionId: extensionId,
            profileId: profileId
        )

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

        let adapterLookup = resolveRegisteredAdapter(
            applicationIdentifier: applicationIdentifier,
            hostBundleIdentifier: hostBundleIdentifier
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

        guard let adapter = adapterLookup.adapter else {
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
            logRoutingOutcome(
                delegateMethod: "connectUsing",
                direction: .connect,
                applicationIdentifier: applicationIdentifier,
                extensionId: extensionId,
                profileId: profileId,
                resolvedHostBundleIdentifier: hostBundleIdentifier,
                registryLookupAttempted: true,
                adapter: nil,
                adapterByApplicationIdentifier: adapterLookup.adapterByApplicationIdentifier,
                fallbackReason: "registryMiss"
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
            delegateMethod: "connectUsing",
            direction: .connect,
            applicationIdentifier: applicationIdentifier,
            extensionId: extensionId,
            profileId: profileId,
            resolvedHostBundleIdentifier: hostBundleIdentifier,
            registryLookupAttempted: true,
            adapter: adapter,
            adapterByApplicationIdentifier: adapterLookup.adapterByApplicationIdentifier,
            fallbackReason: nil
        )

        let session = SumiNativeMessagingPortSession(
            port: port,
            adapter: adapter,
            extensionId: extensionId,
            profileId: profileId,
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
        trackPortSession(session)
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
            recordDiagnostic(
                diagnostic,
                profileId: profileId,
                policyDenial: nil,
                evaluation: nil,
                loopKey: nil,
                hostBundleIdentifier: nil
            )
            teardownPortSession(session)
            trackedPortSessions.removeValue(forKey: ObjectIdentifier(session))
            completionHandler(
                SumiNativeMessagingErrorMapper.relayError(code: .hostNotFound, diagnostic: diagnostic)
            )
            return session
        }

        let launchKey = launchSessionKey(
            profileId: profileId,
            extensionId: extensionId,
            applicationIdentifier: applicationIdentifier,
            hostBundleIdentifier: hostBundleIdentifier
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
                    outcome: nsError.code == ErrorCode.hostNotFound.rawValue
                        ? .hostNotFound
                        : .hostLaunchFailed,
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
                self.recordDiagnostic(
                    diagnostic,
                    profileId: profileId,
                    evaluation: evaluation,
                    loopKey: loopKey,
                    hostBundleIdentifier: hostBundleIdentifier
                )
                self.teardownPortSession(session)
                self.trackedPortSessions.removeValue(forKey: ObjectIdentifier(session))
                completionHandler(error)
                return
            }

            self.loopGuard.recordSupportedAdapterLaunchAttempt(key: loopKey)
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
        launchPolicy.clear(forExtensionId: extensionId, profileId: profileId)
        loopGuard.clear(forExtensionId: extensionId, profileId: profileId)
        diagnosticCoalescer.clear(forExtensionId: extensionId, profileId: profileId)
        disconnectTrackedPortSessions(forExtensionId: extensionId, profileId: profileId)
    }

    func clearLaunchSessionOnExtensionContextUnload(
        forExtensionId extensionId: String,
        profileId: UUID? = nil
    ) {
        SumiNativeMessagingRuntimeCounters.recordContextUnload(extensionId: extensionId)
        cancelPendingOneShotRelays(forExtensionId: extensionId, profileId: profileId)
        launchPolicy.clearSessionKeys(forExtensionId: extensionId, profileId: profileId)
        loopGuard.clear(forExtensionId: extensionId, profileId: profileId)
        diagnosticCoalescer.clear(forExtensionId: extensionId, profileId: profileId)
        disconnectTrackedPortSessions(forExtensionId: extensionId, profileId: profileId)
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
        disconnectAllTrackedPortSessions()
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

    private func trackPortSession(_ session: SumiNativeMessagingPortSession) {
        trackedPortSessions[ObjectIdentifier(session)] = session
    }

    private func trackPendingOneShot(
        _ coordinator: SumiNativeMessagingOnceReplyCoordinator,
        extensionId: String,
        profileId: UUID?
    ) {
        pendingOneShotRelays[ObjectIdentifier(coordinator)] = PendingOneShotRelay(
            extensionId: extensionId,
            profileId: profileId,
            coordinator: coordinator
        )
    }

    private func untrackPendingOneShot(_ coordinator: SumiNativeMessagingOnceReplyCoordinator) {
        pendingOneShotRelays.removeValue(forKey: ObjectIdentifier(coordinator))
    }

    private func cancelPendingOneShotRelays(
        forExtensionId extensionId: String,
        profileId: UUID?
    ) {
        for (key, pending) in pendingOneShotRelays {
            guard pending.extensionId == extensionId else { continue }
            if let profileId, pending.profileId != profileId { continue }
            pending.coordinator.cancel()
            pendingOneShotRelays.removeValue(forKey: key)
        }
    }

    private func disconnectTrackedPortSessions(
        forExtensionId extensionId: String,
        profileId: UUID?
    ) {
        for (key, session) in trackedPortSessions {
            guard session.extensionId == extensionId else { continue }
            if let profileId, session.profileId != profileId { continue }
            teardownPortSession(session)
            trackedPortSessions.removeValue(forKey: key)
        }
    }

    private func disconnectAllTrackedPortSessions() {
        trackedPortSessions.values.forEach { teardownPortSession($0) }
        trackedPortSessions.removeAll()
    }

    private func teardownPortSession(_ session: SumiNativeMessagingPortSession) {
        if let adapter = adapterRegistry.adapter(
            forHostBundleIdentifier: session.resolvedHostBundleIdentifier
        ) {
            adapter.disconnectPort(session: session)
        }
        session.disconnect()
        SumiNativeMessagingRuntimeCounters.recordPortClosed()
    }

    private struct RegisteredAdapterLookup {
        let adapter: SumiNativeMessagingProtocolAdapter?
        let adapterByApplicationIdentifier: SumiNativeMessagingProtocolAdapter?
    }

    private func resolveRegisteredAdapter(
        applicationIdentifier: String?,
        hostBundleIdentifier: String
    ) -> RegisteredAdapterLookup {
        let byHost = adapterRegistry.adapter(forHostBundleIdentifier: hostBundleIdentifier)
        let byApplication = adapterRegistry.adapter(forApplicationIdentifier: applicationIdentifier)
        return RegisteredAdapterLookup(
            adapter: byHost ?? byApplication,
            adapterByApplicationIdentifier: byApplication
        )
    }

    private func logRoutingEntry(
        delegateMethod: String,
        direction: SafariExtensionNativeMessagingDirection,
        applicationIdentifier: String?,
        extensionId: String?,
        profileId: UUID?
    ) {
        SafariExtensionNativeMessagingRoutingProbe.logDelegateObserved(
            delegateMethod: delegateMethod,
            direction: direction,
            extensionId: extensionId,
            applicationIdentifier: applicationIdentifier,
            profileId: profileId
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
        RuntimeDiagnostics.debug(category: "SafariNativeMessaging") {
            """
            ext=\(diagnostic.extensionId) \
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
