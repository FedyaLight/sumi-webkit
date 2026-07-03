import Foundation
import WebKit

/// Coordinates background-content wakes for extension contexts: resolves the
/// scoped wake key, drives the background runtime state machine, and schedules
/// native-messaging wakes with failure logging.
@available(macOS 15.5, *)
@MainActor
final class ExtensionBackgroundWakeCoordinator {
    struct Dependencies {
        let backgroundRuntimeStateOwner: ExtensionBackgroundRuntimeStateOwner
        let nativeMessagingBackgroundWakeOwner: @MainActor () -> ExtensionNativeMessagingBackgroundWakeOwner?
        let contextIdentity: @MainActor (WKWebExtensionContext) -> (extensionId: String, profileId: UUID)?
        let resolvedProfileId: @MainActor (UUID?) -> UUID?
        let recordRuntimeMetric: @MainActor (String, (inout ExtensionManager.ExtensionRuntimeMetrics) -> Void) -> Void
        let trace: @MainActor (String) -> Void
        let logBackgroundWakeFailure: @MainActor (
            Error,
            WKWebExtensionContext,
            ExtensionManager.ExtensionBackgroundWakeReason,
            String
        ) -> Void
        /// Debug-only wake override; returns nil in release builds.
        let debugBackgroundContentWake: @MainActor ()
            -> (@MainActor (String, WKWebExtensionContext) async throws -> Void)?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func ensureBackgroundAvailableIfRequired(
        for webExtension: WKWebExtension,
        context extensionContext: WKWebExtensionContext,
        reason: ExtensionManager.ExtensionBackgroundWakeReason
    ) async throws -> Bool {
        let wakeKey = backgroundWakeKey(for: extensionContext)
        let dependencies = dependencies
        return try await dependencies.backgroundRuntimeStateOwner.ensureBackgroundAvailableIfRequired(
            wakeKey: wakeKey,
            hasBackgroundContent: webExtension.hasBackgroundContent,
            reason: reason,
            trace: { dependencies.trace($0) },
            loadBackgroundContent: {
                if let backgroundContentWake = dependencies.debugBackgroundContentWake() {
                    try await backgroundContentWake(wakeKey, extensionContext)
                } else {
                    try await extensionContext.loadBackgroundContent()
                }
            },
            recordWakeMetric: { duration, reason, didFail in
                dependencies.recordRuntimeMetric(wakeKey) {
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
        dependencies.nativeMessagingBackgroundWakeOwner()?.scheduleWake(
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
                self?.dependencies.logBackgroundWakeFailure(
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
        if let identity = dependencies.contextIdentity(extensionContext) {
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
        let resolvedProfileId = dependencies.resolvedProfileId(profileId)
        guard let resolvedProfileId else { return .neverLoaded }
        let wakeKey = ExtensionRuntimeResidencyState.scopedKey(
            extensionId: extensionId,
            profileId: resolvedProfileId
        )
        return dependencies.backgroundRuntimeStateOwner.state(for: wakeKey)
    }
}

@available(macOS 15.5, *)
extension ExtensionBackgroundWakeCoordinator.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            backgroundRuntimeStateOwner: manager.backgroundRuntimeStateOwner,
            nativeMessagingBackgroundWakeOwner: { [weak manager] in
                manager?.nativeMessagingBackgroundWakeOwner
            },
            contextIdentity: { [weak manager] extensionContext in
                manager?.contextIdentity(for: extensionContext)
            },
            resolvedProfileId: { [weak manager] explicitProfileId in
                manager?.resolvedProfileId(explicitProfileId: explicitProfileId)
            },
            recordRuntimeMetric: { [weak manager] extensionId, update in
                manager?.runtimeSessionOwner.recordRuntimeMetric(for: extensionId, update: update)
            },
            trace: { [weak manager] message in
                manager?.extensionRuntimeTrace(message)
            },
            logBackgroundWakeFailure: { [weak manager] error, extensionContext, reason, operation in
                manager?.logBackgroundWakeFailure(
                    error,
                    extensionContext: extensionContext,
                    reason: reason,
                    operation: operation
                )
            },
            debugBackgroundContentWake: { [weak manager] in
                #if DEBUG
                    manager?.testHooks.backgroundContentWake
                #else
                    nil
                #endif
            }
        )
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
