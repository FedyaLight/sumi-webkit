import Foundation

struct SumiStorageAccessRequest: Sendable {
    let id: String
    let requestingDomain: String
    let currentDomain: String
    let quirkDomains: [String]
    let requestingOrigin: SumiPermissionOrigin

    init(
        id: String = UUID().uuidString,
        requestingDomain: String,
        currentDomain: String,
        quirkDomains: [String] = []
    ) {
        let normalizedRequestingDomain = Self.normalizedDomain(requestingDomain)
        let normalizedCurrentDomain = Self.normalizedDomain(currentDomain)
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString : id
        self.requestingDomain = normalizedRequestingDomain
        self.currentDomain = normalizedCurrentDomain
        self.quirkDomains = quirkDomains.map(Self.normalizedDomain).filter { !$0.isEmpty }
        self.requestingOrigin = Self.origin(from: normalizedRequestingDomain)
    }

    static func origin(from domain: String) -> SumiPermissionOrigin {
        let normalized = normalizedDomain(domain)
        guard !normalized.isEmpty else {
            return .invalid(reason: "missing-storage-access-requesting-domain")
        }

        if normalized.contains("://") {
            return SumiPermissionOrigin(string: normalized)
        }

        guard let url = URL(string: "https://\(normalized)") else {
            return .invalid(reason: "malformed-storage-access-requesting-domain")
        }
        return SumiPermissionOrigin(url: url)
    }

    private static func normalizedDomain(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }
}

struct SumiStorageAccessTabContext: Sendable {
    let tabId: String
    let pageId: String
    let profilePartitionId: String
    let isEphemeralProfile: Bool
    let committedURL: URL?
    let visibleURL: URL?
    let mainFrameURL: URL?
    let isActiveTab: Bool
    let isVisibleTab: Bool
    let navigationOrPageGeneration: String?

    init(
        tabId: String,
        pageId: String,
        profilePartitionId: String,
        isEphemeralProfile: Bool,
        committedURL: URL?,
        visibleURL: URL?,
        mainFrameURL: URL?,
        isActiveTab: Bool,
        isVisibleTab: Bool,
        navigationOrPageGeneration: String?
    ) {
        self.tabId = tabId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.pageId = pageId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.profilePartitionId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        self.isEphemeralProfile = isEphemeralProfile
        self.committedURL = committedURL
        self.visibleURL = visibleURL
        self.mainFrameURL = mainFrameURL
        self.isActiveTab = isActiveTab
        self.isVisibleTab = isVisibleTab
        self.navigationOrPageGeneration = navigationOrPageGeneration?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
