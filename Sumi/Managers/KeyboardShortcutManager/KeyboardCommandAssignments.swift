import Foundation
import SumiDomain

protocol KeyboardCommandCaptureResponder: AnyObject {}

extension Notification.Name {
    static let sumiKeyboardBindingsDidChange = Notification.Name(
        "SumiKeyboardBindingsDidChange"
    )
}

enum BrowserActionBindingOrigin: Equatable {
    case suggested
    case userAssigned
    case explicitlyCleared
}

enum BrowserActionBindingInactiveReason: Equatable {
    case nativeReservation
    case conflict(ShortcutAction)
    case invalidCombination

    var userMessage: String {
        switch self {
        case .nativeReservation:
            return "Reserved by macOS or a fixed Sumi menu command."
        case .conflict(let action):
            return "Used by \(action.displayName)."
        case .invalidCombination:
            return "This saved key combination is not supported."
        }
    }
}

struct BrowserActionBindingAssignment: Equatable {
    let action: ShortcutAction
    let assignedCombination: KeyCombination?
    let activeCombination: KeyCombination?
    let origin: BrowserActionBindingOrigin
    let inactiveReason: BrowserActionBindingInactiveReason?
}

final class KeyboardCommandAssignments {
    private struct LegacyOverride: Decodable {
        let action: ShortcutAction
        let keyCombination: KeyCombination?
    }

    private static let legacyKey = "keyboard.shortcuts"
    private static let legacyBackupDocumentKey =
        "keyboard.bindings.migration.v1.backup"

    private let database: SumiDatabase
    private var recordsByAction: [ShortcutAction: BrowserActionBindingRecord]

    init(
        database: SumiDatabase,
        legacyDefaults: UserDefaults = .standard
    ) throws {
        self.database = database
        try Self.importLegacyBindingsIfNeeded(
            database: database,
            userDefaults: legacyDefaults
        )
        recordsByAction = try Self.readRecords(database: database)
    }

    func reload() throws {
        recordsByAction = try Self.readRecords(database: database)
    }

    private static func readRecords(
        database: SumiDatabase
    ) throws -> [ShortcutAction: BrowserActionBindingRecord] {
        try database.read { connection in
            Dictionary(
                uniqueKeysWithValues: try connection.keyboardBindings
                    .browserActionBindings()
                    .compactMap { record in
                        record.action.map { ($0, record) }
                    }
            )
        }
    }

    func assignment(for action: ShortcutAction) -> BrowserActionBindingAssignment {
        Self.projectAssignments(recordsByAction: recordsByAction)[action]
            ?? BrowserActionBindingAssignment(
                action: action,
                assignedCombination: nil,
                activeCombination: nil,
                origin: .suggested,
                inactiveReason: nil
            )
    }

    func assign(
        _ combination: KeyCombination,
        to action: ShortcutAction,
        replacing previousOwner: ShortcutAction? = nil,
        replacing extensionOwner: ExtensionCommandBindingIdentity? = nil
    ) throws {
        let record = BrowserActionBindingRecord(
            action: action,
            disposition: .userAssigned,
            keyCombination: combination
        )
        let clearedRecord = previousOwner.map {
            BrowserActionBindingRecord(
                action: $0,
                disposition: .explicitlyCleared,
                keyCombination: nil
            )
        }
        try database.transaction { connection in
            if let clearedRecord {
                try connection.keyboardBindings.save(clearedRecord)
            }
            if let extensionOwner {
                try connection.keyboardBindings.save(
                    ExtensionCommandBindingRecord(
                        identity: extensionOwner,
                        disposition: .explicitlyCleared,
                        keyCombination: nil
                    )
                )
            }
            try connection.keyboardBindings.save(record)
        }
        if let previousOwner, let clearedRecord {
            recordsByAction[previousOwner] = clearedRecord
        }
        recordsByAction[action] = record
        notifyBindingsChanged()
    }

    func clear(_ action: ShortcutAction) throws {
        let record = BrowserActionBindingRecord(
            action: action,
            disposition: .explicitlyCleared,
            keyCombination: nil
        )
        try database.transaction { connection in
            try connection.keyboardBindings.save(record)
        }
        recordsByAction[action] = record
        notifyBindingsChanged()
    }

    func resetBrowserActions() throws {
        try database.transaction { connection in
            try connection.keyboardBindings.deleteAllBrowserActionBindings()
        }
        recordsByAction.removeAll()
        notifyBindingsChanged()
    }

    func legacyMigrationBackup() throws -> Data? {
        try database.read {
            try $0.documents.data(forKey: Self.legacyBackupDocumentKey)
        }
    }

    private static func importLegacyBindingsIfNeeded(
        database: SumiDatabase,
        userDefaults: UserDefaults
    ) throws {
        guard let data = userDefaults.data(forKey: legacyKey) else { return }

        try database.transaction { connection in
            guard try connection.documents.data(
                forKey: legacyBackupDocumentKey
            ) == nil else {
                return
            }

            try connection.documents.save(
                data,
                forKey: legacyBackupDocumentKey
            )

            for legacy in legacyOverrides(from: data) {
                try connection.keyboardBindings.save(
                    BrowserActionBindingRecord(
                        action: legacy.action,
                        disposition: legacy.keyCombination == nil
                            ? .explicitlyCleared
                            : .userAssigned,
                        keyCombination: legacy.keyCombination
                    )
                )
            }
        }
    }

    private static func legacyOverrides(from data: Data) -> [LegacyOverride] {
        let elements: [Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: data)
                as? [Any] else { return [] }
            elements = decoded
        } catch {
            return []
        }

        var overrides: [LegacyOverride] = []
        var seenActions: Set<ShortcutAction> = []
        for element in elements where JSONSerialization.isValidJSONObject(element) {
            do {
                let elementData = try JSONSerialization.data(
                    withJSONObject: element
                )
                let legacy = try JSONDecoder().decode(
                    LegacyOverride.self,
                    from: elementData
                )
                if seenActions.insert(legacy.action).inserted {
                    overrides.append(legacy)
                }
            } catch {
                continue
            }
        }
        return overrides
    }

    static func activeBrowserOwners(
        database: SumiDatabase
    ) throws -> [String: ShortcutAction] {
        let recordsByAction = Dictionary(
            uniqueKeysWithValues: try database.read { connection in
                try connection.keyboardBindings.browserActionBindings()
                    .compactMap { record in
                        record.action.map { ($0, record) }
                    }
            }
        )
        return Dictionary(
            uniqueKeysWithValues: projectAssignments(
                recordsByAction: recordsByAction
            ).values.compactMap { assignment in
                assignment.activeCombination.map {
                    ($0.lookupKey, assignment.action)
                }
            }
        )
    }

    private func notifyBindingsChanged() {
        NotificationCenter.default.post(
            name: .sumiKeyboardBindingsDidChange,
            object: database
        )
    }

    private static func projectAssignments(
        recordsByAction: [ShortcutAction: BrowserActionBindingRecord]
    ) -> [ShortcutAction: BrowserActionBindingAssignment] {
        var projected: [ShortcutAction: BrowserActionBindingAssignment] = [:]
        var ownersByCombination: [String: ShortcutAction] = [:]

        let actionsByOwnershipPriority = ShortcutAction.allCases.sorted { lhs, rhs in
            let lhsHasRecord = recordsByAction[lhs] != nil
            let rhsHasRecord = recordsByAction[rhs] != nil
            if lhsHasRecord != rhsHasRecord {
                return lhsHasRecord
            }
            return lhs.rawValue < rhs.rawValue
        }

        for action in actionsByOwnershipPriority {
            let record = recordsByAction[action]
            let origin: BrowserActionBindingOrigin
            let assignedCombination: KeyCombination?
            if let record {
                origin = record.disposition == .explicitlyCleared
                    ? .explicitlyCleared
                    : .userAssigned
                assignedCombination = record.keyCombination
            } else {
                origin = .suggested
                assignedCombination = DefaultKeyboardShortcuts
                    .shortcutsByAction[action]?.keyCombination
            }

            let inactiveReason: BrowserActionBindingInactiveReason?
            let activeCombination: KeyCombination?
            if Self.nativeCommandActions.contains(action) {
                inactiveReason = assignedCombination == nil
                    ? nil
                    : .nativeReservation
                activeCombination = nil
            } else if let assignedCombination,
                      !Self.isValidBrowserActionCombination(assignedCombination) {
                inactiveReason = .invalidCombination
                activeCombination = nil
            } else if let assignedCombination,
                      Self.nativeReservations.contains(assignedCombination) {
                inactiveReason = .nativeReservation
                activeCombination = nil
            } else if let assignedCombination,
                      let owner = ownersByCombination[assignedCombination.lookupKey] {
                inactiveReason = .conflict(owner)
                activeCombination = nil
            } else {
                inactiveReason = nil
                activeCombination = assignedCombination
                if let assignedCombination {
                    ownersByCombination[assignedCombination.lookupKey] = action
                }
            }

            projected[action] = BrowserActionBindingAssignment(
                action: action,
                assignedCombination: assignedCombination,
                activeCombination: activeCombination,
                origin: origin,
                inactiveReason: inactiveReason
            )
        }
        return projected
    }

    static let nativeCommandActions: Set<ShortcutAction> = [
        .openSettings,
        .closeBrowser,
        .toggleFullScreen,
    ]

    static let nativeReservations: Set<KeyCombination> = [
        KeyCombination(key: "x", modifiers: [.command]),
        KeyCombination(key: "c", modifiers: [.command]),
        KeyCombination(key: "v", modifiers: [.command]),
        KeyCombination(key: "a", modifiers: [.command]),
        KeyCombination(key: "z", modifiers: [.command]),
        KeyCombination(key: "z", modifiers: [.command, .shift]),
        KeyCombination(key: "v", modifiers: [.command, .shift]),
        KeyCombination(
            key: "v",
            modifiers: [.command, .option, .shift]
        ),
        KeyCombination(key: "b", modifiers: [.command]),
        KeyCombination(key: "i", modifiers: [.command]),
        KeyCombination(key: "u", modifiers: [.command]),
        KeyCombination(key: "e", modifiers: [.command]),
        KeyCombination(key: "g", modifiers: [.command]),
        KeyCombination(key: "g", modifiers: [.command, .shift]),
        KeyCombination(key: "leftarrow", modifiers: [.command]),
        KeyCombination(key: "rightarrow", modifiers: [.command]),
        KeyCombination(key: "uparrow", modifiers: [.command]),
        KeyCombination(key: "downarrow", modifiers: [.command]),
        KeyCombination(key: "leftarrow", modifiers: [.command, .shift]),
        KeyCombination(key: "rightarrow", modifiers: [.command, .shift]),
        KeyCombination(key: "uparrow", modifiers: [.command, .shift]),
        KeyCombination(key: "downarrow", modifiers: [.command, .shift]),
        KeyCombination(key: "delete", modifiers: [.command]),
        KeyCombination(key: ",", modifiers: [.command]),
        KeyCombination(key: "q", modifiers: [.command]),
        KeyCombination(key: "f", modifiers: [.command, .control]),
        KeyCombination(key: "h", modifiers: [.command]),
        KeyCombination(key: "h", modifiers: [.command, .option]),
        KeyCombination(key: "m", modifiers: [.command]),
        KeyCombination(key: "`", modifiers: [.command]),
        KeyCombination(key: "`", modifiers: [.command, .shift]),
        KeyCombination(key: "b", modifiers: [.command, .option]),
        KeyCombination(key: "d", modifiers: [.command]),
        KeyCombination(key: "d", modifiers: [.command, .shift]),
        KeyCombination(key: "delete", modifiers: [.command, .shift]),
        KeyCombination(key: "space", modifiers: [.command]),
        KeyCombination(key: "space", modifiers: [.command, .control]),
        KeyCombination(key: "escape", modifiers: [.command, .option]),
        KeyCombination(key: "3", modifiers: [.command, .shift]),
        KeyCombination(key: "4", modifiers: [.command, .shift]),
        KeyCombination(key: "5", modifiers: [.command, .shift]),
    ]

    static func isValidBrowserActionCombination(
        _ combination: KeyCombination
    ) -> Bool {
        let key = combination.key.lowercased()
        guard !key.isEmpty else { return false }
        if key == "tab" {
            return combination.modifiers == [.control]
                || combination.modifiers == [.control, .shift]
        }
        guard key.count == 1 else { return false }
        if key.first?.isNumber == true {
            return combination.modifiers.contains(.command)
                || combination.modifiers.contains(.control)
        }
        return combination.modifiers.contains(.command)
    }
}
