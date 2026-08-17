import Combine
import Foundation
import SumiDomain

@MainActor
final class AdblockManifestRuleListProvider: SumiContentRuleListSetProviding {
    private var manifest: AdblockCompiledGenerationManifest?
    private var compiledDefinitionsByIdentifier: [String: SumiContentRuleListDefinition]
    private let compiledDefinitionLoader: (NativeContentBlockingShardDescriptor) throws -> SumiContentRuleListDefinition
    private let changesSubject = PassthroughSubject<Void, Never>()

    init(
        manifest: AdblockCompiledGenerationManifest?,
        compiledDefinitions: [SumiContentRuleListDefinition] = [],
        compiledDefinitionLoader: @escaping (NativeContentBlockingShardDescriptor) throws -> SumiContentRuleListDefinition = {
            throw AdblockUpdateDiagnostics(
                summary: "Missing compiled Adblock shard definition: \($0.webKitIdentifier)",
                failedShardIdentifier: $0.webKitIdentifier
            )
        }
    ) {
        self.manifest = manifest
        compiledDefinitionsByIdentifier = Dictionary(
            uniqueKeysWithValues: compiledDefinitions.map { ($0.storeIdentifierOverride ?? $0.name, $0) }
        )
        self.compiledDefinitionLoader = compiledDefinitionLoader
    }

    var changesPublisher: AnyPublisher<Void, Never> { changesSubject.eraseToAnyPublisher() }
    var activeManifest: AdblockCompiledGenerationManifest? { manifest }

    func updateManifest(
        _ manifest: AdblockCompiledGenerationManifest?,
        compiledDefinitions: [SumiContentRuleListDefinition] = []
    ) {
        let definitionsByIdentifier = Dictionary(
            uniqueKeysWithValues: compiledDefinitions.map { ($0.storeIdentifierOverride ?? $0.name, $0) }
        )
        guard self.manifest != manifest || compiledDefinitionsByIdentifier != definitionsByIdentifier else { return }
        self.manifest = manifest
        compiledDefinitionsByIdentifier = definitionsByIdentifier
        changesSubject.send(())
    }

    func ruleListSet() throws -> SumiContentRuleListSet {
        guard let manifest else { return SumiContentRuleListSet() }
        let definitions = try manifest.networkShards.map { shard in
            if let definition = compiledDefinitionsByIdentifier[shard.webKitIdentifier] {
                return definition
            }
            return try compiledDefinitionLoader(shard)
        }
        return SumiContentRuleListSet(definitions: definitions)
    }

    /// Loads payload-backed definitions for attachment preparation. Metadata-only
    /// definitions cached for WebKit lookup restoration are intentionally ignored.
    func persistedDefinitions(
        for protectionGroups: Set<SumiProtectionGroupKind>
    ) throws -> [SumiContentRuleListDefinition] {
        guard let manifest else { return [] }
        return try manifest.networkShards
            .filter { shard in
                shard.protectionGroup.map(protectionGroups.contains) ?? false
            }
            .sorted { lhs, rhs in
                if lhs.protectionGroup == rhs.protectionGroup {
                    return lhs.id < rhs.id
                }
                return (lhs.protectionGroup?.rawValue ?? "")
                    < (rhs.protectionGroup?.rawValue ?? "")
            }
            .map(compiledDefinitionLoader)
    }

    static func diskBackedDefinitionLoader(
        storageRoot: URL,
        fileManager: FileManager = .default
    ) -> (NativeContentBlockingShardDescriptor) throws -> SumiContentRuleListDefinition {
        let reader = AdblockArchivedShardReader(
            storageRoot: storageRoot,
            fileManager: fileManager
        )
        return reader.definition
    }

    static func metadataOnlyDefinitions(
        for manifest: AdblockCompiledGenerationManifest
    ) -> [SumiContentRuleListDefinition] {
        manifest.networkShards
            .sorted { lhs, rhs in
                lhs.kind == rhs.kind
                    ? lhs.id < rhs.id
                    : lhs.kind.rawValue < rhs.kind.rawValue
            }
            .map { shard in
                SumiContentRuleListDefinition(
                    name: shard.webKitIdentifier,
                    encodedContentRuleList: "",
                    storeIdentifierOverride: shard.webKitIdentifier,
                    contentHashOverride: shard.contentHash
                )
            }
    }
}
