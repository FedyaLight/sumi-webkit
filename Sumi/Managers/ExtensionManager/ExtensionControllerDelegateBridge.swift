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
        manager?.windowFocusResolutionOwner.focusedWindow(for: extensionContext)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        manager?.windowFocusResolutionOwner.openWindows(for: extensionContext) ?? []
    }

    // MARK: - Actions

    func webExtensionController(
        _ controller: WKWebExtensionController,
        didUpdate action: WKWebExtension.Action,
        forExtensionContext extensionContext: WKWebExtensionContext
    ) {
        manager?.updateActionSurfaceState(
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

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        guard let manager else {
            completionHandler([], nil)
            return
        }
        manager.permissionDelegateCallbackOwner.promptForPermissions(
            permissions,
            in: tab,
            for: extensionContext,
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
        guard let manager else {
            completionHandler([], nil)
            return
        }
        manager.permissionDelegateCallbackOwner.promptForPermissionMatchPatterns(
            matchPatterns,
            in: tab,
            for: extensionContext,
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
        guard let manager else {
            completionHandler([], nil)
            return
        }
        manager.permissionDelegateCallbackOwner.promptForPermissionToAccess(
            urls,
            in: tab,
            for: extensionContext,
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
                try await manager.prepareExtensionRequestedTabForInitialLoad(
                    url: configuration.url,
                    requestedWindow: configuration.window,
                    controller: controller,
                    extensionContext: extensionContext
                )
                let newTab = try manager.openExtensionRequestedTab(
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
                      let browserContext = manager.browserBridgeContext else {
                    completionHandler(
                        nil,
                        ExtensionManagerCallbackError.browserManagerUnavailable.nsError()
                    )
                    return
                }

                let parentWindow = browserContext.activeExtensionWindowState?.window
                let adapter = await browserContext.presentExtensionPopupWindow(
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
            createWindow: { [weak manager] in
                manager?.browserBridgeContext?.createExtensionWindow()
            },
            awaitWindowRegistration: { [weak manager] existingWindowIDs in
                await manager?.browserBridgeContext?.awaitNextExtensionWindow(
                    excluding: existingWindowIDs
                )
            },
            completionHandler: completionHandler
        )
    }

    // MARK: - Native Messaging

    func webExtensionController(
        _ controller: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        guard let manager else {
            replyHandler(
                nil,
                ExtensionManagerCallbackError.extensionManagerUnavailable.nsError()
            )
            return
        }
        manager.nativeMessagingRoutingOwner.sendMessage(
            message,
            toApplicationWithIdentifier: applicationIdentifier,
            for: extensionContext,
            controller: controller,
            replyHandler: replyHandler
        )
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        connectUsing port: WKWebExtension.MessagePort,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let manager else {
            completionHandler(
                ExtensionManagerCallbackError.extensionManagerUnavailable.nsError()
            )
            return
        }
        manager.nativeMessagingRoutingOwner.connect(
            using: port,
            for: extensionContext,
            controller: controller,
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
        manager.presentOptionsPageWindow(
            for: extensionContext,
            completionHandler: completionHandler
        )
    }
}
