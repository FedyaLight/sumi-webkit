//
//  SharedVisitedLinkStoreProvider.swift
//  Sumi
//
//  Isolates WebKit visited-link-store SPI behind defensive selectors.
//

import Foundation
import WebKit

@MainActor
final class SharedVisitedLinkStoreProvider {
    static let shared = SharedVisitedLinkStoreProvider()

    private var storesByProfileId: [UUID: NSObject] = [:]
    private var pendingVisitedLinksByProfileId: [UUID: Set<URL>] = [:]

    func applyStore(
        to configuration: WKWebViewConfiguration,
        for profile: Profile
    ) {
        applyStore(to: configuration, profileId: profile.id)
    }

    func applyStore(
        to configuration: WKWebViewConfiguration,
        profileId: UUID
    ) {
        guard let store = store(for: profileId, seed: configuration.sumiVisitedLinkStoreObject) else {
            return
        }
        configuration.sumiVisitedLinkStoreObject = store
        replayPendingVisitedLinks(for: profileId, on: store)
    }

    func applyStoreFromSourceIfAvailable(
        to configuration: WKWebViewConfiguration,
        source: WKWebViewConfiguration?
    ) {
        guard let sourceStore = source?.sumiVisitedLinkStoreObject else {
            return
        }
        configuration.sumiVisitedLinkStoreObject = sourceStore
    }

    func enableVisitedLinkRecording(on webView: WKWebView) {
        webView.sumiSetAddsVisitedLinks(true)
    }

    func recordVisitedLink(
        _ url: URL,
        for profile: Profile,
        sourceConfiguration: WKWebViewConfiguration?
    ) {
        guard let store = store(
            for: profile.id,
            seed: sourceConfiguration?.sumiVisitedLinkStoreObject
        ) else {
            return
        }
        store.sumiAddVisitedLink(url)
    }

    func preloadVisitedLinks(_ urls: [URL], for profileId: UUID) {
        guard !urls.isEmpty else { return }
        let uniqueURLs = Set(urls)
        if let store = storesByProfileId[profileId] {
            for url in uniqueURLs {
                store.sumiAddVisitedLink(url)
            }
        } else {
            pendingVisitedLinksByProfileId[profileId, default: []].formUnion(uniqueURLs)
        }
    }

    func replaceVisitedLinks(_ urls: [URL], for profileId: UUID) {
        pendingVisitedLinksByProfileId[profileId] = Set(urls)
        guard let store = storesByProfileId[profileId] else {
            return
        }
        store.sumiRemoveAllVisitedLinks()
        replayPendingVisitedLinks(for: profileId, on: store)
    }

    /// Releases only Sumi's in-memory reference to the SPI store object.
    /// This does not delete browser history, website data, cookies, profile
    /// records, or files.
    func discardStore(for profileId: UUID) {
        storesByProfileId.removeValue(forKey: profileId)
    }

    private func store(for profileId: UUID, seed: NSObject?) -> NSObject? {
        if let existing = storesByProfileId[profileId] {
            return existing
        }

        guard let seed else {
            return nil
        }

        storesByProfileId[profileId] = seed
        return seed
    }

    private func replayPendingVisitedLinks(for profileId: UUID, on store: NSObject) {
        guard let urls = pendingVisitedLinksByProfileId.removeValue(forKey: profileId) else {
            return
        }
        for url in urls {
            store.sumiAddVisitedLink(url)
        }
    }
}

extension WKWebViewConfiguration {
    var sumiVisitedLinkStoreObject: NSObject? {
        get {
            guard responds(to: SumiVisitedLinkStoreSelector.getStore) else {
                return nil
            }
            return value(
                forKey: NSStringFromSelector(SumiVisitedLinkStoreSelector.getStore)
            ) as? NSObject
        }
        set {
            guard responds(to: SumiVisitedLinkStoreSelector.setStore) else {
                return
            }
            perform(SumiVisitedLinkStoreSelector.setStore, with: newValue)
        }
    }
}

extension WKWebView {
    func sumiSetAddsVisitedLinks(_ enabled: Bool) {
        guard responds(to: SumiVisitedLinkStoreSelector.setAddsVisitedLinks) else {
            return
        }
        perform(
            SumiVisitedLinkStoreSelector.setAddsVisitedLinks,
            with: enabled ? NSNumber(value: true) : nil
        )
    }
}

private enum SumiVisitedLinkStoreSelector {
    static let getStore = NSSelectorFromString("_visitedLinkStore")
    static let setStore = NSSelectorFromString("_setVisitedLinkStore:")
    static let setAddsVisitedLinks = NSSelectorFromString("_setAddsVisitedLinks:")
    static let addVisitedLinkWithURL = NSSelectorFromString("addVisitedLinkWithURL:")
    static let removeAll = NSSelectorFromString("removeAll")
}

extension NSObject {
    func sumiAddVisitedLink(_ url: URL) {
        guard responds(to: SumiVisitedLinkStoreSelector.addVisitedLinkWithURL) else {
            return
        }
        perform(
            SumiVisitedLinkStoreSelector.addVisitedLinkWithURL,
            with: url as NSURL
        )
    }

    func sumiRemoveAllVisitedLinks() {
        guard responds(to: SumiVisitedLinkStoreSelector.removeAll) else {
            return
        }
        perform(SumiVisitedLinkStoreSelector.removeAll)
    }
}
