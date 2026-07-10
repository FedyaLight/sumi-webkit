import Foundation
import SumiDomain

/// Pure metadata-index rules. This type does not own queues, files, caches, or
/// persistence scheduling.
struct SumiFaviconBlobIndex {
    private static let siteNormalizer = SumiSiteNormalizer()

    private struct MappingContent {
        let pageURL: URL
        let sourceURL: URL
        let blobID: String
        let revision: String
        let sourceKind: SumiFaviconSourceKind
        let declaredSizes: [SumiFaviconDeclaredSize]
        let declaredType: String?
        let purposes: [SumiFaviconPurpose]
    }

    func selection(
        for pageURL: URL,
        partition: SumiFaviconPartition,
        metadata: SumiFaviconBlobMetadata,
        now: Date
    ) -> SumiStoredFaviconSelection? {
        for key in pageLookupKeys(for: pageURL, metadata: metadata) {
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

    func isPositiveCandidateFresh(
        _ candidateURL: URL,
        metadata: SumiFaviconBlobMetadata,
        now: Date
    ) -> Bool {
        guard let record = metadata.candidateMappings[candidateKey(candidateURL)],
              let positiveUntil = record.positiveUntil
        else {
            return false
        }
        return positiveUntil > now && record.blobID != nil
    }

    func isNegativeCandidateFresh(
        _ candidateURL: URL,
        metadata: SumiFaviconBlobMetadata,
        now: Date
    ) -> Bool {
        guard let negativeUntil = metadata.candidateMappings[candidateKey(candidateURL)]?.negativeUntil else {
            return false
        }
        return negativeUntil > now
    }

    func isNoIconFresh(
        for pageURL: URL,
        metadata: SumiFaviconBlobMetadata,
        now: Date
    ) -> Bool {
        guard let siteKey = siteKey(for: pageURL),
              let until = metadata.noIconUntilBySiteKey[siteKey]
        else {
            return false
        }
        return until > now
    }

    func indexPayload(
        _ payload: SumiFaviconValidatedPayload,
        identity: SumiFaviconBlobIdentity,
        candidate: SumiFaviconCandidate,
        aliasPageURLs: [URL],
        metadata: inout SumiFaviconBlobMetadata,
        now: Date
    ) -> SumiStoredFaviconSelection {
        let blob = SumiFaviconBlobRecord(
            blobID: identity.blobID,
            revision: identity.blobID,
            payloadKind: payload.payloadKind,
            mimeType: payload.mimeType,
            byteCount: payload.byteCount,
            pixelWidth: payload.pixelWidth,
            pixelHeight: payload.pixelHeight,
            createdAt: metadata.blobs[identity.blobID]?.createdAt ?? now,
            lastAccessedAt: now,
            fileName: identity.fileName
        )
        metadata.blobs[identity.blobID] = blob

        let canonicalPageURL = SumiFaviconCanonicalURL.pageURL(candidate.pageURL)
        let pageKey = pageKey(for: canonicalPageURL)
        let siteKey = siteKey(for: canonicalPageURL)
        let mapping = pageMapping(
            pageKey: pageKey,
            siteKey: siteKey,
            content: MappingContent(
                pageURL: canonicalPageURL,
                sourceURL: candidate.iconURL,
                blobID: identity.blobID,
                revision: identity.blobID,
                sourceKind: candidate.sourceKind,
                declaredSizes: candidate.declaredSizes,
                declaredType: candidate.declaredType,
                purposes: candidate.purposes
            ),
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

        metadata.candidateMappings[candidateKey(candidate.iconURL)] = SumiFaviconCandidateRecord(
            candidateURL: candidate.iconURL,
            blobID: identity.blobID,
            revision: identity.blobID,
            sourceKind: candidate.sourceKind,
            lastFetchAt: now,
            positiveUntil: now.addingTimeInterval(SumiFaviconTTL.positive),
            negativeUntil: nil,
            failureKind: nil
        )

        return selection(from: mapping, blob: blob, partition: candidate.partition)
    }

    func associatePageAliases(
        _ aliasPageURLs: [URL],
        to selection: SumiStoredFaviconSelection,
        metadata: inout SumiFaviconBlobMetadata,
        now: Date
    ) -> SumiFaviconAliasAssociationResult {
        guard !aliasPageURLs.isEmpty,
              let blob = metadata.blobs[selection.blobID]
        else {
            return .empty
        }

        let targetPageKey = pageKey(for: selection.pageURL)
        let targetMapping = metadata.pageMappings[targetPageKey] ?? pageMapping(
            pageKey: targetPageKey,
            siteKey: siteKey(for: selection.pageURL),
            content: MappingContent(
                pageURL: selection.pageURL,
                sourceURL: selection.sourceURL,
                blobID: selection.blobID,
                revision: selection.revision,
                sourceKind: selection.sourceKind,
                declaredSizes: selection.declaredSizes,
                declaredType: selection.declaredType,
                purposes: selection.purposes
            ),
            updatedAt: selection.updatedAt
        )
        metadata.pageMappings[targetPageKey] = targetMapping

        let result = writeAliasMappings(
            aliasPageURLs,
            to: targetMapping,
            partition: selection.partition,
            metadata: &metadata,
            now: now
        )
        if result.didChange {
            var accessedBlob = blob
            accessedBlob.lastAccessedAt = now
            metadata.blobs[blob.blobID] = accessedBlob
        }
        return SumiFaviconAliasAssociationResult(
            invalidations: result.invalidations,
            didChange: result.didChange
        )
    }

    func recordFailure(
        candidateURL: URL,
        failureKind: SumiFaviconValidationFailureKind,
        ttl: TimeInterval,
        metadata: inout SumiFaviconBlobMetadata,
        now: Date
    ) {
        let key = candidateKey(candidateURL)
        var record = metadata.candidateMappings[key] ?? SumiFaviconCandidateRecord(
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
    }

    @discardableResult
    func recordNoIconFound(
        for pageURL: URL,
        metadata: inout SumiFaviconBlobMetadata,
        now: Date
    ) -> Bool {
        guard let siteKey = siteKey(for: pageURL) else { return false }
        let hasFreshMapping = pageLookupKeys(for: pageURL, metadata: metadata).contains { key in
            guard let mapping = metadata.pageMappings[key] else { return false }
            return mapping.expiresAt > now
        }
        guard !hasFreshMapping else { return false }
        metadata.noIconUntilBySiteKey[siteKey] = now.addingTimeInterval(SumiFaviconTTL.noIconFound)
        return true
    }

    func normalizedSiteDomain(_ domain: String) -> String? {
        Self.siteNormalizer.siteDomain(fromRawDomain: domain)
    }

    func normalizedHosts(_ hosts: Set<String>) -> Set<String> {
        Set(hosts.compactMap(Self.siteNormalizer.host(fromRawHost:)))
    }

    func invalidateSite(
        normalizedDomain: String,
        partition: SumiFaviconPartition,
        metadata: inout SumiFaviconBlobMetadata
    ) -> [SumiFaviconInvalidation] {
        let mappingsToRemove = metadata.pageMappings.filter { key, mapping in
            hosts(for: key, mapping: mapping).contains { host in
                domainMatches(host: host, domain: normalizedDomain)
            }
        }
        let invalidations = mappingsToRemove.values.map {
            SumiFaviconInvalidation(partition: partition, revision: $0.revision)
        }
        for key in mappingsToRemove.keys {
            metadata.pageMappings[key] = nil
        }
        pruneAliases(in: &metadata)
        metadata.noIconUntilBySiteKey = metadata.noIconUntilBySiteKey.filter { key, _ in
            guard let host = URL(string: key)?.host?.lowercased() else {
                return !key.contains(normalizedDomain)
            }
            return !domainMatches(host: host, domain: normalizedDomain)
        }
        return invalidations
    }

    func burnAfterHistoryClear(
        preservedHosts: Set<String>,
        partition: SumiFaviconPartition,
        metadata: inout SumiFaviconBlobMetadata
    ) -> [SumiFaviconInvalidation] {
        var invalidations = [SumiFaviconInvalidation]()
        metadata.pageMappings = metadata.pageMappings.filter { key, mapping in
            let shouldPreserve = hosts(for: key, mapping: mapping).contains {
                preservedHosts.contains($0)
            }
            if !shouldPreserve {
                invalidations.append(
                    SumiFaviconInvalidation(partition: partition, revision: mapping.revision)
                )
            }
            return shouldPreserve
        }
        pruneAliases(in: &metadata)
        return invalidations
    }

    func burnDomains(
        normalizedDomains: Set<String>,
        preservedHosts: Set<String>,
        partition: SumiFaviconPartition,
        metadata: inout SumiFaviconBlobMetadata
    ) -> [SumiFaviconInvalidation] {
        var invalidations = [SumiFaviconInvalidation]()
        metadata.pageMappings = metadata.pageMappings.filter { key, mapping in
            let mappingHosts = hosts(for: key, mapping: mapping)
            let matchesBurnedDomain = mappingHosts.contains { host in
                normalizedDomains.contains { domain in
                    domainMatches(host: host, domain: domain)
                }
            }
            guard matchesBurnedDomain else { return true }

            let shouldPreserve = mappingHosts.contains { preservedHosts.contains($0) }
            if !shouldPreserve {
                invalidations.append(
                    SumiFaviconInvalidation(partition: partition, revision: mapping.revision)
                )
            }
            return shouldPreserve
        }
        pruneAliases(in: &metadata)
        return invalidations
    }

    private func selection(
        from mapping: SumiFaviconPageMapping,
        blob: SumiFaviconBlobRecord,
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
        to targetMapping: SumiFaviconPageMapping,
        partition: SumiFaviconPartition,
        metadata: inout SumiFaviconBlobMetadata,
        now: Date
    ) -> SumiFaviconAliasWriteResult {
        let targetPageKey = targetMapping.pageKey
        var invalidations = [SumiFaviconInvalidation]()
        var didChange = false

        for (aliasKey, aliasURL) in uniquePageKeys(for: aliasPageURLs)
            where aliasKey != targetPageKey {
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
                content: MappingContent(
                    pageURL: aliasURL,
                    sourceURL: targetMapping.sourceURL,
                    blobID: targetMapping.blobID,
                    revision: targetMapping.revision,
                    sourceKind: targetMapping.sourceKind,
                    declaredSizes: targetMapping.declaredSizes,
                    declaredType: targetMapping.declaredType,
                    purposes: targetMapping.purposes
                ),
                updatedAt: now,
                expiresAt: targetMapping.expiresAt
            )
            if let aliasSiteKey {
                metadata.noIconUntilBySiteKey[aliasSiteKey] = nil
            }
        }

        return SumiFaviconAliasWriteResult(
            invalidations: invalidations,
            didChange: didChange
        )
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

    private func pruneAliases(in metadata: inout SumiFaviconBlobMetadata) {
        metadata.pageAliases = metadata.pageAliases.filter { aliasKey, targetKey in
            metadata.pageMappings[aliasKey] != nil && metadata.pageMappings[targetKey] != nil
        }
    }

    private func hosts(for key: String, mapping: SumiFaviconPageMapping) -> Set<String> {
        var result = Set<String>()
        if let url = URL(string: key),
           let host = Self.siteNormalizer.host(for: url) {
            result.insert(host)
        }
        if let host = Self.siteNormalizer.host(for: mapping.pageURL) {
            result.insert(host)
        }
        if let siteKey = mapping.siteKey,
           let url = URL(string: siteKey),
           let host = Self.siteNormalizer.host(for: url) {
            result.insert(host)
        }
        return result
    }

    private func domainMatches(host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }

    private func pageMapping(
        pageKey: String,
        siteKey: String?,
        content: MappingContent,
        updatedAt: Date,
        expiresAt: Date? = nil
    ) -> SumiFaviconPageMapping {
        SumiFaviconPageMapping(
            pageKey: pageKey,
            siteKey: siteKey,
            pageURL: SumiFaviconCanonicalURL.pageURL(content.pageURL),
            sourceURL: content.sourceURL,
            blobID: content.blobID,
            revision: content.revision,
            sourceKind: content.sourceKind,
            declaredSizes: content.declaredSizes,
            declaredType: content.declaredType,
            purposes: content.purposes,
            updatedAt: updatedAt,
            expiresAt: expiresAt ?? updatedAt.addingTimeInterval(SumiFaviconTTL.positive)
        )
    }

    private func pageLookupKeys(
        for pageURL: URL,
        metadata: SumiFaviconBlobMetadata
    ) -> [String] {
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
}
