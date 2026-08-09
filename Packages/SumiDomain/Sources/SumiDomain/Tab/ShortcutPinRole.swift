import Foundation

public enum ShortcutPinRole: String, Codable, Sendable {
    case favorite
    case spacePinned

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if value == "essential" {
            self = .favorite
            return
        }
        guard let role = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported shortcut pin role: \(value)"
            )
        }
        self = role
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
