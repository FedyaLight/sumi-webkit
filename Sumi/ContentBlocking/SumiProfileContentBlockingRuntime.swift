import Combine
import Foundation

/// Owns profile-specific materialization, debounce generations, and publisher
/// lifetime. It is created only when the rule source declares profile-specific
/// lists, so the common global-only path pays no observer or task cost.
@MainActor
final class SumiProfileContentBlockingRuntime {
    private enum TaskKey: Hashable {
        case refresh(String)
    }

    private let ruleListProvider: SumiContentRuleListSetProviding
    private let materializer: SumiContentRuleListMaterializer
    private let publication: SumiContentBlockingPublication
    private let privacyConfigurationManager:
        SumiContentBlockingPrivacyConfigurationManager
    private let globalState: SumiContentBlockingStateMachine
    private let taskRegistry = ContentBlockingTaskRegistry<TaskKey>()
    private var refreshGenerations: [String: Int] = [:]
    private var isStopped = false

    init(
        ruleListProvider: SumiContentRuleListSetProviding,
        materializer: SumiContentRuleListMaterializer,
        publication: SumiContentBlockingPublication,
        privacyConfigurationManager:
            SumiContentBlockingPrivacyConfigurationManager,
        globalState: SumiContentBlockingStateMachine
    ) {
        self.ruleListProvider = ruleListProvider
        self.materializer = materializer
        self.publication = publication
        self.privacyConfigurationManager = privacyConfigurationManager
        self.globalState = globalState
    }

    func userContentPublisher(
        scriptsProvider: SumiNormalTabUserScripts,
        profileId: UUID
    ) -> AnyPublisher<SumiNormalTabUserContent, Never> {
        let publisher = publication.profileUserContentPublisher(
            profileId: profileId,
            scriptsProvider: scriptsProvider
        )
        scheduleRefresh(profileId: profileId, delayNanoseconds: 0)
        return publisher
    }

    func scheduleActiveRefreshes(
        delayNanoseconds: UInt64 = 150_000_000
    ) {
        guard !isStopped else { return }
        for profileId in publication.activeProfileIDs {
            scheduleRefresh(
                profileId: profileId,
                delayNanoseconds: delayNanoseconds
            )
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        refreshGenerations = refreshGenerations.mapValues { $0 + 1 }
        taskRegistry.cancelAll()
    }

    #if DEBUG
        func drainTasksForTests(cancel: Bool) async {
            await taskRegistry.drainTasksForTests(cancel: cancel)
        }
    #endif

    private func scheduleRefresh(
        profileId: UUID,
        delayNanoseconds: UInt64
    ) {
        guard !isStopped else { return }
        let key = profileId.uuidString.lowercased()
        let generation = (refreshGenerations[key] ?? 0) + 1
        refreshGenerations[key] = generation

        taskRegistry.replaceTask(for: .refresh(key)) { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard let self,
                  !Task.isCancelled,
                  self.isCurrent(generation, profileKey: key)
            else { return }
            do {
                let ruleLists = try self.ruleListProvider.ruleListSet(
                    profileId: profileId
                ).allDefinitions
                guard self.isCurrent(generation, profileKey: key) else {
                    return
                }
                let update = try await self.materializer.updateEvent(
                    for: ruleLists
                )
                guard self.isCurrent(generation, profileKey: key) else {
                    return
                }
                if !ruleLists.isEmpty {
                    self.privacyConfigurationManager
                        .setContentBlockingEnabled(true)
                } else if self.globalState.currentPolicy.ruleLists.isEmpty {
                    self.privacyConfigurationManager
                        .setContentBlockingEnabled(false)
                }
                self.publication.publishProfile(
                    update,
                    profileId: profileId
                )
            } catch {
                guard self.isCurrent(generation, profileKey: key) else {
                    return
                }
                self.publication.publishEmptyProfileIfUninitialized(
                    profileId: profileId
                )
            }
        }
    }

    private func isCurrent(_ generation: Int, profileKey: String) -> Bool {
        !isStopped && refreshGenerations[profileKey] == generation
    }
}
