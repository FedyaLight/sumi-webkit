import CryptoKit
import Foundation

enum SumiRemoveParamRuleBuilder {
    struct Artifact: Sendable {
        let hash: String
        let byteCount: Int
    }

    private struct Rule: Encodable {
        let id: Int
        let priority: Int
        let action: Action
        let condition: Condition
    }

    private struct Action: Encodable {
        let type: String
        let redirect: Redirect?
    }

    private struct Redirect: Encodable {
        let transform: Transform
    }

    private struct Transform: Encodable {
        let query: String?
        let queryTransform: QueryTransform?
    }

    private struct QueryTransform: Encodable {
        let removeParams: [String]
    }

    private struct Condition: Encodable {
        var urlFilter: String?
        var resourceTypes: [String]
        var initiatorDomains: [String]?
        var excludedInitiatorDomains: [String]?
        var requestDomains: [String]?
        var excludedRequestDomains: [String]?
        var domainType: String?
        var isUrlFilterCaseSensitive: Bool?
    }

    private struct Parsed {
        let isException: Bool
        let pattern: String
        let value: String
        let options: [(name: String, value: String?)]
    }

    private static let maximumRules = 5_000
    private static let ruleIDBase = 1_500_000
    private static let specialURLFilterCharacters = CharacterSet(
        charactersIn: "|*^"
    )
    private static let skippedOptions: Set<String> = [
        "app", "cname", "content", "cookie", "csp", "denyallow", "header",
        "hls", "jsonprune", "permissions", "redirect", "referrerpolicy",
        "removeheader", "replace", "strict1p", "strict3p", "urlblock",
        "webrtc",
    ]
    private static let recognizedOptions: Set<String> = [
        "removeparam", "domain", "to", "third-party", "~third-party",
        "match-case", "important", "badfilter", "document", "main_frame",
        "subdocument", "sub_frame", "stylesheet", "script", "image",
        "font", "object", "xmlhttprequest", "xhr", "ping", "media",
        "websocket", "other",
    ]
    private static let resourceTypes: [String: [String]] = [
        "document": ["main_frame", "sub_frame"],
        "main_frame": ["main_frame"],
        "subdocument": ["sub_frame"],
        "sub_frame": ["sub_frame"],
        "stylesheet": ["stylesheet"],
        "script": ["script"],
        "image": ["image"],
        "font": ["font"],
        "object": ["object"],
        "xmlhttprequest": ["xmlhttprequest"],
        "xhr": ["xmlhttprequest"],
        "ping": ["ping"],
        "media": ["media"],
        "websocket": ["websocket"],
        "other": ["other"],
    ]

    static func writeRules(
        from sourceURLs: [URL],
        to destination: URL
    ) throws -> Artifact {
        var rules: [Rule] = []
        rules.reserveCapacity(1_024)
        for sourceURL in sourceURLs {
            let content = try String(
                contentsOf: sourceURL,
                encoding: .utf8
            )
            for line in content.components(separatedBy: .newlines)
            where line.localizedCaseInsensitiveContains("removeparam") {
                guard rules.count < maximumRules,
                      let rule = makeRule(
                        line,
                        id: ruleIDBase + rules.count
                      )
                else {
                    continue
                }
                rules.append(rule)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(rules)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        return Artifact(
            hash: SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined(),
            byteCount: data.count
        )
    }

    private static func makeRule(_ rawLine: String, id: Int) -> Rule? {
        guard let parsed = parse(rawLine),
              parsed.options.contains(where: { $0.name == "badfilter" })
                == false,
              parsed.options.contains(where: { $0.name == "~removeparam" })
                == false,
              let condition = condition(parsed)
        else {
            return nil
        }
        let names = Set(parsed.options.map(\.name))
        let priority = parsed.isException
            ? 10_000
            : (names.contains("important") ? 1_000 : 1)
        let action: Action
        if parsed.isException {
            action = Action(type: "allow", redirect: nil)
        } else if parsed.value.isEmpty {
            action = Action(
                type: "redirect",
                redirect: Redirect(
                    transform: Transform(
                        query: "",
                        queryTransform: nil
                    )
                )
            )
        } else {
            guard let decoded = decode(parsed.value),
                  isLiteralParameter(decoded)
            else {
                return nil
            }
            action = Action(
                type: "redirect",
                redirect: Redirect(
                    transform: Transform(
                        query: nil,
                        queryTransform: QueryTransform(
                            removeParams: [decoded]
                        )
                    )
                )
            )
        }
        return Rule(
            id: id,
            priority: priority,
            action: action,
            condition: condition
        )
    }

    private static func parse(_ rawLine: String) -> Parsed? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.isEmpty == false,
              line.hasPrefix("!") == false,
              line.hasPrefix("#") == false,
              line.hasPrefix("[") == false
        else {
            return nil
        }
        let isException = line.hasPrefix("@@")
        if isException { line.removeFirst(2) }
        guard let separator = line.lastIndex(of: "$") else { return nil }
        let pattern = String(line[..<separator])
            .trimmingCharacters(in: .whitespaces)
        let values = line[line.index(after: separator)...]
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { option(String($0)) }
        guard let remove = values.first(where: { $0.name == "removeparam" })
        else {
            return nil
        }
        return Parsed(
            isException: isException,
            pattern: pattern,
            value: remove.value ?? "",
            options: values
        )
    }

    private static func option(
        _ raw: String
    ) -> (name: String, value: String?) {
        let parts = raw.split(
            separator: "=",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        return (
            String(parts[0])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
            parts.count == 2 ? String(parts[1]) : nil
        )
    }

    private static func condition(_ parsed: Parsed) -> Condition? {
        for option in parsed.options {
            if option.name.hasPrefix("~"),
               resourceTypes[String(option.name.dropFirst())] != nil {
                return nil
            }
            if skippedOptions.contains(option.name)
                || option.name == "method"
                || recognizedOptions.contains(option.name) == false {
                return nil
            }
        }
        guard parsed.value.hasPrefix("~") == false,
              parsed.value.hasPrefix("/") == false,
              parsed.value.contains("|") == false
        else {
            return nil
        }
        let trimmedPattern = parsed.pattern.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !(trimmedPattern.count > 1
            && trimmedPattern.hasPrefix("/")
            && trimmedPattern.hasSuffix("/"))
        else {
            return nil
        }
        var filter = normalizedPattern(trimmedPattern)
        if parsed.value.isEmpty == false {
            guard let decoded = decode(parsed.value),
                  isLiteralParameter(decoded),
                  decoded.rangeOfCharacter(
                    from: specialURLFilterCharacters
                  ) == nil
            else {
                return nil
            }
            let token = "^\(decoded)="
            filter = filter.map { "\($0)*\(token)" } ?? token
        }
        guard let initiator = domains(named: "domain", in: parsed.options),
              let request = domains(named: "to", in: parsed.options)
        else {
            return nil
        }
        var orderedTypes: [String] = []
        var seenTypes: Set<String> = []
        for option in parsed.options {
            for value in resourceTypes[option.name] ?? []
            where seenTypes.insert(value).inserted {
                orderedTypes.append(value)
            }
        }
        let names = Set(parsed.options.map(\.name))
        return Condition(
            urlFilter: filter,
            resourceTypes: orderedTypes.isEmpty
                ? ["main_frame", "sub_frame"]
                : orderedTypes,
            initiatorDomains: initiator.included.nilIfEmpty,
            excludedInitiatorDomains: initiator.excluded.nilIfEmpty,
            requestDomains: request.included.nilIfEmpty,
            excludedRequestDomains: request.excluded.nilIfEmpty,
            domainType: names.contains("third-party")
                ? "thirdParty"
                : (names.contains("~third-party") ? "firstParty" : nil),
            isUrlFilterCaseSensitive: names.contains("match-case")
                ? true
                : nil
        )
    }

    private static func normalizedPattern(_ value: String) -> String? {
        var pattern = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if pattern.isEmpty { return nil }
        if pattern.hasPrefix("||*") {
            pattern.removeFirst(2)
        }
        return pattern.isEmpty ? nil : pattern
    }

    private static func domains(
        named name: String,
        in options: [(name: String, value: String?)]
    ) -> (included: [String], excluded: [String])? {
        let matches = options.filter { $0.name == name }
        guard matches.isEmpty == false else { return ([], []) }
        guard matches.count == 1,
              let value = matches[0].value,
              value.isEmpty == false
        else {
            return nil
        }
        var included: [String] = []
        var excluded: [String] = []
        let rawDomains = value.split(
            separator: "|",
            omittingEmptySubsequences: false
        )
        guard rawDomains.allSatisfy({ $0.isEmpty == false }) else {
            return nil
        }
        for raw in rawDomains {
            var domain = String(raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let isExcluded = domain.hasPrefix("~")
            if isExcluded { domain.removeFirst() }
            guard validDomain(domain) else { return nil }
            if isExcluded {
                excluded.append(domain)
            } else {
                included.append(domain)
            }
        }
        return (included.sorted(), excluded.sorted())
    }

    private static func validDomain(_ value: String) -> Bool {
        value.isEmpty == false
            && value.contains("*") == false
            && value.contains("/") == false
            && value.contains(":") == false
            && value.allSatisfy {
                $0.isLetter || $0.isNumber || $0 == "." || $0 == "-"
            }
    }

    private static func decode(_ value: String) -> String? {
        value.removingPercentEncoding
    }

    private static func isLiteralParameter(_ value: String) -> Bool {
        value.isEmpty == false
            && value.trimmingCharacters(in: .whitespacesAndNewlines) == value
            && value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }
}

private extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
