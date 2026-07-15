import Foundation
import WebKit

/// Settles the WebKit `sendMessage` native-messaging delegate callback
/// against typed callback evidence. Identity comes only from the captured
/// evidence, the background wake is admitted by the same evidence, delayed
/// relay work revalidates before every external effect, and a stale callback
/// answers fail-closed exactly once instead of surfacing a late success.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNativeMessageSendSettlement {
    private let admission: ExtensionControllerCallbackAdmission
    private let relayOwner: @MainActor () -> ExtensionNativeMessagingRelayOwner
    private let backgroundWakes: ExtensionBackgroundWakeCoordinator
    private let profileRuntime: ExtensionProfileRuntime
    private let installedExtensions: InstalledExtensionCollection
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        admission: ExtensionControllerCallbackAdmission,
        relayOwner: @escaping @MainActor () -> ExtensionNativeMessagingRelayOwner,
        backgroundWakes: ExtensionBackgroundWakeCoordinator,
        profileRuntime: ExtensionProfileRuntime,
        installedExtensions: InstalledExtensionCollection,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.admission = admission
        self.relayOwner = relayOwner
        self.backgroundWakes = backgroundWakes
        self.profileRuntime = profileRuntime
        self.installedExtensions = installedExtensions
        self.diagnostics = diagnostics
    }

    func sendMessage(
        _ message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        evidence: ExtensionControllerCallbackEvidence,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        let extensionId = evidence.extensionID
        let profileId = evidence.profileID

        SumiNativeMessagingRuntimeCounters.recordDelegateSendMessageInvoked()
        SafariExtensionAutofillFillDiagnostics.recordNativeMessagingActivity(
            extensionId: extensionId
        )

        let relayOwner = relayOwner()
        if relayOwner.extensionsModuleEnabledForCallbacks {
            backgroundWakes
                .scheduleNativeMessagingBackgroundWake(
                    evidence: evidence,
                    admission: admission,
                    operation: "wake native messaging background before sendMessage"
                )
        }

        let isPrivateBrowsing = profileRuntime.isPrivateRuntimeProfile(profileId)
        let extensionDisplayName = ExtensionDisplayNameResolver.displayName(
            for: extensionId,
            installedExtensions: installedExtensions.records
        )
        diagnostics.traceNativeMessagingContextBinding(
            phase: "delegateSendMessage",
            extensionId: extensionId,
            profileId: profileId,
            loadSource: SafariAppExtensionRuntimeLoadSource.installedSource(
                for: extensionId,
                in: installedExtensions.records
            ),
            webExtension: evidence.context.webExtension,
            extensionContext: evidence.context,
            controller: evidence.controller,
            configuration: evidence.context.webViewConfiguration,
            profileController: profileRuntime.controller(
                for: profileId
            ),
            expectedControllerDelegate: evidence.controller.delegate
        )
        let messageShape = SafariExtensionNativeMessagingRoutingProbe
            .sanitizedMessageShape(for: message)
        #if DEBUG || SUMI_DIAGNOSTICS
            if RuntimeDiagnostics.isVerboseEnabled {
                RuntimeDiagnostics.debug(category: "SafariNativeMessagingRouting") {
                    """
                    WKWebExtensionControllerDelegate.sendMessage \
                    extBucket=\(SafariExtensionNativeMessagingRoutingProbe.extensionIdBucket(extensionId)) \
                    extLabel=\(SafariExtensionNativeMessagingRoutingProbe.sanitizedExtensionLabel(extensionDisplayName)) \
                    profile=\(SafariExtensionNativeMessagingRoutingProbe.profileIdBucket(profileId)) \
                    appId=\(applicationIdentifier ?? "(nil)") \
                    messageShape=\(messageShape.container) \
                    messageKeys=\(messageShape.keysForLog) \
                    messageTypeKeys=\(messageShape.typeKeysForLog)
                    """
                }
            }
        #endif

        relayOwner.relay.handleSendMessage(
            applicationIdentifier: applicationIdentifier,
            message: message,
            extensionId: extensionId,
            profileId: profileId,
            isPrivateBrowsing: isPrivateBrowsing,
            privateAccessAllowed: evidence.context.hasAccessToPrivateData,
            installedExtensions: installedExtensions.records,
            extensionDisplayName: extensionDisplayName,
            executionAdmission: { [admission] in admission.isCurrent(evidence) },
            replyHandler: settledReply(
                evidence: evidence,
                extensionId: extensionId,
                replyHandler
            )
        )
    }

    /// Wraps the WebKit reply in the one-shot diagnostics latch, then settles
    /// each reply against exact current evidence: a stale callback answers
    /// fail-closed instead of forwarding a superseded success value.
    private func settledReply(
        evidence: ExtensionControllerCallbackEvidence,
        extensionId: String,
        _ replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) -> (Any?, (any Error)?) -> Void {
        let onceReply = SumiWebExtensionCallbackRelay.wrapNativeMessagingReplyHandler(
            api: .runtimeSendNativeMessage,
            extensionId: extensionId,
            replyHandler
        )
        return { [admission] value, error in
            guard admission.isCurrent(evidence) else {
                onceReply(
                    nil,
                    SumiNativeMessagingErrorMapper.relayError(
                        code: .extensionContextMissing,
                        diagnostic: nil
                    )
                )
                return
            }
            onceReply(value, error)
        }
    }
}
