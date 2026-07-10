import Combine
import Foundation

@MainActor
protocol SumiRuleListProviderUpdateApplying: AnyObject {
    func applyGlobalRuleListDefinitions(
        _ definitions: [SumiContentRuleListDefinition],
        refreshProfiles: Bool
    )

    func handleGlobalRuleListProviderFailure(refreshProfiles: Bool)
}

/// Owns the observation and debounce lifetime of an external rule-list source.
/// The target owns policy transitions; this runtime only delivers current
/// provider snapshots and never performs WebKit or publication effects.
@MainActor
final class SumiRuleListProviderRuntime {
    private enum TaskKey: Hashable {
        case refresh
    }

    private let provider: SumiContentRuleListSetProviding
    private weak var updateTarget: (any SumiRuleListProviderUpdateApplying)?
    private let taskRegistry = ContentBlockingTaskRegistry<TaskKey>()
    private var changesCancellable: AnyCancellable?
    private var refreshGeneration = 0
    private var isStopped = false

    init(
        provider: SumiContentRuleListSetProviding,
        updateTarget: any SumiRuleListProviderUpdateApplying
    ) {
        self.provider = provider
        self.updateTarget = updateTarget
        changesCancellable = provider.changesPublisher.sink { [weak self] in
            self?.scheduleRefresh(refreshProfiles: true)
        }
        scheduleRefresh(
            refreshProfiles: false,
            delayNanoseconds: 0
        )
    }

    isolated deinit {
        changesCancellable?.cancel()
        taskRegistry.cancelAll()
    }

    func invalidatePendingRefresh() {
        guard !isStopped else { return }
        refreshGeneration += 1
        taskRegistry.cancelTask(for: .refresh)
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        refreshGeneration += 1
        changesCancellable?.cancel()
        changesCancellable = nil
        taskRegistry.cancelAll()
    }

    #if DEBUG
        func drainTasksForTests(cancel: Bool) async {
            await taskRegistry.drainTasksForTests(cancel: cancel)
        }
    #endif

    private func scheduleRefresh(
        refreshProfiles: Bool,
        delayNanoseconds: UInt64 = 150_000_000
    ) {
        guard !isStopped else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        taskRegistry.replaceTask(for: .refresh) { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard let self,
                  self.isCurrent(generation)
            else { return }

            do {
                let definitions = try self.provider.ruleListSet(
                    profileId: nil
                ).allDefinitions
                guard self.isCurrent(generation) else { return }
                self.updateTarget?.applyGlobalRuleListDefinitions(
                    definitions,
                    refreshProfiles: refreshProfiles
                )
            } catch {
                guard self.isCurrent(generation) else { return }
                self.updateTarget?.handleGlobalRuleListProviderFailure(
                    refreshProfiles: refreshProfiles
                )
            }
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        !isStopped
            && !Task.isCancelled
            && refreshGeneration == generation
    }
}
