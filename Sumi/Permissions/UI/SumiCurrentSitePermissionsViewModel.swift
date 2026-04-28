import Combine
import Foundation
import WebKit

@MainActor
protocol SumiCurrentSiteAutoplayPolicyManaging: AnyObject {
    func effectivePolicy(for url: URL?, profile: Profile?) -> SumiAutoplayPolicy
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
            dependencies: dependencies,
            systemSnapshotMode: systemSnapshotMode
        )
    }

    func load(
        context: Context?,
        webView: WKWebView?,
        profile: Profile?,
        reloadRequired: Bool,
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
            let runtimeState = webView.map {
                dependencies.runtimeController?.currentRuntimeState(for: $0, pageId: context.pageId)
            } ?? nil
            let systemSnapshots = await systemSnapshots(
                using: dependencies.systemPermissionService,
                mode: systemSnapshotMode
            )
            let builtRows = makeRows(
                context: context,
                profile: profile,
                reloadRequired: reloadRequired,
                runtimeState: runtimeState,
                systemSnapshots: systemSnapshots,
                dependencies: dependencies
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
        guard let kind = systemKind(for: row) else { return }
        _ = await systemPermissionService.openSystemSettings(for: kind)
    }

    static func context(tab: Tab?, profile: Profile?) -> Context? {
        guard let tab, let profile else { return nil }

        let tabId = tab.id.uuidString.lowercased()
        let pageGeneration = String(tab.extensionRuntimeDocumentSequence)
        let pageId = tab.currentPermissionPageId()
        let committedURL = tab.extensionRuntimeCommittedMainDocumentURL
        let visibleURL = tab.existingWebView?.url ?? tab.url
        let mainFrameURL = committedURL ?? visibleURL
        let origin = SumiPermissionOrigin(url: mainFrameURL)
        let displayDomain = displayDomain(for: origin, fallbackURL: mainFrameURL)

        return Context(
            tabId: tabId,
            pageId: pageId,
            committedURL: committedURL,
            visibleURL: visibleURL,
            mainFrameURL: mainFrameURL,
            origin: origin,
            profilePartitionId: profile.id.uuidString,
            isEphemeralProfile: profile.isEphemeral,
            displayDomain: displayDomain,
            navigationOrPageGeneration: pageGeneration
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

    private func makeRows(
        context: Context,
        profile: Profile?,
        reloadRequired: Bool,
        runtimeState: SumiRuntimePermissionState?,
        systemSnapshots: [SumiSystemPermissionKind: SumiSystemPermissionSnapshot],
        dependencies: LoadDependencies
    ) -> [SumiCurrentSitePermissionRow] {
        var result: [SumiCurrentSitePermissionRow] = []

        result.append(
            sitePermissionRow(
                permissionType: .camera,
                context: context,
                systemSnapshot: systemSnapshots[.camera],
                runtimeStatus: runtimeStatus(for: runtimeState?.camera),
                recentEventCount: recentEventCount(for: .camera, context: context, dependencies: dependencies)
            )
        )
        result.append(
            sitePermissionRow(
                permissionType: .microphone,
                context: context,
                systemSnapshot: systemSnapshots[.microphone],
                runtimeStatus: runtimeStatus(for: runtimeState?.microphone),
                recentEventCount: recentEventCount(for: .microphone, context: context, dependencies: dependencies)
            )
        )
        result.append(
            sitePermissionRow(
                permissionType: .screenCapture,
                context: context,
                systemSnapshot: systemSnapshots[.screenCapture],
                runtimeStatus: runtimeStatus(for: runtimeState?.screenCapture),
                recentEventCount: recentEventCount(for: .screenCapture, context: context, dependencies: dependencies)
            )
        )
        result.append(
            sitePermissionRow(
                permissionType: .geolocation,
                context: context,
                systemSnapshot: systemSnapshots[.geolocation],
                runtimeStatus: runtimeStatus(for: runtimeState?.geolocation),
                recentEventCount: recentEventCount(for: .geolocation, context: context, dependencies: dependencies)
            )
        )
        result.append(
            sitePermissionRow(
                permissionType: .notifications,
                context: context,
                systemSnapshot: systemSnapshots[.notifications],
                runtimeStatus: nil,
                recentEventCount: recentEventCount(for: .notifications, context: context, dependencies: dependencies)
            )
        )
        result.append(popupsRow(context: context, dependencies: dependencies))
        result.append(contentsOf: externalAppRows(context: context, dependencies: dependencies))
        result.append(autoplayRow(context: context, profile: profile, reloadRequired: reloadRequired, autoplayStore: dependencies.autoplayStore))
        result.append(
            sitePermissionRow(
                permissionType: .storageAccess,
                context: context,
                systemSnapshot: nil,
                runtimeStatus: nil,
                recentEventCount: recentEventCount(for: .storageAccess, context: context, dependencies: dependencies),
                titleOverride: SumiCurrentSitePermissionsStrings.storageAccessTitle,
                subtitleOverride: "Embedded content / saved information access"
            )
        )
        result.append(filePickerRow(context: context, dependencies: dependencies))

        return result
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

    private func sitePermissionRow(
        permissionType: SumiPermissionType,
        context: Context,
        systemSnapshot: SumiSystemPermissionSnapshot?,
        runtimeStatus: String?,
        recentEventCount: Int,
        titleOverride: String? = nil,
        subtitleOverride: String? = nil
    ) -> SumiCurrentSitePermissionRow {
        let descriptor = SumiPermissionIconCatalog.icon(for: permissionType)
        let key = context.key(for: permissionType)
        let option = option(for: record(for: key), defaultOption: .ask)
        let oneTimeRecord = activeOneTimeRecord(for: key, context: context)
        let system = systemStatus(from: systemSnapshot)
        let disabledReason = context.origin.supportsSensitiveWebPermission(permissionType)
            ? nil
            : "Requires a secure connection"
        let isEditable = disabledReason == nil
        let subtitle = subtitleOverride
            ?? subtitle(
                option: option,
                recentEventCount: recentEventCount,
                isEphemeralProfile: context.isEphemeralProfile,
                hasActiveOneTimeGrant: oneTimeRecord != nil
            )

        return SumiCurrentSitePermissionRow(
            id: permissionType.identity,
            kind: .sitePermission(permissionType),
            title: titleOverride ?? permissionType.displayLabel,
            subtitle: subtitle,
            iconName: descriptor.chromeIconName,
            fallbackSystemName: descriptor.fallbackSystemName,
            currentOption: option,
            availableOptions: [.ask, .allow, .block],
            isEditable: isEditable,
            disabledReason: disabledReason,
            systemStatus: system.text,
            showsSystemSettingsAction: system.showsSettings,
            runtimeStatus: runtimeStatus,
            recentEventCount: recentEventCount,
            accessibilityLabel: "\(permissionType.displayLabel), \(option.title), \(context.displayDomain)"
        )
    }

    private func popupsRow(
        context: Context,
        dependencies: LoadDependencies
    ) -> SumiCurrentSitePermissionRow {
        let descriptor = SumiPermissionIconCatalog.icon(for: .popups)
        let key = context.key(for: .popups)
        let option = option(for: record(for: key), defaultOption: .default)
        let records = context.pageId.map {
            dependencies.blockedPopupStore.records(forPageId: $0)
        } ?? []
        let count = records.reduce(0) { $0 + $1.attemptCount }

        return SumiCurrentSitePermissionRow(
            id: "popups",
            kind: .popups,
            title: "Pop-ups and redirects",
            subtitle: count > 0
                ? "\(count) blocked popup\(count == 1 ? "" : "s")"
                : popupSubtitle(for: option, isEphemeralProfile: context.isEphemeralProfile),
            iconName: descriptor.chromeIconName,
            fallbackSystemName: descriptor.fallbackSystemName,
            currentOption: option,
            availableOptions: [.default, .allow, .block],
            isEditable: true,
            recentEventCount: count,
            accessibilityLabel: "Pop-ups and redirects, \(option.title), \(context.displayDomain)"
        )
    }

    private func externalAppRows(
        context: Context,
        dependencies: LoadDependencies
    ) -> [SumiCurrentSitePermissionRow] {
        let descriptor = SumiPermissionIconCatalog.icon(for: .externalScheme(""))
        var rows: [SumiCurrentSitePermissionRow] = [
            SumiCurrentSitePermissionRow(
                id: "external-apps",
                kind: .externalApps,
                title: SumiCurrentSitePermissionsStrings.externalAppsTitle,
                subtitle: SumiCurrentSitePermissionsStrings.externalAppsDefault,
                iconName: descriptor.chromeIconName,
                fallbackSystemName: descriptor.fallbackSystemName,
                currentOption: .ask,
                availableOptions: [],
                isEditable: false,
                accessibilityLabel: "External app links, ask before opening external apps, \(context.displayDomain)"
            ),
        ]

        var schemes = Set<String>()
        for record in storedRecords where isCurrentSite(record.key, context: context) {
            if case .externalScheme(let scheme) = record.key.permissionType {
                schemes.insert(SumiPermissionType.normalizedExternalScheme(scheme))
            }
        }

        let recentRecords = context.pageId.map {
            dependencies.externalSchemeSessionStore.records(forPageId: $0)
        } ?? []
        for record in recentRecords
            where record.requestingOrigin.identity == context.origin.identity
                && record.topOrigin.identity == context.origin.identity
        {
            schemes.insert(SumiPermissionType.normalizedExternalScheme(record.scheme))
        }

        for scheme in schemes.sorted() {
            let permissionType = SumiPermissionType.externalScheme(scheme)
            let key = context.key(for: permissionType)
            let option = option(for: record(for: key), defaultOption: .ask)
            let recentCount = recentRecords
                .filter { SumiPermissionType.normalizedExternalScheme($0.scheme) == scheme }
                .reduce(0) { $0 + $1.attemptCount }
            rows.append(
                SumiCurrentSitePermissionRow(
                    id: "external-scheme-\(scheme)",
                    kind: .externalScheme(scheme),
                    title: "\(scheme) links",
                    subtitle: recentCount > 0
                        ? "\(recentCount) recent attempt\(recentCount == 1 ? "" : "s")"
                        : subtitle(option: option, recentEventCount: 0, isEphemeralProfile: context.isEphemeralProfile),
                    iconName: descriptor.chromeIconName,
                    fallbackSystemName: descriptor.fallbackSystemName,
                    currentOption: option,
                    availableOptions: [.ask, .allow, .block],
                    isEditable: true,
                    recentEventCount: recentCount,
                    accessibilityLabel: "\(scheme) external app links, \(option.title), \(context.displayDomain)"
                )
            )
        }

        return rows
    }

    private func autoplayRow(
        context: Context,
        profile: Profile?,
        reloadRequired: Bool,
        autoplayStore: any SumiCurrentSiteAutoplayPolicyManaging
    ) -> SumiCurrentSitePermissionRow {
        let policy = autoplayStore.explicitPolicy(
            for: context.mainFrameURL ?? context.visibleURL ?? context.committedURL,
            profile: profile
        ) ?? .default
        let option = option(for: policy)
        let descriptor = SumiPermissionIconCatalog.icon(
            for: .autoplay,
            visualStyle: reloadRequired ? .reloadRequired : .neutral
        )

        return SumiCurrentSitePermissionRow(
            id: "autoplay",
            kind: .autoplay,
            title: SumiPermissionType.autoplay.displayLabel,
            subtitle: reloadRequired ? "Reload required" : option.title,
            iconName: descriptor.chromeIconName,
            fallbackSystemName: descriptor.fallbackSystemName,
            currentOption: option,
            availableOptions: [.default, .allowAll, .blockAudible, .blockAll],
            isEditable: true,
            runtimeStatus: reloadRequired ? "Reload required" : nil,
            reloadRequired: reloadRequired,
            accessibilityLabel: "Autoplay, \(option.title), \(context.displayDomain)"
        )
    }

    private func filePickerRow(
        context: Context,
        dependencies: LoadDependencies
    ) -> SumiCurrentSitePermissionRow {
        let descriptor = SumiPermissionIconCatalog.icon(for: .filePicker)
        let count = recentEventCount(for: .filePicker, context: context, dependencies: dependencies)
        let subtitle = count > 0
            ? "File chooser used this visit"
            : SumiCurrentSitePermissionsStrings.fileChooserAlwaysAsks
        return SumiCurrentSitePermissionRow(
            id: "file-picker",
            kind: .filePicker,
            title: SumiCurrentSitePermissionsStrings.fileChooserTitle,
            subtitle: subtitle,
            iconName: descriptor.chromeIconName,
            fallbackSystemName: descriptor.fallbackSystemName,
            currentOption: nil,
            availableOptions: [],
            isEditable: false,
            runtimeStatus: SumiCurrentSitePermissionsStrings.fileChooserExplanation,
            recentEventCount: count,
            accessibilityLabel: "File chooser, always asks, \(context.displayDomain)"
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

    private func record(for key: SumiPermissionKey) -> SumiPermissionStoreRecord? {
        storedRecords.first {
            $0.key.persistentIdentity == key.persistentIdentity
                && $0.key.isEphemeralProfile == key.isEphemeralProfile
                && $0.decision.persistence != .oneTime
        }
    }

    private func activeOneTimeRecord(
        for key: SumiPermissionKey,
        context: Context
    ) -> SumiPermissionStoreRecord? {
        transientRecords.first {
            $0.key.persistentIdentity == key.persistentIdentity
                && $0.key.isEphemeralProfile == key.isEphemeralProfile
                && $0.key.transientPageId == context.pageId
                && $0.decision.persistence == .oneTime
                && $0.decision.state == .allow
        }
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

    private func option(
        for record: SumiPermissionStoreRecord?,
        defaultOption: SumiCurrentSitePermissionOption
    ) -> SumiCurrentSitePermissionOption {
        guard let state = record?.decision.state else { return defaultOption }
        switch state {
        case .ask:
            return defaultOption
        case .allow:
            return .allow
        case .deny:
            return .block
        }
    }

    private func option(for policy: SumiAutoplayPolicy) -> SumiCurrentSitePermissionOption {
        switch policy {
        case .default:
            return .default
        case .allowAll:
            return .allowAll
        case .blockAudible:
            return .blockAudible
        case .blockAll:
            return .blockAll
        }
    }

    private func subtitle(
        option: SumiCurrentSitePermissionOption,
        recentEventCount: Int,
        isEphemeralProfile: Bool,
        hasActiveOneTimeGrant: Bool = false
    ) -> String {
        if hasActiveOneTimeGrant {
            return "Allowed this time"
        }
        if recentEventCount > 0 {
            return "\(recentEventCount) recent event\(recentEventCount == 1 ? "" : "s")"
        }
        if isEphemeralProfile, option == .allow || option == .block {
            return "\(option.title) for this session"
        }
        return option.title
    }

    private func popupSubtitle(
        for option: SumiCurrentSitePermissionOption,
        isEphemeralProfile: Bool
    ) -> String {
        switch option {
        case .default:
            return "Block background pop-ups"
        case .allow, .block:
            return isEphemeralProfile ? "\(option.title) for this session" : option.title
        default:
            return option.title
        }
    }

    private func systemStatus(
        from snapshot: SumiSystemPermissionSnapshot?
    ) -> (text: String?, showsSettings: Bool) {
        guard let snapshot else { return (nil, false) }
        switch snapshot.state {
        case .authorized:
            return (nil, false)
        case .notDetermined:
            return ("macOS has not been asked yet", false)
        case .denied, .restricted, .systemDisabled:
            return (snapshot.reason, snapshot.shouldOpenSystemSettings)
        case .unavailable, .missingUsageDescription, .missingEntitlement:
            return (snapshot.reason, false)
        }
    }

    private func runtimeStatus(
        for state: SumiMediaCaptureRuntimeState?
    ) -> String? {
        switch state {
        case .active:
            return "Active"
        case .muted:
            return "Muted"
        case .stopping:
            return "Stopping"
        case .revoking:
            return "Revoking"
        case .unavailable:
            return "Unavailable"
        default:
            return nil
        }
    }

    private func runtimeStatus(
        for state: SumiGeolocationRuntimeState?
    ) -> String? {
        switch state {
        case .active:
            return "Active"
        case .paused:
            return "Paused"
        case .revoked:
            return "Revoked"
        case .unavailable:
            return "Unavailable"
        default:
            return nil
        }
    }

    private func recentEventCount(
        for permissionType: SumiPermissionType,
        context: Context,
        dependencies: LoadDependencies
    ) -> Int {
        guard let pageId = context.pageId else { return 0 }
        return dependencies.indicatorEventStore.records(forPageId: pageId)
            .filter { record in
                record.permissionTypes.contains { $0.identity == permissionType.identity }
            }
            .reduce(0) { $0 + $1.attemptCount }
    }

    private func systemKind(
        for row: SumiCurrentSitePermissionRow
    ) -> SumiSystemPermissionKind? {
        switch row.kind {
        case .sitePermission(.camera):
            return .camera
        case .sitePermission(.microphone):
            return .microphone
        case .sitePermission(.geolocation):
            return .geolocation
        case .sitePermission(.notifications):
            return .notifications
        case .sitePermission(.screenCapture):
            return .screenCapture
        default:
            return nil
        }
    }
}
