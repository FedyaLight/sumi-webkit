import Foundation
import OSLog

final class SumiFaviconCandidateResolutionPipeline: @unchecked Sendable {
    private static let log = Logger.sumi(category: "FaviconCandidateResolution")

    private let blobReader: SumiFaviconBlobReader
    private let blobWriter: SumiFaviconBlobWriter
    private let payloadFetcher: SumiFaviconPayloadFetcher
    private let payloadCommitter: SumiFaviconStoredPayloadCommitter
    private let mutationGate: SumiFaviconMutationGate

    init(
        blobReader: SumiFaviconBlobReader,
        blobWriter: SumiFaviconBlobWriter,
        payloadFetcher: SumiFaviconPayloadFetcher,
        payloadCommitter: SumiFaviconStoredPayloadCommitter,
        mutationGate: SumiFaviconMutationGate
    ) {
        self.blobReader = blobReader
        self.blobWriter = blobWriter
        self.payloadFetcher = payloadFetcher
        self.payloadCommitter = payloadCommitter
        self.mutationGate = mutationGate
    }

    func resolve(
        _ candidates: [SumiFaviconCandidate],
        pageURL: URL,
        fetchContext: SumiFaviconFetchContext,
        priority: SumiFaviconFetchPriority,
        aliasPageURLs: [URL] = []
    ) async -> SumiStoredFaviconSelection? {
        guard let partition = candidates.first?.partition else { return nil }
        let lease = mutationGate.lease(for: partition)
        let cachedSelection = blobReader.cachedSelection(for: pageURL, partition: partition)
        if let cachedSelection,
           SumiFaviconSelectionPolicy.shouldUseCachedSelection(cachedSelection, over: candidates) {
            payloadCommitter.associateAliases(
                aliasPageURLs,
                to: cachedSelection,
                lease: lease
            )
            return mutationGate.isCurrent(lease)
                ? cachedSelection
                : blobReader.cachedSelection(for: pageURL, partition: partition)
        }

        let hasExplicitCandidates = candidates.contains(
            where: SumiFaviconSelectionPolicy.isExplicitCandidate
        )
        if !hasExplicitCandidates,
           blobReader.isNoIconFresh(for: pageURL, partition: partition) {
            return nil
        }

        let ordered = SumiFaviconCandidateSelector.orderedCandidates(
            candidates,
            for: .tabSidebar,
            backingScale: SumiFaviconPresentationMetrics.defaultBackingScale()
        )
        for candidate in ordered {
            guard !Task.isCancelled else { return nil }
            if blobReader.isNegativeCandidateFresh(
                candidate.iconURL,
                partition: candidate.partition
            ) {
                continue
            }
            if let cachedSelection,
               SumiFaviconSelectionPolicy.sameFaviconURL(
                   candidate.iconURL,
                   cachedSelection.sourceURL
               ),
               blobReader.isPositiveCandidateFresh(
                   candidate.iconURL,
                   partition: candidate.partition
               ) {
                payloadCommitter.associateAliases(
                    aliasPageURLs,
                    to: cachedSelection,
                    lease: lease
                )
                return mutationGate.isCurrent(lease)
                    ? cachedSelection
                    : blobReader.cachedSelection(for: pageURL, partition: partition)
            }

            switch await payloadFetcher.fetch(
                candidate: candidate,
                context: fetchContext,
                priority: priority
            ) {
            case .payload(let response):
                switch SumiFaviconPayloadValidator.validate(
                    data: response.data,
                    responseMimeType: response.mimeType,
                    candidate: candidate
                ) {
                case .valid(let payload):
                    do {
                        if let selection = try payloadCommitter.store(
                            payload,
                            for: candidate,
                            aliasPageURLs: aliasPageURLs,
                            lease: lease
                        ) {
                            return selection
                        }
                        return blobReader.cachedSelection(
                            for: pageURL,
                            partition: partition
                        )
                    } catch {
                        // Persistence failure is not evidence that the remote
                        // favicon is invalid. Preserve the old selection and do
                        // not poison the candidate failure cache.
                        Self.log.error(
                            "Failed to commit favicon for \(pageURL.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)"
                        )
                        return cachedSelection
                    }
                case .invalid(let failureKind):
                    recordFailure(
                        candidate: candidate,
                        failureKind: failureKind,
                        lease: lease
                    )
                }
            case .failure(let failureKind):
                recordFailure(
                    candidate: candidate,
                    failureKind: failureKind,
                    lease: lease
                )
            case .unavailable:
                continue
            case .cancelled:
                return nil
            }
        }

        if let cachedSelection {
            payloadCommitter.associateAliases(
                aliasPageURLs,
                to: cachedSelection,
                lease: lease
            )
            return mutationGate.isCurrent(lease)
                ? cachedSelection
                : blobReader.cachedSelection(for: pageURL, partition: partition)
        }

        guard !Task.isCancelled else { return nil }
        _ = mutationGate.performIfCurrent(lease) {
            blobWriter.recordNoIconFound(for: pageURL, partition: partition)
        }
        return nil
    }

    private func recordFailure(
        candidate: SumiFaviconCandidate,
        failureKind: SumiFaviconValidationFailureKind,
        lease: SumiFaviconMutationGate.Lease
    ) {
        _ = mutationGate.performIfCurrent(lease) {
            blobWriter.recordFailure(
                candidateURL: candidate.iconURL,
                partition: candidate.partition,
                failureKind: failureKind,
                ttl: SumiFaviconTTL.failureCacheDuration(for: failureKind)
            )
        }
    }
}

enum SumiFaviconSelectionPolicy {
    static func shouldUseCachedSelection(
        _ selection: SumiStoredFaviconSelection,
        over candidates: [SumiFaviconCandidate]
    ) -> Bool {
        let explicitCandidates = candidates.filter(isExplicitCandidate)
        guard !explicitCandidates.isEmpty else { return true }

        switch selection.sourceKind {
        case .documentLink, .extensionManifest, .webAppManifest:
            return !hasBetterExplicitCandidate(
                over: selection,
                candidates: explicitCandidates
            )
        case .rootFavicon, .appleTouchRoot, .browserFallback:
            return false
        }
    }

    static func isExplicitCandidate(_ candidate: SumiFaviconCandidate) -> Bool {
        candidate.sourceKind == .documentLink
            || candidate.sourceKind == .extensionManifest
            || candidate.sourceKind == .webAppManifest
    }

    static func sameFaviconURL(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.absoluteString.caseInsensitiveCompare(rhs.absoluteString) == .orderedSame
    }

    private static func hasBetterExplicitCandidate(
        over selection: SumiStoredFaviconSelection,
        candidates: [SumiFaviconCandidate]
    ) -> Bool {
        if selection.payloadKind == .svg {
            // SVG quality is resolution-independent, so document membership is
            // the only upgrade signal. A removed source may be a theme variant.
            return !containsSourceURL(selection.sourceURL, in: candidates)
        }

        let currentPixels = max(selection.pixelWidth ?? 0, selection.pixelHeight ?? 0)
        let targetPixels = max(
            1,
            Int(
                (
                    SumiFaviconDisplayContext.tabSidebar.canonicalPointSize
                        * max(1, SumiFaviconPresentationMetrics.defaultBackingScale())
                ).rounded(.up)
            )
        )
        return candidates.contains { candidate in
            guard !sameFaviconURL(candidate.iconURL, selection.sourceURL) else {
                return false
            }
            if candidate.declaredType == "image/svg+xml"
                || candidate.iconURL.pathExtension.lowercased() == "svg" {
                return true
            }
            if let bestDeclaredPixels = candidate.declaredSizes.map(\.longestSide).max() {
                return bestDeclaredPixels > currentPixels && bestDeclaredPixels >= targetPixels
            }
            guard currentPixels < targetPixels else { return false }
            let type = candidate.declaredType ?? ""
            let ext = candidate.iconURL.pathExtension.lowercased()
            return type != "image/x-icon"
                && type != "image/vnd.microsoft.icon"
                && ext != "ico"
        }
    }

    private static func containsSourceURL(
        _ sourceURL: URL,
        in candidates: [SumiFaviconCandidate]
    ) -> Bool {
        candidates.contains { sameFaviconURL($0.iconURL, sourceURL) }
    }
}
