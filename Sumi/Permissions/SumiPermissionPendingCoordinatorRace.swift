import Foundation

/// Races a coordinator permission request against a poll that detects a pending prompt-UI
/// query for the same page, failing closed after a timeout. Shared by the WebKit media,
/// geolocation, storage-access, and notification permission bridges.
enum SumiPermissionPendingCoordinatorRace {
    enum Outcome: Sendable {
        /// The prompt UI could be presented, so the coordinator was awaited directly.
        case immediate(SumiPermissionCoordinatorDecision)
        case coordinator(SumiPermissionCoordinatorDecision)
        case pendingStrategy(SumiPermissionCoordinatorDecision)
        case timeout(SumiPermissionCoordinatorDecision)

        var decision: SumiPermissionCoordinatorDecision {
            switch self {
            case .immediate(let decision),
                 .coordinator(let decision),
                 .pendingStrategy(let decision),
                 .timeout(let decision):
                return decision
            }
        }
    }

    static func resolve(
        coordinator: any SumiPermissionCoordinating,
        context: SumiPermissionSecurityContext,
        shouldWaitForPromptUI: Bool,
        pendingReason: String,
        timeoutReason: String,
        taskCancelledReason: String,
        noCoordinatorResultReason: String,
        pendingPollIntervalNanoseconds: UInt64,
        coordinatorTimeoutNanoseconds: UInt64,
        temporaryPendingDecision: @escaping @Sendable (
            SumiPermissionSecurityContext,
            String
        ) -> SumiPermissionCoordinatorDecision,
        failClosedDecision: @escaping @Sendable (
            SumiPermissionSecurityContext?,
            String
        ) -> SumiPermissionCoordinatorDecision
    ) async -> SumiPermissionCoordinatorDecision {
        await run(
            coordinator: coordinator,
            context: context,
            shouldWaitForPromptUI: shouldWaitForPromptUI,
            pendingReason: pendingReason,
            timeoutReason: timeoutReason,
            taskCancelledReason: taskCancelledReason,
            noCoordinatorResultReason: noCoordinatorResultReason,
            pendingPollIntervalNanoseconds: pendingPollIntervalNanoseconds,
            coordinatorTimeoutNanoseconds: coordinatorTimeoutNanoseconds,
            temporaryPendingDecision: temporaryPendingDecision,
            failClosedDecision: failClosedDecision
        ).decision
    }

    static func run(
        coordinator: any SumiPermissionCoordinating,
        context: SumiPermissionSecurityContext,
        shouldWaitForPromptUI: Bool,
        pendingReason: String,
        timeoutReason: String,
        taskCancelledReason: String,
        noCoordinatorResultReason: String,
        pendingPollIntervalNanoseconds: UInt64,
        coordinatorTimeoutNanoseconds: UInt64,
        temporaryPendingDecision: @escaping @Sendable (
            SumiPermissionSecurityContext,
            String
        ) -> SumiPermissionCoordinatorDecision,
        failClosedDecision: @escaping @Sendable (
            SumiPermissionSecurityContext?,
            String
        ) -> SumiPermissionCoordinatorDecision
    ) async -> Outcome {
        if shouldWaitForPromptUI,
           context.canPresentPromptUI {
            return .immediate(await coordinator.requestPermission(context))
        }

        let pageId = context.request.pageBucketId
        let requestId = context.request.id

        return await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                .coordinator(await coordinator.requestPermission(context))
            }
            group.addTask {
                var elapsed: UInt64 = 0
                while elapsed < coordinatorTimeoutNanoseconds {
                    let sleepNanoseconds = min(
                        pendingPollIntervalNanoseconds,
                        coordinatorTimeoutNanoseconds - elapsed
                    )
                    try? await Task.sleep(nanoseconds: sleepNanoseconds)
                    if Task.isCancelled {
                        return .timeout(
                            failClosedDecision(context, taskCancelledReason)
                        )
                    }
                    elapsed += sleepNanoseconds
                    if await coordinator.activeQuery(forPageId: pageId) != nil {
                        await coordinator.cancel(
                            requestId: requestId,
                            reason: pendingReason
                        )
                        return .pendingStrategy(
                            temporaryPendingDecision(context, pendingReason)
                        )
                    }
                }

                await coordinator.cancel(
                    requestId: requestId,
                    reason: timeoutReason
                )
                return .timeout(
                    failClosedDecision(context, timeoutReason)
                )
            }

            guard let result = await group.next() else {
                return .timeout(failClosedDecision(context, noCoordinatorResultReason))
            }
            group.cancelAll()
            return result
        }
    }
}
