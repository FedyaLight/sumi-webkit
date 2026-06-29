import Foundation

actor SumiPermissionCoordinator {
    typealias NowProvider = @Sendable () -> Date
    private typealias DecisionContinuation = CheckedContinuation<SumiPermissionCoordinatorDecision, Never>
    private typealias PendingQuery = SumiPendingAuthorizationQuery
    private typealias PolicyEvaluation = SumiPermissionDecisionResolutionOwner.PolicyEvaluation

    private let memoryStore: InMemoryPermissionStore
    private let persistentStore: (any SumiPermissionStore)?
    private let antiAbuseStore: (any SumiPermissionAntiAbuseStoring)?
    private let antiAbusePolicy: SumiPermissionAntiAbusePolicy
    private let decisionResolutionOwner: SumiPermissionDecisionResolutionOwner
    private let queue: SumiPermissionQueue
    private let settlementDecisionBuilder = SumiPermissionSettlementDecisionBuilder()
    private let sessionOwnerId: String?
    private let nowProvider: NowProvider

    private var state = SumiPermissionCoordinatorState()
    private var eventContinuations: [UUID: AsyncStream<SumiPermissionCoordinatorEvent>.Continuation] = [:]
    private var pendingQueryOwner = SumiPermissionPendingQueryOwner()

    init(
        policyResolver: any SumiPermissionPolicyResolver,
        memoryStore: InMemoryPermissionStore = InMemoryPermissionStore(),
        persistentStore: (any SumiPermissionStore)?,
        antiAbuseStore: (any SumiPermissionAntiAbuseStoring)? = nil,
        antiAbusePolicy: SumiPermissionAntiAbusePolicy = SumiPermissionAntiAbusePolicy(),
        queue: SumiPermissionQueue = SumiPermissionQueue(),
        sessionOwnerId: String? = nil,
        now: @escaping NowProvider = { Date() }
    ) {
        self.memoryStore = memoryStore
        self.persistentStore = persistentStore
        self.antiAbuseStore = antiAbuseStore
        self.antiAbusePolicy = antiAbusePolicy
        self.queue = queue
        self.sessionOwnerId = Self.normalizedOptionalId(sessionOwnerId)
        self.nowProvider = now
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
        switch await decisionResolutionOwner.resolveRequest(context) {
        case .immediate(let decision):
            await emitPolicyEventIfNeeded(decision)
            return decision
        case .promptRequired(let promptEvaluations):
            return await enqueueAuthorizationQuery(
                originalContext: context,
                promptEvaluations: promptEvaluations
            )
        case .promptSuppressed(let suppression, let decision):
            await recordAntiAbuseEvents(
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
        let decision = await decisionResolutionOwner.resolveQuery(context)
        await emitPolicyEventIfNeeded(decision)
        return decision
    }

    func stateSnapshot() -> SumiPermissionCoordinatorState {
        var snapshot = state
        snapshot.activeQueriesByPageId = pendingQueryOwner.activeQueriesByPageId
        snapshot.queueCountByPageId = pendingQueryOwner.queueCountsByPageId
        return snapshot
    }

    func activeQuery(forPageId pageId: String) -> SumiPermissionAuthorizationQuery? {
        pendingQueryOwner.activeQuery(forPageId: pageId)
    }

    func recordPromptShown(queryId: String) async {
        guard let pending = pendingQueryOwner.pending(queryId: queryId) else { return }
        await recordAntiAbuseEvents(
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
            await recordManualSiteDecisionAntiAbuse(state: state, key: key, reason: reason)
            return
        }

        guard let persistentStore else {
            throw SumiPermissionSiteDecisionError.persistentStoreUnavailable
        }
        try await persistentStore.setDecision(for: key, decision: decision)
        await recordManualSiteDecisionAntiAbuse(state: state, key: key, reason: reason)
    }

    func resetSiteDecision(
        for key: SumiPermissionKey
    ) async throws {
        try await memoryStore.resetDecision(for: key, sessionOwnerId: sessionOwnerId)
        await antiAbuseStore?.clearSuppressionState(for: key, now: nowProvider())
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

        await recordAntiAbuseEvents(
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
        await recordAntiAbuseCancellation(decision)
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
        await recordAntiAbuseCancellation(decision)
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
        await recordAntiAbuseCancellation(decision)
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
        guard pendingQueryOwner.isActive(queryId: queryId, pageId: pending.query.pageId) else {
            return ignoredDecision(
                reason: "query-not-active",
                permissionTypes: pending.query.permissionTypes
            )
        }

        let decision = settlementDecisionBuilder.decision(for: userDecision, pending: pending)
        await recordAntiAbuseSettlement(userDecision, pending: pending, decision: decision)
        await writeUserDecisionIfNeeded(userDecision, pending: pending, decision: decision)
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
            systemAuthorizationSnapshot: SumiSystemPermissionSnapshot.encodedJSONString(for: decision.systemAuthorizationSnapshot)
        )

        switch persistence {
        case .oneTime, .session:
            guard persistence != .oneTime || pending.keys.allSatisfy({ supportsReusableOneTimeGrant($0.permissionType) }) else {
                return
            }
            for key in pending.keys {
                do {
                    try await memoryStore.setDecision(
                        for: key,
                        decision: storedDecision,
                        sessionOwnerId: sessionOwnerId
                    )
                } catch {
                    RuntimeDiagnostics.emit(
                        "[Permissions] Failed to store transient permission decision for \(key.permissionType.identity): \(error.localizedDescription)"
                    )
                }
            }
        case .persistent:
            guard let persistentStore else { return }
            for key in pending.keys
                where !key.isEphemeralProfile && key.permissionType.canBePersisted {
                do {
                    try await persistentStore.setDecision(for: key, decision: storedDecision)
                } catch {
                    RuntimeDiagnostics.emit(
                        "[Permissions] Failed to persist permission decision for \(key.permissionType.identity): \(error.localizedDescription)"
                    )
                    await writeFallbackSessionDecisionIfAllowed(
                        storedDecision,
                        key: key,
                        query: pending.query
                    )
                }
            }
        }

        _ = userDecision
    }

    private func writeFallbackSessionDecisionIfAllowed(
        _ decision: SumiPermissionDecision,
        key: SumiPermissionKey,
        query: SumiPermissionAuthorizationQuery
    ) async {
        guard decision.state == .allow else { return }

        let fallbackPersistence: SumiPermissionPersistence
        if query.availablePersistences.contains(.session) {
            fallbackPersistence = .session
        } else if query.availablePersistences.contains(.oneTime),
                  supportsReusableOneTimeGrant(key.permissionType) {
            fallbackPersistence = .oneTime
        } else {
            return
        }

        let fallbackDecision = SumiPermissionDecision(
            state: decision.state,
            persistence: fallbackPersistence,
            source: decision.source,
            reason: "\(decision.reason ?? "permission-decision")-fallback-\(fallbackPersistence.rawValue)",
            createdAt: decision.createdAt,
            updatedAt: decision.updatedAt,
            expiresAt: decision.expiresAt,
            systemAuthorizationSnapshot: decision.systemAuthorizationSnapshot
        )
        do {
            try await memoryStore.setDecision(
                for: key,
                decision: fallbackDecision,
                sessionOwnerId: sessionOwnerId
            )
        } catch {
            RuntimeDiagnostics.emit(
                "[Permissions] Failed to store fallback permission decision for \(key.permissionType.identity): \(error.localizedDescription)"
            )
        }
    }

    private func recordManualSiteDecisionAntiAbuse(
        state: SumiPermissionState,
        key: SumiPermissionKey,
        reason: String?
    ) async {
        switch state {
        case .allow, .ask:
            await antiAbuseStore?.clearSuppressionState(for: key, now: nowProvider())
            if state == .allow {
                await recordAntiAbuseEvents(
                    type: .userAllowed,
                    keys: [key],
                    reason: reason ?? "manual-site-decision"
                )
            }
        case .deny:
            await recordAntiAbuseEvents(
                type: .userDenied,
                keys: [key],
                reason: reason ?? "manual-site-decision"
            )
        }
    }

    private func recordAntiAbuseSettlement(
        _ userDecision: SumiPermissionUserDecision,
        pending: PendingQuery,
        decision: SumiPermissionCoordinatorDecision
    ) async {
        guard decision.outcome != .ignored else { return }
        switch userDecision {
        case .approveCurrentAttempt,
             .approveOnce,
             .approveForSession,
             .approvePersistently:
            for key in pending.keys {
                await antiAbuseStore?.clearSuppressionState(for: key, now: nowProvider())
            }
            await recordAntiAbuseEvents(
                type: .userAllowed,
                keys: pending.keys,
                reason: decision.reason
            )
        case .denyOnce,
             .denyForSession,
             .denyPersistently:
            await recordAntiAbuseEvents(
                type: .userDenied,
                keys: pending.keys,
                reason: decision.reason
            )
        case .dismiss:
            await recordAntiAbuseEvents(
                type: .userDismissed,
                keys: pending.keys,
                reason: decision.reason
            )
        case .cancel:
            await recordAntiAbuseEvents(
                type: .requestCancelledByNavigation,
                keys: pending.keys,
                reason: decision.reason
            )
        case .expire,
             .setAskPersistently:
            break
        }
    }

    private func recordAntiAbuseCancellation(
        _ decision: SumiPermissionCoordinatorDecision
    ) async {
        guard decision.outcome == .cancelled, !decision.keys.isEmpty else { return }
        await recordAntiAbuseEvents(
            type: .requestCancelledByNavigation,
            keys: decision.keys,
            reason: decision.reason
        )
    }

    private func recordAntiAbuseEvents(
        type: SumiPermissionAntiAbuseEvent.EventType,
        keys: [SumiPermissionKey],
        reason: String?
    ) async {
        guard let antiAbuseStore else { return }
        let now = nowProvider()
        for key in keys {
            await antiAbuseStore.record(
                SumiPermissionAntiAbuseEvent(
                    type: type,
                    key: key,
                    createdAt: now,
                    reason: reason
                )
            )
        }
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
        await recordAntiAbuseCancellation(decision)
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
            systemAuthorizationSnapshots: systemSnapshots,
            policyReasons: policyResults.map(\.reason),
            createdAt: nowProvider(),
            isEphemeralProfile: request.isEphemeralProfile,
            shouldOfferSystemSettings: policyResults.contains(where: \.mayOpenSystemSettings),
            disablesPersistentAllow: request.isEphemeralProfile || !allowedPersistences.contains(.persistent)
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

    private func presentationPermissionType(
        originalTypes: [SumiPermissionType],
        promptTypes: [SumiPermissionType]
    ) -> SumiPermissionType? {
        Set(originalTypes) == Set([.camera, .microphone])
            && Set(promptTypes) == Set([.camera, .microphone])
            ? .cameraAndMicrophone
            : nil
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

    private func emitPolicyEventIfNeeded(_ decision: SumiPermissionCoordinatorDecision) async {
        guard decision.outcome == .systemBlocked else { return }
        if let suppression = await systemBlockedSuppression(for: decision) {
            let suppressedDecision = SumiPermissionCoordinatorDecision(
                outcome: .systemBlocked,
                state: decision.state,
                persistence: decision.persistence,
                source: decision.source,
                reason: suppression.reason,
                permissionTypes: decision.permissionTypes,
                keys: decision.keys,
                queryId: decision.queryId,
                systemAuthorizationSnapshot: decision.systemAuthorizationSnapshot,
                shouldOfferSystemSettings: decision.shouldOfferSystemSettings,
                disablesPersistentAllow: decision.disablesPersistentAllow,
                promptSuppression: suppression
            )
            await recordAntiAbuseEvents(
                type: suppression.eventType,
                keys: decision.keys,
                reason: suppression.reason
            )
            emit(.promptSuppressed(suppression, decision: suppressedDecision))
            return
        }
        await recordAntiAbuseEvents(
            type: .systemBlocked,
            keys: decision.keys,
            reason: decision.reason
        )
        emit(.systemBlocked(decision))
    }

    private func systemBlockedSuppression(
        for decision: SumiPermissionCoordinatorDecision
    ) async -> SumiPermissionPromptSuppression? {
        guard let antiAbuseStore else { return nil }
        let now = nowProvider()
        for key in decision.keys {
            let events = await antiAbuseStore.events(for: key, now: now)
            if let suppression = antiAbusePolicy.systemBlockedSuppression(
                for: key,
                events: events,
                now: now
            ) {
                return suppression
            }
        }
        return nil
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
