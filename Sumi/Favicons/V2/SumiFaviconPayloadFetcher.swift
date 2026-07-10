import Foundation

final class SumiFaviconPayloadFetcher: @unchecked Sendable {
    enum Result: Sendable {
        case payload(SumiFaviconFetchResponse)
        case failure(SumiFaviconValidationFailureKind)
        case unavailable
        case cancelled
    }

    private let fetchScheduler: SumiFaviconFetchScheduler

    init(fetchScheduler: SumiFaviconFetchScheduler) {
        self.fetchScheduler = fetchScheduler
    }

    func fetch(
        candidate: SumiFaviconCandidate,
        context: SumiFaviconFetchContext,
        priority: SumiFaviconFetchPriority
    ) async -> Result {
        guard let scheme = candidate.iconURL.scheme?.lowercased() else {
            return .unavailable
        }

        if scheme == "data" {
            guard let data = dataURLPayload(candidate.iconURL) else {
                return .unavailable
            }
            return .payload(
                SumiFaviconFetchResponse(
                    data: data,
                    mimeType: candidate.declaredType,
                    statusCode: nil
                )
            )
        }

        guard scheme == "http" || scheme == "https" else {
            return .unavailable
        }

        let resolvedContext = candidate.sourceKind == .rootFavicon
            || candidate.sourceKind == .appleTouchRoot
            ? SumiFaviconFetchContext.publicRootFallback
            : context
        switch await fetchScheduler.fetch(
            candidate: candidate,
            context: resolvedContext,
            priority: priority
        ) {
        case .success(let response):
            return .payload(response)
        case .failure(let failureKind):
            return .failure(failureKind)
        case .cancelled:
            return .cancelled
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
}
