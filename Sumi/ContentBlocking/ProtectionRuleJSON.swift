import CryptoKit
import Foundation

enum ProtectionRuleJSON {
    static func canonicalHash(from encodedRuleList: String) throws -> String {
        let object = try object(from: encodedRuleList)
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ProtectionRuleJSONError.invalidJSONObject
        }
        do {
            let canonicalData = try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
            return SHA256.hash(data: canonicalData)
                .map { String(format: "%02x", $0) }
                .joined()
        } catch {
            throw ProtectionRuleJSONError.canonicalEncodingFailed(
                error.localizedDescription
            )
        }
    }

    static func urlFilterTokens(from encodedRuleList: String) throws -> [String] {
        let object = try object(from: encodedRuleList)
        guard let rules = object as? [[String: Any]] else {
            throw ProtectionRuleJSONError.ruleListTopLevelIsNotArray
        }
        return rules.compactMap { rule in
            guard let trigger = rule["trigger"] as? [String: Any],
                  let filter = trigger["url-filter"] as? String
            else { return nil }
            return domainToken(from: filter)
        }
    }

    private static func object(from encodedRuleList: String) throws -> Any {
        guard let data = encodedRuleList.data(using: .utf8) else {
            throw ProtectionRuleJSONError.nonUTF8Content
        }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ProtectionRuleJSONError.parseFailed(error.localizedDescription)
        }
    }

    private static func domainToken(from filter: String) -> String? {
        let pieces = filter.lowercased().split { character in
            !(character.isLetter
                || character.isNumber
                || character == "."
                || character == "-")
        }
        return pieces
            .map(String.init)
            .first { token in
                token.contains(".")
                    && !token.hasPrefix(".")
                    && !token.hasSuffix(".")
                    && token.count > 3
            }
    }
}

private enum ProtectionRuleJSONError: LocalizedError {
    case nonUTF8Content
    case parseFailed(String)
    case invalidJSONObject
    case canonicalEncodingFailed(String)
    case ruleListTopLevelIsNotArray

    var errorDescription: String? {
        switch self {
        case .nonUTF8Content:
            "rule-list content is not valid UTF-8"
        case .parseFailed(let reason):
            "rule-list JSON parsing failed: \(reason)"
        case .invalidJSONObject:
            "rule-list JSON cannot be serialized as canonical JSON"
        case .canonicalEncodingFailed(let reason):
            "rule-list canonical JSON encoding failed: \(reason)"
        case .ruleListTopLevelIsNotArray:
            "rule-list top-level JSON value is not an array"
        }
    }
}
