import Foundation
import SumiDomain

struct SumiPermissionAuthorizationQueryBuilder {
    typealias PolicyEvaluation = SumiPermissionDecisionResolutionOwner.PolicyEvaluation
    typealias NowProvider = @Sendable () -> Date

    private let now: NowProvider

    init(now: @escaping NowProvider) {
        self.now = now
    }

    func request(
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

    func authorizationQuery(
        request: SumiPermissionRequest,
        originalContext: SumiPermissionSecurityContext,
        promptEvaluations: [PolicyEvaluation]
    ) -> SumiPermissionAuthorizationQuery {
        let policyResults = promptEvaluations.map(\.result)
        let allowedPersistences = allowedPersistences(for: policyResults)
        return SumiPermissionAuthorizationQuery(
            id: stableQueryID(for: request),
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
            systemAuthorizationSnapshots: policyResults.compactMap(\.systemAuthorizationSnapshot),
            policyReasons: policyResults.map(\.reason),
            createdAt: now(),
            isEphemeralProfile: request.isEphemeralProfile,
            shouldOfferSystemSettings: policyResults.contains(where: \.mayOpenSystemSettings),
            disablesPersistentAllow: request.isEphemeralProfile
                || !allowedPersistences.contains(.persistent)
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

    private func stableQueryID(
        for request: SumiPermissionRequest
    ) -> String {
        [
            "permission-query",
            request.pageBucketId,
            request.queuePersistentIdentity,
        ].joined(separator: "|")
    }
}
