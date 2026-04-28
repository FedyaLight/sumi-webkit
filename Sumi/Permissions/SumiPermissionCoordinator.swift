import Foundation

actor SumiPermissionCoordinator {
    typealias NowProvider = @Sendable () -> Date

    private struct PolicyEvaluation: Sendable {
        let permissionType: SumiPermissionType
        let context: SumiPermissionSecurityContext
        let result: SumiPermissionPolicyResult
        let key: SumiPermissionKey
    }

    private struct PendingQuery: Sendable {
        let query: SumiPermissionAuthorizationQuery
        let primaryRequestId: String
        let tabId: String?
        var requestIds: Set<String>
        let keys: [SumiPermissionKey]
        let policyResults: [SumiPermissionPolicyResult]
    }

    private let policyResolver: any SumiPermissionPolicyResolver
    private let memoryStore: InMemoryPermissionStore
    private let persistentStore: (any SumiPermissionStore)?
    private let queue: SumiPermissionQueue
    private let sessionOwnerId: String?
    private let nowProvider: NowProvider

    private var state = SumiPermissionCoordinatorState()
    private var eventContinuations: [UUID: AsyncStream<SumiPermissionCoordinatorEvent>.Continuation] = [:]
    private var continuationByRequestId: [String: CheckedContinuation<SumiPermissionCoordinatorDecision, Never>] = [:]
    private var queryById: [String: PendingQuery] = [:]
    private var queryIdByRequestId: [String: String] = [:]

    init(
        policyResolver: any SumiPermissionPolicyResolver,
        memoryStore: InMemoryPermissionStore = InMemoryPermissionStore(),
        persistentStore: (any SumiPermissionStore)?,
        queue: SumiPermissionQueue = SumiPermissionQueue(),
        sessionOwnerId: String? = nil,
        now: @escaping NowProvider = Date.init
    ) {
        self.policyResolver = policyResolver
        self.memoryStore = memoryStore
        self.persistentStore = persistentStore
        self.queue = queue
        self.sessionOwnerId = Self.normalizedOptionalId(sessionOwnerId)
        self.nowProvider = now
    }

    func requestPermission(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        guard let concreteTypes = concretePermissionTypes(from: context.request.permissionTypes) else {
            let result = await policyResolver.evaluate(context)
            let decision = SumiPermissionCoordinatorDecision.fromPolicyResult(result, context: context)
            emitPolicyEventIfNeeded(decision)
            return decision
        }

        var evaluations: [PolicyEvaluation] = []
        evaluations.reserveCapacity(concreteTypes.count)
        for permissionType in concreteTypes {
            let concreteContext = context.replacingPermissionTypes([permissionType])
            let result = await policyResolver.evaluate(concreteContext)
            let key = permissionKey(for: permissionType, context: concreteContext)
            guard result.isAllowedToProceed else {
                let decision = SumiPermissionCoordinatorDecision.fromPolicyResult(
                    result,
                    context: concreteContext,
                    permissionTypes: [permissionType]
                )
                emitPolicyEventIfNeeded(decision)
                return decision
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
            return deniedDecision
        }
        if lookup.promptEvaluations.isEmpty {
            return aggregateGrantedDecision(
                lookup.grantedRecords,
                evaluations: evaluations,
                context: context
            )
        }

        return await enqueueAuthorizationQuery(
            originalContext: context,
            promptEvaluations: lookup.promptEvaluations
        )
    }

    func queryPermissionState(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        guard let concreteTypes = concretePermissionTypes(from: context.request.permissionTypes) else {
            let result = await policyResolver.evaluate(context)
            let decision = SumiPermissionCoordinatorDecision.fromPolicyResult(result, context: context)
            emitPolicyEventIfNeeded(decision)
            return decision
        }

        var evaluations: [PolicyEvaluation] = []
        evaluations.reserveCapacity(concreteTypes.count)
        for permissionType in concreteTypes {
            let concreteContext = context.replacingPermissionTypes([permissionType])
            let result = await policyResolver.evaluate(concreteContext)
            let key = permissionKey(for: permissionType, context: concreteContext)
            guard result.isAllowedToProceed else {
                let decision = SumiPermissionCoordinatorDecision.fromPolicyResult(
                    result,
                    context: concreteContext,
                    permissionTypes: [permissionType]
                )
                emitPolicyEventIfNeeded(decision)
                return decision
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
            return deniedDecision
        }
        if lookup.promptEvaluations.isEmpty {
            return aggregateGrantedDecision(
                lookup.grantedRecords,
                evaluations: evaluations,
                context: context
            )
        }

        return promptRequiredDecision(
            originalContext: context,
            promptEvaluations: lookup.promptEvaluations,
            reason: "permission-state-query-prompt-required"
        )
    }

    func stateSnapshot() -> SumiPermissionCoordinatorState {
        state
    }

    func activeQuery(forPageId pageId: String) -> SumiPermissionAuthorizationQuery? {
        state.activeQueriesByPageId[Self.normalizedPageId(pageId)]
    }

    func query(id queryId: String) -> SumiPermissionAuthorizationQuery? {
        queryById[queryId]?.query
    }

    func siteDecisionRecords(
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) async throws -> [SumiPermissionStoreRecord] {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        if isEphemeralProfile {
            return try await memoryStore.listDecisions(
                profilePartitionId: profileId,
                includingPersistences: [.session]
            )
        }
        guard let persistentStore else {
            return []
        }
        return try await persistentStore.listDecisions(profilePartitionId: profileId)
    }

    func transientDecisionRecords(
        profilePartitionId: String,
        pageId: String
    ) async throws -> [SumiPermissionStoreRecord] {
        try await memoryStore.listOneTimeDecisions(
            profilePartitionId: profilePartitionId,
            pageId: pageId
        )
    }

    func setSiteDecision(
        for key: SumiPermissionKey,
        state: SumiPermissionState,
        source: SumiPermissionDecisionSource = .user,
        reason: String? = nil
    ) async throws {
        guard key.permissionType.canBePersisted else {
            throw SumiPermissionSiteDecisionError.unsupportedPermission(key.permissionType.identity)
        }

        let now = nowProvider()
        let persistence: SumiPermissionPersistence = key.isEphemeralProfile ? .session : .persistent
        let decision = SumiPermissionDecision(
            state: state,
            persistence: persistence,
            source: source,
            reason: reason,
            createdAt: now,
            updatedAt: now
        )

        if key.isEphemeralProfile {
            try await memoryStore.setDecision(
                for: key,
                decision: decision,
                sessionOwnerId: sessionOwnerId
            )
            return
        }

        guard let persistentStore else {
            throw SumiPermissionSiteDecisionError.persistentStoreUnavailable
        }
        try await persistentStore.setDecision(for: key, decision: decision)
    }

    func resetSiteDecision(
        for key: SumiPermissionKey
    ) async throws {
        try await memoryStore.resetDecision(for: key, sessionOwnerId: sessionOwnerId)
        guard !key.isEphemeralProfile else { return }
        try await persistentStore?.resetDecision(for: key)
    }

    func resetSiteDecisions(
        for keys: [SumiPermissionKey]
    ) async throws {
        for key in keys {
            try await resetSiteDecision(for: key)
        }
    }

    @discardableResult
    func resetTransientDecisions(
        profilePartitionId: String,
        pageId: String?,
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin,
        reason: String = "transient-decisions-reset"
    ) async -> Int {
        _ = reason
        return await memoryStore.clearTransientDecisions(
            profilePartitionId: profilePartitionId,
            pageId: pageId,
            requestingOrigin: requestingOrigin,
            topOrigin: topOrigin
        )
    }

    func events() -> AsyncStream<SumiPermissionCoordinatorEvent> {
        let pair = AsyncStream<SumiPermissionCoordinatorEvent>.makeStream(
            of: SumiPermissionCoordinatorEvent.self,
            bufferingPolicy: .bufferingNewest(50)
        )
        let id = UUID()
        eventContinuations[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeEventContinuation(id)
            }
        }
        return pair.stream
    }

    @discardableResult
    func approveCurrentAttempt(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        await settle(queryId: queryId, with: .approveCurrentAttempt)
    }

    @discardableResult
    func approveOnce(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        await settle(queryId: queryId, with: .approveOnce)
    }

    @discardableResult
    func approveForSession(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        await settle(queryId: queryId, with: .approveForSession)
    }

    @discardableResult
    func approvePersistently(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        await settle(queryId: queryId, with: .approvePersistently)
    }

    @discardableResult
    func denyOnce(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        await settle(queryId: queryId, with: .denyOnce)
    }

    @discardableResult
    func denyForSession(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        await settle(queryId: queryId, with: .denyForSession)
    }

    @discardableResult
    func dismiss(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        await settle(queryId: queryId, with: .dismiss)
    }

    @discardableResult
    func denyPersistently(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        await settle(queryId: queryId, with: .denyPersistently)
    }

    @discardableResult
    func setAskPersistently(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        await settle(queryId: queryId, with: .setAskPersistently)
    }

    @discardableResult
    func cancel(queryId: String, reason: String = "query-cancelled") async -> SumiPermissionCoordinatorDecision {
        await settle(queryId: queryId, with: .cancel(reason: reason))
    }

    @discardableResult
    func expire(queryId: String, reason: String = "query-expired") async -> SumiPermissionCoordinatorDecision {
        await settle(queryId: queryId, with: .expire(reason: reason))
    }

    @discardableResult
    func cancel(requestId: String, reason: String = "request-cancelled") async -> SumiPermissionCoordinatorDecision {
        let cancellation = await queue.cancel(requestId: requestId)
        let decision = cancellationDecision(
            outcome: .cancelled,
            source: .cancelled,
            reason: reason,
            requestIds: cancellation.cancelledRequestIds
        )
        let affectedPageIds = pageIds(forRequestIds: cancellation.cancelledRequestIds)
        await resolveCancelledRequestIds(cancellation.cancelledRequestIds, decision: decision)
        await refreshState(afterPromotion: cancellation.promotedActive, affectedPageIds: affectedPageIds)
        emit(.requestCancelled(requestIds: cancellation.cancelledRequestIds, decision: decision))
        return decision
    }

    @discardableResult
    func cancel(pageId: String, reason: String = "page-cancelled") async -> SumiPermissionCoordinatorDecision {
        await memoryStore.clearForPageId(pageId)
        let cancellation = await queue.cancel(pageId: pageId)
        let decision = cancellationDecision(
            outcome: .cancelled,
            source: .cancelled,
            reason: reason,
            requestIds: cancellation.cancelledRequestIds
        )
        await resolveCancelledRequestIds(cancellation.cancelledRequestIds, decision: decision)
        await refreshState(forPageId: pageId)
        emit(.pageCancelled(pageId: Self.normalizedPageId(pageId), decision: decision))
        return decision
    }

    @discardableResult
    func cancelNavigation(pageId: String, reason: String = "navigation-cancelled") async -> SumiPermissionCoordinatorDecision {
        await memoryStore.clearForNavigation(pageId: pageId)
        let cancellation = await queue.cancelNavigation(pageId: pageId)
        let decision = cancellationDecision(
            outcome: .cancelled,
            source: .cancelled,
            reason: reason,
            requestIds: cancellation.cancelledRequestIds
        )
        await resolveCancelledRequestIds(cancellation.cancelledRequestIds, decision: decision)
        await refreshState(forPageId: pageId)
        emit(.pageCancelled(pageId: Self.normalizedPageId(pageId), decision: decision))
        return decision
    }

    @discardableResult
    func cancelTab(tabId: String, reason: String = "tab-cancelled") async -> SumiPermissionCoordinatorDecision {
        let normalizedTabId = Self.normalizedOptionalId(tabId)
        if let normalizedTabId {
            await memoryStore.clearOneTimeDecisions(forTabId: normalizedTabId)
        }
        let matchingPrimaryIds = queryById.values
            .filter { $0.tabId == normalizedTabId }
            .map(\.primaryRequestId)
        return await cancelPrimaryRequestIds(
            matchingPrimaryIds,
            outcome: .cancelled,
            source: .cancelled,
            reason: reason
        )
    }

    @discardableResult
    func cancelProfile(
        profilePartitionId: String,
        reason: String = "profile-cancelled"
    ) async -> SumiPermissionCoordinatorDecision {
        let normalizedProfileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        await memoryStore.clearForProfile(profilePartitionId: normalizedProfileId)
        let matchingPrimaryIds = queryById.values
            .filter { $0.query.profilePartitionId == normalizedProfileId }
            .map(\.primaryRequestId)
        let decision = await cancelPrimaryRequestIds(
            matchingPrimaryIds,
            outcome: .cancelled,
            source: .cancelled,
            reason: reason
        )
        emit(.profileCancelled(profilePartitionId: normalizedProfileId, decision: decision))
        return decision
    }

    @discardableResult
    func cancelSession(
        ownerId: String,
        reason: String = "session-cancelled"
    ) async -> SumiPermissionCoordinatorDecision {
        let normalizedOwnerId = Self.normalizedOwnerId(ownerId)
        await memoryStore.clearForSession(ownerId: normalizedOwnerId)
        let matchingPrimaryIds: [String]
        if normalizedOwnerId == Self.normalizedOwnerId(sessionOwnerId ?? "") {
            matchingPrimaryIds = queryById.values.map(\.primaryRequestId)
        } else {
            matchingPrimaryIds = []
        }
        let decision = await cancelPrimaryRequestIds(
            matchingPrimaryIds,
            outcome: .cancelled,
            source: .cancelled,
            reason: reason
        )
        emit(.sessionCancelled(sessionOwnerId: normalizedOwnerId, decision: decision))
        return decision
    }

    private func storedDecisionLookup(
        for evaluations: [PolicyEvaluation]
    ) async -> (
        deniedDecision: SumiPermissionCoordinatorDecision?,
        grantedRecords: [SumiPermissionStoreRecord],
        promptEvaluations: [PolicyEvaluation]
    ) {
        var grantedRecords: [SumiPermissionStoreRecord] = []
        var promptEvaluations: [PolicyEvaluation] = []

        for evaluation in evaluations {
            if let memoryRecord = try? await memoryStore.getDecision(
                for: evaluation.key,
                sessionOwnerId: sessionOwnerId
            ) {
                switch memoryRecord.decision.state {
                case .allow:
                    try? await memoryStore.recordLastUsed(
                        for: evaluation.key,
                        at: nowProvider(),
                        sessionOwnerId: sessionOwnerId
                    )
                    grantedRecords.append(memoryRecord)
                    continue
                case .deny:
                    try? await memoryStore.recordLastUsed(
                        for: evaluation.key,
                        at: nowProvider(),
                        sessionOwnerId: sessionOwnerId
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
               let persistentStore,
               let persistentRecord = try? await persistentStore.getDecision(for: evaluation.key)
            {
                switch persistentRecord.decision.state {
                case .allow:
                    try? await persistentStore.recordLastUsed(
                        for: evaluation.key,
                        at: nowProvider()
                    )
                    grantedRecords.append(persistentRecord)
                case .deny:
                    try? await persistentStore.recordLastUsed(
                        for: evaluation.key,
                        at: nowProvider()
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
            shouldPersist: false,
            shouldOfferSystemSettings: false,
            disablesPersistentAllow: context.isEphemeralProfile
        )
    }

    private func enqueueAuthorizationQuery(
        originalContext: SumiPermissionSecurityContext,
        promptEvaluations: [PolicyEvaluation]
    ) async -> SumiPermissionCoordinatorDecision {
        let promptTypes = promptEvaluations.map(\.permissionType)
        let promptRequest = request(
            from: originalContext,
            permissionTypes: promptTypes
        )
        let enqueueResult = await queue.enqueue(promptRequest)
        let query = authorizationQuery(
            id: stableQueryId(for: promptRequest),
            request: promptRequest,
            originalContext: originalContext,
            promptEvaluations: promptEvaluations
        )

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                register(
                    continuation,
                    enqueueResult: enqueueResult,
                    query: query,
                    request: promptRequest,
                    promptEvaluations: promptEvaluations
                )
            }
        } onCancel: {
            Task {
                await self.cancel(requestId: promptRequest.id, reason: "task-cancelled")
            }
        }
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
            shouldPersist: false,
            shouldOfferSystemSettings: policyResults.contains(where: \.mayOpenSystemSettings),
            disablesPersistentAllow: originalContext.isEphemeralProfile
                || !allowedPersistences(for: policyResults).contains(.persistent)
        )
    }

    private func register(
        _ continuation: CheckedContinuation<SumiPermissionCoordinatorDecision, Never>,
        enqueueResult: SumiPermissionQueueEnqueueResult,
        query: SumiPermissionAuthorizationQuery,
        request: SumiPermissionRequest,
        promptEvaluations: [PolicyEvaluation]
    ) {
        switch enqueueResult {
        case .activated(let entry):
            storeNewPendingQuery(
                query: query,
                entry: entry,
                request: request,
                continuation: continuation,
                promptEvaluations: promptEvaluations
            )
            state.activeQueriesByPageId[query.pageId] = query
            state.queueCountByPageId[query.pageId] = 0
            emit(.queryActivated(query))
        case .queued(let entry, let position):
            storeNewPendingQuery(
                query: query,
                entry: entry,
                request: request,
                continuation: continuation,
                promptEvaluations: promptEvaluations
            )
            state.queueCountByPageId[query.pageId] = position
            emit(.queryQueued(query, position: position))
        case .coalesced(let existing):
            guard let existingQueryId = queryIdByRequestId[existing.request.id],
                  var pending = queryById[existingQueryId]
            else {
                continuation.resume(
                    returning: ignoredDecision(
                        reason: "coalesced-query-not-found",
                        permissionTypes: request.permissionTypes
                    )
                )
                return
            }
            pending.requestIds.insert(request.id)
            queryById[existingQueryId] = pending
            queryIdByRequestId[request.id] = existingQueryId
            continuationByRequestId[request.id] = continuation
            emit(.queryCoalesced(queryId: existingQueryId, requestId: request.id))
        }
    }

    private func storeNewPendingQuery(
        query: SumiPermissionAuthorizationQuery,
        entry: SumiPermissionQueueEntry,
        request: SumiPermissionRequest,
        continuation: CheckedContinuation<SumiPermissionCoordinatorDecision, Never>,
        promptEvaluations: [PolicyEvaluation]
    ) {
        let requestIds = Set(entry.allRequestIds)
        queryById[query.id] = PendingQuery(
            query: query,
            primaryRequestId: entry.request.id,
            tabId: request.tabId,
            requestIds: requestIds,
            keys: promptEvaluations.map(\.key),
            policyResults: promptEvaluations.map(\.result)
        )
        for requestId in requestIds {
            queryIdByRequestId[requestId] = query.id
        }
        continuationByRequestId[request.id] = continuation
    }

    private func settle(
        queryId: String,
        with userDecision: SumiPermissionUserDecision
    ) async -> SumiPermissionCoordinatorDecision {
        guard let pending = queryById[queryId] else {
            return ignoredDecision(reason: "query-not-found", permissionTypes: [])
        }
        guard state.activeQueriesByPageId[pending.query.pageId]?.id == queryId else {
            return ignoredDecision(
                reason: "query-not-active",
                permissionTypes: pending.query.permissionTypes
            )
        }

        let decision = coordinatorDecision(for: userDecision, pending: pending)
        await writeUserDecisionIfNeeded(userDecision, pending: pending, decision: decision)
        let continuations = takeContinuations(for: pending.requestIds)
        removePendingQuery(pending)
        let advance = await queue.finishActiveRequest(pageId: pending.query.pageId)
        await refreshState(forPageId: pending.query.pageId)
        if let promoted = advance.nextActive,
           let promotedQuery = queryById[queryIdByRequestId[promoted.request.id] ?? ""]?.query
        {
            emit(.queryPromoted(promotedQuery))
        }
        emit(.querySettled(queryId: queryId, decision: decision))
        resume(continuations, with: decision)
        return decision
    }

    private func coordinatorDecision(
        for userDecision: SumiPermissionUserDecision,
        pending: PendingQuery
    ) -> SumiPermissionCoordinatorDecision {
        let persistence = effectivePersistence(for: userDecision, query: pending.query)
        let outcome: SumiPermissionCoordinatorOutcome
        let state: SumiPermissionState?
        let source: SumiPermissionDecisionSource
        let reason: String
        let shouldPersist: Bool

        switch userDecision {
        case .approveCurrentAttempt:
            outcome = .granted
            state = .allow
            source = .user
            reason = "approved-current-attempt"
            shouldPersist = false
        case .approveOnce:
            outcome = .granted
            state = .allow
            source = .user
            reason = "approved-once"
            shouldPersist = false
        case .approveForSession:
            outcome = .granted
            state = .allow
            source = .user
            reason = persistence == .session ? "approved-for-session" : "approved-for-session-downgraded"
            shouldPersist = false
        case .approvePersistently:
            outcome = .granted
            state = .allow
            source = .user
            reason = persistence == .persistent ? "approved-persistently" : "approved-persistently-downgraded"
            shouldPersist = persistence == .persistent
        case .denyOnce:
            outcome = .denied
            state = .deny
            source = .user
            reason = "denied-once"
            shouldPersist = false
        case .denyForSession:
            outcome = .denied
            state = .deny
            source = .user
            reason = persistence == .session ? "denied-for-session" : "denied-for-session-downgraded"
            shouldPersist = false
        case .dismiss:
            outcome = .dismissed
            state = .ask
            source = .dismissed
            reason = "dismissed"
            shouldPersist = false
        case .denyPersistently:
            if persistence == .persistent {
                outcome = .denied
                state = .deny
                source = .user
                reason = "denied-persistently"
                shouldPersist = true
            } else {
                outcome = .ignored
                state = nil
                source = .runtime
                reason = "persistent-deny-unavailable"
                shouldPersist = false
            }
        case .setAskPersistently:
            if persistence == .persistent {
                outcome = .promptRequired
                state = .ask
                source = .user
                reason = "ask-persistently"
                shouldPersist = true
            } else {
                outcome = .ignored
                state = nil
                source = .runtime
                reason = "persistent-ask-unavailable"
                shouldPersist = false
            }
        case .cancel(let cancelReason):
            outcome = .cancelled
            state = nil
            source = .cancelled
            reason = cancelReason
            shouldPersist = false
        case .expire(let expireReason):
            outcome = .expired
            state = nil
            source = .runtime
            reason = expireReason
            shouldPersist = false
        }

        return SumiPermissionCoordinatorDecision(
            outcome: outcome,
            state: state,
            persistence: persistence,
            source: source,
            reason: reason,
            permissionTypes: pending.query.permissionTypes,
            keys: pending.keys,
            queryId: pending.query.id,
            systemAuthorizationSnapshot: pending.query.systemAuthorizationSnapshots.first,
            shouldPersist: shouldPersist,
            shouldOfferSystemSettings: pending.query.shouldOfferSystemSettings,
            disablesPersistentAllow: pending.query.disablesPersistentAllow
        )
    }

    private func writeUserDecisionIfNeeded(
        _ userDecision: SumiPermissionUserDecision,
        pending: PendingQuery,
        decision: SumiPermissionCoordinatorDecision
    ) async {
        guard let state = decision.state,
              let persistence = decision.persistence,
              decision.outcome != .ignored,
              decision.outcome != .dismissed,
              decision.outcome != .cancelled,
              decision.outcome != .expired
        else {
            return
        }

        let now = nowProvider()
        let storedDecision = SumiPermissionDecision(
            state: state,
            persistence: persistence,
            source: decision.source,
            reason: decision.reason,
            createdAt: now,
            updatedAt: now,
            systemAuthorizationSnapshot: encodedSnapshot(decision.systemAuthorizationSnapshot)
        )

        switch persistence {
        case .oneTime, .session:
            guard persistence != .oneTime || pending.keys.allSatisfy({ supportsReusableOneTimeGrant($0.permissionType) }) else {
                return
            }
            for key in pending.keys {
                try? await memoryStore.setDecision(
                    for: key,
                    decision: storedDecision,
                    sessionOwnerId: sessionOwnerId
                )
            }
        case .persistent:
            guard let persistentStore else { return }
            for key in pending.keys
                where !key.isEphemeralProfile && key.permissionType.canBePersisted
            {
                try? await persistentStore.setDecision(for: key, decision: storedDecision)
            }
        }

        _ = userDecision
    }

    private func supportsReusableOneTimeGrant(_ permissionType: SumiPermissionType) -> Bool {
        switch permissionType {
        case .camera, .microphone, .geolocation, .screenCapture:
            return true
        case .cameraAndMicrophone,
             .notifications,
             .popups,
             .externalScheme,
             .autoplay,
             .filePicker,
             .storageAccess:
            return false
        }
    }

    private func effectivePersistence(
        for userDecision: SumiPermissionUserDecision,
        query: SumiPermissionAuthorizationQuery
    ) -> SumiPermissionPersistence? {
        switch userDecision {
        case .approveCurrentAttempt:
            return nil
        case .approveOnce, .denyOnce:
            return .oneTime
        case .approveForSession, .denyForSession:
            return query.availablePersistences.contains(.session) ? .session : .oneTime
        case .approvePersistently:
            if query.availablePersistences.contains(.persistent), !query.isEphemeralProfile {
                return .persistent
            }
            if query.availablePersistences.contains(.session) {
                return .session
            }
            return .oneTime
        case .denyPersistently, .setAskPersistently:
            return query.availablePersistences.contains(.persistent) && !query.isEphemeralProfile
                ? .persistent
                : nil
        case .dismiss, .cancel, .expire:
            return nil
        }
    }

    private func cancelPrimaryRequestIds(
        _ requestIds: [String],
        outcome: SumiPermissionCoordinatorOutcome,
        source: SumiPermissionDecisionSource,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        var cancelledIds: [String] = []
        var affectedPageIds: Set<String> = []
        for requestId in requestIds {
            let cancellation = await queue.cancel(requestId: requestId)
            cancelledIds.append(contentsOf: cancellation.cancelledRequestIds)
            if let promotedPageId = cancellation.promotedActive?.request.pageBucketId {
                affectedPageIds.insert(promotedPageId)
            }
        }
        affectedPageIds.formUnion(pageIds(forRequestIds: cancelledIds))
        let decision = cancellationDecision(
            outcome: outcome,
            source: source,
            reason: reason,
            requestIds: cancelledIds
        )
        await resolveCancelledRequestIds(cancelledIds, decision: decision)
        for pageId in affectedPageIds {
            await refreshState(forPageId: pageId)
        }
        return decision
    }

    private func resolveCancelledRequestIds(
        _ requestIds: [String],
        decision: SumiPermissionCoordinatorDecision
    ) async {
        guard !requestIds.isEmpty else { return }
        var continuations: [CheckedContinuation<SumiPermissionCoordinatorDecision, Never>] = []
        var touchedQueryIds: Set<String> = []

        for requestId in requestIds {
            if let continuation = continuationByRequestId.removeValue(forKey: requestId) {
                continuations.append(continuation)
            }
            guard let queryId = queryIdByRequestId.removeValue(forKey: requestId),
                  var pending = queryById[queryId]
            else {
                continue
            }
            pending.requestIds.remove(requestId)
            touchedQueryIds.insert(queryId)
            if pending.requestIds.isEmpty {
                queryById.removeValue(forKey: queryId)
            } else {
                queryById[queryId] = pending
            }
        }

        for queryId in touchedQueryIds {
            guard queryById[queryId] == nil else { continue }
            if let pageId = state.activeQueriesByPageId.first(where: { $0.value.id == queryId })?.key {
                state.activeQueriesByPageId.removeValue(forKey: pageId)
            }
        }

        resume(continuations, with: decision)
    }

    private func takeContinuations(
        for requestIds: Set<String>
    ) -> [CheckedContinuation<SumiPermissionCoordinatorDecision, Never>] {
        var continuations: [CheckedContinuation<SumiPermissionCoordinatorDecision, Never>] = []
        for requestId in requestIds {
            if let continuation = continuationByRequestId.removeValue(forKey: requestId) {
                continuations.append(continuation)
            }
        }
        return continuations
    }

    private func removePendingQuery(_ pending: PendingQuery) {
        queryById.removeValue(forKey: pending.query.id)
        for requestId in pending.requestIds {
            queryIdByRequestId.removeValue(forKey: requestId)
        }
        state.activeQueriesByPageId.removeValue(forKey: pending.query.pageId)
    }

    private func resume(
        _ continuations: [CheckedContinuation<SumiPermissionCoordinatorDecision, Never>],
        with decision: SumiPermissionCoordinatorDecision
    ) {
        for continuation in continuations {
            continuation.resume(returning: decision)
        }
    }

    private func refreshState(
        afterPromotion promotedActive: SumiPermissionQueueEntry?,
        affectedPageIds: Set<String>
    ) async {
        var pageIds = affectedPageIds
        if let promotedActive {
            pageIds.insert(promotedActive.request.pageBucketId)
        }
        for pageId in pageIds {
            await refreshState(forPageId: pageId)
        }
    }

    private func refreshState(forPageId pageId: String) async {
        let normalizedPageId = Self.normalizedPageId(pageId)
        let snapshot = await queue.snapshot(forPageId: normalizedPageId)
        if let active = snapshot.active,
           let queryId = queryIdByRequestId[active.request.id],
           let query = queryById[queryId]?.query
        {
            state.activeQueriesByPageId[normalizedPageId] = query
        } else {
            state.activeQueriesByPageId.removeValue(forKey: normalizedPageId)
        }

        if snapshot.queued.isEmpty {
            state.queueCountByPageId.removeValue(forKey: normalizedPageId)
        } else {
            state.queueCountByPageId[normalizedPageId] = snapshot.queued.count
        }
    }

    private func pageIds(forRequestIds requestIds: [String]) -> Set<String> {
        var pageIds: Set<String> = []
        for requestId in requestIds {
            guard let queryId = queryIdByRequestId[requestId],
                  let query = queryById[queryId]?.query
            else {
                continue
            }
            pageIds.insert(query.pageId)
        }
        return pageIds
    }

    private func authorizationQuery(
        id: String,
        request: SumiPermissionRequest,
        originalContext: SumiPermissionSecurityContext,
        promptEvaluations: [PolicyEvaluation]
    ) -> SumiPermissionAuthorizationQuery {
        let policyResults = promptEvaluations.map(\.result)
        let allowedPersistences = allowedPersistences(for: policyResults)
        let systemSnapshots = policyResults.compactMap(\.systemAuthorizationSnapshot)
        return SumiPermissionAuthorizationQuery(
            id: id,
            pageId: request.pageBucketId,
            profilePartitionId: request.profilePartitionId,
            displayDomain: request.displayDomain,
            requestingOrigin: request.requestingOrigin,
            topOrigin: request.topOrigin,
            permissionTypes: request.permissionTypes,
            presentationPermissionType: presentationPermissionType(
                originalTypes: originalContext.request.permissionTypes,
                promptTypes: request.permissionTypes
            ),
            availablePersistences: allowedPersistences,
            defaultPersistence: defaultPersistence(from: allowedPersistences),
            systemAuthorizationSnapshots: systemSnapshots,
            policySources: policyResults.map(\.source),
            policyReasons: policyResults.map(\.reason),
            createdAt: nowProvider(),
            isEphemeralProfile: request.isEphemeralProfile,
            hasUserGesture: originalContext.hasUserGesture,
            shouldOfferSystemSettings: policyResults.contains(where: \.mayOpenSystemSettings),
            disablesPersistentAllow: request.isEphemeralProfile || !allowedPersistences.contains(.persistent),
            requiresSystemAuthorizationPrompt: policyResults.contains(where: \.requiresSystemAuthorizationPrompt)
        )
    }

    private func allowedPersistences(
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

    private func defaultPersistence(
        from allowedPersistences: Set<SumiPermissionPersistence>
    ) -> SumiPermissionPersistence {
        if allowedPersistences.contains(.oneTime) { return .oneTime }
        if allowedPersistences.contains(.session) { return .session }
        return .persistent
    }

    private func presentationPermissionType(
        originalTypes: [SumiPermissionType],
        promptTypes: [SumiPermissionType]
    ) -> SumiPermissionType? {
        Set(originalTypes) == Set([.camera, .microphone])
            && Set(promptTypes) == Set([.camera, .microphone])
            ? .cameraAndMicrophone
            : nil
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

    private func request(
        from context: SumiPermissionSecurityContext,
        permissionTypes: [SumiPermissionType]
    ) -> SumiPermissionRequest {
        SumiPermissionRequest(
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

    private func stableQueryId(for request: SumiPermissionRequest) -> String {
        [
            "permission-query",
            request.pageBucketId,
            request.queuePersistentIdentity,
        ].joined(separator: "|")
    }

    private func cancellationDecision(
        outcome: SumiPermissionCoordinatorOutcome,
        source: SumiPermissionDecisionSource,
        reason: String,
        requestIds: [String]
    ) -> SumiPermissionCoordinatorDecision {
        let queryIds = Set(requestIds.compactMap { queryIdByRequestId[$0] })
        let pendingQueries = queryIds.compactMap { queryById[$0] }
        return SumiPermissionCoordinatorDecision(
            outcome: outcome,
            state: nil,
            persistence: nil,
            source: source,
            reason: reason,
            permissionTypes: pendingQueries.flatMap { $0.query.permissionTypes },
            keys: pendingQueries.flatMap(\.keys),
            queryId: pendingQueries.first?.query.id,
            shouldPersist: false,
            shouldOfferSystemSettings: pendingQueries.contains { $0.query.shouldOfferSystemSettings },
            disablesPersistentAllow: pendingQueries.contains { $0.query.disablesPersistentAllow }
        )
    }

    private func ignoredDecision(
        reason: String,
        permissionTypes: [SumiPermissionType]
    ) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .ignored,
            state: nil,
            persistence: nil,
            source: .runtime,
            reason: reason,
            permissionTypes: permissionTypes
        )
    }

    private func emitPolicyEventIfNeeded(_ decision: SumiPermissionCoordinatorDecision) {
        guard decision.outcome == .systemBlocked else { return }
        emit(.systemBlocked(decision))
    }

    private func emit(_ event: SumiPermissionCoordinatorEvent) {
        state.latestEvent = event
        if case .systemBlocked = event {
            state.latestSystemBlockedEvent = event
        }
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func removeEventContinuation(_ id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }

    private func encodedSnapshot(_ snapshot: SumiSystemPermissionSnapshot?) -> String? {
        guard let snapshot,
              let data = try? JSONEncoder().encode(snapshot)
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func normalizedPageId(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "global" : trimmed
    }

    private static func normalizedOwnerId(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedOptionalId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension SumiPermissionSecurityContext {
    func replacingPermissionTypes(
        _ permissionTypes: [SumiPermissionType]
    ) -> SumiPermissionSecurityContext {
        let replacementRequest = SumiPermissionRequest(
            id: request.id,
            tabId: request.tabId,
            pageId: request.pageId,
            frameId: request.frameId,
            requestingOrigin: requestingOrigin,
            topOrigin: topOrigin,
            displayDomain: request.displayDomain,
            permissionTypes: permissionTypes,
            hasUserGesture: hasUserGesture ?? request.hasUserGesture,
            requestedAt: request.requestedAt,
            isEphemeralProfile: isEphemeralProfile,
            profilePartitionId: profilePartitionId
        )
        return SumiPermissionSecurityContext(
            request: replacementRequest,
            requestingOrigin: requestingOrigin,
            topOrigin: topOrigin,
            committedURL: committedURL,
            visibleURL: visibleURL,
            mainFrameURL: mainFrameURL,
            isMainFrame: isMainFrame,
            isActiveTab: isActiveTab,
            isVisibleTab: isVisibleTab,
            hasUserGesture: hasUserGesture,
            isEphemeralProfile: isEphemeralProfile,
            profilePartitionId: profilePartitionId,
            transientPageId: transientPageId,
            surface: surface,
            navigationOrPageGeneration: navigationOrPageGeneration,
            now: now
        )
    }
}
