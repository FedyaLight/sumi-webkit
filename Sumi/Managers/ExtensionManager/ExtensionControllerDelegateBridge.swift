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

/// The browser-bound half of WebKit delegate routing. It is assembled in full
/// and installed exactly once when the extension runtime attaches to a browser.
@available(macOS 15.5, *)
@MainActor
struct ExtensionControllerDelegateBrowserRoutes {
    let actionSurfaces: ExtensionActionSurfacePublisher
    let actionPopupCallbackAdmission: ExtensionActionPopupCallbackAdmission
    let actionPopupInvocationLedger: ExtensionActionPopupInvocationLedger
    let actionPopupCoordinator: ExtensionActionPopupCoordinator
    let windows: ExtensionWindowVisibilityResolver
    let opening: ExtensionControllerOpeningCallbackRuntime
    let optionsComposer: ExtensionOptionsWindowCallbackComposer
    let optionsWindows: ExtensionOptionsWindowService
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerDelegateBridge: NSObject, WKWebExtensionControllerDelegate {
    struct RoutesReceipt: Equatable {
        fileprivate let identity: ObjectIdentifier
    }

    private struct CoreRoutes {
        let callbackAdmission: ExtensionControllerCallbackAdmission
        let permissions: ExtensionPermissionCallbackSettlement
        let urlPermissions: ExtensionURLPermissionCallbackSettlement
        let nativeMessages: ExtensionNativeMessageSendSettlement
        let nativePorts: ExtensionNativePortConnectionSettlement
    }

    private let coreRoutes: CoreRoutes
    private let openingCallbacks = ExtensionControllerOpeningCallbackHandler()
    private var browserRoutes: ExtensionControllerDelegateBrowserRoutes?

    func optionsInvocation(
        context: WKWebExtensionContext,
        controller: WKWebExtensionController
    ) -> (
        ExtensionOptionsWindowCallbackComposition.Invocation,
        ExtensionOptionsWindowService
    )? {
        guard let routes = browserRoutes,
              let evidence = coreRoutes.callbackAdmission.capture(
                  context: context,
                  controller: controller
              ),
              let invocation = routes.optionsComposer.invocation(
                  evidence: evidence
              )
        else {
            return nil
        }
        return (invocation, routes.optionsWindows)
    }

    init(
        callbackAdmission: ExtensionControllerCallbackAdmission,
        permissions: ExtensionPermissionCallbackSettlement,
        urlPermissions: ExtensionURLPermissionCallbackSettlement,
        nativeMessages: ExtensionNativeMessageSendSettlement,
        nativePorts: ExtensionNativePortConnectionSettlement
    ) {
        coreRoutes = CoreRoutes(
            callbackAdmission: callbackAdmission,
            permissions: permissions,
            urlPermissions: urlPermissions,
            nativeMessages: nativeMessages,
            nativePorts: nativePorts
        )
        super.init()
    }

    @discardableResult
    func installBrowserRoutes(
        _ routes: ExtensionControllerDelegateBrowserRoutes
    ) -> RoutesReceipt? {
        guard browserRoutes == nil else { return nil }
        browserRoutes = routes
        return RoutesReceipt(identity: ObjectIdentifier(self))
    }

    func retireBrowserRoutes() {
        browserRoutes = nil
    }

    // MARK: - Windows
    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        browserRoutes?.windows.focusedWindow(for: extensionContext)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        browserRoutes?.windows.openWindows(for: extensionContext) ?? []
    }

    // MARK: - Actions
    func webExtensionController(
        _ controller: WKWebExtensionController,
        didUpdate action: WKWebExtension.Action,
        forExtensionContext extensionContext: WKWebExtensionContext
    ) {
        browserRoutes?.actionSurfaces.updateActionSurfaceState(
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
        guard let routes = browserRoutes else {
            completionHandler(
                ExtensionManagerCallbackError.extensionManagerUnavailable.nsError()
            )
            return
        }
        guard let evidence = routes.actionPopupCallbackAdmission.capture(
                  context: extensionContext,
                  controller: controller
              )
        else {
            completionHandler(CancellationError())
            return
        }
        let invocation: ExtensionActionPopupInvocationReceipt?
        switch routes.actionPopupInvocationLedger.claim(
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
        routes.actionPopupCoordinator.present(
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
        guard let evidence = coreRoutes.callbackAdmission.capture(
                  context: extensionContext,
                  controller: controller
              )
        else {
            completionHandler([], nil)
            return
        }
        coreRoutes.permissions.promptForPermissions(
            permissions,
            in: tab,
            evidence: evidence,
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
        guard let evidence = coreRoutes.callbackAdmission.capture(
                  context: extensionContext,
                  controller: controller
              )
        else {
            completionHandler([], nil)
            return
        }
        coreRoutes.permissions.promptForPermissionMatchPatterns(
            matchPatterns,
            in: tab,
            evidence: evidence,
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
        guard let evidence = coreRoutes.callbackAdmission.capture(
                  context: extensionContext,
                  controller: controller
              )
        else {
            completionHandler([], nil)
            return
        }
        coreRoutes.urlPermissions.promptForPermissionToAccess(
            urls,
            in: tab,
            evidence: evidence,
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
        guard let routes = browserRoutes,
              let evidence = coreRoutes.callbackAdmission.capture(
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
            evidence: evidence,
            runtime: routes.opening.tabOpeningCallback,
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
        guard let routes = browserRoutes,
              let evidence = coreRoutes.callbackAdmission.capture(
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
            evidence: evidence,
            runtime: routes.opening,
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
        guard let evidence = coreRoutes.callbackAdmission.capture(
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
        coreRoutes.nativeMessages.sendMessage(
            message,
            toApplicationWithIdentifier: applicationIdentifier,
            evidence: evidence,
            replyHandler: replyHandler
        )
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        connectUsing port: WKWebExtension.MessagePort,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let evidence = coreRoutes.callbackAdmission.capture(
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
        coreRoutes.nativePorts.connect(
            using: port,
            evidence: evidence,
            completionHandler: completionHandler
        )
    }
}
