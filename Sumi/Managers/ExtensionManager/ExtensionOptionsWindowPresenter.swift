import AppKit
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowDelegate: NSObject, NSWindowDelegate, WKUIDelegate {
    private let extensionId: String
    private weak var manager: ExtensionManager?
    private weak var webView: WKWebView?
    var isCleaningUp = false

    init(
        extensionId: String,
        manager: ExtensionManager,
        webView: WKWebView
    ) {
        self.extensionId = extensionId
        self.manager = manager
        self.webView = webView
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        guard isCleaningUp == false else { return }
        manager?.cleanupOptionsWindow(
            for: extensionId,
            window: notification.object as? NSWindow,
            webView: webView,
            shouldOrderOut: false
        )
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard isCleaningUp == false else { return }
        manager?.cleanupOptionsWindow(
            for: extensionId,
            window: webView.window,
            webView: webView,
            shouldOrderOut: true
        )
    }
}

@available(macOS 15.5, *)
@MainActor
enum ExtensionOptionsWindowPresenter {
    static func closeWindow(
        for extensionId: String,
        manager: ExtensionManager
    ) {
        cleanupWindow(
            for: extensionId,
            manager: manager,
            shouldOrderOut: true
        )
    }

    static func closeAllWindows(manager: ExtensionManager) {
        Array(manager.optionsWindows.keys).forEach {
            cleanupWindow(
                for: $0,
                manager: manager,
                shouldOrderOut: true
            )
        }
    }

    static func cleanupWindow(
        for extensionId: String,
        manager: ExtensionManager,
        window: NSWindow? = nil,
        webView: WKWebView? = nil,
        shouldOrderOut: Bool
    ) {
        guard let resolvedWindow = window ?? manager.optionsWindows[extensionId] else {
            manager.optionsWindowDelegates.removeValue(forKey: extensionId)
            return
        }

        let delegate = manager.optionsWindowDelegates[extensionId]
        delegate?.isCleaningUp = true

        let resolvedWebView = webView ?? resolvedWindow.contentView.flatMap {
            firstWebView(in: $0)
        }
        if let resolvedWebView {
            SumiAuxiliaryWebViewShutdown.perform(on: resolvedWebView)
        }

        if shouldOrderOut {
            resolvedWindow.orderOut(nil)
        }
        resolvedWindow.contentViewController = nil
        resolvedWindow.contentView = nil
        resolvedWindow.delegate = nil
        manager.optionsWindows.removeValue(forKey: extensionId)
        manager.optionsWindowDelegates.removeValue(forKey: extensionId)
    }

    static func presentOptionsPageWindow(
        for extensionContext: WKWebExtensionContext,
        manager: ExtensionManager,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let displayName =
            extensionContext.webExtension.displayName ?? "Extension"
        guard let extensionId = manager.extensionID(for: extensionContext),
              let installedExtension = manager.installedExtensions.first(where: { $0.id == extensionId })
        else {
            completionHandler(ExtensionUtils.optionsPageNotFoundError())
            return
        }

        let extensionRoot = URL(
            fileURLWithPath: installedExtension.packagePath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        let manifest = manager.loadedExtensionManifests[extensionId] ?? installedExtension.manifest

        let sdkURL = extensionContext.optionsPageURL
        let manifestURL = manager.computeOptionsPageURL(for: extensionContext)
        let sdkResolvedURL = (try? ExtensionUtils.resolvedOptionsPageURL(
            sdkURL: sdkURL,
            persistedPath: nil,
            manifest: manifest,
            extensionRoot: extensionRoot
        ))
        let diskResolvedURL = try? ExtensionUtils.resolvedOptionsPageURL(
            sdkURL: nil,
            persistedPath: installedExtension.optionsPagePath,
            manifest: manifest,
            extensionRoot: extensionRoot
        )
        let optionsURL: URL?
        if let sdkResolvedURL {
            optionsURL = sdkResolvedURL
        } else if let manifestURL {
            optionsURL = manifestURL
        } else if let diskResolvedURL {
            optionsURL = diskResolvedURL
        } else {
            optionsURL = nil
        }

        guard let optionsURL else {
            completionHandler(ExtensionUtils.optionsPageNotFoundError())
            return
        }

        let optionsProfileId =
            manager.profileId(for: extensionContext)
            ?? manager.currentProfileId
            ?? manager.browserManager?.currentProfile?.id
        let configuration: WKWebViewConfiguration
        if let contextConfiguration = extensionContext.webViewConfiguration {
            configuration = contextConfiguration
        } else {
            let baseConfiguration = manager.browserConfiguration.webViewConfiguration
            configuration = manager.browserConfiguration.auxiliaryWebViewConfiguration(
                from: baseConfiguration,
                for: manager.browserManager?.currentProfile,
                surface: .extensionOptions,
                additionalUserScripts: baseConfiguration.userContentController.userScripts
            )
        }
        configuration.sumiIsNormalTabWebViewConfiguration = false
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: optionsProfileId,
            reason: "ExtensionManager.openOptionsPage.configuration"
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        if RuntimeDiagnostics.isDeveloperInspectionEnabled {
            webView.isInspectable = true
        }
        webView.allowsBackForwardNavigationGestures = true
        manager.prepareWebViewForExtensionRuntime(
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

        closeWindow(for: extensionId, manager: manager)
        let delegate = ExtensionOptionsWindowDelegate(
            extensionId: extensionId,
            manager: manager,
            webView: webView
        )
        webView.uiDelegate = delegate
        window.delegate = delegate
        manager.optionsWindows[extensionId] = window
        manager.optionsWindowDelegates[extensionId] = delegate
        window.orderFront(nil)

        completionHandler(nil)
    }

    private static func firstWebView(in root: NSView) -> WKWebView? {
        if let webView = root as? WKWebView {
            return webView
        }

        for subview in root.subviews {
            if let webView = firstWebView(in: subview) {
                return webView
            }
        }
        return nil
    }
}
