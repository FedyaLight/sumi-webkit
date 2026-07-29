import Foundation
import OSLog

/// Runs the bulk extractors during preview and records what they produced.
///
/// Extraction happens while the user is still deciding, not after they press
/// Import, because two of the three kinds can stop and ask: Chromium's cookie
/// key raises a macOS authorization prompt, and Safari's data can be blocked by
/// Full Disk Access. Surfacing that while the wizard is open — and reporting
/// real counts before anything is committed — is more honest than discovering
/// it mid-import.
struct SumiImportBulkStagingCoordinator {
    private static let log = Logger.sumi(category: "ImportStaging")

    var staging: SumiImportBulkStagingStore

    init(staging: SumiImportBulkStagingStore = SumiImportBulkStagingStore()) {
        self.staging = staging
    }

    struct Outcome {
        var manifest: SumiImportBulkStagingManifest?
        var warnings: [String]
    }

    /// Stages every kind the source supports. Returns `nil` when nothing could
    /// be staged, so the caller can present the import without a browsing-data
    /// section at all.
    func stage(
        browser: SumiDetectedBrowser,
        profile: SumiDetectedBrowserProfile,
        kinds: Set<SumiImportBulkKind>,
        sourceProfileKeys: Set<String>? = nil
    ) -> Outcome? {
        let requested = kinds.intersection(Self.supportedKinds(for: browser))
        guard requested.isEmpty == false else { return nil }

        let stagingID = UUID()
        guard let directory = try? staging.makeStagingDirectory(for: stagingID) else { return nil }

        var entries: [SumiImportBulkStagingManifest.Entry] = []
        var warnings: [String] = []
        let sources = bulkSources(
            browser: browser,
            selectedProfile: profile,
            sourceProfileKeys: sourceProfileKeys
        )

        for (sourceIndex, source) in sources.enumerated() {
            let suffix = sources.count == 1 ? "" : "-\(sourceIndex)"
            for kind in SumiImportBulkKind.applyOrder where requested.contains(kind) {
                do {
                    switch kind {
                    case .history:
                        let fileName = "history\(suffix).ndjson"
                        let extraction = try SumiImportHistoryExtractor(
                            family: browser.family,
                            profileURL: source.url
                        ).stage(to: directory.appendingPathComponent(fileName), staging: staging)
                        entries.append(entry(kind, source.key, fileName, nil, extraction.recordCount, extraction.byteCount, extraction.skipped, extraction.skipReasons))

                    case .favicons:
                        let fileName = "favicons\(suffix).ndjson"
                        let blobName = "icons\(suffix)"
                        let extraction = try SumiImportFaviconExtractor(
                            family: browser.family,
                            profileURL: source.url
                        ).stage(
                            to: directory.appendingPathComponent(fileName),
                            blobDirectory: directory.appendingPathComponent(blobName, isDirectory: true),
                            staging: staging
                        )
                        entries.append(entry(kind, source.key, fileName, blobName, extraction.recordCount, extraction.byteCount, extraction.skipped, extraction.skipReasons))

                    case .cookies:
                        let fileName = "cookies\(suffix).ndjson"
                        let extraction = try SumiImportCookieExtractor(
                            family: browser.family,
                            profileURL: source.url,
                            allowedSourceProfileKeys: sourceProfileKeys,
                            safeStorage: Self.safeStorage(for: browser)
                        ).stage(to: directory.appendingPathComponent(fileName), staging: staging)
                        entries.append(entry(kind, source.key, fileName, nil, extraction.recordCount, extraction.byteCount, extraction.skipped, extraction.skipReasons))
                    }
                } catch {
                    // One unreadable source must not cost the others.
                    warnings.append("\(browser.displayName): \(kind.title.lowercased()) could not be read (\(error.localizedDescription)).")
                    Self.log.error("Bulk staging failed for \(kind.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        for entry in entries where entry.skipReasons.isEmpty == false {
            warnings.append(contentsOf: entry.skipReasons)
        }
        let populated = entries.filter { $0.recordCount > 0 || $0.skipped > 0 }
        guard populated.isEmpty == false else {
            staging.discard(stagingID)
            return warnings.isEmpty ? nil : Outcome(manifest: nil, warnings: warnings)
        }

        let manifest = SumiImportBulkStagingManifest(
            stagingID: stagingID,
            sourceKind: browser.sourceKind,
            entries: populated
        )
        do {
            try staging.writeManifest(manifest)
        } catch {
            staging.discard(stagingID)
            return nil
        }
        return Outcome(manifest: manifest, warnings: warnings)
    }

    private func bulkSources(
        browser: SumiDetectedBrowser,
        selectedProfile: SumiDetectedBrowserProfile,
        sourceProfileKeys: Set<String>?
    ) -> [(url: URL, key: String)] {
        if browser.family == .arc {
            let userDataURL = browser.dataRoot.appendingPathComponent("User Data", isDirectory: true)
            return SumiChromiumProfileCatalogReader.profiles(userDataURL: userDataURL)
                .filter { sourceProfileKeys?.contains($0.directoryName) ?? true }
                .map { ($0.directoryURL, $0.directoryName) }
        }

        let key: String
        switch browser.family {
        case .firefox, .zen:
            key = SumiMozillaCookiePartition.sourceProfileKey(
                directoryName: selectedProfile.sourceDirectoryKey,
                userContextId: 0
            )
        case .arc, .chromium, .safari:
            key = selectedProfile.sourceDirectoryKey
        }
        return [(selectedProfile.directoryURL, key)]
    }

    static func supportedKinds(for browser: SumiDetectedBrowser) -> Set<SumiImportBulkKind> {
        var kinds: Set<SumiImportBulkKind> = []
        if browser.capabilities.contains(.history) { kinds.insert(.history) }
        if browser.capabilities.contains(.favicons) { kinds.insert(.favicons) }
        if browser.capabilities.contains(.cookies) { kinds.insert(.cookies) }
        return kinds
    }

    /// Keychain coordinates for each Chromium fork's cookie key.
    static func safeStorage(for browser: SumiDetectedBrowser) -> (service: String, account: String)? {
        let account: String
        switch browser.id {
        case "arc": account = "Arc"
        case "chrome", "chrome-beta", "chrome-canary": account = "Chrome"
        case "chromium": account = "Chromium"
        case "edge": account = "Microsoft Edge"
        case "brave": account = "Brave"
        case "vivaldi": account = "Vivaldi"
        case "opera", "opera-gx": account = "Opera"
        case "yandex": account = "Yandex"
        default: return nil
        }
        return ("\(account) Safe Storage", account)
    }

    private func entry(
        _ kind: SumiImportBulkKind,
        _ key: String,
        _ fileName: String,
        _ blobDirectory: String?,
        _ count: Int,
        _ bytes: Int,
        _ skipped: Int,
        _ reasons: [String]
    ) -> SumiImportBulkStagingManifest.Entry {
        SumiImportBulkStagingManifest.Entry(
            kind: kind,
            sourceProfileKey: key,
            fileName: fileName,
            blobDirectoryName: blobDirectory,
            recordCount: count,
            byteCount: bytes,
            skipped: skipped,
            skipReasons: reasons
        )
    }
}
