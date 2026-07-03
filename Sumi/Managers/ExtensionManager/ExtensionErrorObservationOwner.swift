//
//  ExtensionErrorObservationOwner.swift
//  Sumi
//
//  Owns WKWebExtensionContext error observation: notification tokens,
//  deduplicated error logging, and fingerprint bookkeeping per extension.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionErrorObservationOwner {
    struct Dependencies {
        let shouldObserveExtensionErrors: @MainActor () -> Bool
        let recordErrorUpdateDuration: @MainActor (String, TimeInterval) -> Void
        let trace: @MainActor (() -> String) -> Void
    }

    private let dependencies: Dependencies
    private var observerTokens: [String: NSObjectProtocol] = [:]
    private var loggedErrorFingerprints: [String: String] = [:]

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var observedExtensionIDs: Set<String> {
        Set(observerTokens.keys)
    }

    var hasLoggedErrorFingerprints: Bool {
        loggedErrorFingerprints.isEmpty == false
    }

    func seedLoggedErrorFingerprintForTesting(
        _ fingerprint: String,
        extensionId: String
    ) {
        loggedErrorFingerprints[extensionId] = fingerprint
    }

    func observeExtensionErrors(
        for extensionContext: WKWebExtensionContext,
        extensionId: String
    ) {
        removeObserver(for: extensionId)
        guard dependencies.shouldObserveExtensionErrors() else { return }

        let token = NotificationCenter.default.addObserver(
            forName: WKWebExtensionContext.errorsDidUpdateNotification,
            object: extensionContext,
            queue: .main
        ) { [weak self, weak extensionContext] _ in
            guard let self, let extensionContext else { return }
            Task { @MainActor [weak self, weak extensionContext] in
                guard let self, let extensionContext else { return }
                self.logErrorsIfNeeded(
                    for: extensionContext,
                    extensionId: extensionId,
                    reason: "update"
                )
            }
        }

        observerTokens[extensionId] = token
        logErrorsIfNeeded(
            for: extensionContext,
            extensionId: extensionId,
            reason: "initial"
        )
    }

    func removeObserver(for extensionId: String) {
        guard let token = observerTokens.removeValue(forKey: extensionId) else {
            return
        }

        NotificationCenter.default.removeObserver(token)
    }

    func removeLoggedErrorFingerprint(for extensionId: String) {
        loggedErrorFingerprints.removeValue(forKey: extensionId)
    }

    func removeAllObservers() {
        for (_, token) in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()
    }

    func removeAllLoggedErrorFingerprints() {
        loggedErrorFingerprints.removeAll()
    }

    private func logErrorsIfNeeded(
        for extensionContext: WKWebExtensionContext,
        extensionId: String,
        reason: String
    ) {
        guard dependencies.shouldObserveExtensionErrors() else { return }

        let updateStart = CFAbsoluteTimeGetCurrent()
        defer {
            dependencies.recordErrorUpdateDuration(
                extensionId,
                CFAbsoluteTimeGetCurrent() - updateStart
            )
        }

        let errors = extensionContext.errors
        let fingerprint = errors
            .map { error in
                let nsError = error as NSError
                return [
                    nsError.domain,
                    String(nsError.code),
                    nsError.localizedDescription,
                    Self.describeUserInfo(nsError.userInfo),
                ].joined(separator: "|")
            }
            .joined(separator: "\n")

        guard loggedErrorFingerprints[extensionId] != fingerprint else {
            return
        }

        loggedErrorFingerprints[extensionId] = fingerprint

        guard errors.isEmpty == false else {
            dependencies.trace {
                "Extension errors \(reason) for \(extensionId): none"
            }
            return
        }

        for error in errors {
            let nsError = error as NSError
            let userInfoDescription = Self.describeUserInfo(nsError.userInfo)
            ExtensionManager.logger.error(
                "Extension error \(reason, privacy: .public) for \(extensionId, privacy: .public): domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) description=\(nsError.localizedDescription, privacy: .public) userInfo=\(userInfoDescription, privacy: .public)"
            )
        }
    }

    nonisolated private static func describeUserInfo(_ userInfo: [String: Any]) -> String {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard userInfo.isEmpty == false else {
                return "{}"
            }

            if JSONSerialization.isValidJSONObject(userInfo),
               let data = try? JSONSerialization.data(withJSONObject: userInfo, options: [.sortedKeys]),
               let string = String(data: data, encoding: .utf8) {
                return string
            }

            let parts = userInfo.keys.sorted().map { key in
                "\(key)=\(String(describing: userInfo[key] ?? "nil"))"
            }
            return "{\(parts.joined(separator: ", "))}"
        #else
            _ = userInfo
            return "{}"
        #endif
    }
}

@available(macOS 15.5, *)
extension ExtensionErrorObservationOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            shouldObserveExtensionErrors: {
                ExtensionManager.shouldObserveExtensionErrors
            },
            recordErrorUpdateDuration: { [weak manager] extensionId, duration in
                manager?.runtimeSessionOwner.recordRuntimeMetric(for: extensionId) {
                    $0.errorUpdateDuration = duration
                }
            },
            trace: { [weak manager] message in
                manager?.extensionRuntimeTrace(message())
            }
        )
    }
}
