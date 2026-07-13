import Foundation
import WebKit

/// Observes errors for one exact profile-scoped WebExtension context.
/// Replacement of the same key retires the previous token, while contexts for
/// different profiles remain independent.
@available(macOS 15.5, *)
@MainActor
final class ExtensionContextErrorObservation {
    private final class Entry {
        weak var context: WKWebExtensionContext?
        let token: NSObjectProtocol

        init(context: WKWebExtensionContext, token: NSObjectProtocol) {
            self.context = context
            self.token = token
        }
    }

    private let recordRuntimeMetric: @MainActor (
        String,
        (inout ExtensionManager.ExtensionRuntimeMetrics) -> Void
    ) -> Void
    private let trace: @MainActor (String) -> Void
    private let isEnabled: @MainActor () -> Bool
    private var entries:
        [ExtensionRuntimeResidencyState.ScopedKey: Entry] = [:]
    private var loggedErrorFingerprints:
        [ExtensionRuntimeResidencyState.ScopedKey: String] = [:]

    init(
        recordRuntimeMetric: @escaping @MainActor (
            String,
            (inout ExtensionManager.ExtensionRuntimeMetrics) -> Void
        ) -> Void,
        trace: @escaping @MainActor (String) -> Void,
        isEnabled: @escaping @MainActor () -> Bool = {
            ExtensionManager.shouldObserveExtensionErrors
        }
    ) {
        self.recordRuntimeMetric = recordRuntimeMetric
        self.trace = trace
        self.isEnabled = isEnabled
    }

    var observedExtensionIDs: Set<String> {
        Set(entries.keys.map(\.extensionId))
    }

    var hasLoggedErrorFingerprints: Bool {
        loggedErrorFingerprints.isEmpty == false
    }

    func seedLoggedErrorFingerprintForTesting(
        _ fingerprint: String,
        extensionId: String,
        profileId: UUID
    ) {
        loggedErrorFingerprints[key(extensionId, profileId)] = fingerprint
    }

    func observe(
        _ context: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) {
        let key = key(extensionId, profileId)
        removeObservation(for: key)
        loggedErrorFingerprints.removeValue(forKey: key)
        guard isEnabled() else { return }

        let token = NotificationCenter.default.addObserver(
            forName: WKWebExtensionContext.errorsDidUpdateNotification,
            object: context,
            queue: .main
        ) { [weak self, weak context] _ in
            guard let self, let context else { return }
            Task { @MainActor [weak self, weak context] in
                guard let self, let context else { return }
                self.logErrorsIfCurrent(
                    context,
                    key: key,
                    reason: "update"
                )
            }
        }

        entries[key] = Entry(context: context, token: token)
        logErrorsIfCurrent(context, key: key, reason: "initial")
    }

    func removeObservation(
        ifObserving context: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) {
        let key = key(extensionId, profileId)
        guard entries[key]?.context === context else { return }
        removeObservation(for: key)
    }

    func removeObservations(forExtensionID extensionId: String) {
        let keys = entries.keys.filter { $0.extensionId == extensionId }
        for key in keys {
            removeObservation(for: key)
        }
    }

    func removeAllObservations() {
        for entry in entries.values {
            NotificationCenter.default.removeObserver(entry.token)
        }
        entries.removeAll()
    }

    func removeLoggedErrorFingerprints(forExtensionID extensionId: String) {
        loggedErrorFingerprints = loggedErrorFingerprints.filter {
            $0.key.extensionId != extensionId
        }
    }

    func removeAllLoggedErrorFingerprints() {
        loggedErrorFingerprints.removeAll()
    }

    private func removeObservation(
        for key: ExtensionRuntimeResidencyState.ScopedKey
    ) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        NotificationCenter.default.removeObserver(entry.token)
    }

    private func logErrorsIfCurrent(
        _ context: WKWebExtensionContext,
        key: ExtensionRuntimeResidencyState.ScopedKey,
        reason: String
    ) {
        guard isEnabled(),
              entries[key]?.context === context
        else {
            return
        }

        let updateStart = CFAbsoluteTimeGetCurrent()
        defer {
            recordRuntimeMetric(key.extensionId) {
                $0.errorUpdateDuration =
                    CFAbsoluteTimeGetCurrent() - updateStart
            }
        }

        let errors = context.errors
        let fingerprint = errors.map { error in
            let nsError = error as NSError
            return [
                nsError.domain,
                String(nsError.code),
                nsError.localizedDescription,
                Self.describeUserInfo(nsError.userInfo),
            ].joined(separator: "|")
        }.joined(separator: "\n")

        guard loggedErrorFingerprints[key] != fingerprint else { return }
        loggedErrorFingerprints[key] = fingerprint

        guard errors.isEmpty == false else {
            trace(
                "Extension errors \(reason) for \(key.extensionId) "
                    + "profile \(key.profileId.uuidString): none"
            )
            return
        }

        for error in errors {
            let nsError = error as NSError
            let userInfoDescription = Self.describeUserInfo(nsError.userInfo)
            ExtensionManager.logger.error(
                "Extension error \(reason, privacy: .public) for \(key.extensionId, privacy: .public) profile \(key.profileId.uuidString, privacy: .public): domain=\(nsError.domain, privacy: .public) code=\(nsError.code) description=\(nsError.localizedDescription, privacy: .public) userInfo=\(userInfoDescription, privacy: .public)"
            )
        }
    }

    private func key(
        _ extensionId: String,
        _ profileId: UUID
    ) -> ExtensionRuntimeResidencyState.ScopedKey {
        ExtensionRuntimeResidencyState.ScopedKey(
            profileId: profileId,
            extensionId: extensionId
        )
    }

    nonisolated private static func describeUserInfo(
        _ userInfo: [String: Any]
    ) -> String {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard userInfo.isEmpty == false else { return "{}" }
            if JSONSerialization.isValidJSONObject(userInfo) {
                do {
                    let data = try JSONSerialization.data(
                        withJSONObject: userInfo,
                        options: [.sortedKeys]
                    )
                    if let string = String(data: data, encoding: .utf8) {
                        return string
                    }
                } catch {
                    return fallbackUserInfoDescription(userInfo)
                }
            }
            return fallbackUserInfoDescription(userInfo)
        #else
            _ = userInfo
            return "{}"
        #endif
    }

    nonisolated private static func fallbackUserInfoDescription(
        _ userInfo: [String: Any]
    ) -> String {
        let parts = userInfo.keys.sorted().map { key in
            "\(key)=\(String(describing: userInfo[key] ?? "nil"))"
        }
        return "{\(parts.joined(separator: ", "))}"
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func observeExtensionErrors(
        for extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) {
        contextErrorObservation.observe(
            extensionContext,
            extensionId: extensionId,
            profileId: profileId
        )
    }
}
