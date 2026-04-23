//
//  HistoryTypes.swift
//  Sumi
//

import Foundation

struct VisitIdentifier: Hashable, LosslessStringConvertible, Codable {
    let uuid: String
    let url: String
    let date: Date

    init(uuid: String, url: URL, date: Date) {
        self.uuid = uuid
        self.url = url.absoluteString
        self.date = date
    }

    init?(_ description: String) {
        let components = description.split(separator: "|", omittingEmptySubsequences: true)
        guard components.count == 3,
              let url = URL(string: String(components[1])),
              let interval = TimeInterval(components[2])
        else {
            return nil
        }
        self.init(uuid: String(components[0]), url: url, date: Date(timeIntervalSince1970: interval))
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let identifier = Self(value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Failed to decode VisitIdentifier from \(value)"
            )
        }
        self = identifier
    }

    var description: String {
        [uuid, url, String(date.timeIntervalSince1970)].joined(separator: "|")
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

struct HistoryVisitRecord: Identifiable, Equatable, Hashable {
    let id: UUID
    let url: URL
    let title: String
    let visitedAt: Date
    let domain: String
    let siteDomain: String?
}

struct HistoryListItem: Identifiable, Equatable, Hashable {
    let id: String
    let visitID: VisitIdentifier?
    let url: URL
    let title: String
    let domain: String
    let siteDomain: String?
    let visitedAt: Date?
    let relativeDay: String
    let timeText: String
    let isSiteAggregate: Bool

    var displayTitle: String {
        title.isEmpty ? url.absoluteString : title
    }

    var displayURL: String {
        url.absoluteString
    }

    func matches(_ term: String) -> Bool {
        guard !term.isEmpty else { return true }
        let needle = term.lowercased()
        return displayTitle.lowercased().contains(needle)
            || displayURL.lowercased().contains(needle)
            || domain.lowercased().contains(needle)
            || (siteDomain?.lowercased().contains(needle) ?? false)
    }

    func matchesDomains(_ domains: Set<String>) -> Bool {
        let matchDomain = siteDomain ?? domain
        return domains.contains(matchDomain)
    }
}

struct RecentlyClosedTabState: Identifiable, Equatable {
    let id: UUID
    let title: String
    let url: URL
    let sourceSpaceId: UUID?
    let currentURL: URL?
    let canGoBack: Bool
    let canGoForward: Bool
    let profileId: UUID?
}

struct RecentlyClosedWindowState: Identifiable, Equatable {
    let id: UUID
    let title: String
    let session: WindowSessionSnapshot
}

enum RecentlyClosedItem: Identifiable, Equatable {
    case tab(RecentlyClosedTabState)
    case window(RecentlyClosedWindowState)

    var id: UUID {
        switch self {
        case .tab(let tab):
            return tab.id
        case .window(let window):
            return window.id
        }
    }

}

struct LastSessionWindowSnapshot: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let session: WindowSessionSnapshot
}

enum HistoryDomainResolver {
    static func normalizedDomain(for url: URL) -> String {
        url.host(percentEncoded: false)?.lowercased() ?? url.host?.lowercased()
            ?? url.absoluteString.lowercased()
    }

    static func siteDomain(for url: URL) -> String? {
        let host = normalizedDomain(for: url)
        guard host.contains(".") else { return host }
        let components = host.split(separator: ".")
        guard components.count >= 2 else { return host }
        if host.hasPrefix("www."), components.count == 3 {
            return components.dropFirst().joined(separator: ".")
        }
        if components.count > 2 {
            return components.suffix(2).joined(separator: ".")
        }
        return host
    }
}
