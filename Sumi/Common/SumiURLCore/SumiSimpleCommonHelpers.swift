import Foundation
import os.log

extension Date {
    static var sumiWeekAgo: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    }

    static var sumiMonthAgo: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    }
}

struct SumiNavigationalScheme: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    static let http = SumiNavigationalScheme(rawValue: "http")
    static let https = SumiNavigationalScheme(rawValue: "https")
    static let ftp = SumiNavigationalScheme(rawValue: "ftp")
    static let file = SumiNavigationalScheme(rawValue: "file")
    static let data = SumiNavigationalScheme(rawValue: "data")
    static let blob = SumiNavigationalScheme(rawValue: "blob")
    static let about = SumiNavigationalScheme(rawValue: "about")
    static let duck = SumiNavigationalScheme(rawValue: "duck")
    static let mailto = SumiNavigationalScheme(rawValue: "mailto")
    static let webkitExtension = SumiNavigationalScheme(rawValue: "webkit-extension")
    static let javascript = SumiNavigationalScheme(rawValue: "javascript")
}

extension URL {
    var sumiIsEmpty: Bool {
        absoluteString.isEmpty
    }

    var sumiRoot: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    var sumiNavigationalScheme: SumiNavigationalScheme? {
        scheme.map(SumiNavigationalScheme.init(rawValue:))
    }

    func sumiAppending(_ path: String) -> URL {
        appendingPathComponent(path)
    }

    func sumiToHttps() -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        guard components.scheme == "http" else { return self }
        components.scheme = "https"
        return components.url
    }
}

struct SumiDecodableHelper {
    static func decode<T: Decodable>(from object: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object)
        else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

extension Logger {
    static let sumiGeneral = Logger(subsystem: "General", category: "")
}
