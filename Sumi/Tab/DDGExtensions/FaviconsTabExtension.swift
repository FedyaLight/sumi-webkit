import AppKit
import Combine
import Foundation
import WebKit

/**
 * Sumi favicon tab bridge.
 * Receives bounded live discovery from the favicon user script and publishes
 * already prepared v2 images back to the tab/UI layer.
 */
@MainActor
final class FaviconsTabExtension {
    private weak var tab: Tab?
    private weak var faviconUserScript: SumiFaviconUserScript?
    private var cancellables = Set<AnyCancellable>()
    private var faviconHandlingTask: Task<Void, Never>? {
        willSet {
            faviconHandlingTask?.cancel()
        }
    }
    private var cachedFaviconLoadingTask: Task<Void, Never>? {
        willSet {
            cachedFaviconLoadingTask?.cancel()
        }
    }

    @Published private(set) var favicon: NSImage?

    init(
        scriptsPublisher: some Publisher<SumiFaviconUserScripts, Never>,
        tab: Tab
    ) {
        self.tab = tab

        scriptsPublisher
            .sink { [weak self] scripts in
                guard let self else { return }
                self.faviconUserScript = scripts.faviconScript
                self.faviconUserScript?.delegate = self
            }
            .store(in: &cancellables)
    }

    func loadCachedFavicon(previousURL: URL?, error: Error?) {
        guard let tab, error == nil else { return }
        let currentURL = tab.existingWebView?.url ?? tab.url

        let partition = SumiFaviconSystem.shared.partition(profile: tab.resolveProfile())
        if let cachedFavicon = TabFaviconStore.getCachedImage(
            forDocumentURL: currentURL,
            partition: partition,
            context: .tabSidebar
        ) {
            if cachedFavicon != favicon {
                favicon = cachedFavicon
            }
        } else if previousURL?.host != currentURL.host {
            favicon = nil
        }

        cachedFaviconLoadingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let cachedFavicon = await TabFaviconStore.loadCachedDisplayImage(
                forDocumentURL: currentURL,
                partition: partition,
                context: .tabSidebar,
                priority: .visibleSidebarOrTabStrip
            ) else { return }
            guard let tab = self.tab,
                  currentURL == (tab.existingWebView?.url ?? tab.url) else { return }

            if cachedFavicon != self.favicon {
                self.favicon = cachedFavicon
            }
        }
    }

    deinit {
        faviconHandlingTask?.cancel()
        cachedFaviconLoadingTask?.cancel()
    }

    var faviconPublisher: AnyPublisher<NSImage?, Never> {
        $favicon.dropFirst().eraseToAnyPublisher()
    }
}

extension FaviconsTabExtension: SumiFaviconUserScriptDelegate {
    func faviconUserScript(
        _ faviconUserScript: SumiFaviconUserScript,
        didFindFaviconLinks faviconLinks: [SumiFaviconUserScript.FaviconLink],
        documentUrl: URL,
        baseURL: URL?,
        in webView: WKWebView?
    ) {
        guard let tab else { return }
        let currentURL = tab.existingWebView?.url ?? tab.url
        guard Self.documentURL(documentUrl, matches: currentURL) else { return }

        faviconHandlingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let partition = SumiFaviconSystem.shared.partition(profile: tab.resolveProfile())
            let image = await SumiFaviconSystem.shared.service.ingestVisibleTabDiscovery(
                links: faviconLinks.map(\.discoveredLink),
                documentURL: documentUrl,
                baseURL: baseURL,
                partition: partition,
                webView: webView,
                aliasPageURLs: self.aliasPageURLs(for: tab, currentURL: currentURL)
            )
            if let image,
               !Task.isCancelled,
               let tab = self.tab,
               Self.documentURL(documentUrl, matches: tab.existingWebView?.url ?? tab.url) {
                self.favicon = image
            }
        }
    }

    nonisolated static func documentURL(_ documentURL: URL, matches currentURL: URL) -> Bool {
        SumiFaviconCanonicalURL.equivalentPageURLs(documentURL, currentURL)
    }

    private func aliasPageURLs(for tab: Tab, currentURL: URL) -> [URL] {
        var urls = [currentURL, tab.url]
        if let shortcutPinId = tab.shortcutPinId,
           let launchURL = tab.browserManager?.tabManager.shortcutPin(by: shortcutPinId)?.launchURL {
            urls.append(launchURL)
        }

        var seen = Set<String>()
        return urls.filter { url in
            let key = SumiFaviconCanonicalURL.pageKey(for: url)
            return seen.insert(key).inserted
        }
    }
}
