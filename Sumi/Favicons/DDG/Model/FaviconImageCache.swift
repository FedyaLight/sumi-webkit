//
//  FaviconImageCache.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import Foundation
import Combine
import os.log

protocol FaviconImageCaching {

    @MainActor
    var loaded: Bool { get }

    @MainActor
    func load() async throws

    @MainActor
    func insert(_ favicons: [Favicon])

    @MainActor
    func clearAllInMemory(markLoaded: Bool)

    @MainActor
    func get(faviconUrl: URL) -> Favicon?

    @MainActor
    func getFavicons(with urls: some Sequence<URL>) -> [Favicon]?

    @MainActor
    func loadCachedFavicons(with urls: [URL]) async -> [Favicon]

    @MainActor
    func hasCachedFavicon(faviconUrl: URL) -> Bool

    @MainActor
    func cleanOld(bookmarkManager: BookmarkManager) async

    @MainActor
    func burn(bookmarkManager: BookmarkManager, savedLogins: Set<String>) async -> Result<Void, Error>

    @MainActor
    func burnDomains(_ baseDomains: Set<String>,
                     exceptBookmarks bookmarkManager: BookmarkManager,
                     exceptSavedLogins logins: Set<String>,
                     exceptHistoryDomains history: Set<String>,
                     registrableDomainResolver: any SumiRegistrableDomainResolving) async -> Result<Void, Error>
}

final class FaviconImageCache: FaviconImageCaching {

    private static let maximumInMemoryEntries = 192
    private static let maximumInMemoryCost = 24 * 1024 * 1024

    private let storing: FaviconImageCacheStorage

    @MainActor
    private var entries = [URL: Favicon]()

    @MainActor
    private var entryAccessOrder = [URL]()

    @MainActor
    private var entryCosts = [URL: Int]()

    @MainActor
    private var totalEntryCost = 0

    @MainActor
    private var knownFaviconUrls = Set<URL>()

    init(faviconStoring: FaviconStoring) {
        storing = FaviconImageCacheStorage(storing: faviconStoring)
    }

    @MainActor
    private(set) var loaded = false

    @MainActor
    func load() async throws {
        knownFaviconUrls = Set(try await storing.loadFaviconMetadata().map(\.url))
        Logger.favicons.debug("Favicon image cache ready for lazy loading")
        loaded = true
    }

    func insert(_ favicons: [Favicon]) {
        guard !favicons.isEmpty, loaded else {
            return
        }

        for favicon in favicons {
            cache(favicon)
            storeAccentColorIfNeeded(for: favicon)
        }

        let storing = storing

        Task {
            do {
                try await storing.removeFavicons(with: favicons.map(\.url))
                try await storing.save(favicons)
                Logger.favicons.debug("Favicon saved successfully. URL: \(favicons.map(\.url.absoluteString).description)")
                await MainActor.run {
                    NotificationCenter.default.post(name: .faviconCacheUpdated, object: nil)
                }
            } catch {
                Logger.favicons.error("Saving of favicon failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func clearAllInMemory(markLoaded: Bool = true) {
        entries.removeAll(keepingCapacity: false)
        entryAccessOrder.removeAll(keepingCapacity: false)
        entryCosts.removeAll(keepingCapacity: false)
        totalEntryCost = 0
        knownFaviconUrls.removeAll(keepingCapacity: false)
        loaded = markLoaded
    }

    func get(faviconUrl: URL) -> Favicon? {
        guard loaded else { return nil }

        guard let favicon = entries[faviconUrl] else { return nil }
        markAccessed(faviconUrl)
        return favicon
    }

    func getFavicons(with urls: some Sequence<URL>) -> [Favicon]? {
        guard loaded else { return nil }

        return urls.compactMap { faviconUrl in
            guard let favicon = entries[faviconUrl] else { return nil }
            markAccessed(faviconUrl)
            return favicon
        }
    }

    func loadCachedFavicons(with urls: [URL]) async -> [Favicon] {
        guard loaded, !urls.isEmpty else { return [] }

        let requestedUrls = urls.uniquedPreservingOrder()
        let urlsToLoad = requestedUrls.filter { entries[$0] == nil }

        if !urlsToLoad.isEmpty {
            do {
                let favicons = try await storing.loadFavicons(with: urlsToLoad)
                for favicon in favicons {
                    cache(favicon)
                    storeAccentColorIfNeeded(for: favicon)
                }
            } catch {
                Logger.favicons.error("Loading cached favicons by URL failed: \(error.localizedDescription)")
            }
        }

        return getFavicons(with: requestedUrls) ?? []
    }

    func hasCachedFavicon(faviconUrl: URL) -> Bool {
        guard loaded else { return false }
        return knownFaviconUrls.contains(faviconUrl) || entries[faviconUrl] != nil
    }

    // MARK: - Clean

    func cleanOld(bookmarkManager: BookmarkManager) async {
        let bookmarkedHosts = bookmarkManager.allHosts()
        _ = await removeFavicons { favicon in
            guard let host = favicon.documentUrl.host else {
                return false
            }
            return favicon.dateCreated < Date.sumiMonthAgo &&
                !bookmarkedHosts.contains(host)
        }
    }

    // MARK: - Burning

    func burn(bookmarkManager: BookmarkManager, savedLogins: Set<String>) async -> Result<Void, Error> {
        let bookmarkedHosts = bookmarkManager.allHosts()
        return await removeFavicons { favicon in
            guard let host = favicon.documentUrl.host else {
                return false
            }
            return !(bookmarkedHosts.contains(host) || savedLogins.contains(host))
        }
    }

    func burnDomains(_ baseDomains: Set<String>,
                     exceptBookmarks bookmarkManager: BookmarkManager,
                     exceptSavedLogins logins: Set<String>,
                     exceptHistoryDomains history: Set<String>,
                     registrableDomainResolver: any SumiRegistrableDomainResolving) async -> Result<Void, Error> {
        let bookmarkedHosts = bookmarkManager.allHosts()
        return await removeFavicons { favicon in
            guard let host = favicon.documentUrl.host,
                  let baseDomain = registrableDomainResolver.registrableDomain(forHost: host)
            else { return false }
            return baseDomains.contains(baseDomain)
                && !bookmarkedHosts.contains(host)
                && !logins.contains(host)
                && !history.contains(host)
        }
    }

    // MARK: - Private

    @MainActor
    private func removeFavicons(filter isRemoved: (FaviconMetadata) -> Bool) async -> Result<Void, Error> {
        let metadataToRemove: [FaviconMetadata]
        do {
            metadataToRemove = try await storing.loadFaviconMetadata().filter(isRemoved)
        } catch {
            Logger.favicons.error("Loading favicon metadata for removal failed: \(error.localizedDescription)")
            return .failure(error)
        }

        let urlsToRemove = Set(metadataToRemove.map(\.url))
        for url in urlsToRemove {
            entries[url] = nil
            knownFaviconUrls.remove(url)
            if let cost = entryCosts.removeValue(forKey: url) {
                totalEntryCost -= cost
            }
        }
        entryAccessOrder.removeAll { urlsToRemove.contains($0) }

        return await storing.removeFavicons(withIdentifiers: metadataToRemove.map(\.identifier))
    }

    @MainActor
    private func cache(_ favicon: Favicon) {
        let favicon = favicon.withoutImageData
        if let previousCost = entryCosts[favicon.url] {
            totalEntryCost -= previousCost
        }
        entries[favicon.url] = favicon
        knownFaviconUrls.insert(favicon.url)
        let cost = max(1, favicon.image?.sumiFaviconCacheBitmapByteCost ?? 1)
        entryCosts[favicon.url] = cost
        totalEntryCost += cost
        markAccessed(favicon.url)
        trimInMemoryEntriesIfNeeded()
    }

    @MainActor
    private func storeAccentColorIfNeeded(for favicon: Favicon) {
        guard let host = favicon.documentUrl.host?.lowercased(),
              let image = favicon.image
        else { return }
        let key = SumiFaviconAccentCache.cacheKey(domain: host, faviconIdentity: favicon.url.absoluteString)
        SumiFaviconAccentCache.storeOffMain(image: image, forKey: key)
        SumiFaviconAccentCache.storeOffMain(image: image, forKey: host)
    }

    @MainActor
    private func markAccessed(_ faviconUrl: URL) {
        entryAccessOrder.removeAll { $0 == faviconUrl }
        entryAccessOrder.append(faviconUrl)
    }

    @MainActor
    private func trimInMemoryEntriesIfNeeded() {
        while (entries.count > Self.maximumInMemoryEntries || totalEntryCost > Self.maximumInMemoryCost),
              let oldestUrl = entryAccessOrder.first {
            entries[oldestUrl] = nil
            if let cost = entryCosts.removeValue(forKey: oldestUrl) {
                totalEntryCost -= cost
            }
            entryAccessOrder.removeFirst()
        }
    }
}

private extension NSImage {
    var sumiFaviconCacheBitmapByteCost: Int {
        let representationCost = representations
            .map { $0.pixelsWide * $0.pixelsHigh * 4 }
            .max() ?? 0
        if representationCost > 0 {
            return representationCost
        }

        return max(1, Int(size.width * size.height * 4))
    }
}

// `FaviconStore` serializes access through its private Core Data context queue;
// this wrapper lets cache tasks keep that storage lifetime without capturing the
// main-actor cache object.
private final class FaviconImageCacheStorage: @unchecked Sendable {

    private let storing: FaviconStoring

    init(storing: FaviconStoring) {
        self.storing = storing
    }

    func loadFavicons() async throws -> [Favicon] {
        try await storing.loadFavicons()
    }

    func loadFavicons(with urls: [URL]) async throws -> [Favicon] {
        try await storing.loadFavicons(with: urls)
    }

    func loadFaviconMetadata() async throws -> [FaviconMetadata] {
        try await storing.loadFaviconMetadata()
    }

    func save(_ favicons: [Favicon]) async throws {
        try await storing.save(favicons)
    }

    func removeFavicons(_ favicons: [Favicon]) async -> Result<Void, Error> {
        guard !favicons.isEmpty else { return .success(()) }

        do {
            try await storing.removeFavicons(favicons)
            Logger.favicons.debug("Favicons removed successfully.")
            return .success(())
        } catch {
            Logger.favicons.error("Removing of favicons failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    func removeFavicons(with urls: [URL]) async throws {
        try await storing.removeFavicons(with: urls)
    }

    func removeFavicons(withIdentifiers identifiers: [UUID]) async -> Result<Void, Error> {
        guard !identifiers.isEmpty else { return .success(()) }

        do {
            try await storing.removeFavicons(withIdentifiers: identifiers)
            Logger.favicons.debug("Favicons removed successfully.")
            return .success(())
        } catch {
            Logger.favicons.error("Removing of favicons failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }
}

private extension Array where Element == URL {
    func uniquedPreservingOrder() -> [URL] {
        var seen = Set<URL>()
        return filter { seen.insert($0).inserted }
    }
}
