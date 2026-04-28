import Foundation

enum SumiPermissionType: Codable, Hashable, Sendable {
    case camera
    case microphone
    case cameraAndMicrophone
    case geolocation
    case notifications
    case popups
    case externalScheme(String)
    case autoplay
    case filePicker
    case storageAccess

    private enum CodingKeys: String, CodingKey {
        case type
        case scheme
    }

    private enum Kind: String, Codable {
        case camera
        case microphone
        case cameraAndMicrophone
        case geolocation
        case notifications
        case popups
        case externalScheme
        case autoplay
        case filePicker
        case storageAccess
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .camera:
            self = .camera
        case .microphone:
            self = .microphone
        case .cameraAndMicrophone:
            self = .cameraAndMicrophone
        case .geolocation:
            self = .geolocation
        case .notifications:
            self = .notifications
        case .popups:
            self = .popups
        case .externalScheme:
            let scheme = try container.decode(String.self, forKey: .scheme)
            self = .externalScheme(Self.normalizedExternalScheme(scheme))
        case .autoplay:
            self = .autoplay
        case .filePicker:
            self = .filePicker
        case .storageAccess:
            self = .storageAccess
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .camera:
            try container.encode(Kind.camera, forKey: .type)
        case .microphone:
            try container.encode(Kind.microphone, forKey: .type)
        case .cameraAndMicrophone:
            try container.encode(Kind.cameraAndMicrophone, forKey: .type)
        case .geolocation:
            try container.encode(Kind.geolocation, forKey: .type)
        case .notifications:
            try container.encode(Kind.notifications, forKey: .type)
        case .popups:
            try container.encode(Kind.popups, forKey: .type)
        case .externalScheme(let scheme):
            try container.encode(Kind.externalScheme, forKey: .type)
            try container.encode(Self.normalizedExternalScheme(scheme), forKey: .scheme)
        case .autoplay:
            try container.encode(Kind.autoplay, forKey: .type)
        case .filePicker:
            try container.encode(Kind.filePicker, forKey: .type)
        case .storageAccess:
            try container.encode(Kind.storageAccess, forKey: .type)
        }
    }

    static func == (lhs: SumiPermissionType, rhs: SumiPermissionType) -> Bool {
        lhs.identity == rhs.identity
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }

    var identity: String {
        switch self {
        case .camera:
            return "camera"
        case .microphone:
            return "microphone"
        case .cameraAndMicrophone:
            return "camera-and-microphone"
        case .geolocation:
            return "geolocation"
        case .notifications:
            return "notifications"
        case .popups:
            return "popups"
        case .externalScheme(let scheme):
            return "external-scheme:\(Self.normalizedExternalScheme(scheme))"
        case .autoplay:
            return "autoplay"
        case .filePicker:
            return "file-picker"
        case .storageAccess:
            return "storage-access"
        }
    }

    init?(identity: String) {
        switch identity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "camera":
            self = .camera
        case "microphone":
            self = .microphone
        case "camera-and-microphone":
            self = .cameraAndMicrophone
        case "geolocation":
            self = .geolocation
        case "notifications":
            self = .notifications
        case "popups":
            self = .popups
        case "autoplay":
            self = .autoplay
        case "file-picker":
            self = .filePicker
        case "storage-access":
            self = .storageAccess
        default:
            let prefix = "external-scheme:"
            guard identity.lowercased().hasPrefix(prefix) else { return nil }
            let scheme = String(identity.dropFirst(prefix.count))
            self = .externalScheme(Self.normalizedExternalScheme(scheme))
        }
    }

    var displayLabel: String {
        switch self {
        case .camera:
            return "Camera"
        case .microphone:
            return "Microphone"
        case .cameraAndMicrophone:
            return "Camera and Microphone"
        case .geolocation:
            return "Location"
        case .notifications:
            return "Notifications"
        case .popups:
            return "Pop-ups"
        case .externalScheme(let scheme):
            return "Open \(Self.normalizedExternalScheme(scheme)) Links"
        case .autoplay:
            return "Autoplay"
        case .filePicker:
            return "File Picker"
        case .storageAccess:
            return "Storage Access"
        }
    }

    var expandedForPersistence: [SumiPermissionType] {
        switch self {
        case .cameraAndMicrophone:
            return [.camera, .microphone]
        default:
            return [self]
        }
    }

    var isOneTimeOnly: Bool {
        self == .filePicker
    }

    var canBePersisted: Bool {
        switch self {
        case .cameraAndMicrophone, .filePicker:
            return false
        default:
            return true
        }
    }

    static func normalizedExternalScheme(_ scheme: String) -> String {
        scheme
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":/"))
            .lowercased()
    }
}
