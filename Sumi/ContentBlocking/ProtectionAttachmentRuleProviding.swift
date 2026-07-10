import Foundation
import SumiDomain

@MainActor
protocol ProtectionAttachmentRuleProviding: AnyObject {
    func setRuntimeLevel(_ level: SumiProtectionLevel)
    func activeManifestIfLoaded() -> AdblockCompiledGenerationManifest?
    func contentRuleListDefinitions(
        for protectionGroups: Set<SumiProtectionGroupKind>
    ) throws -> [SumiContentRuleListDefinition]
    func siteOverride(for url: URL?) -> SumiAdblockSiteOverride
}

extension SumiAdBlockingModule: ProtectionAttachmentRuleProviding {}
