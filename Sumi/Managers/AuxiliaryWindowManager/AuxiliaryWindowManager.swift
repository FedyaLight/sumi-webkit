//
//  AuxiliaryWindowManager.swift
//  Sumi
//

import AppKit
import WebKit

enum AuxiliaryWindowCloseReason: String {
    case webViewDidClose
    case nativeClose
    case extensionRequestedClose
    case profileSwitch
    case appQuit
    case extensionDisable
    case managerCloseAll
}

@MainActor
final class AuxiliaryWindowSession {
    let id: UUID
    let tab: Tab
    let window: AuxiliaryCompactWindow
    let webView: WKWebView
    let openerTab: Tab?
    weak var openerWindow: NSWindow?
    let shouldActivateApp: Bool
    let isPrivate: Bool
    let ownerExtensionID: String?
    let miniWindowAdapter: ExtensionMiniWindowAdapter?
    let uiDelegate: AuxiliaryWindowUIDelegate
    let windowDelegate: AuxiliaryWindowSessionDelegate

    init(
        id: UUID = UUID(),
        tab: Tab,
        window: AuxiliaryCompactWindow,
        webView: WKWebView,
        openerTab: Tab?,
        openerWindow: NSWindow?,
        shouldActivateApp: Bool,
        isPrivate: Bool,
        ownerExtensionID: String?,
        miniWindowAdapter: ExtensionMiniWindowAdapter?,
        uiDelegate: AuxiliaryWindowUIDelegate,
        windowDelegate: AuxiliaryWindowSessionDelegate
    ) {
        self.id = id
        self.tab = tab
        self.window = window
        self.webView = webView
        self.openerTab = openerTab
        self.openerWindow = openerWindow
        self.shouldActivateApp = shouldActivateApp
        self.isPrivate = isPrivate
        self.ownerExtensionID = ownerExtensionID
        self.miniWindowAdapter = miniWindowAdapter
        self.uiDelegate = uiDelegate
        self.windowDelegate = windowDelegate
    }
}

@MainActor
final class AuxiliaryWindowSessionDelegate: NSObject, NSWindowDelegate {
    private weak var manager: AuxiliaryWindowManager?
    private let sessionID: UUID

    init(manager: AuxiliaryWindowManager, sessionID: UUID) {
        self.manager = manager
        self.sessionID = sessionID
    }

    func windowWillClose(_ notification: Notification) {
        guard let manager,
              let session = manager.session(for: sessionID)
        else {
            return
        }
        manager.teardown(for: session.webView, reason: .nativeClose)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        manager?.focus(sessionID: sessionID)
    }
}

@MainActor
final class AuxiliaryWindowManager {
    let maxNestedDepth = 3

    private(set) weak var browserManager: BrowserManager?
    private var sessionsByID: [UUID: AuxiliaryWindowSession] = [:]
    private var sessionIDsByWebViewObjectID: [ObjectIdentifier: UUID] = [:]
    private var recentAuxiliarySessionIDByOwnerExtensionID: [String: UUID] = [:]

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func session(for id: UUID) -> AuxiliaryWindowSession? {
        sessionsByID[id]
    }

    func session(for window: NSWindow) -> AuxiliaryWindowSession? {
        sessionsByID.values.first { $0.window === window }
    }

    func session(for webView: WKWebView) -> AuxiliaryWindowSession? {
        guard let sessionID = sessionIDsByWebViewObjectID[ObjectIdentifier(webView)] else {
            return nil
        }
        return sessionsByID[sessionID]
    }

    func session(for tab: Tab) -> AuxiliaryWindowSession? {
        sessionsByID.values.first { $0.tab.id == tab.id }
    }

    func contains(webView: WKWebView) -> Bool {
        sessionIDsByWebViewObjectID[ObjectIdentifier(webView)] != nil
    }

    func ownerExtensionID(for webView: WKWebView) -> String? {
        guard let sessionID = sessionIDsByWebViewObjectID[ObjectIdentifier(webView)] else {
            return nil
        }
        return sessionsByID[sessionID]?.ownerExtensionID
    }

    func recordAuxiliarySessionFocus(_ sessionID: UUID) {
        guard let ownerExtensionID = sessionsByID[sessionID]?.ownerExtensionID else {
            return
        }
        recentAuxiliarySessionIDByOwnerExtensionID[ownerExtensionID] = sessionID
    }

    func focus(sessionID: UUID) {
        guard let session = sessionsByID[sessionID] else { return }

        recordAuxiliarySessionFocus(sessionID)
        browserManager?.extensionsModule.managerIfLoadedAndEnabled()?
            .notifyAuxiliaryWindowFocused(session)
    }

    func focusedMiniWindowAdapter(forOwnerExtensionID ownerExtensionID: String) -> ExtensionMiniWindowAdapter? {
        guard let sessionID = recentAuxiliarySessionIDByOwnerExtensionID[ownerExtensionID],
              let session = sessionsByID[sessionID],
              session.ownerExtensionID == ownerExtensionID,
              session.window.isVisible,
              let adapter = session.miniWindowAdapter
        else {
            return nil
        }
        return adapter
    }

    @discardableResult
    func presentWebPopup(
        configuration: WKWebViewConfiguration,
        request: URLRequest?,
        windowFeatures: WKWindowFeatures,
        openerTab: Tab,
        isExtensionOriginated: Bool = false,
        shouldActivateApp: Bool = true,
        nestedDepth: Int = 0,
        ownerExtensionID: String? = nil,
        extensionOwnedSourceURL: URL? = nil
    ) -> WKWebView? {
        if isExtensionOriginated {
            return presentExtensionExternalWebPopup(
                configuration: configuration,
                request: request,
                windowFeatures: windowFeatures,
                openerTab: openerTab,
                shouldActivateApp: shouldActivateApp,
                nestedDepth: nestedDepth,
                extensionOwnedSourceURL: extensionOwnedSourceURL,
                ownerExtensionID: ownerExtensionID
            )
        }

        guard nestedDepth < maxNestedDepth,
              let browserManager
        else {
            return nil
        }

        let parentWindow = parentWindow(for: openerTab, browserManager: browserManager)
        let geometry = AuxiliaryWindowGeometryResolver.resolve(
            windowFeatures: windowFeatures,
            parentWindow: parentWindow
        )

        let miniTab = browserManager.tabManager.createAuxiliaryMiniWindowTab(
            openerTab: openerTab,
            urlString: request?.url?.absoluteString
        )
        let webView = miniTab.createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
            configuration,
            currentURL: request?.url,
            isExtensionOriginated: false,
            reason: "AuxiliaryWindowManager.presentWebPopup"
        )

        guard finalizePresentation(
            tab: miniTab,
            webView: webView,
            geometry: geometry,
            openerTab: openerTab,
            request: request,
            shouldActivateApp: shouldActivateApp,
            isPrivate: openerTab.isEphemeral,
            nestedDepth: nestedDepth,
            extensionManager: nil,
            extensionContext: nil,
            ownerExtensionID: ownerExtensionID
        ) != nil else {
            return nil
        }
        return webView
    }

    @discardableResult
    func presentExtensionExternalWebPopup(
        configuration: WKWebViewConfiguration,
        request: URLRequest?,
        windowFeatures: WKWindowFeatures,
        openerTab: Tab,
        shouldActivateApp: Bool = true,
        nestedDepth: Int = 0,
        extensionOwnedSourceURL: URL? = nil,
        ownerExtensionID: String? = nil
    ) -> WKWebView? {
        guard nestedDepth < maxNestedDepth,
              let browserManager
        else {
            return nil
        }

        let extensionManager = browserManager.extensionsModule.managerIfLoadedAndEnabled()
        let resolvedOwnerExtensionID = resolveOwnerExtensionID(
            extensionManager: extensionManager,
            extensionContext: nil,
            openerTab: openerTab,
            extensionOwnedSourceURL: extensionOwnedSourceURL,
            explicitOwnerExtensionID: ownerExtensionID
        )

        let parentWindow = parentWindow(for: openerTab, browserManager: browserManager)
        let geometry: AuxiliaryWindowGeometry
        if windowFeatures.width != nil {
            geometry = AuxiliaryWindowGeometryResolver.resolve(
                windowFeatures: windowFeatures,
                parentWindow: parentWindow
            )
        } else {
            geometry = AuxiliaryWindowGeometryResolver.resolveDefault(parentWindow: parentWindow)
        }

        let miniTab = browserManager.tabManager.createAuxiliaryMiniWindowTab(
            openerTab: openerTab,
            urlString: request?.url?.absoluteString
        )
        let webView = miniTab.createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
            configuration,
            currentURL: request?.url,
            isExtensionOriginated: true,
            reason: "AuxiliaryWindowManager.presentExtensionExternalWebPopup"
        )

        guard finalizePresentation(
            tab: miniTab,
            webView: webView,
            geometry: geometry,
            openerTab: openerTab,
            explicitOpenerWindow: parentWindow,
            request: request,
            shouldActivateApp: shouldActivateApp,
            isPrivate: openerTab.isEphemeral,
            nestedDepth: nestedDepth,
            extensionManager: extensionManager,
            extensionContext: miniTab.webExtensionContextOverride,
            registerExtensionMiniWindowAdapter: true,
            ownerExtensionID: resolvedOwnerExtensionID
        ) != nil else {
            return nil
        }

        browserManager.extensionsModule.registerExtensionCreatedTabWithExtensionRuntimeIfLoaded(
            miniTab,
            reason: "AuxiliaryWindowManager.presentExtensionExternalWebPopup"
        )
        if let session = session(for: webView) {
            extensionManager?.notifyAuxiliaryWindowOpened(session)
        }
        return webView
    }

    @discardableResult
    func presentExtensionExternalWebPopupSession(
        configuration: WKWebViewConfiguration,
        request: URLRequest?,
        windowFeatures: WKWindowFeatures,
        openerTab: Tab,
        shouldActivateApp: Bool = true,
        nestedDepth: Int = 0,
        extensionOwnedSourceURL: URL? = nil,
        ownerExtensionID: String? = nil
    ) -> AuxiliaryWindowSession? {
        guard let webView = presentExtensionExternalWebPopup(
            configuration: configuration,
            request: request,
            windowFeatures: windowFeatures,
            openerTab: openerTab,
            shouldActivateApp: shouldActivateApp,
            nestedDepth: nestedDepth,
            extensionOwnedSourceURL: extensionOwnedSourceURL,
            ownerExtensionID: ownerExtensionID
        ) else {
            return nil
        }
        return session(for: webView)
    }

    func presentExtensionPopupWindow(
        configuration: WKWebExtension.WindowConfiguration,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext,
        extensionManager: ExtensionManager,
        parentWindow: NSWindow?
    ) async -> ExtensionMiniWindowAdapter? {
        guard let browserManager else { return nil }

        let isPrivate = configuration.shouldBePrivate
            || browserManager.windowRegistry?.activeWindow?.isIncognito == true
        guard isPrivate == false else {
            return nil
        }

        let geometry = AuxiliaryWindowGeometryResolver.resolve(
            extensionFrame: configuration.frame,
            parentWindow: parentWindow
        )

        let openerTab = browserManager.windowRegistry?.activeWindow.flatMap {
            browserManager.currentTab(for: $0)
        }
        let profileId = extensionManager.profileId(for: extensionContext)
            ?? openerTab?.profileId
            ?? browserManager.currentProfile?.id

        if let profileId {
            await extensionManager.ensureInitialDocumentExtensionContextsLoaded(
                for: profileId
            )
        }

        let firstURL = configuration.tabURLs.first
        let resolvedExtensionLoad = extensionManager.extensionLoadURL(
            for: firstURL,
            controller: controller
        )
        let loadURL = resolvedExtensionLoad.url ?? firstURL
        let isExtensionOwnedLoad = ExtensionUtils.isExtensionOwnedURL(loadURL)
        let tabWebExtensionContextOverride = resolvedExtensionLoad.context
            ?? (isExtensionOwnedLoad ? extensionContext : nil)

        if let loadURL {
            await extensionManager.prepareContentScriptContextsForExtensionRequestedInitialLoad(
                loadURL: loadURL,
                webExtensionContextOverride: tabWebExtensionContextOverride,
                targetWindow: browserManager.windowRegistry?.activeWindow,
                targetSpace: browserManager.tabManager.currentSpace,
                controller: controller
            )
            extensionManager.recordRecentlyOpenedExtensionTabRequest(for: loadURL)
        }

        let loadURLString = loadURL?.absoluteString
            ?? SumiSurface.emptyTabURL.absoluteString

        let miniTab = browserManager.tabManager.createAuxiliaryMiniWindowTab(
            openerTab: openerTab,
            profileId: profileId,
            urlString: loadURLString,
            webExtensionContextOverride: tabWebExtensionContextOverride
        )

        let webViewConfiguration = (tabWebExtensionContextOverride ?? extensionContext).webViewConfiguration
            ?? WKWebViewConfiguration()
        extensionManager.prepareWebViewConfigurationForExtensionRuntime(
            webViewConfiguration,
            profileId: profileId,
            reason: "AuxiliaryWindowManager.presentExtensionPopupWindow.webView"
        )
        let webView = miniTab.createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
            webViewConfiguration,
            currentURL: loadURL,
            isExtensionOriginated: true,
            reason: "AuxiliaryWindowManager.presentExtensionPopupWindow"
        )

        let shouldActivateApp = configuration.shouldBeFocused
        let ownerExtensionID = resolveOwnerExtensionID(
            extensionManager: extensionManager,
            extensionContext: extensionContext,
            openerTab: openerTab,
            extensionOwnedSourceURL: firstURL,
            explicitOwnerExtensionID: nil
        )

        let sessionID = finalizePresentation(
            tab: miniTab,
            webView: webView,
            geometry: geometry,
            openerTab: openerTab,
            explicitOpenerWindow: parentWindow,
            request: firstURL.map { URLRequest(url: $0) },
            shouldActivateApp: shouldActivateApp,
            isPrivate: isPrivate,
            nestedDepth: 0,
            extensionManager: extensionManager,
            extensionContext: extensionContext,
            registerExtensionMiniWindowAdapter: true,
            ownerExtensionID: ownerExtensionID
        )

        guard let sessionID else { return nil }

        extensionManager.registerExtensionCreatedTabWithExtensionRuntime(
            miniTab,
            reason: "AuxiliaryWindowManager.presentExtensionPopupWindow"
        )
        if let session = sessionsByID[sessionID] {
            extensionManager.notifyAuxiliaryWindowOpened(session)
        }
        if let loadURL {
            miniTab.loadURL(loadURL)
        }
        return sessionsByID[sessionID]?.miniWindowAdapter
    }

    func teardown(for webView: WKWebView, reason: AuxiliaryWindowCloseReason = .webViewDidClose) {
        guard let sessionID = sessionIDsByWebViewObjectID.removeValue(forKey: ObjectIdentifier(webView)),
              let session = sessionsByID.removeValue(forKey: sessionID)
        else {
            return
        }

        let openerWindow = session.openerWindow
        let shouldActivateApp = session.shouldActivateApp

        session.window.delegate = nil
        webView.stopLoading()
        webView.uiDelegate = nil
        webView.navigationDelegate = nil
        webView.removeFromSuperview()

        browserManager?.extensionsModule.managerIfLoadedAndEnabled()?
            .notifyAuxiliaryWindowClosed(session)

        if let ownerExtensionID = session.ownerExtensionID,
           recentAuxiliarySessionIDByOwnerExtensionID[ownerExtensionID] == sessionID {
            recentAuxiliarySessionIDByOwnerExtensionID.removeValue(forKey: ownerExtensionID)
        }

        browserManager?.extensionsModule.notifyTabClosedIfLoaded(session.tab)
        session.tab.performComprehensiveWebViewCleanup()
        browserManager?.tabManager.removeAuxiliaryMiniWindowTab(session.tab)

        if reason != .nativeClose, session.window.isVisible {
            session.window.close()
        }

        if shouldActivateApp,
           let openerWindow,
           openerWindow.isVisible {
            openerWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func closeAll(reason: AuxiliaryWindowCloseReason = .managerCloseAll) {
        let activeWebViews = sessionsByID.values.map(\.webView)
        for webView in activeWebViews {
            teardown(for: webView, reason: reason)
        }
    }

    func closeAll(
        forExtensionId extensionId: String,
        reason: AuxiliaryWindowCloseReason = .extensionDisable
    ) {
        let matchingWebViews = sessionsByID.values.compactMap { session -> WKWebView? in
            guard session.ownerExtensionID == extensionId else { return nil }
            return session.webView
        }

        for webView in matchingWebViews {
            teardown(for: webView, reason: reason)
        }
    }

    // MARK: - Private

    private func parentWindow(for tab: Tab, browserManager: BrowserManager) -> NSWindow? {
        browserManager.windowState(containing: tab)?.window
            ?? browserManager.windowRegistry?.activeWindow?.window
    }

    private func resolveOwnerExtensionID(
        extensionManager: ExtensionManager?,
        extensionContext: WKWebExtensionContext?,
        openerTab: Tab?,
        extensionOwnedSourceURL: URL?,
        explicitOwnerExtensionID: String?
    ) -> String? {
        if let explicitOwnerExtensionID {
            return explicitOwnerExtensionID
        }

        if let extensionManager {
            return extensionManager.ownerExtensionID(
                extensionContext: extensionContext,
                openerTab: openerTab,
                extensionOwnedSourceURL: extensionOwnedSourceURL
            )
        }

        for candidate in [extensionOwnedSourceURL, openerTab?.url] {
            guard let url = candidate,
                  ExtensionUtils.isExtensionOwnedURL(url),
                  let host = url.host,
                  host.isEmpty == false
            else {
                continue
            }
            return host
        }

        return nil
    }

    @discardableResult
    private func finalizePresentation(
        tab: Tab,
        webView: WKWebView,
        geometry: AuxiliaryWindowGeometry,
        openerTab: Tab?,
        explicitOpenerWindow: NSWindow? = nil,
        request: URLRequest?,
        shouldActivateApp: Bool,
        isPrivate: Bool,
        nestedDepth: Int,
        extensionManager: ExtensionManager?,
        extensionContext: WKWebExtensionContext?,
        registerExtensionMiniWindowAdapter: Bool = false,
        ownerExtensionID: String? = nil
    ) -> UUID? {
        guard let browserManager else { return nil }

        let sessionID = UUID()
        let openerWindow = openerTab.flatMap {
            parentWindow(for: $0, browserManager: browserManager)
        } ?? explicitOpenerWindow
        let window = AuxiliaryCompactWindow(contentRect: geometry.contentRect)
        window.title = Self.windowTitle(
            for: request?.url,
            ownerExtensionID: ownerExtensionID,
            installedExtensions: extensionManager?.installedExtensions ?? []
        )

        let containerView = NSView(frame: NSRect(origin: .zero, size: geometry.contentRect.size))
        window.contentView = containerView

        webView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: containerView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        let uiDelegate = AuxiliaryWindowUIDelegate(
            manager: self,
            openerTab: openerTab ?? tab,
            nestedDepth: nestedDepth
        )
        webView.uiDelegate = uiDelegate

        let windowDelegate = AuxiliaryWindowSessionDelegate(manager: self, sessionID: sessionID)
        window.delegate = windowDelegate

        let miniWindowAdapter: ExtensionMiniWindowAdapter?
        if let extensionManager,
           extensionContext != nil || registerExtensionMiniWindowAdapter {
            miniWindowAdapter = extensionManager.miniWindowAdapter(
                for: sessionID,
                tab: tab,
                window: window,
                isPrivate: isPrivate,
                shouldActivateApp: shouldActivateApp
            )
        } else {
            miniWindowAdapter = nil
        }

        let session = AuxiliaryWindowSession(
            id: sessionID,
            tab: tab,
            window: window,
            webView: webView,
            openerTab: openerTab,
            openerWindow: openerWindow,
            shouldActivateApp: shouldActivateApp,
            isPrivate: isPrivate,
            ownerExtensionID: ownerExtensionID,
            miniWindowAdapter: miniWindowAdapter,
            uiDelegate: uiDelegate,
            windowDelegate: windowDelegate
        )

        registerSession(session)
        window.present(shouldActivateApp: shouldActivateApp)
        if ownerExtensionID != nil, shouldActivateApp {
            recordAuxiliarySessionFocus(sessionID)
        }
        return sessionID
    }

    static func windowTitle(
        for url: URL?,
        ownerExtensionID: String?,
        installedExtensions: [InstalledExtension]
    ) -> String {
        if ExtensionUtils.isExtensionOwnedURL(url) {
            return ExtensionUtils.displayName(
                forExtensionOwnedURL: url,
                installedExtensions: installedExtensions
            ) ?? ExtensionUtils.displayName(
                forExtensionID: ownerExtensionID,
                installedExtensions: installedExtensions
            ) ?? "Extension"
        }

        if let title = url?.host, title.isEmpty == false {
            return title
        }

        return "Popup"
    }

    private func registerSession(_ session: AuxiliaryWindowSession) {
        sessionsByID[session.id] = session
        sessionIDsByWebViewObjectID[ObjectIdentifier(session.webView)] = session.id
    }
}
