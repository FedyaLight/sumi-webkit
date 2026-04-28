import Foundation
import WebKit

@MainActor
final class SumiPermissionSettingsRepository {
    private enum Constants {
        static let cleanupPreferenceKey = "permissions.cleanup.automatic.enabled"
    }

    private let coordinator: any SumiPermissionCoordinating
    private let systemPermissionService: any SumiSystemPermissionService
    private let autoplayStore: SumiAutoplayPolicyStoreAdapter
    private let recentActivityStore: SumiPermissionRecentActivityStore
    private let blockedPopupStore: SumiBlockedPopupStore
    private let externalSchemeSessionStore: SumiExternalSchemeSessionStore
    private let indicatorEventStore: SumiPermissionIndicatorEventStore
    private let websiteDataCleanupService: (any SumiWebsiteDataCleanupServicing)?
    private let permissionCleanupService: SumiPermissionCleanupService?
    private let userDefaults: UserDefaults
    private let now: () -> Date

    init(
        coordinator: any SumiPermissionCoordinating,
        systemPermissionService: any SumiSystemPermissionService,
        autoplayStore: SumiAutoplayPolicyStoreAdapter? = nil,
        recentActivityStore: SumiPermissionRecentActivityStore,
        blockedPopupStore: SumiBlockedPopupStore,
        externalSchemeSessionStore: SumiExternalSchemeSessionStore,
        indicatorEventStore: SumiPermissionIndicatorEventStore,
        websiteDataCleanupService: (any SumiWebsiteDataCleanupServicing)? = nil,
        permissionCleanupService: SumiPermissionCleanupService? = nil,
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.coordinator = coordinator
        self.systemPermissionService = systemPermissionService
        self.autoplayStore = autoplayStore ?? .shared
        self.recentActivityStore = recentActivityStore
        self.blockedPopupStore = blockedPopupStore
        self.externalSchemeSessionStore = externalSchemeSessionStore
        self.indicatorEventStore = indicatorEventStore
        self.websiteDataCleanupService = websiteDataCleanupService ?? SumiWebsiteDataCleanupService.shared
        self.permissionCleanupService = permissionCleanupService
        self.userDefaults = userDefaults
        self.now = now
    }

    convenience init(browserManager: BrowserManager) {
        self.init(
            coordinator: browserManager.permissionCoordinator,
            systemPermissionService: browserManager.systemPermissionService,
            autoplayStore: .shared,
            recentActivityStore: browserManager.permissionRecentActivityStore,
            blockedPopupStore: browserManager.blockedPopupStore,
            externalSchemeSessionStore: browserManager.externalSchemeSessionStore,
            indicatorEventStore: browserManager.permissionIndicatorEventStore,
            websiteDataCleanupService: SumiWebsiteDataCleanupService.shared,
            permissionCleanupService: browserManager.permissionCleanupService
        )
    }

    var cleanupSettings: SumiPermissionCleanupSettings {
        get {
            SumiPermissionCleanupSettings(
                isAutomaticCleanupEnabled: isAutomaticCleanupEnabled()
            )
        }
        set {
            userDefaults.set(
                newValue.isAutomaticCleanupEnabled,
                forKey: Constants.cleanupPreferenceKey
            )
        }
    }

    func cleanupSettings(profile: SumiPermissionSettingsProfileContext) -> SumiPermissionCleanupSettings {
        let enabled = isAutomaticCleanupEnabled()
        guard let permissionCleanupService else {
            return SumiPermissionCleanupSettings(isAutomaticCleanupEnabled: enabled)
        }
        return permissionCleanupService.settings(
            isAutomaticCleanupEnabled: enabled,
            profilePartitionId: profile.profilePartitionId
        )
    }

    func setAutomaticCleanupEnabled(
        _ isEnabled: Bool,
        profile: SumiPermissionSettingsProfileContext
    ) {
        userDefaults.set(isEnabled, forKey: Constants.cleanupPreferenceKey)
        cleanupSettings = SumiPermissionCleanupSettings(isAutomaticCleanupEnabled: isEnabled)
        _ = profile
    }

    @discardableResult
    func runAutomaticCleanupIfNeeded(
        profile: SumiPermissionSettingsProfileContext
    ) async -> SumiPermissionCleanupResult {
        guard let permissionCleanupService else {
            return .disabled(profilePartitionId: profile.profilePartitionId, now: now())
        }
        return await permissionCleanupService.runIfNeeded(
            profile: profile,
            settings: cleanupSettings(profile: profile)
        )
    }

    @discardableResult
    func runCleanup(
        profile: SumiPermissionSettingsProfileContext,
        force: Bool = false
    ) async -> SumiPermissionCleanupResult {
        guard let permissionCleanupService else {
            return .disabled(profilePartitionId: profile.profilePartitionId, now: now())
        }
        return await permissionCleanupService.run(
            profile: profile,
            settings: cleanupSettings(profile: profile),
            force: force
        )
    }

    func permissionRecords(
        profile: SumiPermissionSettingsProfileContext
    ) async throws -> [SumiPermissionStoreRecord] {
        let coordinatorRecords = try await coordinator.siteDecisionRecords(
            profilePartitionId: profile.profilePartitionId,
            isEphemeralProfile: profile.isEphemeralProfile
        )
        let autoplayRecords = try await autoplayStore.siteDecisionRecords(
            profilePartitionId: profile.profilePartitionId,
            isEphemeralProfile: profile.isEphemeralProfile
        )
        return Self.deduplicated(records: coordinatorRecords + autoplayRecords)
            .filter { $0.decision.persistence == .persistent }
    }

    func categoryRows(
        profile: SumiPermissionSettingsProfileContext
    ) async throws -> [SumiSiteSettingsCategoryRow] {
        let records = try await permissionRecords(profile: profile)
        return SumiSiteSettingsPermissionCategory.allCases.map { category in
            let count = records.filter { category.matches($0.key.permissionType) }.count
            return SumiSiteSettingsCategoryRow(category: category, exceptionCount: count)
        }
    }

    func siteRows(
        profile: SumiPermissionSettingsProfileContext,
        searchText: String = ""
    ) async throws -> [SumiSiteSettingsSiteRow] {
        let records = try await permissionRecords(profile: profile)
        let recent = recentRecords(profile: profile)
        let grouped = Dictionary(grouping: records, by: { SumiPermissionSiteScope(record: $0) })
        let rows: [SumiSiteSettingsSiteRow] = grouped.map { scope, records in
            let recentCount = recent
                .filter {
                    $0.requestingOrigin.identity == scope.requestingOrigin.identity
                        && $0.topOrigin.identity == scope.topOrigin.identity
                }
                .reduce(0) { $0 + $1.count }
            return SumiSiteSettingsSiteRow(
                scope: scope,
                storedPermissionCount: records.count,
                recentActivityCount: recentCount,
                dataSummary: nil
            )
        }
        .sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }

        return filter(rows: rows, searchText: searchText)
    }

    func categoryDetail(
        category: SumiSiteSettingsPermissionCategory,
        profile: SumiPermissionSettingsProfileContext,
        searchText: String = ""
    ) async throws -> SumiSiteSettingsCategoryDetail {
        let records = try await permissionRecords(profile: profile)
            .filter { category.matches($0.key.permissionType) }
        let rows = records
            .map { row(for: $0, category: category) }
            .filter { matches(row: $0, searchText: searchText) }
            .sorted { lhs, rhs in
                lhs.scope.title.localizedStandardCompare(rhs.scope.title) == .orderedAscending
            }
        let snapshot = await systemSnapshot(for: category)
        return SumiSiteSettingsCategoryDetail(
            category: category,
            defaultBehaviorText: category.defaultBehaviorText,
            systemSnapshot: snapshot,
            rows: rows
        )
    }

    func siteDetail(
        scope: SumiPermissionSiteScope,
        profile: SumiPermissionSettingsProfileContext,
        profileObject: Profile? = nil,
        includeDataSummary: Bool = true
    ) async throws -> SumiSiteSettingsSiteDetail {
        let records = try await permissionRecords(profile: profile)
            .filter { isRecord($0, in: scope) }
        let recordsByIdentity = Dictionary(uniqueKeysWithValues: records.map { ($0.key.persistentIdentity, $0) })
        let systemSnapshots = await systemSnapshots()
        var rows: [SumiSiteSettingsPermissionRow] = []

        for category in SumiSiteSettingsPermissionCategory.allCases {
            switch category {
            case .externalScheme:
                rows.append(externalAppSummaryRow(scope: scope))
                rows.append(contentsOf: externalSchemeRows(records: records, scope: scope))
            case .autoplay:
                let key = scope.key(for: .autoplay)
                rows.append(autoplayRow(record: recordsByIdentity[key.persistentIdentity], scope: scope))
            case .popups:
                let key = scope.key(for: .popups)
                rows.append(
                    row(
                        for: recordsByIdentity[key.persistentIdentity],
                        category: .popups,
                        scope: scope,
                        systemSnapshot: nil
                    )
                )
            default:
                guard let permissionType = category.basePermissionType else { continue }
                let key = scope.key(for: permissionType)
                rows.append(
                    row(
                        for: recordsByIdentity[key.persistentIdentity],
                        category: category,
                        scope: scope,
                        systemSnapshot: category.systemKind.flatMap { systemSnapshots[$0] }
                    )
                )
            }
        }

        let filePickerRow = filePickerRowIfNeeded(scope: scope, profile: profile)
        let dataSummary = includeDataSummary
            ? await dataSummary(for: scope, profileObject: profileObject)
            : nil
        return SumiSiteSettingsSiteDetail(
            scope: scope,
            profileName: profile.profileName,
            dataSummary: dataSummary,
            permissionRows: rows,
            filePickerRow: filePickerRow
        )
    }

    func recentActivity(
        profile: SumiPermissionSettingsProfileContext,
        limit: Int = 10
    ) -> [SumiSiteSettingsRecentActivityItem] {
        recentRecords(profile: profile)
            .prefix(max(0, limit))
            .map { item(for: $0, profileName: profile.profileName) }
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
            let key = row.scope.key(for: .autoplay)
            switch option {
            case .default:
                try await autoplayStore.resetPolicy(for: key)
                recentActivityStore.recordSettingsChange(
                    displayDomain: row.scope.displayDomain,
                    key: key,
                    state: nil,
                    detail: "privacy-site-settings-autoplay-reset",
                    now: now()
                )
            case .allowAll:
                try await autoplayStore.setPolicy(.allowAll, for: key, source: .user, now: now())
                recentActivityStore.recordSettingsChange(
                    displayDomain: row.scope.displayDomain,
                    key: key,
                    state: .allow,
                    detail: "privacy-site-settings-autoplay-allow-all",
                    now: now()
                )
            case .blockAudible:
                try await autoplayStore.setPolicy(.blockAudible, for: key, source: .user, now: now())
                recentActivityStore.recordSettingsChange(
                    displayDomain: row.scope.displayDomain,
                    key: key,
                    state: .deny,
                    detail: "privacy-site-settings-autoplay-block-audible",
                    now: now()
                )
            case .blockAll:
                try await autoplayStore.setPolicy(.blockAll, for: key, source: .user, now: now())
                recentActivityStore.recordSettingsChange(
                    displayDomain: row.scope.displayDomain,
                    key: key,
                    state: .deny,
                    detail: "privacy-site-settings-autoplay-block-all",
                    now: now()
                )
            case .ask, .allow, .block:
                throw SumiPermissionSiteDecisionError.unsupportedPermission("autoplay")
            }
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
        let records = try await permissionRecords(profile: profile)
            .filter { isRecord($0, in: scope) }
        for record in records {
            try await reset(key: record.key, displayDomain: scope.displayDomain)
        }
    }

    func deleteSiteData(
        scope: SumiPermissionSiteScope,
        profile: Profile
    ) async {
        guard let host = scope.requestingOrigin.host,
              let websiteDataCleanupService
        else { return }

        await websiteDataCleanupService.removeWebsiteDataForExactHost(
            host,
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypesExceptCookies,
            includingCookies: true,
            in: profile.dataStore
        )
        await profile.refreshDataStoreStats()
    }

    @discardableResult
    func openSystemSettings(for kind: SumiSystemPermissionKind) async -> Bool {
        await systemPermissionService.openSystemSettings(for: kind)
    }

    func systemSnapshot(
        for category: SumiSiteSettingsPermissionCategory
    ) async -> SumiSystemPermissionSnapshot? {
        guard let kind = category.systemKind else { return nil }
        return await systemPermissionService.authorizationSnapshot(for: kind)
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
                detail: "privacy-site-settings",
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
                detail: "privacy-site-settings",
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
            detail: "privacy-site-settings-reset",
            now: now()
        )
    }

    private func row(
        for record: SumiPermissionStoreRecord,
        category: SumiSiteSettingsPermissionCategory
    ) -> SumiSiteSettingsPermissionRow {
        row(
            for: record,
            category: category,
            scope: SumiPermissionSiteScope(record: record),
            systemSnapshot: nil
        )
    }

    private func row(
        for record: SumiPermissionStoreRecord?,
        category: SumiSiteSettingsPermissionCategory,
        scope: SumiPermissionSiteScope,
        systemSnapshot: SumiSystemPermissionSnapshot?
    ) -> SumiSiteSettingsPermissionRow {
        let permissionType = record?.key.permissionType ?? category.basePermissionType ?? .externalScheme("")
        let option = option(for: record, defaultOption: category.defaultOption)
        let system = systemStatus(from: systemSnapshot)
        let disabledReason = disabledReason(for: permissionType, scope: scope)
        let isEditable = disabledReason == nil
        let id = record?.key.persistentIdentity ?? scope.key(for: permissionType).persistentIdentity
        return SumiSiteSettingsPermissionRow(
            id: id,
            kind: kind(for: permissionType),
            scope: scope,
            category: category,
            title: title(for: category, permissionType: permissionType),
            subtitle: subtitle(option: option, record: record, isEphemeralProfile: scope.isEphemeralProfile),
            systemImage: category.systemImage,
            currentOption: option,
            availableOptions: options(for: category),
            isEditable: isEditable,
            disabledReason: disabledReason,
            systemStatus: system.text,
            showsSystemSettingsAction: system.showsSettings,
            isStoredException: record != nil,
            updatedAt: record?.decision.updatedAt,
            accessibilityLabel: "\(title(for: category, permissionType: permissionType)), \(option.title), \(scope.title)"
        )
    }

    private func autoplayRow(
        record: SumiPermissionStoreRecord?,
        scope: SumiPermissionSiteScope
    ) -> SumiSiteSettingsPermissionRow {
        let policy = record.flatMap { SumiAutoplayDecisionMapper.policy(from: $0.decision) } ?? .default
        let option = option(for: policy)
        return SumiSiteSettingsPermissionRow(
            id: record?.key.persistentIdentity ?? scope.key(for: .autoplay).persistentIdentity,
            kind: .autoplay,
            scope: scope,
            category: .autoplay,
            title: SumiSiteSettingsPermissionCategory.autoplay.title,
            subtitle: option.title,
            systemImage: SumiSiteSettingsPermissionCategory.autoplay.systemImage,
            currentOption: option,
            availableOptions: [.default, .allowAll, .blockAudible, .blockAll],
            isEditable: true,
            disabledReason: nil,
            systemStatus: nil,
            showsSystemSettingsAction: false,
            isStoredException: record != nil,
            updatedAt: record?.decision.updatedAt,
            accessibilityLabel: "Autoplay, \(option.title), \(scope.title)"
        )
    }

    private func externalAppSummaryRow(scope: SumiPermissionSiteScope) -> SumiSiteSettingsPermissionRow {
        SumiSiteSettingsPermissionRow(
            id: "\(scope.id)|external-apps-summary",
            kind: .externalScheme(""),
            scope: scope,
            category: .externalScheme,
            title: SumiSiteSettingsPermissionCategory.externalScheme.title,
            subtitle: SumiSiteSettingsPermissionCategory.externalScheme.defaultBehaviorText,
            systemImage: SumiSiteSettingsPermissionCategory.externalScheme.systemImage,
            currentOption: nil,
            availableOptions: [],
            isEditable: false,
            disabledReason: "Scheme-specific exceptions appear after a site attempts to open an external app link.",
            systemStatus: nil,
            showsSystemSettingsAction: false,
            isStoredException: false,
            updatedAt: nil,
            accessibilityLabel: "External app links, ask before opening external apps, \(scope.title)"
        )
    }

    private func externalSchemeRows(
        records: [SumiPermissionStoreRecord],
        scope: SumiPermissionSiteScope
    ) -> [SumiSiteSettingsPermissionRow] {
        records.compactMap { record in
            guard case .externalScheme = record.key.permissionType else { return nil }
            return row(
                for: record,
                category: .externalScheme,
                scope: scope,
                systemSnapshot: nil
            )
        }
        .sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func filePickerRowIfNeeded(
        scope: SumiPermissionSiteScope,
        profile: SumiPermissionSettingsProfileContext
    ) -> SumiSiteSettingsPermissionRow? {
        let count = indicatorRecords(profile: profile)
            .filter {
                $0.permissionTypes.contains(.filePicker)
                    && ($0.requestingOrigin?.identity ?? "") == scope.requestingOrigin.identity
                    && ($0.topOrigin?.identity ?? "") == scope.topOrigin.identity
            }
            .reduce(0) { $0 + $1.attemptCount }
        guard count > 0 else { return nil }
        return SumiSiteSettingsPermissionRow(
            id: "\(scope.id)|file-picker",
            kind: .filePicker,
            scope: scope,
            category: nil,
            title: "File picker",
            subtitle: "File chooser always asks. Recent file chooser activity exists for this site.",
            systemImage: "folder",
            currentOption: nil,
            availableOptions: [],
            isEditable: false,
            disabledReason: nil,
            systemStatus: nil,
            showsSystemSettingsAction: false,
            isStoredException: false,
            updatedAt: nil,
            accessibilityLabel: "File picker, always asks, \(scope.title)"
        )
    }

    private func systemSnapshots() async -> [SumiSystemPermissionKind: SumiSystemPermissionSnapshot] {
        var snapshots: [SumiSystemPermissionKind: SumiSystemPermissionSnapshot] = [:]
        for kind in SumiSystemPermissionKind.allCases {
            snapshots[kind] = await systemPermissionService.authorizationSnapshot(for: kind)
        }
        return snapshots
    }

    private func systemStatus(
        from snapshot: SumiSystemPermissionSnapshot?
    ) -> (text: String?, showsSettings: Bool) {
        guard let snapshot else { return (nil, false) }
        switch snapshot.state {
        case .authorized:
            return ("macOS authorized", false)
        case .notDetermined:
            return ("Not determined by macOS", false)
        case .denied, .restricted:
            return ("Blocked by macOS", snapshot.shouldOpenSystemSettings)
        case .systemDisabled:
            return ("Location Services disabled", snapshot.shouldOpenSystemSettings)
        case .unavailable:
            return ("Unavailable", false)
        case .missingUsageDescription, .missingEntitlement:
            return (snapshot.reason, false)
        }
    }

    private func disabledReason(
        for permissionType: SumiPermissionType,
        scope: SumiPermissionSiteScope
    ) -> String? {
        scope.requestingOrigin.supportsSensitiveWebPermission(permissionType)
            ? nil
            : "Requires a supported web origin"
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

    private func options(
        for category: SumiSiteSettingsPermissionCategory
    ) -> [SumiCurrentSitePermissionOption] {
        switch category {
        case .geolocation, .camera, .microphone, .screenCapture, .notifications, .storageAccess, .externalScheme:
            return [.ask, .allow, .block]
        case .popups:
            return [.default, .allow, .block]
        case .autoplay:
            return [.default, .allowAll, .blockAudible, .blockAll]
        }
    }

    private func subtitle(
        option: SumiCurrentSitePermissionOption,
        record: SumiPermissionStoreRecord?,
        isEphemeralProfile: Bool
    ) -> String {
        guard record != nil else { return option.title }
        if isEphemeralProfile, option == .allow || option == .block {
            return "\(option.title) for this session"
        }
        return option.title
    }

    private func title(
        for category: SumiSiteSettingsPermissionCategory,
        permissionType: SumiPermissionType
    ) -> String {
        switch permissionType {
        case .externalScheme(let scheme):
            return "\(SumiPermissionType.normalizedExternalScheme(scheme)) links"
        default:
            return category.title
        }
    }

    private func kind(for permissionType: SumiPermissionType) -> SumiSiteSettingsPermissionRow.Kind {
        switch permissionType {
        case .popups:
            return .popups
        case .externalScheme(let scheme):
            return .externalScheme(scheme)
        case .autoplay:
            return .autoplay
        case .filePicker:
            return .filePicker
        default:
            return .sitePermission(permissionType)
        }
    }

    private func item(
        for record: SumiPermissionRecentActivityRecord,
        profileName: String
    ) -> SumiSiteSettingsRecentActivityItem {
        let category = SumiSiteSettingsPermissionCategory.allCases.first {
            $0.matches(record.permissionType)
        }
        let originSummary = record.requestingOrigin.identity == record.topOrigin.identity
            ? record.requestingOrigin.identity
            : "\(record.requestingOrigin.displayDomain) embedded on \(record.topOrigin.displayDomain)"
        var item = SumiSiteSettingsRecentActivityItem(
            id: record.id,
            displayDomain: record.displayDomain,
            originSummary: originSummary,
            profileName: profileName,
            permissionTitle: category?.title ?? record.permissionType.displayLabel,
            actionTitle: record.action.displayLabel,
            timestamp: record.createdAt,
            systemImage: category?.systemImage ?? "globe",
            count: record.count
        )
        if record.action == .autoRevoked {
            let permissionTitle = category?.title ?? record.permissionType.displayLabel
            item.customTitle = "\(permissionTitle) permission removed for \(record.displayDomain)"
            item.customSubtitle = "Because the site has not used it recently"
        }
        return item
    }

    private func recentRecords(
        profile: SumiPermissionSettingsProfileContext
    ) -> [SumiPermissionRecentActivityRecord] {
        let normalizedProfileId = profile.profilePartitionId
        var records = recentActivityStore.records(
            profilePartitionId: normalizedProfileId,
            isEphemeralProfile: profile.isEphemeralProfile,
            limit: 100
        )

        records.append(contentsOf: blockedPopupStore.allRecords().compactMap { record in
            guard record.profilePartitionId == normalizedProfileId,
                  record.isEphemeralProfile == profile.isEphemeralProfile
            else { return nil }
            return SumiPermissionRecentActivityRecord(
                id: record.id,
                displayDomain: record.requestingOrigin.displayDomain,
                requestingOrigin: record.requestingOrigin,
                topOrigin: record.topOrigin,
                profilePartitionId: record.profilePartitionId,
                isEphemeralProfile: record.isEphemeralProfile,
                permissionType: .popups,
                action: .blockedPopup,
                detail: record.reason.rawValue,
                createdAt: record.lastBlockedAt,
                count: record.attemptCount
            )
        })

        records.append(contentsOf: externalSchemeSessionStore.allRecords().compactMap { record in
            guard record.profilePartitionId == normalizedProfileId,
                  record.isEphemeralProfile == profile.isEphemeralProfile
            else { return nil }
            return SumiPermissionRecentActivityRecord(
                id: record.id,
                displayDomain: record.requestingOrigin.displayDomain,
                requestingOrigin: record.requestingOrigin,
                topOrigin: record.topOrigin,
                profilePartitionId: record.profilePartitionId,
                isEphemeralProfile: record.isEphemeralProfile,
                permissionType: .externalScheme(record.scheme),
                action: record.result == .opened ? .openedExternalApp : .blocked,
                detail: record.reason,
                createdAt: record.lastAttemptAt,
                count: record.attemptCount
            )
        })

        records.append(contentsOf: indicatorRecords(profile: profile).compactMap { record in
            guard let requestingOrigin = record.requestingOrigin,
                  let topOrigin = record.topOrigin
            else { return nil }
            let action: SumiPermissionRecentActivityRecord.Action = record.category == .systemBlocked
                ? .systemBlocked
                : .blocked
            return SumiPermissionRecentActivityRecord(
                id: record.id,
                displayDomain: record.displayDomain,
                requestingOrigin: requestingOrigin,
                topOrigin: topOrigin,
                profilePartitionId: record.profilePartitionId,
                isEphemeralProfile: record.isEphemeralProfile,
                permissionType: record.primaryPermissionType,
                action: action,
                detail: record.reason,
                createdAt: record.createdAt,
                count: record.attemptCount
            )
        })

        return records.sorted { $0.createdAt > $1.createdAt }
    }

    private func indicatorRecords(
        profile: SumiPermissionSettingsProfileContext
    ) -> [SumiPermissionIndicatorEventRecord] {
        indicatorEventStore.allRecords(now: now()).filter {
            $0.profilePartitionId == profile.profilePartitionId
                && $0.isEphemeralProfile == profile.isEphemeralProfile
        }
    }

    private func dataSummary(
        for scope: SumiPermissionSiteScope,
        profileObject: Profile?
    ) async -> SumiSiteSettingsDataSummary? {
        guard let websiteDataCleanupService,
              let profileObject,
              let host = scope.requestingOrigin.host
        else { return nil }
        let entries = await websiteDataCleanupService.fetchSiteDataEntries(
            forDomain: host,
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypesExceptCookies,
            in: profileObject.dataStore
        )
        let cookieCount = entries.reduce(0) { $0 + $1.cookieCount }
        let recordCount = entries.reduce(0) { $0 + $1.recordCount }
        if cookieCount == 0, recordCount == 0 {
            return SumiSiteSettingsDataSummary(displayText: "No stored site data found", canDelete: false)
        }
        return SumiSiteSettingsDataSummary(
            displayText: "\(cookieCount) cookie\(cookieCount == 1 ? "" : "s"), \(recordCount) data record\(recordCount == 1 ? "" : "s")",
            canDelete: true
        )
    }

    private func isRecord(_ record: SumiPermissionStoreRecord, in scope: SumiPermissionSiteScope) -> Bool {
        record.key.profilePartitionId == scope.profilePartitionId
            && record.key.isEphemeralProfile == scope.isEphemeralProfile
            && record.key.requestingOrigin.identity == scope.requestingOrigin.identity
            && record.key.topOrigin.identity == scope.topOrigin.identity
    }

    private func filter(
        rows: [SumiSiteSettingsSiteRow],
        searchText: String
    ) -> [SumiSiteSettingsSiteRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return rows }
        return rows.filter {
            $0.title.lowercased().contains(query)
                || $0.scope.requestingOrigin.identity.lowercased().contains(query)
                || $0.scope.topOrigin.identity.lowercased().contains(query)
        }
    }

    private func matches(
        row: SumiSiteSettingsPermissionRow,
        searchText: String
    ) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return row.title.lowercased().contains(query)
            || row.scope.title.lowercased().contains(query)
            || row.scope.requestingOrigin.identity.lowercased().contains(query)
            || row.scope.topOrigin.identity.lowercased().contains(query)
    }

    private static func deduplicated(
        records: [SumiPermissionStoreRecord]
    ) -> [SumiPermissionStoreRecord] {
        var byIdentity: [String: SumiPermissionStoreRecord] = [:]
        for record in records {
            byIdentity[record.key.persistentIdentity] = record
        }
        return Array(byIdentity.values)
    }

    private func isAutomaticCleanupEnabled() -> Bool {
        userDefaults.bool(forKey: Constants.cleanupPreferenceKey)
    }
}
