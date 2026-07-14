import Foundation
import WebKit

/// Settles the WebKit `connectUsing` native-messaging delegate callback
/// against typed callback evidence. The registry claim is admitted by exact
/// current evidence before any external connect effect, carries a claim
/// token so a stale finalizer can never remove a newer session, and a stale
/// completion answers fail-closed exactly once without leaving a handler.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNativePortConnectionSettlement {
    /// One registration claim per connect callback; the token exists only
    /// after the registry admitted the exact current evidence.
    private final class PortRegistrationClaim {
        var claimToken: UInt64?
    }

    private let admission: ExtensionControllerCallbackAdmission

    init(admission: ExtensionControllerCallbackAdmission) {
        self.admission = admission
    }

    func connect(
        using port: any SumiNativeMessagingPortControlling,
        evidence: ExtensionControllerCallbackEvidence,
        manager: ExtensionManager,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        let extensionId = evidence.extensionID
        let profileId = evidence.profileID
        let registry = manager.nativeMessagingPortRegistry

        // A physical WebKit message port represents one live connection.
        // Reject a duplicate callback before a new session can overwrite the
        // existing port handlers or later disconnect the existing session.
        guard registry.registeredHandler(for: port) == nil else {
            settledCompletion(
                evidence: evidence,
                extensionId: extensionId,
                completionHandler
            )(
                SumiNativeMessagingErrorMapper.relayError(
                    code: .relayCancelled,
                    diagnostic: nil
                )
            )
            return
        }

        SumiNativeMessagingRuntimeCounters.recordDelegateConnectInvoked()
        SafariExtensionAutofillFillDiagnostics.recordNativeMessagingActivity(
            extensionId: extensionId
        )

        if manager.nativeMessagingRelayOwner.extensionsModuleEnabledForCallbacks {
            manager.backgroundWakeCoordinator
                .scheduleNativeMessagingBackgroundWake(
                    evidence: evidence,
                    admission: admission,
                    operation: "wake native messaging background before connect"
                )
        }

        let extensionDisplayName = ExtensionDisplayNameResolver.displayName(
            for: extensionId,
            installedExtensions: manager.installedExtensionCollection.records
        )
        manager.runtimeDiagnostics.traceNativeMessagingContextBinding(
            phase: "delegateConnectNative",
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
        #if DEBUG || SUMI_DIAGNOSTICS
            if RuntimeDiagnostics.isVerboseEnabled {
                RuntimeDiagnostics.debug(category: "SafariNativeMessagingRouting") {
                    """
                    WKWebExtensionControllerDelegate.connectUsing \
                    extBucket=\(SafariExtensionNativeMessagingRoutingProbe.extensionIdBucket(extensionId)) \
                    extLabel=\(SafariExtensionNativeMessagingRoutingProbe.sanitizedExtensionLabel(extensionDisplayName)) \
                    profile=\(SafariExtensionNativeMessagingRoutingProbe.profileIdBucket(profileId)) \
                    appId=\(port.applicationIdentifier ?? "(nil)")
                    """
                }
            }
        #endif

        let claim = PortRegistrationClaim()
        _ = manager.nativeMessagingRelayOwner.relay.handleConnect(
            port: port,
            extensionId: extensionId,
            profileId: profileId,
            isPrivateBrowsing: manager.isPrivateExtensionRuntimeProfile(profileId),
            privateAccessAllowed: evidence.context.hasAccessToPrivateData,
            installedExtensions: manager.installedExtensionCollection.records,
            registerHandler: { [admission] session in
                guard admission.isCurrent(evidence) else { return false }
                guard let claimToken = registry.register(
                    handler: session,
                    port: port,
                    extensionId: extensionId,
                    profileId: profileId
                ) else {
                    return false
                }
                claim.claimToken = claimToken
                return true
            },
            unregisterHandler: { [weak registry] session in
                guard let registry, let claimToken = claim.claimToken else {
                    return
                }
                registry.unregister(
                    handler: session,
                    port: port,
                    claimToken: claimToken
                )
            },
            executionAdmission: { [admission] in admission.isCurrent(evidence) },
            completionHandler: settledCompletion(
                evidence: evidence,
                extensionId: extensionId,
                completionHandler
            )
        )
    }

    /// Wraps the WebKit completion in the one-shot diagnostics latch, then
    /// settles it against exact current evidence: a stale callback answers
    /// fail-closed instead of forwarding a superseded connect success.
    private func settledCompletion(
        evidence: ExtensionControllerCallbackEvidence,
        extensionId: String,
        _ completionHandler: @escaping ((any Error)?) -> Void
    ) -> ((any Error)?) -> Void {
        let onceCompletion = SumiWebExtensionCallbackRelay.wrapCompletionHandler(
            api: .connectNativePort,
            extensionId: extensionId,
            completionHandler
        )
        return { [admission] error in
            guard admission.isCurrent(evidence) else {
                onceCompletion(
                    SumiNativeMessagingErrorMapper.relayError(
                        code: .extensionContextMissing,
                        diagnostic: nil
                    )
                )
                return
            }
            onceCompletion(error)
        }
    }
}
