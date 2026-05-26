//
//  ChromeMV3NetworkCompatibility.swift
//  Sumi
//
//  Internal synthetic Chrome MV3 declarativeNetRequest/webRequest
//  compatibility foundation. This layer parses extension-local rules, stores
//  fixture-only dynamic/session state, evaluates synthetic request records, and
//  reports compatibility blockers. It does not intercept product requests,
//  attach content blockers, observe product navigation, or expose a normal-tab
//  runtime bridge.
//

import CryptoKit
import Foundation

enum ChromeMV3DNRSupportStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case deferred
    case partial
    case supported
    case unsupported

    static func < (
        lhs: ChromeMV3DNRSupportStatus,
        rhs: ChromeMV3DNRSupportStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3DNRDiagnosticSeverity:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case error
    case info
    case warning

    static func < (
        lhs: ChromeMV3DNRDiagnosticSeverity,
        rhs: ChromeMV3DNRDiagnosticSeverity
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3DNRDiagnostic:
    Codable,
    Equatable,
    Sendable
{
    var code: String
    var severity: ChromeMV3DNRDiagnosticSeverity
    var field: String?
    var message: String
}

enum ChromeMV3DNRRuleSourceKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case dynamic
    case session
    case staticRuleset

    static func < (
        lhs: ChromeMV3DNRRuleSourceKind,
        rhs: ChromeMV3DNRRuleSourceKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3DNRRuleActionType:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case allow
    case allowAllRequests = "allowAllRequests"
    case block
    case modifyHeaders = "modifyHeaders"
    case redirect
    case removeHeaders = "removeHeaders"
    case unknown
    case upgradeScheme = "upgradeScheme"

    static func < (
        lhs: ChromeMV3DNRRuleActionType,
        rhs: ChromeMV3DNRRuleActionType
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var supportStatus: ChromeMV3DNRSupportStatus {
        switch self {
        case .allow, .block, .upgradeScheme:
            return .supported
        case .allowAllRequests:
            return .partial
        case .redirect:
            return .deferred
        case .modifyHeaders, .removeHeaders, .unknown:
            return .unsupported
        }
    }

    var precedence: Int {
        switch self {
        case .allowAllRequests:
            return 600
        case .allow:
            return 500
        case .block:
            return 400
        case .upgradeScheme:
            return 300
        case .redirect:
            return 200
        case .modifyHeaders, .removeHeaders:
            return 100
        case .unknown:
            return 0
        }
    }
}

enum ChromeMV3DNRResourceType:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case cspReport = "csp_report"
    case font
    case image
    case mainFrame = "main_frame"
    case media
    case object
    case other
    case ping
    case script
    case stylesheet
    case subFrame = "sub_frame"
    case webbundle
    case websocket
    case webtransport
    case xmlhttprequest

    static func < (
        lhs: ChromeMV3DNRResourceType,
        rhs: ChromeMV3DNRResourceType
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3DNRRuleAction:
    Codable,
    Equatable,
    Sendable
{
    var type: ChromeMV3DNRRuleActionType
    var redirectURL: String?
    var rawType: String?
    var supportStatus: ChromeMV3DNRSupportStatus
    var diagnostics: [ChromeMV3DNRDiagnostic]

    var storageValue: ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "type": .string(type.rawValue),
            "supportStatus": .string(supportStatus.rawValue),
        ]
        if let redirectURL {
            object["redirect"] = .object(["url": .string(redirectURL)])
        }
        if let rawType {
            object["rawType"] = .string(rawType)
        }
        return .object(object)
    }
}

struct ChromeMV3DNRRuleCondition:
    Codable,
    Equatable,
    Sendable
{
    var urlFilter: String?
    var regexFilter: String?
    var resourceTypes: [ChromeMV3DNRResourceType]
    var excludedResourceTypes: [ChromeMV3DNRResourceType]
    var requestDomains: [String]
    var excludedRequestDomains: [String]
    var initiatorDomains: [String]
    var excludedInitiatorDomains: [String]
    var tabIDs: [Int]
    var excludedTabIDs: [Int]
    var unsupportedFields: [String]
    var diagnostics: [ChromeMV3DNRDiagnostic]

    var supportStatus: ChromeMV3DNRSupportStatus {
        unsupportedFields.isEmpty ? .supported : .partial
    }

    var storageValue: ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [:]
        if let urlFilter { object["urlFilter"] = .string(urlFilter) }
        if let regexFilter { object["regexFilter"] = .string(regexFilter) }
        if resourceTypes.isEmpty == false {
            object["resourceTypes"] =
                .array(resourceTypes.map { .string($0.rawValue) })
        }
        if excludedResourceTypes.isEmpty == false {
            object["excludedResourceTypes"] =
                .array(excludedResourceTypes.map { .string($0.rawValue) })
        }
        if requestDomains.isEmpty == false {
            object["requestDomains"] =
                .array(requestDomains.map(ChromeMV3StorageValue.string))
        }
        if excludedRequestDomains.isEmpty == false {
            object["excludedRequestDomains"] =
                .array(excludedRequestDomains.map(ChromeMV3StorageValue.string))
        }
        if initiatorDomains.isEmpty == false {
            object["initiatorDomains"] =
                .array(initiatorDomains.map(ChromeMV3StorageValue.string))
        }
        if excludedInitiatorDomains.isEmpty == false {
            object["excludedInitiatorDomains"] =
                .array(excludedInitiatorDomains.map(ChromeMV3StorageValue.string))
        }
        if tabIDs.isEmpty == false {
            object["tabIds"] = .array(tabIDs.map { .number(Double($0)) })
        }
        if excludedTabIDs.isEmpty == false {
            object["excludedTabIds"] =
                .array(excludedTabIDs.map { .number(Double($0)) })
        }
        return .object(object)
    }
}

struct ChromeMV3DNRRule:
    Codable,
    Equatable,
    Sendable
{
    var id: Int
    var priority: Int
    var action: ChromeMV3DNRRuleAction
    var condition: ChromeMV3DNRRuleCondition
    var rulesetID: String
    var sourceKind: ChromeMV3DNRRuleSourceKind
    var supportStatus: ChromeMV3DNRSupportStatus
    var diagnostics: [ChromeMV3DNRDiagnostic]

    var storageValue: ChromeMV3StorageValue {
        .object([
            "id": .number(Double(id)),
            "priority": .number(Double(priority)),
            "action": action.storageValue,
            "condition": condition.storageValue,
            "rulesetId": .string(rulesetID),
            "sourceKind": .string(sourceKind.rawValue),
            "supportStatus": .string(supportStatus.rawValue),
        ])
    }
}

struct ChromeMV3DNRRuleParseResult:
    Codable,
    Equatable,
    Sendable
{
    var rulesetID: String
    var sourceKind: ChromeMV3DNRRuleSourceKind
    var rules: [ChromeMV3DNRRule]
    var diagnostics: [ChromeMV3DNRDiagnostic]

    var duplicateRuleIDs: [Int] {
        let counts = Dictionary(grouping: rules.map(\.id), by: { $0 })
            .mapValues(\.count)
        return counts
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
    }

    var unsupportedFeatureCount: Int {
        rules.reduce(0) { partial, rule in
            partial
                + (rule.supportStatus == .unsupported ? 1 : 0)
                + rule.condition.unsupportedFields.count
                + rule.action.diagnostics.filter {
                    $0.severity == .warning || $0.severity == .error
                }.count
        }
    }

    var validRules: [ChromeMV3DNRRule] {
        rules.filter { rule in
            rule.diagnostics.contains { $0.severity == .error } == false
        }
    }
}

private struct ChromeMV3DNRRuleParseFailure: Error {
    var diagnostics: [ChromeMV3DNRDiagnostic]
}

struct ChromeMV3DNRRulesetResourceModel:
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var enabledByDefault: Bool
    var manifestPath: String?
    var generatedBundleResourcePath: String?
    var parsedRuleCount: Int
    var validRuleCount: Int
    var duplicateRuleIDs: [Int]
    var unsupportedFeatureCount: Int
    var validationStatus: ChromeMV3DNRSupportStatus
    var diagnostics: [ChromeMV3DNRDiagnostic]
    var rules: [ChromeMV3DNRRule]
}

struct ChromeMV3DNRManifestRulesetModel:
    Codable,
    Equatable,
    Sendable
{
    var declaresDeclarativeNetRequest: Bool
    var rulesets: [ChromeMV3DNRRulesetResourceModel]
    var totalParsedRuleCount: Int
    var totalValidRuleCount: Int
    var enabledRulesetIDs: [String]
    var unsupportedFeatureCount: Int
    var dnrAvailableInInternalEvaluator: Bool
    var dnrAvailableInProduct: Bool
    var dnrProductEnforcementAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [ChromeMV3DNRDiagnostic]

    static let empty = ChromeMV3DNRManifestRulesetModel(
        declaresDeclarativeNetRequest: false,
        rulesets: [],
        totalParsedRuleCount: 0,
        totalValidRuleCount: 0,
        enabledRulesetIDs: [],
        unsupportedFeatureCount: 0,
        dnrAvailableInInternalEvaluator: false,
        dnrAvailableInProduct: false,
        dnrProductEnforcementAvailable: false,
        normalTabRuntimeBridgeAvailable: false,
        runtimeLoadable: false,
        diagnostics: [
            ChromeMV3DNRDiagnostic(
                code: "dnrNotDeclared",
                severity: .info,
                field: "declarative_net_request",
                message: "Manifest does not declare declarative_net_request."
            ),
        ]
    )
}

enum ChromeMV3DNRRuleParser {
    static func parseRules(
        data: Data,
        rulesetID: String,
        sourceKind: ChromeMV3DNRRuleSourceKind
    ) -> ChromeMV3DNRRuleParseResult {
        do {
            let value = try JSONSerialization.jsonObject(with: data)
            guard let rawRules = value as? [[String: Any]] else {
                return ChromeMV3DNRRuleParseResult(
                    rulesetID: rulesetID,
                    sourceKind: sourceKind,
                    rules: [],
                    diagnostics: [
                        diagnostic(
                            "invalidRulesetJSONShape",
                            .error,
                            "rules",
                            "DNR ruleset JSON must be an array of rule objects."
                        ),
                    ]
                )
            }
            return parseRuleObjects(
                rawRules,
                rulesetID: rulesetID,
                sourceKind: sourceKind
            )
        } catch {
            return ChromeMV3DNRRuleParseResult(
                rulesetID: rulesetID,
                sourceKind: sourceKind,
                rules: [],
                diagnostics: [
                    diagnostic(
                        "invalidRulesetJSON",
                        .error,
                        "rules",
                        "DNR ruleset JSON could not be parsed: \(error.localizedDescription)"
                    ),
                ]
            )
        }
    }

    static func parseRuleValues(
        _ values: [ChromeMV3StorageValue],
        rulesetID: String,
        sourceKind: ChromeMV3DNRRuleSourceKind
    ) -> ChromeMV3DNRRuleParseResult {
        let rawRules = values.compactMap { $0.dnrFoundationObject as? [String: Any] }
        guard rawRules.count == values.count else {
            return ChromeMV3DNRRuleParseResult(
                rulesetID: rulesetID,
                sourceKind: sourceKind,
                rules: [],
                diagnostics: [
                    diagnostic(
                        "invalidRuleValue",
                        .error,
                        "rules",
                        "DNR rule updates must contain JSON object rules."
                    ),
                ]
            )
        }
        return parseRuleObjects(
            rawRules,
            rulesetID: rulesetID,
            sourceKind: sourceKind
        )
    }

    private static func parseRuleObjects(
        _ rawRules: [[String: Any]],
        rulesetID: String,
        sourceKind: ChromeMV3DNRRuleSourceKind
    ) -> ChromeMV3DNRRuleParseResult {
        var rules: [ChromeMV3DNRRule] = []
        var diagnostics: [ChromeMV3DNRDiagnostic] = []
        for (index, object) in rawRules.enumerated() {
            switch parseRule(
                object,
                index: index,
                rulesetID: rulesetID,
                sourceKind: sourceKind
            ) {
            case .success(let rule):
                rules.append(rule)
            case .failure(let failure):
                diagnostics.append(contentsOf: failure.diagnostics)
            }
        }

        let duplicateIDs = Dictionary(grouping: rules.map(\.id), by: { $0 })
            .mapValues(\.count)
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
        for id in duplicateIDs {
            diagnostics.append(
                diagnostic(
                    "duplicateRuleID",
                    .error,
                    "id",
                    "DNR rule id \(id) is duplicated in ruleset \(rulesetID)."
                )
            )
        }

        return ChromeMV3DNRRuleParseResult(
            rulesetID: rulesetID,
            sourceKind: sourceKind,
            rules: rules.sorted(by: deterministicRuleOrder),
            diagnostics: uniqueDiagnostics(diagnostics)
        )
    }

    private static func parseRule(
        _ object: [String: Any],
        index: Int,
        rulesetID: String,
        sourceKind: ChromeMV3DNRRuleSourceKind
    ) -> Result<ChromeMV3DNRRule, ChromeMV3DNRRuleParseFailure> {
        var diagnostics: [ChromeMV3DNRDiagnostic] = []
        let supportedRuleKeys: Set<String> = [
            "action",
            "condition",
            "id",
            "priority",
        ]
        for key in object.keys.sorted()
        where supportedRuleKeys.contains(key) == false {
            diagnostics.append(
                diagnostic(
                    "unsupportedRuleField",
                    .warning,
                    "rules[\(index)].\(key)",
                    "DNR rule field \(key) is not modeled by Sumi's internal synthetic evaluator."
                )
            )
        }

        guard let id = intValue(object["id"]), id > 0 else {
            diagnostics.append(
                diagnostic(
                    "invalidRuleID",
                    .error,
                    "rules[\(index)].id",
                    "DNR rule id must be a positive integer."
                )
            )
            return .failure(ChromeMV3DNRRuleParseFailure(diagnostics: diagnostics))
        }

        let priority = intValue(object["priority"]) ?? 1
        guard priority > 0 else {
            diagnostics.append(
                diagnostic(
                    "invalidRulePriority",
                    .error,
                    "rules[\(index)].priority",
                    "DNR rule priority must be a positive integer when present."
                )
            )
            return .failure(ChromeMV3DNRRuleParseFailure(diagnostics: diagnostics))
        }

        guard let actionObject = object["action"] as? [String: Any] else {
            diagnostics.append(
                diagnostic(
                    "missingRuleAction",
                    .error,
                    "rules[\(index)].action",
                    "DNR rule action must be an object."
                )
            )
            return .failure(ChromeMV3DNRRuleParseFailure(diagnostics: diagnostics))
        }

        guard let conditionObject = object["condition"] as? [String: Any] else {
            diagnostics.append(
                diagnostic(
                    "missingRuleCondition",
                    .error,
                    "rules[\(index)].condition",
                    "DNR rule condition must be an object."
                )
            )
            return .failure(ChromeMV3DNRRuleParseFailure(diagnostics: diagnostics))
        }

        let action = parseAction(actionObject, index: index)
        let condition = parseCondition(conditionObject, index: index)
        diagnostics.append(contentsOf: action.diagnostics)
        diagnostics.append(contentsOf: condition.diagnostics)

        let status = combinedStatus([
            action.supportStatus,
            condition.supportStatus,
            diagnostics.contains { $0.severity == .error }
                ? .unsupported
                : .supported,
        ])

        return .success(
            ChromeMV3DNRRule(
                id: id,
                priority: priority,
                action: action,
                condition: condition,
                rulesetID: rulesetID,
                sourceKind: sourceKind,
                supportStatus: status,
                diagnostics: uniqueDiagnostics(diagnostics)
            )
        )
    }

    private static func parseAction(
        _ object: [String: Any],
        index: Int
    ) -> ChromeMV3DNRRuleAction {
        var diagnostics: [ChromeMV3DNRDiagnostic] = []
        let supportedActionKeys: Set<String> = [
            "requestHeaders",
            "redirect",
            "responseHeaders",
            "type",
        ]
        for key in object.keys.sorted()
        where supportedActionKeys.contains(key) == false {
            diagnostics.append(
                diagnostic(
                    "unsupportedActionField",
                    .warning,
                    "rules[\(index)].action.\(key)",
                    "DNR action field \(key) is not modeled by the internal synthetic evaluator."
                )
            )
        }

        let rawType = object["type"] as? String
        let parsedType = rawType.flatMap(ChromeMV3DNRRuleActionType.init(rawValue:))
            ?? .unknown
        var type = parsedType
        if parsedType == .modifyHeaders {
            let requestHeaders = object["requestHeaders"] as? [[String: Any]] ?? []
            let responseHeaders = object["responseHeaders"] as? [[String: Any]] ?? []
            if requestHeaders.contains(where: { ($0["operation"] as? String) == "remove" })
                || responseHeaders.contains(where: { ($0["operation"] as? String) == "remove" })
            {
                type = .removeHeaders
            }
        }

        switch type {
        case .allow, .block:
            break
        case .allowAllRequests:
            diagnostics.append(
                diagnostic(
                    "allowAllRequestsPartial",
                    .warning,
                    "rules[\(index)].action.type",
                    "allowAllRequests is selected in synthetic evaluation, but frame-scoped request ancestry is not fully modeled."
                )
            )
        case .upgradeScheme:
            diagnostics.append(
                diagnostic(
                    "upgradeSchemeSyntheticOnly",
                    .info,
                    "rules[\(index)].action.type",
                    "upgradeScheme is modeled only as a synthetic outcome and is never applied to product network traffic."
                )
            )
        case .redirect:
            diagnostics.append(
                diagnostic(
                    "redirectDeferred",
                    .warning,
                    "rules[\(index)].action.type",
                    "DNR redirect is deferred and reported by the synthetic evaluator without product enforcement."
                )
            )
        case .modifyHeaders:
            diagnostics.append(
                diagnostic(
                    "modifyHeadersUnsupported",
                    .warning,
                    "rules[\(index)].action.type",
                    "DNR modifyHeaders is unsupported in this internal MVP."
                )
            )
        case .removeHeaders:
            diagnostics.append(
                diagnostic(
                    "removeHeadersUnsupported",
                    .warning,
                    "rules[\(index)].action.type",
                    "DNR header removal is unsupported in this internal MVP."
                )
            )
        case .unknown:
            diagnostics.append(
                diagnostic(
                    "unknownActionType",
                    .error,
                    "rules[\(index)].action.type",
                    "DNR action type is missing or unsupported."
                )
            )
        }

        let redirectURL = (object["redirect"] as? [String: Any])?["url"] as? String
        return ChromeMV3DNRRuleAction(
            type: type,
            redirectURL: redirectURL,
            rawType: rawType,
            supportStatus: type.supportStatus,
            diagnostics: uniqueDiagnostics(diagnostics)
        )
    }

    private static func parseCondition(
        _ object: [String: Any],
        index: Int
    ) -> ChromeMV3DNRRuleCondition {
        var diagnostics: [ChromeMV3DNRDiagnostic] = []
        let supportedConditionKeys: Set<String> = [
            "excludedInitiatorDomains",
            "excludedRequestDomains",
            "excludedResourceTypes",
            "excludedTabIds",
            "initiatorDomains",
            "regexFilter",
            "requestDomains",
            "resourceTypes",
            "tabIds",
            "urlFilter",
        ]
        let unsupportedFields = object.keys.sorted().filter {
            supportedConditionKeys.contains($0) == false
        }
        for field in unsupportedFields {
            diagnostics.append(
                diagnostic(
                    "unsupportedConditionField",
                    .warning,
                    "rules[\(index)].condition.\(field)",
                    "DNR condition field \(field) is not modeled by the internal synthetic evaluator."
                )
            )
        }

        let regexFilter = object["regexFilter"] as? String
        if let regexFilter {
            do {
                _ = try NSRegularExpression(pattern: regexFilter)
            } catch {
                diagnostics.append(
                    diagnostic(
                        "invalidRegexFilter",
                        .error,
                        "rules[\(index)].condition.regexFilter",
                        "DNR regexFilter could not be compiled: \(error.localizedDescription)"
                    )
                )
            }
        }

        return ChromeMV3DNRRuleCondition(
            urlFilter: object["urlFilter"] as? String,
            regexFilter: regexFilter,
            resourceTypes:
                resourceTypes(object["resourceTypes"], diagnostics: &diagnostics),
            excludedResourceTypes:
                resourceTypes(
                    object["excludedResourceTypes"],
                    diagnostics: &diagnostics
                ),
            requestDomains: normalizedDomains(object["requestDomains"]),
            excludedRequestDomains:
                normalizedDomains(object["excludedRequestDomains"]),
            initiatorDomains: normalizedDomains(object["initiatorDomains"]),
            excludedInitiatorDomains:
                normalizedDomains(object["excludedInitiatorDomains"]),
            tabIDs: intArray(object["tabIds"]),
            excludedTabIDs: intArray(object["excludedTabIds"]),
            unsupportedFields: unsupportedFields,
            diagnostics: uniqueDiagnostics(diagnostics)
        )
    }

    private static func resourceTypes(
        _ value: Any?,
        diagnostics: inout [ChromeMV3DNRDiagnostic]
    ) -> [ChromeMV3DNRResourceType] {
        guard let strings = value as? [String] else { return [] }
        var types: [ChromeMV3DNRResourceType] = []
        for string in strings {
            guard let type = ChromeMV3DNRResourceType(rawValue: string) else {
                diagnostics.append(
                    diagnostic(
                        "unsupportedResourceType",
                        .warning,
                        "condition.resourceTypes",
                        "DNR resource type \(string) is not modeled."
                    )
                )
                continue
            }
            types.append(type)
        }
        return Array(Set(types)).sorted()
    }

    private static func normalizedDomains(_ value: Any?) -> [String] {
        guard let strings = value as? [String] else { return [] }
        return Array(Set(strings.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }.filter { $0.isEmpty == false })).sorted()
    }

    private static func intArray(_ value: Any?) -> [Int] {
        guard let values = value as? [Any] else { return [] }
        return Array(Set(values.compactMap(intValue))).sorted()
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        guard let number = value as? NSNumber else { return nil }
        let type = String(cString: number.objCType)
        guard type != "c" else { return nil }
        let double = number.doubleValue
        guard double.rounded(.towardZero) == double else { return nil }
        return Int(double)
    }
}

enum ChromeMV3DNRStaticRulesetLoader {
    static func loadRulesets(
        manifest: ChromeMV3Manifest,
        generatedBundleRootURL: URL?
    ) -> ChromeMV3DNRManifestRulesetModel {
        guard let dnr = manifest.declarativeNetRequest else {
            return .empty
        }

        let rootURL = generatedBundleRootURL?.standardizedFileURL
        var rulesets: [ChromeMV3DNRRulesetResourceModel] = []
        var manifestDiagnostics: [ChromeMV3DNRDiagnostic] = []
        let resources = dnr.ruleResources.enumerated().sorted { lhs, rhs in
            let lhsKey = lhs.element.id ?? lhs.element.path ?? "\(lhs.offset)"
            let rhsKey = rhs.element.id ?? rhs.element.path ?? "\(rhs.offset)"
            return lhsKey < rhsKey
        }

        for (index, resource) in resources {
            let ruleset = loadResource(
                resource,
                index: index,
                rootURL: rootURL
            )
            rulesets.append(ruleset)
        }

        let duplicateRulesetIDs = Dictionary(grouping: rulesets.map(\.id), by: { $0 })
            .mapValues(\.count)
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
        for id in duplicateRulesetIDs {
            manifestDiagnostics.append(
                diagnostic(
                    "duplicateRulesetID",
                    .error,
                    "declarative_net_request.rule_resources.id",
                    "DNR static ruleset id \(id) is duplicated."
                )
            )
        }

        let enabled = rulesets
            .filter { $0.enabledByDefault }
            .map(\.id)
            .sorted()
        return ChromeMV3DNRManifestRulesetModel(
            declaresDeclarativeNetRequest: true,
            rulesets: rulesets.sorted { $0.id < $1.id },
            totalParsedRuleCount: rulesets.reduce(0) {
                $0 + $1.parsedRuleCount
            },
            totalValidRuleCount: rulesets.reduce(0) {
                $0 + $1.validRuleCount
            },
            enabledRulesetIDs: enabled,
            unsupportedFeatureCount: rulesets.reduce(0) {
                $0 + $1.unsupportedFeatureCount
            },
            dnrAvailableInInternalEvaluator: true,
            dnrAvailableInProduct: false,
            dnrProductEnforcementAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueDiagnostics(
                    manifestDiagnostics
                        + rulesets.flatMap(\.diagnostics)
                        + [
                            diagnostic(
                                "syntheticOnly",
                                .info,
                                "declarative_net_request",
                                "DNR is available only in the internal synthetic evaluator; product enforcement is unavailable."
                            ),
                        ]
                )
        )
    }

    private static func loadResource(
        _ resource: ChromeMV3DeclarativeNetRequestRuleResource,
        index: Int,
        rootURL: URL?
    ) -> ChromeMV3DNRRulesetResourceModel {
        var diagnostics: [ChromeMV3DNRDiagnostic] = []
        let rulesetID = normalized(
            resource.id ?? "",
            fallback: "ruleset-\(index)"
        )
        if resource.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ?? true
        {
            diagnostics.append(
                diagnostic(
                    "missingRulesetID",
                    .error,
                    "declarative_net_request.rule_resources[\(index)].id",
                    "DNR static ruleset id is required for deterministic state."
                )
            )
        }

        guard let manifestPath = resource.path else {
            diagnostics.append(
                diagnostic(
                    "missingRulesetPath",
                    .error,
                    "declarative_net_request.rule_resources[\(index)].path",
                    "DNR static ruleset path is missing."
                )
            )
            return emptyRuleset(
                id: rulesetID,
                enabledByDefault: resource.enabled ?? false,
                manifestPath: nil,
                generatedPath: nil,
                diagnostics: diagnostics
            )
        }

        guard let normalizedPath = safeRelativePath(manifestPath) else {
            diagnostics.append(
                diagnostic(
                    "unsafeRulesetPath",
                    .error,
                    "declarative_net_request.rule_resources[\(index)].path",
                    "DNR static ruleset path is unsafe or escapes the extension bundle."
                )
            )
            return emptyRuleset(
                id: rulesetID,
                enabledByDefault: resource.enabled ?? false,
                manifestPath: manifestPath,
                generatedPath: nil,
                diagnostics: diagnostics
            )
        }

        guard let rootURL else {
            diagnostics.append(
                diagnostic(
                    "missingGeneratedBundleRoot",
                    .error,
                    "generatedBundleRoot",
                    "Generated bundle root is required before static DNR rules can be loaded."
                )
            )
            return emptyRuleset(
                id: rulesetID,
                enabledByDefault: resource.enabled ?? false,
                manifestPath: normalizedPath,
                generatedPath: nil,
                diagnostics: diagnostics
            )
        }

        let fileURL = rootURL.appendingPathComponent(normalizedPath)
            .standardizedFileURL
        guard fileURL.path == rootURL.path
            || fileURL.path.hasPrefix(rootURL.path + "/")
        else {
            diagnostics.append(
                diagnostic(
                    "rulesetEscapesGeneratedBundle",
                    .error,
                    "declarative_net_request.rule_resources[\(index)].path",
                    "DNR static ruleset path resolves outside the generated bundle."
                )
            )
            return emptyRuleset(
                id: rulesetID,
                enabledByDefault: resource.enabled ?? false,
                manifestPath: normalizedPath,
                generatedPath: fileURL.path,
                diagnostics: diagnostics
            )
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: fileURL.path,
            isDirectory: &isDirectory
        ) else {
            diagnostics.append(
                diagnostic(
                    "missingRulesetFile",
                    .error,
                    "declarative_net_request.rule_resources[\(index)].path",
                    "DNR static ruleset file is missing at \(normalizedPath)."
                )
            )
            return emptyRuleset(
                id: rulesetID,
                enabledByDefault: resource.enabled ?? false,
                manifestPath: normalizedPath,
                generatedPath: fileURL.path,
                diagnostics: diagnostics
            )
        }

        guard isDirectory.boolValue == false else {
            diagnostics.append(
                diagnostic(
                    "rulesetPathIsDirectory",
                    .error,
                    "declarative_net_request.rule_resources[\(index)].path",
                    "DNR static ruleset path must point to a JSON file."
                )
            )
            return emptyRuleset(
                id: rulesetID,
                enabledByDefault: resource.enabled ?? false,
                manifestPath: normalizedPath,
                generatedPath: fileURL.path,
                diagnostics: diagnostics
            )
        }

        let parseResult: ChromeMV3DNRRuleParseResult
        do {
            parseResult = ChromeMV3DNRRuleParser.parseRules(
                data: try Data(contentsOf: fileURL),
                rulesetID: rulesetID,
                sourceKind: .staticRuleset
            )
        } catch {
            diagnostics.append(
                diagnostic(
                    "rulesetReadFailed",
                    .error,
                    "declarative_net_request.rule_resources[\(index)].path",
                    "DNR static ruleset file could not be read: \(error.localizedDescription)"
                )
            )
            return emptyRuleset(
                id: rulesetID,
                enabledByDefault: resource.enabled ?? false,
                manifestPath: normalizedPath,
                generatedPath: fileURL.path,
                diagnostics: diagnostics
            )
        }

        diagnostics.append(contentsOf: parseResult.diagnostics)
        let status: ChromeMV3DNRSupportStatus =
            diagnostics.contains { $0.severity == .error }
            ? .unsupported
            : parseResult.unsupportedFeatureCount > 0 ? .partial : .supported

        return ChromeMV3DNRRulesetResourceModel(
            id: rulesetID,
            enabledByDefault: resource.enabled ?? false,
            manifestPath: normalizedPath,
            generatedBundleResourcePath: fileURL.path,
            parsedRuleCount: parseResult.rules.count,
            validRuleCount: parseResult.validRules.count,
            duplicateRuleIDs: parseResult.duplicateRuleIDs,
            unsupportedFeatureCount: parseResult.unsupportedFeatureCount,
            validationStatus: status,
            diagnostics: uniqueDiagnostics(diagnostics),
            rules: parseResult.rules
        )
    }

    private static func emptyRuleset(
        id: String,
        enabledByDefault: Bool,
        manifestPath: String?,
        generatedPath: String?,
        diagnostics: [ChromeMV3DNRDiagnostic]
    ) -> ChromeMV3DNRRulesetResourceModel {
        ChromeMV3DNRRulesetResourceModel(
            id: id,
            enabledByDefault: enabledByDefault,
            manifestPath: manifestPath,
            generatedBundleResourcePath: generatedPath,
            parsedRuleCount: 0,
            validRuleCount: 0,
            duplicateRuleIDs: [],
            unsupportedFeatureCount: 0,
            validationStatus: .unsupported,
            diagnostics: uniqueDiagnostics(diagnostics),
            rules: []
        )
    }
}

final class ChromeMV3DNRStaticRulesetState {
    private let model: ChromeMV3DNRManifestRulesetModel
    private var enabledIDs: Set<String>

    init(model: ChromeMV3DNRManifestRulesetModel) {
        self.model = model
        self.enabledIDs = Set(model.enabledRulesetIDs)
    }

    var enabledRulesetIDs: [String] {
        enabledIDs.sorted()
    }

    var enabledRules: [ChromeMV3DNRRule] {
        model.rulesets
            .filter { enabledIDs.contains($0.id) }
            .flatMap(\.rules)
            .filter { $0.diagnostics.contains { $0.severity == .error } == false }
            .sorted(by: deterministicRuleOrder)
    }

    var summary: ChromeMV3DNRStaticRulesetStateSummary {
        ChromeMV3DNRStaticRulesetStateSummary(
            totalRulesetCount: model.rulesets.count,
            enabledRulesetIDs: enabledRulesetIDs,
            enabledRuleCount: enabledRules.count,
            dnrAvailableInInternalEvaluator:
                model.dnrAvailableInInternalEvaluator,
            dnrAvailableInProduct: false,
            dnrProductEnforcementAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false
        )
    }

    func updateEnabledRulesets(
        enableRulesetIDs: [String],
        disableRulesetIDs: [String]
    ) -> ChromeMV3DNRRulesetStateUpdateResult {
        let knownIDs = Set(model.rulesets.map(\.id))
        let unknown = Array(
            Set(enableRulesetIDs + disableRulesetIDs).subtracting(knownIDs)
        ).sorted()
        guard unknown.isEmpty else {
            return ChromeMV3DNRRulesetStateUpdateResult(
                succeeded: false,
                enabledRulesetIDs: enabledRulesetIDs,
                diagnostics: unknown.map {
                    diagnostic(
                        "unknownRulesetID",
                        .error,
                        "rulesetIds",
                        "DNR ruleset id \($0) is not declared by the manifest."
                    )
                }
            )
        }

        for id in disableRulesetIDs { enabledIDs.remove(id) }
        for id in enableRulesetIDs { enabledIDs.insert(id) }
        return ChromeMV3DNRRulesetStateUpdateResult(
            succeeded: true,
            enabledRulesetIDs: enabledRulesetIDs,
            diagnostics: [
                diagnostic(
                    "enabledRulesetsUpdated",
                    .info,
                    "rulesetIds",
                    "DNR enabled static ruleset state was updated inside synthetic state only."
                ),
            ]
        )
    }

}

struct ChromeMV3DNRStaticRulesetStateSummary:
    Codable,
    Equatable,
    Sendable
{
    var totalRulesetCount: Int
    var enabledRulesetIDs: [String]
    var enabledRuleCount: Int
    var dnrAvailableInInternalEvaluator: Bool
    var dnrAvailableInProduct: Bool
    var dnrProductEnforcementAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
}

struct ChromeMV3DNRRulesetStateUpdateResult:
    Codable,
    Equatable,
    Sendable
{
    var succeeded: Bool
    var enabledRulesetIDs: [String]
    var diagnostics: [ChromeMV3DNRDiagnostic]
}

struct ChromeMV3DNRRuleStoreSummary:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var dynamicRuleCount: Int
    var sessionRuleCount: Int
    var dynamicRuleIDs: [Int]
    var sessionRuleIDs: [Int]
    var storeIsSyntheticOnly: Bool
    var dnrAvailableInInternalEvaluator: Bool
    var dnrAvailableInProduct: Bool
    var dnrProductEnforcementAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

struct ChromeMV3DNRRuleStoreUpdateResult:
    Codable,
    Equatable,
    Sendable
{
    var succeeded: Bool
    var scope: ChromeMV3DNRRuleSourceKind
    var addedRuleIDs: [Int]
    var removedRuleIDs: [Int]
    var currentRuleIDs: [Int]
    var diagnostics: [ChromeMV3DNRDiagnostic]
}

final class ChromeMV3DNRRuleStateOwner {
    let extensionID: String
    let profileID: String
    private var dynamicRulesByID: [Int: ChromeMV3DNRRule] = [:]
    private var sessionRulesByID: [Int: ChromeMV3DNRRule] = [:]

    init(
        extensionID: String = "dnr-synthetic-extension",
        profileID: String = "dnr-synthetic-profile"
    ) {
        self.extensionID = normalized(
            extensionID,
            fallback: "dnr-synthetic-extension"
        )
        self.profileID = normalized(
            profileID,
            fallback: "dnr-synthetic-profile"
        )
    }

    var dynamicRules: [ChromeMV3DNRRule] {
        dynamicRulesByID.values.sorted(by: deterministicRuleOrder)
    }

    var sessionRules: [ChromeMV3DNRRule] {
        sessionRulesByID.values.sorted(by: deterministicRuleOrder)
    }

    var summary: ChromeMV3DNRRuleStoreSummary {
        ChromeMV3DNRRuleStoreSummary(
            extensionID: extensionID,
            profileID: profileID,
            dynamicRuleCount: dynamicRulesByID.count,
            sessionRuleCount: sessionRulesByID.count,
            dynamicRuleIDs: dynamicRulesByID.keys.sorted(),
            sessionRuleIDs: sessionRulesByID.keys.sorted(),
            storeIsSyntheticOnly: true,
            dnrAvailableInInternalEvaluator: true,
            dnrAvailableInProduct: false,
            dnrProductEnforcementAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics: [
                "Dynamic and session DNR stores are profile/extension-scoped fixture state only.",
                "No product request interception or content blocker attachment is performed.",
            ]
        )
    }

    func updateDynamicRules(
        addRules: [ChromeMV3DNRRule],
        removeRuleIDs: [Int]
    ) -> ChromeMV3DNRRuleStoreUpdateResult {
        update(
            scope: .dynamic,
            addRules: addRules,
            removeRuleIDs: removeRuleIDs
        )
    }

    func updateSessionRules(
        addRules: [ChromeMV3DNRRule],
        removeRuleIDs: [Int]
    ) -> ChromeMV3DNRRuleStoreUpdateResult {
        update(
            scope: .session,
            addRules: addRules,
            removeRuleIDs: removeRuleIDs
        )
    }

    func resetForExtensionDisableOrProfileClose() {
        dynamicRulesByID.removeAll()
        sessionRulesByID.removeAll()
    }

    private func update(
        scope: ChromeMV3DNRRuleSourceKind,
        addRules: [ChromeMV3DNRRule],
        removeRuleIDs: [Int]
    ) -> ChromeMV3DNRRuleStoreUpdateResult {
        var diagnostics: [ChromeMV3DNRDiagnostic] = []
        let addIDs = addRules.map(\.id)
        let duplicateAddIDs = Dictionary(grouping: addIDs, by: { $0 })
            .mapValues(\.count)
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
        for id in duplicateAddIDs {
            diagnostics.append(
                diagnostic(
                    "duplicateRuleID",
                    .error,
                    "addRules",
                    "DNR \(scope.rawValue) update contains duplicate rule id \(id)."
                )
            )
        }

        let current = scope == .dynamic ? dynamicRulesByID : sessionRulesByID
        let removedSet = Set(removeRuleIDs)
        let existingAfterRemove = current.keys.filter { removedSet.contains($0) == false }
        let duplicateExisting = Set(existingAfterRemove).intersection(addIDs)
            .sorted()
        for id in duplicateExisting {
            diagnostics.append(
                diagnostic(
                    "duplicateRuleID",
                    .error,
                    "addRules",
                    "DNR \(scope.rawValue) rule id \(id) already exists."
                )
            )
        }
        for rule in addRules where rule.id <= 0 {
            diagnostics.append(
                diagnostic(
                    "invalidRuleID",
                    .error,
                    "addRules",
                    "DNR \(scope.rawValue) rule id must be positive."
                )
            )
        }

        guard diagnostics.contains(where: { $0.severity == .error }) == false
        else {
            return ChromeMV3DNRRuleStoreUpdateResult(
                succeeded: false,
                scope: scope,
                addedRuleIDs: [],
                removedRuleIDs: [],
                currentRuleIDs: current.keys.sorted(),
                diagnostics: uniqueDiagnostics(diagnostics)
            )
        }

        var next = current
        for id in removeRuleIDs { next.removeValue(forKey: id) }
        for rule in addRules {
            var scopedRule = rule
            scopedRule.sourceKind = scope
            scopedRule.rulesetID = scope.rawValue
            next[scopedRule.id] = scopedRule
        }

        if scope == .dynamic {
            dynamicRulesByID = next
        } else {
            sessionRulesByID = next
        }

        return ChromeMV3DNRRuleStoreUpdateResult(
            succeeded: true,
            scope: scope,
            addedRuleIDs: addRules.map(\.id).sorted(),
            removedRuleIDs: removeRuleIDs.sorted(),
            currentRuleIDs: next.keys.sorted(),
            diagnostics:
                uniqueDiagnostics(
                    diagnostics
                        + [
                            diagnostic(
                                "ruleStoreUpdated",
                                .info,
                                scope.rawValue,
                                "DNR \(scope.rawValue) rules were updated in synthetic state only."
                            ),
                        ]
                )
        )
    }
}

struct ChromeMV3DNRSyntheticRequest:
    Codable,
    Equatable,
    Sendable
{
    var url: String
    var method: String
    var resourceType: ChromeMV3DNRResourceType
    var initiator: String?
    var tabID: Int?
    var frameID: Int?
    var documentID: String?
    var requestHeaders: [String: String]
    var responseHeaders: [String: String]
    var lifecycleEventType: String
    var sequenceID: Int

    static func fixture(
        url: String,
        resourceType: ChromeMV3DNRResourceType = .script,
        initiator: String? = "https://example.com/",
        tabID: Int? = 1,
        frameID: Int? = 0,
        sequenceID: Int = 1
    ) -> ChromeMV3DNRSyntheticRequest {
        ChromeMV3DNRSyntheticRequest(
            url: url,
            method: "GET",
            resourceType: resourceType,
            initiator: initiator,
            tabID: tabID,
            frameID: frameID,
            documentID: "synthetic-document-\(sequenceID)",
            requestHeaders: [:],
            responseHeaders: [:],
            lifecycleEventType: "syntheticBeforeRequest",
            sequenceID: sequenceID
        )
    }
}

struct ChromeMV3DNRSyntheticMatchedRule:
    Codable,
    Equatable,
    Sendable
{
    var ruleID: Int
    var rulesetID: String
    var sourceKind: ChromeMV3DNRRuleSourceKind
    var priority: Int
    var actionType: ChromeMV3DNRRuleActionType
    var supportStatus: ChromeMV3DNRSupportStatus
    var diagnostics: [String]

    var storageValue: ChromeMV3StorageValue {
        .object([
            "ruleId": .number(Double(ruleID)),
            "rulesetId": .string(rulesetID),
            "sourceKind": .string(sourceKind.rawValue),
            "priority": .number(Double(priority)),
            "actionType": .string(actionType.rawValue),
            "supportStatus": .string(supportStatus.rawValue),
        ])
    }
}

struct ChromeMV3DNRSyntheticEvaluationResult:
    Codable,
    Equatable,
    Sendable
{
    var request: ChromeMV3DNRSyntheticRequest
    var matchedRules: [ChromeMV3DNRSyntheticMatchedRule]
    var selectedRule: ChromeMV3DNRSyntheticMatchedRule?
    var selectedActionType: ChromeMV3DNRRuleActionType?
    var selectedActionStatus: ChromeMV3DNRSupportStatus?
    var outcome: String
    var upgradedURL: String?
    var dnrAvailableInInternalEvaluator: Bool
    var dnrAvailableInProduct: Bool
    var dnrProductEnforcementAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    var storageValue: ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "matchedRules": .array(matchedRules.map(\.storageValue)),
            "rulesMatchedInfo": .array(matchedRules.map(\.storageValue)),
            "outcome": .string(outcome),
            "dnrAvailableInInternalEvaluator":
                .bool(dnrAvailableInInternalEvaluator),
            "dnrAvailableInProduct": .bool(false),
            "dnrProductEnforcementAvailable": .bool(false),
            "normalTabRuntimeBridgeAvailable": .bool(false),
            "runtimeLoadable": .bool(false),
            "diagnostics": .array(diagnostics.map(ChromeMV3StorageValue.string)),
        ]
        if let selectedRule {
            object["selectedRule"] = selectedRule.storageValue
        }
        if let selectedActionType {
            object["selectedActionType"] = .string(selectedActionType.rawValue)
        }
        if let selectedActionStatus {
            object["selectedActionStatus"] =
                .string(selectedActionStatus.rawValue)
        }
        if let upgradedURL {
            object["upgradedURL"] = .string(upgradedURL)
        }
        return .object(object)
    }
}

enum ChromeMV3DNRSyntheticEvaluator {
    static func evaluate(
        staticRulesetState: ChromeMV3DNRStaticRulesetState? = nil,
        dynamicRules: [ChromeMV3DNRRule] = [],
        sessionRules: [ChromeMV3DNRRule] = [],
        request: ChromeMV3DNRSyntheticRequest
    ) -> ChromeMV3DNRSyntheticEvaluationResult {
        let rules =
            (staticRulesetState?.enabledRules ?? [])
            + dynamicRules
            + sessionRules
        let matched = rules
            .filter { matches(rule: $0, request: request) }
            .sorted(by: selectedRuleOrder)
            .map(matchedRule)
        let selected = matched.first
        let selectedAction = selected?.actionType
        let outcome = outcomeString(
            selectedAction,
            status: selected?.supportStatus
        )
        let upgradedURL =
            selectedAction == .upgradeScheme
            ? upgradedHTTPSURL(from: request.url)
            : nil

        return ChromeMV3DNRSyntheticEvaluationResult(
            request: request,
            matchedRules: matched,
            selectedRule: selected,
            selectedActionType: selectedAction,
            selectedActionStatus: selected?.supportStatus,
            outcome: outcome,
            upgradedURL: upgradedURL,
            dnrAvailableInInternalEvaluator: true,
            dnrAvailableInProduct: false,
            dnrProductEnforcementAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedNetworkCompatibility([
                    "Synthetic DNR evaluator considered enabled static, dynamic, and session rules only.",
                    "No product network request was blocked, redirected, upgraded, or modified.",
                    selected == nil
                        ? "No DNR rule matched the synthetic request."
                        : "Selected action is a diagnostic outcome only.",
                ])
        )
    }

    private static func matches(
        rule: ChromeMV3DNRRule,
        request: ChromeMV3DNRSyntheticRequest
    ) -> Bool {
        let condition = rule.condition
        if condition.resourceTypes.isEmpty == false
            && condition.resourceTypes.contains(request.resourceType) == false
        {
            return false
        }
        if condition.excludedResourceTypes.contains(request.resourceType) {
            return false
        }
        if condition.tabIDs.isEmpty == false {
            guard let tabID = request.tabID,
                  condition.tabIDs.contains(tabID)
            else { return false }
        }
        if let tabID = request.tabID,
           condition.excludedTabIDs.contains(tabID)
        {
            return false
        }

        let requestHost = host(from: request.url)
        if domainList(condition.requestDomains, matches: requestHost) == false {
            return false
        }
        if excludedDomainList(
            condition.excludedRequestDomains,
            matches: requestHost
        ) {
            return false
        }

        let initiatorHost = request.initiator.flatMap(host(from:))
        if domainList(condition.initiatorDomains, matches: initiatorHost) == false {
            return false
        }
        if excludedDomainList(
            condition.excludedInitiatorDomains,
            matches: initiatorHost
        ) {
            return false
        }

        if let urlFilter = condition.urlFilter,
           urlFilterMatches(urlFilter, requestURLString: request.url) == false
        {
            return false
        }

        if let regexFilter = condition.regexFilter {
            guard let regex = try? NSRegularExpression(pattern: regexFilter)
            else { return false }
            let range = NSRange(
                request.url.startIndex..<request.url.endIndex,
                in: request.url
            )
            if regex.firstMatch(in: request.url, range: range) == nil {
                return false
            }
        }

        return true
    }

    private static func domainList(
        _ domains: [String],
        matches host: String?
    ) -> Bool {
        guard domains.isEmpty == false else { return true }
        guard let host else { return false }
        return domains.contains { domainMatches(domain: $0, host: host) }
    }

    private static func excludedDomainList(
        _ domains: [String],
        matches host: String?
    ) -> Bool {
        guard domains.isEmpty == false, let host else { return false }
        return domains.contains { domainMatches(domain: $0, host: host) }
    }

    private static func domainMatches(domain: String, host: String) -> Bool {
        let host = host.lowercased()
        let domain = domain.lowercased()
        return host == domain || host.hasSuffix("." + domain)
    }

    private static func host(from string: String) -> String? {
        URL(string: string)?.host?.lowercased()
    }

    private static func urlFilterMatches(
        _ filter: String,
        requestURLString: String
    ) -> Bool {
        let request = requestURLString.lowercased()
        let filter = filter.lowercased()
        guard filter.isEmpty == false else { return true }
        guard filter != "*" else { return true }

        if filter.hasPrefix("||") {
            let remainder = String(filter.dropFirst(2))
            let separators = CharacterSet(charactersIn: "/^|*")
            let domainEnd = remainder.rangeOfCharacter(from: separators)?
                .lowerBound ?? remainder.endIndex
            let domain = String(remainder[..<domainEnd])
            guard let host = host(from: requestURLString),
                  domainMatches(domain: domain, host: host)
            else { return false }
            let rest = String(remainder[domainEnd...])
                .replacingOccurrences(of: "^", with: "")
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "|", with: "")
            return rest.isEmpty || request.contains(rest)
        }

        if filter.contains("*") || filter.hasPrefix("|") || filter.hasSuffix("|") {
            var pattern = NSRegularExpression.escapedPattern(for: filter)
            pattern = pattern.replacingOccurrences(of: "\\*", with: ".*")
            var anchored = pattern
            if anchored.hasPrefix("\\|") {
                anchored = "^" + String(anchored.dropFirst(2))
            }
            if anchored.hasSuffix("\\|") {
                anchored = String(anchored.dropLast(2)) + "$"
            }
            guard let regex = try? NSRegularExpression(pattern: anchored)
            else { return false }
            let range = NSRange(request.startIndex..<request.endIndex, in: request)
            return regex.firstMatch(in: request, range: range) != nil
        }

        return request.contains(filter.replacingOccurrences(of: "^", with: ""))
    }

    private static func matchedRule(
        _ rule: ChromeMV3DNRRule
    ) -> ChromeMV3DNRSyntheticMatchedRule {
        ChromeMV3DNRSyntheticMatchedRule(
            ruleID: rule.id,
            rulesetID: rule.rulesetID,
            sourceKind: rule.sourceKind,
            priority: rule.priority,
            actionType: rule.action.type,
            supportStatus: rule.supportStatus,
            diagnostics: rule.diagnostics.map(\.message).sorted()
        )
    }

    private static func selectedRuleOrder(
        lhs: ChromeMV3DNRRule,
        rhs: ChromeMV3DNRRule
    ) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        if lhs.action.type.precedence != rhs.action.type.precedence {
            return lhs.action.type.precedence > rhs.action.type.precedence
        }
        if lhs.sourceKind != rhs.sourceKind {
            return lhs.sourceKind.rawValue < rhs.sourceKind.rawValue
        }
        if lhs.rulesetID != rhs.rulesetID {
            return lhs.rulesetID < rhs.rulesetID
        }
        return lhs.id < rhs.id
    }

    private static func outcomeString(
        _ action: ChromeMV3DNRRuleActionType?,
        status: ChromeMV3DNRSupportStatus?
    ) -> String {
        guard let action else { return "noMatch" }
        if status == .unsupported { return "unsupportedAction" }
        if status == .deferred { return "deferredAction" }
        switch action {
        case .allow, .allowAllRequests:
            return "allowed"
        case .block:
            return "blocked"
        case .upgradeScheme:
            return "upgradedScheme"
        case .redirect:
            return "deferredAction"
        case .modifyHeaders, .removeHeaders, .unknown:
            return "unsupportedAction"
        }
    }

    private static func upgradedHTTPSURL(from string: String) -> String? {
        guard var components = URLComponents(string: string),
              components.scheme == "http"
        else { return nil }
        components.scheme = "https"
        return components.string
    }
}

struct ChromeMV3DNRJSBridgeConfiguration:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var moduleState: ChromeMV3ProfileHostModuleState
    var explicitInternalDNRBridgeAllowed: Bool
    var dnrAvailableInInternalEvaluator: Bool
    var dnrAvailableInProduct: Bool
    var dnrProductEnforcementAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    static func syntheticHarness(
        extensionID: String = "dnr-synthetic-extension",
        profileID: String = "dnr-synthetic-profile",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        explicitInternalDNRBridgeAllowed: Bool = true
    ) -> ChromeMV3DNRJSBridgeConfiguration {
        let allowed = moduleState == .enabled
            && explicitInternalDNRBridgeAllowed
        return ChromeMV3DNRJSBridgeConfiguration(
            extensionID: normalized(
                extensionID,
                fallback: "dnr-synthetic-extension"
            ),
            profileID: normalized(
                profileID,
                fallback: "dnr-synthetic-profile"
            ),
            moduleState: moduleState,
            explicitInternalDNRBridgeAllowed: explicitInternalDNRBridgeAllowed,
            dnrAvailableInInternalEvaluator: allowed,
            dnrAvailableInProduct: false,
            dnrProductEnforcementAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics: [
                "declarativeNetRequest JS bridge is confined to DEBUG/internal synthetic harnesses.",
                "DNR product enforcement is unavailable.",
                "Normal-tab runtime bridge remains unavailable.",
                "runtimeLoadable remains false.",
            ]
        )
    }
}

struct ChromeMV3DNRJSShimCoverage:
    Codable,
    Equatable,
    Sendable
{
    var exposedChromeNamespaces: [String]
    var declarativeNetRequestMethods: [String]
    var callbackModeSupported: Bool
    var promiseModeSupported: Bool
    var productEnforcementAvailable: Bool
}

enum ChromeMV3DNRJSShimSource {
    static let bridgeMessageHandlerName = "sumiChromeMV3DNR"

    static var coverage: ChromeMV3DNRJSShimCoverage {
        ChromeMV3DNRJSShimCoverage(
            exposedChromeNamespaces: ["declarativeNetRequest", "runtime"],
            declarativeNetRequestMethods: [
                "getAvailableStaticRuleCount",
                "getDynamicRules",
                "getEnabledRulesets",
                "getSessionRules",
                "testMatchOutcome",
                "updateDynamicRules",
                "updateEnabledRulesets",
                "updateSessionRules",
            ],
            callbackModeSupported: true,
            promiseModeSupported: true,
            productEnforcementAvailable: false
        )
    }

    static func source(configuration: ChromeMV3DNRJSBridgeConfiguration) -> String {
        let configJSON = jsonStringNetworkCompatibility([
            "extensionID": configuration.extensionID,
            "profileID": configuration.profileID,
            "bridgeMessageHandlerName": bridgeMessageHandlerName,
        ])
        return """
        (() => {
          "use strict";
          const config = \(configJSON);
          const chromeObject = globalThis.chrome || {};
          const runtime = chromeObject.runtime || {};
          let lastErrorValue;
          let nextBridgeCallNumber = 0;
          Object.defineProperty(runtime, "lastError", {
            configurable: true,
            get() { return lastErrorValue; }
          });
          function handler() {
            return globalThis.webkit
              && globalThis.webkit.messageHandlers
              && globalThis.webkit.messageHandlers[config.bridgeMessageHandlerName];
          }
          function toJSONCompatible(value) {
            if (value === undefined) { return null; }
            return JSON.parse(JSON.stringify(value));
          }
          function invoke(methodName, invocationMode, args) {
            const target = handler();
            if (!target || typeof target.postMessage !== "function") {
              return Promise.resolve({
                succeeded: false,
                lastErrorMessage: "DNR JS bridge handler is unavailable.",
                resultPayload: null
              });
            }
            nextBridgeCallNumber += 1;
            return target.postMessage({
              namespace: "declarativeNetRequest",
              methodName,
              invocationMode,
              bridgeCallID: [
                "dnr-js",
                config.extensionID,
                methodName,
                String(nextBridgeCallNumber)
              ].join("-"),
              arguments: Array.prototype.slice.call(args || []).map(toJSONCompatible)
            });
          }
          function wrap(methodName) {
            return function() {
              const args = Array.prototype.slice.call(arguments);
              const maybeCallback =
                typeof args[args.length - 1] === "function" ? args.pop() : null;
              const mode = maybeCallback ? "callback" : "promise";
              const promise = invoke(methodName, mode, args).then((response) => {
                if (response.succeeded) {
                  return response.resultPayload === undefined
                    ? undefined
                    : response.resultPayload;
                }
                const message = response.lastErrorMessage || "DNR call failed.";
                if (maybeCallback) {
                  lastErrorValue = { message };
                  try { maybeCallback(); } finally { lastErrorValue = undefined; }
                  return undefined;
                }
                throw new Error(message);
              });
              if (maybeCallback) {
                promise.then((value) => maybeCallback(value), () => undefined);
                return;
              }
              return promise;
            };
          }
          const dnr = {};
          [
            "getAvailableStaticRuleCount",
            "getDynamicRules",
            "getEnabledRulesets",
            "getSessionRules",
            "testMatchOutcome",
            "updateDynamicRules",
            "updateEnabledRulesets",
            "updateSessionRules"
          ].forEach((name) => {
            Object.defineProperty(dnr, name, {
              configurable: false,
              enumerable: true,
              value: wrap(name)
            });
          });
          Object.defineProperty(chromeObject, "runtime", { value: runtime });
          Object.defineProperty(chromeObject, "declarativeNetRequest", {
            configurable: false,
            enumerable: true,
            value: Object.freeze(dnr)
          });
          Object.defineProperty(globalThis, "chrome", { value: chromeObject });
        })();
        """
    }
}

struct ChromeMV3DNRJSBridgeHostResponse:
    Codable,
    Equatable,
    Sendable
{
    var bridgeCallID: String
    var namespace: String
    var methodName: String
    var succeeded: Bool
    var resultPayload: ChromeMV3StorageValue?
    var lastErrorMessage: String?
    var lastErrorCode: String?
    var callbackWouldSetLastError: Bool
    var promiseWouldReject: Bool
    var staticRulesetSummary: ChromeMV3DNRStaticRulesetStateSummary
    var ruleStoreSummary: ChromeMV3DNRRuleStoreSummary
    var dnrAvailableInInternalEvaluator: Bool
    var dnrAvailableInProduct: Bool
    var dnrProductEnforcementAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

final class ChromeMV3DNRJSBridgeHandler {
    let configuration: ChromeMV3DNRJSBridgeConfiguration
    let staticRulesetState: ChromeMV3DNRStaticRulesetState
    let ruleStateOwner: ChromeMV3DNRRuleStateOwner
    private(set) var handledRequestCount = 0
    private(set) var rejectedRequestCount = 0

    init(
        configuration: ChromeMV3DNRJSBridgeConfiguration = .syntheticHarness(),
        staticRulesetState: ChromeMV3DNRStaticRulesetState? = nil,
        ruleStateOwner: ChromeMV3DNRRuleStateOwner? = nil
    ) {
        self.configuration = configuration
        self.staticRulesetState = staticRulesetState
            ?? ChromeMV3DNRStaticRulesetState(model: .empty)
        self.ruleStateOwner = ruleStateOwner
            ?? ChromeMV3DNRRuleStateOwner(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID
            )
    }

    func handle(_ body: Any) -> ChromeMV3DNRJSBridgeHostResponse {
        handledRequestCount += 1
        switch ChromeMV3RuntimeJSBridgeHostRequest.parse(body) {
        case .success(let request):
            return handle(request)
        case .failure(let error):
            rejectedRequestCount += 1
            return response(
                request: nil,
                methodName: "parse",
                succeeded: false,
                payload: nil,
                lastErrorMessage: error.message,
                lastErrorCode: "invalidArguments",
                diagnostics: [error.message]
            )
        }
    }

    func handle(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3DNRJSBridgeHostResponse {
        guard configuration.moduleState == .enabled,
              configuration.explicitInternalDNRBridgeAllowed
        else {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage: "Extensions module is disabled.",
                lastErrorCode: "extensionDisabled",
                diagnostics: [
                    "DNR JS bridge request blocked because the extensions module or explicit DEBUG/internal gate is disabled.",
                ]
            )
        }

        guard request.namespace == "declarativeNetRequest" else {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage: "DNR JS bridge namespace is unsupported.",
                lastErrorCode: "namespaceUnsupported",
                diagnostics: [
                    "DNR JS bridge accepts only the declarativeNetRequest namespace.",
                ]
            )
        }

        switch request.methodName {
        case "getEnabledRulesets":
            return response(
                request: request,
                succeeded: true,
                payload:
                    .array(
                        staticRulesetState.enabledRulesetIDs
                            .map(ChromeMV3StorageValue.string)
                    ),
                diagnostics: ["Returned synthetic enabled static ruleset ids."]
            )
        case "updateEnabledRulesets":
            return updateEnabledRulesets(request)
        case "getAvailableStaticRuleCount":
            let available = max(
                0,
                30_000 - staticRulesetState.summary.enabledRuleCount
            )
            return response(
                request: request,
                succeeded: true,
                payload: .number(Double(available)),
                diagnostics: [
                    "Returned synthetic available static rule count; this is not a Chrome quota parity claim.",
                ]
            )
        case "getDynamicRules":
            return getRules(request, scope: .dynamic)
        case "updateDynamicRules":
            return updateRules(request, scope: .dynamic)
        case "getSessionRules":
            return getRules(request, scope: .session)
        case "updateSessionRules":
            return updateRules(request, scope: .session)
        case "testMatchOutcome":
            return testMatchOutcome(request)
        default:
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    "DNR method is unsupported by this internal synthetic MVP.",
                lastErrorCode: "methodUnsupported",
                diagnostics: [
                    "Unsupported declarativeNetRequest method: \(request.methodName).",
                ]
            )
        }
    }

    private func updateEnabledRulesets(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3DNRJSBridgeHostResponse {
        guard let object = request.arguments.first?.objectValue else {
            return argumentError(
                request,
                "chrome.declarativeNetRequest.updateEnabledRulesets requires an options object."
            )
        }
        let enableIDs = object["enableRulesetIds"]?.stringArrayValue ?? []
        let disableIDs = object["disableRulesetIds"]?.stringArrayValue ?? []
        let result = staticRulesetState.updateEnabledRulesets(
            enableRulesetIDs: enableIDs,
            disableRulesetIDs: disableIDs
        )
        return response(
            request: request,
            succeeded: result.succeeded,
            payload: result.succeeded ? .null : nil,
            lastErrorMessage:
                result.succeeded ? nil : result.diagnostics.first?.message,
            lastErrorCode: result.succeeded ? nil : "invalidRulesetID",
            diagnostics: result.diagnostics.map(\.message)
        )
    }

    private func getRules(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        scope: ChromeMV3DNRRuleSourceKind
    ) -> ChromeMV3DNRJSBridgeHostResponse {
        let rules = scope == .dynamic
            ? ruleStateOwner.dynamicRules
            : ruleStateOwner.sessionRules
        let filterIDs =
            request.arguments.first?.objectValue?["ruleIds"]?.intArrayValue
            ?? []
        let filtered = filterIDs.isEmpty
            ? rules
            : rules.filter { filterIDs.contains($0.id) }
        return response(
            request: request,
            succeeded: true,
            payload: .array(filtered.map(\.storageValue)),
            diagnostics: [
                "Returned DNR \(scope.rawValue) rules from synthetic state only.",
            ]
        )
    }

    private func updateRules(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        scope: ChromeMV3DNRRuleSourceKind
    ) -> ChromeMV3DNRJSBridgeHostResponse {
        guard let object = request.arguments.first?.objectValue else {
            return argumentError(
                request,
                "chrome.declarativeNetRequest.update\(scope == .dynamic ? "Dynamic" : "Session")Rules requires an options object."
            )
        }
        let removeIDs = object["removeRuleIds"]?.intArrayValue ?? []
        let addValues = object["addRules"]?.arrayValue ?? []
        let parseResult = ChromeMV3DNRRuleParser.parseRuleValues(
            addValues,
            rulesetID: scope.rawValue,
            sourceKind: scope
        )
        guard parseResult.diagnostics.contains(where: { $0.severity == .error })
            == false
        else {
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage: parseResult.diagnostics.first?.message,
                lastErrorCode: "invalidRule",
                diagnostics: parseResult.diagnostics.map(\.message)
            )
        }
        let result = scope == .dynamic
            ? ruleStateOwner.updateDynamicRules(
                addRules: parseResult.rules,
                removeRuleIDs: removeIDs
            )
            : ruleStateOwner.updateSessionRules(
                addRules: parseResult.rules,
                removeRuleIDs: removeIDs
            )
        return response(
            request: request,
            succeeded: result.succeeded,
            payload: result.succeeded ? .null : nil,
            lastErrorMessage:
                result.succeeded ? nil : result.diagnostics.first?.message,
            lastErrorCode: result.succeeded ? nil : "invalidRuleUpdate",
            diagnostics:
                (parseResult.diagnostics + result.diagnostics).map(\.message)
        )
    }

    private func testMatchOutcome(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3DNRJSBridgeHostResponse {
        guard let object = request.arguments.first?.objectValue,
              let syntheticRequest =
                ChromeMV3DNRSyntheticRequest(dnrJSObject: object)
        else {
            return argumentError(
                request,
                "chrome.declarativeNetRequest.testMatchOutcome requires synthetic request details with a URL."
            )
        }
        let result = ChromeMV3DNRSyntheticEvaluator.evaluate(
            staticRulesetState: staticRulesetState,
            dynamicRules: ruleStateOwner.dynamicRules,
            sessionRules: ruleStateOwner.sessionRules,
            request: syntheticRequest
        )
        return response(
            request: request,
            succeeded: true,
            payload: result.storageValue,
            diagnostics: result.diagnostics
        )
    }

    private func argumentError(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        _ message: String
    ) -> ChromeMV3DNRJSBridgeHostResponse {
        rejectedRequestCount += 1
        return response(
            request: request,
            succeeded: false,
            lastErrorMessage: message,
            lastErrorCode: "invalidArguments",
            diagnostics: [message]
        )
    }

    private func response(
        request: ChromeMV3RuntimeJSBridgeHostRequest?,
        methodName: String? = nil,
        succeeded: Bool,
        payload: ChromeMV3StorageValue? = nil,
        lastErrorMessage: String? = nil,
        lastErrorCode: String? = nil,
        diagnostics: [String]
    ) -> ChromeMV3DNRJSBridgeHostResponse {
        let mode = request?.invocationMode ?? .promise
        return ChromeMV3DNRJSBridgeHostResponse(
            bridgeCallID: request?.bridgeCallID ?? "dnr-js-bridge-response",
            namespace: request?.namespace ?? "declarativeNetRequest",
            methodName: methodName ?? request?.methodName ?? "unknown",
            succeeded: succeeded,
            resultPayload: payload,
            lastErrorMessage: lastErrorMessage,
            lastErrorCode: lastErrorCode,
            callbackWouldSetLastError:
                succeeded == false && mode == .callback,
            promiseWouldReject:
                succeeded == false && mode == .promise,
            staticRulesetSummary: staticRulesetState.summary,
            ruleStoreSummary: ruleStateOwner.summary,
            dnrAvailableInInternalEvaluator:
                configuration.dnrAvailableInInternalEvaluator,
            dnrAvailableInProduct: false,
            dnrProductEnforcementAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedNetworkCompatibility(
                    diagnostics
                        + [
                            "DNR JS bridge response is synthetic/internal only.",
                            "Product DNR enforcement remains unavailable.",
                        ]
                )
        )
    }
}

enum ChromeMV3WebRequestCompatibilityStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case deferred
    case internalSyntheticOnly
    case observableSyntheticOnly
    case productBlocked
    case requiresDNRInstead
    case requiresManualDesign
    case unsupported

    static func < (
        lhs: ChromeMV3WebRequestCompatibilityStatus,
        rhs: ChromeMV3WebRequestCompatibilityStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3WebRequestEventName:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case onBeforeRequest
    case onBeforeSendHeaders
    case onCompleted
    case onErrorOccurred
    case onHeadersReceived
    case onResponseStarted
    case onSendHeaders

    static func < (
        lhs: ChromeMV3WebRequestEventName,
        rhs: ChromeMV3WebRequestEventName
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var lifecycleEvent: ChromeMV3ServiceWorkerSyntheticListenerEvent {
        switch self {
        case .onBeforeRequest:
            return .webRequestOnBeforeRequest
        case .onBeforeSendHeaders:
            return .webRequestOnBeforeSendHeaders
        case .onSendHeaders:
            return .webRequestOnSendHeaders
        case .onHeadersReceived:
            return .webRequestOnHeadersReceived
        case .onResponseStarted:
            return .webRequestOnResponseStarted
        case .onCompleted:
            return .webRequestOnCompleted
        case .onErrorOccurred:
            return .webRequestOnErrorOccurred
        }
    }
}

struct ChromeMV3WebRequestEventCompatibility:
    Codable,
    Equatable,
    Sendable
{
    var eventName: ChromeMV3WebRequestEventName
    var statuses: [ChromeMV3WebRequestCompatibilityStatus]
    var requiresWebRequestPermission: Bool
    var blockingBehaviorAvailableInProduct: Bool
    var headerMutationAvailableInProduct: Bool
    var diagnostics: [String]
}

struct ChromeMV3WebRequestCompatibilityReport:
    Codable,
    Equatable,
    Sendable
{
    var hasWebRequestPermission: Bool
    var hasWebRequestBlockingPermission: Bool
    var hasWebRequestAuthProviderPermission: Bool
    var hostPermissions: [String]
    var eventClassifications: [ChromeMV3WebRequestEventCompatibility]
    var webRequestAvailableInInternalFixture: Bool
    var webRequestBlockingAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

enum ChromeMV3WebRequestCompatibilityClassifier {
    static func classify(
        manifest: ChromeMV3Manifest?
    ) -> ChromeMV3WebRequestCompatibilityReport {
        let hasWebRequest = manifest?.declaresPermission("webRequest") ?? false
        let hasBlocking =
            manifest?.declaresPermission("webRequestBlocking") ?? false
        let hasAuth =
            manifest?.declaresPermission("webRequestAuthProvider") ?? false
        let hostPermissions = manifest?.hostPermissions ?? []
        let fixtureAvailable = hasWebRequest || hasBlocking || hasAuth

        return ChromeMV3WebRequestCompatibilityReport(
            hasWebRequestPermission: hasWebRequest,
            hasWebRequestBlockingPermission: hasBlocking,
            hasWebRequestAuthProviderPermission: hasAuth,
            hostPermissions: hostPermissions,
            eventClassifications:
                ChromeMV3WebRequestEventName.allCases.map {
                    classification(
                        event: $0,
                        fixtureAvailable: fixtureAvailable,
                        hasBlocking: hasBlocking
                    )
                }.sorted { $0.eventName < $1.eventName },
            webRequestAvailableInInternalFixture: fixtureAvailable,
            webRequestBlockingAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedNetworkCompatibility([
                    fixtureAvailable
                        ? "webRequest is classified for internal synthetic fixture observation only."
                        : "Manifest does not request webRequest permissions.",
                    hasBlocking
                        ? "webRequestBlocking is product-blocked; MV3 request modification must be redesigned around DNR or a future explicit product design."
                        : "webRequest blocking permission is absent or not usable in product.",
                    "No product network observer or blocking subscription is registered.",
                ])
        )
    }

    private static func classification(
        event: ChromeMV3WebRequestEventName,
        fixtureAvailable: Bool,
        hasBlocking: Bool
    ) -> ChromeMV3WebRequestEventCompatibility {
        var statuses: [ChromeMV3WebRequestCompatibilityStatus] =
            fixtureAvailable ? [.observableSyntheticOnly] : [.unsupported]
        var diagnostics: [String] = []
        if fixtureAvailable {
            diagnostics.append(
                "\(event.rawValue) can be emitted only by controlled synthetic tests."
            )
        }
        if hasBlocking {
            statuses.append(.productBlocked)
            statuses.append(.requiresDNRInstead)
            diagnostics.append(
                "\(event.rawValue) blocking or mutation behavior is unavailable in product."
            )
        }
        switch event {
        case .onBeforeRequest:
            diagnostics.append(
                "Request cancellation/redirect is not implemented as product webRequest blocking."
            )
        case .onBeforeSendHeaders, .onHeadersReceived:
            statuses.append(.requiresManualDesign)
            diagnostics.append(
                "Header observation can be modeled synthetically; header mutation is unsupported/deferred."
            )
        case .onSendHeaders, .onResponseStarted, .onCompleted,
             .onErrorOccurred:
            diagnostics.append(
                "Observable event payloads are fixture-only and not product navigation subscriptions."
            )
        }
        return ChromeMV3WebRequestEventCompatibility(
            eventName: event,
            statuses: Array(Set(statuses)).sorted(),
            requiresWebRequestPermission: true,
            blockingBehaviorAvailableInProduct: false,
            headerMutationAvailableInProduct: false,
            diagnostics: uniqueSortedNetworkCompatibility(diagnostics)
        )
    }
}

struct ChromeMV3WebRequestSyntheticEventRecord:
    Codable,
    Equatable,
    Sendable
{
    var requestID: String
    var eventName: ChromeMV3WebRequestEventName
    var url: String
    var method: String
    var resourceType: ChromeMV3DNRResourceType
    var tabID: Int?
    var frameID: Int?
    var initiator: String?
    var requestHeaders: [String: String]
    var responseHeaders: [String: String]
    var sequenceID: Int

    static func beforeRequest(
        url: String = "https://example.com/script.js",
        sequenceID: Int = 1
    ) -> ChromeMV3WebRequestSyntheticEventRecord {
        ChromeMV3WebRequestSyntheticEventRecord(
            requestID: "synthetic-web-request-\(sequenceID)",
            eventName: .onBeforeRequest,
            url: url,
            method: "GET",
            resourceType: .script,
            tabID: 1,
            frameID: 0,
            initiator: "https://example.com/",
            requestHeaders: [:],
            responseHeaders: [:],
            sequenceID: sequenceID
        )
    }

    var payload: ChromeMV3StorageValue {
        .object([
            "requestId": .string(requestID),
            "url": .string(url),
            "method": .string(method),
            "type": .string(resourceType.rawValue),
            "tabId": tabID.map { .number(Double($0)) } ?? .number(-1),
            "frameId": frameID.map { .number(Double($0)) } ?? .number(-1),
            "initiator": initiator.map(ChromeMV3StorageValue.string) ?? .null,
            "sequenceId": .number(Double(sequenceID)),
        ])
    }
}

struct ChromeMV3WebRequestSyntheticListenerRecord:
    Codable,
    Equatable,
    Sendable
{
    var listenerID: String
    var eventName: ChromeMV3WebRequestEventName
    var registeredSequence: Int
    var extraInfoSpec: [String]
    var diagnostics: [String]
}

struct ChromeMV3WebRequestSyntheticDispatchRecord:
    Codable,
    Equatable,
    Sendable
{
    var event: ChromeMV3WebRequestSyntheticEventRecord
    var dispatched: Bool
    var listenerIDs: [String]
    var sharedLifecycleSessionID: String?
    var serviceWorkerLifecycleWakeResult:
        ChromeMV3ServiceWorkerInternalWakeResult?
    var productRequestModified: Bool
    var diagnostics: [String]
}

struct ChromeMV3WebRequestSyntheticRegistrySummary:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var listenerCount: Int
    var listenerIDs: [String]
    var webRequestAvailableInInternalFixture: Bool
    var webRequestBlockingAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

final class ChromeMV3WebRequestSyntheticEventRegistry {
    let extensionID: String
    let profileID: String
    private var listeners:
        [ChromeMV3WebRequestEventName:
            [String: ChromeMV3WebRequestSyntheticListenerRecord]] = [:]
    private var nextSequence = 0
    private let sharedLifecycleSession:
        ChromeMV3ServiceWorkerSharedLifecycleSession?
    private let lifecycleComponentID: String

    init(
        extensionID: String = "web-request-synthetic-extension",
        profileID: String = "web-request-synthetic-profile",
        sharedLifecycleSession:
            ChromeMV3ServiceWorkerSharedLifecycleSession? = nil
    ) {
        self.extensionID = normalized(
            extensionID,
            fallback: "web-request-synthetic-extension"
        )
        self.profileID = normalized(
            profileID,
            fallback: "web-request-synthetic-profile"
        )
        self.sharedLifecycleSession = sharedLifecycleSession
        self.lifecycleComponentID =
            "web-request-harness:\(self.profileID):\(self.extensionID)"
        if let sharedLifecycleSession {
            _ = sharedLifecycleSession.attachComponent(
                kind: .webRequestHarness,
                componentID: lifecycleComponentID,
                eventSurfaces:
                    ChromeMV3WebRequestEventName.allCases
                    .map(\.lifecycleEvent),
                diagnostics: [
                    "webRequest harness attached for synthetic event dispatch only.",
                ]
            )
        }
    }

    @discardableResult
    func addListener(
        eventName: ChromeMV3WebRequestEventName,
        listenerID: String,
        extraInfoSpec: [String] = []
    ) -> ChromeMV3WebRequestSyntheticListenerRecord {
        nextSequence += 1
        let record = ChromeMV3WebRequestSyntheticListenerRecord(
            listenerID: normalized(
                listenerID,
                fallback: "web-request-listener-\(nextSequence)"
            ),
            eventName: eventName,
            registeredSequence: nextSequence,
            extraInfoSpec: extraInfoSpec.sorted(),
            diagnostics: [
                "webRequest listener is registered only in the internal synthetic registry.",
                "No product network observer is installed.",
            ]
        )
        listeners[eventName, default: [:]][record.listenerID] = record
        sharedLifecycleSession?.runtimeOwner.registerListener(
            event: eventName.lifecycleEvent,
            listenerID: record.listenerID
        )
        return record
    }

    func emit(
        _ event: ChromeMV3WebRequestSyntheticEventRecord
    ) -> ChromeMV3WebRequestSyntheticDispatchRecord {
        let matching = listeners[event.eventName]?.values.sorted {
            $0.listenerID < $1.listenerID
        } ?? []
        let wakeResult: ChromeMV3ServiceWorkerInternalWakeResult?
        if matching.isEmpty == false {
            wakeResult = sharedLifecycleSession?.runtimeOwner.requestWake(
                reason: .webRequestEvent,
                listenerEvent: event.eventName.lifecycleEvent,
                payload: event.payload,
                payloadSummary: "webRequest.\(event.eventName.rawValue)",
                sourceContext: .serviceWorker,
                sourceComponentID: lifecycleComponentID,
                sourceComponentKind: .webRequestHarness
            )
        } else {
            wakeResult = nil
        }
        return ChromeMV3WebRequestSyntheticDispatchRecord(
            event: event,
            dispatched: matching.isEmpty == false
                && (wakeResult?.dispatched ?? (sharedLifecycleSession == nil)),
            listenerIDs: matching.map(\.listenerID),
            sharedLifecycleSessionID:
                sharedLifecycleSession?.key.lifecycleSessionID,
            serviceWorkerLifecycleWakeResult: wakeResult,
            productRequestModified: false,
            diagnostics:
                uniqueSortedNetworkCompatibility([
                    matching.isEmpty
                        ? "No synthetic webRequest listener matched this event."
                        : "Synthetic webRequest event routed through the shared lifecycle session.",
                    "Product requests are not observed, blocked, redirected, or modified.",
                ])
        )
    }

    func tearDown() {
        listeners.removeAll()
        _ = sharedLifecycleSession?.detachComponent(
            componentID: lifecycleComponentID,
            reason: .reset
        )
    }

    var summary: ChromeMV3WebRequestSyntheticRegistrySummary {
        let records = listeners.values.flatMap(\.values)
        return ChromeMV3WebRequestSyntheticRegistrySummary(
            extensionID: extensionID,
            profileID: profileID,
            listenerCount: records.count,
            listenerIDs: records.map(\.listenerID).sorted(),
            webRequestAvailableInInternalFixture: true,
            webRequestBlockingAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics: [
                "webRequest synthetic registry is fixture state only.",
                "No product browser network/navigation subscription is added.",
            ]
        )
    }
}

struct ChromeMV3NetworkCompatibilityReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var dnrAvailableInInternalEvaluator: Bool
    var dnrAvailableInProduct: Bool
    var dnrProductEnforcementAvailable: Bool
    var webRequestAvailableInInternalFixture: Bool
    var webRequestBlockingAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
}

struct ChromeMV3NetworkCompatibilityReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var extensionID: String
    var profileID: String
    var dnrManifestRulesetModel: ChromeMV3DNRManifestRulesetModel
    var staticRulesetSummary: ChromeMV3DNRStaticRulesetStateSummary
    var dynamicSessionRuleStoreSummary: ChromeMV3DNRRuleStoreSummary
    var syntheticEvaluationResults: [ChromeMV3DNRSyntheticEvaluationResult]
    var dnrJSShimCoverage: ChromeMV3DNRJSShimCoverage
    var dnrJSMethodDiagnostics: [String]
    var webRequestCompatibility: ChromeMV3WebRequestCompatibilityReport
    var webRequestSyntheticRegistrySummary:
        ChromeMV3WebRequestSyntheticRegistrySummary
    var webRequestSyntheticDispatches:
        [ChromeMV3WebRequestSyntheticDispatchRecord]
    var productEnforcementStatus: [String: Bool]
    var futureMappingNotes: [String]
    var dnrAvailableInInternalEvaluator: Bool
    var dnrAvailableInProduct: Bool
    var dnrProductEnforcementAvailable: Bool
    var webRequestAvailableInInternalFixture: Bool
    var webRequestBlockingAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    var diagnostics: [String]

    var summary: ChromeMV3NetworkCompatibilityReportSummary {
        ChromeMV3NetworkCompatibilityReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            dnrAvailableInInternalEvaluator:
                dnrAvailableInInternalEvaluator,
            dnrAvailableInProduct: false,
            dnrProductEnforcementAvailable: false,
            webRequestAvailableInInternalFixture:
                webRequestAvailableInInternalFixture,
            webRequestBlockingAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false
        )
    }
}

enum ChromeMV3NetworkCompatibilityReportWriter {
    static let reportFileName = "runtime-network-compatibility-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3NetworkCompatibilityReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3NetworkCompatibilityReport {
        guard directoryExists(rootURL.standardizedFileURL) else {
            return report
        }
        try ChromeMV3DeterministicJSON.write(
            report,
            to: rootURL.standardizedFileURL
                .appendingPathComponent(Self.reportFileName)
        )
        return report
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}

enum ChromeMV3NetworkCompatibilityReportGenerator {
    static func makeReport(
        manifest: ChromeMV3Manifest? = nil,
        generatedBundleRootURL: URL? = nil,
        extensionID: String = "network-compatibility-extension",
        profileID: String = "network-compatibility-profile",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled
    ) -> ChromeMV3NetworkCompatibilityReport {
        let dnrModel = manifest.map {
            ChromeMV3DNRStaticRulesetLoader.loadRulesets(
                manifest: $0,
                generatedBundleRootURL: generatedBundleRootURL
            )
        } ?? .empty
        let staticState = ChromeMV3DNRStaticRulesetState(model: dnrModel)
        let store = ChromeMV3DNRRuleStateOwner(
            extensionID: extensionID,
            profileID: profileID
        )
        let sampleDynamicRule = parseSingleRule(
            [
                "id": 9_001,
                "priority": 1,
                "action": ["type": "block"],
                "condition": [
                    "urlFilter": "synthetic-dynamic-block",
                    "resourceTypes": ["script"],
                ],
            ],
            rulesetID: "dynamic",
            sourceKind: .dynamic
        )
        if let sampleDynamicRule {
            _ = store.updateDynamicRules(
                addRules: [sampleDynamicRule],
                removeRuleIDs: []
            )
        }
        let syntheticRequests = [
            ChromeMV3DNRSyntheticRequest.fixture(
                url: "https://example.com/synthetic-dynamic-block.js"
            ),
            ChromeMV3DNRSyntheticRequest.fixture(
                url: "http://example.com/plain.js",
                sequenceID: 2
            ),
        ]
        let evaluations = syntheticRequests.map {
            ChromeMV3DNRSyntheticEvaluator.evaluate(
                staticRulesetState: staticState,
                dynamicRules: store.dynamicRules,
                sessionRules: store.sessionRules,
                request: $0
            )
        }

        let dnrHandler = ChromeMV3DNRJSBridgeHandler(
            configuration: .syntheticHarness(
                extensionID: extensionID,
                profileID: profileID,
                moduleState: moduleState
            ),
            staticRulesetState: staticState,
            ruleStateOwner: store
        )
        let getEnabled = dnrHandler.handle(
            request(
                namespace: "declarativeNetRequest",
                methodName: "getEnabledRulesets"
            )
        )
        let testOutcome = dnrHandler.handle(
            request(
                namespace: "declarativeNetRequest",
                methodName: "testMatchOutcome",
                arguments: [
                    .object([
                        "url": .string(
                            "https://example.com/synthetic-dynamic-block.js"
                        ),
                        "type": .string("script"),
                        "tabId": .number(1),
                    ]),
                ]
            )
        )

        let webRequestCompatibility =
            ChromeMV3WebRequestCompatibilityClassifier.classify(
                manifest: manifest
            )
        let lifecycleRegistry = ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
        let lifecycleSession = lifecycleRegistry.session(
            profileID: profileID,
            extensionID: extensionID,
            moduleState: moduleState,
            explicitInternalLifecycleAllowed: true
        )
        let webRequestRegistry = ChromeMV3WebRequestSyntheticEventRegistry(
            extensionID: extensionID,
            profileID: profileID,
            sharedLifecycleSession: lifecycleSession
        )
        _ = webRequestRegistry.addListener(
            eventName: .onBeforeRequest,
            listenerID: "web-request-before-request-listener"
        )
        let webRequestDispatch = webRequestRegistry.emit(.beforeRequest())

        let reportID = stableIDNetworkCompatibility(
            prefix: "network-compatibility-report",
            parts: [
                extensionID,
                profileID,
                String(dnrModel.totalParsedRuleCount),
                String(webRequestCompatibility.webRequestAvailableInInternalFixture),
            ]
        )
        return ChromeMV3NetworkCompatibilityReport(
            schemaVersion: 1,
            id: reportID,
            reportFileName: ChromeMV3NetworkCompatibilityReportWriter
                .reportFileName,
            extensionID: extensionID,
            profileID: profileID,
            dnrManifestRulesetModel: dnrModel,
            staticRulesetSummary: staticState.summary,
            dynamicSessionRuleStoreSummary: store.summary,
            syntheticEvaluationResults: evaluations,
            dnrJSShimCoverage: ChromeMV3DNRJSShimSource.coverage,
            dnrJSMethodDiagnostics:
                uniqueSortedNetworkCompatibility(
                    getEnabled.diagnostics + testOutcome.diagnostics
                ),
            webRequestCompatibility: webRequestCompatibility,
            webRequestSyntheticRegistrySummary: webRequestRegistry.summary,
            webRequestSyntheticDispatches: [webRequestDispatch],
            productEnforcementStatus: [
                "dnrAvailableInProduct": false,
                "dnrProductEnforcementAvailable": false,
                "normalTabRuntimeBridgeAvailable": false,
                "productRuntimeExposed": false,
                "runtimeLoadable": false,
                "webRequestBlockingAvailableInProduct": false,
            ],
            futureMappingNotes: [
                "Possible WKContentRuleList mapping remains future work and is not attached here.",
                "Possible adblock-rust integration remains separate from MV3 DNR.",
                "DNR redirect and header modification need explicit product design before any enforcement.",
                "webRequest blocking and header mutation remain product-blocked.",
            ],
            dnrAvailableInInternalEvaluator:
                dnrModel.dnrAvailableInInternalEvaluator || manifest != nil,
            dnrAvailableInProduct: false,
            dnrProductEnforcementAvailable: false,
            webRequestAvailableInInternalFixture:
                webRequestCompatibility.webRequestAvailableInInternalFixture,
            webRequestBlockingAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            documentationSources: documentationSources(),
            diagnostics:
                uniqueSortedNetworkCompatibility(
                    dnrModel.diagnostics.map(\.message)
                        + webRequestCompatibility.diagnostics
                        + [
                            "Network compatibility report is internal and deterministic.",
                            "No product content-rule, URL loading hook, navigation delegate, or browser configuration integration is added.",
                            "runtimeLoadable remains false.",
                        ]
                )
        )
    }

    private static func parseSingleRule(
        _ object: [String: Any],
        rulesetID: String,
        sourceKind: ChromeMV3DNRRuleSourceKind
    ) -> ChromeMV3DNRRule? {
        let data = try? JSONSerialization.data(withJSONObject: [object])
        guard let data else { return nil }
        return ChromeMV3DNRRuleParser.parseRules(
            data: data,
            rulesetID: rulesetID,
            sourceKind: sourceKind
        ).rules.first
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            ChromeMV3WebKitObjectAcceptanceDocumentationSource(
                kind: "chromeDocumentation",
                title: "Chrome declarativeNetRequest API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest",
                note: "Defines static, dynamic, and session rules, enabled rulesets, rule actions, conditions, priorities, and testMatchOutcome."
            ),
            ChromeMV3WebKitObjectAcceptanceDocumentationSource(
                kind: "chromeDocumentation",
                title: "Chrome declarative_net_request manifest key",
                url: "https://developer.chrome.com/docs/extensions/reference/manifest/declarative-net-request",
                note: "Defines manifest rule_resources metadata for static rulesets."
            ),
            ChromeMV3WebKitObjectAcceptanceDocumentationSource(
                kind: "chromeDocumentation",
                title: "Chrome webRequest API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/webRequest",
                note: "Defines webRequest events, permissions, and MV3 blocking limitations."
            ),
            ChromeMV3WebKitObjectAcceptanceDocumentationSource(
                kind: "appleDocumentation",
                title: "WebKit content rules and web view configuration",
                url: "https://developer.apple.com/documentation/webkit",
                note: "Used only to document future mapping boundaries; this task does not attach WKContentRuleList or mutate WKWebViewConfiguration."
            ),
            ChromeMV3WebKitObjectAcceptanceDocumentationSource(
                kind: "currentSumiCode",
                title: "Sumi Chrome MV3 synthetic runtime foundation",
                url: nil,
                note: "Existing runtime, tabs, storage, permissions, native messaging, and event fixtures remain synthetic-only."
            ),
        ]
    }

    private static func request(
        namespace: String,
        methodName: String,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: stableIDNetworkCompatibility(
                prefix: "network-report-bridge-call",
                parts: [namespace, methodName]
            ),
            namespace: namespace,
            methodName: methodName,
            invocationMode: .promise,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }
}

private extension ChromeMV3DNRSyntheticRequest {
    init?(dnrJSObject object: [String: ChromeMV3StorageValue]) {
        guard let url = object["url"]?.stringValue else { return nil }
        let resourceType =
            object["type"]?.stringValue
            .flatMap(ChromeMV3DNRResourceType.init(rawValue:)) ?? .other
        self.init(
            url: url,
            method: object["method"]?.stringValue ?? "GET",
            resourceType: resourceType,
            initiator: object["initiator"]?.stringValue,
            tabID: object["tabId"]?.intValue,
            frameID: object["frameId"]?.intValue,
            documentID: object["documentId"]?.stringValue,
            requestHeaders: [:],
            responseHeaders: [:],
            lifecycleEventType: "testMatchOutcome",
            sequenceID: object["sequenceId"]?.intValue ?? 1
        )
    }
}

private extension ChromeMV3StorageValue {
    var objectValue: [String: ChromeMV3StorageValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var arrayValue: [ChromeMV3StorageValue]? {
        guard case .array(let array) = self else { return nil }
        return array
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self,
              value.isFinite,
              value.rounded(.towardZero) == value
        else { return nil }
        return Int(value)
    }

    var stringArrayValue: [String] {
        arrayValue?.compactMap(\.stringValue) ?? []
    }

    var intArrayValue: [Int] {
        arrayValue?.compactMap(\.intValue) ?? []
    }

    var dnrFoundationObject: Any {
        switch self {
        case .array(let values):
            return values.map(\.dnrFoundationObject)
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .number(let value):
            return value
        case .object(let object):
            return object.mapValues(\.dnrFoundationObject)
        case .string(let value):
            return value
        }
    }
}

private func deterministicRuleOrder(
    lhs: ChromeMV3DNRRule,
    rhs: ChromeMV3DNRRule
) -> Bool {
    if lhs.sourceKind != rhs.sourceKind {
        return lhs.sourceKind < rhs.sourceKind
    }
    if lhs.rulesetID != rhs.rulesetID {
        return lhs.rulesetID < rhs.rulesetID
    }
    if lhs.priority != rhs.priority {
        return lhs.priority > rhs.priority
    }
    return lhs.id < rhs.id
}

private func combinedStatus(
    _ statuses: [ChromeMV3DNRSupportStatus]
) -> ChromeMV3DNRSupportStatus {
    if statuses.contains(.unsupported) { return .unsupported }
    if statuses.contains(.deferred) { return .deferred }
    if statuses.contains(.partial) { return .partial }
    return .supported
}

private func safeRelativePath(_ path: String) -> String? {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return nil }
    let pathBeforeFragment = trimmed.split(
        separator: "#",
        maxSplits: 1,
        omittingEmptySubsequences: false
    ).first.map(String.init) ?? trimmed
    let pathOnly = pathBeforeFragment.split(
        separator: "?",
        maxSplits: 1,
        omittingEmptySubsequences: false
    ).first.map(String.init) ?? pathBeforeFragment
    let decoded = pathOnly.removingPercentEncoding ?? pathOnly
    guard decoded.hasPrefix("/") == false,
          decoded.hasPrefix("~") == false,
          decoded.contains("\\") == false,
          decoded.contains("\0") == false,
          decoded.localizedCaseInsensitiveContains("://") == false,
          decoded.contains("*") == false
    else { return nil }
    let segments = decoded.split(separator: "/", omittingEmptySubsequences: false)
    guard segments.isEmpty == false,
          segments.allSatisfy({
              $0.isEmpty == false && $0 != "." && $0 != ".."
          })
    else { return nil }
    return decoded
}

private func diagnostic(
    _ code: String,
    _ severity: ChromeMV3DNRDiagnosticSeverity,
    _ field: String?,
    _ message: String
) -> ChromeMV3DNRDiagnostic {
    ChromeMV3DNRDiagnostic(
        code: code,
        severity: severity,
        field: field,
        message: message
    )
}

private func uniqueDiagnostics(
    _ diagnostics: [ChromeMV3DNRDiagnostic]
) -> [ChromeMV3DNRDiagnostic] {
    var seen: Set<String> = []
    var unique: [ChromeMV3DNRDiagnostic] = []
    for diagnostic in diagnostics.sorted(by: {
        if $0.code == $1.code {
            return ($0.field ?? "") < ($1.field ?? "")
        }
        return $0.code < $1.code
    }) {
        let key =
            "\(diagnostic.code)|\(diagnostic.field ?? "")|\(diagnostic.message)"
        if seen.insert(key).inserted {
            unique.append(diagnostic)
        }
    }
    return unique
}

private func normalized(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

private func uniqueSortedNetworkCompatibility(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

private func stableIDNetworkCompatibility(
    prefix: String,
    parts: [String]
) -> String {
    let seed = parts.joined(separator: "\u{1F}")
    let digest = SHA256.hash(data: Data(seed.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-\(String(hex.prefix(16)))"
}

private func jsonStringNetworkCompatibility(_ object: [String: String]) -> String {
    let data = try? JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys]
    )
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
}
