import CryptoKit
import Foundation
import OSLog

struct SumiStoredFaviconSelection: Sendable {
    let partition: SumiFaviconPartition
    let pageURL: URL
    let sourceURL: URL
    let blobID: String
    let revision: String
    let payloadKind: SumiFaviconPayloadKind
    let mimeType: String?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let sourceKind: SumiFaviconSourceKind
    let declaredSizes: [SumiFaviconDeclaredSize]
    let declaredType: String?
    let purposes: [SumiFaviconPurpose]
    let updatedAt: Date
}

struct SumiFaviconInvalidation: Hashable, Sendable {
    let partition: SumiFaviconPartition
    let revision: String
}

struct SumiFaviconAliasAssociationResult: Sendable {
    let invalidations: [SumiFaviconInvalidation]
    let didChange: Bool

    static let empty = SumiFaviconAliasAssociationResult(invalidations: [], didChange: false)
}

// Sendable by construction: every metadata and private-payload mutation is isolated to `queue`.
final class SumiFaviconBlobStore: @unchecked Sendable {
    private static let log = Logger.sumi(category: "FaviconBlobStore")
    private static let siteNormalizer = SumiSiteNormalizer()

    private struct Metadata: Codable {
        var schemaVersion = 2
        var blobs: [String: BlobRecord] = [:]
        var pageMappings: [String: PageMapping] = [:]
        var pageAliases: [String: String] = [:]
        var candidateMappings: [String: CandidateRecord] = [:]
        var noIconUntilBySiteKey: [String: Date] = [:]

        enum CodingKeys: String, CodingKey {
            case schemaVersion
            case blobs
            case pageMappings
            case pageAliases
            case candidateMappings
            case noIconUntilBySiteKey
        }

        init() { /* Uses property defaults for an empty metadata store. */ }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 2
            blobs = try container.decodeIfPresent([String: BlobRecord].self, forKey: .blobs) ?? [:]
            pageMappings = try container.decodeIfPresent([String: PageMapping].self, forKey: .pageMappings) ?? [:]
            pageAliases = try container.decodeIfPresent([String: String].self, forKey: .pageAliases) ?? [:]
            candidateMappings = try container.decodeIfPresent([String: CandidateRecord].self, forKey: .candidateMappings) ?? [:]
            noIconUntilBySiteKey = try container.decodeIfPresent([String: Date].self, forKey: .noIconUntilBySiteKey) ?? [:]
        }
    }

    private struct BlobRecord: Codable {
        let blobID: String
        let revision: String
        let payloadKind: SumiFaviconPayloadKind
        let mimeType: String?
        let byteCount: Int
        let pixelWidth: Int?
        let pixelHeight: Int?
        var createdAt: Date
        var lastAccessedAt: Date
        let fileName: String
    }

    private struct PageMapping: Codable {
        let pageKey: String
        let siteKey: String?
        let pageURL: URL
        let sourceURL: URL
        let blobID: String
        let revision: String
        let sourceKind: SumiFaviconSourceKind
        let declaredSizes: [SumiFaviconDeclaredSize]
        let declaredType: String?
        let purposes: [SumiFaviconPurpose]
        let updatedAt: Date
        let expiresAt: Date
    }

    private struct CandidateRecord: Codable {
        let candidateURL: URL
        var blobID: String?
        var revision: String?
        var sourceKind: SumiFaviconSourceKind?
        var lastFetchAt: Date
        var positiveUntil: Date?
        var negativeUntil: Date?
        var failureKind: SumiFaviconValidationFailureKind?
    }

    private struct AliasWriteResult {
        let invalidations: [SumiFaviconInvalidation]
        let didChange: Bool

        static let empty = AliasWriteResult(invalidations: [], didChange: false)
    }

    private let rootDirectory: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "SumiFaviconBlobStore", qos: .utility)
    private var metadataByPartition: [SumiFaviconPartition: Metadata] = [:]
    private var privatePayloads: [SumiFaviconPartition: [String: Data]] = [:]

    init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    func cachedSelection(
        for pageURL: URL,
        partition: SumiFaviconPartition,
        now: Date = Date()
    ) -> SumiStoredFaviconSelection? {
        return queue.sync {
            let metadata = loadMetadataIfNeeded(for: partition)

            let keys = pageLookupKeys(for: pageURL, metadata: metadata)
            for key in keys {
                guard let mapping = metadata.pageMappings[key],
                      mapping.expiresAt > now,
                      let blob = metadata.blobs[mapping.blobID]
                else {
                    continue
                }
                return selection(from: mapping, blob: blob, partition: partition)
            }
            return nil
        }
    }

    func payloadData(
        blobID: String,
        partition: SumiFaviconPartition
    ) -> Data? {
        return queue.sync {
            let metadata = loadMetadataIfNeeded(for: partition)
            guard let blob = metadata.blobs[blobID] else { return nil }
            if partition.isPrivate {
                return privatePayloads[partition]?[blobID]
            }
            return try? Data(contentsOf: blobURL(for: blob, partition: partition))
        }
    }

    func isPositiveCandidateFresh(
        _ candidateURL: URL,
        partition: SumiFaviconPartition,
        now: Date = Date()
    ) -> Bool {
        queue.sync {
            let metadata = loadMetadataIfNeeded(for: partition)
            guard let record = metadata.candidateMappings[candidateKey(candidateURL)],
                  let positiveUntil = record.positiveUntil
            else {
                return false
            }
            return positiveUntil > now && record.blobID != nil
        }
    }

    func isNegativeCandidateFresh(
        _ candidateURL: URL,
        partition: SumiFaviconPartition,
        now: Date = Date()
    ) -> Bool {
        queue.sync {
            let metadata = loadMetadataIfNeeded(for: partition)
            guard let negativeUntil = metadata.candidateMappings[candidateKey(candidateURL)]?.negativeUntil else {
                return false
            }
            return negativeUntil > now
        }
    }

    func isNoIconFresh(
        for pageURL: URL,
        partition: SumiFaviconPartition,
        now: Date = Date()
    ) -> Bool {
        queue.sync {
            let metadata = loadMetadataIfNeeded(for: partition)
            guard let siteKey = siteKey(for: pageURL),
                  let until = metadata.noIconUntilBySiteKey[siteKey]
            else {
                return false
            }
            return until > now
        }
    }

    @discardableResult
    func storeValidatedPayload(
        _ payload: SumiFaviconValidatedPayload,
        for candidate: SumiFaviconCandidate,
        aliasPageURLs: [URL] = [],
        now: Date = Date()
    ) throws -> SumiStoredFaviconSelection {
        try queue.sync {
            var metadata = loadMetadataIfNeeded(for: candidate.partition)
            let blobID = sha256Hex(payload.data)
            let revision = blobID
            let fileName = "\(blobID).\(payload.payloadKind.preferredFileExtension)"

            if candidate.partition.isPrivate {
                var payloads = privatePayloads[candidate.partition] ?? [:]
                payloads[blobID] = payload.data
                privatePayloads[candidate.partition] = payloads
            } else {
                let partitionBlobDirectory = blobDirectory(for: candidate.partition)
                try fileManager.createDirectory(at: partitionBlobDirectory, withIntermediateDirectories: true)
                let destination = partitionBlobDirectory.appendingPathComponent(fileName)
                if !fileManager.fileExists(atPath: destination.path) {
                    try payload.data.write(to: destination, options: [.atomic])
                }
            }

            let existingCreatedAt = metadata.blobs[blobID]?.createdAt ?? now
            let blob = BlobRecord(
                blobID: blobID,
                revision: revision,
                payloadKind: payload.payloadKind,
                mimeType: payload.mimeType,
                byteCount: payload.byteCount,
                pixelWidth: payload.pixelWidth,
                pixelHeight: payload.pixelHeight,
                createdAt: existingCreatedAt,
                lastAccessedAt: now,
                fileName: fileName
            )
            metadata.blobs[blobID] = blob

            let canonicalPageURL = SumiFaviconCanonicalURL.pageURL(candidate.pageURL)
            let pageKey = pageKey(for: canonicalPageURL)
            let siteKey = siteKey(for: canonicalPageURL)
            let mapping = pageMapping(
                pageKey: pageKey,
                siteKey: siteKey,
                pageURL: canonicalPageURL,
                sourceURL: candidate.iconURL,
                blobID: blobID,
                revision: revision,
                sourceKind: candidate.sourceKind,
                declaredSizes: candidate.declaredSizes,
                declaredType: candidate.declaredType,
                purposes: candidate.purposes,
                updatedAt: now
            )
            metadata.pageMappings[pageKey] = mapping
            if let siteKey {
                metadata.pageMappings[siteKey] = mapping
                metadata.noIconUntilBySiteKey[siteKey] = nil
            }
            writeAliasMappings(
                aliasPageURLs,
                to: mapping,
                partition: candidate.partition,
                metadata: &metadata,
                now: now
            )

            metadata.candidateMappings[candidateKey(candidate.iconURL)] = CandidateRecord(
                candidateURL: candidate.iconURL,
                blobID: blobID,
                revision: revision,
                sourceKind: candidate.sourceKind,
                lastFetchAt: now,
                positiveUntil: now.addingTimeInterval(SumiFaviconTTL.positive),
                negativeUntil: nil,
                failureKind: nil
            )

            cleanupDiskBudgetIfNeeded(metadata: &metadata, partition: candidate.partition)
            metadataByPartition[candidate.partition] = metadata
            try persist(metadata: metadata, partition: candidate.partition)
            return selection(from: mapping, blob: blob, partition: candidate.partition)
        }
    }

    @discardableResult
    func associatePageAliases(
        _ aliasPageURLs: [URL],
        to selection: SumiStoredFaviconSelection,
        now: Date = Date()
    ) -> SumiFaviconAliasAssociationResult {
        guard !aliasPageURLs.isEmpty else { return .empty }

        return queue.sync {
            var metadata = loadMetadataIfNeeded(for: selection.partition)
            guard let blob = metadata.blobs[selection.blobID] else { return .empty }

            let targetPageKey = pageKey(for: selection.pageURL)
            let targetMapping = metadata.pageMappings[targetPageKey] ?? pageMapping(
                pageKey: targetPageKey,
                siteKey: siteKey(for: selection.pageURL),
                pageURL: selection.pageURL,
                sourceURL: selection.sourceURL,
                blobID: selection.blobID,
                revision: selection.revision,
                sourceKind: selection.sourceKind,
                declaredSizes: selection.declaredSizes,
                declaredType: selection.declaredType,
                purposes: selection.purposes,
                updatedAt: selection.updatedAt
            )
            metadata.pageMappings[targetPageKey] = targetMapping

            let aliasResult = writeAliasMappings(
                aliasPageURLs,
                to: targetMapping,
                partition: selection.partition,
                metadata: &metadata,
                now: now
            )
            if aliasResult.didChange {
                metadata.blobs[blob.blobID] = BlobRecord(
                    blobID: blob.blobID,
                    revision: blob.revision,
                    payloadKind: blob.payloadKind,
                    mimeType: blob.mimeType,
                    byteCount: blob.byteCount,
                    pixelWidth: blob.pixelWidth,
                    pixelHeight: blob.pixelHeight,
                    createdAt: blob.createdAt,
                    lastAccessedAt: now,
                    fileName: blob.fileName
                )
                metadataByPartition[selection.partition] = metadata
                persistOrLog(
                    metadata: metadata,
                    partition: selection.partition,
                    operation: "alias association"
                )
            }
            return SumiFaviconAliasAssociationResult(
                invalidations: aliasResult.invalidations,
                didChange: aliasResult.didChange
            )
        }
    }

    func recordFailure(
        candidateURL: URL,
        partition: SumiFaviconPartition,
        failureKind: SumiFaviconValidationFailureKind,
        ttl: TimeInterval,
        now: Date = Date()
    ) {
        queue.sync {
            var metadata = loadMetadataIfNeeded(for: partition)
            let key = candidateKey(candidateURL)
            var record = metadata.candidateMappings[key] ?? CandidateRecord(
                candidateURL: candidateURL,
                blobID: nil,
                revision: nil,
                sourceKind: nil,
                lastFetchAt: now,
                positiveUntil: nil,
                negativeUntil: nil,
                failureKind: nil
            )
            record.lastFetchAt = now
            record.negativeUntil = now.addingTimeInterval(ttl)
            record.failureKind = failureKind
            metadata.candidateMappings[key] = record
            metadataByPartition[partition] = metadata
            persistOrLog(
                metadata: metadata,
                partition: partition,
                operation: "candidate failure"
            )
        }
    }

    func recordNoIconFound(
        for pageURL: URL,
        partition: SumiFaviconPartition,
        now: Date = Date()
    ) {
        queue.sync {
            guard let siteKey = siteKey(for: pageURL) else { return }
            var metadata = loadMetadataIfNeeded(for: partition)
            let hasFreshMapping = pageLookupKeys(for: pageURL, metadata: metadata).contains { key in
                guard let mapping = metadata.pageMappings[key] else { return false }
                return mapping.expiresAt > now
            }
            guard !hasFreshMapping else { return }
            metadata.noIconUntilBySiteKey[siteKey] = now.addingTimeInterval(SumiFaviconTTL.noIconFound)
            metadataByPartition[partition] = metadata
            persistOrLog(
                metadata: metadata,
                partition: partition,
                operation: "no-icon marker"
            )
        }
    }

    func invalidateSite(
        domain: String,
        partition: SumiFaviconPartition? = nil
    ) -> [SumiFaviconInvalidation] {
        guard let normalizedDomain = Self.normalizedSiteDomain(domain) else { return [] }

        return queue.sync {
            let partitions = partition.map { [$0] } ?? Array(loadedOrDiscoverablePartitions())
            var invalidations = [SumiFaviconInvalidation]()

            for partition in partitions {
                var metadata = loadMetadataIfNeeded(for: partition)
                let mappingsToRemove = metadata.pageMappings.filter { key, mapping in
                    hosts(for: key, mapping: mapping).contains { host in
                        domainMatches(host: host, domain: normalizedDomain)
                    }
                }
                for (key, mapping) in mappingsToRemove {
                    invalidations.append(SumiFaviconInvalidation(partition: partition, revision: mapping.revision))
                    metadata.pageMappings[key] = nil
                }
                pruneAliases(in: &metadata)
                metadata.noIconUntilBySiteKey = metadata.noIconUntilBySiteKey.filter { key, _ in
                    guard let host = URL(string: key)?.host?.lowercased() else {
                        return key.contains(normalizedDomain) == false
                    }
                    return !domainMatches(host: host, domain: normalizedDomain)
                }
                metadataByPartition[partition] = metadata
                persistOrLog(
                    metadata: metadata,
                    partition: partition,
                    operation: "site invalidation"
                )
            }

            return invalidations
        }
    }

    func clearPartition(_ partition: SumiFaviconPartition) {
        queue.sync {
            metadataByPartition[partition] = Metadata()
            privatePayloads[partition] = nil
            if !partition.isPrivate {
                try? fileManager.removeItem(at: partitionDirectory(for: partition))
            }
        }
    }

    func burnAfterHistoryClear(savedLogins: Set<String>, bookmarkHosts: Set<String>) -> [SumiFaviconInvalidation] {
        let preservedHosts = Self.normalizedHosts(savedLogins)
            .union(Self.normalizedHosts(bookmarkHosts))

        return queue.sync {
            var invalidations = [SumiFaviconInvalidation]()
            for partition in loadedOrDiscoverablePartitions() {
                var metadata = loadMetadataIfNeeded(for: partition)
                metadata.pageMappings = metadata.pageMappings.filter { key, mapping in
                    let hosts = hosts(for: key, mapping: mapping)
                    let shouldPreserve = hosts.contains { preservedHosts.contains($0) }
                    if !shouldPreserve {
                        invalidations.append(SumiFaviconInvalidation(partition: partition, revision: mapping.revision))
                    }
                    return shouldPreserve
                }
                pruneAliases(in: &metadata)
                metadataByPartition[partition] = metadata
                persistOrLog(
                    metadata: metadata,
                    partition: partition,
                    operation: "history clear burn"
                )
            }
            return invalidations
        }
    }

    func burnDomains(
        _ domains: Set<String>,
        remainingHistoryHosts: Set<String>,
        savedLogins: Set<String>,
        bookmarkHosts: Set<String>
    ) -> [SumiFaviconInvalidation] {
        let normalizedDomains = Set(domains.compactMap(Self.normalizedSiteDomain))
        guard !normalizedDomains.isEmpty else { return [] }
        let preservedHosts = Self.normalizedHosts(remainingHistoryHosts)
            .union(Self.normalizedHosts(savedLogins))
            .union(Self.normalizedHosts(bookmarkHosts))

        return queue.sync {
            var invalidations = [SumiFaviconInvalidation]()
            for partition in loadedOrDiscoverablePartitions() {
                var metadata = loadMetadataIfNeeded(for: partition)
                metadata.pageMappings = metadata.pageMappings.filter { key, mapping in
                    let hosts = hosts(for: key, mapping: mapping)
                    guard hosts.contains(where: { host in normalizedDomains.contains(where: { domainMatches(host: host, domain: $0) }) }) else {
                        return true
                    }
                    let shouldPreserve = hosts.contains { preservedHosts.contains($0) }
                    if !shouldPreserve {
                        invalidations.append(SumiFaviconInvalidation(partition: partition, revision: mapping.revision))
                    }
                    return shouldPreserve
                }
                pruneAliases(in: &metadata)
                metadataByPartition[partition] = metadata
                persistOrLog(
                    metadata: metadata,
                    partition: partition,
                    operation: "domain burn"
                )
            }
            return invalidations
        }
    }

    private func loadMetadataIfNeeded(for partition: SumiFaviconPartition) -> Metadata {
        if let metadata = metadataByPartition[partition] {
            return metadata
        }

        guard !partition.isPrivate else {
            let metadata = Metadata()
            metadataByPartition[partition] = metadata
            return metadata
        }

        let url = metadataURL(for: partition)
        let loadedData: Data
        do {
            loadedData = try Data(contentsOf: url)
        } catch {
            // Missing metadata file is expected on first run / empty partition;
            // treat it as a fresh store. Non-missing read errors are logged.
            if (error as NSError).code != NSFileReadNoSuchFileError {
                Self.log.error(
                    "Failed to read favicon metadata for partition \(partition.storageComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
            let metadata = Metadata()
            metadataByPartition[partition] = metadata
            return metadata
        }

        do {
            let metadata = try JSONDecoder.sumiFavicon.decode(Metadata.self, from: loadedData)
            guard metadata.schemaVersion == 2 else {
                // Stale schema: preserve the bytes for inspection and start fresh.
                preserveUnreadableMetadata(loadedData, at: url)
                Self.log.error(
                    "Favicon metadata for partition \(partition.storageComponent, privacy: .public) has unexpected schemaVersion; starting fresh."
                )
                let fresh = Metadata()
                metadataByPartition[partition] = fresh
                return fresh
            }
            metadataByPartition[partition] = metadata
            return metadata
        } catch {
            // Corrupt metadata used to silently reset the whole partition's cache,
            // orphaning blobs on disk. Preserve the bytes for recovery and log.
            preserveUnreadableMetadata(loadedData, at: url)
            Self.log.error(
                "Failed to decode favicon metadata for partition \(partition.storageComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            let metadata = Metadata()
            metadataByPartition[partition] = metadata
            return metadata
        }
    }

    private func persist(metadata: Metadata, partition: SumiFaviconPartition) throws {
        guard !partition.isPrivate else { return }
        let directory = partitionDirectory(for: partition)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.sumiFavicon.encode(metadata)
        try data.write(to: metadataURL(for: partition), options: [.atomic])
    }

    private func persistOrLog(
        metadata: Metadata,
        partition: SumiFaviconPartition,
        operation: String
    ) {
        do {
            try persist(metadata: metadata, partition: partition)
        } catch {
            Self.log.error(
                "Failed to persist favicon metadata after \(operation, privacy: .public) for \(partition.storageComponent, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Preserves the unreadable bytes of a corrupt metadata file alongside the
    /// original so they can be recovered manually. Diagnostic only — contents
    /// are not logged or otherwise surfaced.
    private func preserveUnreadableMetadata(_ data: Data, at url: URL) {
        let backupURL = url.appendingPathExtension("unreadable")
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }
        try? data.write(to: backupURL, options: [.atomic])
    }

    private func cleanupDiskBudgetIfNeeded(metadata: inout Metadata, partition: SumiFaviconPartition) {
        guard !partition.isPrivate else { return }
        var total = metadata.blobs.values.reduce(0) { $0 + $1.byteCount }
        guard total > SumiFaviconConstants.diskBudgetBytes else { return }

        let usedBlobIDs = Set(metadata.pageMappings.values.map(\.blobID))
        let removable = metadata.blobs.values
            .filter { !usedBlobIDs.contains($0.blobID) }
            .sorted { $0.lastAccessedAt < $1.lastAccessedAt }

        for blob in removable where total > SumiFaviconConstants.diskBudgetBytes {
            try? fileManager.removeItem(at: blobURL(for: blob, partition: partition))
            metadata.blobs[blob.blobID] = nil
            total -= blob.byteCount
        }
    }

    private func loadedOrDiscoverablePartitions() -> Set<SumiFaviconPartition> {
        var partitions = Set(metadataByPartition.keys)
        guard let contents = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return partitions
        }
        for url in contents {
            let name = url.lastPathComponent
            if name.hasPrefix("profile-") {
                partitions.insert(SumiFaviconPartition(profileIdentifier: String(name.dropFirst("profile-".count)), isPrivate: false))
            }
        }
        return partitions
    }

    private func selection(
        from mapping: PageMapping,
        blob: BlobRecord,
        partition: SumiFaviconPartition
    ) -> SumiStoredFaviconSelection {
        SumiStoredFaviconSelection(
            partition: partition,
            pageURL: mapping.pageURL,
            sourceURL: mapping.sourceURL,
            blobID: mapping.blobID,
            revision: mapping.revision,
            payloadKind: blob.payloadKind,
            mimeType: blob.mimeType,
            pixelWidth: blob.pixelWidth,
            pixelHeight: blob.pixelHeight,
            sourceKind: mapping.sourceKind,
            declaredSizes: mapping.declaredSizes,
            declaredType: mapping.declaredType,
            purposes: mapping.purposes,
            updatedAt: mapping.updatedAt
        )
    }

    @discardableResult
    private func writeAliasMappings(
        _ aliasPageURLs: [URL],
        to targetMapping: PageMapping,
        partition: SumiFaviconPartition,
        metadata: inout Metadata,
        now: Date
    ) -> AliasWriteResult {
        let targetPageKey = targetMapping.pageKey
        var invalidations = [SumiFaviconInvalidation]()
        var didChange = false
        let targetAliasKeys = uniquePageKeys(for: aliasPageURLs)

        for (aliasKey, aliasURL) in targetAliasKeys where aliasKey != targetPageKey {
            let oldMapping = metadata.pageMappings[aliasKey]
            let selectionChanged = oldMapping.map {
                $0.revision != targetMapping.revision
                    || $0.blobID != targetMapping.blobID
                    || $0.sourceURL != targetMapping.sourceURL
            } ?? true
            let aliasTargetChanged = metadata.pageAliases[aliasKey] != targetPageKey
            didChange = didChange || selectionChanged || aliasTargetChanged

            if let oldMapping, selectionChanged {
                invalidations.append(
                    SumiFaviconInvalidation(
                        partition: partition,
                        revision: oldMapping.revision
                    )
                )
            }

            let aliasSiteKey = siteKey(for: aliasURL)
            metadata.pageAliases[aliasKey] = targetPageKey
            metadata.pageMappings[aliasKey] = pageMapping(
                pageKey: aliasKey,
                siteKey: aliasSiteKey,
                pageURL: aliasURL,
                sourceURL: targetMapping.sourceURL,
                blobID: targetMapping.blobID,
                revision: targetMapping.revision,
                sourceKind: targetMapping.sourceKind,
                declaredSizes: targetMapping.declaredSizes,
                declaredType: targetMapping.declaredType,
                purposes: targetMapping.purposes,
                updatedAt: now,
                expiresAt: targetMapping.expiresAt
            )
            if let aliasSiteKey {
                metadata.noIconUntilBySiteKey[aliasSiteKey] = nil
            }
        }

        return AliasWriteResult(invalidations: invalidations, didChange: didChange)
    }

    private func uniquePageKeys(for urls: [URL]) -> [(String, URL)] {
        var seen = Set<String>()
        var result = [(String, URL)]()
        for url in urls {
            let canonicalURL = SumiFaviconCanonicalURL.pageURL(url)
            let key = pageKey(for: canonicalURL)
            guard seen.insert(key).inserted else { continue }
            result.append((key, canonicalURL))
        }
        return result
    }

    private func pruneAliases(in metadata: inout Metadata) {
        metadata.pageAliases = metadata.pageAliases.filter { aliasKey, targetKey in
            metadata.pageMappings[aliasKey] != nil && metadata.pageMappings[targetKey] != nil
        }
    }

    private func hosts(for key: String, mapping: PageMapping) -> Set<String> {
        var result = Set<String>()
        if let url = URL(string: key),
           let host = Self.normalizedHost(for: url) {
            result.insert(host)
        }
        if let host = Self.normalizedHost(for: mapping.pageURL) {
            result.insert(host)
        }
        if let siteKey = mapping.siteKey,
           let url = URL(string: siteKey),
           let host = Self.normalizedHost(for: url) {
            result.insert(host)
        }
        return result
    }

    private static func normalizedHosts(_ hosts: Set<String>) -> Set<String> {
        Set(hosts.compactMap(siteNormalizer.host(fromRawHost:)))
    }

    private static func normalizedHost(for url: URL) -> String? {
        siteNormalizer.host(for: url)
    }

    private static func normalizedSiteDomain(_ domain: String) -> String? {
        siteNormalizer.siteDomain(fromRawDomain: domain)
    }

    private func domainMatches(host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }

    private func pageMapping(
        pageKey: String,
        siteKey: String?,
        pageURL: URL,
        sourceURL: URL,
        blobID: String,
        revision: String,
        sourceKind: SumiFaviconSourceKind,
        declaredSizes: [SumiFaviconDeclaredSize],
        declaredType: String?,
        purposes: [SumiFaviconPurpose],
        updatedAt: Date,
        expiresAt: Date? = nil
    ) -> PageMapping {
        PageMapping(
            pageKey: pageKey,
            siteKey: siteKey,
            pageURL: SumiFaviconCanonicalURL.pageURL(pageURL),
            sourceURL: sourceURL,
            blobID: blobID,
            revision: revision,
            sourceKind: sourceKind,
            declaredSizes: declaredSizes,
            declaredType: declaredType,
            purposes: purposes,
            updatedAt: updatedAt,
            expiresAt: expiresAt ?? updatedAt.addingTimeInterval(SumiFaviconTTL.positive)
        )
    }

    private func pageLookupKeys(for pageURL: URL, metadata: Metadata) -> [String] {
        var keys = [pageKey(for: pageURL)]
        if let aliasTarget = metadata.pageAliases[keys[0]],
           aliasTarget != keys[0],
           !keys.contains(aliasTarget) {
            keys.append(aliasTarget)
        }
        if let siteKey = siteKey(for: pageURL), !keys.contains(siteKey) {
            keys.append(siteKey)
        }
        return keys
    }

    private func pageKey(for url: URL) -> String {
        SumiFaviconCanonicalURL.pageKey(for: url)
    }

    private func siteKey(for url: URL) -> String? {
        SumiFaviconCanonicalURL.siteKey(for: url)
    }

    private func candidateKey(_ url: URL) -> String {
        SumiFaviconCanonicalURL.candidateKey(for: url)
    }

    private func partitionDirectory(for partition: SumiFaviconPartition) -> URL {
        rootDirectory.appendingPathComponent(partition.storageComponent, isDirectory: true)
    }

    private func blobDirectory(for partition: SumiFaviconPartition) -> URL {
        partitionDirectory(for: partition).appendingPathComponent("blobs", isDirectory: true)
    }

    private func metadataURL(for partition: SumiFaviconPartition) -> URL {
        partitionDirectory(for: partition).appendingPathComponent("metadata.json")
    }

    private func blobURL(for blob: BlobRecord, partition: SumiFaviconPartition) -> URL {
        blobDirectory(for: partition).appendingPathComponent(blob.fileName)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension JSONEncoder {
    static var sumiFavicon: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var sumiFavicon: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
