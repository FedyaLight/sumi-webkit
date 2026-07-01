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
    var siteRules: [SafariExtensionSiteAccessRule]
    var privateAccessAllowed: Bool
    var hasRequestedOptionalAccessToAllHosts: Bool
    var updatedAt: Date

    @MainActor
    static func defaultPolicy(
        extensionId: String,
        profileId: UUID,
        seededRules: [SafariExtensionSiteAccessRule] = []
    ) -> SafariExtensionSiteAccessPolicy {
        SafariExtensionSiteAccessPolicy(
            profileId: profileId.uuidString.lowercased(),
            extensionId: extensionId,
            defaultAccess: .ask,
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
        guard let matchPattern = try? WKWebExtension.MatchPattern(string: trimmed) else {
            return trimmed
        }
        return matchPattern.string
    }

    @MainActor
    func accessLevel(for url: URL) -> SafariExtensionSiteAccessLevel {
        let matchingRules = siteRules.filter { rule in
            guard let matchPattern = try? WKWebExtension.MatchPattern(
                string: rule.matchPattern
            ) else {
                return false
            }
            return matchPattern.matches(url)
        }
        return Self.mostSpecificRule(in: matchingRules)?.access ?? defaultAccess
    }

    @MainActor
    func accessLevel(
        for matchPattern: WKWebExtension.MatchPattern
    ) -> SafariExtensionSiteAccessLevel {
        let coveringRules = siteRules.filter { rule in
            guard let rulePattern = try? WKWebExtension.MatchPattern(
                string: rule.matchPattern
            ) else {
                return false
            }
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
        guard let pattern = try? WKWebExtension.MatchPattern(string: patternString),
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
}
