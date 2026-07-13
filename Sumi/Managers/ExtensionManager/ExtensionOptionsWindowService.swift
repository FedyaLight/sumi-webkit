import AppKit
import OSLog
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowDelegate: NSObject, NSWindowDelegate, WKUIDelegate {
    private let extensionId: String
    private weak var service: ExtensionOptionsWindowService?
    private weak var webView: WKWebView?
    private weak var window: NSWindow?
    var isCleaningUp = false

    init(
        extensionId: String,
        service: ExtensionOptionsWindowService,
        webView: WKWebView,
        window: NSWindow
    ) {
        self.extensionId = extensionId
        self.service = service
        self.webView = webView
        self.window = window
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        guard isCleaningUp == false else { return }
        service?.cleanupWindow(
            for: extensionId,
            window: notification.object as? NSWindow,
            webView: webView,
            shouldOrderOut: false
        )
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard isCleaningUp == false else { return }
        service?.cleanupWindow(
            for: extensionId,
            window: window,
            webView: webView,
            shouldOrderOut: true
        )
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowService {
    private static let log = Logger.sumi(category: "Extensions")

    private(set) var windows: [String: NSWindow] = [:]
    private var delegates: [String: ExtensionOptionsWindowDelegate] = [:]
    private var profileIDsByExtensionID: [String: UUID] = [:]

    var extensionIDs: Set<String> {
        Set(windows.keys)
    }

    func closeWindow(for extensionId: String) {
        cleanupWindow(
            for: extensionId,
            shouldOrderOut: true
        )
    }

    func closeAllWindows() {
        Array(windows.keys).forEach {
            cleanupWindow(
                for: $0,
                shouldOrderOut: true
            )
        }
    }

    func closeWindows(backedBy profileIDs: Set<UUID>) {
        let extensionIDs = windows.keys.filter { extensionID in
            guard let profileID = profileIDsByExtensionID[extensionID] else {
                // An unclassified profile-store window cannot safely survive
                // any destructive profile mutation.
                return true
            }
            return profileIDs.contains(profileID)
        }
        extensionIDs.forEach {
            cleanupWindow(for: $0, shouldOrderOut: true)
        }
    }

    func cleanupWindow(
        for extensionId: String,
        window: NSWindow? = nil,
        webView: WKWebView? = nil,
        shouldOrderOut: Bool
    ) {
        let resolvedWindow: NSWindow?
        if let window {
            resolvedWindow = window
        } else if let webView {
            let registeredWindow = windows[extensionId]
            if let registeredWindow,
               registeredWindow.contentView.map({
                   firstWebView(in: $0) === webView
               }) == true {
                resolvedWindow = registeredWindow
            } else {
                // A WebKit close callback can arrive after its old window was
                // detached and replaced. It may retire only that exact WebView.
                SumiAuxiliaryWebViewShutdown.perform(on: webView)
                return
            }
        } else {
            resolvedWindow = windows[extensionId]
        }
        guard let resolvedWindow else {
            return
        }

        let ownsRegistration = windows[extensionId] === resolvedWindow
        let delegate = ownsRegistration
            ? delegates[extensionId]
            : resolvedWindow.delegate as? ExtensionOptionsWindowDelegate
        if ownsRegistration {
            windows.removeValue(forKey: extensionId)
            delegates.removeValue(forKey: extensionId)
            profileIDsByExtensionID.removeValue(forKey: extensionId)
        }
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
    }

    func presentOptionsPageWindow(
        for extensionContext: WKWebExtensionContext,
        manager: ExtensionManager,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let displayName =
            extensionContext.webExtension.displayName ?? "Extension"
        guard let extensionId = manager.extensionID(for: extensionContext),
              let installedExtension = manager.installedExtensionCollection.records.first(where: { $0.id == extensionId })
        else {
            completionHandler(ExtensionUtils.optionsPageNotFoundError())
            return
        }

        let extensionRoot = URL(
            fileURLWithPath: installedExtension.packagePath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        let manifest = manager.runtimeSession.loadedExtensionManifests[extensionId] ?? installedExtension.manifest

        let sdkURL = extensionContext.optionsPageURL
        let manifestURL = manager.computeOptionsPageURL(for: extensionContext)
        let optionsURL = Self.preferredOptionsPageURL(
            sdkURL: sdkURL,
            manifestURL: manifestURL,
            persistedPath: installedExtension.optionsPagePath,
            manifest: manifest,
            extensionRoot: extensionRoot,
            extensionId: extensionId
        )

        guard let optionsURL else {
            completionHandler(ExtensionUtils.optionsPageNotFoundError())
            return
        }

        let optionsProfileId =
            manager.profileId(for: extensionContext)
            ?? manager.fallbackProfileId
        if let optionsProfileId,
           manager.runtime.websiteDataMutationAdmissionIsBlocked(optionsProfileId) {
            Task { @MainActor [weak self, weak manager] in
                guard let self, let manager,
                      await manager.runtime.waitForWebsiteDataMutationAdmission(
                          optionsProfileId
                      ) else {
                    completionHandler(CancellationError())
                    return
                }
                self.presentOptionsPageWindow(
                    for: extensionContext,
                    manager: manager,
                    completionHandler: completionHandler
                )
            }
            return
        }
        let configuration: WKWebViewConfiguration
        if let contextConfiguration = extensionContext.webViewConfiguration {
            configuration = contextConfiguration
        } else {
            let baseConfiguration = manager.browserConfiguration.webViewConfiguration
            configuration = manager.browserConfiguration.auxiliaryWebViewConfiguration(
                from: baseConfiguration,
                for: manager.runtime.currentProfile(),
                surface: .extensionOptions,
                additionalUserScripts: baseConfiguration.userContentController.userScripts
            )
        }
        configuration.sumiIsNormalTabWebViewConfiguration = false
        manager.prepareWebViewConfigForExtensionRuntime(
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

        closeWindow(for: extensionId)
        let delegate = ExtensionOptionsWindowDelegate(
            extensionId: extensionId,
            service: self,
            webView: webView,
            window: window
        )
        webView.uiDelegate = delegate
        window.delegate = delegate
        trackPresentedWindow(
            window,
            delegate: delegate,
            for: extensionId,
            profileID: optionsProfileId
        )
        window.orderFront(nil)

        completionHandler(nil)
    }

    func trackPresentedWindow(
        _ window: NSWindow,
        delegate: ExtensionOptionsWindowDelegate?,
        for extensionId: String,
        profileID: UUID? = nil
    ) {
        windows[extensionId] = window
        delegates[extensionId] = delegate
        profileIDsByExtensionID[extensionId] = profileID
    }

    static func preferredOptionsPageURL(
        sdkURL: URL?,
        manifestURL: URL?,
        persistedPath: String?,
        manifest: [String: Any],
        extensionRoot: URL,
        extensionId: String
    ) -> URL? {
        let sdkResolvedURL = resolveOptionsPageURLOrLog(
            sdkURL: sdkURL,
            persistedPath: nil,
            manifest: manifest,
            extensionRoot: extensionRoot,
            extensionId: extensionId,
            source: "SDK or manifest options page"
        )
        let diskResolvedURL = resolveOptionsPageURLOrLog(
            sdkURL: nil,
            persistedPath: persistedPath,
            manifest: manifest,
            extensionRoot: extensionRoot,
            extensionId: extensionId,
            source: "persisted or manifest options page"
        )

        if let sdkResolvedURL {
            return sdkResolvedURL
        }
        if let manifestURL {
            return manifestURL
        }
        return diskResolvedURL
    }

    private static func resolveOptionsPageURLOrLog(
        sdkURL: URL?,
        persistedPath: String?,
        manifest: [String: Any],
        extensionRoot: URL,
        extensionId: String,
        source: String
    ) -> URL? {
        do {
            return try ExtensionUtils.resolvedOptionsPageURL(
                sdkURL: sdkURL,
                persistedPath: persistedPath,
                manifest: manifest,
                extensionRoot: extensionRoot
            )
        } catch {
            log.error(
                "Failed to resolve \(source, privacy: .public) for extension \(extensionId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func firstWebView(in root: NSView) -> WKWebView? {
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
