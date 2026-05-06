//
//  FaviconManager.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Bookmarks
import Cocoa
import Combine
import CoreImage
import os.log
import Persistence
import WebKit

@MainActor
protocol FaviconDownloading: AnyObject, Sendable {
    func download(from url: URL, using webView: WKWebView?) async throws -> Data
}

protocol FaviconManagement: AnyObject {

    @MainActor
    var isCacheLoaded: Bool { get }

    @MainActor
    func handleFaviconLinks(_ faviconLinks: [SumiDDGFaviconUserScript.FaviconLink], documentUrl: URL, webView: WKWebView?) async -> Favicon?

    @MainActor
    func getCachedFavicon(for documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon?

    @MainActor
    func getCachedFavicon(forHostOrAnySubdomain domain: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon?
}

final class FaviconManager: FaviconManagement {

    enum CacheType {
        case standard(_ database: CoreDataDatabase)
        case inMemory
    }

    private(set) var store: FaviconStoring

    private let bookmarkManager: BookmarkManager
    private let faviconDownloader: any FaviconDownloading
    private let recoveryStorage: FaviconManagerRecoveryStorage

    @Published private var faviconsLoaded = false

    var isCacheLoaded: Bool {
        imageCache.loaded && referenceCache.loaded
    }

    @MainActor
    init(
        cacheType: CacheType,
        bookmarkManager: BookmarkManager,
        fireproofDomains: FireproofDomains,
        privacyConfigurationManager: any SumiPrivacyConfigurationManaging,
        imageCache: ((FaviconStoring) -> FaviconImageCaching)? = nil,
        referenceCache: ((FaviconStoring) -> FaviconReferenceCaching)? = nil
    ) {
        switch cacheType {
        case .standard(let database):
            store = FaviconStore(database: database)
        case .inMemory:
            store = FaviconNullStore()
        }
        self.bookmarkManager = bookmarkManager
        self.faviconDownloader = FaviconDownloader(privacyConfigurationManager: privacyConfigurationManager)
        self.recoveryStorage = FaviconManagerRecoveryStorage(storing: store)
        self.imageCache = imageCache?(store) ?? FaviconImageCache(faviconStoring: store)
        self.referenceCache = referenceCache?(store) ?? FaviconReferenceCache(faviconStoring: store)

        Task {
            await loadFaviconsRecoveringIfNeeded(fireproofDomains)
        }
    }

    @MainActor
    private func loadFaviconsRecoveringIfNeeded(_ fireproofDomains: FireproofDomains) async {
        do {
            try await loadFavicons(fireproofDomains)
        } catch {
            Logger.favicons.error("Favicon cache load failed, resetting store: \(error.localizedDescription)")

            do {
                try await recoveryStorage.clearAll()
            } catch {
                Logger.favicons.error("Favicon store reset failed: \(error.localizedDescription)")
            }

            await imageCache.clearAllInMemory(markLoaded: true)
            await referenceCache.clearAllInMemory(markLoaded: true)

            do {
                try await loadFavicons(fireproofDomains)
            } catch {
                Logger.favicons.error("Favicon cache reload after reset failed: \(error.localizedDescription)")
                faviconsLoaded = true
            }
        }
    }

    @MainActor
    private func loadFavicons(_ fireproofDomains: FireproofDomains) async throws {
        try await imageCache.load()
        await imageCache.cleanOld(except: fireproofDomains, bookmarkManager: bookmarkManager)
        try await referenceCache.load()
        await referenceCache.cleanOld(except: fireproofDomains, bookmarkManager: bookmarkManager)
        faviconsLoaded = true
    }

    @MainActor
    private func awaitFaviconsLoaded() async {
        if faviconsLoaded { return }
        await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = $faviconsLoaded
                .filter { $0 }
                .first()
                .sink { _ in
                    cancellable?.cancel()
                    cancellable = nil
                    continuation.resume(returning: ())
                }
        }
    }

    @MainActor
    func waitUntilLoaded() async {
        await awaitFaviconsLoaded()
    }

    // MARK: - Fetching & Cache

    private let imageCache: FaviconImageCaching
    private let referenceCache: FaviconReferenceCaching

    @MainActor
    func handleFaviconLinks(_ faviconLinks: [SumiDDGFaviconUserScript.FaviconLink], documentUrl: URL, webView: WKWebView?) async -> Favicon? {
        await awaitFaviconsLoaded()
        guard !Task.isCancelled else { return nil }

        let faviconLinkSnapshots = faviconLinks.map(FaviconLinkSnapshot.init)

        // If we have links from the page, try those first
        // Fetch favicons if needed
        var faviconLinksToFetch = filteringAlreadyFetchedFaviconLinks(from: faviconLinkSnapshots)
        var newFavicons = await fetchFavicons(faviconLinks: faviconLinksToFetch, documentUrl: documentUrl, webView: webView)
        if let favicon = await cacheFavicons(newFavicons, faviconURLs: faviconLinkSnapshots.map(\.href), for: documentUrl) {
            return favicon
        }
        guard !Task.isCancelled else { return nil }

        // If main links failed or were empty, try fallback
        let fallbackLinks = fallbackFaviconLinks(for: documentUrl)
        faviconLinksToFetch = filteringAlreadyFetchedFaviconLinks(from: fallbackLinks)
        newFavicons = await fetchFavicons(faviconLinks: faviconLinksToFetch, documentUrl: documentUrl, webView: webView)
        return await cacheFavicons(newFavicons, faviconURLs: fallbackLinks.lazy.map(\.href), for: documentUrl)
    }

    @MainActor
    func image(forLookupKey key: String) -> NSImage? {
        guard let documentURL = SumiFaviconLookupKey.documentURL(for: key) else { return nil }

        if let favicon = getCachedFavicon(for: documentURL, sizeCategory: .small, fallBackToSmaller: true) {
            return favicon.image
        }

        guard let host = documentURL.host else { return nil }
        return getCachedFavicon(for: host, sizeCategory: .small, fallBackToSmaller: true)?.image
    }

    @MainActor
    @discardableResult private func handleFaviconReferenceCacheInsertion(documentURL: URL, cachedFavicons: [Favicon], newFavicons: [Favicon]) async -> Favicon? {
        let noFaviconPickedYet = referenceCache.getFaviconUrl(for: documentURL, sizeCategory: .small) == nil
        let currentFavicon: Favicon? = {
            guard let currentSmallFaviconUrl = referenceCache.getFaviconUrl(for: documentURL, sizeCategory: .small) else {
                return nil
            }
            return imageCache.get(faviconUrl: currentSmallFaviconUrl)
        }()
        if cachedFavicons.isEmpty, newFavicons.isEmpty {
            return currentFavicon
        }
        let newFaviconLoaded = !newFavicons.isEmpty
        let currentSmallFaviconUrl = referenceCache.getFaviconUrl(for: documentURL, sizeCategory: .small)
        let currentMediumFaviconUrl = referenceCache.getFaviconUrl(for: documentURL, sizeCategory: .medium)
        let cachedFaviconUrls = cachedFavicons.map { $0.url }
        let faviconsOutdated: Bool = {
            if let currentSmallFaviconUrl = currentSmallFaviconUrl, !cachedFaviconUrls.contains(currentSmallFaviconUrl) {
                return true
            }
            if let currentMediumFaviconUrl = currentMediumFaviconUrl, !cachedFaviconUrls.contains(currentMediumFaviconUrl) {
                return true
            }
            return false
        }()

        // If we haven't pick a favicon yet or there is a new favicon loaded or favicons are outdated
        // Pick the most suitable favicons. Otherwise use cached references
        if noFaviconPickedYet || newFaviconLoaded || faviconsOutdated {
            let sortedCachedFavicons = cachedFavicons.sorted(by: { $0.longestSide < $1.longestSide })
            let mediumFavicon = FaviconSelector.getMostSuitableFavicon(for: .medium, favicons: sortedCachedFavicons)
            let smallFavicon = FaviconSelector.getMostSuitableFavicon(for: .small, favicons: sortedCachedFavicons)
            referenceCache.insert(faviconUrls: (smallFavicon?.url, mediumFavicon?.url), documentUrl: documentURL)
            return smallFavicon
        } else {
            return currentFavicon
        }
    }

    func getCachedFavicon(for documentUrl: URL, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? {
        guard let faviconURL = referenceCache.getFaviconUrl(for: documentUrl, sizeCategory: sizeCategory) else {
            guard fallBackToSmaller, let smallerSizeCategory = sizeCategory.smaller else {
                return nil
            }
            return getCachedFavicon(for: documentUrl, sizeCategory: smallerSizeCategory, fallBackToSmaller: fallBackToSmaller)
        }

        return imageCache.get(faviconUrl: faviconURL)
    }

    @MainActor
    func getCachedFavicon(for host: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? {
        guard let faviconUrl = referenceCache.getFaviconUrl(for: host, sizeCategory: sizeCategory) else {
            guard fallBackToSmaller, let smallerSizeCategory = sizeCategory.smaller else {
                return nil
            }
            return getCachedFavicon(for: host, sizeCategory: smallerSizeCategory, fallBackToSmaller: fallBackToSmaller)
        }

        return imageCache.get(faviconUrl: faviconUrl)
    }

    func getCachedFavicon(forHostOrAnySubdomain domain: String, sizeCategory: Favicon.SizeCategory, fallBackToSmaller: Bool) -> Favicon? {
        if let favicon = getCachedFavicon(for: domain, sizeCategory: sizeCategory, fallBackToSmaller: fallBackToSmaller) {
            return favicon
        }

        let availableSubdomains = referenceCache.hostReferences.keys + referenceCache.urlReferences.keys.compactMap { $0.host }
        let subdomain = availableSubdomains.first { subdomain in
            subdomain.hasSuffix(domain)
        }

        if let subdomain {
            return getCachedFavicon(for: subdomain, sizeCategory: sizeCategory, fallBackToSmaller: fallBackToSmaller)
        }
        return nil
    }

    // MARK: - Burning

    @MainActor
    func burn(except fireproofDomains: FireproofDomains, bookmarkManager: BookmarkManager, savedLogins: Set<String> = []) async -> Result<Void, Error> {
        await referenceCache.burn(except: fireproofDomains, bookmarkManager: bookmarkManager, savedLogins: savedLogins)
        return await imageCache.burn(except: fireproofDomains, bookmarkManager: bookmarkManager, savedLogins: savedLogins)
    }

    @MainActor
    func burnDomains(_ baseDomains: Set<String>,
                     exceptBookmarks bookmarkManager: BookmarkManager,
                     exceptSavedLogins: Set<String> = [],
                     exceptExistingHistoryHosts existingHistoryDomains: Set<String>,
                     registrableDomainResolver: any SumiRegistrableDomainResolving) async -> Result<Void, Error> {
        await referenceCache.burnDomains(baseDomains, exceptBookmarks: bookmarkManager,
                                         exceptSavedLogins: exceptSavedLogins,
                                         exceptHistoryDomains: existingHistoryDomains,
                                         registrableDomainResolver: registrableDomainResolver)
        return await imageCache.burnDomains(baseDomains,
                                            exceptBookmarks: bookmarkManager,
                                            exceptSavedLogins: exceptSavedLogins,
                                            exceptHistoryDomains: existingHistoryDomains,
                                            registrableDomainResolver: registrableDomainResolver)
    }

    // MARK: - Private

    private func fallbackFaviconLinks(for documentUrl: URL) -> [FaviconLinkSnapshot] {
        guard let root = documentUrl.sumiRoot else { return [] }
        var result = [FaviconLinkSnapshot]()
        if [.https, .http].contains(documentUrl.sumiNavigationalScheme) {
            result.append(FaviconLinkSnapshot(href: root.sumiAppending("favicon.ico"), rel: "favicon.ico"))
        }
        if documentUrl.sumiNavigationalScheme == .http, let upgradedRoot = root.sumiToHttps() {
            result.append(FaviconLinkSnapshot(href: upgradedRoot.sumiAppending("favicon.ico"), rel: "favicon.ico"))
        }
        return result
    }

    @MainActor
    private func filteringAlreadyFetchedFaviconLinks(from faviconLinks: [FaviconLinkSnapshot]) -> [FaviconLinkSnapshot] {
        guard !faviconLinks.isEmpty else { return [] }

        let urlsToLinks = faviconLinks.reduce(into: [URL: FaviconLinkSnapshot]()) { result, faviconLink in
            result[faviconLink.href] = faviconLink
        }
        let weekAgo = Date.sumiWeekAgo
        let faviconURLs = Array(urlsToLinks.keys)
        let cachedFavicons = imageCache.getFavicons(with: faviconURLs)?
            .filter { favicon in
                favicon.dateCreated > weekAgo
            } ?? []
        let cachedUrls = Set(cachedFavicons.map(\.url))

        let nonCachedFavicons = urlsToLinks.filter { url, _ in
            !cachedUrls.contains(url)
        }.values

        return Array(nonCachedFavicons)
    }

    @MainActor
    private func fetchFavicons(faviconLinks: [FaviconLinkSnapshot], documentUrl: URL, webView: WKWebView?) async -> [Favicon] {
        guard !faviconLinks.isEmpty else { return [] }

        return await withTaskGroup(of: FaviconDownloadResult?.self, isolation: MainActor.shared) { [faviconDownloader] group in
            for faviconLink in faviconLinks {
                let faviconUrl = faviconLink.href
                let relationString = faviconLink.rel
                group.addTask {
                    await Self.downloadFavicon(
                        faviconUrl: faviconUrl,
                        relationString: relationString,
                        documentUrl: documentUrl,
                        webView: webView,
                        faviconDownloader: faviconDownloader
                    )
                }
            }
            var favicons = [Favicon]()
            for await result in group {
                guard !Task.isCancelled else {
                    return []
                }
                guard let result else {
                    continue
                }
                guard let image = NSImage(dataUsingCIImage: result.data) else {
                    Logger.favicons.error("Error downloading Favicon from \(result.faviconUrl.absoluteString): \(CocoaError(.fileReadCorruptFile).localizedDescription)")
                    continue
                }
                favicons.append(Favicon(identifier: UUID(),
                                        url: result.faviconUrl,
                                        image: image,
                                        relationString: result.relationString,
                                        documentUrl: result.documentUrl,
                                        dateCreated: Date()))
            }

            return favicons
        }
    }

    @MainActor
    private static func downloadFavicon(faviconUrl: URL,
                                        relationString: String,
                                        documentUrl: URL,
                                        webView: WKWebView?,
                                        faviconDownloader: any FaviconDownloading) async -> FaviconDownloadResult? {
        do {
            try Task.checkCancellation()

            let data = try await faviconDownloader.download(from: faviconUrl, using: webView)

            try Task.checkCancellation()

            guard FaviconPayloadValidator.isLikelyValidImageData(data) else {
                throw URLError(.zeroByteResource, userInfo: [NSURLErrorKey: faviconUrl])
            }
            return FaviconDownloadResult(
                faviconUrl: faviconUrl,
                relationString: relationString,
                documentUrl: documentUrl,
                data: data
            )
        } catch {
            Logger.favicons.error("Error downloading Favicon from \(faviconUrl.absoluteString): \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    @discardableResult private func cacheFavicons(_ favicons: [Favicon], faviconURLs: [URL], for documentUrl: URL) async -> Favicon? {
        // Insert new favicons to cache
        imageCache.insert(favicons)
        // Pick most suitable favicons
        let cachedFavicons = imageCache.getFavicons(with: faviconURLs)?.filter { $0.dateCreated > Date.sumiWeekAgo }

        return await handleFaviconReferenceCacheInsertion(
            documentURL: documentUrl,
            cachedFavicons: cachedFavicons ?? [],
            newFavicons: favicons
        )
    }
}

private struct FaviconLinkSnapshot: Sendable {
    let href: URL
    let rel: String

    init(href: URL, rel: String) {
        self.href = href
        self.rel = rel
    }

    init(_ faviconLink: SumiDDGFaviconUserScript.FaviconLink) {
        self.init(href: faviconLink.href, rel: faviconLink.rel)
    }
}

private struct FaviconDownloadResult: Sendable {
    let faviconUrl: URL
    let relationString: String
    let documentUrl: URL
    let data: Data
}

// The concrete favicon stores perform their async work through their own
// storage queues; recovery only needs that serialized clear operation without
// capturing the main-actor manager or cache objects across a suspension point.
private final class FaviconManagerRecoveryStorage: @unchecked Sendable {

    private let storing: FaviconStoring

    init(storing: FaviconStoring) {
        self.storing = storing
    }

    func clearAll() async throws {
        try await storing.clearAll()
    }
}

@MainActor
extension FaviconManager: Bookmarks.FaviconStoring {

    func hasFavicon(for domain: String) -> Bool {
        guard let url = SumiFaviconLookupKey.documentURL(for: domain),
              let faviconURL = self.referenceCache.getFaviconUrl(for: url, sizeCategory: .small) else {
            return false
        }
        return self.imageCache.get(faviconUrl: faviconURL) != nil
    }

    func storeFavicon(_ imageData: Data, with url: URL?, for documentURL: URL) async throws {
        guard let image = NSImage(data: imageData) else {
            return
        }

        await self.awaitFaviconsLoaded()

        // If URL is not provided, we don't know the favicon URL,
        // so we use a made up URL that identifies sync-related favicon.
        let faviconURL = url ?? documentURL.appendingPathComponent("ddgsync-favicon.ico")

        let favicon = Favicon(identifier: UUID(),
                              url: faviconURL,
                              image: image,
                              relationString: "favicon",
                              documentUrl: documentURL,
                              dateCreated: Date())

        await cacheFavicons([favicon], faviconURLs: [faviconURL], for: documentURL)
        NotificationCenter.default.post(name: .faviconCacheUpdated, object: nil)
    }
}

fileprivate extension NSImage {
    /**
     * This function attempts to initialize `NSImage` from `CIImage`.
     *
     * This helps to preserve transparency on some PNG images, and fixes
     * storing `NSImage` initialized with `ico` files in NSKeyedArchiver.
     */
    convenience init?(dataUsingCIImage data: Data) {
        guard let ciImage = CIImage(data: data) else {
            self.init(data: data)
            return
        }
        let rep = NSCIImageRep(ciImage: ciImage)
        self.init(size: rep.size)
        addRepresentation(rep)
    }
}

private enum FaviconPayloadValidator {
    static func isLikelyValidImageData(_ data: Data) -> Bool {
        guard data.count > 8 else { return false }

        let prefix = data.prefix(32)
        let textPrefix = data.prefix(512)

        if isHTML(textPrefix) || isPlainText(textPrefix) {
            return false
        }

        if isSVG(textPrefix) {
            return true
        }

        if isXML(textPrefix) {
            return false
        }

        return hasKnownImageMagic(prefix) || looksLikeICO(data)
    }

    private static func hasKnownImageMagic(_ prefix: Data) -> Bool {
        let signatures: [[UInt8]] = [
            [0x89, 0x50, 0x4E, 0x47],
            [0xFF, 0xD8, 0xFF],
            [0x47, 0x49, 0x46, 0x38],
            [0x52, 0x49, 0x46, 0x46],
            [0x42, 0x4D]
        ]

        return signatures.contains { signature in
            prefix.starts(with: signature)
        }
    }

    private static func looksLikeICO(_ data: Data) -> Bool {
        guard data.count >= 6 else { return false }
        let bytes = Array(data.prefix(6))
        return bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0x01 && bytes[3] == 0x00
    }

    private static func isHTML(_ prefix: Data) -> Bool {
        let ascii = lowercasedASCII(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
        return ascii.hasPrefix("<!doctype") || ascii.hasPrefix("<html")
    }

    private static func isXML(_ prefix: Data) -> Bool {
        lowercasedASCII(prefix).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<?xml")
    }

    private static func isSVG(_ prefix: Data) -> Bool {
        lowercasedASCII(prefix).contains("<svg")
    }

    private static func isPlainText(_ prefix: Data) -> Bool {
        let ascii = lowercasedASCII(prefix).trimmingCharacters(in: .whitespacesAndNewlines)
        return ascii.hasPrefix("http") || ascii.hasPrefix("{") || ascii.hasPrefix("[")
    }

    private static func lowercasedASCII(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).lowercased()
    }
}
