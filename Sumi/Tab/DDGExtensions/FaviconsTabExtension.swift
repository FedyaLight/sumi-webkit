import AppKit
import Combine
import Foundation
import UserScript
import WebKit

/**
 * Port of DDG `FaviconsTabExtension`, adapted to Sumi's `Tab` model.
 *
 * The ownership boundary stays the same as DDG:
 * - load cached favicon or placeholder from the shared favicon backend
 * - receive live favicon links only through `FaviconUserScript`
 * - publish the resolved favicon back to the tab/UI layer
 */
@MainActor
final class FaviconsTabExtension {
    let faviconManagement: FaviconManagement

    private weak var tab: Tab?
    private weak var faviconUserScript: FaviconUserScript?
    private var cancellables = Set<AnyCancellable>()
    private var faviconHandlingTask: Task<Void, Never>? {
        willSet {
            faviconHandlingTask?.cancel()
        }
    }

    @Published private(set) var favicon: NSImage?

    init(
        scriptsPublisher: some Publisher<SumiDDGFaviconUserScripts, Never>,
        tab: Tab,
        faviconManagement: FaviconManagement
    ) {
        self.tab = tab
        self.faviconManagement = faviconManagement

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

        guard tab.requiresPrimaryWebView else {
            favicon = nil
            return
        }

        guard faviconManagement.isCacheLoaded else { return }

        if let cachedFavicon = faviconManagement.getCachedFavicon(
            forUrlOrAnySubdomain: currentURL,
            sizeCategory: .small,
            fallBackToSmaller: false
        )?.image {
            if cachedFavicon != favicon {
                favicon = cachedFavicon
            }
        } else if previousURL?.host != currentURL.host {
            favicon = nil
        }
    }

    deinit {
        faviconHandlingTask?.cancel()
    }

    var faviconPublisher: AnyPublisher<NSImage?, Never> {
        $favicon.dropFirst().eraseToAnyPublisher()
    }
}

extension FaviconsTabExtension: FaviconUserScriptDelegate {
    func faviconUserScript(
        _ faviconUserScript: FaviconUserScript,
        didFindFaviconLinks faviconLinks: [FaviconUserScript.FaviconLink],
        for documentUrl: URL,
        in webView: WKWebView?
    ) {
        guard let tab else { return }
        let currentURL = tab.existingWebView?.url ?? tab.url
        guard documentUrl == currentURL else { return }

        faviconHandlingTask = Task { [weak self, faviconManagement] in
            guard let self else { return }
            if let favicon = await faviconManagement.handleFaviconLinks(
                faviconLinks,
                documentUrl: documentUrl,
                webView: webView
            ),
               !Task.isCancelled,
               let tab = self.tab,
               documentUrl == (tab.existingWebView?.url ?? tab.url)
            {
                self.favicon = favicon.image
            }
        }
    }
}
