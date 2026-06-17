import Foundation

enum SumiBoostTextCaseOverride: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case uppercase
    case lowercase
    case capitalize

    var id: String { rawValue }

    var next: SumiBoostTextCaseOverride {
        switch self {
        case .none: return .uppercase
        case .uppercase: return .lowercase
        case .lowercase: return .capitalize
        case .capitalize: return .none
        }
    }
}

struct SumiBoostDotPosition: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
}

struct SumiBoostData: Codable, Equatable, Sendable {
    var boostName: String
    var dotAngleDeg: Double
    var dotPos: SumiBoostDotPosition
    var dotDistance: Double
    var secondaryDotAngleDegDelta: Double
    var secondaryDotPos: SumiBoostDotPosition
    var brightness: Double
    var saturation: Double
    var contrast: Double
    var fontFamily: String
    var enableColorBoost: Bool
    var smartInvert: Bool
    var autoTheme: Bool
    var textCaseOverride: SumiBoostTextCaseOverride
    var sizeOverride: Double
    var zapSelectors: [String]
    var customCSS: String
    var changeWasMade: Bool

    static func empty(named name: String = "My Boost") -> SumiBoostData {
        SumiBoostData(
            boostName: name,
            dotAngleDeg: 131.61,
            dotPos: SumiBoostDotPosition(x: 0.76, y: 0.66),
            dotDistance: 0.91,
            secondaryDotAngleDegDelta: 55,
            secondaryDotPos: SumiBoostDotPosition(x: 0.5, y: 0.81),
            brightness: 0.5,
            saturation: 0.5,
            contrast: 0.75,
            fontFamily: "",
            enableColorBoost: false,
            smartInvert: false,
            autoTheme: false,
            textCaseOverride: .none,
            sizeOverride: 1,
            zapSelectors: [],
            customCSS: "",
            changeWasMade: false
        )
    }
}

struct SumiBoost: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var profileId: UUID
    var host: String
    var data: SumiBoostData
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        profileId: UUID,
        host: String,
        data: SumiBoostData = .empty(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.profileId = profileId
        self.host = host
        self.data = data
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct SumiBoostDomainEntry: Codable, Equatable, Identifiable, Sendable {
    var profileId: UUID
    var host: String
    var activeBoostId: UUID?
    var boosts: [SumiBoost]
    var isEphemeral: Bool

    var id: String {
        "\(profileId.uuidString.lowercased())|\(host)"
    }
}

struct SumiBoostDomainKey: Codable, Equatable, Hashable, Sendable {
    var profileId: UUID
    var host: String

    init(profileId: UUID, host: String) {
        self.profileId = profileId
        self.host = host
    }
}

enum SumiBoostURLPolicy {
    static func normalizedBoostableHost(for url: URL?) -> String? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else {
            return nil
        }

        let normalized = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    static func key(for url: URL?, profileId: UUID?) -> SumiBoostDomainKey? {
        guard let profileId,
              let host = normalizedBoostableHost(for: url)
        else {
            return nil
        }
        return SumiBoostDomainKey(profileId: profileId, host: host)
    }
}

struct SumiBoostExportPackage: Codable, Equatable, Sendable {
    var version: Int
    var exportedAt: Date
    var boostName: String
    var data: SumiBoostData

    init(boost: SumiBoost, exportedAt: Date = Date()) {
        self.version = 1
        self.exportedAt = exportedAt
        self.boostName = boost.data.boostName
        self.data = boost.data
    }
}
