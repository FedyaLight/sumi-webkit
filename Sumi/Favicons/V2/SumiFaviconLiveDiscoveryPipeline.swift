import AppKit
import Foundation
import WebKit

final class SumiFaviconLiveDiscoveryPipeline: @unchecked Sendable {
    private let resolutionPipeline: SumiFaviconCandidateResolutionPipeline
    private let fetchScheduler: SumiFaviconFetchScheduler
    private let preparedPipeline: SumiPreparedFaviconPipeline

    init(
        resolutionPipeline: SumiFaviconCandidateResolutionPipeline,
        fetchScheduler: SumiFaviconFetchScheduler,
        preparedPipeline: SumiPreparedFaviconPipeline
    ) {
        self.resolutionPipeline = resolutionPipeline
        self.fetchScheduler = fetchScheduler
        self.preparedPipeline = preparedPipeline
    }

    @MainActor
    func ingest(
        links: [SumiFaviconDiscoveredLink],
        documentURL: URL,
        baseURL: URL?,
        partition: SumiFaviconPartition,
        webView: WKWebView?,
        aliasPageURLs: [URL] = []
    ) async -> NSImage? {
        let canonicalDocumentURL = SumiFaviconCanonicalURL.pageURL(documentURL)
        let candidates = await candidates(
            links: links,
            documentURL: canonicalDocumentURL,
            baseURL: baseURL,
            partition: partition,
            webView: webView
        )
        guard let selection = await resolutionPipeline.resolve(
            candidates,
            pageURL: canonicalDocumentURL,
            fetchContext: .session(
                webView: webView,
                sourceDocumentURL: canonicalDocumentURL
            ),
            priority: .visibleActiveTab,
            aliasPageURLs: aliasPageURLs
        ) else {
            return nil
        }
        return await preparedPipeline.preparedImage(
            for: selection,
            request: SumiPreparedFaviconRequest(
                pageURL: canonicalDocumentURL,
                partition: partition,
                context: .tabSidebar,
                backingScale: SumiFaviconPresentationMetrics.defaultBackingScale()
            )
        )
    }

    @MainActor
    private func candidates(
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
            let request = await fetchScheduler.request(
                candidate: manifestCandidate,
                context: .session(
                    webView: webView,
                    sourceDocumentURL: documentURL
                ),
                priority: .visibleSidebarOrTabStrip
            )
            let result = await request.value
            if case .success(let response) = result,
               response.data.count <= SumiFaviconConstants.maxPayloadBytes {
                candidates.append(
                    contentsOf: SumiFaviconDiscovery.manifestCandidates(
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
}
