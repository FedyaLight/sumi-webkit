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

    private let storing: FaviconImageCacheStorage

    @MainActor
    private var entries = [URL: Favicon]()

    init(faviconStoring: FaviconStoring) {
        storing = FaviconImageCacheStorage(storing: faviconStoring)
    }

    @MainActor
    private(set) var loaded = false

    @MainActor
    func load() async throws {
        let favicons: [Favicon]
        do {
            favicons = try await storing.loadFavicons()
            Logger.favicons.debug("Favicons loaded successfully")
        } catch {
            Logger.favicons.error("Loading of favicons failed: \(error.localizedDescription)")
            throw error
        }

        for favicon in favicons {
            entries[favicon.url] = favicon
        }
        loaded = true
    }

    func insert(_ favicons: [Favicon]) {
        guard !favicons.isEmpty, loaded else {
            return
        }

        // Remove existing favicon with the same URL
        let oldFavicons = favicons.compactMap { entries[$0.url] }

        // Save the new ones
        for favicon in favicons {
            entries[favicon.url] = favicon
        }

        let storing = storing

        Task {
            do {
                _ = await storing.removeFavicons(oldFavicons)
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
        loaded = markLoaded
    }

    func get(faviconUrl: URL) -> Favicon? {
        guard loaded else { return nil }

        return entries[faviconUrl]
    }

    func getFavicons(with urls: some Sequence<URL>) -> [Favicon]? {
        guard loaded else { return nil }

        return urls.compactMap { faviconUrl in entries[faviconUrl] }
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
    private func removeFavicons(filter isRemoved: (Favicon) -> Bool) async -> Result<Void, Error> {
        let faviconsToRemove = entries.values.filter(isRemoved)
        faviconsToRemove.forEach { entries[$0.url] = nil }

        return await storing.removeFavicons(faviconsToRemove)
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
}
