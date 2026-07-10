import Foundation

struct SumiContentBlockingCompilationRequest: Equatable, Sendable {
    let generation: Int
    let policy: SumiContentBlockingPolicy
    let previousPolicy: SumiContentBlockingPolicy?
}

enum SumiContentBlockingPolicyRequest: Equatable, Sendable {
    case ignored
    case publishDisabled
    case compile(SumiContentBlockingCompilationRequest)
}

enum SumiContentBlockingCompilationFailure: Equatable, Sendable {
    case stale
    case restore(SumiContentBlockingPolicy)
    case disable
}

/// Pure transition state for the content-blocking runtime. It decides which
/// effect is valid; WebKit materialization, Combine publication, and task
/// cancellation remain outside this value.
@MainActor
final class SumiContentBlockingStateMachine {
    private(set) var currentPolicy: SumiContentBlockingPolicy
    private(set) var isStopped = false
    private var compilationGeneration = 0

    init(policy: SumiContentBlockingPolicy) {
        currentPolicy = policy
    }

    func requestPolicy(
        _ policy: SumiContentBlockingPolicy,
        hasPublishedUpdate: Bool
    ) -> SumiContentBlockingPolicyRequest {
        guard !isStopped else { return .ignored }
        guard policy != currentPolicy else {
            guard !hasPublishedUpdate, policy.ruleLists.isEmpty else {
                return .ignored
            }
            compilationGeneration += 1
            return .publishDisabled
        }

        let previousPolicy = currentPolicy
        currentPolicy = policy
        guard !policy.ruleLists.isEmpty else {
            compilationGeneration += 1
            return .publishDisabled
        }
        return .compile(beginCompilation(for: policy, previousPolicy: previousPolicy))
    }

    func beginInitialCompilation() -> SumiContentBlockingCompilationRequest? {
        guard !isStopped, !currentPolicy.ruleLists.isEmpty else { return nil }
        return beginCompilation(for: currentPolicy, previousPolicy: nil)
    }

    func stagePreparedPolicy(
        _ policy: SumiContentBlockingPolicy
    ) -> Int? {
        guard !isStopped else { return nil }
        compilationGeneration += 1
        currentPolicy = policy
        return compilationGeneration
    }

    func canPublishStagedUpdate(generation: Int) -> Bool {
        !isStopped && generation == compilationGeneration
    }

    func acceptCompilation(
        _ request: SumiContentBlockingCompilationRequest
    ) -> Bool {
        guard !isStopped,
              request.generation == compilationGeneration,
              request.policy == currentPolicy
        else { return false }
        currentPolicy = request.policy.metadataOnly
        return true
    }

    func rejectCompilation(
        _ request: SumiContentBlockingCompilationRequest,
        hasPublishedRules: Bool
    ) -> SumiContentBlockingCompilationFailure {
        guard !isStopped,
              request.generation == compilationGeneration,
              request.policy == currentPolicy
        else { return .stale }

        if let previousPolicy = request.previousPolicy, hasPublishedRules {
            currentPolicy = previousPolicy
            return .restore(previousPolicy)
        }
        currentPolicy = .disabled
        return .disable
    }

    func stop() -> Bool {
        guard !isStopped else { return false }
        isStopped = true
        compilationGeneration += 1
        return true
    }

    private func beginCompilation(
        for policy: SumiContentBlockingPolicy,
        previousPolicy: SumiContentBlockingPolicy?
    ) -> SumiContentBlockingCompilationRequest {
        compilationGeneration += 1
        return SumiContentBlockingCompilationRequest(
            generation: compilationGeneration,
            policy: policy,
            previousPolicy: previousPolicy
        )
    }
}
