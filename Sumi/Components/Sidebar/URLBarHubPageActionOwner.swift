import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import WebKit

@MainActor
final class URLBarHubPageActionOwner: ObservableObject {
    @Published private(set) var isCapturingScreenshot = false

    let shareButtonAnchor = URLBarHubShareAnchorStore()

    func shareCurrentPage(
        currentTab: Tab?,
        browserManager: BrowserManager,
        windowState: BrowserWindowState
    ) {
        guard let url = currentTab?.url else { return }

        let source = windowState.sidebarTransientSessionCoordinator.preparedPresentationSource(
            window: windowState.window,
            ownerView: shareButtonAnchor.view
        )
        browserManager.presentSharingServicePicker([url], source: source)
    }

    func captureCurrentPageUsingSavedSettings(
        currentTab: Tab?,
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        options: URLBarHubScreenshotOptions
    ) {
        guard let target = captureTarget(
            currentTab: currentTab,
            browserManager: browserManager,
            windowState: windowState
        ) else { return }

        captureCurrentPage(
            currentTab: target.tab,
            webView: target.webView,
            options: options,
            window: windowState.window
        )
    }

    func presentScreenshotSettings(
        currentTab: Tab?,
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        options: URLBarHubScreenshotOptions,
        persistOptions: @escaping @MainActor (URLBarHubScreenshotOptions) -> Void
    ) {
        guard let target = captureTarget(
            currentTab: currentTab,
            browserManager: browserManager,
            windowState: windowState
        ) else { return }

        URLBarHubScreenshotSettingsPresenter.present(
            initial: options,
            window: windowState.window
        ) { selectedOptions in
            guard let selectedOptions else { return }
            persistOptions(selectedOptions)
            self.captureCurrentPage(
                currentTab: target.tab,
                webView: target.webView,
                options: selectedOptions,
                window: windowState.window
            )
        }
    }

    private func captureTarget(
        currentTab: Tab?,
        browserManager: BrowserManager,
        windowState: BrowserWindowState
    ) -> (tab: Tab, webView: WKWebView)? {
        guard let currentTab,
              let webView = browserManager.getWebView(
                for: currentTab.id,
                in: windowState.id
              ),
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
