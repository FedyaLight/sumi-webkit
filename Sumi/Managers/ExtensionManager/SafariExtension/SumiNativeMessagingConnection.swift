//
//  SumiNativeMessagingConnection.swift
//  Sumi
//
//  One-time native messaging via WKWebExtensionControllerDelegate sendMessage.
//

import Foundation

@MainActor
protocol SumiHostApplicationLaunching: AnyObject {
    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL?
    func openApplication(withBundleIdentifier bundleIdentifier: String) async throws
}

@MainActor
final class SumiNSWorkspaceHostApplicationLauncher: SumiHostApplicationLaunching {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func openApplication(withBundleIdentifier bundleIdentifier: String) async throws {
        guard let appURL = urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw SumiNativeMessagingRelay.makeError(
                code: .hostNotFound,
                description: "No installed application matches the resolved host bundle identifier.",
                diagnostic: nil
            )
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            workspace.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

@MainActor
final class SumiLaunchPolicyGatedHostApplicationLauncher: SumiHostApplicationLaunching {
    private let underlying: SumiHostApplicationLaunching
    private let launchPolicy: SumiCompanionAppLaunchPolicy
    private let hostBundleIdentifier: String
    private let protocolAdapterAvailable: Bool
    private let sessionKey: SumiCompanionAppLaunchSessionKey?
    private let launchReason: SumiCompanionAppLaunchReason
    var lastLaunchDecision: SumiCompanionAppLaunchDecision?
    var lastLaunchSuppressed = false

    init(
        underlying: SumiHostApplicationLaunching,
        launchPolicy: SumiCompanionAppLaunchPolicy,
        hostBundleIdentifier: String,
        protocolAdapterAvailable: Bool,
        sessionKey: SumiCompanionAppLaunchSessionKey? = nil,
        launchReason: SumiCompanionAppLaunchReason = .adapterConnect
    ) {
        self.underlying = underlying
        self.launchPolicy = launchPolicy
        self.hostBundleIdentifier = hostBundleIdentifier
        self.protocolAdapterAvailable = protocolAdapterAvailable
        self.sessionKey = sessionKey
        self.launchReason = launchReason
    }

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        underlying.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func openApplication(withBundleIdentifier bundleIdentifier: String) async throws {
        guard bundleIdentifier == hostBundleIdentifier else {
            throw SumiNativeMessagingRelay.makeError(
                code: .hostLaunchFailed,
                description: "Refusing to launch an application outside the resolved host bundle identifier.",
                diagnostic: nil
            )
        }

        let appInstalled = underlying.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
        let decision = launchPolicy.evaluateLaunch(
            hostBundleIdentifier: hostBundleIdentifier,
            appInstalled: appInstalled,
            protocolAdapterAvailable: protocolAdapterAvailable,
            sessionKey: sessionKey,
            isHostRunning: launchPolicy.isHostApplicationRunning(hostBundleIdentifier: hostBundleIdentifier)
        )
        lastLaunchDecision = decision
        lastLaunchSuppressed = decision != .allowed
        guard decision == .allowed else {
            if let sessionKey {
                launchPolicy.recordLaunchSuppressed(sessionKey: sessionKey, decision: decision)
            }
            throw SumiNativeMessagingRelay.makeError(
                code: .companionAppProtocolUnknown,
                diagnostic: nil
            )
        }
        try await launchPolicy.launchInstalledApplication(
            hostBundleIdentifier: bundleIdentifier,
            sessionKey: sessionKey,
            launcher: underlying
        )
        _ = launchReason
    }
}

@MainActor
final class SumiNativeMessagingOnceReplyCoordinator {
    private var replyHandler: ((Any?, (any Error)?) -> Void)?
    private var fulfilled = false
    private var relayTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(_ replyHandler: @escaping (Any?, (any Error)?) -> Void) {
        self.replyHandler = replyHandler
    }

    func startRelay(
        timeout: Duration = SumiNativeMessagingConnection.defaultReplyTimeout,
        operation: @escaping @MainActor () async -> Void
    ) {
        relayTask = Task { @MainActor in
            await operation()
        }

        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            guard fulfilled == false else { return }
            relayTask?.cancel()
            complete(
                nil,
                SumiNativeMessagingErrorMapper.relayError(
                    code: .relayTimeout,
                    diagnostic: nil
                )
            )
        }
    }

    func complete(_ value: Any?, _ error: (any Error)?) {
        guard fulfilled == false else { return }
        fulfilled = true
        timeoutTask?.cancel()
        relayTask?.cancel()
        replyHandler?(value, error)
        replyHandler = nil
    }

    var isFulfilled: Bool { fulfilled }
}

@MainActor
enum SumiNativeMessagingConnection {
    static let defaultReplyTimeout: Duration = .seconds(30)

    static func relayOneShot(
        applicationIdentifier: String?,
        message: Any,
        extensionId: String,
        evaluation: SumiCompanionAppResolverResult,
        adapter: SumiNativeMessagingProtocolAdapter,
        launcher: SumiHostApplicationLaunching,
        launchPolicy: SumiCompanionAppLaunchPolicy,
        launchSessionKey: SumiCompanionAppLaunchSessionKey? = nil,
        launchSuppressed: Bool = false,
        retryCountBucket: SumiNativeMessagingRetryCountBucket = .none,
        extensionContextActive: Bool? = nil,
        logDiagnostic: @escaping (SafariExtensionNativeMessagingDiagnostic) -> Void,
        replyHandler: @escaping (Any?, (any Error)?) -> Void,
        replyTimeout: Duration = defaultReplyTimeout
    ) {
        guard let detail = evaluation.detail else {
            let diagnostic = Self.diagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation,
                launchSuppressed: launchSuppressed,
                retryCountBucket: retryCountBucket
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

        logDiagnostic(
            Self.diagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation,
                outcome: .hostResolved,
                launchAttempted: false,
                launchSuppressed: launchSuppressed,
                retryCountBucket: retryCountBucket
            )
        )

        let hostBundleIdentifier = detail.resolvedBundleIdentifier

        guard launcher.urlForApplication(withBundleIdentifier: hostBundleIdentifier) != nil else {
            let diagnostic = Self.diagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: .appNotFound(detail),
                outcome: .hostNotFound,
                launchSuppressed: launchSuppressed,
                retryCountBucket: retryCountBucket
            )
            logDiagnostic(diagnostic)
            replyHandler(
                nil,
                SumiNativeMessagingErrorMapper.relayError(code: .hostNotFound, diagnostic: diagnostic)
            )
            return
        }

        guard SumiCompanionAppResolver.shouldLaunchApp(for: evaluation) else {
            let diagnostic = Self.diagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                evaluation: evaluation,
                launchAttempted: false,
                launchSuppressed: true,
                retryCountBucket: retryCountBucket
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

        let gatedLauncher = SumiLaunchPolicyGatedHostApplicationLauncher(
            underlying: launcher,
            launchPolicy: launchPolicy,
            hostBundleIdentifier: hostBundleIdentifier,
            protocolAdapterAvailable: detail.protocolAdapterAvailable,
            sessionKey: launchSessionKey,
            launchReason: .adapterOneShot
        )

        let coordinator = SumiNativeMessagingOnceReplyCoordinator(replyHandler)
        let request = SumiNativeMessagingOneShotRequest(
            applicationIdentifier: applicationIdentifier,
            extensionId: extensionId,
            hostBundleIdentifier: hostBundleIdentifier,
            resolverBucket: evaluation.legacyResolverBucket,
            message: message
        )

        coordinator.startRelay(timeout: replyTimeout) { @MainActor in
            adapter.relayOneShotMessage(
                request: request,
                launcher: gatedLauncher
            ) { value, error in
                if let error {
                    let nsError = error as NSError
                    let diagnostic = Self.diagnostic(
                        extensionId: extensionId,
                        direction: .send,
                        requestedApplicationIdentifier: applicationIdentifier,
                        evaluation: evaluation,
                        outcome: Self.outcome(forRelayError: nsError),
                        errorDomain: nsError.domain,
                        errorCode: nsError.code,
                        launchAttempted: true,
                        launchSuppressed: launchSuppressed,
                        retryCountBucket: retryCountBucket,
                        adapter: adapter
                    )
                    logDiagnostic(diagnostic)
                    coordinator.complete(
                        nil,
                        SumiNativeMessagingErrorMapper.relayError(
                            code: Self.relayCode(for: nsError),
                            diagnostic: diagnostic
                        )
                    )
                    return
                }

                logDiagnostic(
                    Self.diagnostic(
                        extensionId: extensionId,
                        direction: .send,
                        requestedApplicationIdentifier: applicationIdentifier,
                        evaluation: evaluation,
                        outcome: .portConnected,
                        launchAttempted: true,
                        launchSuppressed: launchSuppressed,
                        retryCountBucket: retryCountBucket,
                        adapter: adapter
                    )
                )
                coordinator.complete(value, nil)
            }

            guard Task.isCancelled == false else {
                let diagnostic = Self.diagnostic(
                    extensionId: extensionId,
                    direction: .send,
                    requestedApplicationIdentifier: applicationIdentifier,
                    evaluation: evaluation,
                    outcome: .relayCancelled,
                    errorDomain: SumiNativeMessagingRelay.errorDomain,
                    errorCode: SumiNativeMessagingRelay.ErrorCode.relayCancelled.rawValue,
                    launchAttempted: true,
                    launchSuppressed: launchSuppressed,
                    retryCountBucket: retryCountBucket,
                    adapter: adapter
                )
                logDiagnostic(diagnostic)
                coordinator.complete(
                    nil,
                    SumiNativeMessagingErrorMapper.relayError(
                        code: .relayCancelled,
                        diagnostic: diagnostic
                    )
                )
                return
            }
        }
    }

    static func diagnostic(
        extensionId: String,
        direction: SafariExtensionNativeMessagingDirection,
        requestedApplicationIdentifier: String?,
        evaluation: SumiCompanionAppResolverResult,
        outcome resolvedOutcome: SafariExtensionNativeMessagingOutcome? = nil,
        errorDomain: String? = nil,
        errorCode: Int? = nil,
        launchAttempted: Bool? = nil,
        launchSuppressed: Bool? = nil,
        retryCountBucket: SumiNativeMessagingRetryCountBucket? = nil,
        launchReason: SumiCompanionAppLaunchReason? = nil,
        launchRequestedByAdapter: Bool? = nil,
        launchCooldownBucket: SumiNativeMessagingRetryCountBucket? = nil,
        extensionContextActive: Bool? = nil,
        adapter: SumiNativeMessagingProtocolAdapter? = nil
    ) -> SafariExtensionNativeMessagingDiagnostic {
        let detail = evaluation.detail
        let base = SafariExtensionNativeMessagingDiagnostic(
            extensionId: extensionId,
            direction: direction,
            requestedApplicationIdentifier: requestedApplicationIdentifier,
            hostBundleIdentifier: detail?.resolvedBundleIdentifier,
            resolverBucket: detail.map { _ in evaluation.legacyResolverBucket },
            outcome: resolvedOutcome ?? Self.outcome(for: evaluation),
            errorDomain: errorDomain,
            errorCode: errorCode,
            launchAttempted: launchAttempted,
            launchSuppressed: launchSuppressed,
            retryCountBucket: retryCountBucket,
            launchReason: launchReason,
            launchRequestedByAdapter: launchRequestedByAdapter,
            launchCooldownBucket: launchCooldownBucket,
            extensionContextActive: extensionContextActive,
            isContainingApp: detail?.isContainingApp,
            protocolAdapterAvailable: detail?.protocolAdapterAvailable,
            launchAllowed: detail?.launchAllowed,
            appResolved: detail != nil,
            appLaunched: launchAttempted
        )
        return SafariExtensionNativeMessagingDiagnosticEnrichment.enrich(
            base,
            adapter: adapter,
            adapterIdentifier: adapter?.protocolIdentifier,
            evaluation: evaluation
        )
    }

    private static func relayCode(for error: NSError) -> SumiNativeMessagingRelay.ErrorCode {
        if error.domain == SumiNativeMessagingRelay.errorDomain,
           let mapped = SumiNativeMessagingRelay.ErrorCode(rawValue: error.code)
        {
            return mapped
        }
        return .hostLaunchFailed
    }

    private static func outcome(forRelayError error: NSError) -> SafariExtensionNativeMessagingOutcome {
        switch relayCode(for: error) {
        case .hostNotFound:
            return .hostNotFound
        case .hostLaunchFailed:
            return .hostLaunchFailed
        case .companionAppProtocolUnknown:
            return .companionAppProtocolUnknown
        case .relayTimeout:
            return .relayTimeout
        case .relayCancelled:
            return .relayCancelled
        default:
            return .hostLaunchFailed
        }
    }

    private static func outcome(
        for evaluation: SumiCompanionAppResolverResult
    ) -> SafariExtensionNativeMessagingOutcome {
        switch evaluation {
        case .appNotFound:
            return .hostNotFound
        case .launchRateLimited:
            return .launchRateLimited
        case .launchSuppressed:
            return .launchSuppressed
        case .protocolAdapterUnavailable, .appFoundButProtocolUnknown:
            return .companionAppProtocolUnknown
        default:
            return .companionAppProtocolUnknown
        }
    }
}

// Legacy launcher protocol name used by existing tests.
typealias SafariHostApplicationLaunching = SumiHostApplicationLaunching
