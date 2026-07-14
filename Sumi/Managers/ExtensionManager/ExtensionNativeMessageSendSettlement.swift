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

    init(admission: ExtensionControllerCallbackAdmission) {
        self.admission = admission
    }

    func sendMessage(
        _ message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        evidence: ExtensionControllerCallbackEvidence,
        manager: ExtensionManager,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        let extensionId = evidence.extensionID
        let profileId = evidence.profileID

        SumiNativeMessagingRuntimeCounters.recordDelegateSendMessageInvoked()
        SafariExtensionAutofillFillDiagnostics.recordNativeMessagingActivity(
            extensionId: extensionId
        )

        if manager.nativeMessagingRelayOwner.extensionsModuleEnabledForCallbacks {
            manager.backgroundWakeCoordinator
                .scheduleNativeMessagingBackgroundWake(
                    evidence: evidence,
                    admission: admission,
                    operation: "wake native messaging background before sendMessage"
                )
        }

        let isPrivateBrowsing = manager.isPrivateExtensionRuntimeProfile(profileId)
        let extensionDisplayName = ExtensionDisplayNameResolver.displayName(
            for: extensionId,
            installedExtensions: manager.installedExtensionCollection.records
        )
        manager.runtimeDiagnostics.traceNativeMessagingContextBinding(
            phase: "delegateSendMessage",
            extensionId: extensionId,
            profileId: profileId,
            loadSource: SafariAppExtensionRuntimeLoadSource.installedSource(
                for: extensionId,
                in: manager.installedExtensionCollection.records
            ),
            webExtension: evidence.context.webExtension,
            extensionContext: evidence.context,
            controller: evidence.controller,
            configuration: evidence.context.webViewConfiguration,
            profileController: manager.profileRuntime.controller(
                for: profileId
            ),
            expectedControllerDelegate: manager.controllerDelegateBridge
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

        manager.nativeMessagingRelayOwner.relay.handleSendMessage(
            applicationIdentifier: applicationIdentifier,
            message: message,
            extensionId: extensionId,
            profileId: profileId,
            isPrivateBrowsing: isPrivateBrowsing,
            privateAccessAllowed: evidence.context.hasAccessToPrivateData,
            installedExtensions: manager.installedExtensionCollection.records,
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
