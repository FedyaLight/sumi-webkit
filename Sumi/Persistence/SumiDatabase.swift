import Foundation
import GRDB

final class SumiDatabase: @unchecked Sendable {
    private let writer: any DatabaseWriter

    static func open(at url: URL) throws -> SumiDatabase {
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let pool = try DatabasePool(
            path: url.path,
            configuration: configuration
        )
        return try SumiDatabase(writer: pool)
    }

    static func inMemory() throws -> SumiDatabase {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return try SumiDatabase(
            writer: DatabaseQueue(configuration: configuration)
        )
    }

    private init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try writer.write { database in
            let schemaVersion = try Int.fetchOne(
                database,
                sql: "PRAGMA user_version"
            ) ?? 0
            switch schemaVersion {
            case 0:
                try Self.createSchema(in: database)
                try Self.createKeyboardCommandSchema(in: database)
                try database.execute(sql: "PRAGMA user_version = 3")
            case 1:
                try database.alter(table: "folders") { table in
                    table.add(column: "is_live", .boolean)
                        .notNull()
                        .defaults(to: false)
                }
                try Self.createKeyboardCommandSchema(in: database)
                try database.execute(sql: "PRAGMA user_version = 3")
            case 2:
                try Self.createKeyboardCommandSchema(in: database)
                try database.execute(sql: "PRAGMA user_version = 3")
            case 3:
                break
            default:
                throw SumiDatabaseError.unsupportedSchemaVersion(schemaVersion)
            }
        }
    }

    func read<Value>(
        _ operation: (SumiDatabaseConnection) throws -> Value
    ) throws -> Value {
        try writer.read { database in
            try operation(SumiDatabaseConnection(database: database))
        }
    }

    func transaction<Value>(
        _ operation: (SumiDatabaseConnection) throws -> Value
    ) throws -> Value {
        try writer.write { database in
            try operation(SumiDatabaseConnection(database: database))
        }
    }

    private static func createSchema(in database: Database) throws {
            try database.create(table: "browser_documents") { table in
                table.column("key", .text).primaryKey()
                table.column("payload", .blob).notNull()
                table.column("updated_at", .datetime).notNull()
            }
            try database.create(table: "profiles") { table in
                table.column("id", .blob).primaryKey()
                table.column("name", .text).notNull()
                table.column("position", .integer).notNull()
            }

            try database.create(table: "spaces") { table in
                table.column("id", .blob).primaryKey()
                table.column("profile_id", .blob)
                    .notNull()
                    .references("profiles", onDelete: .cascade)
                table.column("name", .text).notNull()
                table.column("icon", .text).notNull()
                table.column("position", .integer).notNull()
                table.column("workspace_theme", .blob)
            }

            try database.create(table: "folders") { table in
                table.column("id", .blob).primaryKey()
                table.column("space_id", .blob)
                    .notNull()
                    .references("spaces", onDelete: .cascade)
                table.column("parent_folder_id", .blob)
                    .references("folders", onDelete: .cascade)
                table.column("name", .text).notNull()
                table.column("icon", .text).notNull()
                table.column("color", .text).notNull()
                table.column("is_open", .boolean).notNull()
                table.column("is_live", .boolean).notNull().defaults(to: false)
                table.column("position", .integer).notNull()
                table.uniqueKey(["space_id", "parent_folder_id", "position"])
            }

            try database.create(table: "tabs") { table in
                table.column("id", .blob).primaryKey()
                table.column("profile_id", .blob)
                    .references("profiles", onDelete: .cascade)
                table.column("execution_profile_id", .blob)
                    .references("profiles", onDelete: .setNull)
                table.column("space_id", .blob)
                    .references("spaces", onDelete: .cascade)
                table.column("folder_id", .blob)
                    .references("folders", onDelete: .cascade)
                table.column("url", .text).notNull()
                table.column("name", .text).notNull()
                table.column("is_pinned", .boolean).notNull()
                table.column("is_space_pinned", .boolean).notNull()
                table.column("position", .integer).notNull()
                table.column("icon_asset", .text)
                table.column("title_is_custom", .boolean).notNull()
                table.column("current_url", .text).notNull()
                table.column("can_go_back", .boolean).notNull()
                table.column("can_go_forward", .boolean).notNull()
            }

            try database.create(
                index: "tabs_space_position",
                on: "tabs",
                columns: ["space_id", "position"]
            )
            try database.create(
                index: "tabs_profile",
                on: "tabs",
                columns: ["profile_id"]
            )

            try database.create(table: "tab_state") { table in
                table.column("id", .integer).primaryKey()
                table.column("current_tab_id", .blob)
                table.column("current_space_id", .blob)
                table.column("split_groups", .blob)
                table.check(sql: "id = 1")
            }

            try database.create(table: "profile_retirements") { table in
                table.column("profile_id", .blob).primaryKey()
                table.column("profile_name", .text).notNull()
                table.column("profile_position", .integer).notNull()
                table.column("fallback_profile_id", .blob).notNull()
                table.column("generation", .blob).notNull()
                table.column("phase", .text).notNull()
                table.column("next_cleanup_step", .text).notNull()
            }
            try database.create(table: "bookmarks") { table in
                table.column("id", .blob).primaryKey()
                table.column("parent_id", .blob)
                    .references("bookmarks", onDelete: .cascade)
                table.column("name", .text).notNull()
                table.column("url", .text)
                table.column("kind", .text).notNull()
                table.column("position", .integer).notNull()
            }
            try database.create(
                index: "bookmarks_parent_position",
                on: "bookmarks",
                columns: ["parent_id", "position"]
            )
            try database.create(table: "history_entries") { table in
                table.column("id", .blob).primaryKey()
                table.column("profile_id", .blob)
                    .notNull()
                    .references("profiles", onDelete: .cascade)
                table.column("url", .text).notNull()
                table.column("title", .text).notNull()
                table.column("domain", .text).notNull()
                table.column("site_domain", .text)
                table.column("visit_count", .integer).notNull()
                table.column("last_visit", .datetime).notNull()
                table.uniqueKey(["profile_id", "url"])
            }
            try database.create(
                index: "history_entries_profile_last_visit",
                on: "history_entries",
                columns: ["profile_id", "last_visit"]
            )
            try database.create(
                index: "history_entries_profile_site",
                on: "history_entries",
                columns: ["profile_id", "site_domain"]
            )

            try database.create(table: "history_visits") { table in
                table.column("id", .blob).primaryKey()
                table.column("entry_id", .blob)
                    .notNull()
                    .references("history_entries", onDelete: .cascade)
                table.column("visited_at", .datetime).notNull()
                table.column("tab_id", .blob)
            }
            try database.create(
                index: "history_visits_entry_date",
                on: "history_visits",
                columns: ["entry_id", "visited_at"]
            )
            try database.create(
                index: "history_visits_date",
                on: "history_visits",
                columns: ["visited_at"]
            )
            try database.create(
                index: "history_visits_tab",
                on: "history_visits",
                columns: ["tab_id"]
            )
            try database.create(table: "permission_decisions") { table in
                table.column("identity", .text).primaryKey()
                table.column("profile_id", .blob)
                    .notNull()
                    .references("profiles", onDelete: .cascade)
                table.column("profile_partition_id", .text).notNull()
                table.column("requesting_origin", .text).notNull()
                table.column("top_origin", .text).notNull()
                table.column("permission_type", .text).notNull()
                table.column("display_domain", .text).notNull()
                table.column("state", .text).notNull()
                table.column("persistence", .text).notNull()
                table.column("source", .text).notNull()
                table.column("reason", .text)
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
                table.column("expires_at", .datetime)
                table.column("last_used_at", .datetime)
                table.column("system_authorization", .text)
                table.column("metadata", .blob)
            }
            try database.create(
                index: "permission_decisions_profile_domain",
                on: "permission_decisions",
                columns: ["profile_partition_id", "display_domain"]
            )
            try database.create(
                index: "permission_decisions_profile_type",
                on: "permission_decisions",
                columns: ["profile_partition_id", "permission_type"]
            )
            try database.create(table: "permission_state") { table in
                table.column("id", .integer).primaryKey()
                table.column("generation", .integer).notNull()
                table.column("anti_abuse_events", .blob).notNull()
                table.column("site_activity_records", .blob).notNull()
                table.check(sql: "id = 1")
            }
            try database.create(table: "extensions") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("version", .text).notNull()
                table.column("manifest_version", .integer).notNull()
                table.column("description", .text)
                table.column("is_enabled", .boolean).notNull()
                table.column("installed_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
                table.column("package_path", .text).notNull()
                table.column("icon_path", .text)
                table.column("source_kind", .text).notNull()
                table.column("background_model", .text).notNull()
                table.column("incognito_mode", .text).notNull()
                table.column("source_path_fingerprint", .text).notNull()
                table.column("manifest_root_fingerprint", .text).notNull()
                table.column("source_bundle_path", .text).notNull()
                table.column("safari_runtime_identity", .text)
                table.column("options_page_path", .text)
                table.column("default_popup_path", .text)
                table.column("has_background", .boolean).notNull()
                table.column("has_action", .boolean).notNull()
                table.column("has_options_page", .boolean).notNull()
                table.column("has_content_scripts", .boolean).notNull()
                table.column("has_extension_pages", .boolean).notNull()
                table.column("broad_scope", .boolean).notNull()
                table.column("activation_summary", .text).notNull()
                table.column("manifest_snapshot", .text).notNull()
            }
            try database.create(
                index: "extensions_enabled",
                on: "extensions",
                columns: ["is_enabled"]
            )
            try database.create(table: "safari_content_blockers") { table in
                table.column("id", .text).primaryKey()
                table.column("extension_bundle_id", .text).notNull().unique()
                table.column("display_name", .text).notNull()
                table.column("version", .text)
                table.column("containing_app_name", .text).notNull()
                table.column("containing_app_bundle_id", .text)
                table.column("appex_path", .text).notNull()
                table.column("containing_app_path", .text).notNull()
                table.column("resource_fingerprint", .text).notNull()
                table.column("is_enabled", .boolean).notNull()
                table.column("installed_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
                table.column("compile_status", .text).notNull()
                table.column("last_error", .text)
                table.column("rule_list_count", .integer).notNull()
                table.column("ignored_empty_rule_list_count", .integer).notNull()
            }
            try database.create(
                table: "safari_content_blocker_site_overrides"
            ) { table in
                table.column("host", .text).primaryKey()
                table.column("override", .text).notNull()
            }
    }

    private static func createKeyboardCommandSchema(in database: Database) throws {
        try database.create(table: "browser_action_bindings") { table in
            table.column("action_id", .text).primaryKey()
            table.column("disposition", .text).notNull()
            table.column("key", .text)
            table.column("modifiers", .integer)
        }

        try database.create(table: "extension_command_bindings") { table in
            table.column("profile_id", .blob).notNull()
            table.column("extension_id", .text).notNull()
            table.column("command_name", .text).notNull()
            table.column("disposition", .text).notNull()
            table.column("key", .text)
            table.column("modifiers", .integer)
            table.primaryKey(["profile_id", "extension_id", "command_name"])
        }
    }
}

struct SumiDatabaseConnection {
    let profiles: ProfileRecordStore
    let workspace: WorkspaceRecordStore
    let bookmarks: BookmarkRecordStore
    let history: HistoryRecordStore
    let retirements: ProfileRetirementRecordStore
    let permissions: PermissionDecisionRecordStore
    let permissionAuxiliary: PermissionAuxiliaryRecordStore
    let extensions: ExtensionMetadataRecordStore
    let safariContentBlockers: SafariContentBlockerRecordStore
    let documents: BrowserDocumentRecordStore
    let keyboardBindings: KeyboardBindingRecordStore

    fileprivate init(database: Database) {
        profiles = ProfileRecordStore(database: database)
        workspace = WorkspaceRecordStore(database: database)
        bookmarks = BookmarkRecordStore(database: database)
        history = HistoryRecordStore(database: database)
        retirements = ProfileRetirementRecordStore(database: database)
        permissions = PermissionDecisionRecordStore(database: database)
        permissionAuxiliary = PermissionAuxiliaryRecordStore(database: database)
        extensions = ExtensionMetadataRecordStore(database: database)
        safariContentBlockers = SafariContentBlockerRecordStore(
            database: database
        )
        documents = BrowserDocumentRecordStore(database: database)
        keyboardBindings = KeyboardBindingRecordStore(database: database)
    }
}

enum SumiDatabaseError: Error {
    case importRequiresProfile
    case historyRequiresProfile
    case invalidIdentifier(String)
    case missingProfile(UUID)
    case missingSpace(UUID)
    case unsupportedSchemaVersion(Int)
}
