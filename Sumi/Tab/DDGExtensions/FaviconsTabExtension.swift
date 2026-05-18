import AppKit
import Combine
import Foundation
import WebKit

/**
 * Port of DDG `FaviconsTabExtension`, adapted to Sumi's `Tab` model.
 *
 * The ownership boundary stays the same as DDG:
 * - load cached favicon or placeholder from the shared favicon backend
 * - receive live favicon links only through `SumiDDGFaviconUserScript`
 * - publish the resolved favicon back to the tab/UI layer
 */
@MainActor
final class FaviconsTabExtension {
    let faviconManagement: FaviconManagement

    private weak var tab: Tab?
    private weak var faviconUserScript: SumiDDGFaviconUserScript?
    private let registrableDomainResolver: any SumiRegistrableDomainResolving
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
        scriptsPublisher: some Publisher<SumiDDGFaviconUserScripts, Never>,
        tab: Tab,
        faviconManagement: FaviconManagement,
        registrableDomainResolver: any SumiRegistrableDomainResolving = SumiRegistrableDomainResolver()
    ) {
        self.tab = tab
        self.faviconManagement = faviconManagement
        self.registrableDomainResolver = registrableDomainResolver

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

        if faviconManagement.isCacheLoaded {
            if let cachedFavicon = displayImage(from: cachedDisplayFavicon(for: currentURL)) {
                if cachedFavicon != favicon {
                    favicon = cachedFavicon
                }
            } else if previousURL?.host != currentURL.host {
                favicon = nil
            }
        }

        cachedFaviconLoadingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let cachedFavicon = displayImage(from: await loadCachedDisplayFavicon(for: currentURL)) else { return }
            guard let tab = self.tab,
                  currentURL == (tab.existingWebView?.url ?? tab.url) else { return }

            if cachedFavicon != self.favicon {
                self.favicon = cachedFavicon
            }
        }
    }

    private func cachedDisplayFavicon(for currentURL: URL) -> Favicon? {
        faviconManagement.getCachedDisplayFavicon(
            for: currentURL,
            baseDomain: registrableDomainResolver.registrableDomain(forHost: currentURL.host),
            targetPixelSize: CGFloat(SumiFaviconImagePolicy.maxLauncherDisplayPixelSize)
        )
    }

    private func loadCachedDisplayFavicon(for currentURL: URL) async -> Favicon? {
        await faviconManagement.loadCachedDisplayFavicon(
            for: currentURL,
            baseDomain: registrableDomainResolver.registrableDomain(forHost: currentURL.host),
            targetPixelSize: CGFloat(SumiFaviconImagePolicy.maxLauncherDisplayPixelSize)
        )
    }

    deinit {
        faviconHandlingTask?.cancel()
        cachedFaviconLoadingTask?.cancel()
    }

    var faviconPublisher: AnyPublisher<NSImage?, Never> {
        $favicon.dropFirst().eraseToAnyPublisher()
    }
}

extension FaviconsTabExtension: SumiDDGFaviconUserScriptDelegate {
    func faviconUserScript(
        _ faviconUserScript: SumiDDGFaviconUserScript,
        didFindFaviconLinks faviconLinks: [SumiDDGFaviconUserScript.FaviconLink],
        for documentUrl: URL,
        in webView: WKWebView?
    ) {
        guard let tab else { return }
        let currentURL = tab.existingWebView?.url ?? tab.url
        guard documentUrl == currentURL else { return }

        faviconHandlingTask = Task { [weak self, faviconManagement] in
            guard let self else { return }
            let handledFavicon = await faviconManagement.handleFaviconLinks(
                faviconLinks,
                documentUrl: documentUrl,
                webView: webView
            )
            let displayFavicon = await self.loadCachedDisplayFavicon(for: documentUrl) ?? handledFavicon
            if let image = self.displayImage(from: displayFavicon),
               !Task.isCancelled,
               let tab = self.tab,
               documentUrl == (tab.existingWebView?.url ?? tab.url)
            {
                self.favicon = image
            }
        }
    }

    private func displayImage(from favicon: Favicon?) -> NSImage? {
        favicon?.image?.sumiFaviconImageConstrained(
            maxLongestSide: CGFloat(SumiFaviconImagePolicy.maxLauncherDisplayPixelSize)
        )
    }
}
