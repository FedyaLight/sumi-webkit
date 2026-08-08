import Foundation
import GRDB
import SumiDomain

enum KeyboardBindingDisposition: String, Codable {
    case userAssigned
    case explicitlyCleared
}

struct BrowserActionBindingRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "browser_action_bindings"

    let actionID: String
    let disposition: KeyboardBindingDisposition
    let key: String?
    let modifiers: Int?

    init(
        action: ShortcutAction,
        disposition: KeyboardBindingDisposition,
        keyCombination: KeyCombination?
    ) {
        actionID = action.rawValue
        self.disposition = disposition
        key = keyCombination?.key
        modifiers = keyCombination?.modifiers.rawValue
    }

    var action: ShortcutAction? { ShortcutAction(rawValue: actionID) }

    var keyCombination: KeyCombination? {
        guard let key, let modifiers else { return nil }
        return KeyCombination(
            key: key,
            modifiers: Modifiers(rawValue: modifiers)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case actionID = "action_id"
        case disposition, key, modifiers
    }
}

struct ExtensionCommandBindingRecord:
    Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "extension_command_bindings"

    let profileID: UUID
    let extensionID: String
    let commandName: String
    let disposition: KeyboardBindingDisposition
    let key: String?
    let modifiers: Int?

    init(
        identity: ExtensionCommandBindingIdentity,
        disposition: KeyboardBindingDisposition,
        keyCombination: KeyCombination?
    ) {
        profileID = identity.profileID
        extensionID = identity.extensionID
        commandName = identity.commandName
        self.disposition = disposition
        key = keyCombination?.key
        modifiers = keyCombination?.modifiers.rawValue
    }

    var keyCombination: KeyCombination? {
        guard let key, let modifiers else { return nil }
        return KeyCombination(
            key: key,
            modifiers: Modifiers(rawValue: modifiers)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case extensionID = "extension_id"
        case commandName = "command_name"
        case disposition, key, modifiers
    }
}

struct KeyboardBindingRecordStore {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func browserActionBindings() throws -> [BrowserActionBindingRecord] {
        try BrowserActionBindingRecord.fetchAll(database)
    }

    func save(_ record: BrowserActionBindingRecord) throws {
        try record.save(database)
    }

    func deleteBrowserActionBinding(action: ShortcutAction) throws {
        _ = try BrowserActionBindingRecord.deleteOne(
            database,
            key: action.rawValue
        )
    }

    func deleteAllBrowserActionBindings() throws {
        _ = try BrowserActionBindingRecord.deleteAll(database)
    }

    func extensionCommandBindings() throws -> [ExtensionCommandBindingRecord] {
        try ExtensionCommandBindingRecord.fetchAll(database)
    }

    func save(_ record: ExtensionCommandBindingRecord) throws {
        try record.save(database)
    }
}
