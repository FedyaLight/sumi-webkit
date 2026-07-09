//
//  DownloadSettingsStore.swift
//  Sumi
//

import Foundation

@MainActor
@Observable
final class DownloadSettingsStore {
    private let userDefaults: UserDefaults
    private let downloadsAlwaysAskWhereToSaveKey: String
    private let downloadsFallbackActionKey: String

    let downloadApplicationsStore: SumiDownloadApplicationsStore
    let downloadsDirectoryStore: SumiDownloadsDirectoryStore

    var downloadsAlwaysAskWhereToSave: Bool {
        didSet {
            Persisted.bool(
                downloadsAlwaysAskWhereToSave,
                key: downloadsAlwaysAskWhereToSaveKey,
                defaults: userDefaults
            )
        }
    }

    var downloadsFallbackAction: SumiDownloadFallbackAction {
        didSet {
            Persisted.rawRepresentable(
                downloadsFallbackAction,
                key: downloadsFallbackActionKey,
                defaults: userDefaults
            )
        }
    }

    var downloadsDirectoryURL: URL? {
        downloadsDirectoryStore.directoryURL
    }

    var downloadsDestinationPreference: SumiDownloadDestinationPreference {
        SumiDownloadDestinationPreference(
            alwaysAskWhereToSave: DownloadsDirectoryResolver.usesIsolatedDirectory
                ? false
                : downloadsAlwaysAskWhereToSave,
            customDirectoryURL: resolvedDownloadsDirectoryURL()
        )
    }

    var downloadsDirectoryDisplayName: String {
        let url = resolvedDownloadsDirectoryURL() ?? DownloadsDirectoryResolver.resolvedDownloadsDirectory()
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    init(
        userDefaults: UserDefaults,
        downloadsAlwaysAskWhereToSaveKey: String,
        downloadsFallbackActionKey: String,
        downloadApplicationsStore: SumiDownloadApplicationsStore
    ) {
        self.userDefaults = userDefaults
        self.downloadsAlwaysAskWhereToSaveKey = downloadsAlwaysAskWhereToSaveKey
        self.downloadsFallbackActionKey = downloadsFallbackActionKey
        self.downloadApplicationsStore = downloadApplicationsStore
        self.downloadsDirectoryStore = SumiDownloadsDirectoryStore(userDefaults: userDefaults)

        self.downloadsAlwaysAskWhereToSave = userDefaults.bool(forKey: downloadsAlwaysAskWhereToSaveKey)
        self.downloadsFallbackAction = SumiDownloadFallbackAction(
            rawValue: userDefaults.string(forKey: downloadsFallbackActionKey)
                ?? SumiDownloadFallbackAction.saveFile.rawValue
        ) ?? .saveFile
    }

    func setDownloadsDirectory(_ url: URL) {
        downloadsDirectoryStore.setDirectory(url)
    }

    func clearDownloadsDirectory() {
        downloadsDirectoryStore.clear()
    }

    func resolvedDownloadsDirectoryURL() -> URL? {
        downloadsDirectoryStore.resolvedDirectoryURL()
    }
}
