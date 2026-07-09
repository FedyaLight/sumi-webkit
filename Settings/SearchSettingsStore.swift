//
//  SearchSettingsStore.swift
//  Sumi
//

import Foundation
import OSLog

@MainActor
@Observable
final class SearchSettingsStore {
    private static let log = Logger.sumi(category: "Settings")

    private let userDefaults: UserDefaults
    private let searchEngineKey: String
    private let searchEnginesKey: String

    var searchEngineId: String {
        didSet {
            Persisted.string(searchEngineId, key: searchEngineKey, defaults: userDefaults)
        }
    }

    var searchEngines: [SumiSearchEngine] {
        didSet {
            let normalized = SumiSearchEngine.normalized(searchEngines)
            if normalized != searchEngines {
                searchEngines = normalized
                return
            }

            do {
                let data = try JSONEncoder().encode(searchEngines)
                Persisted.data(data, key: searchEnginesKey, defaults: userDefaults)
            } catch {
                Self.log.error(
                    "Failed to encode search engines: \(error.localizedDescription, privacy: .public)"
                )
            }

            if !searchEngines.contains(where: { $0.id == searchEngineId }) {
                searchEngineId = SumiSearchEngine.defaultSearchEngineID(in: searchEngines)
            }
        }
    }

    /// Resolves the current `searchEngineId` to a query template string.
    var resolvedSearchEngineTemplate: String {
        if let engine = searchEngines.first(where: { $0.id == searchEngineId }) {
            return engine.queryTemplate
        }
        return SearchProvider.google.queryTemplate
    }

    var resolvedSearchEngineDisplayName: String {
        if let engine = searchEngines.first(where: { $0.id == searchEngineId }) {
            return engine.name
        }
        return SearchProvider.google.displayName
    }

    init(
        userDefaults: UserDefaults,
        searchEngineKey: String,
        searchEnginesKey: String
    ) {
        self.userDefaults = userDefaults
        self.searchEngineKey = searchEngineKey
        self.searchEnginesKey = searchEnginesKey

        let storedSearchEngineID = userDefaults.string(forKey: searchEngineKey)
            ?? SearchProvider.google.rawValue
        self.searchEngineId = storedSearchEngineID

        let loadedSearchEngines: [SumiSearchEngine]
        if let data = userDefaults.data(forKey: searchEnginesKey) {
            do {
                let decoded = try JSONDecoder().decode([SumiSearchEngine].self, from: data)
                loadedSearchEngines = decoded.isEmpty
                    ? SumiSearchEngine.defaultEngines()
                    : SumiSearchEngine.normalized(decoded)
            } catch {
                Self.log.error(
                    "Failed to decode search engines: \(error.localizedDescription, privacy: .public)"
                )
                loadedSearchEngines = SumiSearchEngine.defaultEngines()
            }
        } else {
            loadedSearchEngines = SumiSearchEngine.defaultEngines()
        }
        self.searchEngines = loadedSearchEngines

        if !loadedSearchEngines.contains(where: { $0.id == storedSearchEngineID }) {
            self.searchEngineId = SumiSearchEngine.defaultSearchEngineID(in: loadedSearchEngines)
        }
    }
}
