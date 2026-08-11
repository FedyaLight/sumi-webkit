import Foundation
import SumiDomain

struct TabRestorePageResolution: Sendable {
    let url: URL
    let isRestoreFailure: Bool
    let failureDestination: URL?
    let failureRawDestination: String?
}

struct TabRestorePageResolver: Sendable {
    func launchURL(
        _ value: String,
        repairReasons: inout Set<String>
    ) -> URL? {
        guard let url = resolveURL(
            primary: value,
            repairReasons: &repairReasons
        ), SumiSurface.isEmptyNewTabURL(url) == false else {
            return nil
        }
        return url
    }

    func resolveRegularPage(
        _ record: TabRestoreTabRecord,
        repairReasons: inout Set<String>
    ) -> TabRestorePageResolution {
        let resolvedURL: URL?
        switch record.pageKind {
        case .empty:
            resolvedURL = SumiSurface.emptyTabURL
        case .restoreFailure:
            resolvedURL = nil
        case .web, nil:
            let candidate = resolveURL(
                primary: record.currentURLString ?? record.urlString,
                fallback: record.urlString,
                repairReasons: &repairReasons
            )
            if candidate.map(SumiSurface.isEmptyNewTabURL) == true {
                // Legacy records cannot prove whether blank represented a
                // real Empty Page or the retired corruption fallback.
                repairReasons.insert("quarantined legacy blank restored tab")
                resolvedURL = nil
            } else {
                resolvedURL = candidate
            }
        }

        let isRestoreFailure = resolvedURL == nil
        return TabRestorePageResolution(
            url: resolvedURL ?? SumiSurface.restoreFailureURL,
            isRestoreFailure: isRestoreFailure,
            failureDestination: isRestoreFailure
                ? [record.currentURLString, record.urlString]
                    .compactMap { $0 }
                    .compactMap(URL.init(string:))
                    .first
                : nil,
            failureRawDestination: isRestoreFailure
                ? record.currentURLString ?? record.urlString
                : nil
        )
    }

    private func resolveURL(
        primary: String,
        fallback: String? = nil,
        repairReasons: inout Set<String>
    ) -> URL? {
        if let url = validAbsoluteURL(primary) {
            return url
        }
        if let fallback, let url = validAbsoluteURL(fallback) {
            repairReasons.insert("repaired invalid restored url")
            return url
        }
        repairReasons.insert("repaired invalid restored url")
        return nil
    }

    private func validAbsoluteURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme,
              scheme.isEmpty == false else {
            return nil
        }
        return url
    }
}
