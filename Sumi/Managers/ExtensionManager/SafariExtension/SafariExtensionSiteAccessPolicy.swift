//
//  SafariExtensionSiteAccessPolicy.swift
//  Sumi
//
//  Profile-scoped website access settings for native WebKit extensions.
//

import Foundation
import WebKit

enum SafariExtensionSiteAccessLevel: String, Codable, CaseIterable, Identifiable {
    case ask
    case allow
    case deny

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask:
            return "Ask"
        case .allow:
            return "Allow"
        case .deny:
            return "Deny"
        }
    }

    var status: WKWebExtensionContext.PermissionStatus {
        switch self {
        case .ask:
            return .unknown
        case .allow:
            return .grantedExplicitly
        case .deny:
            return .deniedExplicitly
        }
    }

    var diagnosticDecisionSource: SafariExtensionSiteAccessDecisionSource {
        switch self {
        case .ask:
            return .askOrUnknown
        case .allow:
            return .defaultOtherWebsites
        case .deny:
            return .explicitDeny
        }
    }
}

struct SafariExtensionSiteAccessRule: Codable, Equatable, Identifiable {
    var matchPattern: String
    var access: SafariExtensionSiteAccessLevel
    var expiresAt: Date?
    var updatedAt: Date

    var id: String { matchPattern }

    func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

struct SafariExtensionSiteAccessPolicy: Codable, Equatable {
    var profileId: String
    var extensionId: String
    var defaultAccess: SafariExtensionSiteAccessLevel
    /// True only when the user explicitly chose the default access level in
    /// Sumi settings. Auto-created and prompt-derived policies keep this false
    /// so Safari-appex default-access seeding can still apply the product
    /// default even after per-site prompt rules or the private-browsing
    /// toggle have been persisted.
    var defaultAccessConfiguredByUser: Bool
    var siteRules: [SafariExtensionSiteAccessRule]
    var privateAccessAllowed: Bool
    var hasRequestedOptionalAccessToAllHosts: Bool
    var updatedAt: Date

    init(
        profileId: String,
        extensionId: String,
        defaultAccess: SafariExtensionSiteAccessLevel,
        defaultAccessConfiguredByUser: Bool = false,
        siteRules: [SafariExtensionSiteAccessRule],
        privateAccessAllowed: Bool,
        hasRequestedOptionalAccessToAllHosts: Bool,
        updatedAt: Date
    ) {
        self.profileId = profileId
        self.extensionId = extensionId
        self.defaultAccess = defaultAccess
        self.defaultAccessConfiguredByUser = defaultAccessConfiguredByUser
        self.siteRules = siteRules
        self.privateAccessAllowed = privateAccessAllowed
        self.hasRequestedOptionalAccessToAllHosts = hasRequestedOptionalAccessToAllHosts
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileId = try container.decode(String.self, forKey: .profileId)
        extensionId = try container.decode(String.self, forKey: .extensionId)
        defaultAccess = try container.decode(
            SafariExtensionSiteAccessLevel.self,
            forKey: .defaultAccess
        )
        defaultAccessConfiguredByUser = try container.decodeIfPresent(
            Bool.self,
            forKey: .defaultAccessConfiguredByUser
        ) ?? false
        siteRules = try container.decode(
            [SafariExtensionSiteAccessRule].self,
            forKey: .siteRules
        )
        privateAccessAllowed = try container.decode(
            Bool.self,
            forKey: .privateAccessAllowed
        )
        hasRequestedOptionalAccessToAllHosts = try container.decode(
            Bool.self,
            forKey: .hasRequestedOptionalAccessToAllHosts
        )
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    @MainActor
    static func defaultPolicy(
        extensionId: String,
        profileId: UUID,
        seededRules: [SafariExtensionSiteAccessRule] = [],
        defaultAccess: SafariExtensionSiteAccessLevel = .ask
    ) -> SafariExtensionSiteAccessPolicy {
        SafariExtensionSiteAccessPolicy(
            profileId: profileId.uuidString.lowercased(),
            extensionId: extensionId,
            defaultAccess: defaultAccess,
            siteRules: normalizedRules(seededRules),
            privateAccessAllowed: false,
            hasRequestedOptionalAccessToAllHosts: false,
            updatedAt: Date()
        )
    }

    @MainActor
    func normalized() -> SafariExtensionSiteAccessPolicy {
        var copy = self
        copy.profileId = profileId.lowercased()
        copy.siteRules = Self.normalizedRules(siteRules)
        return copy
    }

    @MainActor
    static func normalizedRules(
        _ rules: [SafariExtensionSiteAccessRule]
    ) -> [SafariExtensionSiteAccessRule] {
        var rulesByPattern: [String: SafariExtensionSiteAccessRule] = [:]
        for rule in rules {
            guard rule.isExpired() == false else { continue }
            let normalizedPattern =
                SafariExtensionSiteAccessPolicy.normalizedMatchPatternString(
                    rule.matchPattern
                )
            guard normalizedPattern.isEmpty == false else { continue }
            rulesByPattern[normalizedPattern] = SafariExtensionSiteAccessRule(
                matchPattern: normalizedPattern,
                access: rule.access,
                expiresAt: rule.expiresAt,
                updatedAt: rule.updatedAt
            )
        }
        return rulesByPattern.values.sorted {
            $0.matchPattern.localizedCaseInsensitiveCompare($1.matchPattern)
                == .orderedAscending
        }
    }

    @MainActor
    static func normalizedMatchPatternString(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        guard let matchPattern = matchPattern(
            from: trimmed,
            purpose: "normalize"
        ) else {
            return trimmed
        }
        return matchPattern.string
    }

    @MainActor
    func accessLevel(for url: URL) -> SafariExtensionSiteAccessLevel {
        let matchingRules = siteRules.filter { rule in
            guard let matchPattern = Self.matchPattern(
                from: rule.matchPattern,
                purpose: "urlAccess"
            ) else { return false }
            return matchPattern.matches(url)
        }
        return Self.mostSpecificRule(in: matchingRules)?.access ?? defaultAccess
    }

    @MainActor
    func accessLevel(
        for matchPattern: WKWebExtension.MatchPattern
    ) -> SafariExtensionSiteAccessLevel {
        let coveringRules = siteRules.filter { rule in
            guard let rulePattern = Self.matchPattern(
                from: rule.matchPattern,
                purpose: "patternAccess"
            ) else { return false }
            return rulePattern.matches(matchPattern)
        }
        return Self.mostSpecificRule(in: coveringRules)?.access ?? defaultAccess
    }

    @MainActor
    var rulesByIncreasingSpecificity: [SafariExtensionSiteAccessRule] {
        siteRules.sorted { lhs, rhs in
            Self.isLessSpecific(lhs, than: rhs)
        }
    }

    @MainActor
    private static func mostSpecificRule(
        in rules: [SafariExtensionSiteAccessRule]
    ) -> SafariExtensionSiteAccessRule? {
        rules.max { lhs, rhs in
            isLessSpecific(lhs, than: rhs)
        }
    }

    @MainActor
    private static func isLessSpecific(
        _ lhs: SafariExtensionSiteAccessRule,
        than rhs: SafariExtensionSiteAccessRule
    ) -> Bool {
        let lhsScore = matchPatternSpecificityScore(lhs.matchPattern)
        let rhsScore = matchPatternSpecificityScore(rhs.matchPattern)
        if lhsScore != rhsScore {
            return lhsScore < rhsScore
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt < rhs.updatedAt
        }
        return lhs.matchPattern.localizedCaseInsensitiveCompare(rhs.matchPattern)
            == .orderedDescending
    }

    @MainActor
    private static func matchPatternSpecificityScore(_ patternString: String) -> Int {
        guard let pattern = matchPattern(
                from: patternString,
                purpose: "specificity"
              ),
              pattern.matchesAllURLs == false
        else {
            return 0
        }

        var score = 0
        if let host = pattern.host, pattern.matchesAllHosts == false {
            let literalHost = host
                .replacingOccurrences(of: "*.", with: "")
                .replacingOccurrences(of: "*", with: "")
            score += host.contains("*") ? 70_000 : 100_000
            score += literalHost.count * 10
        }
        if let scheme = pattern.scheme, scheme != "*" {
            score += 10_000
        }
        if let path = pattern.path, path != "/*" {
            let literalPath = path.replacingOccurrences(of: "*", with: "")
            score += 1_000 + min(literalPath.count, 500)
        }
        return score
    }

    @MainActor
    private static func matchPattern(
        from value: String,
        purpose: String
    ) -> WKWebExtension.MatchPattern? {
        do {
            return try WKWebExtension.MatchPattern(string: value)
        } catch {
            RuntimeDiagnostics.debug(
                category: SafariExtensionPermissionLifecycleDiagnostics.category
            ) {
                let bucket = SafariExtensionPermissionLifecycleDiagnostics.bucket(value)
                    ?? "empty"
                return "Ignoring invalid site access match pattern: purpose=\(purpose) patternBucket=\(bucket) error=\(error.localizedDescription)"
            }
            return nil
        }
    }
}
