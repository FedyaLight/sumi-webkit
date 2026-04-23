import Foundation

enum DataModel {
    struct HistoryItemsBatch: Codable, Equatable {
        let finished: Bool
        let visits: [HistoryItem]
    }

    enum DeleteDialogResponse: String, Codable, Equatable {
        case delete
        case domainSearch = "domain-search"
        case noAction = "none"
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
    }

    struct HistoryRangeWithCount: Codable, Equatable, Hashable, Identifiable {
        let id: HistoryRange
        let count: Int
    }

    enum HistoryQueryKind: Codable, Equatable, Hashable {
        case searchTerm(String)
        case domainFilter(Set<String>)
        case rangeFilter(HistoryRange)
        case dateFilter(Date)
        case visits([VisitIdentifier])

        enum CodingKeys: CodingKey {
            case term
            case range
            case domain
        }

        init(from decoder: any Decoder) throws {
            if let singleValueContainer = try? decoder.singleValueContainer(),
               let value = try? singleValueContainer.decode(Date.self) {
                self = .dateFilter(value)
                return
            } else if var unkeyedContainer = try? decoder.unkeyedContainer(),
                      let value = try? unkeyedContainer.decode([VisitIdentifier].self) {
                self = .visits(value)
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let term = try container.decodeIfPresent(String.self, forKey: .term) {
                self = .searchTerm(term)
            } else if let domain = try? container.decodeIfPresent(String.self, forKey: .domain) {
                self = .domainFilter([domain])
            } else if let domains = try container.decodeIfPresent([String].self, forKey: .domain) {
                self = .domainFilter(Set(domains))
            } else if let range = try container.decodeIfPresent(HistoryRange.self, forKey: .range) {
                self = .rangeFilter(range)
            } else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Unknown history query kind")
                )
            }
        }

        func encode(to encoder: any Encoder) throws {
            switch self {
            case .searchTerm(let term):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(term, forKey: .term)
            case .domainFilter(let domains) where domains.count == 1:
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(domains.first, forKey: .domain)
            case .domainFilter(let domains):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(Array(domains).sorted(), forKey: .domain)
            case .rangeFilter(let range):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(range, forKey: .range)
            case .dateFilter(let date):
                var container = encoder.singleValueContainer()
                try container.encode(date)
            case .visits(let visits):
                var container = encoder.unkeyedContainer()
                try container.encode(visits)
            }
        }
    }

    enum HistoryQuerySource: String, Codable, Equatable {
        case initial
        case user
        case auto
    }

    struct HistoryQuery: Codable, Equatable {
        let query: HistoryQueryKind
        let source: HistoryQuerySource
        let limit: Int
        let offset: Int
    }

    struct HistoryItem: Codable, Equatable {
        let id: String
        let url: String
        let title: String
        let domain: String
        let etldPlusOne: String?
        let dateRelativeDay: String
        let dateShort: String
        let dateTimeOfDay: String
        let favicon: Favicon?
    }

    struct Favicon: Codable, Equatable {
        let maxAvailableSize: Int
        let src: String
    }
}

extension DataModel {
    struct Configuration: Codable, Equatable {
        let env: String
        let locale: String
        let platform: Platform
        let theme: String
        let themeVariant: String

        struct Platform: Codable, Equatable {
            let name: String
        }
    }

    struct ThemeUpdate: Codable, Equatable {
        let theme: String
        let themeVariant: String
    }

    struct Exception: Codable, Equatable {
        let message: String
    }

    struct GetRangesResponse: Codable, Equatable {
        let ranges: [HistoryRangeWithCount]
    }

    struct DeleteDomainRequest: Codable, Equatable {
        let domain: String
    }

    struct DeleteRangeRequest: Codable, Equatable {
        let range: HistoryRange
    }

    struct DeleteTermRequest: Codable, Equatable {
        let term: String
    }

    struct DeleteRangeResponse: Codable, Equatable {
        let action: DeleteDialogResponse
    }

    struct EntriesMenuRequest: Codable, Equatable {
        let ids: [String]
    }

    struct HistoryQueryInfo: Codable, Equatable {
        let finished: Bool
        let query: HistoryQueryKind
    }

    struct HistoryQueryResponse: Codable, Equatable {
        let info: HistoryQueryInfo
        let value: [HistoryItem]
    }

    struct HistoryOpenAction: Codable, Equatable {
        let url: String
    }
}

extension DataModel.HistoryRange {
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
        guard referenceDate >= date else {
            return nil
        }

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
        guard let weekday = weekday(for: referenceDate, calendar: calendar) else {
            return nil
        }

        let startOfReferenceDay = calendar.startOfDay(for: referenceDate)
        let startDate = self == .today
            ? startOfReferenceDay
            : calendar.firstWeekday(weekday, before: startOfReferenceDay)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startDate) else {
            return nil
        }

        if self == .older {
            return Date.distantPast..<nextDay
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

enum SumiHistoryFaviconURL {
    static let host = "favicon"

    static func url(for pageURL: URL) -> URL? {
        guard let encoded = pageURL.absoluteString.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) else {
            return nil
        }
        return URL(string: "sumi://\(host)/\(encoded)")
    }

    static func decode(from requestURL: URL) -> URL? {
        guard requestURL.scheme?.lowercased() == "sumi",
              requestURL.host?.lowercased() == host
        else {
            return nil
        }
        let encodedPath = URLComponents(
            url: requestURL,
            resolvingAgainstBaseURL: false
        )?.percentEncodedPath ?? requestURL.path
        let trimmed = encodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let decoded = trimmed.removingPercentEncoding else {
            return nil
        }
        return URL(string: decoded)
    }
}
