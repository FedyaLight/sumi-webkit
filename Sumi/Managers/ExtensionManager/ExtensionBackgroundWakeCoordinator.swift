import Foundation
import WebKit

/// Coordinates background-content wakes for extension contexts: resolves the
/// scoped wake key, drives the background runtime state machine, and schedules
/// native-messaging wakes with failure logging.
@available(macOS 15.5, *)
@MainActor
final class ExtensionBackgroundWakeCoordinator {
    private let backgroundRuntimeStateOwner: ExtensionBackgroundRuntimeStateOwner
    private let nativeMessagingBackgroundWakeOwner: @MainActor () -> ExtensionNativeMessagingBackgroundWakeOwner?
    private let contextIdentity: @MainActor (WKWebExtensionContext) -> (extensionId: String, profileId: UUID)?
    private let resolvedProfileId: @MainActor (UUID?) -> UUID?
    private let recordRuntimeMetric: @MainActor (String, (inout ExtensionManager.ExtensionRuntimeMetrics) -> Void) -> Void
    private let trace: @MainActor (String) -> Void
    private let logBackgroundWakeFailure: @MainActor (
        Error,
        WKWebExtensionContext,
        ExtensionManager.ExtensionBackgroundWakeReason,
        String
    ) -> Void
    /// Debug-only wake override; returns nil in release builds.
    private let debugBackgroundContentWake: @MainActor ()
        -> (@MainActor (String, WKWebExtensionContext) async throws -> Void)?

    init(
        backgroundRuntimeStateOwner: ExtensionBackgroundRuntimeStateOwner,
        nativeMessagingBackgroundWakeOwner: @escaping @MainActor () -> ExtensionNativeMessagingBackgroundWakeOwner?,
        contextIdentity: @escaping @MainActor (WKWebExtensionContext) -> (extensionId: String, profileId: UUID)?,
        resolvedProfileId: @escaping @MainActor (UUID?) -> UUID?,
        recordRuntimeMetric: @escaping @MainActor (String, (inout ExtensionManager.ExtensionRuntimeMetrics) -> Void) -> Void,
        trace: @escaping @MainActor (String) -> Void,
        logBackgroundWakeFailure: @escaping @MainActor (
            Error,
            WKWebExtensionContext,
            ExtensionManager.ExtensionBackgroundWakeReason,
            String
        ) -> Void,
        debugBackgroundContentWake: @escaping @MainActor ()
            -> (@MainActor (String, WKWebExtensionContext) async throws -> Void)?
    ) {
        self.backgroundRuntimeStateOwner = backgroundRuntimeStateOwner
        self.nativeMessagingBackgroundWakeOwner = nativeMessagingBackgroundWakeOwner
        self.contextIdentity = contextIdentity
        self.resolvedProfileId = resolvedProfileId
        self.recordRuntimeMetric = recordRuntimeMetric
        self.trace = trace
        self.logBackgroundWakeFailure = logBackgroundWakeFailure
        self.debugBackgroundContentWake = debugBackgroundContentWake
    }

    @discardableResult
    func ensureBackgroundAvailableIfRequired(
        for webExtension: WKWebExtension,
        context extensionContext: WKWebExtensionContext,
        reason: ExtensionManager.ExtensionBackgroundWakeReason
    ) async throws -> Bool {
        let wakeKey = backgroundWakeKey(for: extensionContext)
        return try await backgroundRuntimeStateOwner.ensureBackgroundAvailableIfRequired(
            wakeKey: wakeKey,
            hasBackgroundContent: webExtension.hasBackgroundContent,
            reason: reason,
            trace: { [trace] in trace($0) },
            loadBackgroundContent: { [debugBackgroundContentWake] in
                if let backgroundContentWake = debugBackgroundContentWake() {
                    try await backgroundContentWake(wakeKey, extensionContext)
                } else {
                    try await extensionContext.loadBackgroundContent()
                }
            },
            recordWakeMetric: { [recordRuntimeMetric] duration, reason, didFail in
                recordRuntimeMetric(wakeKey) {
                    $0.backgroundWakeDuration = duration
                    $0.backgroundWakeCount += 1
                    $0.lastBackgroundWakeReason = reason
                    $0.lastBackgroundWakeFailed = didFail
                }
            }
        )
    }

    func scheduleNativeMessagingBackgroundWake(
        for extensionContext: WKWebExtensionContext,
        operation: String
    ) {
        let wakeKey = backgroundWakeKey(for: extensionContext)
        nativeMessagingBackgroundWakeOwner()?.scheduleWake(
            wakeKey: wakeKey,
            operation: operation,
            wake: { [weak self] in
                guard let self else { return }
                _ = try await self.ensureBackgroundAvailableIfRequired(
                    for: extensionContext.webExtension,
                    context: extensionContext,
                    reason: .nativeMessaging
                )
            },
            logFailure: { [weak self] error, operation in
                self?.logBackgroundWakeFailure(
                    error,
                    extensionContext,
                    .nativeMessaging,
                    operation
                )
            }
        )
    }

    private func backgroundWakeKey(
        for extensionContext: WKWebExtensionContext
    ) -> String {
        if let identity = contextIdentity(extensionContext) {
            return ExtensionRuntimeResidencyState.scopedKey(
                extensionId: identity.extensionId,
                profileId: identity.profileId
            )
        }
        return "context:\(ObjectIdentifier(extensionContext))"
    }

    func backgroundRuntimeState(
        for extensionId: String,
        profileId: UUID?
    ) -> ExtensionManager.BackgroundRuntimeState {
        guard let resolvedProfileId = self.resolvedProfileId(profileId) else {
            return .neverLoaded
        }
        let wakeKey = ExtensionRuntimeResidencyState.scopedKey(
            extensionId: extensionId,
            profileId: resolvedProfileId
        )
        return backgroundRuntimeStateOwner.state(for: wakeKey)
    }
}

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    @discardableResult
    func ensureBackgroundAvailableIfRequired(
        for webExtension: WKWebExtension,
        context extensionContext: WKWebExtensionContext,
        reason: ExtensionBackgroundWakeReason
    ) async throws -> Bool {
        try await backgroundWakeCoordinator.ensureBackgroundAvailableIfRequired(
            for: webExtension,
            context: extensionContext,
            reason: reason
        )
    }

    func scheduleNativeMessagingBackgroundWake(
        for extensionContext: WKWebExtensionContext,
        operation: String
    ) {
        backgroundWakeCoordinator.scheduleNativeMessagingBackgroundWake(
            for: extensionContext,
            operation: operation
        )
    }

    func cancelNativeMessagingBackgroundWakeTasks(forExtensionId extensionId: String) {
        loadedNativeMessagingBackgroundWakeOwner?.cancelWakeTasks(
            forExtensionId: extensionId,
            wakeKeyBelongsToExtension: { wakeKey, extensionId in
                ExtensionRuntimeResidencyState.parseScopedKey(wakeKey)?
                    .extensionId == extensionId
            }
        )
    }

    /// Operates on the loaded wake owner directly: this runs during manager
    /// deinit, where instantiating the lazy coordinator would form a weak
    /// reference to a deallocating object.
    func cancelNativeMessagingBackgroundWakeTasks() {
        loadedNativeMessagingBackgroundWakeOwner?.cancelAllWakeTasks()
    }

    func backgroundRuntimeState(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> BackgroundRuntimeState {
        backgroundWakeCoordinator.backgroundRuntimeState(
            for: extensionId,
            profileId: profileId
        )
    }
}
