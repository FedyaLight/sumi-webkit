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

struct HistoryVisitPage: Equatable {
    let records: [HistoryVisitRecord]
    let nextOffset: Int
    let hasMore: Bool
}

struct HistorySiteRecord: Identifiable, Equatable, Hashable {
    let id: String
    let domain: String
    let url: URL
    let title: String
    let visitCount: Int
}

struct HistorySitePage: Equatable {
    let sites: [HistorySiteRecord]
    let nextOffset: Int
    let hasMore: Bool
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
    let visitCount: Int
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

enum HistoryRange: String, Codable, CaseIterable, Equatable, Hashable {
    case all
    case today
    case yesterday
    case sunday
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case older
    case allSites = "sites"

    var title: String {
        switch self {
        case .all:
            return "All"
        case .today:
            return "Today"
        case .yesterday:
            return "Yesterday"
        case .sunday:
            return "Sunday"
        case .monday:
            return "Monday"
        case .tuesday:
            return "Tuesday"
        case .wednesday:
            return "Wednesday"
        case .thursday:
            return "Thursday"
        case .friday:
            return "Friday"
        case .saturday:
            return "Saturday"
        case .older:
            return "Older"
        case .allSites:
            return "Sites"
        }
    }

    var paneQueryValue: String { rawValue }

    init?(date: Date, referenceDate: Date, calendar: Calendar = .autoupdatingCurrent) {
        guard referenceDate >= date else { return nil }

        let dayDelta = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: referenceDate)
        ).day ?? 0

        switch dayDelta {
        case 0:
            self = .today
        case 1:
            self = .yesterday
        default:
            let weekday = calendar.component(.weekday, from: date)
            if dayDelta < 7, let range = Self(weekday: weekday) {
                self = range
            } else {
                self = .older
            }
        }
    }

    static func displayedRanges(
        for referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [Self] {
        var currentRange: Self? = .today
        var ranges: [Self] = []
        for _ in 0..<7 {
            guard let unwrappedCurrentRange = currentRange else { break }
            ranges.append(unwrappedCurrentRange)
            currentRange = unwrappedCurrentRange.previousRange(
                for: referenceDate,
                calendar: calendar
            )
        }
        ranges.append(.older)
        return ranges
    }

    func dateRange(
        for referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Range<Date>? {
        let startOfReferenceDay = calendar.startOfDay(for: referenceDate)
        if self == .older {
            guard let oldestDisplayedDay = calendar.date(
                byAdding: .day,
                value: -6,
                to: startOfReferenceDay
            ) else {
                return nil
            }
            return Date.distantPast..<oldestDisplayedDay
        }

        guard let weekday = weekday(for: referenceDate, calendar: calendar) else {
            return nil
        }

        let startDate = self == .today
            ? startOfReferenceDay
            : calendar.firstWeekday(weekday, before: startOfReferenceDay)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            return nil
        }

        return startDate..<nextDay
    }

    private init?(weekday: Int) {
        switch weekday {
        case 1: self = .sunday
        case 2: self = .monday
        case 3: self = .tuesday
        case 4: self = .wednesday
        case 5: self = .thursday
        case 6: self = .friday
        case 7: self = .saturday
        default: return nil
        }
    }

    private func weekday(
        for referenceDate: Date,
        calendar: Calendar
    ) -> Int? {
        let referenceWeekday = calendar.component(.weekday, from: referenceDate)

        switch self {
        case .all, .allSites:
            return nil
        case .today, .older:
            return referenceWeekday
        case .yesterday:
            return referenceWeekday == 1 ? 7 : referenceWeekday - 1
        case .sunday:
            return 1
        case .monday:
            return 2
        case .tuesday:
            return 3
        case .wednesday:
            return 4
        case .thursday:
            return 5
        case .friday:
            return 6
        case .saturday:
            return 7
        }
    }

    private func previousRange(
        for referenceDate: Date,
        calendar: Calendar
    ) -> Self? {
        switch self {
        case .all:
            return .today
        case .today:
            return .yesterday
        case .yesterday:
            guard let yesterday = dateRange(for: referenceDate, calendar: calendar)?.lowerBound,
                  let previousDay = calendar.date(byAdding: .day, value: -1, to: yesterday)
            else {
                return nil
            }
            return Self(date: previousDay, referenceDate: referenceDate, calendar: calendar)
        case .sunday:
            return .saturday
        case .monday:
            return .sunday
        case .tuesday:
            return .monday
        case .wednesday:
            return .tuesday
        case .thursday:
            return .wednesday
        case .friday:
            return .thursday
        case .saturday:
            return .friday
        case .older, .allSites:
            return nil
        }
    }
}

struct HistoryRangeCount: Equatable, Hashable, Identifiable {
    let id: HistoryRange
    let count: Int
}

enum HistoryQuery: Equatable, Hashable {
    case searchTerm(String)
    case domainFilter(Set<String>)
    case rangeFilter(HistoryRange)
    case dateFilter(Date)
    case timeRange(start: Date, end: Date)
    case visits([VisitIdentifier])
}

struct HistoryListPage: Equatable {
    let items: [HistoryListItem]
    let nextOffset: Int
    let hasMore: Bool
}

struct HistorySection: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [HistoryListItem]
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

private extension Calendar {
    func firstWeekday(_ weekday: Int, before referenceDate: Date) -> Date {
        let startOfReferenceDay = startOfDay(for: referenceDate)
        var current = startOfReferenceDay
        while component(.weekday, from: current) != weekday {
            guard let previousDay = date(byAdding: .day, value: -1, to: current) else {
                break
            }
            current = previousDay
        }
        return current
    }
}
