import Foundation

enum SumiNotificationPayloadKind: String, Codable, Equatable, Hashable, Sendable {
    case website
    case userscript
}

struct SumiNotificationPayload: Codable, Equatable, Sendable {
    let identifier: SumiNotificationIdentifier
    let kind: SumiNotificationPayloadKind
    let title: String
    let body: String
    let iconURL: URL?
    let imageURL: URL?
    let tag: String?
    let isSilent: Bool
    let userInfo: [String: String]

    init(
        identifier: SumiNotificationIdentifier,
        kind: SumiNotificationPayloadKind,
        title: String,
        body: String,
        iconURL: URL? = nil,
        imageURL: URL? = nil,
        tag: String? = nil,
        isSilent: Bool = false,
        userInfo: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.kind = kind
        self.title = Self.sanitized(title, maxLength: 256, fallback: "Sumi")
        self.body = Self.sanitized(body, maxLength: 1024, fallback: "")
        self.iconURL = iconURL
        self.imageURL = imageURL
        self.tag = Self.sanitizedOptional(tag, maxLength: 128)
        self.isSilent = isSilent
        self.userInfo = userInfo.mapValues {
            Self.sanitized($0, maxLength: 512, fallback: "")
        }
    }

    private static func sanitizedOptional(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        let sanitized = sanitized(value, maxLength: maxLength, fallback: "")
        return sanitized.isEmpty ? nil : sanitized
    }

    private static func sanitized(_ value: String, maxLength: Int, fallback: String) -> String {
        let filteredScalars = value.unicodeScalars.filter { scalar in
            scalar.value >= 0x20 || scalar == "\n" || scalar == "\t"
        }
        var result = String(String.UnicodeScalarView(filteredScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count > maxLength {
            result = String(result.prefix(maxLength))
        }
        return result.isEmpty ? fallback : result
    }
}
