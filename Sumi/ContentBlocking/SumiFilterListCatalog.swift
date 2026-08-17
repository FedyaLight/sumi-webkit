import Foundation

struct SumiFilterListCatalog: Equatable, Sendable {
    struct List: Codable, Equatable, Identifiable, Sendable {
        enum Category: String, Codable, CaseIterable, Sendable {
            case ads
            case privacy
            case security
            case multipurpose
            case annoyances
            case experimental
            case custom
            case foreign
            case scripts

            var displayTitle: String {
                switch self {
                case .ads: "Ads"
                case .privacy: "Privacy"
                case .security: "Security"
                case .multipurpose: "Multipurpose"
                case .annoyances: "Annoyances"
                case .experimental: "Experimental"
                case .custom: "Custom"
                case .foreign: "Regional"
                case .scripts: "Scripts"
                }
            }
        }

        let id: String
        let displayName: String
        let url: URL
        let category: Category
        let defaultEnabled: Bool
        let description: String
        let languages: [String]?
        let trustLevel: String?
    }

    private struct Payload: Codable {
        let schemaVersion: Int
        let lists: [List]
    }

    static let supportedSchemaVersion = 1

    let lists: [List]

    var defaultEnabledIDs: Set<String> {
        Set(lists.lazy.filter(\.defaultEnabled).map(\.id))
    }

    var allIDs: Set<String> { Set(lists.map(\.id)) }

    var categories: [List.Category] {
        List.Category.allCases.filter { category in
            lists.contains { $0.category == category }
        }
    }

    static func bundled(in bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(
            forResource: "filter-catalog",
            withExtension: "json"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try load(from: url)
    }

    static func load(from url: URL) throws -> Self {
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.schemaVersion == supportedSchemaVersion else {
            throw CocoaError(.coderInvalidValue)
        }
        guard payload.lists.isEmpty == false,
              Set(payload.lists.map(\.id)).count == payload.lists.count
        else {
            throw CocoaError(.coderInvalidValue)
        }
        return Self(lists: payload.lists)
    }
}
