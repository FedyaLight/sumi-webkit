import Combine
import Foundation

/// Coordinates policy transitions and refresh task lifetime. WebKit IO,
/// transition decisions, observer publication, and compiled-list retirement
/// are delegated to components that own those states directly.
@MainActor
final class SumiContentBlockingService {
    private enum TaskKey: Hashable {
        case compilation
    }

    let privacyConfigurationManager: SumiContentBlockingPrivacyConfigurationManager

    private let ruleListMaterializer: SumiContentRuleListMaterializer
    private let publication: SumiContentBlockingPublication
    private let taskRegistry = ContentBlockingTaskRegistry<TaskKey>()
    private let stateMachine: SumiContentBlockingStateMachine
    private var ruleListProviderRuntime: SumiRuleListProviderRuntime?

    var latestUpdate: SumiContentBlockerRulesUpdate? {
        publication.latestUpdate
    }

    var latestRuleListIdentifiers: [String] {
        publication.latestRuleListIdentifiers
    }

    #if DEBUG
        convenience init(
            policy: SumiContentBlockingPolicy = .defaultPolicy,
            compiler: SumiContentRuleListCompiling =
                SumiWKContentRuleListCompiler(),
            ruleListProvider: SumiContentRuleListSetProviding? = nil,
            compiledRuleListCatalog: SumiCompiledContentRuleListCataloging =
                SumiContentBlockingService.defaultCompiledRuleListCatalog,
            startupDiagnostics: any SumiProtectionStartupRestoreDiagnosticsRecording =
                SumiProtectionStartupRestoreDiagnosticsDefaults.recorder
        ) {
            let materializer = SumiContentRuleListMaterializer(
                compiler: compiler,
                startupDiagnostics: startupDiagnostics
            )
            self.init(
                policy: policy,
                ruleListProvider: ruleListProvider,
                ruleListMaterializer: materializer,
                retirement: SumiCompiledContentRuleListRetirement(
                    compiler: compiler,
                    catalog: compiledRuleListCatalog,
                    startupDiagnostics: startupDiagnostics
                )
            )
        }
    #else
        convenience init(
            policy: SumiContentBlockingPolicy = .defaultPolicy,
            compiler: SumiContentRuleListCompiling =
                SumiWKContentRuleListCompiler(),
            ruleListProvider: SumiContentRuleListSetProviding? = nil,
            compiledRuleListCatalog: SumiCompiledContentRuleListCataloging =
                SumiContentBlockingService.defaultCompiledRuleListCatalog
        ) {
            let materializer = SumiContentRuleListMaterializer(compiler: compiler)
            self.init(
                policy: policy,
                ruleListProvider: ruleListProvider,
                ruleListMaterializer: materializer,
                retirement: SumiCompiledContentRuleListRetirement(
                    compiler: compiler,
                    catalog: compiledRuleListCatalog
                )
            )
        }
    #endif

    private init(
        policy: SumiContentBlockingPolicy,
        ruleListProvider: SumiContentRuleListSetProviding?,
        ruleListMaterializer: SumiContentRuleListMaterializer,
        retirement: SumiCompiledContentRuleListRetirement
    ) {
        self.ruleListMaterializer = ruleListMaterializer
        let stateMachine = SumiContentBlockingStateMachine(policy: policy)
        self.stateMachine = stateMachine
        let privacyConfigurationManager =
            SumiContentBlockingPrivacyConfigurationManager(
                isContentBlockingEnabled: policy.shouldEnableContentBlockingFeature
            )
        self.privacyConfigurationManager = privacyConfigurationManager
        let initialUpdate: SumiContentBlockerRulesUpdate? =
            policy.ruleLists.isEmpty && ruleListProvider == nil
                ? SumiContentBlockingPublication.emptyUpdate()
                : nil
        let publication = SumiContentBlockingPublication(
            initialUpdate: initialUpdate,
            retirement: retirement,
            materializer: ruleListMaterializer
        )
        self.publication = publication
        if let ruleListProvider {
            ruleListProviderRuntime = SumiRuleListProviderRuntime(
                provider: ruleListProvider,
                updateTarget: self
            )
        } else if let request = stateMachine.beginInitialCompilation() {
            scheduleCompilation(request)
        }
    }

    private static let defaultCompiledRuleListCatalog:
        SumiCompiledContentRuleListCataloging =
            SumiCompiledContentRuleListCatalog()

    isolated deinit {
        taskRegistry.cancelAll()
        ruleListProviderRuntime?.stop()
    }

    var updatesPublisher: AnyPublisher<SumiContentBlockerRulesUpdate, Never> {
        publication.updatesPublisher
    }

    func userContentPublisher(
        for scriptsProvider: SumiNormalTabUserScripts
    ) -> AnyPublisher<SumiNormalTabUserContent, Never> {
        publication.userContentPublisher(scriptsProvider: scriptsProvider)
    }

    func setPolicy(_ policy: SumiContentBlockingPolicy) {
        let request = stateMachine.requestPolicy(
            policy,
            hasPublishedUpdate: latestUpdate != nil
        )
        switch request {
        case .ignored:
            return
        case .publishDisabled:
            taskRegistry.cancelTask(for: .compilation)
            privacyConfigurationManager.setContentBlockingEnabled(false)
            publication.publish(
                SumiContentBlockingPublication.emptyUpdate(),
                replacing: latestUpdate
            )
        case .compile(let compilation):
            privacyConfigurationManager.setContentBlockingEnabled(
                policy.shouldEnableContentBlockingFeature
            )
            scheduleCompilation(compilation)
        }
    }

    func prepareRuleListUpdate(
        ruleLists definitions: [SumiContentRuleListDefinition],
        retainEncodedRuleListsInPreparedPolicy: Bool = true
    ) async throws -> SumiPreparedContentBlockingUpdate {
        let policy: SumiContentBlockingPolicy = definitions.isEmpty
            ? .disabled
            : .enabled(
                ruleLists: retainEncodedRuleListsInPreparedPolicy
                    ? definitions
                    : definitions.map { $0.metadataOnly() }
            )
        return SumiPreparedContentBlockingUpdate(
            policy: policy,
            updateEvent: try await ruleListMaterializer.updateEvent(
                for: definitions
            )
        )
    }

    func prepareExistingRuleListUpdate(
        ruleLists definitions: [SumiContentRuleListDefinition]
    ) async throws -> SumiPreparedContentBlockingUpdate {
        let definitions = definitions.map { $0.metadataOnly() }
        let policy: SumiContentBlockingPolicy = definitions.isEmpty
            ? .disabled
            : .enabled(ruleLists: definitions)
        return SumiPreparedContentBlockingUpdate(
            policy: policy,
            updateEvent: try await ruleListMaterializer.existingUpdateEvent(
                for: definitions
            )
        )
    }

    func commitPreparedContentBlockingUpdate(
        _ preparedUpdate: SumiPreparedContentBlockingUpdate
    ) {
        guard let staged = stagePreparedContentBlockingUpdate(preparedUpdate)
        else { return }
        publishStagedContentBlockingUpdate(staged)
    }

    func stagePreparedContentBlockingUpdate(
        _ preparedUpdate: SumiPreparedContentBlockingUpdate
    ) -> SumiStagedContentBlockingPublication? {
        guard let generation = stateMachine.stagePreparedPolicy(
            preparedUpdate.policy
        ) else { return nil }
        ruleListProviderRuntime?.invalidatePendingRefresh()
        privacyConfigurationManager.setContentBlockingEnabled(
            preparedUpdate.policy.shouldEnableContentBlockingFeature
        )
        return SumiStagedContentBlockingPublication(
            compilationGeneration: generation,
            updateEvent: preparedUpdate.updateEvent,
            previousUpdate: publication.stage(preparedUpdate.updateEvent)
        )
    }

    func publishStagedContentBlockingUpdate(
        _ staged: SumiStagedContentBlockingPublication
    ) {
        guard stateMachine.canPublishStagedUpdate(
            generation: staged.compilationGeneration
        ) else { return }
        publication.publishStaged(
            staged.updateEvent,
            replacing: staged.previousUpdate
        )
    }

    func stopRuntime() {
        guard stateMachine.stop() else { return }
        ruleListProviderRuntime?.stop()
        taskRegistry.cancelAll()
    }

    #if DEBUG
        func drainScheduledTasksForTests(cancel: Bool = false) async {
            await taskRegistry.drainTasksForTests(cancel: cancel)
            await ruleListProviderRuntime?.drainTasksForTests(cancel: cancel)
        }
    #endif

    private func scheduleCompilation(
        _ request: SumiContentBlockingCompilationRequest
    ) {
        taskRegistry.replaceTask(for: .compilation) { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.compileAndPublish(request)
        }
    }

    private func compileAndPublish(
        _ request: SumiContentBlockingCompilationRequest
    ) async {
        do {
            let update = try await ruleListMaterializer.updateEvent(
                for: request.policy.ruleLists
            )
            guard stateMachine.acceptCompilation(request) else { return }
            privacyConfigurationManager.setContentBlockingEnabled(
                request.policy.shouldEnableContentBlockingFeature
            )
            publication.publish(update, replacing: latestUpdate)
        } catch {
            switch stateMachine.rejectCompilation(
                request,
                hasPublishedRules: latestUpdate?.rules.isEmpty == false
            ) {
            case .stale:
                return
            case .restore(let policy):
                privacyConfigurationManager.setContentBlockingEnabled(
                    policy.shouldEnableContentBlockingFeature
                )
            case .disable:
                privacyConfigurationManager.setContentBlockingEnabled(false)
                publication.publish(
                    SumiContentBlockingPublication.emptyUpdate(),
                    replacing: latestUpdate
                )
            }
        }
    }
}

extension SumiContentBlockingService: SumiRuleListProviderUpdateApplying {
    func applyGlobalRuleListDefinitions(
        _ definitions: [SumiContentRuleListDefinition],
        refreshProfiles: Bool
    ) {
        setPolicy(
            definitions.isEmpty
                ? .disabled
                : .enabled(ruleLists: definitions)
        )
        _ = refreshProfiles
    }

    func handleGlobalRuleListProviderFailure(refreshProfiles: Bool) {
        if latestUpdate == nil {
            setPolicy(.disabled)
        }
        _ = refreshProfiles
    }
}
