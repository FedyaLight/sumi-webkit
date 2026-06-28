//
//  SumiNativeMessagingOneShotRelayFlow.swift
//  Sumi
//
//  One-shot native messaging completion bookkeeping after relay routing selects an adapter.
//

import Foundation

@MainActor
final class SumiNativeMessagingOneShotRelayFlow {
    private let sessionStore: SumiNativeMessagingRelaySessionStore
    private let loopGuard: SumiNativeMessagingRelayLoopGuard
    private let profileRuntimeLoaded: @MainActor () -> Bool
    private let recordAutofillRelaySuccess: @MainActor (String) -> Void

    init(
        sessionStore: SumiNativeMessagingRelaySessionStore,
        loopGuard: SumiNativeMessagingRelayLoopGuard,
        profileRuntimeLoaded: @escaping @MainActor () -> Bool,
        recordAutofillRelaySuccess: @escaping @MainActor (String) -> Void =
            SafariExtensionAutofillFillDiagnostics.noteNativeMessagingRelaySucceeded
    ) {
        self.sessionStore = sessionStore
        self.loopGuard = loopGuard
        self.profileRuntimeLoaded = profileRuntimeLoaded
        self.recordAutofillRelaySuccess = recordAutofillRelaySuccess
    }

    func relay(
        applicationIdentifier: String?,
        message: Any,
        extensionId: String,
        profileId: UUID?,
        evaluation: SumiCompanionAppResolverResult,
        adapter: SumiNativeMessagingProtocolAdapter,
        launcher: SumiHostApplicationLaunching,
        launchPolicy: SumiCompanionAppLaunchPolicy,
        launchSessionKey: SumiCompanionAppLaunchSessionKey,
        loopKey: SumiNativeMessagingRelayLoopGuard.SessionKey,
        loopEvaluation: SumiNativeMessagingRelayLoopGuard.Evaluation,
        logDiagnostic: @escaping @MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        let once = SumiNativeMessagingOneShotReplyHandler(replyHandler)
        let pendingCoordinatorRef = SumiNativeMessagingPendingOneShotCoordinatorRef()
        SumiNativeMessagingConnection.relayOneShot(
            applicationIdentifier: applicationIdentifier,
            message: message,
            extensionId: extensionId,
            evaluation: evaluation,
            adapter: adapter,
            launcher: launcher,
            launchPolicy: launchPolicy,
            launchSessionKey: launchSessionKey,
            launchSuppressed: loopEvaluation.launchSuppressed,
            retryCountBucket: loopEvaluation.retryCountBucket,
            extensionContextActive: profileRuntimeLoaded(),
            logDiagnostic: logDiagnostic,
            replyHandler: { [self] value, error in
                if let coordinator = pendingCoordinatorRef.coordinator {
                    self.sessionStore.untrackPendingOneShot(coordinator)
                }
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == SumiNativeMessagingRelay.errorDomain,
                       nsError.code == SumiNativeMessagingRelay.ErrorCode
                           .companionAppProtocolUnknown.rawValue {
                        self.loopGuard.recordCompanionAppProtocolUnknown(
                            key: loopKey,
                            launchAttempted: true
                        )
                    }
                } else {
                    self.loopGuard.recordSupportedAdapterLaunchAttempt(key: loopKey)
                    self.recordAutofillRelaySuccess(extensionId)
                }
                once.call(value, error)
            },
            registerCoordinator: { [self] coordinator in
                pendingCoordinatorRef.coordinator = coordinator
                self.sessionStore.trackPendingOneShot(
                    coordinator,
                    extensionId: extensionId,
                    profileId: profileId
                )
            }
        )
    }
}

@MainActor
private final class SumiNativeMessagingPendingOneShotCoordinatorRef {
    var coordinator: SumiNativeMessagingOnceReplyCoordinator?
}

@MainActor
private final class SumiNativeMessagingOneShotReplyHandler {
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
