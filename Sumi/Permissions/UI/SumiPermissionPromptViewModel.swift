import Combine
import Foundation

@MainActor
final class SumiPermissionPromptViewModel: ObservableObject {
    enum Source: Equatable {
        case query(SumiPermissionAuthorizationQuery)
        case systemBlocked(SumiPermissionCoordinatorDecision)
    }

    private let source: Source
    private let coordinator: any SumiPermissionCoordinating
    private let systemPermissionService: any SumiSystemPermissionService
    private let externalAppResolver: (any SumiExternalAppResolving)?
    private let onFinished: @MainActor () -> Void

    @Published private(set) var isPerformingAction = false
    @Published private(set) var systemBlockedSnapshots: [SumiSystemPermissionSnapshot]

    init(
        query: SumiPermissionAuthorizationQuery,
        coordinator: any SumiPermissionCoordinating,
        systemPermissionService: any SumiSystemPermissionService,
        externalAppResolver: (any SumiExternalAppResolving)? = nil,
        onFinished: @escaping @MainActor () -> Void = {}
    ) {
        self.source = .query(query)
        self.coordinator = coordinator
        self.systemPermissionService = systemPermissionService
        self.externalAppResolver = externalAppResolver
        self.onFinished = onFinished
        self.systemBlockedSnapshots = Self.blockedSnapshots(from: query.systemAuthorizationSnapshots)
    }

    init(
        systemBlockedDecision decision: SumiPermissionCoordinatorDecision,
        coordinator: any SumiPermissionCoordinating,
        systemPermissionService: any SumiSystemPermissionService,
        externalAppResolver: (any SumiExternalAppResolving)? = nil,
        onFinished: @escaping @MainActor () -> Void = {}
    ) {
        self.source = .systemBlocked(decision)
        self.coordinator = coordinator
        self.systemPermissionService = systemPermissionService
        self.externalAppResolver = externalAppResolver
        self.onFinished = onFinished
        self.systemBlockedSnapshots = Self.blockedSnapshots(
            from: [decision.systemAuthorizationSnapshot].compactMap { $0 }
        )
    }

    var queryId: String? {
        query?.id
    }

    var displayDomain: String {
        switch source {
        case .query(let query):
            return SumiPermissionPromptStrings.normalizedDisplayDomain(query.displayDomain)
        case .systemBlocked(let decision):
            return SumiPermissionPromptStrings.normalizedDisplayDomain(
                decision.keys.first?.displayDomain ?? "Current site"
            )
        }
    }

    var permissionType: SumiPermissionType {
        switch source {
        case .query(let query):
            return Self.primaryPermissionType(
                permissionTypes: query.permissionTypes,
                presentationPermissionType: query.presentationPermissionType
            )
        case .systemBlocked(let decision):
            return Self.primaryPermissionType(
                permissionTypes: decision.permissionTypes,
                presentationPermissionType: nil
            )
        }
    }

    var permissionTypes: [SumiPermissionType] {
        switch source {
        case .query(let query):
            return query.permissionTypes
        case .systemBlocked(let decision):
            return decision.permissionTypes
        }
    }

    var icon: SumiPermissionIconDescriptor {
        SumiPermissionIconCatalog.icon(
            for: permissionType,
            visualStyle: isSystemBlocked ? .systemWarning : .attention
        )
    }

    var title: String {
        SumiPermissionPromptStrings.title(
            permissionType: permissionType,
            displayDomain: displayDomain,
            externalAppName: externalAppName
        )
    }

    var detail: String? {
        SumiPermissionPromptStrings.detail(
            permissionType: permissionType,
            permissionTypes: permissionTypes,
            externalAppName: externalAppName
        )
    }

    var isSystemBlocked: Bool {
        !systemBlockedSnapshots.isEmpty
    }

    var systemBlockedTitle: String {
        SumiPermissionPromptStrings.systemBlockedTitle(for: systemBlockedSnapshots)
    }

    var systemBlockedMessage: String {
        SumiPermissionPromptStrings.systemBlockedMessage(for: systemBlockedSnapshots)
    }

    var canOpenSystemSettings: Bool {
        systemBlockedSnapshots.contains(where: \.shouldOpenSystemSettings)
    }

    var options: [SumiPermissionPromptOption] {
        let resolvedOptions: [SumiPermissionPromptOption]
        if isSystemBlocked {
            resolvedOptions = systemOptions()
        } else {
            resolvedOptions = normalOptions()
        }

        guard isPerformingAction else { return resolvedOptions }
        return resolvedOptions.map {
            SumiPermissionPromptOption(
                action: $0.action,
                title: $0.title,
                accessibilityLabel: $0.accessibilityLabel,
                role: $0.role,
                isEnabled: false
            )
        }
    }

    func perform(_ action: SumiPermissionPromptAction) {
        Task { @MainActor in
            await performAction(action)
        }
    }

    func performAction(_ action: SumiPermissionPromptAction) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }

        switch action {
        case .allowWhileVisiting, .allowThisTime, .allow, .openThisTime, .alwaysAllowExternal:
            await performAllowAction(action)
        case .dontAllow:
            await performDenyAction()
        case .openSystemSettings:
            await openSystemSettings()
        case .dismiss:
            await dismiss()
        }
    }

    private var query: SumiPermissionAuthorizationQuery? {
        if case .query(let query) = source {
            return query
        }
        return nil
    }

    private var externalAppName: String? {
        guard case .externalScheme(let scheme) = permissionType,
              let url = URL(string: "\(SumiPermissionType.normalizedExternalScheme(scheme)):"),
              let name = externalAppResolver?.appInfo(for: url)?.appDisplayName?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else {
            return nil
        }
        return name
    }

    private func normalOptions() -> [SumiPermissionPromptOption] {
        guard query != nil, Self.isPromptable(permissionType) else { return [] }

        switch permissionType {
        case .notifications:
            return [
                .init(action: .allow, title: "Allow", role: .primary),
                .init(action: .dontAllow, title: "Don't allow", role: .destructive),
            ]
        case .storageAccess:
            return [
                .init(action: .allow, title: "Allow", role: .primary),
                .init(action: .dontAllow, title: "Don't allow", role: .destructive),
            ]
        case .externalScheme:
            var options: [SumiPermissionPromptOption] = [
                .init(action: .openThisTime, title: "Open this time", role: .primary),
            ]
            if canUsePersistentSiteDecision {
                options.append(
                    .init(
                        action: .alwaysAllowExternal,
                        title: "Always allow this site to open this app",
                        role: .normal
                    )
                )
            }
            options.append(.init(action: .dontAllow, title: "Don't allow", role: .destructive))
            return options
        case .camera, .microphone, .cameraAndMicrophone, .geolocation, .screenCapture:
            return [
                .init(
                    action: .allowWhileVisiting,
                    title: "Allow while visiting this site",
                    role: .primary
                ),
                .init(action: .allowThisTime, title: "Allow this time", role: .normal),
                .init(action: .dontAllow, title: "Don't allow", role: .destructive),
            ]
        case .popups, .autoplay, .filePicker:
            return []
        }
    }

    private func systemOptions() -> [SumiPermissionPromptOption] {
        var options: [SumiPermissionPromptOption] = []
        if canOpenSystemSettings {
            options.append(
                .init(
                    action: .openSystemSettings,
                    title: "Open System Settings",
                    role: .primary
                )
            )
        }
        options.append(.init(action: .dismiss, title: "Not now", role: .cancel))
        return options
    }

    private var canUsePersistentSiteDecision: Bool {
        guard let query else { return false }
        return !query.isEphemeralProfile
            && !query.disablesPersistentAllow
            && query.availablePersistences.contains(.persistent)
    }

    private func performAllowAction(_ action: SumiPermissionPromptAction) async {
        guard let query else {
            onFinished()
            return
        }

        guard await ensureSystemAuthorizationIfNeeded(for: query) else {
            onFinished()
            return
        }

        switch action {
        case .allowThisTime, .openThisTime:
            await coordinator.approveOnce(query.id)
        case .allowWhileVisiting, .allow:
            if canUsePersistentSiteDecision {
                await coordinator.approvePersistently(query.id)
            } else {
                await coordinator.approveForSession(query.id)
            }
        case .alwaysAllowExternal:
            if canUsePersistentSiteDecision {
                await coordinator.approvePersistently(query.id)
            } else {
                await coordinator.approveForSession(query.id)
            }
        case .dontAllow, .openSystemSettings, .dismiss:
            break
        }
        onFinished()
    }

    private func performDenyAction() async {
        guard let query else {
            onFinished()
            return
        }

        if canUsePersistentSiteDecision {
            await coordinator.denyPersistently(query.id)
        } else {
            await coordinator.denyForSession(query.id)
        }
        onFinished()
    }

    private func dismiss() async {
        if let query {
            await coordinator.dismiss(query.id)
        }
        onFinished()
    }

    private func openSystemSettings() async {
        if let kind = systemBlockedSnapshots.first(where: \.shouldOpenSystemSettings)?.kind
            ?? systemBlockedSnapshots.first?.kind
            ?? systemPermissionKinds().first {
            await systemPermissionService.openSystemSettings(for: kind)
        }
        if let query {
            await coordinator.cancel(
                queryId: query.id,
                reason: "permission-prompt-open-system-settings"
            )
        }
        onFinished()
    }

    private func ensureSystemAuthorizationIfNeeded(
        for query: SumiPermissionAuthorizationQuery
    ) async -> Bool {
        let kinds = systemPermissionKinds()
        guard !kinds.isEmpty else { return true }

        var blockedSnapshots: [SumiSystemPermissionSnapshot] = []
        for kind in kinds {
            let currentState = await systemPermissionService.authorizationState(for: kind)
            switch currentState {
            case .authorized:
                continue
            case .notDetermined:
                let requestedState = await systemPermissionService.requestAuthorization(for: kind)
                guard requestedState == .authorized else {
                    blockedSnapshots.append(SumiSystemPermissionSnapshot(kind: kind, state: requestedState))
                    continue
                }
            case .denied,
                 .restricted,
                 .systemDisabled,
                 .unavailable,
                 .missingUsageDescription,
                 .missingEntitlement:
                blockedSnapshots.append(SumiSystemPermissionSnapshot(kind: kind, state: currentState))
            }
        }

        guard blockedSnapshots.isEmpty else {
            systemBlockedSnapshots = blockedSnapshots
            await coordinator.cancel(
                queryId: query.id,
                reason: "permission-prompt-system-authorization-denied"
            )
            return false
        }
        return true
    }

    private func systemPermissionKinds() -> [SumiSystemPermissionKind] {
        var seen = Set<SumiSystemPermissionKind>()
        var kinds: [SumiSystemPermissionKind] = []
        for permissionType in permissionTypes {
            let mappedKinds: [SumiSystemPermissionKind]
            switch permissionType {
            case .camera:
                mappedKinds = [.camera]
            case .microphone:
                mappedKinds = [.microphone]
            case .cameraAndMicrophone:
                mappedKinds = [.camera, .microphone]
            case .geolocation:
                mappedKinds = [.geolocation]
            case .notifications:
                mappedKinds = [.notifications]
            case .screenCapture:
                mappedKinds = [.screenCapture]
            case .popups, .externalScheme, .autoplay, .filePicker, .storageAccess:
                mappedKinds = []
            }
            for kind in mappedKinds where seen.insert(kind).inserted {
                kinds.append(kind)
            }
        }
        return kinds
    }

    private static func blockedSnapshots(
        from snapshots: [SumiSystemPermissionSnapshot]
    ) -> [SumiSystemPermissionSnapshot] {
        snapshots.filter { snapshot in
            switch snapshot.state {
            case .denied,
                 .restricted,
                 .systemDisabled,
                 .unavailable,
                 .missingUsageDescription,
                 .missingEntitlement:
                return true
            case .authorized, .notDetermined:
                return false
            }
        }
    }

    static func isPromptable(_ permissionType: SumiPermissionType) -> Bool {
        switch permissionType {
        case .camera,
             .microphone,
             .cameraAndMicrophone,
             .geolocation,
             .notifications,
             .screenCapture,
             .storageAccess,
             .externalScheme:
            return true
        case .popups, .autoplay, .filePicker:
            return false
        }
    }

    static func primaryPermissionType(
        permissionTypes: [SumiPermissionType],
        presentationPermissionType: SumiPermissionType?
    ) -> SumiPermissionType {
        if let presentationPermissionType {
            return presentationPermissionType
        }

        let identities = Set(permissionTypes.map(\.identity))
        if identities.contains(SumiPermissionType.camera.identity),
           identities.contains(SumiPermissionType.microphone.identity) {
            return .cameraAndMicrophone
        }

        let ordered: [SumiPermissionType] = [
            .screenCapture,
            .camera,
            .microphone,
            .geolocation,
            .notifications,
            .storageAccess,
        ]
        for candidate in ordered where identities.contains(candidate.identity) {
            return candidate
        }

        if let external = permissionTypes.first(where: { permissionType in
            if case .externalScheme = permissionType { return true }
            return false
        }) {
            return external
        }

        return permissionTypes.first ?? .notifications
    }
}
