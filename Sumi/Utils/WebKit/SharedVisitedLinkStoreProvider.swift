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
    var sumiAddsVisitedLinks: Bool {
        guard responds(to: SumiVisitedLinkStoreSelector.getAddsVisitedLinks) else {
            return false
        }
        return value(
            forKey: NSStringFromSelector(SumiVisitedLinkStoreSelector.getAddsVisitedLinks)
        ) as? Bool ?? false
    }

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
    static let getAddsVisitedLinks = NSSelectorFromString("_addsVisitedLinks")
    static let setAddsVisitedLinks = NSSelectorFromString("_setAddsVisitedLinks:")
}
