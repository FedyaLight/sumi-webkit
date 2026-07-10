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
    private let windowQuery: @MainActor () -> (any ExtensionWindowQuery)?
    private let requestedTabTargets:
        @MainActor () -> (any ExtensionTabTargetQuery)?
    private let tabMutation: @MainActor () -> (any ExtensionTabMutation)?
    private let profileIdForContext: @MainActor (WKWebExtensionContext) -> UUID?
    private let windowMatchesProfile: @MainActor (BrowserWindowState, UUID) -> Bool
    private let extensionLoadURL:
        @MainActor (URL?, WKWebExtensionController) -> (url: URL?, context: WKWebExtensionContext?)
    private let prepareContentScriptContextsForInitialLoad:
        @MainActor (URL?, WKWebExtensionContext?, BrowserWindowState?, Space?, WKWebExtensionController) async -> Void
    private let openExtensionRequestedTab:
        @MainActor (URL?, Bool, Bool, (any WKWebExtensionWindow)?, WKWebExtensionController, WKWebExtensionContext?, String) throws -> Tab
    private let windowAdapter: @MainActor (UUID) -> ExtensionWindowAdapter?
    private let materializeNormalTabIfNeeded: @MainActor (Tab, Bool, BrowserWindowState?) -> Void
    private let registerCreatedTabWithExtensionRuntime: @MainActor (Tab, String) -> Void

    init(
        windowQuery: @escaping @MainActor () -> (any ExtensionWindowQuery)?,
        requestedTabTargets:
            @escaping @MainActor () -> (any ExtensionTabTargetQuery)?,
        tabMutation: @escaping @MainActor () -> (any ExtensionTabMutation)?,
        profileIdForContext: @escaping @MainActor (WKWebExtensionContext) -> UUID?,
        windowMatchesProfile: @escaping @MainActor (BrowserWindowState, UUID) -> Bool,
        extensionLoadURL:
            @escaping @MainActor (URL?, WKWebExtensionController) -> (url: URL?, context: WKWebExtensionContext?),
        prepareContentScriptContextsForInitialLoad:
            @escaping @MainActor (URL?, WKWebExtensionContext?, BrowserWindowState?, Space?, WKWebExtensionController) async -> Void,
        openExtensionRequestedTab:
            @escaping @MainActor (URL?, Bool, Bool, (any WKWebExtensionWindow)?, WKWebExtensionController, WKWebExtensionContext?, String) throws -> Tab,
        windowAdapter: @escaping @MainActor (UUID) -> ExtensionWindowAdapter?,
        materializeNormalTabIfNeeded: @escaping @MainActor (Tab, Bool, BrowserWindowState?) -> Void,
        registerCreatedTabWithExtensionRuntime: @escaping @MainActor (Tab, String) -> Void
    ) {
        self.windowQuery = windowQuery
        self.requestedTabTargets = requestedTabTargets
        self.tabMutation = tabMutation
        self.profileIdForContext = profileIdForContext
        self.windowMatchesProfile = windowMatchesProfile
        self.extensionLoadURL = extensionLoadURL
        self.prepareContentScriptContextsForInitialLoad = prepareContentScriptContextsForInitialLoad
        self.openExtensionRequestedTab = openExtensionRequestedTab
        self.windowAdapter = windowAdapter
        self.materializeNormalTabIfNeeded = materializeNormalTabIfNeeded
        self.registerCreatedTabWithExtensionRuntime = registerCreatedTabWithExtensionRuntime
    }

    func openExtensionWindowUsingTabURLs(
        _ tabURLs: [URL],
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
        createWindow: @escaping @MainActor () -> Void,
        awaitWindowRegistration: @escaping @MainActor (Set<UUID>) async -> BrowserWindowState?,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        guard let windowQuery = windowQuery() else {
            completionHandler(
                nil,
                ExtensionManagerCallbackError.browserManagerUnavailable.nsError()
            )
            return
        }

        if let extensionContext,
           let firstURL = tabURLs.first,
           ExtensionActionPopupPresentation.isExtensionExternalWebPopupURL(firstURL),
           let contextProfileId = profileIdForContext(extensionContext),
           let activeWindow = windowQuery.activeExtensionWindowState,
           windowMatchesProfile(activeWindow, contextProfileId) {
            Task { @MainActor [weak self] in
                guard let self,
                      let requestedTabTargets = self.requestedTabTargets()
                else {
                    completionHandler(
                        nil,
                        ExtensionManagerCallbackError.browserManagerUnavailable.nsError()
                    )
                    return
                }
                let targetSpace = requestedTabTargets.extensionTargetSpace(
                    for: activeWindow
                )

                let resolvedExtensionLoad = self.extensionLoadURL(
                    firstURL,
                    controller
                )
                await self.prepareContentScriptContextsForInitialLoad(
                    resolvedExtensionLoad.url,
                    resolvedExtensionLoad.context,
                    activeWindow,
                    targetSpace,
                    controller
                )
                do {
                    _ = try self.openExtensionRequestedTab(
                        firstURL,
                        true,
                        false,
                        self.windowAdapter(activeWindow.id),
                        controller,
                        extensionContext,
                        "webExtensionController.openNewWindowUsing.externalNormalTab"
                    )
                    completionHandler(self.windowAdapter(activeWindow.id), nil)
                } catch {
                    completionHandler(
                        nil,
                        ExtensionManagerCallbackError.extensionExternalTabUnavailable.nsError()
                    )
                }
            }
            return
        }

        let existingWindowIDs = Set(windowQuery.allExtensionWindowStates.map(\.id))
        createWindow()

        Task { @MainActor [weak self] in
            guard let self,
                  let requestedTabTargets = self.requestedTabTargets(),
                  let tabMutation = self.tabMutation()
            else {
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
                self.profileIdForContext($0)
            }
            if let contextProfileId {
                windowState.currentProfileId = contextProfileId
                if let targetSpace = requestedTabTargets.extensionTargetSpace(
                    for: windowState
                ),
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

            let targetSpace = requestedTabTargets.extensionTargetSpace(
                for: windowState
            )

            let createdTab: Tab
            if let firstURL = tabURLs.first {
                let resolvedExtensionLoad = self.extensionLoadURL(
                    firstURL,
                    controller
                )
                await self.prepareContentScriptContextsForInitialLoad(
                    resolvedExtensionLoad.url,
                    resolvedExtensionLoad.context,
                    windowState,
                    targetSpace,
                    controller
                )
                createdTab = tabMutation.createExtensionTab(
                    url: resolvedExtensionLoad.url ?? firstURL,
                    in: targetSpace,
                    activate: false,
                    webExtensionContextOverride: resolvedExtensionLoad.context
                )
            } else {
                createdTab = tabMutation.createExtensionTab(
                    url: nil,
                    in: targetSpace,
                    activate: false,
                    webExtensionContextOverride: nil
                )
            }

            self.materializeNormalTabIfNeeded(
                createdTab,
                true,
                windowState
            )
            tabMutation.selectExtensionTab(createdTab, in: windowState)
            self.registerCreatedTabWithExtensionRuntime(
                createdTab,
                "webExtensionController.openNewWindowUsing"
            )
            completionHandler(self.windowAdapter(windowState.id), nil)
        }
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
        runtimeBundle.requestedWindowOpeningOwner.openExtensionWindowUsingTabURLs(
            tabURLs,
            controller: controller,
            extensionContext: extensionContext,
            createWindow: createWindow,
            awaitWindowRegistration: awaitWindowRegistration,
            completionHandler: completionHandler
        )
    }
}
