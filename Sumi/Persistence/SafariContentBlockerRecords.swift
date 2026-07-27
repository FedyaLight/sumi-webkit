import Foundation
import GRDB

struct SafariContentBlockerRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "safari_content_blockers"

    let id: String
    var extensionBundleIdentifier: String
    var displayName: String
    var version: String?
    var containingAppName: String
    var containingAppBundleIdentifier: String?
    var appexPath: String
    var containingAppPath: String
    var resourceFingerprint: String
    var isEnabled: Bool
    var installDate: Date
    var lastUpdateDate: Date
    var compileStatusRawValue: String
    var lastError: String?
    var ruleListCount: Int
    var ignoredEmptyRuleListCount: Int

    init(_ metadata: SafariContentBlockerMetadata) {
        id = metadata.id
        extensionBundleIdentifier = metadata.extensionBundleIdentifier
        displayName = metadata.displayName
        version = metadata.version
        containingAppName = metadata.containingAppName
        containingAppBundleIdentifier = metadata.containingAppBundleIdentifier
        appexPath = metadata.appexPath
        containingAppPath = metadata.containingAppPath
        resourceFingerprint = metadata.resourceFingerprint
        isEnabled = metadata.isEnabled
        installDate = metadata.installDate
        lastUpdateDate = metadata.lastUpdateDate
        compileStatusRawValue = metadata.compileStatusRawValue
        lastError = metadata.lastError
        ruleListCount = metadata.ruleListCount
        ignoredEmptyRuleListCount = metadata.ignoredEmptyRuleListCount
    }

    var metadata: SafariContentBlockerMetadata {
        SafariContentBlockerMetadata(
            id: id,
            extensionBundleIdentifier: extensionBundleIdentifier,
            displayName: displayName,
            version: version,
            containingAppName: containingAppName,
            containingAppBundleIdentifier: containingAppBundleIdentifier,
            appexPath: appexPath,
            containingAppPath: containingAppPath,
            resourceFingerprint: resourceFingerprint,
            isEnabled: isEnabled,
            installDate: installDate,
            lastUpdateDate: lastUpdateDate,
            compileStatus: SafariContentBlockerCompileStatus(
                rawValue: compileStatusRawValue
            ) ?? .unknown,
            lastError: lastError,
            ruleListCount: ruleListCount,
            ignoredEmptyRuleListCount: ignoredEmptyRuleListCount
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case extensionBundleIdentifier = "extension_bundle_id"
        case displayName = "display_name"
        case version
        case containingAppName = "containing_app_name"
        case containingAppBundleIdentifier = "containing_app_bundle_id"
        case appexPath = "appex_path"
        case containingAppPath = "containing_app_path"
        case resourceFingerprint = "resource_fingerprint"
        case isEnabled = "is_enabled"
        case installDate = "installed_at"
        case lastUpdateDate = "updated_at"
        case compileStatusRawValue = "compile_status"
        case lastError = "last_error"
        case ruleListCount = "rule_list_count"
        case ignoredEmptyRuleListCount = "ignored_empty_rule_list_count"
    }
}

struct SafariContentBlockerRecordStore {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func all() throws -> [SafariContentBlockerMetadata] {
        try SafariContentBlockerRow.fetchAll(database).map(\.metadata)
    }

    func find(bundleID: String) throws -> SafariContentBlockerMetadata? {
        try SafariContentBlockerRow
            .filter(Column("extension_bundle_id") == bundleID)
            .fetchOne(database)?
            .metadata
    }

    func save(_ metadata: SafariContentBlockerMetadata) throws {
        try SafariContentBlockerRow(metadata).save(database)
    }

    func siteOverrides() throws
        -> [String: SumiSafariContentBlockerSiteOverride] {
        let rows = try Row.fetchAll(
            database,
            sql: "SELECT host, override FROM safari_content_blocker_site_overrides"
        )
        return Dictionary(
            uniqueKeysWithValues: rows.compactMap { row in
                let host: String = row["host"]
                let rawValue: String = row["override"]
                guard let value = SumiSafariContentBlockerSiteOverride(
                    rawValue: rawValue
                ) else {
                    return nil
                }
                return (host, value)
            }
        )
    }

    func replaceSiteOverrides(
        _ overrides: [String: SumiSafariContentBlockerSiteOverride]
    ) throws {
        try database.execute(
            sql: "DELETE FROM safari_content_blocker_site_overrides"
        )
        for (host, value) in overrides {
            try database.execute(
                sql: """
                    INSERT INTO safari_content_blocker_site_overrides
                        (host, override)
                    VALUES (?, ?)
                    """,
                arguments: [host, value.rawValue]
            )
        }
    }
}
