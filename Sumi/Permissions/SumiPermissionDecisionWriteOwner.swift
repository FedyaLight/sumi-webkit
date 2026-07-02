import Foundation

/// Owns writes of site permission decisions from the settings surface:
/// applying a chosen option, removing exceptions, and resetting a site's
/// permissions, while recording the change in the activity stores.
@MainActor
final class SumiPermissionDecisionWriteOwner {
    private let coordinator: any SumiPermissionCoordinating
    private let autoplayStore: SumiAutoplayPolicyStoreAdapter
    private let recentActivityStore: SumiPermissionRecentActivityStore
    private let siteActivityStore: SumiPermissionSiteActivityStore
    private let aggregator: SumiPermissionRecordAggregator
    private let now: () -> Date

    init(
        coordinator: any SumiPermissionCoordinating,
        autoplayStore: SumiAutoplayPolicyStoreAdapter,
        recentActivityStore: SumiPermissionRecentActivityStore,
        siteActivityStore: SumiPermissionSiteActivityStore,
        aggregator: SumiPermissionRecordAggregator,
        now: @escaping () -> Date
    ) {
        self.coordinator = coordinator
        self.autoplayStore = autoplayStore
        self.recentActivityStore = recentActivityStore
        self.siteActivityStore = siteActivityStore
        self.aggregator = aggregator
        self.now = now
    }

    func setOption(
        _ option: SumiCurrentSitePermissionOption,
        for row: SumiSiteSettingsPermissionRow
    ) async throws {
        switch row.kind {
        case .sitePermission(let permissionType):
            try await writeSiteDecision(
                option,
                key: row.scope.key(for: permissionType),
                displayDomain: row.scope.displayDomain
            )
        case .popups:
            try await writeSiteDecision(
                option,
                key: row.scope.key(for: .popups),
                displayDomain: row.scope.displayDomain
            )
        case .externalScheme(let scheme):
            try await writeSiteDecision(
                option,
                key: row.scope.key(for: .externalScheme(scheme)),
                displayDomain: row.scope.displayDomain
            )
        case .autoplay:
            try await writeAutoplayDecision(option, for: row)
        case .filePicker:
            throw SumiPermissionSiteDecisionError.unsupportedPermission("file-picker")
        }
    }

    func removeException(for row: SumiSiteSettingsPermissionRow) async throws {
        switch row.kind {
        case .sitePermission(let permissionType):
            try await reset(key: row.scope.key(for: permissionType), displayDomain: row.scope.displayDomain)
        case .popups:
            try await reset(key: row.scope.key(for: .popups), displayDomain: row.scope.displayDomain)
        case .externalScheme(let scheme):
            try await reset(key: row.scope.key(for: .externalScheme(scheme)), displayDomain: row.scope.displayDomain)
        case .autoplay:
            try await reset(key: row.scope.key(for: .autoplay), displayDomain: row.scope.displayDomain)
        case .filePicker:
            return
        }
    }

    func resetSitePermissions(
        scope: SumiPermissionSiteScope,
        profile: SumiPermissionSettingsProfileContext
    ) async throws {
        let records = try await aggregator.permissionRecords(profile: profile)
            .filter { aggregator.isRecord($0, in: scope) }
        for record in records {
            try await reset(key: record.key, displayDomain: scope.displayDomain)
        }
    }

    private func writeAutoplayDecision(
        _ option: SumiCurrentSitePermissionOption,
        for row: SumiSiteSettingsPermissionRow
    ) async throws {
        let key = row.scope.key(for: .autoplay)
        switch option {
        case .default:
            try await autoplayStore.resetPolicy(for: key)
            recentActivityStore.recordSettingsChange(
                displayDomain: row.scope.displayDomain,
                key: key,
                state: nil,
                now: now()
            )
            siteActivityStore.recordSettingsChange(
                displayDomain: row.scope.displayDomain,
                key: key,
                state: nil,
                autoplayPolicy: .default,
                reason: "privacy-site-settings-autoplay-default",
                now: now()
            )
        case .allowAll:
            try await autoplayStore.setPolicy(.allowAll, for: key, source: .user, now: now())
            recentActivityStore.recordSettingsChange(
                displayDomain: row.scope.displayDomain,
                key: key,
                state: .allow,
                now: now()
            )
            siteActivityStore.recordSettingsChange(
                displayDomain: row.scope.displayDomain,
                key: key,
                state: .allow,
                autoplayPolicy: .allowAll,
                reason: "privacy-site-settings-autoplay-allow-all",
                now: now()
            )
        case .blockAudible:
            try await autoplayStore.setPolicy(.blockAudible, for: key, source: .user, now: now())
            recentActivityStore.recordSettingsChange(
                displayDomain: row.scope.displayDomain,
                key: key,
                state: .deny,
                now: now()
            )
            siteActivityStore.recordSettingsChange(
                displayDomain: row.scope.displayDomain,
                key: key,
                state: .deny,
                autoplayPolicy: .blockAudible,
                reason: "privacy-site-settings-autoplay-block-audible",
                now: now()
            )
        case .blockAll:
            try await autoplayStore.setPolicy(.blockAll, for: key, source: .user, now: now())
            recentActivityStore.recordSettingsChange(
                displayDomain: row.scope.displayDomain,
                key: key,
                state: .deny,
                now: now()
            )
            siteActivityStore.recordSettingsChange(
                displayDomain: row.scope.displayDomain,
                key: key,
                state: .deny,
                autoplayPolicy: .blockAll,
                reason: "privacy-site-settings-autoplay-block-all",
                now: now()
            )
        case .ask, .allow, .block:
            throw SumiPermissionSiteDecisionError.unsupportedPermission("autoplay")
        }
    }

    private func writeSiteDecision(
        _ option: SumiCurrentSitePermissionOption,
        key: SumiPermissionKey,
        displayDomain: String
    ) async throws {
        switch option {
        case .ask, .default:
            try await reset(key: key, displayDomain: displayDomain)
        case .allow:
            try await coordinator.setSiteDecision(
                for: key,
                state: .allow,
                source: .user,
                reason: "privacy-site-settings"
            )
            recentActivityStore.recordSettingsChange(
                displayDomain: displayDomain,
                key: key,
                state: .allow,
                now: now()
            )
            siteActivityStore.recordSettingsChange(
                displayDomain: displayDomain,
                key: key,
                state: .allow,
                reason: "privacy-site-settings-allow",
                now: now()
            )
        case .block:
            try await coordinator.setSiteDecision(
                for: key,
                state: .deny,
                source: .user,
                reason: "privacy-site-settings"
            )
            recentActivityStore.recordSettingsChange(
                displayDomain: displayDomain,
                key: key,
                state: .deny,
                now: now()
            )
            siteActivityStore.recordSettingsChange(
                displayDomain: displayDomain,
                key: key,
                state: .deny,
                reason: "privacy-site-settings-block",
                now: now()
            )
        case .allowAll, .blockAudible, .blockAll:
            throw SumiPermissionSiteDecisionError.unsupportedPermission(key.permissionType.identity)
        }
    }

    private func reset(key: SumiPermissionKey, displayDomain: String) async throws {
        if key.permissionType == .autoplay {
            try await autoplayStore.resetPolicy(for: key)
        } else {
            try await coordinator.resetSiteDecision(for: key)
        }
        recentActivityStore.recordSettingsChange(
            displayDomain: displayDomain,
            key: key,
            state: nil,
            now: now()
        )
        siteActivityStore.recordSettingsChange(
            displayDomain: displayDomain,
            key: key,
            state: nil,
            autoplayPolicy: key.permissionType == .autoplay ? .default : nil,
            reason: "privacy-site-settings-reset",
            now: now()
        )
    }
}
