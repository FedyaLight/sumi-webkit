import Foundation

protocol SumiPermissionPolicyResolver: Sendable {
    func evaluate(_ context: SumiPermissionSecurityContext) async -> SumiPermissionPolicyResult
}

struct DefaultSumiPermissionPolicyResolver: SumiPermissionPolicyResolver {
    private let systemPermissionService: any SumiSystemPermissionService
    private let policyProvider: any SumiPermissionPolicyProvider

    init(
        systemPermissionService: any SumiSystemPermissionService = MacSumiSystemPermissionService(),
        policyProvider: any SumiPermissionPolicyProvider = NoOpSumiPermissionPolicyProvider()
    ) {
        self.systemPermissionService = systemPermissionService
        self.policyProvider = policyProvider
    }

    func evaluate(_ context: SumiPermissionSecurityContext) async -> SumiPermissionPolicyResult {
        guard let permissionType = singleSupportedPermissionType(in: context) else {
            return unsupported(context, reason: SumiPermissionPolicyReason.requiresSinglePermissionType)
        }

        if let unsupportedReason = unsupportedReason(for: permissionType) {
            return unsupported(context, permissionType: permissionType, reason: unsupportedReason)
        }

        if requiresKeyableWebOrigin(permissionType) {
            if let result = sensitiveOriginGate(context, permissionType: permissionType) {
                return result
            }
        }

        if requiresSecureContext(permissionType) {
            if let result = secureContextGate(context, permissionType: permissionType) {
                return result
            }
        }

        if requiresCommittedVisibleOriginConsistency(permissionType) {
            if shouldDenyForVirtualURLMismatch(context) {
                return deny(
                    .hardDeny,
                    context: context,
                    permissionType: permissionType,
                    source: .virtualURLMismatch,
                    reason: SumiPermissionPolicyReason.virtualURLMismatch
                )
            }
        }

        if let result = storageAccessThirdPartyGate(context, permissionType: permissionType) {
            return result
        }

        if let result = surfaceGate(context, permissionType: permissionType) {
            return result
        }

        if requiresUserActivation(permissionType), context.hasUserGesture != true {
            return deny(
                .requiresUserActivation,
                context: context,
                permissionType: permissionType,
                source: .runtime,
                reason: SumiPermissionPolicyReason.requiresUserActivation
            )
        }

        let override = await policyProvider.override(for: context, permissionType: permissionType)
        if let override, override.action == .deny {
            let source: SumiPermissionDecisionSource =
                override.source == .defaultSetting ? .defaultSetting : .policy
            return deny(
                .hardDeny,
                context: context,
                permissionType: permissionType,
                source: source,
                reason: override.reason
            )
        }

        if let systemKind = systemPermissionKind(for: permissionType) {
            let snapshot = await systemPermissionService.authorizationSnapshot(for: systemKind)
            switch snapshot.state {
            case .authorized:
                if let override, override.action == .allow {
                    return proceed(
                        context,
                        permissionType: permissionType,
                        source: override.source,
                        reason: override.reason,
                        systemAuthorizationSnapshot: snapshot
                    )
                }
                return proceed(
                    context,
                    permissionType: permissionType,
                    source: .defaultSetting,
                    reason: SumiPermissionPolicyReason.allowed,
                    systemAuthorizationSnapshot: snapshot
                )
            case .notDetermined:
                if let override, override.action == .allow {
                    return proceed(
                        context,
                        permissionType: permissionType,
                        source: override.source,
                        reason: override.reason,
                        systemAuthorizationSnapshot: snapshot,
                        requiresSystemAuthorizationPrompt: true
                    )
                }
                return proceed(
                    context,
                    permissionType: permissionType,
                    source: .system,
                    reason: SumiPermissionPolicyReason.systemAuthorizationNotDetermined,
                    systemAuthorizationSnapshot: snapshot,
                    requiresSystemAuthorizationPrompt: true
                )
            case .denied,
                 .restricted,
                 .systemDisabled,
                 .unavailable,
                 .missingUsageDescription,
                 .missingEntitlement:
                return systemBlocked(context, permissionType: permissionType, snapshot: snapshot)
            }
        }

        if let override, override.action == .allow {
            return proceed(
                context,
                permissionType: permissionType,
                source: override.source,
                reason: override.reason
            )
        }

        return proceed(
            context,
            permissionType: permissionType,
            source: .defaultSetting,
            reason: SumiPermissionPolicyReason.allowed
        )
    }

    private func singleSupportedPermissionType(
        in context: SumiPermissionSecurityContext
    ) -> SumiPermissionType? {
        guard context.request.permissionTypes.count == 1 else { return nil }
        return context.request.permissionTypes[0]
    }

    private func unsupportedReason(for permissionType: SumiPermissionType) -> String? {
        switch permissionType {
        case .cameraAndMicrophone:
            return SumiPermissionPolicyReason.cameraAndMicrophoneRequiresCoordinatorExpansion
        case .externalScheme(let scheme) where SumiPermissionType.normalizedExternalScheme(scheme).isEmpty:
            return SumiPermissionPolicyReason.emptyExternalSchemeUnsupported
        case .camera,
             .microphone,
             .geolocation,
             .notifications,
             .screenCapture,
             .popups,
             .externalScheme,
             .autoplay,
             .filePicker,
             .storageAccess:
            return nil
        }
    }

    private func sensitiveOriginGate(
        _ context: SumiPermissionSecurityContext,
        permissionType: SumiPermissionType
    ) -> SumiPermissionPolicyResult? {
        if isInternalBrowserPage(context, origin: context.requestingOrigin) {
            return deny(
                .internalOnly,
                context: context,
                permissionType: permissionType,
                source: .internalPage,
                reason: SumiPermissionPolicyReason.internalPage
            )
        }
        if isInternalBrowserPage(context, origin: context.topOrigin) {
            return deny(
                .internalOnly,
                context: context,
                permissionType: permissionType,
                source: .internalPage,
                reason: SumiPermissionPolicyReason.internalPage
            )
        }

        if let result = originValidityResult(
            context.requestingOrigin,
            context: context,
            permissionType: permissionType,
            invalidReason: SumiPermissionPolicyReason.invalidRequestingOrigin,
            unsupportedReason: SumiPermissionPolicyReason.unsupportedRequestingOrigin
        ) {
            return result
        }

        return originValidityResult(
            context.topOrigin,
            context: context,
            permissionType: permissionType,
            invalidReason: SumiPermissionPolicyReason.invalidTopOrigin,
            unsupportedReason: SumiPermissionPolicyReason.unsupportedTopOrigin
        )
    }

    private func originValidityResult(
        _ origin: SumiPermissionOrigin,
        context: SumiPermissionSecurityContext,
        permissionType: SumiPermissionType,
        invalidReason: String,
        unsupportedReason: String
    ) -> SumiPermissionPolicyResult? {
        switch origin.kind {
        case .web:
            return nil
        case .file:
            return deny(
                .hardDeny,
                context: context,
                permissionType: permissionType,
                source: .invalidOrigin,
                reason: SumiPermissionPolicyReason.fileOriginDenied
            )
        case .opaque, .invalid:
            return deny(
                .hardDeny,
                context: context,
                permissionType: permissionType,
                source: .invalidOrigin,
                reason: invalidReason
            )
        case .unsupported:
            return deny(
                .unsupported,
                context: context,
                permissionType: permissionType,
                source: .unsupported,
                reason: unsupportedReason
            )
        }
    }

    private func secureContextGate(
        _ context: SumiPermissionSecurityContext,
        permissionType: SumiPermissionType
    ) -> SumiPermissionPolicyResult? {
        guard context.requestingOrigin.isPotentiallyTrustworthy else {
            return deny(
                .hardDeny,
                context: context,
                permissionType: permissionType,
                source: .insecureOrigin,
                reason: SumiPermissionPolicyReason.insecureRequestingOrigin
            )
        }
        guard context.topOrigin.isPotentiallyTrustworthy else {
            return deny(
                .hardDeny,
                context: context,
                permissionType: permissionType,
                source: .insecureOrigin,
                reason: SumiPermissionPolicyReason.insecureTopOrigin
            )
        }
        return nil
    }

    private func surfaceGate(
        _ context: SumiPermissionSecurityContext,
        permissionType: SumiPermissionType
    ) -> SumiPermissionPolicyResult? {
        switch context.surface {
        case .normalTab:
            return nil
        case .miniWindow:
            guard requiresNormalTabSurface(permissionType) else { return nil }
            return deny(
                .hardDeny,
                context: context,
                permissionType: permissionType,
                source: .defaultSetting,
                reason: SumiPermissionPolicyReason.miniWindowSensitiveDenied
            )
        case .peek:
            guard requiresNormalTabSurface(permissionType) else { return nil }
            return deny(
                .hardDeny,
                context: context,
                permissionType: permissionType,
                source: .defaultSetting,
                reason: SumiPermissionPolicyReason.peekSensitiveDenied
            )
        case .extensionPage:
            return deny(
                .unsupported,
                context: context,
                permissionType: permissionType,
                source: .unsupported,
                reason: SumiPermissionPolicyReason.extensionPageUnsupported
            )
        case .internalPage:
            return deny(
                .internalOnly,
                context: context,
                permissionType: permissionType,
                source: .internalPage,
                reason: SumiPermissionPolicyReason.internalPage
            )
        case .unknown:
            guard requiresNormalTabSurface(permissionType) else { return nil }
            return deny(
                .hardDeny,
                context: context,
                permissionType: permissionType,
                source: .defaultSetting,
                reason: SumiPermissionPolicyReason.unknownSurfaceSensitiveDenied
            )
        }
    }

    private func storageAccessThirdPartyGate(
        _ context: SumiPermissionSecurityContext,
        permissionType: SumiPermissionType
    ) -> SumiPermissionPolicyResult? {
        guard permissionType == .storageAccess else { return nil }
        let sameIdentity = context.requestingOrigin.identity == context.topOrigin.identity
        let sameHost = context.requestingOrigin.host != nil
            && context.requestingOrigin.host == context.topOrigin.host
        guard sameIdentity || sameHost else { return nil }

        return deny(
            .hardDeny,
            context: context,
            permissionType: permissionType,
            source: .defaultSetting,
            reason: SumiPermissionPolicyReason.storageAccessSameOrigin
        )
    }

    private func shouldDenyForVirtualURLMismatch(
        _ context: SumiPermissionSecurityContext
    ) -> Bool {
        guard let committedURL = context.committedURL ?? context.mainFrameURL,
              let visibleURL = context.visibleURL
        else {
            return false
        }

        guard committedURL.absoluteString != visibleURL.absoluteString else {
            return false
        }

        let committedOrigin = SumiPermissionOrigin(url: committedURL)
        let visibleOrigin = SumiPermissionOrigin(url: visibleURL)
        return committedOrigin.identity != visibleOrigin.identity
    }

    private func systemBlocked(
        _ context: SumiPermissionSecurityContext,
        permissionType: SumiPermissionType,
        snapshot: SumiSystemPermissionSnapshot
    ) -> SumiPermissionPolicyResult {
        let decision = decision(
            context: context,
            permissionType: permissionType,
            source: .system,
            reason: "\(SumiPermissionPolicyReason.systemAuthorizationBlocked):\(snapshot.state.rawValue)",
            systemAuthorizationSnapshot: snapshot
        )
        return .systemBlocked(snapshot: snapshot, decision: decision)
    }

    private func proceed(
        _ context: SumiPermissionSecurityContext,
        permissionType: SumiPermissionType,
        source: SumiPermissionDecisionSource,
        reason: String,
        systemAuthorizationSnapshot: SumiSystemPermissionSnapshot? = nil,
        requiresSystemAuthorizationPrompt: Bool = false
    ) -> SumiPermissionPolicyResult {
        .proceed(
            source: source,
            reason: reason,
            systemAuthorizationSnapshot: systemAuthorizationSnapshot,
            mayOpenSystemSettings: systemAuthorizationSnapshot?.shouldOpenSystemSettings ?? false,
            requiresSystemAuthorizationPrompt: requiresSystemAuthorizationPrompt,
            allowedPersistences: allowedPersistences(
                for: permissionType,
                isEphemeralProfile: context.isEphemeralProfile
            )
        )
    }

    private enum DenyResultKind {
        case hardDeny
        case unsupported
        case internalOnly
        case requiresUserActivation
    }

    private func deny(
        _ kind: DenyResultKind,
        context: SumiPermissionSecurityContext,
        permissionType: SumiPermissionType? = nil,
        source: SumiPermissionDecisionSource,
        reason: String
    ) -> SumiPermissionPolicyResult {
        let decision = decision(
            context: context,
            permissionType: permissionType,
            source: source,
            reason: reason
        )
        switch kind {
        case .hardDeny:
            return .hardDeny(decision: decision)
        case .unsupported:
            return .unsupported(decision: decision)
        case .internalOnly:
            return .internalOnly(decision: decision)
        case .requiresUserActivation:
            return .requiresUserActivation(decision: decision)
        }
    }

    private func unsupported(
        _ context: SumiPermissionSecurityContext,
        permissionType: SumiPermissionType? = nil,
        reason: String
    ) -> SumiPermissionPolicyResult {
        deny(
            .unsupported,
            context: context,
            permissionType: permissionType,
            source: .unsupported,
            reason: reason
        )
    }

    private func decision(
        context: SumiPermissionSecurityContext,
        permissionType: SumiPermissionType?,
        source: SumiPermissionDecisionSource,
        reason: String,
        systemAuthorizationSnapshot: SumiSystemPermissionSnapshot? = nil
    ) -> SumiPermissionDecision {
        SumiPermissionDecision(
            state: .deny,
            persistence: denialPersistence(for: permissionType),
            source: source,
            reason: reason,
            createdAt: context.now,
            updatedAt: context.now,
            systemAuthorizationSnapshot: encodedSnapshot(systemAuthorizationSnapshot)
        )
    }

    private func denialPersistence(
        for permissionType: SumiPermissionType?
    ) -> SumiPermissionPersistence {
        permissionType == .filePicker ? .oneTime : .session
    }

    private func allowedPersistences(
        for permissionType: SumiPermissionType,
        isEphemeralProfile: Bool
    ) -> Set<SumiPermissionPersistence> {
        if permissionType.isOneTimeOnly {
            return [.oneTime]
        }
        if isEphemeralProfile {
            return [.oneTime, .session]
        }
        return [.oneTime, .session, .persistent]
    }

    private func encodedSnapshot(_ snapshot: SumiSystemPermissionSnapshot?) -> String? {
        guard let snapshot,
              let data = try? JSONEncoder().encode(snapshot)
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func requiresKeyableWebOrigin(_ permissionType: SumiPermissionType) -> Bool {
        switch permissionType {
        case .camera,
             .microphone,
             .geolocation,
             .notifications,
             .screenCapture,
             .filePicker,
             .storageAccess:
            return true
        case .cameraAndMicrophone,
             .popups,
             .externalScheme,
             .autoplay:
            return false
        }
    }

    private func requiresSecureContext(_ permissionType: SumiPermissionType) -> Bool {
        switch permissionType {
        case .camera, .microphone, .geolocation, .notifications, .screenCapture, .storageAccess:
            return true
        case .cameraAndMicrophone,
             .popups,
             .externalScheme,
             .autoplay,
             .filePicker:
            return false
        }
    }

    private func requiresCommittedVisibleOriginConsistency(
        _ permissionType: SumiPermissionType
    ) -> Bool {
        switch permissionType {
        case .camera,
             .microphone,
             .geolocation,
             .notifications,
             .screenCapture,
             .filePicker,
             .storageAccess:
            return true
        case .cameraAndMicrophone,
             .popups,
             .externalScheme,
             .autoplay:
            return false
        }
    }

    private func requiresNormalTabSurface(_ permissionType: SumiPermissionType) -> Bool {
        switch permissionType {
        case .camera,
             .microphone,
             .geolocation,
             .notifications,
             .screenCapture,
             .filePicker,
             .storageAccess:
            return true
        case .cameraAndMicrophone,
             .popups,
             .externalScheme,
             .autoplay:
            return false
        }
    }

    private func requiresUserActivation(_ permissionType: SumiPermissionType) -> Bool {
        switch permissionType {
        case .popups, .externalScheme, .filePicker:
            return true
        case .camera,
             .microphone,
             .cameraAndMicrophone,
             .geolocation,
             .notifications,
             .screenCapture,
             .autoplay,
             .storageAccess:
            return false
        }
    }

    private func systemPermissionKind(
        for permissionType: SumiPermissionType
    ) -> SumiSystemPermissionKind? {
        switch permissionType {
        case .camera:
            return .camera
        case .microphone:
            return .microphone
        case .geolocation:
            return .geolocation
        case .notifications:
            return .notifications
        case .screenCapture:
            return .screenCapture
        case .cameraAndMicrophone,
             .popups,
             .externalScheme,
             .autoplay,
             .filePicker,
             .storageAccess:
            return nil
        }
    }

    private func isInternalBrowserPage(
        _ context: SumiPermissionSecurityContext,
        origin: SumiPermissionOrigin
    ) -> Bool {
        origin.scheme == "sumi"
            || context.surface == .internalPage
            || context.committedURL.map(isInternalBrowserURL) == true
            || context.mainFrameURL.map(isInternalBrowserURL) == true
    }

    private func isInternalBrowserURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "sumi"
    }
}
