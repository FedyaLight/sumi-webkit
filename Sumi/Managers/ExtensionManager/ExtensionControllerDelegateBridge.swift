//
//  ExtensionControllerDelegateBridge.swift
//  Sumi
//
//  Receives WKWebExtensionControllerDelegate callbacks and routes each one
//  to the composed owner responsible for that concern, so ExtensionManager
//  does not have to conform to the WebKit delegate protocol itself.
//

import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerDelegateBridge: NSObject, WKWebExtensionControllerDelegate {
    private weak var manager: ExtensionManager?
    private let openingCallbacks = ExtensionControllerOpeningCallbackHandler()
    init(manager: ExtensionManager) {
        self.manager = manager
        super.init()
    }

    func loadedManagerForCallback() -> ExtensionManager? { manager }

    // MARK: - Windows
    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        manager?.windowVisibilityResolver.focusedWindow(for: extensionContext)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        manager?.windowVisibilityResolver.openWindows(for: extensionContext) ?? []
    }

    // MARK: - Actions
    func webExtensionController(
        _ controller: WKWebExtensionController,
        didUpdate action: WKWebExtension.Action,
        forExtensionContext extensionContext: WKWebExtensionContext
    ) {
        manager?.actionSurfacePublisher.updateActionSurfaceState(
            for: action,
            extensionContext: extensionContext
        )
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let manager else {
            completionHandler(
                ExtensionManagerCallbackError.extensionManagerUnavailable.nsError()
            )
            return
        }
        guard let evidence = manager.actionPopupCallbackAdmission.capture(
                  context: extensionContext,
                  controller: controller
              )
        else {
            completionHandler(CancellationError())
            return
        }
        let invocation: ExtensionActionPopupInvocationReceipt?
        switch manager.actionPopupInvocationLedger.claim(
            action: action,
            evidence: evidence
        ) {
        case .claimed(let receipt):
            invocation = receipt
        case .staleBrowserInvocation:
            completionHandler(CancellationError())
            return
        case .unsolicited:
            invocation = nil
        }
        manager.actionPopupCoordinator.present(
            action: action,
            evidence: evidence.attaching(invocation: invocation),
            completionHandler: completionHandler
        )
    }

    // MARK: - Permission Prompts
    // Every permission callback must prove it came from the exact currently
    // bound controller/context pair before any lookup, prompt scheduling or
    // mutation. A failed capture answers fail-closed exactly once.

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        guard let manager,
              let evidence = manager.controllerCallbackAdmission.capture(
                  context: extensionContext,
                  controller: controller
              )
        else {
            completionHandler([], nil)
            return
        }
        manager.permissionCallbackSettlement.promptForPermissions(
            permissions,
            in: tab,
            evidence: evidence,
            manager: manager,
            completionHandler: completionHandler
        )
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        guard let manager,
              let evidence = manager.controllerCallbackAdmission.capture(
                  context: extensionContext,
                  controller: controller
              )
        else {
            completionHandler([], nil)
            return
        }
        manager.permissionCallbackSettlement.promptForPermissionMatchPatterns(
            matchPatterns,
            in: tab,
            evidence: evidence,
            manager: manager,
            completionHandler: completionHandler
        )
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        guard let manager,
              let evidence = manager.controllerCallbackAdmission.capture(
                  context: extensionContext,
                  controller: controller
              )
        else {
            completionHandler([], nil)
            return
        }
        manager.urlPermissionCallbackSettlement.promptForPermissionToAccess(
            urls,
            in: tab,
            evidence: evidence,
            manager: manager,
            completionHandler: completionHandler
        )
    }

    // MARK: - Tabs & Windows Opening
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        guard let manager,
              let invocation = ExtensionControllerOpeningCallbackComposition
                  .invocation(
                      from: manager,
                      context: extensionContext,
                      controller: controller
                  )
        else {
            completionHandler(
                nil,
                CancellationError()
            )
            return
        }
        openingCallbacks.openNewTab(
            configuration: configuration,
            evidence: invocation.evidence,
            runtime: invocation.runtime.tabOpeningCallback,
            completionHandler: completionHandler
        )
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        let request = ExtensionWindowOpeningRequest(
            configuration: configuration
        )
        guard let manager,
              let invocation = ExtensionControllerOpeningCallbackComposition
                  .invocation(
                      from: manager,
                      context: extensionContext,
                      controller: controller
                  )
        else {
            completionHandler(
                nil,
                CancellationError()
            )
            return
        }
        openingCallbacks.openNewWindow(
            request: request,
            evidence: invocation.evidence,
            runtime: invocation.runtime,
            completionHandler: completionHandler
        )
    }

    // MARK: - Native Messaging
    // Both native-messaging callbacks must prove exact controller/context
    // authority before any counter, diagnostic, wake scheduling, relay
    // materialization or port registration. A failed capture answers
    // fail-closed exactly once and creates nothing.

    func webExtensionController(
        _ controller: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        guard let manager,
              let evidence = manager.controllerCallbackAdmission.capture(
                  context: extensionContext,
                  controller: controller
              )
        else {
            replyHandler(
                nil,
                SumiNativeMessagingErrorMapper.relayError(
                    code: .extensionContextMissing,
                    diagnostic: nil
                )
            )
            return
        }
        manager.nativeMessageSendSettlement.sendMessage(
            message,
            toApplicationWithIdentifier: applicationIdentifier,
            evidence: evidence,
            manager: manager,
            replyHandler: replyHandler
        )
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        connectUsing port: WKWebExtension.MessagePort,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let manager,
              let evidence = manager.controllerCallbackAdmission.capture(
                  context: extensionContext,
                  controller: controller
              )
        else {
            port.disconnect()
            completionHandler(
                SumiNativeMessagingErrorMapper.relayError(
                    code: .extensionContextMissing,
                    diagnostic: nil
                )
            )
            return
        }
        manager.nativePortConnectionSettlement.connect(
            using: port,
            evidence: evidence,
            manager: manager,
            completionHandler: completionHandler
        )
    }
}
