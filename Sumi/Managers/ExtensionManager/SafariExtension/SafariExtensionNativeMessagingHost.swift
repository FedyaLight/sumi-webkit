//
//  SafariExtensionNativeMessagingHost.swift
//  Sumi
//
//  Public WebKit delegate bridge for Safari extension native messaging.
//  Maps extension context to host-app bundle identifiers and wakes the host
//  via NSWorkspace. Host message relay is not available on public macOS 15 APIs.
//

import AppKit
import Foundation
import WebKit

enum SafariExtensionNativeMessagingDirection: String, Sendable {
    case send
    case connect
    case portReceive
    case portRelay
}

enum SafariExtensionNativeMessagingOutcome: String, Sendable {
    case hostResolved
    case hostNotFound
    case hostLaunched
    case hostLaunchFailed
    case portConnected
    case hostRelayUnavailable
    case extensionContextMissing
}

struct SafariExtensionNativeMessagingDiagnostic: Sendable, Equatable {
    let extensionId: String
    let direction: SafariExtensionNativeMessagingDirection
    let requestedApplicationIdentifier: String?
    let hostBundleIdentifier: String?
    let outcome: SafariExtensionNativeMessagingOutcome
    let errorDomain: String?
    let errorCode: Int?
}

@MainActor
protocol SafariHostApplicationLaunching: AnyObject {
    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL?
    func openApplication(withBundleIdentifier bundleIdentifier: String) async throws
}

@MainActor
final class SumiNSWorkspaceHostApplicationLauncher: SafariHostApplicationLaunching {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func openApplication(withBundleIdentifier bundleIdentifier: String) async throws {
        guard let appURL = urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw SafariExtensionNativeMessagingHost.makeError(
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
enum SafariExtensionNativeMessagingResolver {
    /// Known extension host identifiers that differ from the containing `.app` bundle ID.
    static let hostApplicationIdentifierAliases: [String: String] = [
        "com.8bit.bitwarden": "com.bitwarden.desktop",
        "me.proton.pass.nm": "me.proton.pass.catalyst",
    ]

    static func resolveHostApplicationBundleIdentifier(
        requestedApplicationIdentifier: String?,
        extensionId: String?,
        installedExtensions: [InstalledExtension],
        importStore: SafariExtensionImportStore
    ) -> String? {
        let trimmedRequest = requestedApplicationIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedRequest, trimmedRequest.isEmpty == false {
            return normalizedHostBundleIdentifier(trimmedRequest)
        }

        guard let extensionId, extensionId.isEmpty == false else {
            return nil
        }

        if let installed = installedExtensions.first(where: { $0.id == extensionId }),
           installed.sourceKind == .safariAppExtension
        {
            if let containing = containingApplicationBundleIdentifier(
                forAppexPath: installed.sourceBundlePath
            ) {
                return containing
            }

            if let appexBundleID = appexBundleIdentifier(at: installed.sourceBundlePath),
               let discovered = importStore.discoveredCandidates().first(where: {
                   $0.extensionBundleIdentifier == appexBundleID
               }),
               let containing = containingApplicationBundleIdentifier(
                   forAppexPath: discovered.appexPath
               )
            {
                return containing
            }
        }

        return nil
    }

    static func normalizedHostBundleIdentifier(_ identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return hostApplicationIdentifierAliases[trimmed] ?? trimmed
    }

    static func containingApplicationBundleIdentifier(forAppexPath path: String) -> String? {
        var current = URL(fileURLWithPath: path).standardizedFileURL
        while current.path != "/" {
            if current.pathExtension == "app" {
                return Bundle(url: current)?.bundleIdentifier
            }
            current.deleteLastPathComponent()
        }
        return nil
    }

    static func appexBundleIdentifier(at path: String) -> String? {
        Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
    }
}

@MainActor
final class SafariExtensionNativeMessagingHost {
    enum ErrorCode: Int {
        case hostNotFound = 1
        case hostLaunchFailed = 2
        case hostRelayUnavailable = 3
        case extensionContextMissing = 4
    }

    static let errorDomain = "Sumi.SafariNativeMessaging"

    private let importStore: SafariExtensionImportStore
    private let launcher: SafariHostApplicationLaunching
    private let logDiagnostic: @MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void

    init(
        importStore: SafariExtensionImportStore = .shared,
        launcher: SafariHostApplicationLaunching = SumiNSWorkspaceHostApplicationLauncher(),
        logDiagnostic: (@MainActor (SafariExtensionNativeMessagingDiagnostic) -> Void)? = nil
    ) {
        self.importStore = importStore
        self.launcher = launcher
        self.logDiagnostic = logDiagnostic ?? Self.defaultDiagnosticLogger
    }

    func handleSendMessage(
        applicationIdentifier: String?,
        message: Any,
        extensionId: String?,
        installedExtensions: [InstalledExtension],
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        _ = message

        guard let extensionId else {
            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: "unknown",
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: nil,
                outcome: .extensionContextMissing,
                errorDomain: Self.errorDomain,
                errorCode: ErrorCode.extensionContextMissing.rawValue
            )
            logDiagnostic(diagnostic)
            replyHandler(nil, Self.makeError(code: .extensionContextMissing, diagnostic: diagnostic))
            return
        }

        guard let hostBundleIdentifier = SafariExtensionNativeMessagingResolver
            .resolveHostApplicationBundleIdentifier(
                requestedApplicationIdentifier: applicationIdentifier,
                extensionId: extensionId,
                installedExtensions: installedExtensions,
                importStore: importStore
            )
        else {
            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: nil,
                outcome: .hostNotFound,
                errorDomain: Self.errorDomain,
                errorCode: ErrorCode.hostNotFound.rawValue
            )
            logDiagnostic(diagnostic)
            replyHandler(nil, Self.makeError(code: .hostNotFound, diagnostic: diagnostic))
            return
        }

        logDiagnostic(
            SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: hostBundleIdentifier,
                outcome: .hostResolved,
                errorDomain: nil,
                errorCode: nil
            )
        )

        if launcher.urlForApplication(withBundleIdentifier: hostBundleIdentifier) == nil {
            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: hostBundleIdentifier,
                outcome: .hostNotFound,
                errorDomain: Self.errorDomain,
                errorCode: ErrorCode.hostNotFound.rawValue
            )
            logDiagnostic(diagnostic)
            replyHandler(nil, Self.makeError(code: .hostNotFound, diagnostic: diagnostic))
            return
        }

        Task { @MainActor in
            do {
                try await launcher.openApplication(withBundleIdentifier: hostBundleIdentifier)
                logDiagnostic(
                    SafariExtensionNativeMessagingDiagnostic(
                        extensionId: extensionId,
                        direction: .send,
                        requestedApplicationIdentifier: applicationIdentifier,
                        hostBundleIdentifier: hostBundleIdentifier,
                        outcome: .hostLaunched,
                        errorDomain: nil,
                        errorCode: nil
                    )
                )
            } catch {
                let nsError = error as NSError
                let launchCode: ErrorCode =
                    nsError.domain == Self.errorDomain
                    && nsError.code == ErrorCode.hostNotFound.rawValue
                    ? .hostNotFound
                    : .hostLaunchFailed
                let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                    extensionId: extensionId,
                    direction: .send,
                    requestedApplicationIdentifier: applicationIdentifier,
                    hostBundleIdentifier: hostBundleIdentifier,
                    outcome: launchCode == .hostNotFound ? .hostNotFound : .hostLaunchFailed,
                    errorDomain: nsError.domain,
                    errorCode: nsError.code
                )
                logDiagnostic(diagnostic)
                replyHandler(nil, Self.makeError(code: launchCode, diagnostic: diagnostic))
                return
            }

            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: .send,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: hostBundleIdentifier,
                outcome: .hostRelayUnavailable,
                errorDomain: Self.errorDomain,
                errorCode: ErrorCode.hostRelayUnavailable.rawValue
            )
            logDiagnostic(diagnostic)
            replyHandler(nil, Self.makeError(code: .hostRelayUnavailable, diagnostic: diagnostic))
        }
    }

    @discardableResult
    func handleConnect(
        port: WKWebExtension.MessagePort,
        extensionId: String?,
        installedExtensions: [InstalledExtension],
        registerHandler: (NativeMessagingHandler) -> Void,
        completionHandler: @escaping ((any Error)?) -> Void
    ) -> NativeMessagingHandler? {
        let applicationIdentifier = port.applicationIdentifier

        guard let extensionId else {
            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: "unknown",
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: nil,
                outcome: .extensionContextMissing,
                errorDomain: Self.errorDomain,
                errorCode: ErrorCode.extensionContextMissing.rawValue
            )
            logDiagnostic(diagnostic)
            port.disconnect()
            completionHandler(Self.makeError(code: .extensionContextMissing, diagnostic: diagnostic))
            return nil
        }

        guard let hostBundleIdentifier = SafariExtensionNativeMessagingResolver
            .resolveHostApplicationBundleIdentifier(
                requestedApplicationIdentifier: applicationIdentifier,
                extensionId: extensionId,
                installedExtensions: installedExtensions,
                importStore: importStore
            )
        else {
            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: nil,
                outcome: .hostNotFound,
                errorDomain: Self.errorDomain,
                errorCode: ErrorCode.hostNotFound.rawValue
            )
            logDiagnostic(diagnostic)
            port.disconnect()
            completionHandler(Self.makeError(code: .hostNotFound, diagnostic: diagnostic))
            return nil
        }

        logDiagnostic(
            SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: hostBundleIdentifier,
                outcome: .hostResolved,
                errorDomain: nil,
                errorCode: nil
            )
        )

        let handler = NativeMessagingHandler(
            port: port,
            extensionId: extensionId,
            hostBundleIdentifier: hostBundleIdentifier,
            logDiagnostic: logDiagnostic,
            hostRelayErrorProvider: {
                Self.makeError(
                    code: .hostRelayUnavailable,
                    diagnostic: SafariExtensionNativeMessagingDiagnostic(
                        extensionId: extensionId,
                        direction: .portRelay,
                        requestedApplicationIdentifier: applicationIdentifier,
                        hostBundleIdentifier: hostBundleIdentifier,
                        outcome: .hostRelayUnavailable,
                        errorDomain: Self.errorDomain,
                        errorCode: ErrorCode.hostRelayUnavailable.rawValue
                    )
                )
            }
        )
        registerHandler(handler)

        if launcher.urlForApplication(withBundleIdentifier: hostBundleIdentifier) == nil {
            let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                extensionId: extensionId,
                direction: .connect,
                requestedApplicationIdentifier: applicationIdentifier,
                hostBundleIdentifier: hostBundleIdentifier,
                outcome: .hostNotFound,
                errorDomain: Self.errorDomain,
                errorCode: ErrorCode.hostNotFound.rawValue
            )
            logDiagnostic(diagnostic)
            handler.disconnect()
            completionHandler(Self.makeError(code: .hostNotFound, diagnostic: diagnostic))
            return handler
        }

        Task { @MainActor in
            do {
                try await launcher.openApplication(withBundleIdentifier: hostBundleIdentifier)
                logDiagnostic(
                    SafariExtensionNativeMessagingDiagnostic(
                        extensionId: extensionId,
                        direction: .connect,
                        requestedApplicationIdentifier: applicationIdentifier,
                        hostBundleIdentifier: hostBundleIdentifier,
                        outcome: .hostLaunched,
                        errorDomain: nil,
                        errorCode: nil
                    )
                )
            } catch {
                let nsError = error as NSError
                let launchCode: ErrorCode =
                    nsError.domain == Self.errorDomain
                    && nsError.code == ErrorCode.hostNotFound.rawValue
                    ? .hostNotFound
                    : .hostLaunchFailed
                let diagnostic = SafariExtensionNativeMessagingDiagnostic(
                    extensionId: extensionId,
                    direction: .connect,
                    requestedApplicationIdentifier: applicationIdentifier,
                    hostBundleIdentifier: hostBundleIdentifier,
                    outcome: launchCode == .hostNotFound ? .hostNotFound : .hostLaunchFailed,
                    errorDomain: nsError.domain,
                    errorCode: nsError.code
                )
                logDiagnostic(diagnostic)
                handler.disconnect()
                completionHandler(Self.makeError(code: launchCode, diagnostic: diagnostic))
                return
            }

            logDiagnostic(
                SafariExtensionNativeMessagingDiagnostic(
                    extensionId: extensionId,
                    direction: .connect,
                    requestedApplicationIdentifier: applicationIdentifier,
                    hostBundleIdentifier: hostBundleIdentifier,
                    outcome: .portConnected,
                    errorDomain: nil,
                    errorCode: nil
                )
            )
            completionHandler(nil)
        }

        return handler
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
        case .hostRelayUnavailable:
            message = description
                ?? "Host application message relay is unavailable on public WebKit APIs in this Sumi build."
        case .extensionContextMissing:
            message = description
                ?? "The extension context for native messaging could not be resolved."
        }

        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let diagnostic {
            userInfo["SumiNativeMessagingDiagnostic"] = diagnostic.outcome.rawValue
            if let hostBundleIdentifier = diagnostic.hostBundleIdentifier {
                userInfo["SumiNativeMessagingHostBundleIdentifier"] = hostBundleIdentifier
            }
        }
        return NSError(domain: errorDomain, code: code.rawValue, userInfo: userInfo)
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
            outcome=\(diagnostic.outcome.rawValue) \
            err=\(diagnostic.errorDomain ?? "-")/\(diagnostic.errorCode.map(String.init) ?? "-")
            """
        }
    }
}
