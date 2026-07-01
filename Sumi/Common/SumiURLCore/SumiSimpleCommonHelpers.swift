import Foundation
import os.log

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
    static let webkitExtension = SumiNavigationalScheme(rawValue: "webkit-extension")
    static let javascript = SumiNavigationalScheme(rawValue: "javascript")
}

extension URL {
    var sumiIsEmpty: Bool {
        absoluteString.isEmpty
    }

    var sumiNavigationalScheme: SumiNavigationalScheme? {
        scheme.map(SumiNavigationalScheme.init(rawValue:))
    }

    var sumiIsGlancePreviewableLink: Bool {
        switch sumiNavigationalScheme {
        case .http, .https, .file:
            return true
        default:
            return false
        }
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
