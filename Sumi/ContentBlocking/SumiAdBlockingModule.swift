import Foundation

enum SumiAdBlockingModuleStatus: Equatable, Sendable {
    case disabled
    case enabledButEngineUnavailable
}

struct SumiAdBlockingAssets: Equatable, Sendable {
    static let empty = SumiAdBlockingAssets()

    let contentRuleListIdentifiers: [String]
    let scriptSources: [String]
    let scriptMessageHandlerNames: [String]

    init(
        contentRuleListIdentifiers: [String] = [],
        scriptSources: [String] = [],
        scriptMessageHandlerNames: [String] = []
    ) {
        self.contentRuleListIdentifiers = contentRuleListIdentifiers
        self.scriptSources = scriptSources
        self.scriptMessageHandlerNames = scriptMessageHandlerNames
    }

    var isEmpty: Bool {
        contentRuleListIdentifiers.isEmpty
            && scriptSources.isEmpty
            && scriptMessageHandlerNames.isEmpty
    }
}

struct SumiAdBlockingNormalTabDecision: Equatable, Sendable {
    let status: SumiAdBlockingModuleStatus
    let assets: SumiAdBlockingAssets

    static let disabled = SumiAdBlockingNormalTabDecision(
        status: .disabled,
        assets: .empty
    )
}

@MainActor
final class SumiAdBlockingModule {
    static let shared = SumiAdBlockingModule()

    private let moduleRegistry: SumiModuleRegistry

    init(moduleRegistry: SumiModuleRegistry = .shared) {
        self.moduleRegistry = moduleRegistry
    }

    var isEnabled: Bool {
        moduleRegistry.isEnabled(.adBlocking)
    }

    var status: SumiAdBlockingModuleStatus {
        isEnabled ? .enabledButEngineUnavailable : .disabled
    }

    var hasLoadedRuntime: Bool {
        false
    }

    func setEnabled(_ isEnabled: Bool) {
        moduleRegistry.setEnabled(isEnabled, for: .adBlocking)
    }

    func assetsIfAvailable() -> SumiAdBlockingAssets {
        .empty
    }

    func normalTabDecision(for url: URL?) -> SumiAdBlockingNormalTabDecision {
        _ = url
        return SumiAdBlockingNormalTabDecision(
            status: status,
            assets: .empty
        )
    }
}
