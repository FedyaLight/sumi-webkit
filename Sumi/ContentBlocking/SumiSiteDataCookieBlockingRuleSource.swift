import Foundation

@MainActor
protocol SumiSiteDataContentRuleProviding: AnyObject {
    func ruleLists(profileId: UUID?) throws -> [SumiContentRuleListDefinition]
}

@MainActor
final class SumiSiteDataCookieBlockingRuleSource: SumiSiteDataContentRuleProviding {
    private let policyStore: SumiSiteDataPolicyStore

    init(policyStore: SumiSiteDataPolicyStore? = nil) {
        self.policyStore = policyStore ?? .shared
    }

    func ruleLists(profileId: UUID?) throws -> [SumiContentRuleListDefinition] {
        let hosts = policyStore.hostsBlockingStorage(profileId: profileId)
            .map(\.normalizedWebsiteDataDomain)
            .filter { !$0.isEmpty }
            .sorted()
        guard !hosts.isEmpty else { return [] }

        let rules = hosts.map { host in
            CookieBlockingRule(
                trigger: Trigger(
                    urlFilter: ".*",
                    ifDomain: ["*\(host)"],
                    loadType: ["first-party", "third-party"]
                ),
                action: Action(type: "block-cookies")
            )
        }

        let encodedRules = try JSONEncoder().encode(rules)
        let encodedRuleList = String(data: encodedRules, encoding: .utf8) ?? "[]"
        return [
            SumiContentRuleListDefinition(
                name: "SumiSiteDataCookieBlocking-\(profileId?.uuidString.lowercased() ?? "global")",
                encodedContentRuleList: encodedRuleList
            )
        ]
    }

    private struct CookieBlockingRule: Codable {
        let trigger: Trigger
        let action: Action
    }

    private struct Trigger: Codable {
        let urlFilter: String
        let ifDomain: [String]
        let loadType: [String]

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case ifDomain = "if-domain"
            case loadType = "load-type"
        }
    }

    private struct Action: Codable {
        let type: String
    }
}
