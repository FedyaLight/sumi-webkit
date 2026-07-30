//
//  ExtensionBridge.swift
//  Sumi
//
//  WebKit bridge adapters that expose Sumi windows and tabs to WebExtensions.
//

import AppKit
import Foundation
import SumiWebRuntime

@MainActor
final class ExtensionMiniWindowAdapter: NSObject, WKWebExtensionWindow {
    let sessionId: UUID
    let tabId: UUID

    private weak var auxiliaryWindows: (any ExtensionAuxiliaryWindowControl)?
    private weak var windowPublications: ExtensionWindowPublicationQuery?
    private weak var window: NSWindow?
    private var sessionReceipt: AuxiliaryWindowSessionReceipt?
    private var isRetired = false
    private let isPrivateWindow: Bool
    private let shouldActivateApp: Bool
    private let stateTransitions = ExtensionWindowStateTransitionCoordinator(
        supersededError: {
            ExtensionBridgeAdapterCallbackError
                .miniWindowStateTransitionSuperseded
                .nsError()
        },
        invalidatedError: {
            ExtensionBridgeAdapterCallbackError
                .miniWindowStateTransitionInvalidated
                .nsError()
        }
    )

    init(
        sessionId: UUID,
        tab: Tab,
        window: NSWindow,
        auxiliaryWindows: any ExtensionAuxiliaryWindowControl,
        windowPublications: ExtensionWindowPublicationQuery,
        isPrivate: Bool,
        shouldActivateApp: Bool
    ) {
        self.sessionId = sessionId
        self.tabId = tab.id
        self.window = window
        self.auxiliaryWindows = auxiliaryWindows
        self.windowPublications = windowPublications
        self.isPrivateWindow = isPrivate
        self.shouldActivateApp = shouldActivateApp
        super.init()
    }

    func bind(_ receipt: AuxiliaryWindowSessionReceipt) {
        precondition(sessionReceipt == nil)
        precondition(receipt.sessionID == sessionId)
        sessionReceipt = receipt
    }

    private func currentSession(
        to extensionContext: WKWebExtensionContext
    ) -> AuxiliaryWindowSession? {
        guard isRetired == false,
              let sessionReceipt,
              let session = auxiliaryWindows?.auxiliaryWindowSession(
                for: sessionReceipt
              ),
              session.id == sessionId,
              session.miniWindowAdapter === self,
              session.window === window,
              windowPublications?.isCurrentAuxiliaryWindowAdapter(
                self,
                visibleTo: extensionContext
              ) == true
        else {
            return nil
        }
        return session
    }

    private func completeUnavailable(
        _ operation: ExtensionBridgeAdapterCallbackError.MiniWindowOperation,
        completionHandler: @escaping (Error?) -> Void
    ) {
        ExtensionBridgeCallbackSupport.complete(
            completionHandler,
            api: .windowAdapterCompletion,
            error: ExtensionBridgeAdapterCallbackError
                .miniWindowUnavailable(operation: operation)
                .nsError()
        )
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ExtensionMiniWindowAdapter else { return false }
        return other.sessionId == sessionId
    }

    override var hash: Int {
        sessionId.hashValue
    }

    func tabs(
        for extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionTab] {
        guard currentSession(to: extensionContext) != nil,
              let adapter = windowPublications?
            .publishedAuxiliaryTabAdapter(
                for: self,
                visibleTo: extensionContext
            ) else { return [] }
        return [adapter]
    }

    func activeTab(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        tabs(for: extensionContext).first
    }

    func windowType(
        for extensionContext: WKWebExtensionContext
    ) -> WKWebExtension.WindowType {
        currentSession(to: extensionContext) != nil ? .popup : .normal
    }

    func windowState(
        for extensionContext: WKWebExtensionContext
    ) -> WKWebExtension.WindowState {
        guard currentSession(to: extensionContext) != nil, let window else {
            return .normal
        }
        return webExtensionWindowState(of: window)
    }

    func isPrivate(for extensionContext: WKWebExtensionContext) -> Bool {
        currentSession(to: extensionContext) != nil && isPrivateWindow
    }

    func screenFrame(for extensionContext: WKWebExtensionContext) -> CGRect {
        guard currentSession(to: extensionContext) != nil else { return .zero }
        return window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
    }

    func frame(for extensionContext: WKWebExtensionContext) -> CGRect {
        guard currentSession(to: extensionContext) != nil else { return .zero }
        return window?.frame ?? .zero
    }

    func setWindowState(
        _ windowState: WKWebExtension.WindowState,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let session = currentSession(to: extensionContext),
              let window,
              let expectedReceipt = sessionReceipt else {
            completeUnavailable(
                .setWindowState,
                completionHandler: completionHandler
            )
            return
        }
        let sessionIdentity = ObjectIdentifier(session)
        let windowIdentity = ObjectIdentifier(window)
        stateTransitions.transition(
            window: window,
            to: windowState,
            isCurrent: { [weak self, weak window] in
                guard let self,
                      let window,
                      ObjectIdentifier(window) == windowIdentity,
                      self.sessionReceipt == expectedReceipt,
                      let current = self.currentSession(to: extensionContext),
                      ObjectIdentifier(current) == sessionIdentity,
                      current.window === window else {
                    return false
                }
                return true
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
        guard let session = currentSession(to: extensionContext),
              let window else {
            completeUnavailable(.setFrame, completionHandler: completionHandler)
            return
        }

        window.setFrame(frame, display: true)
        guard currentSession(to: extensionContext) === session else {
            completeUnavailable(.setFrame, completionHandler: completionHandler)
            return
        }
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }

    func focus(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let session = currentSession(to: extensionContext),
              let window,
              let sessionReceipt else {
            completeUnavailable(.focus, completionHandler: completionHandler)
            return
        }
        if shouldActivateApp {
            NSApp.activate(ignoringOtherApps: true)
            guard currentSession(to: extensionContext) === session else {
                completeUnavailable(.focus, completionHandler: completionHandler)
                return
            }
        }
        window.makeKeyAndOrderFront(nil)
        guard currentSession(to: extensionContext) === session,
              auxiliaryWindows?.focusAuxiliaryWindowSession(sessionReceipt)
                == true,
              currentSession(to: extensionContext) === session else {
            completeUnavailable(.focus, completionHandler: completionHandler)
            return
        }
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }

    func close(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard currentSession(to: extensionContext) != nil,
              let auxiliaryWindows,
              let sessionReceipt
        else {
            completeUnavailable(.close, completionHandler: completionHandler)
            return
        }

        isRetired = true
        stateTransitions.invalidateActiveTransition()
        auxiliaryWindows.closeAuxiliaryWindowSession(sessionReceipt)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }
}
