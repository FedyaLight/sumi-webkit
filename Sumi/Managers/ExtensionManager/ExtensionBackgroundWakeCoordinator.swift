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
        reason: ExtensionManager.ExtensionBackgroundWakeReason,
        isCurrent: @escaping @MainActor () -> Bool = { true }
    ) async throws -> Bool {
        let wakeKey = backgroundWakeKey(for: extensionContext)
        return try await backgroundRuntimeStateOwner.ensureBackgroundAvailableIfRequired(
            wakeKey: wakeKey,
            hasBackgroundContent: webExtension.hasBackgroundContent,
            reason: reason,
            trace: { [trace] in trace($0) },
            isCurrent: isCurrent,
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

    /// Schedules a native-messaging background wake admitted by exact typed
    /// callback evidence. The wake key derives only from the captured
    /// extension/profile identity — never from mutable context identity —
    /// and the evidence is revalidated when the scheduled task actually
    /// starts and again immediately before the background load effect.
    func scheduleNativeMessagingBackgroundWake(
        evidence: ExtensionControllerCallbackEvidence,
        admission: ExtensionControllerCallbackAdmission,
        operation: String
    ) {
        let wakeKey = ExtensionRuntimeResidencyState.scopedKey(
            extensionId: evidence.extensionID,
            profileId: evidence.profileID
        )
        nativeMessagingBackgroundWakeOwner()?.scheduleWake(
            wakeKey: wakeKey,
            operation: operation,
            isCurrent: { admission.isCurrent(evidence) },
            wake: { [weak self] in
                guard let self else { return }
                guard admission.isCurrent(evidence) else { return }
                _ = try await self.ensureCallbackAdmittedBackgroundAvailable(
                    wakeKey: wakeKey,
                    evidence: evidence,
                    admission: admission
                )
            },
            logFailure: { [weak self] error, operation in
                self?.logBackgroundWakeFailure(
                    error,
                    evidence.context,
                    .nativeMessaging,
                    operation
                )
            }
        )
    }

    /// Runs the background-wake state machine for one callback-admitted wake.
    /// The load closure revalidates the evidence right before the external
    /// load effect, so a context replaced after the wake task started fails
    /// closed instead of loading a superseded runtime generation.
    private func ensureCallbackAdmittedBackgroundAvailable(
        wakeKey: String,
        evidence: ExtensionControllerCallbackEvidence,
        admission: ExtensionControllerCallbackAdmission
    ) async throws -> Bool {
        try await backgroundRuntimeStateOwner.ensureBackgroundAvailableIfRequired(
            wakeKey: wakeKey,
            hasBackgroundContent: evidence.context.webExtension.hasBackgroundContent,
            reason: .nativeMessaging,
            trace: { [trace] in trace($0) },
            isCurrent: { admission.isCurrent(evidence) },
            loadBackgroundContent: { [debugBackgroundContentWake] in
                guard admission.isCurrent(evidence) else {
                    throw CancellationError()
                }
                if let backgroundContentWake = debugBackgroundContentWake() {
                    try await backgroundContentWake(wakeKey, evidence.context)
                } else {
                    try await evidence.context.loadBackgroundContent()
                }
            },
            recordWakeMetric: { [recordRuntimeMetric] duration, reason, didFail in
                guard admission.isCurrent(evidence) else { return }
                recordRuntimeMetric(wakeKey) {
                    $0.backgroundWakeDuration = duration
                    $0.backgroundWakeCount += 1
                    $0.lastBackgroundWakeReason = reason
                    $0.lastBackgroundWakeFailed = didFail
                }
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

@available(macOS 15.5, *)
extension ExtensionBackgroundWakeCoordinator {
    convenience init(manager: ExtensionManager) {
        self.init(
            backgroundRuntimeStateOwner: manager.backgroundRuntimeStateOwner,
            nativeMessagingBackgroundWakeOwner: { [weak manager] in
                manager?.nativeMessagingBackgroundWakeOwner
            },
            contextIdentity: { [weak manager] context in
                manager?.contextIdentity(for: context)
            },
            resolvedProfileId: { [weak manager] profileID in
                manager?.resolvedProfileId(explicitProfileId: profileID)
            },
            recordRuntimeMetric: { [weak manager] extensionID, update in
                manager?.runtimeSession.recordRuntimeMetric(
                    for: extensionID,
                    update: update
                )
            },
            trace: { [weak manager] message in
                manager?.runtimeDiagnostics.trace(message)
            },
            logBackgroundWakeFailure: {
                [weak manager] error, context, reason, operation in
                manager?.logBackgroundWakeFailure(
                    error,
                    extensionContext: context,
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
        reason: ExtensionBackgroundWakeReason,
        isCurrent: @escaping @MainActor () -> Bool = { true }
    ) async throws -> Bool {
        try await backgroundWakeCoordinator.ensureBackgroundAvailableIfRequired(
            for: webExtension,
            context: extensionContext,
            reason: reason,
            isCurrent: isCurrent
        )
    }

    func cancelNativeMessagingBackgroundWakeTasks(forExtensionId extensionId: String) {
        loadedNativeMessagingBackgroundWakeOwner?.cancelWakeTasks(
            forExtensionId: extensionId
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
