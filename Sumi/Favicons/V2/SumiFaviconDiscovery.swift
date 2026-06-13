import Foundation

struct SumiFaviconDiscoveredLink: Codable, Equatable, Sendable {
    let href: String
    let rel: String
    let type: String?
    let sizes: String?
    let media: String?

    init(
        href: String,
        rel: String,
        type: String? = nil,
        sizes: String? = nil,
        media: String? = nil
    ) {
        self.href = href
        self.rel = rel
        self.type = type
        self.sizes = sizes
        self.media = media
    }
}

enum SumiFaviconDiscovery {
    static func relTokens(from rel: String) -> [String] {
        rel
            .split { byte in
                byte == " " || byte == "\t" || byte == "\n" || byte == "\r" || byte == "\u{0C}"
            }
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
    }

    static func declaredSizes(from sizes: String?) -> [SumiFaviconDeclaredSize] {
        guard let sizes else { return [] }
        return sizes
            .split { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
            .compactMap { token in
                let lower = token.lowercased()
                guard lower != "any" else { return nil }
                let parts = lower.split(separator: "x")
                guard parts.count == 2,
                      let width = Int(parts[0]),
                      let height = Int(parts[1]),
                      width > 0,
                      height > 0
                else {
                    return nil
                }
                return SumiFaviconDeclaredSize(width: width, height: height)
            }
    }

    static func purposes(from rawValue: String?) -> [SumiFaviconPurpose] {
        guard let rawValue else { return [.any] }
        let parsed = rawValue
            .split { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
            .compactMap { SumiFaviconPurpose(rawValue: $0.lowercased()) }
        return parsed.isEmpty ? [.any] : parsed.uniquedPreservingOrder()
    }

    static func documentCandidates(
        from links: [SumiFaviconDiscoveredLink],
        pageURL: URL,
        baseURL: URL?,
        partition: SumiFaviconPartition,
        discoveredAt: Date = Date()
    ) -> [SumiFaviconCandidate] {
        var seen = Set<String>()
        var candidates = [SumiFaviconCandidate]()
        let resolutionBaseURL = baseURL ?? pageURL

        for link in links {
            let tokens = relTokens(from: link.rel)
            guard !tokens.isEmpty else { continue }

            let tokenSet = Set(tokens)
            let sourceKind: SumiFaviconSourceKind?
            let priority: Int
            if tokenSet.contains("icon") {
                sourceKind = .documentLink
                priority = 0
            } else if tokenSet.contains("apple-touch-icon") || tokenSet.contains("apple-touch-icon-precomposed") {
                sourceKind = .documentLink
                priority = 1
            } else if tokenSet.contains("mask-icon") {
                sourceKind = .documentLink
                priority = 1
            } else {
                sourceKind = nil
                priority = 0
            }

            guard let sourceKind,
                  let iconURL = resolve(link.href, relativeTo: resolutionBaseURL, pageURL: pageURL),
                  isUsableLiveOrNetworkCandidateURL(iconURL)
            else {
                continue
            }

            let key = [
                partition.storageComponent,
                sourceKind.rawValue,
                iconURL.absoluteString,
                tokens.joined(separator: " "),
                link.sizes ?? "",
                link.type ?? "",
                link.media ?? "",
            ].joined(separator: "|")
            guard seen.insert(key).inserted else { continue }

            let purpose: [SumiFaviconPurpose] = tokenSet.contains("mask-icon") ? [.monochrome] : [.any]
            candidates.append(
                SumiFaviconCandidate(
                    pageURL: pageURL,
                    iconURL: iconURL,
                    sourceKind: sourceKind,
                    relTokens: tokens,
                    declaredSizes: declaredSizes(from: link.sizes),
                    declaredType: link.type,
                    purposes: purpose,
                    media: link.media,
                    sourcePriority: priority,
                    discoveredAt: discoveredAt,
                    partition: partition
                )
            )
        }

        return candidates
    }

    static func firstManifestURL(
        from links: [SumiFaviconDiscoveredLink],
        pageURL: URL,
        baseURL: URL?
    ) -> URL? {
        let resolutionBaseURL = baseURL ?? pageURL
        for link in links {
            let tokens = relTokens(from: link.rel)
            guard Set(tokens).contains("manifest"),
                  let manifestURL = resolve(link.href, relativeTo: resolutionBaseURL, pageURL: pageURL),
                  manifestURL.sumiIsHTTPOrHTTPS
            else {
                continue
            }
            return manifestURL
        }
        return nil
    }

    static func rootFallbackCandidates(
        for pageURL: URL,
        partition: SumiFaviconPartition,
        discoveredAt: Date = Date()
    ) -> [SumiFaviconCandidate] {
        guard let rootURL = pageURL.sumiFaviconOriginRoot else { return [] }

        var candidates = [SumiFaviconCandidate]()
        func append(
            _ path: String,
            sourceKind: SumiFaviconSourceKind,
            type: String?,
            sizes: [SumiFaviconDeclaredSize] = []
        ) {
            guard let iconURL = URL(string: path, relativeTo: rootURL)?.absoluteURL else { return }
            candidates.append(
                SumiFaviconCandidate(
                    pageURL: pageURL,
                    iconURL: iconURL,
                    sourceKind: sourceKind,
                    relTokens: sourceKind == .appleTouchRoot ? ["apple-touch-icon"] : ["icon"],
                    declaredSizes: sizes,
                    declaredType: type,
                    purposes: [.any],
                    sourcePriority: sourceKind.discoveryRank,
                    discoveredAt: discoveredAt,
                    partition: partition
                )
            )
        }

        append("/favicon.ico", sourceKind: .rootFavicon, type: "image/x-icon")
        append("/favicon.png", sourceKind: .rootFavicon, type: "image/png")
        append(
            "/apple-touch-icon.png",
            sourceKind: .appleTouchRoot,
            type: "image/png",
            sizes: [SumiFaviconDeclaredSize(width: 180, height: 180)]
        )
        append(
            "/apple-touch-icon-precomposed.png",
            sourceKind: .appleTouchRoot,
            type: "image/png",
            sizes: [SumiFaviconDeclaredSize(width: 180, height: 180)]
        )
        append(
            "/apple-touch-icon-180x180.png",
            sourceKind: .appleTouchRoot,
            type: "image/png",
            sizes: [SumiFaviconDeclaredSize(width: 180, height: 180)]
        )
        append(
            "/apple-touch-icon-152x152.png",
            sourceKind: .appleTouchRoot,
            type: "image/png",
            sizes: [SumiFaviconDeclaredSize(width: 152, height: 152)]
        )

        return candidates
    }

    static func manifestCandidates(
        from manifestData: Data,
        manifestURL: URL,
        pageURL: URL,
        partition: SumiFaviconPartition,
        discoveredAt: Date = Date()
    ) -> [SumiFaviconCandidate] {
        guard let object = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let icons = object["icons"] as? [[String: Any]]
        else {
            return []
        }

        var candidates = [SumiFaviconCandidate]()
        var seen = Set<String>()

        for icon in icons {
            guard let src = icon["src"] as? String,
                  let iconURL = resolve(src, relativeTo: manifestURL, pageURL: pageURL),
                  iconURL.sumiIsHTTPOrHTTPS || iconURL.scheme?.lowercased() == "data"
            else {
                continue
            }

            let sizes = icon["sizes"] as? String
            let type = icon["type"] as? String
            let purpose = icon["purpose"] as? String
            let purposes = purposes(from: purpose)
            let key = [
                iconURL.absoluteString,
                sizes ?? "",
                type ?? "",
                purposes.map(\.rawValue).joined(separator: " "),
            ].joined(separator: "|")
            guard seen.insert(key).inserted else { continue }

            candidates.append(
                SumiFaviconCandidate(
                    pageURL: pageURL,
                    iconURL: iconURL,
                    sourceKind: .webAppManifest,
                    relTokens: ["manifest"],
                    declaredSizes: declaredSizes(from: sizes),
                    declaredType: type,
                    purposes: purposes,
                    sourcePriority: SumiFaviconSourceKind.webAppManifest.discoveryRank,
                    discoveredAt: discoveredAt,
                    partition: partition
                )
            )
        }

        return candidates
    }

    static func resolve(_ href: String, relativeTo baseURL: URL, pageURL: URL) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
            ?? URL(string: trimmed, relativeTo: pageURL)?.absoluteURL
    }

    private static func isUsableLiveOrNetworkCandidateURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "data" || scheme == "blob"
    }
}

enum SumiWebAppManifestIconDiscovery {
    static func candidates(
        from data: Data,
        manifestURL: URL,
        pageURL: URL,
        partition: SumiFaviconPartition
    ) -> [SumiFaviconCandidate] {
        SumiFaviconDiscovery.manifestCandidates(
            from: data,
            manifestURL: manifestURL,
            pageURL: pageURL,
            partition: partition
        )
    }
}

extension Sequence where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        var result = [Element]()
        for value in self where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}

private extension URL {
    var sumiIsHTTPOrHTTPS: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    var sumiFaviconOriginRoot: URL? {
        guard sumiIsHTTPOrHTTPS,
              let scheme = scheme?.lowercased(),
              let host = host?.lowercased()
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = "/"
        return components.url
    }
}
