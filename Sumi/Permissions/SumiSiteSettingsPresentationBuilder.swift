import Foundation
import SumiDomain
import WebKit

/// Owns presentation assembly for the site settings surface: category and
/// site rows, category/site detail models, recent activity items, system
/// permission status text, and stored-data summaries.
@MainActor
final class SumiSiteSettingsPresentationBuilder {
    private let aggregator: SumiPermissionRecordAggregator
    private let systemPermissionService: any SumiSystemPermissionService
    private let websiteDataCleanupService: (any SumiWebsiteDataCleanupServicing)?

    init(
        aggregator: SumiPermissionRecordAggregator,
        systemPermissionService: any SumiSystemPermissionService,
        websiteDataCleanupService: (any SumiWebsiteDataCleanupServicing)?
    ) {
        self.aggregator = aggregator
        self.systemPermissionService = systemPermissionService
        self.websiteDataCleanupService = websiteDataCleanupService
    }

    func categoryRows(
        profile: SumiPermissionSettingsProfileContext
    ) async throws -> [SumiSiteSettingsCategoryRow] {
        let records = try await aggregator.permissionRecords(profile: profile)
        return SumiSiteSettingsPermissionCategory.allCases.map { category in
            let count = records.filter { category.matches($0.key.permissionType) }.count
            return SumiSiteSettingsCategoryRow(category: category, exceptionCount: count)
        }
    }

    func siteRows(
        profile: SumiPermissionSettingsProfileContext,
        searchText: String
    ) async throws -> [SumiSiteSettingsSiteRow] {
        let records = try await aggregator.permissionRecords(profile: profile)
        let recent = aggregator.recentRecords(profile: profile)
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
        searchText: String
    ) async throws -> SumiSiteSettingsCategoryDetail {
        let records = try await aggregator.permissionRecords(profile: profile)
            .filter { category.matches($0.key.permissionType) }
        let rows = records
            .map { row(for: $0, category: category) }
            .filter { matches(row: $0, searchText: searchText) }
            .sorted { lhs, rhs in
                lhs.scope.title.localizedStandardCompare(rhs.scope.title) == .orderedAscending
            }
        let snapshot = await systemSnapshot(for: category)
        return SumiSiteSettingsCategoryDetail(
            defaultBehaviorText: category.defaultBehaviorText,
            systemSnapshot: snapshot,
            rows: rows
        )
    }

    func siteDetail(
        scope: SumiPermissionSiteScope,
        profile: SumiPermissionSettingsProfileContext,
        profileObject: Profile?,
        includeDataSummary: Bool
    ) async throws -> SumiSiteSettingsSiteDetail {
        let records = try await aggregator.permissionRecords(profile: profile)
            .filter { aggregator.isRecord($0, in: scope) }
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
            profileName: profile.profileName,
            dataSummary: dataSummary,
            permissionRows: rows,
            filePickerRow: filePickerRow
        )
    }

    func recentActivity(
        profile: SumiPermissionSettingsProfileContext,
        limit: Int
    ) -> [SumiSiteSettingsRecentActivityItem] {
        aggregator.recentRecords(profile: profile)
            .prefix(max(0, limit))
            .map { item(for: $0, profileName: profile.profileName) }
    }

    func systemSnapshot(
        for category: SumiSiteSettingsPermissionCategory
    ) async -> SumiSystemPermissionSnapshot? {
        guard let kind = category.systemKind else { return nil }
        return await systemPermissionService.authorizationSnapshot(for: kind)
    }

    func dataSummary(
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
        let count = aggregator.indicatorRecords(profile: profile)
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
}
