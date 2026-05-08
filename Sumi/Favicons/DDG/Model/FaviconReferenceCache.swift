//
//  FaviconReferenceCache.swift
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

protocol FaviconReferenceCaching {

    // References to favicon URLs for whole domains
    @MainActor
    var hostReferences: [String: FaviconHostReference] { get }

    // References to favicon URLs for special URLs
    @MainActor
    var urlReferences: [URL: FaviconUrlReference] { get }

    @MainActor
    var loaded: Bool { get }

    @MainActor
    func load() async throws

    @MainActor
    func insert(faviconUrls: (smallFaviconUrl: URL?, mediumFaviconUrl: URL?), documentUrl: URL)

    @MainActor
    func clearAllInMemory(markLoaded: Bool)

    @MainActor
    func getFaviconUrl(for documentURL: URL, sizeCategory: Favicon.SizeCategory) -> URL?
    @MainActor
    func getFaviconUrl(for host: String, sizeCategory: Favicon.SizeCategory) -> URL?

    @MainActor
    func cleanOld(bookmarkManager: BookmarkManager) async
    @MainActor
    func burn(bookmarkManager: BookmarkManager, savedLogins: Set<String>) async
    @MainActor
    func burnDomains(_ baseDomains: Set<String>, exceptBookmarks bookmarkManager: BookmarkManager, exceptSavedLogins logins: Set<String>, exceptHistoryDomains history: Set<String>, registrableDomainResolver: any SumiRegistrableDomainResolving) async
}

final class FaviconReferenceCache: FaviconReferenceCaching {

    private let storing: FaviconReferenceCacheStorage

    // References to favicon URLs for whole domains
    private(set) var hostReferences = [String: FaviconHostReference]()

    // References to favicon URLs for special URLs
    private(set) var urlReferences = [URL: FaviconUrlReference]()

    init(faviconStoring: FaviconStoring) {
        storing = FaviconReferenceCacheStorage(storing: faviconStoring)
    }

    private(set) var loaded = false

    func load() async throws {
        do {
            let (hostReferences, urlReferences) = try await storing.loadFaviconReferences()

            for reference in hostReferences {
                self.hostReferences[reference.host] = reference
            }
            for reference in urlReferences {
                self.urlReferences[reference.documentUrl] = reference
            }
            loaded = true

            Logger.favicons.debug("References loaded successfully")

            NotificationCenter.default.post(name: .faviconCacheUpdated, object: nil)
        } catch {
            Logger.favicons.error("Loading of references failed: \(error.localizedDescription)")
            throw error
        }
    }

    func insert(faviconUrls: (smallFaviconUrl: URL?, mediumFaviconUrl: URL?), documentUrl: URL) {
        guard loaded else { return }

        guard let host = documentUrl.host else {
            insertToUrlCache(faviconUrls: faviconUrls, documentUrl: documentUrl)
            return
        }

        if let cacheEntry = hostReferences[host] {
            // Host references already cached

            if cacheEntry.smallFaviconUrl == faviconUrls.smallFaviconUrl && cacheEntry.mediumFaviconUrl == faviconUrls.mediumFaviconUrl {
                // Equal

                // There is a possibility of old cache entry in urlReferences
                if urlReferences[documentUrl] != nil {
                    invalidateUrlCache(for: host)
                }
                return
            }

            if cacheEntry.documentUrl == documentUrl {
                // Favicon was updated

                // Exceptions may contain updated favicon if user visited a different documentUrl sooner
                invalidateUrlCache(for: host)
                insertToHostCache(faviconUrls: (faviconUrls.smallFaviconUrl, faviconUrls.mediumFaviconUrl), host: host, documentUrl: documentUrl)
                return
            } else {
                // Exception
                insertToUrlCache(faviconUrls: (faviconUrls.smallFaviconUrl, faviconUrls.mediumFaviconUrl), documentUrl: documentUrl)

                return
            }
        } else {
            // Not cached. Add to cache
            insertToHostCache(faviconUrls: (faviconUrls.smallFaviconUrl, faviconUrls.mediumFaviconUrl), host: host, documentUrl: documentUrl)
            return
        }
    }

    @MainActor
    func clearAllInMemory(markLoaded: Bool = true) {
        hostReferences.removeAll(keepingCapacity: false)
        urlReferences.removeAll(keepingCapacity: false)
        loaded = markLoaded
    }

    func getFaviconUrl(for documentURL: URL, sizeCategory: Favicon.SizeCategory) -> URL? {
        guard loaded else {
            return nil
        }

        if let urlCacheEntry = urlReferences[documentURL] {
            switch sizeCategory {
            case .small: return urlCacheEntry.smallFaviconUrl ?? urlCacheEntry.mediumFaviconUrl
            default: return urlCacheEntry.mediumFaviconUrl
            }
        } else if let host = documentURL.host,
                    let hostCacheEntry = hostReferences[host] {
            switch sizeCategory {
            case .small: return hostCacheEntry.smallFaviconUrl ?? hostCacheEntry.mediumFaviconUrl
            default: return hostCacheEntry.mediumFaviconUrl
            }
        }

        return nil
    }

    func getFaviconUrl(for host: String, sizeCategory: Favicon.SizeCategory) -> URL? {
        guard loaded else {
            return nil
        }

        let hostCacheEntry = hostReferences[host]

        switch sizeCategory {
        case .small:
            return hostCacheEntry?.smallFaviconUrl ?? hostCacheEntry?.mediumFaviconUrl
        default:
            return hostCacheEntry?.mediumFaviconUrl
        }
    }

    // MARK: - Clean

    func cleanOld(bookmarkManager: BookmarkManager) async {
        let bookmarkedHosts = bookmarkManager.allHosts()
        // Remove host references
        await removeHostReferences(filter: { hostReference in
            let host = hostReference.host
            return hostReference.dateCreated < Date.sumiMonthAgo &&
                !bookmarkedHosts.contains(host)
        }).value
        // Remove URL references
        await removeUrlReferences(filter: { urlReference in
            guard let host = urlReference.documentUrl.host else {
                return false
            }
            return urlReference.dateCreated < Date.sumiMonthAgo &&
                !bookmarkedHosts.contains(host)
        }).value
    }

    // MARK: - Burning

    func burn(bookmarkManager: BookmarkManager, savedLogins: Set<String>) async {
        let bookmarkedHosts = bookmarkManager.allHosts()
        func isHostApproved(host: String) -> Bool {
            return bookmarkedHosts.contains(host) || savedLogins.contains(host)
        }

        // Remove host references
        await removeHostReferences(filter: { hostReference in
            let host = hostReference.host
            return !isHostApproved(host: host)
        }).value
        // Remove URL references
        await removeUrlReferences(filter: { urlReference in
            guard let host = urlReference.documentUrl.host else {
                return false
            }
            return !isHostApproved(host: host)
        }).value
    }

    func burnDomains(_ baseDomains: Set<String>,
                     exceptBookmarks bookmarkManager: BookmarkManager,
                     exceptSavedLogins logins: Set<String>,
                     exceptHistoryDomains history: Set<String>,
                     registrableDomainResolver: any SumiRegistrableDomainResolving) async {
        // Remove host references
        let bookmarkedHosts = bookmarkManager.allHosts()
        await removeHostReferences(filter: { hostReference in
            let host = hostReference.host
            let baseDomain = registrableDomainResolver.registrableDomain(forHost: host) ?? ""
            return baseDomains.contains(baseDomain) && !bookmarkedHosts.contains(host) && !logins.contains(host) && !history.contains(host)
        }).value
        // Remove URL references
        await removeUrlReferences(filter: { urlReference in
            guard let host = urlReference.documentUrl.host else {
                return false
            }
            return baseDomains.contains(host) && !bookmarkedHosts.contains(host) && !logins.contains(host) && !history.contains(host)
        }).value
    }

    // MARK: - Private

    @MainActor
    private func insertToHostCache(faviconUrls: (smallFaviconUrl: URL?, mediumFaviconUrl: URL?), host: String, documentUrl: URL) {
        // Remove existing
        if let oldReference = hostReferences[host] {
            let storing = storing
            Task {
                await storing.removeHostReferences([oldReference])
            }
        }

        // Create and save new references
        let hostReference = FaviconHostReference(identifier: UUID(),
                                              smallFaviconUrl: faviconUrls.smallFaviconUrl,
                                              mediumFaviconUrl: faviconUrls.mediumFaviconUrl,
                                              host: host,
                                              documentUrl: documentUrl,
                                              dateCreated: Date())
        hostReferences[host] = hostReference

        let storing = storing
        Task {
            do {
                try await storing.save(hostReference: hostReference)
                Logger.favicons.debug("Host reference saved successfully. host: \(hostReference.host)")
            } catch {
                Logger.favicons.error("Saving of host reference failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func insertToUrlCache(faviconUrls: (smallFaviconUrl: URL?, mediumFaviconUrl: URL?), documentUrl: URL) {
        // Remove existing
        if let oldReference = urlReferences[documentUrl] {
            let storing = storing
            Task {
                await storing.removeUrlReferences([oldReference])
            }
        }

        // Create and save new references
        let urlReference = FaviconUrlReference(identifier: UUID(),
                                             smallFaviconUrl: faviconUrls.smallFaviconUrl,
                                             mediumFaviconUrl: faviconUrls.mediumFaviconUrl,
                                             documentUrl: documentUrl,
                                             dateCreated: Date())

        urlReferences[documentUrl] = urlReference

        let storing = storing
        Task {
            do {
                try await storing.save(urlReference: urlReference)
                Logger.favicons.debug("URL reference saved successfully. document URL: \(urlReference.documentUrl.absoluteString)")
            } catch {
                Logger.favicons.error("Saving of URL reference failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func invalidateUrlCache(for host: String) {
        _ = removeUrlReferences { urlReference in
            urlReference.documentUrl.host == host
        }
    }

    @MainActor
    private func removeHostReferences(filter isRemoved: (FaviconHostReference) -> Bool) -> Task<Void, Never> {
        let hostReferencesToRemove = hostReferences.values.filter(isRemoved)
        hostReferencesToRemove.forEach { hostReferences[$0.host] = nil }
        let storing = storing

        return Task {
            await storing.removeHostReferences(hostReferencesToRemove)
        }
    }

    @MainActor
    private func removeUrlReferences(filter isRemoved: (FaviconUrlReference) -> Bool) -> Task<Void, Never> {
        let urlReferencesToRemove = urlReferences.values.filter(isRemoved)
        urlReferencesToRemove.forEach { urlReferences[$0.documentUrl] = nil }
        let storing = storing

        return Task {
            await storing.removeUrlReferences(urlReferencesToRemove)
        }
    }
}

// `FaviconStore` serializes reference persistence through its private Core Data
// context queue; this boundary keeps persistence tasks from capturing the
// main-actor reference cache while preserving that storage lifetime.
private final class FaviconReferenceCacheStorage: @unchecked Sendable {

    private let storing: FaviconStoring

    init(storing: FaviconStoring) {
        self.storing = storing
    }

    func loadFaviconReferences() async throws -> ([FaviconHostReference], [FaviconUrlReference]) {
        try await storing.loadFaviconReferences()
    }

    func save(hostReference: FaviconHostReference) async throws {
        try await storing.save(hostReference: hostReference)
    }

    func save(urlReference: FaviconUrlReference) async throws {
        try await storing.save(urlReference: urlReference)
    }

    func removeHostReferences(_ hostReferences: [FaviconHostReference]) async {
        guard !hostReferences.isEmpty else { return }

        do {
            try await storing.remove(hostReferences: hostReferences)
            Logger.favicons.debug("Host references removed successfully.")
        } catch {
            Logger.favicons.error("Removing of host references failed: \(error.localizedDescription)")
        }
    }

    func removeUrlReferences(_ urlReferences: [FaviconUrlReference]) async {
        guard !urlReferences.isEmpty else { return }

        do {
            try await storing.remove(urlReferences: urlReferences)
            Logger.favicons.debug("URL references removed successfully.")
        } catch {
            Logger.favicons.error("Removing of URL references failed: \(error.localizedDescription)")
        }
    }
}
