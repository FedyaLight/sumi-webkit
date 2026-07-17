import CryptoKit
import Foundation

struct SumiContentRuleListDefinition: Equatable, Sendable {
    let name: String
    let encodedContentRuleList: String
    let storeIdentifierOverride: String?
    private let contentHashOverride: String?

    init(
        name: String,
        encodedContentRuleList: String,
        storeIdentifierOverride: String? = nil,
        contentHashOverride: String? = nil
    ) {
        self.name = name
        self.encodedContentRuleList = encodedContentRuleList
        self.storeIdentifierOverride = storeIdentifierOverride
        self.contentHashOverride = contentHashOverride
    }

    var contentHash: String {
        if let contentHashOverride {
            return contentHashOverride
        }
        let digest = SHA256.hash(data: Data(encodedContentRuleList.utf8))
        return digest.prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    var webKitStoreIdentifier: String {
        storeIdentifierOverride ?? SumiContentBlockerRulesIdentifier(
            name: name,
            tdsEtag: contentHash,
            tempListId: nil,
            allowListId: nil,
            unprotectedSitesHash: nil
        ).stringValue
    }

    func metadataOnly() -> SumiContentRuleListDefinition {
        SumiContentRuleListDefinition(
            name: name,
            encodedContentRuleList: "",
            storeIdentifierOverride: storeIdentifierOverride,
            contentHashOverride: contentHash
        )
    }

    static func == (
        lhs: SumiContentRuleListDefinition,
        rhs: SumiContentRuleListDefinition
    ) -> Bool {
        lhs.name == rhs.name
            && lhs.storeIdentifierOverride == rhs.storeIdentifierOverride
            && lhs.contentHash == rhs.contentHash
    }
}

enum SumiContentBlockingPolicy: Equatable, Sendable {
    case disabled
    case enabled(ruleLists: [SumiContentRuleListDefinition])

    static let defaultPolicy = SumiContentBlockingPolicy.disabled

    var ruleLists: [SumiContentRuleListDefinition] {
        switch self {
        case .disabled:
            return []
        case .enabled(let ruleLists):
            return ruleLists
        }
    }

    var shouldEnableContentBlockingFeature: Bool {
        !ruleLists.isEmpty
    }

    var metadataOnly: SumiContentBlockingPolicy {
        switch self {
        case .disabled:
            return .disabled
        case .enabled(let ruleLists):
            return .enabled(ruleLists: ruleLists.map { $0.metadataOnly() })
        }
    }
}

enum SumiContentBlockingCompilationError: Error, LocalizedError {
    case missingCompiledRuleList(String)
    case failedToCompileRuleList(String, String)

    var identifier: String {
        switch self {
        case .missingCompiledRuleList(let identifier),
             .failedToCompileRuleList(let identifier, _):
            return identifier
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingCompiledRuleList(let identifier):
            return "Compiled content rule list could not be looked up: \(identifier)"
        case .failedToCompileRuleList(let identifier, let reason):
            return "Failed to compile content rule list \(identifier): \(reason)"
        }
    }
}

struct SumiPreparedContentBlockingUpdate {
    let policy: SumiContentBlockingPolicy
    let updateEvent: SumiContentBlockerRulesUpdate
}

struct SumiStagedContentBlockingPublication {
    let compilationGeneration: Int
    let updateEvent: SumiContentBlockerRulesUpdate
    let previousUpdate: SumiContentBlockerRulesUpdate?
}
