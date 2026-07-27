import Foundation
import GRDB

struct ExtensionMetadataRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "extensions"

    let id: String
    var name: String
    var version: String
    var manifestVersion: Int
    var extensionDescription: String?
    var isEnabled: Bool
    var installDate: Date
    var lastUpdateDate: Date
    var packagePath: String
    var iconPath: String?
    var sourceKindRawValue: String
    var backgroundModelRawValue: String
    var incognitoModeRawValue: String
    var sourcePathFingerprint: String
    var manifestRootFingerprint: String
    var sourceBundlePath: String
    var safariRuntimeIdentity: String?
    var optionsPagePath: String?
    var defaultPopupPath: String?
    var hasBackground: Bool
    var hasAction: Bool
    var hasOptionsPage: Bool
    var hasContentScripts: Bool
    var hasExtensionPages: Bool
    var broadScope: Bool
    var activationSummaryJSON: String
    var manifestSnapshotJSON: String

    init(_ metadata: InstalledExtensionMetadata) {
        id = metadata.id
        name = metadata.name
        version = metadata.version
        manifestVersion = metadata.manifestVersion
        extensionDescription = metadata.extensionDescription
        isEnabled = metadata.isEnabled
        installDate = metadata.installDate
        lastUpdateDate = metadata.lastUpdateDate
        packagePath = metadata.packagePath
        iconPath = metadata.iconPath
        sourceKindRawValue = metadata.sourceKindRawValue
        backgroundModelRawValue = metadata.backgroundModelRawValue
        incognitoModeRawValue = metadata.incognitoModeRawValue
        sourcePathFingerprint = metadata.sourcePathFingerprint
        manifestRootFingerprint = metadata.manifestRootFingerprint
        sourceBundlePath = metadata.sourceBundlePath
        safariRuntimeIdentity = metadata.safariRuntimeIdentity
        optionsPagePath = metadata.optionsPagePath
        defaultPopupPath = metadata.defaultPopupPath
        hasBackground = metadata.hasBackground
        hasAction = metadata.hasAction
        hasOptionsPage = metadata.hasOptionsPage
        hasContentScripts = metadata.hasContentScripts
        hasExtensionPages = metadata.hasExtensionPages
        broadScope = metadata.broadScope
        activationSummaryJSON = metadata.activationSummaryJSON
        manifestSnapshotJSON = metadata.manifestSnapshotJSON
    }

    var metadata: InstalledExtensionMetadata {
        let record = InstalledExtensionMetadata(
            record: InstalledExtensionRecord(
                id: id,
                name: name,
                version: version,
                manifestVersion: manifestVersion,
                description: extensionDescription,
                isEnabled: isEnabled,
                installDate: installDate,
                lastUpdateDate: lastUpdateDate,
                packagePath: packagePath,
                iconPath: iconPath,
                sourceKind: WebExtensionSourceKind(rawValue: sourceKindRawValue)
                    ?? .directory,
                backgroundModel: WebExtensionBackgroundModel(
                    rawValue: backgroundModelRawValue
                ) ?? .none,
                incognitoMode: IncognitoExtensionMode(
                    rawValue: incognitoModeRawValue
                ) ?? .spanning,
                sourcePathFingerprint: sourcePathFingerprint,
                manifestRootFingerprint: manifestRootFingerprint,
                sourceBundlePath: sourceBundlePath,
                safariRuntimeIdentity: safariRuntimeIdentity,
                optionsPagePath: optionsPagePath,
                defaultPopupPath: defaultPopupPath,
                hasBackground: hasBackground,
                hasAction: hasAction,
                hasOptionsPage: hasOptionsPage,
                hasContentScripts: hasContentScripts,
                hasExtensionPages: hasExtensionPages,
                activationSummary: InstalledExtensionRecord.decodeActivationSummary(
                    activationSummaryJSON
                ) ?? .init(
                    matchPatternStrings: [],
                    broadScope: broadScope,
                    hasContentScripts: hasContentScripts,
                    hasAction: hasAction,
                    hasOptionsPage: hasOptionsPage,
                    hasExtensionPages: hasExtensionPages
                ),
                manifest: InstalledExtensionRecord.decodeManifest(
                    manifestSnapshotJSON
                ) ?? [:]
            )
        )
        record.activationSummaryJSON = activationSummaryJSON
        record.manifestSnapshotJSON = manifestSnapshotJSON
        return record
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, version
        case manifestVersion = "manifest_version"
        case extensionDescription = "description"
        case isEnabled = "is_enabled"
        case installDate = "installed_at"
        case lastUpdateDate = "updated_at"
        case packagePath = "package_path"
        case iconPath = "icon_path"
        case sourceKindRawValue = "source_kind"
        case backgroundModelRawValue = "background_model"
        case incognitoModeRawValue = "incognito_mode"
        case sourcePathFingerprint = "source_path_fingerprint"
        case manifestRootFingerprint = "manifest_root_fingerprint"
        case sourceBundlePath = "source_bundle_path"
        case safariRuntimeIdentity = "safari_runtime_identity"
        case optionsPagePath = "options_page_path"
        case defaultPopupPath = "default_popup_path"
        case hasBackground = "has_background"
        case hasAction = "has_action"
        case hasOptionsPage = "has_options_page"
        case hasContentScripts = "has_content_scripts"
        case hasExtensionPages = "has_extension_pages"
        case broadScope = "broad_scope"
        case activationSummaryJSON = "activation_summary"
        case manifestSnapshotJSON = "manifest_snapshot"
    }
}

struct ExtensionMetadataRecordStore {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func all() throws -> [InstalledExtensionMetadata] {
        try ExtensionMetadataRow.fetchAll(database).map(\.metadata)
    }

    func find(id: String) throws -> InstalledExtensionMetadata? {
        try ExtensionMetadataRow.fetchOne(database, key: id)?.metadata
    }

    func containsEnabledExtension() throws -> Bool {
        try Bool.fetchOne(
            database,
            sql: "SELECT EXISTS(SELECT 1 FROM extensions WHERE is_enabled = 1)"
        ) ?? false
    }

    func save(_ metadata: InstalledExtensionMetadata) throws {
        try ExtensionMetadataRow(metadata).save(database)
    }

    func delete(id: String) throws {
        _ = try ExtensionMetadataRow.deleteOne(database, key: id)
    }
}
