import Foundation
import SumiDomain

actor SumiPermissionCoordinator {
    typealias NowProvider = @Sendable () -> Date
    private typealias DecisionContinuation = CheckedContinuation<SumiPermissionCoordinatorDecision, Never>
    private typealias PolicyEvaluation = SumiPermissionDecisionResolutionOwner.PolicyEvaluation

    private let memoryStore: InMemoryPermissionStore
    private let persistentStore: (any SumiPermissionStore)?
    private let decisionResolutionOwner: SumiPermissionDecisionResolutionOwner
    private let decisionSideEffectOwner: SumiPermissionDecisionSideEffectOwner
    private let siteDecisions: SumiPermissionSiteDecisionTransaction
    private let queue: SumiPermissionQueue
    private let settlementDecisionBuilder = SumiPermissionSettlementDecisionBuilder()
    private let authorizationQueryBuilder: SumiPermissionAuthorizationQueryBuilder
    private let eventPublisher: SumiPermissionEventPublisher
    private let sessionOwnerId: String?
    private let profileAdmission: SumiPermissionProfileAdmission

    private var state = SumiPermissionCoordinatorState()
    private var pendingQueryOwner = SumiPermissionPendingQueryOwner()

    init(
        policyResolver: any SumiPermissionPolicyResolver,
        memoryStore: InMemoryPermissionStore = InMemoryPermissionStore(),
        persistentStore: (any SumiPermissionStore)?,
        antiAbuseStore: (any SumiPermissionAntiAbuseStoring)? = nil,
        antiAbusePolicy: SumiPermissionAntiAbusePolicy = SumiPermissionAntiAbusePolicy(),
        queue: SumiPermissionQueue = SumiPermissionQueue(),
        sessionOwnerId: String? = nil,
        profileAdmission: SumiPermissionProfileAdmission = SumiPermissionProfileAdmission(),
        now: @escaping NowProvider = { Date() }
    ) {
        self.memoryStore = memoryStore
        self.persistentStore = persistentStore
        self.queue = queue
        self.sessionOwnerId = Self.normalizedOptionalId(sessionOwnerId)
        self.profileAdmission = profileAdmission
        self.authorizationQueryBuilder = SumiPermissionAuthorizationQueryBuilder(
            now: now
        )
        let decisionSideEffects = SumiPermissionDecisionSideEffectOwner(
            memoryStore: memoryStore,
            persistentStore: persistentStore,
            antiAbuseStore: antiAbuseStore,
            antiAbusePolicy: antiAbusePolicy,
            sessionOwnerId: Self.normalizedOptionalId(sessionOwnerId),
            now: now
        )
        self.decisionSideEffectOwner = decisionSideEffects
        self.siteDecisions = SumiPermissionSiteDecisionTransaction(
            memoryStore: memoryStore,
            persistentStore: persistentStore,
            sideEffects: decisionSideEffects,
            sessionOwnerID: Self.normalizedOptionalId(sessionOwnerId),
            now: now
        )
        let eventStream = SumiPermissionCoordinatorEventStream()
        self.eventPublisher = SumiPermissionEventPublisher(
            sideEffects: decisionSideEffects,
            events: eventStream
        )
        self.decisionResolutionOwner = SumiPermissionDecisionResolutionOwner(
            policyResolver: policyResolver,
            memoryStore: memoryStore,
            persistentStore: persistentStore,
            antiAbuseStore: antiAbuseStore,
            antiAbusePolicy: antiAbusePolicy,
            sessionOwnerId: Self.normalizedOptionalId(sessionOwnerId),
            now: now
        )
    }

    func requestPermission(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        guard let decision = await profileAdmission.withLease(
            profilePartitionId: context.profilePartitionId,
            operation: { await self.resolveRequestPermission(context) }
        ) else {
            return SumiPermissionRetiredProfileDecisionBuilder.make(for: context)
        }
        return decision
    }

    private func resolveRequestPermission(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        let resolution = await decisionResolutionOwner.resolveRequest(context)
        guard await isContextAdmitted(context) else {
            return SumiPermissionRetiredProfileDecisionBuilder.make(for: context)
        }
        switch resolution {
        case .immediate(let decision):
            await eventPublisher.publishIfNeeded(decision)
            return decision
        case .promptRequired(let promptEvaluations):
            return await enqueueAuthorizationQuery(
                originalContext: context,
                promptEvaluations: promptEvaluations
            )
        case .promptSuppressed(let suppression, let decision):
            await decisionSideEffectOwner.recordEvents(
                type: suppression.eventType,
                keys: decision.keys,
                reason: suppression.reason
            )
            emit(.promptSuppressed(suppression, decision: decision))
            return decision
        }
    }

    func queryPermissionState(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        guard let decision = await profileAdmission.withLease(
            profilePartitionId: context.profilePartitionId,
            operation: {
                let decision = await self.decisionResolutionOwner.resolveQuery(context)
                guard await self.isContextAdmitted(context) else {
                    return SumiPermissionRetiredProfileDecisionBuilder.make(
                        for: context
                    )
                }
                await self.eventPublisher.publishIfNeeded(decision)
                return decision
            }
        ) else {
            return SumiPermissionRetiredProfileDecisionBuilder.make(for: context)
        }
        return decision
    }

    func stateSnapshot() -> SumiPermissionCoordinatorState {
        var snapshot = state
        let eventSnapshot = eventPublisher.snapshot()
        snapshot.latestEvent = eventSnapshot.latestEvent
        snapshot.latestSystemBlockedEvent = eventSnapshot.latestSystemBlockedEvent
        snapshot.activeQueriesByPageId = pendingQueryOwner.activeQueriesByPageId
        snapshot.queueCountByPageId = pendingQueryOwner.queueCountsByPageId
        return snapshot
    }

    func activeQuery(forPageId pageId: String) -> SumiPermissionAuthorizationQuery? {
        pendingQueryOwner.activeQuery(forPageId: pageId)
    }

    func recordPromptShown(queryId: String) async {
        guard let pending = pendingQueryOwner.pending(queryId: queryId) else { return }
        _ = await profileAdmission.withLease(
            profilePartitionId: pending.query.profilePartitionId,
            operation: {
                await self.recordPromptShownAdmitted(queryId: queryId)
            }
        )
    }

    private func recordPromptShownAdmitted(queryId: String) async {
        guard let pending = pendingQueryOwner.pending(queryId: queryId) else {
            return
        }
        await decisionSideEffectOwner.recordEvents(
            type: .promptShown,
            keys: pending.keys,
            reason: "prompt-shown"
        )
    }

    func siteDecisionRecords(
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) async throws -> [SumiPermissionStoreRecord] {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        let memoryStore = memoryStore
        let persistentStore = persistentStore
        guard let records = try await profileAdmission.withLease(
            profilePartitionId: profileId,
            operation: {
                if isEphemeralProfile {
                    return try await memoryStore.listDecisions(
                        profilePartitionId: profileId,
                        includingPersistences: [.session]
                    )
                }
                guard let persistentStore else {
                    return []
                }
                return try await persistentStore.listDecisions(
                    profilePartitionId: profileId
                )
            }
        ) else {
            throw SumiPermissionSiteDecisionError.unavailable
        }
        return records
    }

    func transientDecisionRecords(
        profilePartitionId: String,
        pageId: String
    ) async throws -> [SumiPermissionStoreRecord] {
        let memoryStore = memoryStore
        guard let records = try await profileAdmission.withLease(
            profilePartitionId: profilePartitionId,
            operation: {
                try await memoryStore.listOneTimeDecisions(
                    profilePartitionId: profilePartitionId,
                    pageId: pageId
                )
            }
        ) else {
            throw SumiPermissionSiteDecisionError.unavailable
        }
        return records
    }

    func setSiteDecision(
        for key: SumiPermissionKey,
        state: SumiPermissionState,
        source: SumiPermissionDecisionSource = .user,
        reason: String? = nil
    ) async throws {
        let result: Void? = try await profileAdmission.withLease(
            profilePartitionId: key.profilePartitionId,
            operation: {
                try await self.siteDecisions.set(
                    state,
                    for: key,
                    source: source,
                    reason: reason
                )
            }
        )
        guard result != nil else {
            throw SumiPermissionSiteDecisionError.unavailable
        }
    }

    func resetSiteDecision(
        for key: SumiPermissionKey
    ) async throws {
        let result: Void? = try await profileAdmission.withLease(
            profilePartitionId: key.profilePartitionId,
            operation: {
                try await self.siteDecisions.reset(key)
            }
        )
        guard result != nil else {
            throw SumiPermissionSiteDecisionError.unavailable
        }
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
        let memoryStore = memoryStore
        return await profileAdmission.withLease(
            profilePartitionId: profilePartitionId,
            operation: {
                await memoryStore.clearTransientDecisions(
                    profilePartitionId: profilePartitionId,
                    pageId: pageId,
                    requestingOrigin: requestingOrigin,
                    topOrigin: topOrigin
                )
            }
        ) ?? 0
    }

    func events() async -> AsyncStream<SumiPermissionCoordinatorEvent> {
        eventPublisher.stream()
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
    func systemBlock(
        queryId: String,
        snapshots: [SumiSystemPermissionSnapshot],
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        guard let pending = pendingQueryOwner.pending(queryId: queryId) else {
            return ignoredDecision(reason: "query-not-found", permissionTypes: [])
        }
        let profilePartitionID = pending.query.profilePartitionId
        let requestIDs = Array(pending.requestIds)
        guard let decision = await profileAdmission.withLease(
            profilePartitionId: profilePartitionID,
            operation: {
                await self.systemBlockAdmitted(
                    queryId: queryId,
                    snapshots: snapshots,
                    reason: reason
                )
            }
        ) else {
            return cancellationDecision(
                outcome: .cancelled,
                source: .cancelled,
                reason: "profile-retired",
                requestIds: requestIDs
            )
        }
        return decision
    }

    private func systemBlockAdmitted(
        queryId: String,
        snapshots: [SumiSystemPermissionSnapshot],
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        guard let pending = pendingQueryOwner.pending(queryId: queryId) else {
            return ignoredDecision(reason: "query-not-found", permissionTypes: [])
        }
        guard pendingQueryOwner.isActive(queryId: queryId, pageId: pending.query.pageId) else {
            return ignoredDecision(
                reason: "query-not-active",
                permissionTypes: pending.query.permissionTypes
            )
        }

        let snapshot = snapshots.first ?? pending.query.systemAuthorizationSnapshots.first
        let decision = SumiPermissionCoordinatorDecision(
            outcome: .systemBlocked,
            state: .deny,
            persistence: nil,
            source: .system,
            reason: reason,
            permissionTypes: pending.query.permissionTypes,
            keys: pending.keys,
            queryId: pending.query.id,
            systemAuthorizationSnapshot: snapshot,
            shouldOfferSystemSettings: snapshots.contains { $0.shouldOpenSystemSettings }
                || pending.query.shouldOfferSystemSettings,
            disablesPersistentAllow: pending.query.disablesPersistentAllow
        )

        await decisionSideEffectOwner.recordEvents(
            type: .systemBlocked,
            keys: pending.keys,
            reason: reason
        )
        let continuations = pendingQueryOwner.resolveCompletedActiveQuery(pending)
        let advance = await queue.finishActiveRequest(pageId: pending.query.pageId)
        await refreshState(forPageId: pending.query.pageId)
        if let promotedQuery = pendingQueryOwner.promotedQuery(from: advance.nextActive) {
            emit(.queryPromoted(promotedQuery))
        }
        emit(.systemBlocked(decision))
        resume(continuations, with: decision)
        return decision
    }

    @discardableResult
    func cancel(queryId: String, reason: String = "query-cancelled") async -> SumiPermissionCoordinatorDecision {
        await settle(queryId: queryId, with: .cancel(reason: reason))
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
        await decisionSideEffectOwner.recordCancellation(decision)
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
        await decisionSideEffectOwner.recordCancellation(decision)
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
        await decisionSideEffectOwner.recordCancellation(decision)
        await resolveCancelledRequestIds(cancellation.cancelledRequestIds, decision: decision)
        await refreshState(forPageId: pageId)
        emit(.pageCancelled(pageId: Self.normalizedPageId(pageId), decision: decision))
        return decision
    }

    @discardableResult
    func cancelTab(tabId: String, reason: String = "tab-cancelled") async -> SumiPermissionCoordinatorDecision {
        let normalizedTabId = Self.normalizedOptionalId(tabId)
        if let normalizedTabId {
            _ = await memoryStore.clearOneTimeDecisions(forTabId: normalizedTabId)
        }
        let matchingPrimaryIds = pendingQueryOwner.primaryRequestIds { $0.tabId == normalizedTabId }
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
        let matchingPrimaryIds = pendingQueryOwner.primaryRequestIds {
            $0.query.profilePartitionId == normalizedProfileId
        }
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
    func retireProfile(
        profilePartitionId: String,
        reason: String = "profile-retired"
    ) async -> SumiPermissionCoordinatorDecision {
        let profileID = SumiPermissionKey.normalizedProfilePartitionId(
            profilePartitionId
        )
        await profileAdmission.seal(profilePartitionId: profileID)
        let decision = await cancelProfile(
            profilePartitionId: profileID,
            reason: reason
        )
        await profileAdmission.waitForDrain(profilePartitionId: profileID)
        return decision
    }

    func isProfileRetired(_ profilePartitionId: String) async -> Bool {
        await profileAdmission.isRetired(profilePartitionId)
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
            matchingPrimaryIds = pendingQueryOwner.primaryRequestIds { _ in true }
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

    private func enqueueAuthorizationQuery(
        originalContext: SumiPermissionSecurityContext,
        promptEvaluations: [PolicyEvaluation]
    ) async -> SumiPermissionCoordinatorDecision {
        guard await isContextAdmitted(originalContext) else {
            return SumiPermissionRetiredProfileDecisionBuilder.make(
                for: originalContext
            )
        }
        let promptTypes = promptEvaluations.map(\.permissionType)
        let promptRequest = authorizationQueryBuilder.request(
            from: originalContext,
            permissionTypes: promptTypes
        )
        let enqueueResult = await queue.enqueue(promptRequest)
        guard await isContextAdmitted(originalContext) else {
            _ = await queue.cancel(requestId: promptRequest.id)
            return SumiPermissionRetiredProfileDecisionBuilder.make(
                for: originalContext
            )
        }
        let query = authorizationQueryBuilder.authorizationQuery(
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

    private func isContextAdmitted(
        _ context: SumiPermissionSecurityContext
    ) async -> Bool {
        await profileAdmission.isRetired(context.profilePartitionId) == false
    }

    private func register(
        _ continuation: CheckedContinuation<SumiPermissionCoordinatorDecision, Never>,
        enqueueResult: SumiPermissionQueueEnqueueResult,
        query: SumiPermissionAuthorizationQuery,
        request: SumiPermissionRequest,
        promptEvaluations: [PolicyEvaluation]
    ) {
        let registration = pendingQueryOwner.register(
            continuation,
            enqueueResult: enqueueResult,
            query: query,
            request: request,
            keys: promptEvaluations.map(\.key)
        )
        switch registration {
        case .activated(let query):
            emit(.queryActivated(query))
        case .queued(let query, let position):
            emit(.queryQueued(query, position: position))
        case .coalesced(let queryId, let requestId):
            emit(.queryCoalesced(queryId: queryId, requestId: requestId))
        case .coalescedQueryMissing(let continuation, let permissionTypes):
            continuation.resume(
                returning: ignoredDecision(
                    reason: "coalesced-query-not-found",
                    permissionTypes: permissionTypes
                )
            )
        }
    }

    private func settle(
        queryId: String,
        with userDecision: SumiPermissionUserDecision
    ) async -> SumiPermissionCoordinatorDecision {
        guard let pending = pendingQueryOwner.pending(queryId: queryId) else {
            return ignoredDecision(reason: "query-not-found", permissionTypes: [])
        }
        let requestIDs = Array(pending.requestIds)
        guard let decision = await profileAdmission.withLease(
            profilePartitionId: pending.query.profilePartitionId,
            operation: {
                await self.settleAdmitted(
                    queryId: queryId,
                    with: userDecision
                )
            }
        ) else {
            return cancellationDecision(
                outcome: .cancelled,
                source: .cancelled,
                reason: "profile-retired",
                requestIds: requestIDs
            )
        }
        return decision
    }

    private func settleAdmitted(
        queryId: String,
        with userDecision: SumiPermissionUserDecision
    ) async -> SumiPermissionCoordinatorDecision {
        guard let pending = pendingQueryOwner.pending(queryId: queryId) else {
            return ignoredDecision(reason: "query-not-found", permissionTypes: [])
        }
        guard pendingQueryOwner.isActive(queryId: queryId, pageId: pending.query.pageId) else {
            return ignoredDecision(
                reason: "query-not-active",
                permissionTypes: pending.query.permissionTypes
            )
        }

        let decision = settlementDecisionBuilder.decision(for: userDecision, pending: pending)
        await decisionSideEffectOwner.recordSettlement(userDecision, pending: pending, decision: decision)
        await decisionSideEffectOwner.writeUserDecisionIfNeeded(pending: pending, decision: decision)
        let continuations = pendingQueryOwner.resolveCompletedActiveQuery(pending)
        let advance = await queue.finishActiveRequest(pageId: pending.query.pageId)
        await refreshState(forPageId: pending.query.pageId)
        if let promotedQuery = pendingQueryOwner.promotedQuery(from: advance.nextActive) {
            emit(.queryPromoted(promotedQuery))
        }
        emit(.querySettled(queryId: queryId, decision: decision))
        resume(continuations, with: decision)
        return decision
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
        await decisionSideEffectOwner.recordCancellation(decision)
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
        let continuations = pendingQueryOwner.resolveCancelledRequestIds(requestIds)
        resume(continuations, with: decision)
    }

    private func resume(
        _ continuations: [DecisionContinuation],
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
        pendingQueryOwner.refreshActiveQuery(pageId: normalizedPageId, snapshot: snapshot)
    }

    private func pageIds(forRequestIds requestIds: [String]) -> Set<String> {
        pendingQueryOwner.pageIds(forRequestIds: requestIds)
    }

    private func cancellationDecision(
        outcome: SumiPermissionCoordinatorOutcome,
        source: SumiPermissionDecisionSource,
        reason: String,
        requestIds: [String]
    ) -> SumiPermissionCoordinatorDecision {
        let pendingQueries = pendingQueryOwner.pendingQueries(forRequestIds: requestIds)
        return SumiPermissionCoordinatorDecision(
            outcome: outcome,
            state: nil,
            persistence: nil,
            source: source,
            reason: reason,
            permissionTypes: pendingQueries.flatMap { $0.query.permissionTypes },
            keys: pendingQueries.flatMap(\.keys),
            queryId: pendingQueries.first?.query.id,
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

    private func emit(_ event: SumiPermissionCoordinatorEvent) {
        eventPublisher.emit(event)
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
