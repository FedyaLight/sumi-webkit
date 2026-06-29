import Combine
import Foundation
import WebKit

@MainActor
protocol SumiCurrentSiteAutoplayPolicyManaging: AnyObject {
    func explicitPolicy(for url: URL?, profile: Profile?) -> SumiAutoplayPolicy?
    func setPolicy(
        _ policy: SumiAutoplayPolicy,
        for url: URL?,
        profile: Profile?,
        source: SumiPermissionDecisionSource,
        now: Date
    ) async throws
    func resetPolicy(for url: URL?, profile: Profile?) async throws
}

extension SumiAutoplayPolicyStoreAdapter: SumiCurrentSiteAutoplayPolicyManaging {}

enum SumiCurrentSiteSystemSnapshotMode: Equatable, Sendable {
    case none
    case live
}

@MainActor
final class SumiCurrentSitePermissionsViewModel: ObservableObject {
    struct Context: Equatable, Sendable {
        let tabId: String?
        let pageId: String?
        let committedURL: URL?
        let visibleURL: URL?
        let mainFrameURL: URL?
        let origin: SumiPermissionOrigin
        let profilePartitionId: String
        let isEphemeralProfile: Bool
        let displayDomain: String
        let navigationOrPageGeneration: String?

        var isSupportedWebOrigin: Bool {
            origin.isWebOrigin
        }

        func key(for permissionType: SumiPermissionType) -> SumiPermissionKey {
            SumiPermissionKey(
                requestingOrigin: origin,
                topOrigin: origin,
                permissionType: permissionType,
                profilePartitionId: profilePartitionId,
                transientPageId: pageId,
                isEphemeralProfile: isEphemeralProfile
            )
        }

        func securityContext(for permissionType: SumiPermissionType) -> SumiPermissionSecurityContext {
            let request = SumiPermissionRequest(
                id: "url-hub-\(permissionType.identity)-\(pageId ?? "page")",
                tabId: tabId,
                pageId: pageId,
                requestingOrigin: origin,
                topOrigin: origin,
                displayDomain: displayDomain,
                permissionTypes: [permissionType],
                hasUserGesture: false,
                isEphemeralProfile: isEphemeralProfile,
                profilePartitionId: profilePartitionId
            )
            return SumiPermissionSecurityContext(
                request: request,
                requestingOrigin: origin,
                topOrigin: origin,
                committedURL: committedURL,
                visibleURL: visibleURL,
                mainFrameURL: mainFrameURL,
                isMainFrame: true,
                isActiveTab: true,
                isVisibleTab: true,
                hasUserGesture: false,
                isEphemeralProfile: isEphemeralProfile,
                profilePartitionId: profilePartitionId,
                transientPageId: pageId,
                surface: .normalTab,
                navigationOrPageGeneration: navigationOrPageGeneration,
                now: Date()
            )
        }
    }

    struct LoadDependencies {
        let coordinator: any SumiPermissionCoordinating
        let systemPermissionService: any SumiSystemPermissionService
        let runtimeController: (any SumiRuntimePermissionControlling)?
        let autoplayStore: any SumiCurrentSiteAutoplayPolicyManaging
        let blockedPopupStore: SumiBlockedPopupStore
        let externalSchemeSessionStore: SumiExternalSchemeSessionStore
        let indicatorEventStore: SumiPermissionIndicatorEventStore
        let siteActivityStore: SumiPermissionSiteActivityStore
    }

    @Published private(set) var context: Context?
    @Published private(set) var rows: [SumiCurrentSitePermissionRow] = []
    @Published private(set) var summary: SumiCurrentSitePermissionSummary = .default
    @Published private(set) var isLoading = false
    @Published private(set) var isResetting = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private(set) var storedRecords: [SumiPermissionStoreRecord] = []
    private(set) var transientRecords: [SumiPermissionStoreRecord] = []

    func load(
        tab: Tab?,
        profile: Profile?,
        dependencies: LoadDependencies,
        systemSnapshotMode: SumiCurrentSiteSystemSnapshotMode = .none
    ) async {
        await load(
            context: Self.context(tab: tab, profile: profile),
            webView: tab?.existingWebView,
            profile: profile,
            reloadRequired: tab?.isAutoplayReloadRequired == true,
            autoplayInUse: tab?.audioState.isPlayingAudio == true,
            dependencies: dependencies,
            systemSnapshotMode: systemSnapshotMode
        )
    }

    func load(
        context: Context?,
        webView: WKWebView?,
        profile: Profile?,
        reloadRequired: Bool,
        autoplayInUse: Bool = false,
        dependencies: LoadDependencies,
        systemSnapshotMode: SumiCurrentSiteSystemSnapshotMode = .none
    ) async {
        self.context = context
        statusMessage = nil
        errorMessage = nil

        guard let context, context.isSupportedWebOrigin else {
            rows = []
            storedRecords = []
            transientRecords = []
            summary = .default
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            storedRecords = try await dependencies.coordinator.siteDecisionRecords(
                profilePartitionId: context.profilePartitionId,
                isEphemeralProfile: context.isEphemeralProfile
            )
            if let pageId = context.pageId {
                transientRecords = try await dependencies.coordinator.transientDecisionRecords(
                    profilePartitionId: context.profilePartitionId,
                    pageId: pageId
                )
            } else {
                transientRecords = []
            }
            dependencies.siteActivityStore.recordStoredRecords(storedRecords)
            dependencies.siteActivityStore.recordStoredRecords(transientRecords)
            recordAutoplayActivityIfNeeded(
                context: context,
                reloadRequired: reloadRequired,
                autoplayInUse: autoplayInUse,
                dependencies: dependencies
            )
            let rowIndex = SumiCurrentSitePermissionRowsBuilder.RowIndex(
                context: context,
                storedRecords: storedRecords,
                transientRecords: transientRecords,
                blockedPopupStore: dependencies.blockedPopupStore,
                externalSchemeSessionStore: dependencies.externalSchemeSessionStore,
                indicatorEventStore: dependencies.indicatorEventStore,
                siteActivityStore: dependencies.siteActivityStore
            )
            let runtimeState = webView.map {
                dependencies.runtimeController?.currentRuntimeState(for: $0, pageId: context.pageId)
            } ?? nil
            let systemSnapshots = await systemSnapshots(
                using: dependencies.systemPermissionService,
                mode: systemSnapshotMode
            )
            let builtRows = SumiCurrentSitePermissionRowsBuilder.makeRows(
                context: context,
                profile: profile,
                reloadRequired: reloadRequired,
                autoplayInUse: autoplayInUse,
                runtimeState: runtimeState,
                systemSnapshots: systemSnapshots,
                rowIndex: rowIndex,
                autoplayStore: dependencies.autoplayStore
            )
            rows = builtRows
            summary = SumiCurrentSitePermissionSummary.make(
                rows: builtRows,
                isEphemeralProfile: context.isEphemeralProfile
            )
        } catch {
            rows = []
            transientRecords = []
            summary = .default
            errorMessage = error.localizedDescription
        }
    }

    func select(
        _ option: SumiCurrentSitePermissionOption,
        for row: SumiCurrentSitePermissionRow,
        profile: Profile?,
        dependencies: LoadDependencies,
        onAutoplayChanged: (() -> Void)? = nil
    ) async {
        guard let context,
              context.isSupportedWebOrigin,
              row.isEditable
        else { return }

        do {
            switch row.kind {
            case .sitePermission(let permissionType):
                try await write(
                    option,
                    permissionType: permissionType,
                    context: context,
                    coordinator: dependencies.coordinator
                )
            case .popups:
                try await write(
                    option,
                    permissionType: .popups,
                    context: context,
                    coordinator: dependencies.coordinator
                )
            case .externalScheme(let scheme):
                try await write(
                    option,
                    permissionType: .externalScheme(scheme),
                    context: context,
                    coordinator: dependencies.coordinator
                )
            case .autoplay:
                try await writeAutoplay(
                    option,
                    context: context,
                    profile: profile,
                    autoplayStore: dependencies.autoplayStore
                )
                onAutoplayChanged?()
            case .externalApps, .filePicker:
                return
            }
            recordSelectionActivity(
                option,
                for: row,
                context: context,
                dependencies: dependencies
            )
            statusMessage = SumiCurrentSitePermissionsStrings.permissionsChanged
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetCurrentSite(
        profile: Profile?,
        dependencies: LoadDependencies
    ) async {
        guard let context, context.isSupportedWebOrigin else { return }
        isResetting = true
        defer { isResetting = false }

        do {
            let keys = resettableKeys(context: context)
            try await dependencies.coordinator.resetSiteDecisions(for: keys)
            try await dependencies.autoplayStore.resetPolicy(
                for: context.mainFrameURL ?? context.visibleURL ?? context.committedURL,
                profile: profile
            )
            if let pageId = context.pageId {
                dependencies.blockedPopupStore.clear(pageId: pageId)
                dependencies.externalSchemeSessionStore.clear(pageId: pageId)
                dependencies.indicatorEventStore.clear(pageId: pageId)
            }
            dependencies.siteActivityStore.clearSite(
                origin: context.origin,
                profilePartitionId: context.profilePartitionId,
                isEphemeralProfile: context.isEphemeralProfile
            )
            await dependencies.coordinator.resetTransientDecisions(
                profilePartitionId: context.profilePartitionId,
                pageId: context.pageId,
                requestingOrigin: context.origin,
                topOrigin: context.origin,
                reason: "url-hub-reset-current-site"
            )
            statusMessage = SumiCurrentSitePermissionsStrings.resetComplete
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openSystemSettings(
        for row: SumiCurrentSitePermissionRow,
        systemPermissionService: any SumiSystemPermissionService
    ) async {
        guard let kind = SumiCurrentSitePermissionRowsBuilder.systemKind(for: row) else { return }
        _ = await systemPermissionService.openSystemSettings(for: kind)
    }

    static func context(tab: Tab?, profile: Profile?) -> Context? {
        guard let tab, let profile else { return nil }

        let identity = tab.currentExtensionPageIdentity()
        let committedURL = tab.extensionRuntimeCommittedMainDocumentURL
        let visibleURL = tab.existingWebView?.url ?? tab.url
        let mainFrameURL = committedURL ?? visibleURL
        let origin = SumiPermissionOrigin(url: mainFrameURL)
        let displayDomain = displayDomain(for: origin, fallbackURL: mainFrameURL)

        return Context(
            tabId: identity.tabId,
            pageId: identity.pageId,
            committedURL: committedURL,
            visibleURL: visibleURL,
            mainFrameURL: mainFrameURL,
            origin: origin,
            profilePartitionId: profile.id.uuidString,
            isEphemeralProfile: profile.isEphemeral,
            displayDomain: displayDomain,
            navigationOrPageGeneration: identity.pageGeneration
        )
    }

    static func displayDomain(for origin: SumiPermissionOrigin, fallbackURL: URL?) -> String {
        guard origin.isWebOrigin else {
            return origin.displayDomain
        }
        let rawHost = fallbackURL?.host(percentEncoded: false) ?? fallbackURL?.host ?? origin.displayDomain
        let displayHost = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        return displayHost.isEmpty ? origin.displayDomain : displayHost
    }

    private func systemSnapshots(
        using service: any SumiSystemPermissionService,
        mode: SumiCurrentSiteSystemSnapshotMode
    ) async -> [SumiSystemPermissionKind: SumiSystemPermissionSnapshot] {
        guard mode == .live else { return [:] }

        var snapshots: [SumiSystemPermissionKind: SumiSystemPermissionSnapshot] = [:]
        for kind in SumiSystemPermissionKind.allCases {
            snapshots[kind] = await service.authorizationSnapshot(for: kind)
        }
        return snapshots
    }

    private func recordAutoplayActivityIfNeeded(
        context: Context,
        reloadRequired: Bool,
        autoplayInUse: Bool,
        dependencies: LoadDependencies
    ) {
        guard reloadRequired || autoplayInUse else { return }

        let reason = reloadRequired
            ? "autoplay-reload-required"
            : "autoplay-media-playing"
        dependencies.siteActivityStore.recordAutoplayActivity(
            displayDomain: context.displayDomain,
            key: context.key(for: .autoplay),
            reason: reason
        )
    }

    private func write(
        _ option: SumiCurrentSitePermissionOption,
        permissionType: SumiPermissionType,
        context: Context,
        coordinator: any SumiPermissionCoordinating
    ) async throws {
        let key = context.key(for: permissionType)
        switch option {
        case .ask, .default:
            try await coordinator.resetSiteDecision(for: key)
        case .allow:
            try await coordinator.setSiteDecision(
                for: key,
                state: .allow,
                source: .user,
                reason: "url-hub-permissions-submenu"
            )
        case .block:
            try await coordinator.setSiteDecision(
                for: key,
                state: .deny,
                source: .user,
                reason: "url-hub-permissions-submenu"
            )
        case .allowAll, .blockAudible, .blockAll:
            throw SumiPermissionSiteDecisionError.unsupportedPermission(permissionType.identity)
        }
    }

    private func writeAutoplay(
        _ option: SumiCurrentSitePermissionOption,
        context: Context,
        profile: Profile?,
        autoplayStore: any SumiCurrentSiteAutoplayPolicyManaging
    ) async throws {
        let url = context.mainFrameURL ?? context.visibleURL ?? context.committedURL
        switch option {
        case .default:
            try await autoplayStore.resetPolicy(for: url, profile: profile)
        case .allowAll:
            try await autoplayStore.setPolicy(.allowAll, for: url, profile: profile, source: .user, now: Date())
        case .blockAudible:
            try await autoplayStore.setPolicy(.blockAudible, for: url, profile: profile, source: .user, now: Date())
        case .blockAll:
            try await autoplayStore.setPolicy(.blockAll, for: url, profile: profile, source: .user, now: Date())
        case .ask, .allow, .block:
            throw SumiPermissionSiteDecisionError.unsupportedPermission("autoplay")
        }
    }

    private func recordSelectionActivity(
        _ option: SumiCurrentSitePermissionOption,
        for row: SumiCurrentSitePermissionRow,
        context: Context,
        dependencies: LoadDependencies
    ) {
        let permissionType: SumiPermissionType
        let state: SumiPermissionState?
        let selectedAutoplayPolicy: SumiAutoplayPolicy?

        switch row.kind {
        case .sitePermission(let type):
            permissionType = type
            state = permissionState(for: option)
            selectedAutoplayPolicy = nil
        case .popups:
            permissionType = .popups
            state = permissionState(for: option)
            selectedAutoplayPolicy = nil
        case .externalScheme(let scheme):
            permissionType = .externalScheme(scheme)
            state = permissionState(for: option)
            selectedAutoplayPolicy = nil
        case .autoplay:
            permissionType = .autoplay
            selectedAutoplayPolicy = autoplayPolicy(for: option)
            switch selectedAutoplayPolicy {
            case .allowAll:
                state = .allow
            case .blockAudible, .blockAll:
                state = .deny
            case .default, nil:
                state = nil
            }
        case .externalApps, .filePicker:
            return
        }

        dependencies.siteActivityStore.recordSettingsChange(
            displayDomain: context.displayDomain,
            key: context.key(for: permissionType),
            state: state,
            autoplayPolicy: selectedAutoplayPolicy,
            reason: "url-hub-permission-setting"
        )
    }

    private func permissionState(
        for option: SumiCurrentSitePermissionOption
    ) -> SumiPermissionState? {
        switch option {
        case .ask, .default:
            return nil
        case .allow, .allowAll:
            return .allow
        case .block, .blockAudible, .blockAll:
            return .deny
        }
    }

    private func autoplayPolicy(
        for option: SumiCurrentSitePermissionOption
    ) -> SumiAutoplayPolicy? {
        switch option {
        case .default:
            return .default
        case .allowAll:
            return .allowAll
        case .blockAudible:
            return .blockAudible
        case .blockAll:
            return .blockAll
        case .ask, .allow, .block:
            return nil
        }
    }

    private func resettableKeys(context: Context) -> [SumiPermissionKey] {
        var permissionTypes: [SumiPermissionType] = [
            .camera,
            .microphone,
            .geolocation,
            .notifications,
            .screenCapture,
            .popups,
            .storageAccess,
        ]

        let externalSchemes = storedRecords.compactMap { record -> String? in
            guard isCurrentSite(record.key, context: context),
                  case .externalScheme(let scheme) = record.key.permissionType
            else { return nil }
            return SumiPermissionType.normalizedExternalScheme(scheme)
        }
        permissionTypes.append(contentsOf: Set(externalSchemes).sorted().map(SumiPermissionType.externalScheme))

        return permissionTypes.map { context.key(for: $0) }
    }

    private func isCurrentSite(
        _ key: SumiPermissionKey,
        context: Context
    ) -> Bool {
        key.profilePartitionId == context.profilePartitionId
            && key.isEphemeralProfile == context.isEphemeralProfile
            && key.requestingOrigin.identity == context.origin.identity
            && key.topOrigin.identity == context.origin.identity
    }
}
