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

    init(manager: ExtensionManager) {
        self.manager = manager
        super.init()
    }

    // MARK: - Windows

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        manager?.runtimeBundle.windowFocusResolutionOwner.focusedWindow(for: extensionContext)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        manager?.runtimeBundle.windowFocusResolutionOwner.openWindows(for: extensionContext) ?? []
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
        manager.actionPopupSessionOwner.presentActionPopup(
            action,
            for: extensionContext,
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
        Task { @MainActor [weak self] in
            guard let manager = self?.manager else {
                completionHandler(
                    nil,
                    ExtensionManagerCallbackError.extensionManagerUnavailable.nsError()
                )
                return
            }

            do {
                try await manager.requestedTabContextPreloader.prepare(
                    url: configuration.url,
                    requestedWindow: configuration.window,
                    controller: controller,
                    extensionContext: extensionContext
                )
                let newTab = try manager.requestedTabOpening.open(
                    url: configuration.url,
                    shouldBeActive: configuration.shouldBeActive,
                    shouldBePinned: configuration.shouldBePinned,
                    requestedWindow: configuration.window,
                    controller: controller,
                    extensionContext: extensionContext,
                    reason: "webExtensionController.openNewTabUsing"
                )
                completionHandler(manager.adapterResolutionOwner.stableAdapter(for: newTab), nil)
            } catch {
                completionHandler(
                    nil,
                    SumiWebExtensionCallbackErrorMapper.webExtensionCallbackError(from: error)
                )
            }
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        guard let manager else {
            completionHandler(
                nil,
                ExtensionManagerCallbackError.extensionManagerUnavailable.nsError()
            )
            return
        }
        guard configuration.shouldBePrivate == false else {
            completionHandler(
                nil,
                ExtensionManagerCallbackError.privateWindowsUnsupported.nsError()
            )
            return
        }

        if configuration.windowType == .popup {
            Task { @MainActor [weak self] in
                guard let manager = self?.manager,
                      let windowQuery = manager.extensionWindowQuery,
                      let windowPresentation = manager.extensionWindowPresentation
                else {
                    completionHandler(
                        nil,
                        ExtensionManagerCallbackError.browserManagerUnavailable.nsError()
                    )
                    return
                }

                let parentWindow = windowQuery.activeExtensionWindowState.flatMap {
                    windowQuery.appKitWindow(for: $0)
                }
                let adapter = await windowPresentation.presentExtensionPopupWindow(
                    configuration: configuration,
                    controller: controller,
                    extensionContext: extensionContext,
                    extensionManager: manager,
                    parentWindow: parentWindow
                )

                if let adapter {
                    completionHandler(adapter, nil)
                } else {
                    completionHandler(
                        nil,
                        ExtensionManagerCallbackError.extensionPopupWindowUnavailable.nsError()
                    )
                }
            }
            return
        }

        manager.openExtensionWindowUsingTabURLs(
            configuration.tabURLs,
            controller: controller,
            extensionContext: extensionContext,
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

    // MARK: - Options Page

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let manager else {
            completionHandler(
                ExtensionManagerCallbackError.extensionManagerUnavailable.nsError()
            )
            return
        }
        manager.optionsWindows.presentOptionsPageWindow(
            for: extensionContext,
            manager: manager,
            completionHandler: completionHandler
        )
    }
}
