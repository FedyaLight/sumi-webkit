import AppKit
import Foundation
import WebKit

// Cross-task facade; mutable scheduling state is isolated to `schedulingQueue`, and collaborators
// are actors or queue-protected services.
final class SumiFaviconService: @unchecked Sendable {
    private let blobStore: SumiFaviconBlobStore
    private let preparedPipeline: SumiPreparedFaviconPipeline
    private let fetchScheduler: SumiFaviconFetchScheduler
    private let schedulingQueue = DispatchQueue(label: "SumiFaviconService.scheduling")
    private var scheduledColdFetchPageKeys = Set<String>()

    init(
        rootDirectory: URL,
        fetcher: any SumiFaviconNetworkFetching = SumiFaviconNetworkClient()
    ) {
        let blobStore = SumiFaviconBlobStore(rootDirectory: rootDirectory)
        let preparedCache = SumiPreparedFaviconCache()
        self.blobStore = blobStore
        self.preparedPipeline = SumiPreparedFaviconPipeline(
            blobStore: blobStore,
            preparedCache: preparedCache
        )
        self.fetchScheduler = SumiFaviconFetchScheduler(fetcher: fetcher)
    }

    func cachedPreparedImage(for request: SumiPreparedFaviconRequest) -> NSImage? {
        guard let selection = blobStore.cachedSelection(
            for: request.pageURL,
            partition: request.partition
        ) else {
            return nil
        }
        return preparedPipeline.cachedImage(for: selection, request: request)
    }

    func cachedSelection(
        for pageURL: URL,
        partition: SumiFaviconPartition
    ) -> SumiStoredFaviconSelection? {
        blobStore.cachedSelection(for: pageURL, partition: partition)
    }

    func preparedImage(
        for request: SumiPreparedFaviconRequest,
        priority: SumiFaviconFetchPriority,
        scheduleFetchOnMiss: Bool = true
    ) async -> NSImage? {
        if let selection = blobStore.cachedSelection(
            for: request.pageURL,
            partition: request.partition
        ), let prepared = await preparedPipeline.preparedImage(for: selection, request: request) {
            return prepared
        }

        if scheduleFetchOnMiss {
            scheduleColdFetch(
                for: request.pageURL,
                partition: request.partition,
                priority: priority
            )
        }
        return nil
    }

    @MainActor
    func ingestVisibleTabDiscovery(
        links: [SumiFaviconDiscoveredLink],
        documentURL: URL,
        baseURL: URL?,
        partition: SumiFaviconPartition,
        webView: WKWebView?,
        aliasPageURLs: [URL] = []
    ) async -> NSImage? {
        let canonicalDocumentURL = SumiFaviconCanonicalURL.pageURL(documentURL)
        let candidates = await candidatesFromLiveDiscovery(
            links: links,
            documentURL: canonicalDocumentURL,
            baseURL: baseURL,
            partition: partition,
            webView: webView
        )
        guard let selection = await resolveCandidates(
            candidates,
            pageURL: canonicalDocumentURL,
            fetchContext: .session(webView: webView),
            priority: .visibleActiveTab,
            aliasPageURLs: aliasPageURLs
        ) else {
            return nil
        }
        let request = SumiPreparedFaviconRequest(
            pageURL: canonicalDocumentURL,
            partition: partition,
            context: .tabSidebar,
            backingScale: Self.defaultBackingScale()
        )
        return await preparedPipeline.preparedImage(for: selection, request: request)
    }

    func scheduleColdFetch(
        for pageURL: URL,
        partition: SumiFaviconPartition,
        priority: SumiFaviconFetchPriority
    ) {
        guard pageURL.sumiIsHTTPOrHTTPS else { return }
        guard !blobStore.isNoIconFresh(for: pageURL, partition: partition) else { return }
        let key = "\(partition.storageComponent)|\(pageURL.sumiFaviconPageKey)"
        let shouldSchedule = schedulingQueue.sync { () -> Bool in
            guard !scheduledColdFetchPageKeys.contains(key) else { return false }
            scheduledColdFetchPageKeys.insert(key)
            return true
        }
        guard shouldSchedule else { return }

        Task(priority: taskPriority(for: priority)) { [weak self] in
            guard let self else { return }
            defer {
                _ = self.schedulingQueue.sync {
                    self.scheduledColdFetchPageKeys.remove(key)
                }
            }
            let candidates = SumiFaviconDiscovery.rootFallbackCandidates(
                for: pageURL,
                partition: partition
            )
            _ = await self.resolveCandidates(
                candidates,
                pageURL: pageURL,
                fetchContext: .publicRootFallback,
                priority: priority
            )
        }
    }

    func invalidateSite(domain: String, partition: SumiFaviconPartition? = nil) {
        let invalidations = blobStore.invalidateSite(domain: domain, partition: partition)
        for invalidation in Set(invalidations) {
            preparedPipeline.invalidate(partition: invalidation.partition, revision: invalidation.revision)
        }
        postUpdate(domain: domain, partition: partition, revision: nil)
    }

    func clearPartition(_ partition: SumiFaviconPartition) {
        blobStore.clearPartition(partition)
        preparedPipeline.invalidate(partition: partition)
    }

    func burnAfterHistoryClear(savedLogins: Set<String>, bookmarkHosts: Set<String>) {
        let invalidations = blobStore.burnAfterHistoryClear(savedLogins: savedLogins, bookmarkHosts: bookmarkHosts)
        for invalidation in Set(invalidations) {
            preparedPipeline.invalidate(partition: invalidation.partition, revision: invalidation.revision)
        }
    }

    func burnDomains(
        _ domains: Set<String>,
        remainingHistoryHosts: Set<String>,
        savedLogins: Set<String>,
        bookmarkHosts: Set<String>
    ) {
        let invalidations = blobStore.burnDomains(
            domains,
            remainingHistoryHosts: remainingHistoryHosts,
            savedLogins: savedLogins,
            bookmarkHosts: bookmarkHosts
        )
        for invalidation in Set(invalidations) {
            preparedPipeline.invalidate(partition: invalidation.partition, revision: invalidation.revision)
        }
        for domain in domains {
            postUpdate(domain: domain, partition: nil, revision: nil)
        }
    }

    func storeExternalPayload(
        _ imageData: Data,
        faviconURL: URL?,
        documentURL: URL,
        partition: SumiFaviconPartition
    ) async throws {
        let candidate = SumiFaviconCandidate(
            pageURL: documentURL,
            iconURL: faviconURL ?? documentURL,
            sourceKind: .browserFallback,
            relTokens: ["icon"],
            partition: partition
        )
        let validation = SumiFaviconPayloadValidator.validate(
            data: imageData,
            responseMimeType: nil,
            candidate: candidate
        )
        guard case .valid(let payload) = validation else {
            return
        }
        let oldSelection = blobStore.cachedSelection(for: documentURL, partition: partition)
        let selection = try blobStore.storeValidatedPayload(payload, for: candidate)
        invalidatePreparedVariantsIfRevisionChanged(oldSelection: oldSelection, newSelection: selection)
        postUpdate(
            domain: documentURL.host,
            partition: partition,
            revision: selection.revision
        )
    }

    func hasFavicon(
        for pageURL: URL,
        partition: SumiFaviconPartition
    ) -> Bool {
        blobStore.cachedSelection(for: pageURL, partition: partition) != nil
    }

    @MainActor
    private func candidatesFromLiveDiscovery(
        links: [SumiFaviconDiscoveredLink],
        documentURL: URL,
        baseURL: URL?,
        partition: SumiFaviconPartition,
        webView: WKWebView?
    ) async -> [SumiFaviconCandidate] {
        var candidates = SumiFaviconDiscovery.documentCandidates(
            from: links,
            pageURL: documentURL,
            baseURL: baseURL,
            partition: partition
        )

        if let manifestURL = SumiFaviconDiscovery.firstManifestURL(
            from: links,
            pageURL: documentURL,
            baseURL: baseURL
        ) {
            let manifestCandidate = SumiFaviconCandidate(
                pageURL: documentURL,
                iconURL: manifestURL,
                sourceKind: .documentLink,
                relTokens: ["manifest"],
                declaredType: "application/manifest+json",
                partition: partition
            )
            let result = await fetchScheduler.fetch(
                candidate: manifestCandidate,
                context: .session(webView: webView),
                priority: .visibleSidebarOrTabStrip
            )
            if case .success(let response) = result,
               response.data.count <= SumiFaviconConstants.maxPayloadBytes
            {
                candidates.append(
                    contentsOf: SumiWebAppManifestIconDiscovery.candidates(
                        from: response.data,
                        manifestURL: manifestURL,
                        pageURL: documentURL,
                        partition: partition
                    )
                )
            }
        }

        candidates.append(
            contentsOf: SumiFaviconDiscovery.rootFallbackCandidates(
                for: documentURL,
                partition: partition
            )
        )
        return candidates
    }

    private func resolveCandidates(
        _ candidates: [SumiFaviconCandidate],
        pageURL: URL,
        fetchContext: SumiFaviconFetchContext,
        priority: SumiFaviconFetchPriority,
        aliasPageURLs: [URL] = []
    ) async -> SumiStoredFaviconSelection? {
        guard let partition = candidates.first?.partition else { return nil }
        let cachedSelection = blobStore.cachedSelection(for: pageURL, partition: partition)
        if let cachedSelection,
           shouldUseCachedSelection(cachedSelection, over: candidates)
        {
            publishAliasUpdatesIfNeeded(
                blobStore.associatePageAliases(aliasPageURLs, to: cachedSelection),
                selection: cachedSelection
            )
            return cachedSelection
        }

        let hasExplicitCandidates = candidates.contains {
            $0.sourceKind == .documentLink || $0.sourceKind == .webAppManifest
        }
        if !hasExplicitCandidates,
           blobStore.isNoIconFresh(for: pageURL, partition: partition)
        {
            return nil
        }

        let ordered = SumiFaviconCandidateSelector.orderedCandidates(
            candidates,
            for: .tabSidebar,
            backingScale: Self.defaultBackingScale()
        )
        for candidate in ordered {
            if blobStore.isNegativeCandidateFresh(candidate.iconURL, partition: candidate.partition) {
                continue
            }
            if let cachedSelection,
               Self.sameFaviconURL(candidate.iconURL, cachedSelection.sourceURL),
               blobStore.isPositiveCandidateFresh(candidate.iconURL, partition: candidate.partition)
            {
                publishAliasUpdatesIfNeeded(
                    blobStore.associatePageAliases(aliasPageURLs, to: cachedSelection),
                    selection: cachedSelection
                )
                return cachedSelection
            }
            guard let payload = await payload(for: candidate, fetchContext: fetchContext, priority: priority) else {
                continue
            }

            let validation = SumiFaviconPayloadValidator.validate(
                data: payload.data,
                responseMimeType: payload.mimeType,
                candidate: candidate
            )

            switch validation {
            case .valid(let validatedPayload):
                do {
                    let oldSelection = blobStore.cachedSelection(for: pageURL, partition: candidate.partition)
                    let selection = try blobStore.storeValidatedPayload(
                        validatedPayload,
                        for: candidate,
                        aliasPageURLs: aliasPageURLs
                    )
                    invalidatePreparedVariantsIfRevisionChanged(
                        oldSelection: oldSelection,
                        newSelection: selection
                    )
                    postUpdate(
                        domain: pageURL.host,
                        partition: candidate.partition,
                        revision: selection.revision
                    )
                    if !aliasPageURLs.isEmpty {
                        postUpdate(
                            domain: nil,
                            partition: candidate.partition,
                            revision: selection.revision
                        )
                    }
                    return selection
                } catch {
                    blobStore.recordFailure(
                        candidateURL: candidate.iconURL,
                        partition: candidate.partition,
                        failureKind: .invalidPayload,
                        ttl: SumiFaviconTTL.verifiedInvalidPayload
                    )
                }

            case .invalid(let failureKind):
                blobStore.recordFailure(
                    candidateURL: candidate.iconURL,
                    partition: candidate.partition,
                    failureKind: failureKind,
                    ttl: ttl(for: failureKind)
                )
            }
        }

        if let cachedSelection {
            publishAliasUpdatesIfNeeded(
                blobStore.associatePageAliases(aliasPageURLs, to: cachedSelection),
                selection: cachedSelection
            )
            return cachedSelection
        }

        blobStore.recordNoIconFound(for: pageURL, partition: partition)
        return nil
    }

    private func shouldUseCachedSelection(
        _ selection: SumiStoredFaviconSelection,
        over candidates: [SumiFaviconCandidate]
    ) -> Bool {
        let explicitCandidates = candidates.filter(Self.isExplicitCandidate)
        guard !explicitCandidates.isEmpty else { return true }

        switch selection.sourceKind {
        case .documentLink, .webAppManifest:
            return !Self.explicitCandidatesCanImprove(over: selection, candidates: explicitCandidates)
        case .rootFavicon, .appleTouchRoot, .browserFallback:
            return false
        }
    }

    private static func isExplicitCandidate(_ candidate: SumiFaviconCandidate) -> Bool {
        candidate.sourceKind == .documentLink || candidate.sourceKind == .webAppManifest
    }

    private static func explicitCandidatesCanImprove(
        over selection: SumiStoredFaviconSelection,
        candidates: [SumiFaviconCandidate]
    ) -> Bool {
        guard selection.payloadKind != .svg else { return false }
        let currentPixels = max(selection.pixelWidth ?? 0, selection.pixelHeight ?? 0)
        let targetPixels = max(
            1,
            Int((SumiFaviconDisplayContext.tabSidebar.canonicalPointSize * max(1, defaultBackingScale())).rounded(.up))
        )
        return candidates.contains { candidate in
            guard !sameFaviconURL(candidate.iconURL, selection.sourceURL) else { return false }
            if candidate.declaredType == "image/svg+xml" || candidate.iconURL.pathExtension.lowercased() == "svg" {
                return true
            }
            if let bestDeclaredPixels = candidate.declaredSizes.map(\.longestSide).max() {
                return bestDeclaredPixels > currentPixels && bestDeclaredPixels >= targetPixels
            }
            guard currentPixels < targetPixels else { return false }
            let type = candidate.declaredType ?? ""
            let ext = candidate.iconURL.pathExtension.lowercased()
            return type != "image/x-icon" && type != "image/vnd.microsoft.icon" && ext != "ico"
        }
    }

    private static func sameFaviconURL(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.absoluteString.caseInsensitiveCompare(rhs.absoluteString) == .orderedSame
    }

    private func payload(
        for candidate: SumiFaviconCandidate,
        fetchContext: SumiFaviconFetchContext,
        priority: SumiFaviconFetchPriority
    ) async -> SumiFaviconFetchResponse? {
        guard let scheme = candidate.iconURL.scheme?.lowercased() else { return nil }

        if scheme == "data" {
            guard let data = dataURLPayload(candidate.iconURL) else { return nil }
            return SumiFaviconFetchResponse(data: data, mimeType: candidate.declaredType, statusCode: nil)
        }
        guard scheme == "http" || scheme == "https" else {
            return nil
        }

        let context = candidate.sourceKind == .rootFavicon || candidate.sourceKind == .appleTouchRoot
            ? SumiFaviconFetchContext.publicRootFallback
            : fetchContext
        let result = await fetchScheduler.fetch(
            candidate: candidate,
            context: context,
            priority: priority
        )
        switch result {
        case .success(let response):
            return response
        case .failure(let failureKind):
            blobStore.recordFailure(
                candidateURL: candidate.iconURL,
                partition: candidate.partition,
                failureKind: failureKind,
                ttl: ttl(for: failureKind)
            )
            return nil
        }
    }

    private func dataURLPayload(_ url: URL) -> Data? {
        let value = url.absoluteString
        guard value.lowercased().hasPrefix("data:"),
              let comma = value.firstIndex(of: ",")
        else {
            return nil
        }
        let metadata = value[value.index(value.startIndex, offsetBy: 5)..<comma].lowercased()
        let payload = value[value.index(after: comma)...]
        if metadata.contains(";base64") {
            return Data(base64Encoded: String(payload))
        }
        return String(payload).removingPercentEncoding?.data(using: .utf8)
    }

    private func invalidatePreparedVariantsIfRevisionChanged(
        oldSelection: SumiStoredFaviconSelection?,
        newSelection: SumiStoredFaviconSelection
    ) {
        guard let oldSelection,
              oldSelection.revision != newSelection.revision
        else {
            return
        }
        preparedPipeline.invalidate(
            partition: oldSelection.partition,
            blobID: oldSelection.blobID,
            revision: oldSelection.revision
        )
    }

    private func publishAliasUpdatesIfNeeded(
        _ result: SumiFaviconAliasAssociationResult,
        selection: SumiStoredFaviconSelection
    ) {
        guard result.didChange else { return }
        for invalidation in Set(result.invalidations) {
            preparedPipeline.invalidate(
                partition: invalidation.partition,
                revision: invalidation.revision
            )
        }
        postUpdate(
            domain: nil,
            partition: selection.partition,
            revision: selection.revision
        )
    }

    private func ttl(for failureKind: SumiFaviconValidationFailureKind) -> TimeInterval {
        switch failureKind {
        case .transport:
            return SumiFaviconTTL.transientTransportFailure
        case .notFound, .invalidPayload, .oversizedPayload, .oversizedPixels, .htmlPayload, .unsafeSVG, .unsupported:
            return SumiFaviconTTL.verifiedInvalidPayload
        case .noIconFound:
            return SumiFaviconTTL.noIconFound
        }
    }

    private func postUpdate(
        domain: String?,
        partition: SumiFaviconPartition?,
        revision: String?
    ) {
        Task { @MainActor in
            var userInfo: [AnyHashable: Any] = [:]
            if let domain {
                userInfo[NSNotification.Name.faviconCacheUpdatedDomainKey] = domain
            }
            if let partition {
                userInfo["SumiFaviconPartition"] = partition.storageComponent
            }
            if let revision {
                userInfo["SumiFaviconRevision"] = revision
            }
            NotificationCenter.default.post(
                name: .faviconCacheUpdated,
                object: self,
                userInfo: userInfo
            )
        }
    }

    private func taskPriority(for priority: SumiFaviconFetchPriority) -> TaskPriority {
        switch priority {
        case .visibleActiveTab:
            return .userInitiated
        case .visibleSidebarOrTabStrip, .pinnedLauncher, .historyBookmarkVisibleRow:
            return .utility
        case .backgroundPrefetch, .staleRefresh:
            return .background
        }
    }

    static func defaultBackingScale() -> CGFloat {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                NSScreen.main?.backingScaleFactor ?? 2
            }
        }
        return 2
    }
}

private extension URL {
    var sumiIsHTTPOrHTTPS: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    var sumiFaviconPageKey: String {
        SumiFaviconCanonicalURL.pageKey(for: self)
    }
}
