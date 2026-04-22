import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager: NSPopoverDelegate {
    func prepareWebViewConfigurationForExtensionRuntime(
        _ configuration: WKWebViewConfiguration,
        reason: String = #function
    ) {
        let requestedController = requestExtensionRuntime(
            reason: .webViewConfiguration
        )
        let existingController = configuration.webExtensionController
        let shouldAssignController = existingController == nil && requestedController != nil

        extensionRuntimeTrace(
            "prepareConfiguration reason=\(reason) configuration=\(extensionRuntimeConfigurationDescription(configuration)) userContentController=\(extensionRuntimeUserContentControllerDescription(configuration.userContentController)) existingController=\(extensionRuntimeControllerDescription(existingController)) targetController=\(extensionRuntimeControllerDescription(requestedController)) willAssign=\(shouldAssignController)"
        )

        if shouldAssignController {
            configuration.webExtensionController = requestedController
        }
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    }

    func prepareWebViewForExtensionRuntime(
        _ webView: WKWebView,
        currentURL: URL? = nil
    ) {
        prepareWebViewForExtensionRuntime(
            webView,
            currentURL: currentURL,
            reason: #function
        )
    }

    func showExtensionInstallDialog() {
        guard isExtensionSupportAvailable else {
            showErrorAlert(.unsupportedOS)
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.title = "Install Safari Extension"
        openPanel.message = "Select a Safari extension bundle (.app, .appex) or an unpacked extension directory with a manifest.json."
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [
            .application,
            .applicationExtension,
            .directory,
        ]

        if openPanel.runModal() == .OK, let url = openPanel.url {
            installExtension(from: url) { [weak self] result in
                if case .failure(let error) = result {
                    self?.showErrorAlert(error)
                }
            }
        }
    }

    func setActionAnchor(for extensionId: String, anchorView: NSView) {
        pruneActionAnchors(for: extensionId, keeping: anchorView)

        let anchor = WeakAnchor(view: anchorView, window: anchorView.window)
        var anchors = actionAnchors[extensionId] ?? []

        if let index = anchors.firstIndex(where: { $0.view === anchorView }) {
            anchors[index] = anchor
        } else {
            anchors.append(anchor)
        }
        actionAnchors[extensionId] = anchors

        let viewIdentifier = ObjectIdentifier(anchorView)
        anchorView.postsFrameChangedNotifications = true

        if anchorObserverTokens[extensionId]?[viewIdentifier] != nil {
            return
        }

        let token = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: anchorView,
            queue: .main
        ) { [weak self, weak anchorView] _ in
            guard let anchorView else { return }
            Task { @MainActor [weak self] in
                guard let index = self?.actionAnchors[extensionId]?.firstIndex(where: { $0.view === anchorView }) else {
                    return
                }
                self?.actionAnchors[extensionId]?[index] = WeakAnchor(
                    view: anchorView,
                    window: anchorView.window
                )
                self?.pruneActionAnchors(for: extensionId, keeping: anchorView)
            }
        }

        anchorObserverTokens[extensionId, default: [:]][viewIdentifier] = token
        enforceActionAnchorLimit(for: extensionId, keeping: anchorView)
    }

    func clearActionAnchors(for extensionId: String) {
        removeAnchorObservers(for: extensionId)
        actionAnchors.removeValue(forKey: extensionId)
    }

    func closeOptionsWindow(for extensionId: String) {
        guard let window = optionsWindows.removeValue(forKey: extensionId) else {
            return
        }
        window.orderOut(nil)
        window.contentViewController = nil
        window.delegate = nil
    }

    func prepareWebViewForExtensionRuntime(
        _ webView: WKWebView,
        currentURL: URL? = nil,
        reason: String = #function
    ) {
        let existingController = webView.configuration.webExtensionController

        extensionRuntimeTrace(
            "prepareWebView reason=\(reason) webView=\(extensionRuntimeWebViewDescription(webView)) configuration=\(extensionRuntimeConfigurationDescription(webView.configuration)) userContentController=\(extensionRuntimeUserContentControllerDescription(webView.configuration.userContentController)) currentURL=\(currentURL?.absoluteString ?? "nil") existingController=\(extensionRuntimeControllerDescription(existingController)) extensionController=\(extensionRuntimeControllerDescription(extensionController)) willAssign=false"
        )

        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        installExternallyConnectableNativeBridgeIfNeeded(
            into: webView.configuration.userContentController
        )
        updateExternallyConnectableNavigationLifecycle(
            for: webView,
            currentURL: currentURL
        )
    }

    func openExtensionWindowUsingTabURLs(
        _ tabURLs: [URL],
        controller: WKWebExtensionController,
        createWindow: @escaping @MainActor () -> Void,
        awaitWindowRegistration: @escaping @MainActor (Set<UUID>) async -> BrowserWindowState?,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        guard let browserManager, let windowRegistry = browserManager.windowRegistry else {
            completionHandler(
                nil,
                NSError(
                    domain: "ExtensionManager",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Browser manager is unavailable"]
                )
            )
            return
        }

        if let firstURL = tabURLs.first,
           OAuthDetector.isLikelyOAuthPopupURL(firstURL),
           let activeWindow = windowRegistry.activeWindow
        {
            let targetSpace = activeWindow.currentSpaceId.flatMap { spaceID in
                browserManager.tabManager.spaces.first(where: { $0.id == spaceID })
            } ?? browserManager.tabManager.currentSpace

            let createdTab = browserManager.tabManager.createNewTab(
                url: firstURL.absoluteString,
                in: targetSpace,
                activate: false
            )

            if Self.isExtensionOwnedURL(firstURL),
               let resolvedContext = controller.extensionContext(for: firstURL)
            {
                createdTab.applyWebViewConfigurationOverride(
                    resolvedContext.webViewConfiguration
                        ?? browserConfiguration.webViewConfiguration
                )
            }

            browserManager.selectTab(createdTab, in: activeWindow)
            completionHandler(windowAdapter(for: activeWindow.id), nil)
            return
        }

        let existingWindowIDs = Set(windowRegistry.windows.keys)
        createWindow()

        Task { @MainActor [weak self, weak browserManager] in
            guard let self, let browserManager else { return }

            guard let windowState = await awaitWindowRegistration(existingWindowIDs) else {
                completionHandler(nil, NSError(
                    domain: "ExtensionManager",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Sumi could not resolve the new window"]
                ))
                return
            }

            let targetSpace = windowState.currentSpaceId.flatMap { spaceID in
                browserManager.tabManager.spaces.first(where: { $0.id == spaceID })
            } ?? browserManager.tabManager.currentSpace

            let createdTab: Tab
            if let firstURL = tabURLs.first {
                createdTab = browserManager.tabManager.createNewTab(
                    url: firstURL.absoluteString,
                    in: targetSpace,
                    activate: false
                )

                if Self.isExtensionOwnedURL(firstURL),
                   let resolvedContext = controller.extensionContext(for: firstURL)
                {
                    createdTab.applyWebViewConfigurationOverride(
                        resolvedContext.webViewConfiguration
                            ?? browserConfiguration.webViewConfiguration
                    )
                }
            } else {
                createdTab = browserManager.tabManager.createNewTab(
                    in: targetSpace,
                    activate: false
                )
            }

            browserManager.selectTab(createdTab, in: windowState)
            completionHandler(self.windowAdapter(for: windowState.id), nil)
        }
    }

    func presentOptionsPageWindow(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let displayName =
            extensionContext.webExtension.displayName ?? "Extension"
        guard let extensionId = extensionID(for: extensionContext),
              let installedExtension = installedExtensions.first(where: { $0.id == extensionId })
        else {
            completionHandler(ExtensionUtils.optionsPageNotFoundError())
            return
        }

        let extensionRoot = URL(
            fileURLWithPath: installedExtension.packagePath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        let manifest = loadedExtensionManifests[extensionId] ?? installedExtension.manifest

        let diskResolvedURL = try? ExtensionUtils.resolvedOptionsPageURL(
            sdkURL: nil,
            persistedPath: installedExtension.optionsPagePath,
            manifest: manifest,
            extensionRoot: extensionRoot
        )

        let sdkURL = extensionContext.optionsPageURL
        let manifestURL = computeOptionsPageURL(for: extensionContext)
        let optionsURL: URL?
        if let diskResolvedURL {
            optionsURL = diskResolvedURL
        } else if let sdkURL {
            optionsURL = sdkURL
        } else if let manifestURL {
            optionsURL = manifestURL
        } else {
            optionsURL = nil
        }

        guard let optionsURL else {
            completionHandler(ExtensionUtils.optionsPageNotFoundError())
            return
        }

        let baseConfiguration =
            extensionContext.webViewConfiguration
            ?? browserConfiguration.webViewConfiguration
        let configuration = browserConfiguration.isolatedWebViewConfigurationCopy(
            from: baseConfiguration,
            websiteDataStore: baseConfiguration.websiteDataStore
        )
        prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            reason: "ExtensionManager.openOptionsPage.configuration"
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        if RuntimeDiagnostics.isDeveloperInspectionEnabled {
            webView.isInspectable = true
        }
        webView.allowsBackForwardNavigationGestures = true
        prepareWebViewForExtensionRuntime(
            webView,
            currentURL: optionsURL,
            reason: "ExtensionManager.openOptionsPage"
        )

        if optionsURL.isFileURL {
            do {
                let validatedOptionsURL = try ExtensionUtils.validatedExtensionPageURL(
                    optionsURL,
                    within: extensionRoot
                )
                webView.loadFileURL(
                    validatedOptionsURL,
                    allowingReadAccessTo: extensionRoot
                )
            } catch {
                completionHandler(error)
                return
            }
        } else {
            webView.load(URLRequest(url: optionsURL))
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(displayName) – Options"

        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container
        window.center()

        closeOptionsWindow(for: extensionId)
        optionsWindows[extensionId] = window
        window.orderFront(nil)

        completionHandler(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        isPopupActive = false
    }

    private func removeAnchorObservers(for extensionId: String) {
        guard let tokens = anchorObserverTokens.removeValue(forKey: extensionId) else {
            return
        }

        for (_, token) in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func pruneActionAnchors(
        for extensionId: String,
        keeping anchorView: NSView? = nil
    ) {
        guard var anchors = actionAnchors[extensionId] else {
            return
        }

        anchors.removeAll { anchor in
            guard let view = anchor.view else { return true }
            if let anchorView, view === anchorView {
                return false
            }
            return anchor.window == nil || view.window == nil
        }

        if anchors.isEmpty {
            actionAnchors.removeValue(forKey: extensionId)
        } else {
            actionAnchors[extensionId] = anchors
        }

        let liveViewIDs = Set(anchors.compactMap { anchor -> ObjectIdentifier? in
            guard let view = anchor.view else { return nil }
            return ObjectIdentifier(view)
        })
        let keptViewID = anchorView.map(ObjectIdentifier.init)

        guard var tokens = anchorObserverTokens[extensionId] else {
            return
        }

        for viewID in Array(tokens.keys) {
            guard liveViewIDs.contains(viewID) == false,
                  viewID != keptViewID
            else {
                continue
            }
            if let token = tokens.removeValue(forKey: viewID) {
                NotificationCenter.default.removeObserver(token)
            }
        }

        if tokens.isEmpty {
            anchorObserverTokens.removeValue(forKey: extensionId)
        } else {
            anchorObserverTokens[extensionId] = tokens
        }
    }

    private func enforceActionAnchorLimit(
        for extensionId: String,
        keeping anchorView: NSView
    ) {
        let maxAnchors = 32
        guard var anchors = actionAnchors[extensionId],
              anchors.count > maxAnchors else {
            return
        }

        var removedViewIDs: [ObjectIdentifier] = []
        while anchors.count > maxAnchors {
            guard let removalIndex = anchors.firstIndex(where: { anchor in
                guard let view = anchor.view else { return true }
                return view !== anchorView
            }) else {
                break
            }

            if let view = anchors[removalIndex].view {
                removedViewIDs.append(ObjectIdentifier(view))
            }
            anchors.remove(at: removalIndex)
        }

        actionAnchors[extensionId] = anchors

        guard var tokens = anchorObserverTokens[extensionId] else {
            return
        }

        for viewID in removedViewIDs {
            if let token = tokens.removeValue(forKey: viewID) {
                NotificationCenter.default.removeObserver(token)
            }
        }

        if tokens.isEmpty {
            anchorObserverTokens.removeValue(forKey: extensionId)
        } else {
            anchorObserverTokens[extensionId] = tokens
        }
    }

    private func showErrorAlert(_ error: ExtensionError) {
        let alert = NSAlert()
        alert.messageText = "Extension Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
