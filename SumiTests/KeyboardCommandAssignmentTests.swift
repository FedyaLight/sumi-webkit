import XCTest

@testable import Sumi
import SumiDomain

final class KeyboardCommandAssignmentTests: XCTestCase {
    private struct LegacyOverride: Codable {
        let action: ShortcutAction
        let keyCombination: KeyCombination?
    }

    func testMigratedUserBindingWinsOverAConflictingSuggestion() throws {
        let suiteName = "KeyboardCommandAssignmentTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let replacement = KeyCombination(key: "r", modifiers: [.command])
        defaults.set(
            try JSONEncoder().encode([
                LegacyOverride(action: .newTab, keyCombination: replacement),
            ]),
            forKey: "keyboard.shortcuts"
        )

        let assignments = try KeyboardCommandAssignments(
            database: SumiDatabase.inMemory(),
            legacyDefaults: defaults
        )

        XCTAssertEqual(
            assignments.assignment(for: .newTab).activeCombination,
            replacement
        )
        XCTAssertNil(
            assignments.assignment(for: .refresh).activeCombination
        )
        XCTAssertEqual(
            assignments.assignment(for: .refresh).inactiveReason,
            .conflict(.newTab)
        )
    }

    func testLegacyImportPreservesValidSiblingAndKeepsNativeCommandInactive() throws {
        let suiteName = "KeyboardCommandAssignmentTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyData = try JSONEncoder().encode([
            LegacyOverride(
                action: .newTab,
                keyCombination: KeyCombination(
                    key: "k",
                    modifiers: [.command, .option]
                )
            ),
            LegacyOverride(
                action: .openSettings,
                keyCombination: KeyCombination(key: ",", modifiers: [.command])
            ),
        ])
        defaults.set(legacyData, forKey: "keyboard.shortcuts")

        let assignments = try KeyboardCommandAssignments(
            database: SumiDatabase.inMemory(),
            legacyDefaults: defaults
        )

        XCTAssertEqual(
            assignments.assignment(for: .newTab),
            BrowserActionBindingAssignment(
                action: .newTab,
                assignedCombination: KeyCombination(
                    key: "k",
                    modifiers: [.command, .option]
                ),
                activeCombination: KeyCombination(
                    key: "k",
                    modifiers: [.command, .option]
                ),
                origin: .userAssigned,
                inactiveReason: nil
            )
        )
        XCTAssertEqual(
            assignments.assignment(for: .openSettings),
            BrowserActionBindingAssignment(
                action: .openSettings,
                assignedCombination: KeyCombination(
                    key: ",",
                    modifiers: [.command]
                ),
                activeCombination: nil,
                origin: .userAssigned,
                inactiveReason: .nativeReservation
            )
        )
        XCTAssertEqual(
            try assignments.legacyMigrationBackup(),
            legacyData
        )
    }

    func testUserAssignmentAndExplicitClearSurviveRecreation() throws {
        let suiteName = "KeyboardCommandAssignmentTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let database = try SumiDatabase.inMemory()
        let replacement = KeyCombination(
            key: "k",
            modifiers: [.command, .option]
        )
        var assignments = try KeyboardCommandAssignments(
            database: database,
            legacyDefaults: defaults
        )

        try assignments.assign(replacement, to: .newTab)
        try assignments.clear(.undoCloseTab)
        assignments = try KeyboardCommandAssignments(
            database: database,
            legacyDefaults: defaults
        )

        XCTAssertEqual(
            assignments.assignment(for: .newTab).activeCombination,
            replacement
        )
        XCTAssertEqual(
            assignments.assignment(for: .undoCloseTab).origin,
            .explicitlyCleared
        )
        XCTAssertNil(
            assignments.assignment(for: .undoCloseTab).assignedCombination
        )
    }

    @MainActor
    func testConflictingAssignmentAtomicallyClearsPreviousOwner() throws {
        let suiteName = "KeyboardCommandAssignmentTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let database = try SumiDatabase.inMemory()
        let commandR = KeyCombination(key: "r", modifiers: [.command])
        var manager = KeyboardShortcutManager(
            userDefaults: defaults,
            database: database
        )

        XCTAssertEqual(
            manager.setShortcut(action: .newTab, keyCombination: commandR),
            .valid
        )
        manager = KeyboardShortcutManager(
            userDefaults: defaults,
            database: database
        )

        XCTAssertEqual(manager.shortcut(for: .newTab)?.keyCombination, commandR)
        XCTAssertNil(manager.shortcut(for: .refresh))
    }

    func testExtensionProjectionUsesChromeMacModifiersAndRejectsUnsupportedScopes() throws {
        let database = try SumiDatabase.inMemory()
        let profileID = UUID()
        try saveExtension(
            manifestCommands: [
                "regular": [
                    "description": "Regular Command",
                    "suggested_key": ["default": "Alt+Shift+U"],
                ],
                "browser-conflict": [
                    "suggested_key": ["default": "Ctrl+R"],
                ],
                "media": [
                    "suggested_key": ["default": "MediaPlayPause"],
                ],
                "global": [
                    "suggested_key": ["default": "Alt+G"],
                    "global": true,
                ],
            ],
            database: database
        )

        let projected = try ExtensionCommandAssignments(
            database: database
        ).assignments(profileID: profileID)

        XCTAssertEqual(
            projected.first { $0.identity.commandName == "regular" }?
                .activeCombination,
            KeyCombination(key: "u", modifiers: [.option, .shift])
        )
        XCTAssertEqual(
            projected.first {
                $0.identity.commandName == "browser-conflict"
            }?.inactiveReason,
            .browserConflict(.refresh)
        )
        XCTAssertEqual(
            projected.first { $0.identity.commandName == "media" }?
                .inactiveReason,
            .unsupportedMedia
        )
        XCTAssertEqual(
            projected.first { $0.identity.commandName == "global" }?
                .inactiveReason,
            .unsupportedGlobal
        )
    }

    @MainActor
    func testConfirmedExtensionReplacementClearsBrowserOwnerAtomically() throws {
        let database = try SumiDatabase.inMemory()
        let profileID = UUID()
        try saveExtension(
            manifestCommands: [
                "regular": ["description": "Regular Command"],
            ],
            database: database
        )
        let manager = KeyboardShortcutManager(database: database)
        let identity = try XCTUnwrap(
            manager.extensionCommandAssignments(profileID: profileID).first?
                .identity
        )
        let commandT = KeyCombination(key: "t", modifiers: [.command])

        XCTAssertEqual(
            manager.validateExtensionCommand(commandT, identity: identity),
            .conflict(.newTab)
        )
        XCTAssertEqual(
            manager.setExtensionCommand(commandT, identity: identity),
            .valid
        )
        XCTAssertNil(manager.shortcut(for: .newTab))
        XCTAssertEqual(
            manager.extensionCommandAssignments(profileID: profileID).first?
                .activeCombination,
            commandT
        )

        XCTAssertEqual(
            manager.validate(
                commandT,
                excludingAction: .newWindow,
                profileID: profileID
            ),
            .namedConflict("Regular Command")
        )
        XCTAssertEqual(
            manager.setShortcut(
                action: .newWindow,
                keyCombination: commandT,
                profileID: profileID
            ),
            .valid
        )
        XCTAssertEqual(manager.shortcut(for: .newWindow)?.keyCombination, commandT)
        XCTAssertNil(
            manager.extensionCommandAssignments(profileID: profileID).first?
                .activeCombination
        )
    }

    @MainActor
    func testGlobalRealmScopeSharesExtensionCommandsAcrossProfiles() throws {
        let database = try SumiDatabase.inMemory()
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let realmID = UUID()
        try saveExtension(
            manifestCommands: [
                "toggle": ["description": "Toggle"],
            ],
            database: database
        )
        let manager = KeyboardShortcutManager(
            database: database,
            extensionCommandProfileScopeID: { _ in realmID }
        )
        let firstIdentity = try XCTUnwrap(
            manager.extensionCommandAssignments(profileID: firstProfileID)
                .first?.identity
        )
        let combination = KeyCombination(
            key: "u",
            modifiers: [.option, .shift]
        )

        XCTAssertEqual(firstIdentity.profileID, realmID)
        XCTAssertEqual(
            manager.setExtensionCommand(
                combination,
                identity: firstIdentity
            ),
            .valid
        )
        XCTAssertEqual(
            manager.extensionCommandAssignments(profileID: secondProfileID)
                .first?.activeCombination,
            combination
        )
    }

    func testDeletingLegacyExtensionBindingsKeepsTheGlobalBinding() throws {
        let database = try SumiDatabase.inMemory()
        let legacyProfileID = UUID()
        let realmID = UUID()
        try database.transaction { connection in
            for profileID in [legacyProfileID, realmID] {
                try connection.keyboardBindings.save(
                    ExtensionCommandBindingRecord(
                        identity: .init(
                            profileID: profileID,
                            extensionID: "extension-fixture",
                            commandName: "toggle"
                        ),
                        disposition: .explicitlyCleared,
                        keyCombination: nil
                    )
                )
            }
            try connection.keyboardBindings.deleteExtensionCommandBindings(
                profileIDs: [legacyProfileID]
            )
        }

        let remaining = try database.read {
            try $0.keyboardBindings.extensionCommandBindings()
        }
        XCTAssertEqual(remaining.map(\.profileID), [realmID])
    }

    private func saveExtension(
        manifestCommands: [String: Any],
        database: SumiDatabase
    ) throws {
        let record = InstalledExtension(
            id: "extension-fixture",
            name: "Extension Fixture",
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: true,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: "/tmp/extension-fixture",
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .serviceWorker,
            incognitoMode: .spanning,
            sourcePathFingerprint: "source",
            manifestRootFingerprint: "manifest",
            sourceBundlePath: "",
            optionsPagePath: nil,
            defaultPopupPath: nil,
            hasBackground: true,
            hasAction: false,
            hasOptionsPage: false,
            hasContentScripts: false,
            hasExtensionPages: false,
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: [],
                broadScope: false,
                hasContentScripts: false,
                hasAction: false,
                hasOptionsPage: false,
                hasExtensionPages: false
            ),
            manifest: ["commands": manifestCommands]
        )
        try database.transaction { connection in
            try connection.extensions.save(
                InstalledExtensionMetadata(record: record)
            )
        }
    }
}
