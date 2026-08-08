import Foundation
import SumiDomain

struct ExtensionCommandBindingIdentity: Hashable, Identifiable {
    let profileID: UUID
    let extensionID: String
    let commandName: String

    var id: String {
        "\(profileID.uuidString):\(extensionID):\(commandName)"
    }
}

enum ExtensionCommandBindingOrigin: Equatable {
    case suggested
    case userAssigned
    case explicitlyCleared
}

enum ExtensionCommandBindingInactiveReason: Equatable {
    case nativeReservation
    case browserConflict(ShortcutAction)
    case extensionConflict(String)
    case invalidCombination
    case unsupportedMedia
    case unsupportedGlobal

    var userMessage: String {
        switch self {
        case .nativeReservation:
            return "Reserved by macOS or a fixed Sumi command."
        case .browserConflict(let action):
            return "Used by \(action.displayName)."
        case .extensionConflict(let title):
            return "Used by \(title)."
        case .invalidCombination:
            return "The extension's suggested key is not supported."
        case .unsupportedMedia:
            return "Media commands are not supported."
        case .unsupportedGlobal:
            return "Global commands are not supported."
        }
    }
}

struct ExtensionCommandBindingAssignment: Identifiable, Equatable {
    let identity: ExtensionCommandBindingIdentity
    let extensionName: String
    let title: String
    let assignedCombination: KeyCombination?
    let activeCombination: KeyCombination?
    let origin: ExtensionCommandBindingOrigin
    let inactiveReason: ExtensionCommandBindingInactiveReason?

    var id: String { identity.id }
}

final class ExtensionCommandAssignments {
    private struct Declaration {
        let identity: ExtensionCommandBindingIdentity
        let extensionName: String
        let title: String
        let suggestedKey: String?
        let isGlobal: Bool
        let isMedia: Bool
    }

    private struct Candidate {
        let declaration: Declaration
        let assignedCombination: KeyCombination?
        let origin: ExtensionCommandBindingOrigin
        var inactiveReason: ExtensionCommandBindingInactiveReason?
    }

    private enum ReplacementOwner {
        case browser(ShortcutAction)
        case extensionCommand(ExtensionCommandBindingIdentity)
    }

    private let database: SumiDatabase

    init(database: SumiDatabase) {
        self.database = database
    }

    func assignments(
        profileID: UUID
    ) throws -> [ExtensionCommandBindingAssignment] {
        let declarations = try declarations(profileID: profileID)
        let records = try records(profileID: profileID)
        let browserOwners = try KeyboardCommandAssignments.activeBrowserOwners(
            database: database
        )
        var candidates = makeCandidates(
            declarations: declarations,
            records: records,
            browserOwners: browserOwners
        )
        resolveExtensionConflicts(in: &candidates)
        return project(candidates)
    }

    private func project(
        _ candidates: [Candidate]
    ) -> [ExtensionCommandBindingAssignment] {
        candidates.map { candidate in
            ExtensionCommandBindingAssignment(
                identity: candidate.declaration.identity,
                extensionName: candidate.declaration.extensionName,
                title: candidate.declaration.title,
                assignedCombination: candidate.assignedCombination,
                activeCombination: candidate.inactiveReason == nil
                    ? candidate.assignedCombination
                    : nil,
                origin: candidate.origin,
                inactiveReason: candidate.inactiveReason
            )
        }
        .sorted {
            if $0.extensionName != $1.extensionName {
                return $0.extensionName.localizedCaseInsensitiveCompare(
                    $1.extensionName
                ) == .orderedAscending
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title)
                == .orderedAscending
        }
    }

    private func records(
        profileID: UUID
    ) throws -> [ExtensionCommandBindingIdentity: ExtensionCommandBindingRecord] {
        Dictionary(
            uniqueKeysWithValues: try database.read { connection in
                try connection.keyboardBindings.extensionCommandBindings()
                    .filter { $0.profileID == profileID }
                    .map {
                        (
                            ExtensionCommandBindingIdentity(
                                profileID: $0.profileID,
                                extensionID: $0.extensionID,
                                commandName: $0.commandName
                            ),
                            $0
                        )
                    }
            }
        )
    }

    private func makeCandidates(
        declarations: [Declaration],
        records: [ExtensionCommandBindingIdentity: ExtensionCommandBindingRecord],
        browserOwners: [String: ShortcutAction]
    ) -> [Candidate] {
        declarations.map { declaration in
            let record = records[declaration.identity]
            let origin: ExtensionCommandBindingOrigin = if let record {
                record.disposition == .explicitlyCleared
                    ? .explicitlyCleared
                    : .userAssigned
            } else {
                .suggested
            }
            let combination: KeyCombination?
            if let record {
                combination = record.keyCombination
            } else {
                combination = Self.parseSuggestedKey(declaration.suggestedKey)
            }
            return Candidate(
                declaration: declaration,
                assignedCombination: combination,
                origin: origin,
                inactiveReason: inactiveReason(
                    for: declaration,
                    hasRecord: record != nil,
                    combination: combination,
                    browserOwners: browserOwners
                )
            )
        }
    }

    private func inactiveReason(
        for declaration: Declaration,
        hasRecord: Bool,
        combination: KeyCombination?,
        browserOwners: [String: ShortcutAction]
    ) -> ExtensionCommandBindingInactiveReason? {
        if declaration.isGlobal { return .unsupportedGlobal }
        if declaration.isMedia { return .unsupportedMedia }
        if declaration.suggestedKey != nil, !hasRecord, combination == nil {
            return .invalidCombination
        }
        if let combination,
           !Self.isSupportedRegularCombination(combination) {
            return .invalidCombination
        }
        if let combination,
           KeyboardCommandAssignments.nativeReservations.contains(combination) {
            return .nativeReservation
        }
        if let combination,
           let action = browserOwners[combination.lookupKey] {
            return .browserConflict(action)
        }
        return nil
    }

    private func resolveExtensionConflicts(in candidates: inout [Candidate]) {
        var groups: [String: [Int]] = [:]
        for index in candidates.indices where candidates[index].inactiveReason == nil {
            guard let combination = candidates[index].assignedCombination else {
                continue
            }
            groups[combination.lookupKey, default: []].append(index)
        }
        for indices in groups.values where indices.count > 1 {
            let userIndices = indices.filter {
                candidates[$0].origin == .userAssigned
            }
            if userIndices.count == 1, let ownerIndex = userIndices.first {
                let ownerTitle = candidates[ownerIndex].declaration.title
                for index in indices where index != ownerIndex {
                    candidates[index].inactiveReason = .extensionConflict(ownerTitle)
                }
            } else {
                for index in indices {
                    candidates[index].inactiveReason = .extensionConflict(
                        "another extension command"
                    )
                }
            }
        }
    }

    func validate(
        _ combination: KeyCombination,
        for identity: ExtensionCommandBindingIdentity
    ) throws -> ShortcutValidationResult {
        guard Self.isSupportedRegularCombination(combination) else {
            return .invalid
        }
        guard !KeyboardCommandAssignments.nativeReservations
            .contains(combination) else {
            return .systemOwned
        }
        if let owner = try replacementOwner(
            for: combination,
            excluding: identity
        ) {
            switch owner {
            case .browser(let action):
                return .conflict(action)
            case .extensionCommand(let ownerIdentity):
                let ownerTitle = try assignments(profileID: identity.profileID)
                    .first { $0.identity == ownerIdentity }?.title
                    ?? ownerIdentity.commandName
                return .namedConflict(ownerTitle)
            }
        }
        return .valid
    }

    func assign(
        _ combination: KeyCombination,
        to identity: ExtensionCommandBindingIdentity
    ) throws -> ShortcutValidationResult {
        let validation = try validate(combination, for: identity)
        guard validation.allowsAssignment else { return validation }
        let replacement = try replacementOwner(
            for: combination,
            excluding: identity
        )
        let record = ExtensionCommandBindingRecord(
            identity: identity,
            disposition: .userAssigned,
            keyCombination: combination
        )
        try database.transaction { connection in
            switch replacement {
            case .browser(let action):
                try connection.keyboardBindings.save(
                    BrowserActionBindingRecord(
                        action: action,
                        disposition: .explicitlyCleared,
                        keyCombination: nil
                    )
                )
            case .extensionCommand(let ownerIdentity):
                try connection.keyboardBindings.save(
                    ExtensionCommandBindingRecord(
                        identity: ownerIdentity,
                        disposition: .explicitlyCleared,
                        keyCombination: nil
                    )
                )
            case nil:
                break
            }
            try connection.keyboardBindings.save(record)
        }
        notifyBindingsChanged()
        return .valid
    }

    func clear(_ identity: ExtensionCommandBindingIdentity) throws {
        try database.transaction { connection in
            try connection.keyboardBindings.save(
                ExtensionCommandBindingRecord(
                    identity: identity,
                    disposition: .explicitlyCleared,
                    keyCombination: nil
                )
            )
        }
        notifyBindingsChanged()
    }

    func activeOwner(
        for combination: KeyCombination,
        profileID: UUID
    ) throws -> ExtensionCommandBindingAssignment? {
        try assignments(profileID: profileID).first {
            $0.activeCombination?.lookupKey == combination.lookupKey
        }
    }

    private func replacementOwner(
        for combination: KeyCombination,
        excluding identity: ExtensionCommandBindingIdentity
    ) throws -> ReplacementOwner? {
        if let action = try KeyboardCommandAssignments.activeBrowserOwners(
            database: database
        )[combination.lookupKey] {
            return .browser(action)
        }
        return try assignments(profileID: identity.profileID)
            .first {
                $0.identity != identity
                    && $0.activeCombination?.lookupKey == combination.lookupKey
            }
            .map { .extensionCommand($0.identity) }
    }

    private func declarations(profileID: UUID) throws -> [Declaration] {
        let extensions: [InstalledExtension] = try database.read { connection in
            let metadata = try connection.extensions.all()
            return metadata.compactMap { item -> InstalledExtension? in
                InstalledExtension(from: item)
            }
        }
        return extensions.flatMap { extensionRecord -> [Declaration] in
            guard let commands = extensionRecord.manifest["commands"]
                as? [String: Any] else {
                return []
            }
            return commands.compactMap { name, value in
                guard let command = value as? [String: Any] else { return nil }
                let suggestedKey = Self.suggestedKey(
                    from: command["suggested_key"]
                )
                return Declaration(
                    identity: ExtensionCommandBindingIdentity(
                        profileID: profileID,
                        extensionID: extensionRecord.id,
                        commandName: name
                    ),
                    extensionName: extensionRecord.name,
                    title: ((command["description"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines))
                        .flatMap { $0.isEmpty ? nil : $0 }
                        ?? Self.humanizedCommandName(name),
                    suggestedKey: suggestedKey,
                    isGlobal: command["global"] as? Bool == true,
                    isMedia: suggestedKey?.split(separator: "+").last?
                        .lowercased().hasPrefix("media") == true
                )
            }
        }
    }

    private func notifyBindingsChanged() {
        NotificationCenter.default.post(
            name: .sumiKeyboardBindingsDidChange,
            object: database
        )
    }

    private static func suggestedKey(from value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty { return value }
        guard let values = value as? [String: Any] else { return nil }
        return (values["mac"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (values["default"] as? String).flatMap {
                $0.isEmpty ? nil : $0
            }
    }

    static func parseSuggestedKey(_ rawValue: String?) -> KeyCombination? {
        guard let rawValue else { return nil }
        let parts = rawValue.split(separator: "+").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let rawKey = parts.last, !rawKey.isEmpty else { return nil }
        var modifiers: Modifiers = []
        for modifier in parts.dropLast() {
            switch modifier.lowercased() {
            case "ctrl", "command", "cmd":
                modifiers.insert(.command)
            case "macctrl", "control":
                modifiers.insert(.control)
            case "alt", "option":
                modifiers.insert(.option)
            case "shift":
                modifiers.insert(.shift)
            default:
                return nil
            }
        }
        let key: String
        switch rawKey.lowercased() {
        case "comma": key = ","
        case "period": key = "."
        case "left": key = "leftarrow"
        case "right": key = "rightarrow"
        case "up": key = "uparrow"
        case "down": key = "downarrow"
        case "space": key = "space"
        case "pageup": key = "pageup"
        case "pagedown": key = "pagedown"
        case "home": key = "home"
        case "end": key = "end"
        case "insert": key = "insert"
        case "delete": key = "delete"
        default:
            let normalizedKey = rawKey.lowercased()
            if normalizedKey.first == "f",
               let number = Int(normalizedKey.dropFirst()),
               (1...12).contains(number) {
                key = normalizedKey
            } else {
                guard rawKey.count == 1 else { return nil }
                key = normalizedKey
            }
        }
        return KeyCombination(key: key, modifiers: modifiers)
    }

    private static func isSupportedRegularCombination(
        _ combination: KeyCombination
    ) -> Bool {
        let key = combination.key.lowercased()
        let namedKeys: Set<String> = [
            "home", "end", "pageup", "pagedown", "space", "insert",
            "delete", "leftarrow", "rightarrow", "uparrow", "downarrow",
            "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9",
            "f10", "f11", "f12",
        ]
        let supportedKey = namedKeys.contains(key)
            || (key.count == 1 && key.first?.isLetter == true)
            || (key.count == 1 && key.first?.isNumber == true)
            || key == "," || key == "."
        return supportedKey
            && !combination.modifiers.isDisjoint(with: [
                .command, .control, .option,
            ])
    }

    private static func humanizedCommandName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
