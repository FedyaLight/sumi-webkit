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
enum SumiNativeMessagingConnection {
    static let defaultReplyTimeout: Duration = .seconds(30)

    static func relayOneShot(
        applicationIdentifier: String?,
        message: Any,
        extensionId: String,
        hostResolution: SumiNativeMessagingAppResolution,
        launcher: SumiHostApplicationLaunching,
        logDiagnostic: @escaping (SafariExtensionNativeMessagingDiagnostic) -> Void,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        _ = message

        logDiagnostic(
            SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: hostResolution.hostBundleIdentifier,
                resolverBucket: hostResolution.bucket,
                outcome: .hostResolved,
                errorDomain: nil,
                errorCode: nil
            )
        )

        let hostBundleIdentifier = hostResolution.hostBundleIdentifier

        guard launcher.urlForApplication(withBundleIdentifier: hostBundleIdentifier) != nil else {
            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: hostBundleIdentifier,
                resolverBucket: hostResolution.bucket,
                outcome: .hostNotFound,
                errorDomain: SumiNativeMessagingRelay.errorDomain,
                errorCode: SumiNativeMessagingRelay.ErrorCode.hostNotFound.rawValue
            )
            logDiagnostic(diagnostic)
            replyHandler(
                nil,
                SumiNativeMessagingRelay.makeError(code: .hostNotFound, diagnostic: diagnostic)
            )
            return
        }

        var completed = false
        let complete: (Any?, (any Error)?) -> Void = { value, error in
            guard completed == false else { return }
            completed = true
            replyHandler(value, error)
        }

        let relayTask = Task { @MainActor in
            do {
                try await launcher.openApplication(withBundleIdentifier: hostBundleIdentifier)
                logDiagnostic(
                    SafariExtensionNativeMessagingDiagnostic(
                        extensionId: extensionId,
                        direction: .send,
                        requestedApplicationIdentifier: applicationIdentifier,
                        hostBundleIdentifier: hostBundleIdentifier,
                        resolverBucket: hostResolution.bucket,
                        outcome: .hostLaunched,
                        errorDomain: nil,
                        errorCode: nil
                    )
                )
            } catch {
                let nsError = error as NSError
                let launchCode: SumiNativeMessagingRelay.ErrorCode =
                    nsError.domain == SumiNativeMessagingRelay.errorDomain
                    && nsError.code == SumiNativeMessagingRelay.ErrorCode.hostNotFound.rawValue
                    ? .hostNotFound
                    : .hostLaunchFailed
                let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                    extensionId: extensionId,
                    direction: .send,
                    requestedApplicationIdentifier: applicationIdentifier,
                    hostBundleIdentifier: hostBundleIdentifier,
                    resolverBucket: hostResolution.bucket,
                    outcome: launchCode == .hostNotFound ? .hostNotFound : .hostLaunchFailed,
                    errorDomain: nsError.domain,
                    errorCode: nsError.code
                )
                logDiagnostic(diagnostic)
                complete(nil, SumiNativeMessagingRelay.makeError(code: launchCode, diagnostic: diagnostic))
                return
            }

            guard Task.isCancelled == false else {
                let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                    extensionId: extensionId,
                    direction: .send,
                    requestedApplicationIdentifier: applicationIdentifier,
                    hostBundleIdentifier: hostBundleIdentifier,
                    resolverBucket: hostResolution.bucket,
                    outcome: .relayCancelled,
                    errorDomain: SumiNativeMessagingRelay.errorDomain,
                    errorCode: SumiNativeMessagingRelay.ErrorCode.relayCancelled.rawValue
                )
                logDiagnostic(diagnostic)
                complete(
                    nil,
                    SumiNativeMessagingRelay.makeError(code: .relayCancelled, diagnostic: diagnostic)
                )
                return
            }

            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: hostBundleIdentifier,
                resolverBucket: hostResolution.bucket,
                outcome: .companionAppProtocolUnknown,
                errorDomain: SumiNativeMessagingRelay.errorDomain,
                errorCode: SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue
            )
            logDiagnostic(diagnostic)
            complete(
                nil,
                SumiNativeMessagingRelay.makeError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: diagnostic
                )
            )
        }

        Task { @MainActor in
            try? await Task.sleep(for: defaultReplyTimeout)
            guard completed == false else { return }
            relayTask.cancel()
            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: hostBundleIdentifier,
                resolverBucket: hostResolution.bucket,
                outcome: .relayTimeout,
                errorDomain: SumiNativeMessagingRelay.errorDomain,
                errorCode: SumiNativeMessagingRelay.ErrorCode.relayTimeout.rawValue
            )
            logDiagnostic(diagnostic)
            complete(
                nil,
                SumiNativeMessagingRelay.makeError(code: .relayTimeout, diagnostic: diagnostic)
            )
        }
    }
}

// Legacy launcher protocol name used by existing tests.
typealias SafariHostApplicationLaunching = SumiHostApplicationLaunching
