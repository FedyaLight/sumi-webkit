//
//  ExtensionNativeMessagingRoutingOwner.swift
//  Sumi
//
//  Owns routing WebKit native-messaging delegate callbacks (one-shot
//  sendMessage and long-lived connect ports) into the Sumi native
//  messaging relay, including background wake and routing diagnostics.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionNativeMessagingRoutingOwner {
    private weak var manager: ExtensionManager?

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    func sendMessage(
        _ message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext,
        controller: WKWebExtensionController,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        guard let manager else {
            replyHandler(
                nil,
                ExtensionManagerCallbackError.extensionManagerUnavailable.nsError()
            )
            return
        }
        let extensionId = manager.extensionID(for: extensionContext)
        let extensionsModuleEnabled = manager.extensionsModuleEnabledForCallbacks

        SumiNativeMessagingRuntimeCounters.recordDelegateSendMessageInvoked()
        SafariExtensionAutofillFillDiagnostics.recordNativeMessagingActivity(
            extensionId: extensionId
        )
        if extensionsModuleEnabled {
            manager.scheduleNativeMessagingBackgroundWake(
                for: extensionContext,
                operation: "wake native messaging background before sendMessage"
            )
        }
        let profileId = manager.profileId(for: extensionContext)
        let isPrivateBrowsing = manager.isPrivateExtensionRuntimeProfile(profileId)
        let extensionDisplayName = ExtensionUtils.displayName(
            forExtensionID: extensionId,
            installedExtensions: manager.installedExtensions
        )
        manager.traceNativeMessagingContextBinding(
            phase: "delegateSendMessage",
            extensionId: extensionId,
            profileId: profileId,
            loadSource: manager.nativeMessagingLoadSource(for: extensionId),
            webExtension: extensionContext.webExtension,
            extensionContext: extensionContext,
            controller: controller,
            configuration: extensionContext.webViewConfiguration
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
        manager.nativeMessagingRelay.handleSendMessage(
            applicationIdentifier: applicationIdentifier,
            message: message,
            extensionId: extensionId,
            profileId: profileId,
            isPrivateBrowsing: isPrivateBrowsing,
            privateAccessAllowed: extensionContext.hasAccessToPrivateData,
            installedExtensions: manager.installedExtensions,
            extensionDisplayName: extensionDisplayName,
            replyHandler: SumiWebExtensionCallbackRelay.wrapNativeMessagingReplyHandler(
                api: .runtimeSendNativeMessage,
                extensionId: extensionId,
                replyHandler
            )
        )
    }

    func connect(
        using port: WKWebExtension.MessagePort,
        for extensionContext: WKWebExtensionContext,
        controller: WKWebExtensionController,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let manager else {
            completionHandler(
                ExtensionManagerCallbackError.extensionManagerUnavailable.nsError()
            )
            return
        }
        SumiNativeMessagingRuntimeCounters.recordDelegateConnectInvoked()
        let extensionId = manager.extensionID(for: extensionContext)
        SafariExtensionAutofillFillDiagnostics.recordNativeMessagingActivity(
            extensionId: extensionId
        )
        let extensionsModuleEnabled = manager.extensionsModuleEnabledForCallbacks
        if extensionsModuleEnabled {
            manager.scheduleNativeMessagingBackgroundWake(
                for: extensionContext,
                operation: "wake native messaging background before connect"
            )
        }

        let profileId = manager.profileId(for: extensionContext)
        let isPrivateBrowsing = manager.isPrivateExtensionRuntimeProfile(profileId)
        let extensionDisplayName = ExtensionUtils.displayName(
            forExtensionID: extensionId,
            installedExtensions: manager.installedExtensions
        )
        manager.traceNativeMessagingContextBinding(
            phase: "delegateConnectNative",
            extensionId: extensionId,
            profileId: profileId,
            loadSource: manager.nativeMessagingLoadSource(for: extensionId),
            webExtension: extensionContext.webExtension,
            extensionContext: extensionContext,
            controller: controller,
            configuration: extensionContext.webViewConfiguration
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

        let portKey = ObjectIdentifier(port)
        _ = manager.nativeMessagingRelay.handleConnect(
            port: port,
            extensionId: extensionId,
            profileId: profileId,
            isPrivateBrowsing: isPrivateBrowsing,
            privateAccessAllowed: extensionContext.hasAccessToPrivateData,
            installedExtensions: manager.installedExtensions,
            registerHandler: { [weak manager] handler in
                manager?.nativeMessagingPortRegistry.register(
                    handler: handler,
                    portKey: portKey,
                    extensionId: extensionId,
                    profileId: profileId
                )
            },
            unregisterHandler: { [weak manager] handler in
                manager?.nativeMessagingPortRegistry.unregister(
                    handler: handler,
                    portKey: portKey
                )
            },
            completionHandler: SumiWebExtensionCallbackRelay.wrapCompletionHandler(
                api: .connectNativePort,
                extensionId: extensionId,
                completionHandler
            )
        )
    }
}
