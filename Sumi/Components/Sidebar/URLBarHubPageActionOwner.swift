import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import WebKit

@MainActor
final class URLBarHubPageActionOwner: ObservableObject {
    @Published private(set) var isCapturingScreenshot = false

    let shareButtonAnchor = URLBarHubShareAnchorStore()
    weak var windowRegistry: WindowRegistry?

    func canCapture(_ page: ActivePageResolution?) -> Bool {
        guard let page,
              page.tab.representsSumiNativeSurface == false,
              page.presentationWebView != nil else {
            return false
        }
        return isCapturingScreenshot == false
    }

    @discardableResult
    func captureUsingSavedSettings(_ page: ActivePageResolution?) -> Bool {
        guard canCapture(page), let page else { return false }
        let options = URLBarHubScreenshotPreferences.options()
        DispatchQueue.main.async { [weak self, weak windowState = page.windowState] in
            guard let self, let windowState,
                  self.canCapture(page),
                  let webView = page.presentationWebView else {
                return
            }
            self.captureCurrentPage(
                currentTab: page.tab,
                webView: webView,
                options: options,
                window: windowState.shellWindow(in: self.windowRegistry)
            )
        }
        return true
    }

    func shareCurrentPage(
        currentTab: Tab?,
        windowState: BrowserWindowState,
        presentSharingServicePicker: ([Any], SidebarTransientPresentationSource) -> Void
    ) {
        guard let url = currentTab?.url else { return }

        let source = windowState.sidebarTransientSessionCoordinator.preparedPresentationSource(
            window: windowState.shellWindow(in: windowRegistry),
            ownerView: shareButtonAnchor.view
        )
        presentSharingServicePicker([url], source)
    }

    func captureCurrentPageUsingSavedSettings(
        currentTab: Tab?,
        windowState: BrowserWindowState,
        webViewProvider: (Tab, BrowserWindowState) -> WKWebView?,
        options: URLBarHubScreenshotOptions
    ) {
        guard let target = captureTarget(
            currentTab: currentTab,
            windowState: windowState,
            webViewProvider: webViewProvider
        ) else { return }

        captureCurrentPage(
            currentTab: target.tab,
            webView: target.webView,
            options: options,
            window: windowState.shellWindow(in: windowRegistry)
        )
    }

    func presentScreenshotSettings(
        currentTab: Tab?,
        windowState: BrowserWindowState,
        webViewProvider: (Tab, BrowserWindowState) -> WKWebView?,
        options: URLBarHubScreenshotOptions,
        themeContext: ResolvedThemeContext? = nil,
        persistOptions: @escaping @MainActor (URLBarHubScreenshotOptions) -> Void
    ) {
        guard let target = captureTarget(
            currentTab: currentTab,
            windowState: windowState,
            webViewProvider: webViewProvider
        ) else { return }

        URLBarHubScreenshotSettingsPresenter.present(
            initial: options,
            window: windowState.shellWindow(in: windowRegistry),
            themeContext: themeContext
        ) { selectedOptions in
            guard let selectedOptions else { return }
            persistOptions(selectedOptions)
            self.captureCurrentPage(
                currentTab: target.tab,
                webView: target.webView,
                options: selectedOptions,
                window: windowState.shellWindow(in: self.windowRegistry)
            )
        }
    }

    private func captureTarget(
        currentTab: Tab?,
        windowState: BrowserWindowState,
        webViewProvider: (Tab, BrowserWindowState) -> WKWebView?
    ) -> (tab: Tab, webView: WKWebView)? {
        guard let currentTab,
              let webView = webViewProvider(currentTab, windowState),
              !isCapturingScreenshot
        else {
            return nil
        }

        return (currentTab, webView)
    }

    private func captureCurrentPage(
        currentTab: Tab,
        webView: WKWebView,
        options: URLBarHubScreenshotOptions,
        window: NSWindow?
    ) {
        guard !isCapturingScreenshot else { return }
        isCapturingScreenshot = true

        switch options.target {
        case .visiblePage:
            saveCurrentPageCapture(
                currentTab: currentTab,
                webView: webView,
                rect: webView.bounds,
                options: options,
                window: window
            )

        case .selectedArea:
            URLBarHubScreenshotRegionSelector.selectRegion(in: webView) { rect in
                guard let rect else {
                    self.isCapturingScreenshot = false
                    return
                }

                self.saveCurrentPageCapture(
                    currentTab: currentTab,
                    webView: webView,
                    rect: rect,
                    options: options,
                    window: window
                )
            }
        }
    }

    private func saveCurrentPageCapture(
        currentTab: Tab,
        webView: WKWebView,
        rect: CGRect,
        options: URLBarHubScreenshotOptions,
        window: NSWindow?
    ) {
        let suggestedFilename = URLBarHubSnapshotActions.suggestedFilename(
            for: currentTab,
            quality: options.scale
        )

        switch options.destination {
        case .askEveryTime:
            askForScreenshotDestination(
                suggestedFilename: suggestedFilename,
                window: window
            ) { destinationURL in
                guard let destinationURL else {
                    self.isCapturingScreenshot = false
                    return
                }

                self.writeCurrentPageCapture(
                    webView: webView,
                    rect: rect,
                    options: options,
                    destinationURL: destinationURL
                )
            }

        case .downloads:
            writeCurrentPageCapture(
                webView: webView,
                rect: rect,
                options: options,
                destinationURL: DownloadFileUtilities.uniqueDestination(for: suggestedFilename)
            )
        }
    }

    private func askForScreenshotDestination(
        suggestedFilename: String,
        window: NSWindow?,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Page Capture"
        savePanel.message = "Choose where to save the page snapshot"
        savePanel.nameFieldStringValue = suggestedFilename
        savePanel.allowedContentTypes = [.png]

        let panelCompletion: (NSApplication.ModalResponse) -> Void = { result in
            guard result == .OK,
                  let destinationURL = savePanel.url else {
                completion(nil)
                return
            }
            completion(destinationURL)
        }

        if let window {
            savePanel.beginSheetModal(for: window, completionHandler: panelCompletion)
        } else {
            savePanel.begin(completionHandler: panelCompletion)
        }
    }

    private func writeCurrentPageCapture(
        webView: WKWebView,
        rect: CGRect,
        options: URLBarHubScreenshotOptions,
        destinationURL: URL
    ) {
        URLBarHubScreenshotCapture.writeVisibleSnapshot(
            of: webView,
            rect: rect,
            quality: options.scale,
            to: destinationURL
        ) { _ in
            self.isCapturingScreenshot = false
        }
    }
}

final class URLBarHubShareAnchorStore {
    weak var view: NSView?
}

struct URLBarHubShareAnchorView: NSViewRepresentable {
    let anchor: URLBarHubShareAnchorStore

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        _ = nsView
    }
}
