import Foundation
import WebKit
import SumiDomain

/// Facade for the site settings surface. Composes the cleanup settings
/// owner, permission record aggregator, presentation builder, and decision
/// write owner behind the stable public API the settings UI consumes.
@MainActor
final class SumiPermissionSettingsRepository {
    private let systemPermissionService: any SumiSystemPermissionService
    private let websiteDataCleanupService: (any SumiWebsiteDataCleanupServicing)?
    private let cleanupSettingsOwner: SumiPermissionCleanupSettingsOwner
    private let aggregator: SumiPermissionRecordAggregator
    private let presentationBuilder: SumiSiteSettingsPresentationBuilder
    private let decisionWriteOwner: SumiPermissionDecisionWriteOwner

    init(
        coordinator: any SumiPermissionCoordinating,
        systemPermissionService: any SumiSystemPermissionService,
        autoplayStore: SumiAutoplayPolicyStoreAdapter,
        recentActivityStore: SumiPermissionRecentActivityStore,
        siteActivityStore: SumiPermissionSiteActivityStore,
        blockedPopupStore: SumiBlockedPopupStore,
        externalSchemeSessionStore: SumiExternalSchemeSessionStore,
        indicatorEventStore: SumiPermissionIndicatorEventStore,
        websiteDataCleanupService: (any SumiWebsiteDataCleanupServicing)? = nil,
        permissionCleanupService: SumiPermissionCleanupService? = nil,
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.systemPermissionService = systemPermissionService
        self.websiteDataCleanupService = websiteDataCleanupService
        self.cleanupSettingsOwner = SumiPermissionCleanupSettingsOwner(
            permissionCleanupService: permissionCleanupService,
            userDefaults: userDefaults,
            now: now
        )
        let aggregator = SumiPermissionRecordAggregator(
            coordinator: coordinator,
            autoplayStore: autoplayStore,
            recentActivityStore: recentActivityStore,
            blockedPopupStore: blockedPopupStore,
            externalSchemeSessionStore: externalSchemeSessionStore,
            indicatorEventStore: indicatorEventStore,
            now: now
        )
        self.aggregator = aggregator
        self.presentationBuilder = SumiSiteSettingsPresentationBuilder(
            aggregator: aggregator,
            systemPermissionService: systemPermissionService,
            websiteDataCleanupService: websiteDataCleanupService
        )
        self.decisionWriteOwner = SumiPermissionDecisionWriteOwner(
            coordinator: coordinator,
            autoplayStore: autoplayStore,
            recentActivityStore: recentActivityStore,
            siteActivityStore: siteActivityStore,
            aggregator: aggregator,
            now: now
        )
    }

    convenience init(
        permissionRuntime: BrowserManagerPermissionRuntime,
        dataServices: BrowserManagerDataServices,
        autoplayStore: SumiAutoplayPolicyStoreAdapter,
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.init(
            coordinator: permissionRuntime.permissionCoordinator,
            systemPermissionService: permissionRuntime.systemPermissionService,
            autoplayStore: autoplayStore,
            recentActivityStore: permissionRuntime.permissionRecentActivityStore,
            siteActivityStore: permissionRuntime.permissionSiteActivityStore,
            blockedPopupStore: permissionRuntime.blockedPopupStore,
            externalSchemeSessionStore: permissionRuntime.externalSchemeSessionStore,
            indicatorEventStore: permissionRuntime.permissionIndicatorEventStore,
            websiteDataCleanupService: dataServices.websiteDataCleanupService,
            permissionCleanupService: permissionRuntime.permissionCleanupService,
            userDefaults: userDefaults,
            now: now
        )
    }

    // MARK: - Cleanup Settings

    var cleanupSettings: SumiPermissionCleanupSettings {
        get { cleanupSettingsOwner.cleanupSettings }
        set { cleanupSettingsOwner.cleanupSettings = newValue }
    }

    func cleanupSettings(profile: SumiPermissionSettingsProfileContext) -> SumiPermissionCleanupSettings {
        cleanupSettingsOwner.cleanupSettings(profile: profile)
    }

    func setAutomaticCleanupEnabled(
        _ isEnabled: Bool,
        profile: SumiPermissionSettingsProfileContext
    ) {
        cleanupSettingsOwner.setAutomaticCleanupEnabled(isEnabled, profile: profile)
    }

    @discardableResult
    func runAutomaticCleanupIfNeeded(
        profile: SumiPermissionSettingsProfileContext
    ) async -> SumiPermissionCleanupResult {
        await cleanupSettingsOwner.runAutomaticCleanupIfNeeded(profile: profile)
    }

    // MARK: - Records and Presentation

    func permissionRecords(
        profile: SumiPermissionSettingsProfileContext
    ) async throws -> [SumiPermissionStoreRecord] {
        try await aggregator.permissionRecords(profile: profile)
    }

    func categoryRows(
        profile: SumiPermissionSettingsProfileContext
    ) async throws -> [SumiSiteSettingsCategoryRow] {
        try await presentationBuilder.categoryRows(profile: profile)
    }

    func siteRows(
        profile: SumiPermissionSettingsProfileContext,
        searchText: String = ""
    ) async throws -> [SumiSiteSettingsSiteRow] {
        try await presentationBuilder.siteRows(profile: profile, searchText: searchText)
    }

    func categoryDetail(
        category: SumiSiteSettingsPermissionCategory,
        profile: SumiPermissionSettingsProfileContext,
        searchText: String = ""
    ) async throws -> SumiSiteSettingsCategoryDetail {
        try await presentationBuilder.categoryDetail(
            category: category,
            profile: profile,
            searchText: searchText
        )
    }

    func siteDetail(
        scope: SumiPermissionSiteScope,
        profile: SumiPermissionSettingsProfileContext,
        profileObject: Profile? = nil,
        includeDataSummary: Bool = true
    ) async throws -> SumiSiteSettingsSiteDetail {
        try await presentationBuilder.siteDetail(
            scope: scope,
            profile: profile,
            profileObject: profileObject,
            includeDataSummary: includeDataSummary
        )
    }

    func recentActivity(
        profile: SumiPermissionSettingsProfileContext,
        limit: Int = 10
    ) -> [SumiSiteSettingsRecentActivityItem] {
        presentationBuilder.recentActivity(profile: profile, limit: limit)
    }

    func systemSnapshot(
        for category: SumiSiteSettingsPermissionCategory
    ) async -> SumiSystemPermissionSnapshot? {
        await presentationBuilder.systemSnapshot(for: category)
    }

    // MARK: - Decision Writes

    func setOption(
        _ option: SumiCurrentSitePermissionOption,
        for row: SumiSiteSettingsPermissionRow
    ) async throws {
        try await decisionWriteOwner.setOption(option, for: row)
    }

    func removeException(for row: SumiSiteSettingsPermissionRow) async throws {
        try await decisionWriteOwner.removeException(for: row)
    }

    func resetSitePermissions(
        scope: SumiPermissionSiteScope,
        profile: SumiPermissionSettingsProfileContext
    ) async throws {
        try await decisionWriteOwner.resetSitePermissions(scope: scope, profile: profile)
    }

    // MARK: - Site Data and System Settings

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
        await profile.refreshDataStoreStats(cleanupService: websiteDataCleanupService)
    }

    @discardableResult
    func openSystemSettings(for kind: SumiSystemPermissionKind) async -> Bool {
        await systemPermissionService.openSystemSettings(for: kind)
    }
}
