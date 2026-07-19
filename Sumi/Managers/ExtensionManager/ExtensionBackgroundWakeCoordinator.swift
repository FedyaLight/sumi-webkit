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
    private let runtimeMetrics: ExtensionRuntimeMetricsAuthority
    private let trace: @MainActor (String) -> Void
    private let logBackgroundWakeFailure: @MainActor (
        Error,
        WKWebExtensionContext,
        ExtensionManager.ExtensionBackgroundWakeReason,
        String
    ) -> Void
    #if DEBUG
        private var debugBackgroundContentWake: (@MainActor ()
            -> (@MainActor (String, WKWebExtensionContext) async throws -> Void)?)?
    #endif

    init(
        backgroundRuntimeStateOwner: ExtensionBackgroundRuntimeStateOwner,
        nativeMessagingBackgroundWakeOwner: @escaping @MainActor () -> ExtensionNativeMessagingBackgroundWakeOwner?,
        contextIdentity: @escaping @MainActor (WKWebExtensionContext) -> (extensionId: String, profileId: UUID)?,
        resolvedProfileId: @escaping @MainActor (UUID?) -> UUID?,
        runtimeMetrics: ExtensionRuntimeMetricsAuthority,
        trace: @escaping @MainActor (String) -> Void,
        logBackgroundWakeFailure: @escaping @MainActor (
            Error,
            WKWebExtensionContext,
            ExtensionManager.ExtensionBackgroundWakeReason,
            String
        ) -> Void
    ) {
        self.backgroundRuntimeStateOwner = backgroundRuntimeStateOwner
        self.nativeMessagingBackgroundWakeOwner = nativeMessagingBackgroundWakeOwner
        self.contextIdentity = contextIdentity
        self.resolvedProfileId = resolvedProfileId
        self.runtimeMetrics = runtimeMetrics
        self.trace = trace
        self.logBackgroundWakeFailure = logBackgroundWakeFailure
    }

    #if DEBUG
        func installDebugBackgroundContentWake(
            _ provider: @escaping @MainActor ()
                -> (@MainActor (String, WKWebExtensionContext) async throws -> Void)?
        ) {
            debugBackgroundContentWake = provider
        }
    #endif

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
            loadBackgroundContent: {
                try await self.loadBackgroundContent(
                    wakeKey: wakeKey,
                    context: extensionContext
                )
            },
            recordWakeMetric: { [runtimeMetrics] duration, reason, didFail in
                runtimeMetrics.recordBackgroundWake(
                    duration: duration,
                    reason: reason,
                    didFail: didFail,
                    for: wakeKey
                )
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
            loadBackgroundContent: {
                guard admission.isCurrent(evidence) else {
                    throw CancellationError()
                }
                try await self.loadBackgroundContent(
                    wakeKey: wakeKey,
                    context: evidence.context
                )
            },
            recordWakeMetric: { [runtimeMetrics] duration, reason, didFail in
                guard admission.isCurrent(evidence) else { return }
                runtimeMetrics.recordBackgroundWake(
                    duration: duration,
                    reason: reason,
                    didFail: didFail,
                    for: wakeKey
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

    private func loadBackgroundContent(
        wakeKey: String,
        context: WKWebExtensionContext
    ) async throws {
        #if DEBUG
            if let backgroundContentWake = debugBackgroundContentWake?() {
                // The injected operation represents the complete background
                // readiness boundary. Reaching into WebKit after it would
                // mix the real runtime with deterministic test ownership.
                try await backgroundContentWake(wakeKey, context)
                return
            }
        #endif

        try await context.loadBackgroundContent()
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
