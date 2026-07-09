//
//  SumiNativeMessagingRelay.swift
//  Sumi
//
//  Sumi-owned native/app messaging relay on public WKWebExtensionControllerDelegate hooks.
//  Facade composing the send/connect relay flows, route resolver, session
//  store, and diagnostics recorder behind the delegate-facing API.
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
    private let extensionsModuleEnabled: () -> Bool
    private let fallbackIsPrivateBrowsing: () -> Bool
    private let profileRuntimeLoaded: () -> Bool
    private let sessionStore: SumiNativeMessagingRelaySessionStore
    private let routeResolver: SumiNativeMessagingRelayRouteResolver
    private let oneShotFlow: SumiNativeMessagingOneShotRelayFlow
    private let portConnectFlow: SumiNativeMessagingPortConnectRelayFlow
    private let sendFlow: SumiNativeMessagingSendRelayFlow
    private let diagnosticsRecorder: SumiNativeMessagingDiagnosticsRecorder

    init(
        importStore: SafariExtensionImportStore = .process,
        launcher: SumiHostApplicationLaunching = SumiNSWorkspaceHostApplicationLauncher(),
        adapterRegistry: SumiNativeMessagingAdapterRegistry = .production(),
        companionApplicationRouter: CompanionApplicationMessageRouter =
            CompanionApplicationMessageRouter(),
        launchPolicy: SumiCompanionAppLaunchPolicy = SumiCompanionAppLaunchPolicy(),
        loopGuard: SumiNativeMessagingRelayLoopGuard = SumiNativeMessagingRelayLoopGuard(),
        extensionsModuleEnabled: @escaping @MainActor () -> Bool = { true },
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
        let oneShotFlow = SumiNativeMessagingOneShotRelayFlow(
            sessionStore: sessionStore,
            loopGuard: loopGuard,
            profileRuntimeLoaded: profileRuntimeLoaded
        )
        self.oneShotFlow = oneShotFlow
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
        let diagnosticsRecorder = SumiNativeMessagingDiagnosticsRecorder(
            adapterRegistry: adapterRegistry,
            launchPolicy: launchPolicy,
            loopGuard: loopGuard,
            profileRuntimeLoaded: profileRuntimeLoaded,
            logDiagnostic: logDiagnostic
        )
        self.diagnosticsRecorder = diagnosticsRecorder
        self.sendFlow = SumiNativeMessagingSendRelayFlow(
            companionApplicationRouter: companionApplicationRouter,
            routeResolver: routeResolver,
            oneShotFlow: oneShotFlow,
            launcher: launcher,
            launchPolicy: launchPolicy,
            loopGuard: loopGuard,
            diagnostics: diagnosticsRecorder,
            extensionsModuleEnabled: extensionsModuleEnabled
        )
    }

    static func production(
        importStore: SafariExtensionImportStore = .process,
        launcher: SumiHostApplicationLaunching = SumiNSWorkspaceHostApplicationLauncher(),
        extensionsModuleEnabled: @escaping @MainActor () -> Bool,
        isPrivateBrowsing: @escaping @MainActor () -> Bool = { false },
        profileRuntimeLoaded: @escaping @MainActor () -> Bool = { true },
        logDiagnostic: (@MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void)? = nil
    ) -> SumiNativeMessagingRelay {
        SumiNativeMessagingRelay(
            importStore: importStore,
            launcher: launcher,
            adapterRegistry: .production(),
            companionApplicationRouter: CompanionApplicationMessageRouter(
                registry: .production()
            ),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: extensionsModuleEnabled,
            isPrivateBrowsing: isPrivateBrowsing,
            profileRuntimeLoaded: profileRuntimeLoaded,
            logDiagnostic: logDiagnostic
        )
    }

    var diagnosticsAdapterRegistry: SumiNativeMessagingAdapterRegistry {
        adapterRegistry
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
        sendFlow.send(
            applicationIdentifier: applicationIdentifier,
            message: message,
            extensionId: extensionId,
            profileId: profileId,
            isPrivateBrowsing: isPrivateBrowsing,
            privateAccessAllowed: privateAccessAllowed,
            installedExtensions: installedExtensions,
            extensionDisplayName: extensionDisplayName,
            evaluatePolicy: evaluatePolicy,
            policyDeniedDiagnostic: policyDeniedDiagnostic,
            launchSessionKey: launchSessionKey,
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
            recordDiagnostic: { [diagnosticsRecorder] diagnostic, profileId, policyDenial, evaluation, loopKey, hostBundleIdentifier in
                diagnosticsRecorder.record(
                    diagnostic,
                    profileId: profileId,
                    policyDenial: policyDenial,
                    evaluation: evaluation,
                    loopKey: loopKey,
                    hostBundleIdentifier: hostBundleIdentifier
                )
            },
            logRoutingEntry: { [diagnosticsRecorder] delegateMethod, direction, applicationIdentifier, extensionId, extensionDisplayName, profileId, messageShape in
                diagnosticsRecorder.logRoutingEntry(
                    delegateMethod: delegateMethod,
                    direction: direction,
                    applicationIdentifier: applicationIdentifier,
                    extensionId: extensionId,
                    extensionDisplayName: extensionDisplayName,
                    profileId: profileId,
                    messageShape: messageShape
                )
            },
            logRoutingOutcome: { [diagnosticsRecorder] delegateMethod, direction, applicationIdentifier, extensionId, profileId, resolvedHostBundleIdentifier, registryLookupAttempted, adapter, adapterByApplicationIdentifier, fallbackReason in
                diagnosticsRecorder.logRoutingOutcome(
                    delegateMethod: delegateMethod,
                    direction: direction,
                    applicationIdentifier: applicationIdentifier,
                    extensionId: extensionId,
                    profileId: profileId,
                    resolvedHostBundleIdentifier: resolvedHostBundleIdentifier,
                    registryLookupAttempted: registryLookupAttempted,
                    adapter: adapter,
                    adapterByApplicationIdentifier: adapterByApplicationIdentifier,
                    fallbackReason: fallbackReason
                )
            },
            logConnectionDiagnostic: diagnosticsRecorder.makeConnectionLogger(profileId: profileId),
            outcomeForAdapterError: Self.outcome(forAdapterError:),
            launchSessionKey: launchSessionKey,
            completionHandler: completionHandler
        )
    }

    func clearCompanionState(forExtensionId extensionId: String, profileId: UUID? = nil) {
        launchPolicy.clear(forExtensionId: extensionId, profileId: profileId)
        loopGuard.clear(forExtensionId: extensionId, profileId: profileId)
        diagnosticsRecorder.clear(forExtensionId: extensionId, profileId: profileId)
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
        diagnosticsRecorder.clear(forExtensionId: extensionId, profileId: profileId)
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
        diagnosticsRecorder.clearAll()
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
        diagnostic _: SafariExtensionNativeMessagingDiagnostic?
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

        let userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
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
