//
//  ExtensionBridge.swift
//  Sumi
//
//  WebKit bridge adapters that expose Sumi windows and tabs to WebExtensions.
//

import AppKit
import Foundation
import SumiWebRuntime

@available(macOS 15.5, *)
@MainActor
final class ExtensionWindowAdapter: NSObject, WKWebExtensionWindow {
    let windowId: UUID

    private weak var exactWindowState: BrowserWindowState?
    private weak var windowQuery: (any ExtensionWindowQuery)?
    private weak var windowActivation: (any ExtensionWindowActivation)?
    private let identity: ExtensionWindowAdapterIdentityProjection
    private weak var windowPublications: ExtensionWindowPublicationQuery?
    private weak var tabAdapters: (any ExtensionTabAdapterResolving)?
    private weak var publishedTabs: ExtensionPublishedNormalTabQuery?
    private weak var preparedTabs: ExtensionPreparedNormalTabQuery?
    private let preparedTabVisibility: ExtensionPreparedTabVisibility
    private let stateTransitions = ExtensionWindowStateTransitionCoordinator(
        supersededError: {
            ExtensionBridgeAdapterCallbackError
                .windowStateTransitionSuperseded
                .nsError()
        },
        invalidatedError: {
            ExtensionBridgeAdapterCallbackError
                .windowStateTransitionInvalidated
                .nsError()
        }
    )

    init(
        windowState: BrowserWindowState,
        windowQuery: any ExtensionWindowQuery,
        windowActivation: any ExtensionWindowActivation,
        identity: ExtensionWindowAdapterIdentityProjection,
        preparedTabVisibility: ExtensionPreparedTabVisibility,
        windowPublications: ExtensionWindowPublicationQuery,
        tabAdapters: any ExtensionTabAdapterResolving,
        publishedTabs: ExtensionPublishedNormalTabQuery,
        preparedTabs: ExtensionPreparedNormalTabQuery
    ) {
        self.windowId = windowState.id
        self.exactWindowState = windowState
        self.windowQuery = windowQuery
        self.windowActivation = windowActivation
        self.identity = identity
        self.preparedTabVisibility = preparedTabVisibility
        self.windowPublications = windowPublications
        self.tabAdapters = tabAdapters
        self.publishedTabs = publishedTabs
        self.preparedTabs = preparedTabs
        super.init()
    }

    private var windowState: BrowserWindowState? {
        guard let exactWindowState,
              windowQuery?.extensionWindowState(for: windowId)
                === exactWindowState
        else {
            return nil
        }
        return exactWindowState
    }

    private func publishedWindowState(
        for extensionContext: WKWebExtensionContext
    ) -> BrowserWindowState? {
        guard let windowState,
              let contextProfileId = identity.profileID(for: extensionContext),
              identity.profileID(for: windowState) == contextProfileId,
              windowPublications?.publishedWindowAdapter(
                    for: windowState,
                    profileID: contextProfileId
                ) === self
        else {
            return nil
        }
        return windowState
    }

    func represents(_ windowState: BrowserWindowState) -> Bool {
        exactWindowState === windowState
            && self.windowState === windowState
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ExtensionWindowAdapter else {
            return false
        }
        return other === self
    }

    override var hash: Int {
        ObjectIdentifier(self).hashValue
    }

    func activeTab(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard
            let windowQuery,
            let tabAdapters,
            let windowState = publishedWindowState(for: extensionContext),
            let contextProfileId = identity.profileID(for: extensionContext),
            let tab = windowQuery.currentExtensionTab(in: windowState),
            identity.profileID(for: tab) == contextProfileId,
            tabIsVisibleToPublishedWindow(tab, in: windowState)
        else {
            SafariExtensionAutofillFillDiagnostics.recordPopupTabVisibility(
                seesCurrentTab: false,
                extensionId: identity.extensionID(for: extensionContext),
                reason: "activeTabAdapterUnavailable"
            )
            return nil
        }

        let adapter = tabAdapters.stableAdapter(for: tab)
        SafariExtensionAutofillFillDiagnostics.recordPopupTabVisibility(
            seesCurrentTab: adapter != nil,
            extensionId: identity.extensionID(for: extensionContext),
            reason: "activeTabAdapterResolved"
        )
        return adapter
    }

    func tabs(for extensionContext: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let windowQuery,
              let tabAdapters,
              let windowState = publishedWindowState(for: extensionContext),
              let contextProfileId = identity.profileID(for: extensionContext),
              identity.profileID(for: windowState) == contextProfileId
        else { return [] }

        return windowQuery.tabsForExtensionWindow(windowState).filter {
            identity.profileID(for: $0) == contextProfileId
                && tabIsVisibleToPublishedWindow($0, in: windowState)
        }.compactMap {
            tabAdapters.stableAdapter(for: $0)
        }
    }

    private func tabIsVisibleToPublishedWindow(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) -> Bool {
        if publishedTabs?.containsPublishedTab(tab) == true {
            return true
        }
        return preparedTabVisibility.allowsPreparedTabRead(
            tab,
            in: windowState,
            through: self
        ) && preparedTabs?.containsPreparedTab(tab) == true
    }

    func frame(for extensionContext: WKWebExtensionContext) -> CGRect {
        appKitWindow(for: extensionContext)?.frame ?? .zero
    }

    func screenFrame(for extensionContext: WKWebExtensionContext) -> CGRect {
        guard let window = appKitWindow(for: extensionContext) else {
            return .zero
        }
        return window.screen?.frame ?? .zero
    }

    func focus(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let windowState = publishedWindowState(for: extensionContext),
              let window = appKitWindow(for: windowState)
        else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: ExtensionBridgeAdapterCallbackError
                    .windowUnavailable(operation: .focus)
                    .nsError()
            )
            return
        }

        window.makeKeyAndOrderFront(nil)
        windowActivation?.setActiveExtensionWindow(windowState)
        NSApp.activate(ignoringOtherApps: true)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }

    func isPrivate(for extensionContext: WKWebExtensionContext) -> Bool {
        publishedWindowState(for: extensionContext)?.isIncognito ?? false
    }

    func windowType(for _: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .normal
    }

    func windowState(for extensionContext: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window = appKitWindow(for: extensionContext) else { return .normal }
        return webExtensionWindowState(of: window)
    }

    func setWindowState(
        _ windowState: WKWebExtension.WindowState,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let window = appKitWindow(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: ExtensionBridgeAdapterCallbackError
                    .windowUnavailable(operation: .setWindowState)
                    .nsError()
            )
            return
        }
        stateTransitions.transition(
            window: window,
            to: windowState,
            isCurrent: { [weak self, weak window] in
                guard let self, let window else { return false }
                return self.appKitWindow(for: extensionContext) === window
            },
            completion: { error in
                ExtensionBridgeCallbackSupport.complete(
                    completionHandler,
                    api: .windowAdapterCompletion,
                    error: error
                )
            }
        )
    }

    func setFrame(
        _ frame: CGRect,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let window = appKitWindow(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: ExtensionBridgeAdapterCallbackError
                    .windowUnavailable(operation: .setFrame)
                    .nsError()
            )
            return
        }

        window.setFrame(frame, display: true)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }

    func close(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let window = appKitWindow(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: ExtensionBridgeAdapterCallbackError
                    .windowUnavailable(operation: .close)
                    .nsError()
            )
            return
        }

        window.performClose(nil)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }

    private func appKitWindow(for extensionContext: WKWebExtensionContext) -> NSWindow? {
        guard let windowState = publishedWindowState(for: extensionContext) else {
            return nil
        }
        return appKitWindow(for: windowState)
    }

    private func appKitWindow(for windowState: BrowserWindowState) -> NSWindow? {
        windowQuery?.appKitWindow(for: windowState)
    }
}
