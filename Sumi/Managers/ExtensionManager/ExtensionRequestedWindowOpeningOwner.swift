//
//  ExtensionRequestedWindowOpeningOwner.swift
//  Sumi
//
//  Owns extension-requested browser window opening: reusing the active window
//  for external web popups, awaiting new window registration, and seeding the
//  first tab with the extension-provided URLs.
//

import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedWindowOpeningOwner {
    struct Dependencies {
        let browserBridgeContext: @MainActor () -> (any ExtensionBrowserBridgeContext)?
        let profileIdForContext: @MainActor (WKWebExtensionContext) -> UUID?
        let windowMatchesProfile: @MainActor (BrowserWindowState, UUID) -> Bool
        let extensionLoadURL:
            @MainActor (URL?, WKWebExtensionController) -> (url: URL?, context: WKWebExtensionContext?)
        let prepareContentScriptContextsForInitialLoad:
            @MainActor (URL?, WKWebExtensionContext?, BrowserWindowState?, Space?, WKWebExtensionController) async -> Void
        let openExtensionRequestedTab:
            @MainActor (URL?, Bool, Bool, (any WKWebExtensionWindow)?, WKWebExtensionController, WKWebExtensionContext?, String) throws -> Tab
        let windowAdapter: @MainActor (UUID) -> ExtensionWindowAdapter?
        let materializeNormalTabIfNeeded: @MainActor (Tab, Bool, BrowserWindowState?) -> Void
        let registerCreatedTabWithExtensionRuntime: @MainActor (Tab, String) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func openExtensionWindowUsingTabURLs(
        _ tabURLs: [URL],
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
        createWindow: @escaping @MainActor () -> Void,
        awaitWindowRegistration: @escaping @MainActor (Set<UUID>) async -> BrowserWindowState?,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        guard let browserContext = dependencies.browserBridgeContext() else {
            completionHandler(
                nil,
                ExtensionManagerCallbackError.browserManagerUnavailable.nsError()
            )
            return
        }

        if let extensionContext,
           let firstURL = tabURLs.first,
           ExtensionActionPopupPresentationOwner.isExtensionExternalWebPopupURL(firstURL),
           let contextProfileId = dependencies.profileIdForContext(extensionContext),
           let activeWindow = browserContext.activeExtensionWindowState,
           dependencies.windowMatchesProfile(activeWindow, contextProfileId) {
            Task { @MainActor [weak self] in
                guard let self,
                      let browserContext = dependencies.browserBridgeContext() else {
                    completionHandler(
                        nil,
                        ExtensionManagerCallbackError.browserManagerUnavailable.nsError()
                    )
                    return
                }
                let targetSpace = browserContext.extensionTargetSpace(for: activeWindow)

                let resolvedExtensionLoad = dependencies.extensionLoadURL(
                    firstURL,
                    controller
                )
                await dependencies.prepareContentScriptContextsForInitialLoad(
                    resolvedExtensionLoad.url,
                    resolvedExtensionLoad.context,
                    activeWindow,
                    targetSpace,
                    controller
                )
                do {
                    _ = try dependencies.openExtensionRequestedTab(
                        firstURL,
                        true,
                        false,
                        dependencies.windowAdapter(activeWindow.id),
                        controller,
                        extensionContext,
                        "webExtensionController.openNewWindowUsing.externalNormalTab"
                    )
                    completionHandler(dependencies.windowAdapter(activeWindow.id), nil)
                } catch {
                    completionHandler(
                        nil,
                        ExtensionManagerCallbackError.extensionExternalTabUnavailable.nsError()
                    )
                }
            }
            return
        }

        let existingWindowIDs = Set(browserContext.allExtensionWindowStates.map(\.id))
        createWindow()

        Task { @MainActor [weak self] in
            guard let self,
                  let browserContext = dependencies.browserBridgeContext() else {
                completionHandler(
                    nil,
                    ExtensionManagerCallbackError.browserManagerUnavailable.nsError()
                )
                return
            }

            guard let windowState = await awaitWindowRegistration(existingWindowIDs) else {
                completionHandler(
                    nil,
                    ExtensionManagerCallbackError.newWindowUnavailable.nsError()
                )
                return
            }

            let contextProfileId = extensionContext.flatMap {
                dependencies.profileIdForContext($0)
            }
            if let contextProfileId {
                windowState.currentProfileId = contextProfileId
                if let targetSpace = browserContext.extensionTargetSpace(for: windowState),
                   targetSpace.profileId == contextProfileId {
                    windowState.currentSpaceId = targetSpace.id
                } else {
                    completionHandler(
                        nil,
                        ExtensionManagerCallbackError.newWindowUnavailable.nsError()
                    )
                    return
                }
            }

            let targetSpace = browserContext.extensionTargetSpace(for: windowState)

            let createdTab: Tab
            if let firstURL = tabURLs.first {
                let resolvedExtensionLoad = dependencies.extensionLoadURL(
                    firstURL,
                    controller
                )
                await dependencies.prepareContentScriptContextsForInitialLoad(
                    resolvedExtensionLoad.url,
                    resolvedExtensionLoad.context,
                    windowState,
                    targetSpace,
                    controller
                )
                createdTab = browserContext.createExtensionTab(
                    url: resolvedExtensionLoad.url ?? firstURL,
                    in: targetSpace,
                    activate: false,
                    webExtensionContextOverride: resolvedExtensionLoad.context
                )
            } else {
                createdTab = browserContext.createExtensionTab(
                    url: nil,
                    in: targetSpace,
                    activate: false,
                    webExtensionContextOverride: nil
                )
            }

            dependencies.materializeNormalTabIfNeeded(
                createdTab,
                true,
                windowState
            )
            browserContext.selectExtensionTab(createdTab, in: windowState)
            dependencies.registerCreatedTabWithExtensionRuntime(
                createdTab,
                "webExtensionController.openNewWindowUsing"
            )
            completionHandler(dependencies.windowAdapter(windowState.id), nil)
        }
    }
}

@available(macOS 15.5, *)
extension ExtensionRequestedWindowOpeningOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            browserBridgeContext: { [weak manager] in
                manager?.browserBridgeContext
            },
            profileIdForContext: { [weak manager] context in
                manager?.profileId(for: context)
            },
            windowMatchesProfile: { [weak manager] windowState, profileId in
                manager?.windowMatchesProfile(windowState, profileId: profileId) ?? false
            },
            extensionLoadURL: { [weak manager] url, controller in
                manager?.extensionLoadURL(for: url, controller: controller) ?? (nil, nil)
            },
            prepareContentScriptContextsForInitialLoad: { [weak manager] loadURL, contextOverride, targetWindow, targetSpace, controller in
                _ = await manager?.prepareContentScriptContextsForExtensionRequestedInitialLoad(
                    loadURL: loadURL,
                    webExtensionContextOverride: contextOverride,
                    targetWindow: targetWindow,
                    targetSpace: targetSpace,
                    controller: controller
                )
            },
            openExtensionRequestedTab: { [weak manager] url, shouldBeActive, shouldBePinned, requestedWindow, controller, extensionContext, reason in
                guard let manager else {
                    throw ExtensionManagerCallbackError.extensionManagerUnavailable.nsError()
                }
                return try manager.openExtensionRequestedTab(
                    url: url,
                    shouldBeActive: shouldBeActive,
                    shouldBePinned: shouldBePinned,
                    requestedWindow: requestedWindow,
                    controller: controller,
                    extensionContext: extensionContext,
                    reason: reason
                )
            },
            windowAdapter: { [weak manager] windowId in
                manager?.windowAdapter(for: windowId)
            },
            materializeNormalTabIfNeeded: { [weak manager] tab, isActive, targetWindow in
                manager?.materializeExtensionRequestedNormalTabIfNeeded(
                    tab,
                    isActive: isActive,
                    targetWindow: targetWindow
                )
            },
            registerCreatedTabWithExtensionRuntime: { [weak manager] tab, reason in
                manager?.registerExtensionCreatedTabWithExtensionRuntime(
                    tab,
                    reason: reason
                )
            }
        )
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func openExtensionWindowUsingTabURLs(
        _ configuration: WKWebExtension.WindowConfiguration,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext? = nil,
        createWindow: @escaping @MainActor () -> Void,
        awaitWindowRegistration: @escaping @MainActor (Set<UUID>) async -> BrowserWindowState?,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        openExtensionWindowUsingTabURLs(
            configuration.tabURLs,
            controller: controller,
            extensionContext: extensionContext,
            createWindow: createWindow,
            awaitWindowRegistration: awaitWindowRegistration,
            completionHandler: completionHandler
        )
    }

    func openExtensionWindowUsingTabURLs(
        _ tabURLs: [URL],
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext? = nil,
        createWindow: @escaping @MainActor () -> Void,
        awaitWindowRegistration: @escaping @MainActor (Set<UUID>) async -> BrowserWindowState?,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        requestedWindowOpeningOwner.openExtensionWindowUsingTabURLs(
            tabURLs,
            controller: controller,
            extensionContext: extensionContext,
            createWindow: createWindow,
            awaitWindowRegistration: awaitWindowRegistration,
            completionHandler: completionHandler
        )
    }
}
