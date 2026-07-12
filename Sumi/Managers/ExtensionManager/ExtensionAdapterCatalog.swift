//
//  ExtensionAdapterCatalog.swift
//  Sumi
//
//  Resolves (and lazily creates) the WKWebExtension window/tab adapter
//  objects that bridge browser windows and tabs into the extension runtime.
//

import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionAdapterCatalog {
    private weak var manager: ExtensionManager?

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    func miniWindowAdapter(for tab: Tab) -> ExtensionMiniWindowAdapter? {
        manager?.extensionAuxiliaryWindows?
            .auxiliaryWindowSession(for: tab)?.miniWindowAdapter
    }

    func miniWindowAdapter(
        for sessionId: UUID,
        tab: Tab,
        window: NSWindow,
        isPrivate: Bool,
        shouldActivateApp: Bool
    ) -> ExtensionMiniWindowAdapter? {
        guard let manager else { return nil }
        return manager.adapterStore.miniWindowAdapter(for: sessionId) { [weak manager] in
            guard let manager,
                  let auxiliaryWindows = manager.extensionAuxiliaryWindows
            else {
                return nil
            }

            return ExtensionMiniWindowAdapter(
                sessionId: sessionId,
                tab: tab,
                window: window,
                auxiliaryWindows: auxiliaryWindows,
                windowPublications: manager.windowPublications,
                isPrivate: isPrivate,
                shouldActivateApp: shouldActivateApp
            )
        }
    }

    func windowAdapter(for windowId: UUID) -> ExtensionWindowAdapter? {
        guard let manager else { return nil }
        return manager.adapterStore.windowAdapter(for: windowId) { [weak manager] in
            guard let manager,
                  let windowQuery = manager.extensionWindowQuery,
                  let windowActivation = manager.extensionWindowActivation,
                  let windowState = windowQuery.extensionWindowState(
                    for: windowId
                  )
            else {
                return nil
            }

            return ExtensionWindowAdapter(
                windowState: windowState,
                windowQuery: windowQuery,
                windowActivation: windowActivation,
                contextPublications: manager.contextPublications,
                extensionManager: manager
            )
        }
    }

    /// Resolves only a normal window already published to the exact WebKit
    /// profile represented by `extensionContext`. This is the read boundary;
    /// `windowAdapter(for:)` exists only for lifecycle materialization.
    func publishedNormalWindowAdapter(
        for windowState: BrowserWindowState,
        extensionContext: WKWebExtensionContext
    ) -> ExtensionWindowAdapter? {
        guard let manager,
              let windowQuery = manager.extensionWindowQuery,
              windowQuery.extensionWindowState(for: windowState.id)
                === windowState,
              let profileID = manager.contextPublications.currentIdentity(
                for: extensionContext
              )?.profileID,
              manager.windowMatchesProfile(windowState, profileId: profileID),
              let adapter = manager.windowPublications.publishedWindowAdapter(
                    for: windowState,
                    profileID: profileID
                ),
              adapter.represents(windowState)
        else {
            return nil
        }
        return adapter
    }

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        guard let manager else { return nil }
        return manager.adapterStore.tabAdapter(for: tab) { [weak manager] in
            guard let manager,
                  let windowQuery = manager.extensionWindowQuery,
                  let tabQuery = manager.extensionTabQuery,
                  let tabMutation = manager.extensionTabMutation,
                  let webViewHosting = manager.extensionWebViewHosting,
                  let auxiliaryWindows = manager.extensionAuxiliaryWindows
            else {
                return nil
            }

            let evidence = ExtensionTabCurrentPublicationEvidence(
                tab: tab,
                tabQuery: tabQuery,
                runtimeSession: manager.runtimeSession,
                profileID: { [weak manager] tab in
                    manager?.resolvedProfileId(for: tab)
                },
                adapterPublications: manager.adapterStore,
                windowPublications: manager.windowPublications,
                contextPublications: manager.contextPublications
            )
            let projection = ExtensionTabReadProjection(
                evidence: evidence,
                windowQuery: windowQuery,
                tabQuery: tabQuery,
                webViews: manager.tabWebViewResolver,
                auxiliaryWindows: auxiliaryWindows,
                windowPublications: manager.windowPublications
            )
            let commands = ExtensionTabCommandMutation(
                evidence: evidence,
                projection: projection,
                windowQuery: windowQuery,
                tabMutation: tabMutation,
                webViewHosting: webViewHosting,
                auxiliaryWindows: auxiliaryWindows
            )
            return ExtensionTabAdapter(
                evidence: evidence,
                projection: projection,
                commands: commands
            )
        }
    }
}
