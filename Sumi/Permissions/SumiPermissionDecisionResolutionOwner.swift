import Foundation
import OSLog

struct SumiPermissionDecisionResolutionOwner {
    typealias NowProvider = @Sendable () -> Date

    struct PolicyEvaluation: Sendable {
        let permissionType: SumiPermissionType
        let context: SumiPermissionSecurityContext
        let result: SumiPermissionPolicyResult
        let key: SumiPermissionKey
    }

    private typealias StoredDecisionLookupResult = (
        deniedDecision: SumiPermissionCoordinatorDecision?,
        grantedRecords: [SumiPermissionStoreRecord],
        promptEvaluations: [PolicyEvaluation]
    )

    enum Resolution {
        case immediate(SumiPermissionCoordinatorDecision)
        case promptRequired([PolicyEvaluation])
        case promptSuppressed(SumiPermissionPromptSuppression, decision: SumiPermissionCoordinatorDecision)
    }

    private enum PrePromptResolution {
        case immediate(SumiPermissionCoordinatorDecision)
        case promptRequired([PolicyEvaluation])
    }

    private enum StoreFailure: String, Sendable {
        case memoryRead = "permission-memory-store-read-failed"
        case memoryRecordLastUsed = "permission-memory-store-record-last-used-failed"
        case persistentRead = "permission-persistent-store-read-failed"
        case persistentRecordLastUsed = "permission-persistent-store-record-last-used-failed"
    }

    private static let logger = RuntimeDiagnostics.logger(category: "Permissions")

    private let policyResolver: any SumiPermissionPolicyResolver
    private let memoryStore: InMemoryPermissionStore
    private let persistentStore: (any SumiPermissionStore)?
    private let antiAbuseStore: (any SumiPermissionAntiAbuseStoring)?
    private let antiAbusePolicy: SumiPermissionAntiAbusePolicy
    private let sessionOwnerId: String?
    private let nowProvider: NowProvider

    init(
        policyResolver: any SumiPermissionPolicyResolver,
        memoryStore: InMemoryPermissionStore,
        persistentStore: (any SumiPermissionStore)?,
        antiAbuseStore: (any SumiPermissionAntiAbuseStoring)?,
        antiAbusePolicy: SumiPermissionAntiAbusePolicy,
        sessionOwnerId: String?,
        now: @escaping NowProvider
    ) {
        self.policyResolver = policyResolver
        self.memoryStore = memoryStore
        self.persistentStore = persistentStore
        self.antiAbuseStore = antiAbuseStore
        self.antiAbusePolicy = antiAbusePolicy
        self.sessionOwnerId = sessionOwnerId
        self.nowProvider = now
    }

    func resolveRequest(
        _ context: SumiPermissionSecurityContext
    ) async -> Resolution {
        let prePrompt = await resolvePrePrompt(context)
        if case .promptRequired(let promptEvaluations) = prePrompt,
           let suppressedDecision = await promptSuppressedDecision(
            originalContext: context,
            promptEvaluations: promptEvaluations
           ) {
            return .promptSuppressed(
                suppressedDecision.suppression,
                decision: suppressedDecision.decision
            )
        }
        switch prePrompt {
        case .immediate(let decision):
            return .immediate(decision)
        case .promptRequired(let promptEvaluations):
            return .promptRequired(promptEvaluations)
        }
    }

    func resolveQuery(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        switch await resolvePrePrompt(context) {
        case .immediate(let decision):
            return decision
        case .promptRequired(let promptEvaluations):
            return promptRequiredDecision(
                originalContext: context,
                promptEvaluations: promptEvaluations,
                reason: "permission-state-query-prompt-required"
            )
        }
    }

    static func allowedPersistences(
        for policyResults: [SumiPermissionPolicyResult]
    ) -> Set<SumiPermissionPersistence> {
        var allowed: Set<SumiPermissionPersistence>?
        for policyResult in policyResults {
            if var current = allowed {
                current.formIntersection(policyResult.allowedPersistences)
                allowed = current
            } else {
                allowed = policyResult.allowedPersistences
            }
        }
        return allowed ?? [.oneTime]
    }

    private func resolvePrePrompt(
        _ context: SumiPermissionSecurityContext
    ) async -> PrePromptResolution {
        guard let concreteTypes = concretePermissionTypes(from: context.request.permissionTypes) else {
            let result = await policyResolver.evaluate(context)
            return .immediate(SumiPermissionCoordinatorDecision.fromPolicyResult(result, context: context))
        }

        var evaluations: [PolicyEvaluation] = []
        evaluations.reserveCapacity(concreteTypes.count)
        for permissionType in concreteTypes {
            let concreteContext = replacingPermissionTypes([permissionType], in: context)
            let result = await policyResolver.evaluate(concreteContext)
            let key = permissionKey(for: permissionType, context: concreteContext)
            guard result.isAllowedToProceed else {
                return .immediate(
                    SumiPermissionCoordinatorDecision.fromPolicyResult(
                        result,
                        context: concreteContext,
                        permissionTypes: [permissionType]
                    )
                )
            }
            evaluations.append(
                PolicyEvaluation(
                    permissionType: permissionType,
                    context: concreteContext,
                    result: result,
                    key: key
                )
            )
        }

        let lookup = await storedDecisionLookup(for: evaluations)
        if let deniedDecision = lookup.deniedDecision {
            return .immediate(deniedDecision)
        }
        if lookup.promptEvaluations.isEmpty {
            return .immediate(
                aggregateGrantedDecision(
                    lookup.grantedRecords,
                    evaluations: evaluations,
                    context: context
                )
            )
        }

        return .promptRequired(lookup.promptEvaluations)
    }

    private func storedDecisionLookup(
        for evaluations: [PolicyEvaluation]
    ) async -> StoredDecisionLookupResult {
        var grantedRecords: [SumiPermissionStoreRecord] = []
        var promptEvaluations: [PolicyEvaluation] = []

        for evaluation in evaluations {
            let memoryRecord: SumiPermissionStoreRecord?
            do {
                memoryRecord = try await memoryStore.getDecision(
                    for: evaluation.key,
                    sessionOwnerId: sessionOwnerId
                )
            } catch {
                return storeFailureLookupResult(
                    .memoryRead,
                    error: error,
                    evaluation: evaluation,
                    grantedRecords: grantedRecords
                )
            }

            if let memoryRecord {
                switch memoryRecord.decision.state {
                case .allow:
                    await recordMemoryLastUsed(
                        for: evaluation,
                        failure: .memoryRecordLastUsed
                    )
                    grantedRecords.append(memoryRecord)
                    continue
                case .deny:
                    await recordMemoryLastUsed(
                        for: evaluation,
                        failure: .memoryRecordLastUsed
                    )
                    return (
                        SumiPermissionCoordinatorDecision.fromStoredDecision(
                            memoryRecord.decision,
                            key: evaluation.key,
                            reason: "stored-memory-deny"
                        ),
                        grantedRecords,
                        []
                    )
                case .ask:
                    promptEvaluations.append(evaluation)
                    continue
                }
            }

            if !evaluation.context.isEphemeralProfile,
               evaluation.key.permissionType.canBePersisted,
               let persistentStore {
                let persistentRecord: SumiPermissionStoreRecord?
                do {
                    persistentRecord = try await persistentStore.getDecision(for: evaluation.key)
                } catch {
                    return storeFailureLookupResult(
                        .persistentRead,
                        error: error,
                        evaluation: evaluation,
                        grantedRecords: grantedRecords
                    )
                }

                guard let persistentRecord else {
                    promptEvaluations.append(evaluation)
                    continue
                }

                switch persistentRecord.decision.state {
                case .allow:
                    await recordPersistentLastUsed(
                        persistentStore,
                        for: evaluation,
                        failure: .persistentRecordLastUsed
                    )
                    grantedRecords.append(persistentRecord)
                case .deny:
                    await recordPersistentLastUsed(
                        persistentStore,
                        for: evaluation,
                        failure: .persistentRecordLastUsed
                    )
                    return (
                        SumiPermissionCoordinatorDecision.fromStoredDecision(
                            persistentRecord.decision,
                            key: evaluation.key,
                            reason: "stored-persistent-deny"
                        ),
                        grantedRecords,
                        []
                    )
                case .ask:
                    promptEvaluations.append(evaluation)
                }
            } else {
                promptEvaluations.append(evaluation)
            }
        }

        return (nil, grantedRecords, promptEvaluations)
    }

    private func recordMemoryLastUsed(
        for evaluation: PolicyEvaluation,
        failure: StoreFailure
    ) async {
        do {
            try await memoryStore.recordLastUsed(
                for: evaluation.key,
                at: nowProvider(),
                sessionOwnerId: sessionOwnerId
            )
        } catch {
            logStoreFailure(failure, evaluation: evaluation, error: error)
        }
    }

    private func recordPersistentLastUsed(
        _ persistentStore: any SumiPermissionStore,
        for evaluation: PolicyEvaluation,
        failure: StoreFailure
    ) async {
        do {
            try await persistentStore.recordLastUsed(
                for: evaluation.key,
                at: nowProvider()
            )
        } catch {
            logStoreFailure(failure, evaluation: evaluation, error: error)
        }
    }

    private func storeFailureLookupResult(
        _ failure: StoreFailure,
        error: any Error,
        evaluation: PolicyEvaluation,
        grantedRecords: [SumiPermissionStoreRecord]
    ) -> StoredDecisionLookupResult {
        logStoreFailure(failure, evaluation: evaluation, error: error)
        return (
            storeFailureDecision(for: evaluation, failure: failure),
            grantedRecords,
            []
        )
    }

    private func logStoreFailure(
        _ failure: StoreFailure,
        evaluation: PolicyEvaluation,
        error: any Error
    ) {
        Self.logger.error(
            "Permission decision store failure \(failure.rawValue, privacy: .public) permission=\(evaluation.key.permissionType.identity, privacy: .public) domain=\(evaluation.key.displayDomain, privacy: .private) error=\(error.localizedDescription, privacy: .public)"
        )
    }

    private func storeFailureDecision(
        for evaluation: PolicyEvaluation,
        failure: StoreFailure
    ) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .denied,
            state: .deny,
            persistence: nil,
            source: .runtime,
            reason: failure.rawValue,
            permissionTypes: [evaluation.permissionType],
            keys: [evaluation.key],
            systemAuthorizationSnapshot: evaluation.result.systemAuthorizationSnapshot,
            shouldOfferSystemSettings: evaluation.result.mayOpenSystemSettings,
            disablesPersistentAllow: evaluation.context.isEphemeralProfile
        )
    }

    private func aggregateGrantedDecision(
        _ records: [SumiPermissionStoreRecord],
        evaluations: [PolicyEvaluation],
        context: SumiPermissionSecurityContext
    ) -> SumiPermissionCoordinatorDecision {
        let firstDecision = records.first?.decision
        let currentSystemSnapshot = evaluations
            .compactMap(\.result.systemAuthorizationSnapshot)
            .first
        return SumiPermissionCoordinatorDecision(
            outcome: .granted,
            state: .allow,
            persistence: firstDecision?.persistence,
            source: firstDecision?.source ?? .user,
            reason: "stored-allow",
            permissionTypes: evaluations.map(\.permissionType),
            keys: evaluations.map(\.key),
            systemAuthorizationSnapshot: currentSystemSnapshot ?? firstDecision.flatMap {
                SumiPermissionCoordinatorDecision.decodedSnapshot($0.systemAuthorizationSnapshot)
            },
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: context.isEphemeralProfile
        )
    }

    private func promptSuppressedDecision(
        originalContext: SumiPermissionSecurityContext,
        promptEvaluations: [PolicyEvaluation]
    ) async -> (suppression: SumiPermissionPromptSuppression, decision: SumiPermissionCoordinatorDecision)? {
        guard let antiAbuseStore else { return nil }
        let now = nowProvider()
        for evaluation in promptEvaluations {
            let events = await antiAbuseStore.events(for: evaluation.key, now: now)
            guard let suppression = antiAbusePolicy.suppression(
                for: evaluation.key,
                events: events,
                now: now
            ) else {
                continue
            }
            let decision = SumiPermissionCoordinatorDecision(
                outcome: .suppressed,
                state: .ask,
                persistence: nil,
                source: suppression.decisionSource,
                reason: suppression.reason,
                permissionTypes: promptEvaluations.map(\.permissionType),
                keys: promptEvaluations.map(\.key),
                systemAuthorizationSnapshot: promptEvaluations
                    .compactMap(\.result.systemAuthorizationSnapshot)
                    .first,
                shouldOfferSystemSettings: false,
                disablesPersistentAllow: originalContext.isEphemeralProfile,
                promptSuppression: suppression
            )
            return (suppression, decision)
        }
        return nil
    }

    private func promptRequiredDecision(
        originalContext: SumiPermissionSecurityContext,
        promptEvaluations: [PolicyEvaluation],
        reason: String
    ) -> SumiPermissionCoordinatorDecision {
        let policyResults = promptEvaluations.map(\.result)
        return SumiPermissionCoordinatorDecision(
            outcome: .promptRequired,
            state: .ask,
            persistence: nil,
            source: policyResults.first?.source ?? .defaultSetting,
            reason: reason,
            permissionTypes: promptEvaluations.map(\.permissionType),
            keys: promptEvaluations.map(\.key),
            queryId: nil,
            systemAuthorizationSnapshot: policyResults.compactMap(\.systemAuthorizationSnapshot).first,
            shouldOfferSystemSettings: policyResults.contains(where: \.mayOpenSystemSettings),
            disablesPersistentAllow: originalContext.isEphemeralProfile
                || !Self.allowedPersistences(for: policyResults).contains(.persistent)
        )
    }

    private func concretePermissionTypes(
        from permissionTypes: [SumiPermissionType]
    ) -> [SumiPermissionType]? {
        if Set(permissionTypes) == Set([.camera, .microphone]), permissionTypes.count == 2 {
            return [.camera, .microphone]
        }
        if Set(permissionTypes) == Set([.screenCapture, .microphone]), permissionTypes.count == 2 {
            return [.screenCapture, .microphone]
        }
        guard permissionTypes.count == 1,
              permissionTypes.first != .cameraAndMicrophone
        else {
            return nil
        }
        return permissionTypes
    }

    private func replacingPermissionTypes(
        _ permissionTypes: [SumiPermissionType],
        in context: SumiPermissionSecurityContext
    ) -> SumiPermissionSecurityContext {
        let replacementRequest = SumiPermissionRequest(
            id: context.request.id,
            tabId: context.request.tabId,
            pageId: context.request.pageId,
            frameId: context.request.frameId,
            requestingOrigin: context.requestingOrigin,
            topOrigin: context.topOrigin,
            displayDomain: context.request.displayDomain,
            permissionTypes: permissionTypes,
            hasUserGesture: context.hasUserGesture ?? context.request.hasUserGesture,
            requestedAt: context.request.requestedAt,
            isEphemeralProfile: context.isEphemeralProfile,
            profilePartitionId: context.profilePartitionId
        )
        return SumiPermissionSecurityContext(
            request: replacementRequest,
            requestingOrigin: context.requestingOrigin,
            topOrigin: context.topOrigin,
            committedURL: context.committedURL,
            visibleURL: context.visibleURL,
            mainFrameURL: context.mainFrameURL,
            isMainFrame: context.isMainFrame,
            isActiveTab: context.isActiveTab,
            isVisibleTab: context.isVisibleTab,
            hasUserGesture: context.hasUserGesture,
            isEphemeralProfile: context.isEphemeralProfile,
            profilePartitionId: context.profilePartitionId,
            transientPageId: context.transientPageId,
            surface: context.surface,
            navigationOrPageGeneration: context.navigationOrPageGeneration,
            now: context.now
        )
    }

    private func permissionKey(
        for permissionType: SumiPermissionType,
        context: SumiPermissionSecurityContext
    ) -> SumiPermissionKey {
        SumiPermissionKey(
            requestingOrigin: context.requestingOrigin,
            topOrigin: context.topOrigin,
            permissionType: permissionType,
            profilePartitionId: context.profilePartitionId,
            transientPageId: context.transientPageId,
            isEphemeralProfile: context.isEphemeralProfile
        )
    }
}
