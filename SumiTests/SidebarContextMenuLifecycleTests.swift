import AppKit
@testable import Sumi
import XCTest

final class SidebarContextMenuLifecycleTests: XCTestCase {
    private static let spaceA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let spaceB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let folderA = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private static let folderB = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
    private static let profileA = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    private static let profileB = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    private static func noop() { /* no-op */ }

    func testPopupReturnFinalizesClosedVisibleMenu() {
        XCTAssertEqual(
            SidebarContextMenuPopupReturnPolicy.finalizationReason(
                didBecomeVisible: true,
                didClose: true
            ),
            "popup-return-after-close"
        )
    }

    func testPopupReturnFinalizesMenuThatNeverOpened() {
        XCTAssertEqual(
            SidebarContextMenuPopupReturnPolicy.finalizationReason(
                didBecomeVisible: false,
                didClose: false
            ),
            "popup-return-before-open"
        )
    }

    func testPopupReturnDoesNotFinalizeVisibleMenuWithoutCloseSignal() {
        XCTAssertNil(
            SidebarContextMenuPopupReturnPolicy.finalizationReason(
                didBecomeVisible: true,
                didClose: false
            )
        )
    }

    func testContextMenuControllerKeepsRootMenuAliveUntilFinalization() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SidebarContextMenuController.swift")

        XCTAssertTrue(source.contains("private var activeRootMenu: NSMenu?"))
        XCTAssertFalse(source.contains("private weak var activeRootMenu: NSMenu?"))
    }

    func testRegularTabContextMenuSnapshot() {
        let folders: [SidebarContextMenuChoice] = [.init(id: Self.folderA, title: "Project")]
        let spaces: [SidebarContextMenuChoice] = [
            .init(id: Self.spaceA, title: "Current", isSelected: true),
            .init(id: Self.spaceB, title: "Work"),
        ]
        let profiles: [SidebarContextMenuChoice] = [
            .init(id: Self.profileA, title: "Personal", isSelected: true),
            .init(id: Self.profileB, title: "Work Profile"),
        ]
        let entries = makeSidebarTabContextMenuEntries(
            role: .regularTab,
            actions: Self.regularActions(
                folders: folders,
                spaces: spaces,
                profiles: profiles,
                moveUp: nil
            )
        )

        XCTAssertEqual(
            Self.snapshot(entries),
            [
                "Duplicate Tab",
                "---",
                "Copy Link",
                "Share…",
                "Rename Tab",
                "---",
                "> Add to Folder",
                "  Project",
                "> Move to Space",
                "  Work",
                "> Use Profile",
                "  Personal [disabled] [on]",
                "  Work Profile",
                "Move Down",
                "---",
                "Pin to This Space",
                "Add to Essentials",
                "---",
                "Close Tabs Below",
                "Close Tab [destructive]",
            ]
        )
    }

    @MainActor
    func testChoiceFactoriesHideSingleSpaceAndSingleProfile() {
        let personalProfile = Profile(id: Self.profileA, name: "Personal")
        let workProfile = Profile(id: Self.profileB, name: "Work")
        let currentSpace = Space(id: Self.spaceA, name: "Current", profileId: personalProfile.id)
        let workSpace = Space(id: Self.spaceB, name: "Work", profileId: workProfile.id)

        XCTAssertTrue(
            makeSidebarContextMenuSpaceChoices(
                spaces: [currentSpace],
                selectedSpaceId: currentSpace.id
            ).isEmpty
        )
        XCTAssertTrue(
            makeSidebarContextMenuProfileChoices(
                profiles: [personalProfile],
                selectedProfileId: personalProfile.id
            ).isEmpty
        )

        let spaceChoices = makeSidebarContextMenuSpaceChoices(
            spaces: [currentSpace, workSpace],
            selectedSpaceId: currentSpace.id
        )
        XCTAssertEqual(spaceChoices.map(\.title), ["Current", "Work"])
        XCTAssertEqual(spaceChoices.first?.isSelected, true)

        let profileChoices = makeSidebarContextMenuProfileChoices(
            profiles: [personalProfile, workProfile],
            selectedProfileId: personalProfile.id
        )
        XCTAssertEqual(profileChoices.map(\.title), ["Personal", "Work"])
        XCTAssertEqual(profileChoices.first?.isSelected, true)
    }

    @MainActor
    func testChoiceFactoriesPreserveSpaceProfileAndFolderIcons() {
        XCTAssertFalse(SumiPersistentGlyph.presentsAsEmoji("square.grid.2x2"))

        let personalProfile = Profile(id: Self.profileA, name: "Personal", icon: "😀")
        let workProfile = Profile(id: Self.profileB, name: "Work", icon: "💼")
        let currentSpace = Space(id: Self.spaceA, name: "Current", icon: "✨", profileId: personalProfile.id)
        let workSpace = Space(id: Self.spaceB, name: "Work", icon: "square.grid.2x2", profileId: workProfile.id)
        let folder = TabFolder(
            id: Self.folderA,
            name: "Project",
            spaceId: Self.spaceA,
            icon: SumiZenFolderIconCatalog.storageValue(for: "folder")
        )

        let spaceChoices = makeSidebarContextMenuSpaceChoices(
            spaces: [currentSpace, workSpace],
            selectedSpaceId: currentSpace.id
        )
        XCTAssertEqual(spaceChoices.first?.icon, .emoji("✨"))
        XCTAssertEqual(spaceChoices.last?.icon, .systemImage("square.grid.2x2"))

        let profileChoices = makeSidebarContextMenuProfileChoices(
            profiles: [personalProfile, workProfile],
            selectedProfileId: personalProfile.id
        )
        XCTAssertEqual(profileChoices.first?.icon, .emoji("😀"))
        XCTAssertEqual(profileChoices.last?.icon, .emoji("💼"))

        let folderChoices = makeSidebarContextMenuFolderChoices(folders: [folder])
        XCTAssertEqual(
            folderChoices.first?.icon,
            .folderIcon(SumiZenFolderIconCatalog.storageValue(for: "folder"))
        )
    }

    func testContextMenusHideOrganizationActionsWithoutUsefulTargets() {
        let regular = makeSidebarTabContextMenuEntries(
            role: .regularTab,
            actions: Self.regularActions(
                folders: [.init(id: Self.folderA, title: "Project")],
                spaces: [.init(id: Self.spaceA, title: "Only Space", isSelected: true)],
                profiles: [.init(id: Self.profileA, title: "Only Profile", isSelected: true)],
                moveUp: nil,
                moveDown: nil,
                addToEssentials: nil,
                closeTabsBelow: nil
            )
        )
        let regularSnapshot = Self.snapshot(regular)
        XCTAssertTrue(regularSnapshot.contains("> Add to Folder"))
        XCTAssertFalse(regularSnapshot.contains("> Move to Space"))
        XCTAssertFalse(regularSnapshot.contains("> Move to Space…"))
        XCTAssertFalse(regularSnapshot.contains("> Use Profile"))
        XCTAssertFalse(regularSnapshot.contains("Move Up"))
        XCTAssertFalse(regularSnapshot.contains("Move Down"))
        XCTAssertFalse(regularSnapshot.contains("Add to Essentials"))

        let saved = makeSidebarTabContextMenuEntries(
            role: .essential,
            actions: Self.savedTabActions(
                folders: [.init(id: Self.folderA, title: "Project")],
                spaces: [.init(id: Self.spaceA, title: "Only Space", isSelected: true)],
                profiles: [.init(id: Self.profileA, title: "Only Profile", isSelected: true)]
            )
        )
        let savedSnapshot = Self.snapshot(saved)
        XCTAssertTrue(savedSnapshot.contains("> Add to Folder"))
        XCTAssertFalse(savedSnapshot.contains("> Move to Space"))
        XCTAssertFalse(savedSnapshot.contains("> Move to Space…"))
        XCTAssertFalse(savedSnapshot.contains("> Use Profile"))

        let folderPinnedOnlyCurrentFolder = makeSidebarTabContextMenuEntries(
            role: .folderPinnedTab,
            actions: Self.savedTabActions(
                folders: [.init(id: Self.folderA, title: "Project", isSelected: true)]
            )
        )
        XCTAssertFalse(Self.snapshot(folderPinnedOnlyCurrentFolder).contains("> Move to Folder"))
    }

    func testEssentialContextMenuSnapshots() {
        let stored = makeSidebarTabContextMenuEntries(
            role: .essential,
            actions: Self.savedTabActions()
        )
        XCTAssertEqual(
            Self.snapshot(stored),
            [
                "Duplicate as Tab",
                "---",
                "Copy Link",
                "Share…",
                "---",
                "Edit",
                "---",
                "Delete Essential [destructive]",
            ]
        )
        XCTAssertFalse(Self.snapshot(stored).contains("Add to Essentials"))
        XCTAssertFalse(Self.snapshot(stored).contains("Unload Essential"))
        XCTAssertFalse(Self.snapshot(stored).contains("> Open in Split"))

        let live = makeSidebarTabContextMenuEntries(
            role: .essential,
            actions: Self.savedTabActions(unload: Self.noop)
        )
        XCTAssertTrue(Self.snapshot(live).contains("Unload Essential"))

        let drifted = makeSidebarTabContextMenuEntries(
            role: .essential,
            actions: Self.savedTabActions(
                onBackToSavedURL: Self.noop,
                onUseCurrentPageAsSavedURL: Self.noop,
                unload: Self.noop
            )
        )
        XCTAssertEqual(
            Self.snapshot(drifted).filter { $0.contains("Essential URL") },
            [
                "Back to Essential URL",
                "Use Current Page as Essential URL",
            ]
        )
    }

    func testPinnedTabContextMenuSnapshots() {
        let folders: [SidebarContextMenuChoice] = [.init(id: Self.folderA, title: "Project")]
        let spaces: [SidebarContextMenuChoice] = [
            .init(id: Self.spaceA, title: "Current", isSelected: true),
            .init(id: Self.spaceB, title: "Work"),
        ]
        let profiles: [SidebarContextMenuChoice] = [
            .init(id: Self.profileA, title: "Personal", isSelected: true),
            .init(id: Self.profileB, title: "Work Profile"),
        ]
        let stored = makeSidebarTabContextMenuEntries(
            role: .pinnedTab,
            actions: Self.savedTabActions(
                folders: folders,
                spaces: spaces,
                profiles: profiles,
                addToEssentials: Self.noop
            )
        )
        XCTAssertEqual(
            Self.snapshot(stored),
            [
                "Duplicate as Tab",
                "---",
                "Copy Link",
                "Share…",
                "---",
                "Edit",
                "---",
                "Add to Essentials",
                "> Add to Folder",
                "  Project",
                "> Move to Space",
                "  Work",
                "> Use Profile",
                "  Personal [disabled] [on]",
                "  Work Profile",
                "---",
                "Delete Pinned Tab [destructive]",
            ]
        )

        let live = makeSidebarTabContextMenuEntries(
            role: .pinnedTab,
            actions: Self.savedTabActions(unload: Self.noop)
        )
        XCTAssertTrue(Self.snapshot(live).contains("Unload Pinned Tab"))
        XCTAssertFalse(Self.snapshot(live).contains("Add to Essentials"))

        let driftedFolderPinned = makeSidebarTabContextMenuEntries(
            role: .folderPinnedTab,
            actions: Self.savedTabActions(
                folders: [
                    .init(id: Self.folderA, title: "Project", isSelected: true),
                    .init(id: Self.folderB, title: "Archive"),
                ],
                onBackToSavedURL: Self.noop,
                onUseCurrentPageAsSavedURL: Self.noop,
                unload: Self.noop
            )
        )
        let folderPinnedSnapshot = Self.snapshot(driftedFolderPinned)
        XCTAssertEqual(
            folderPinnedSnapshot.filter { $0.contains("Pinned Tab URL") },
            [
                "Back to Pinned Tab URL",
                "Use Current Page as Pinned Tab URL",
            ]
        )
        XCTAssertTrue(folderPinnedSnapshot.contains("> Move to Folder"))
        XCTAssertFalse(folderPinnedSnapshot.contains("  Project [disabled] [on]"))
        XCTAssertTrue(folderPinnedSnapshot.contains("  Archive"))
        XCTAssertFalse(folderPinnedSnapshot.contains("> Add to Folder"))
        XCTAssertTrue(folderPinnedSnapshot.contains("Delete Pinned Tab [destructive]"))
    }

    func testMoveToSpaceUsesSubmenuForLongDestinationLists() {
        let spaces = (0..<10).map { index in
            SidebarContextMenuChoice(
                id: UUID(),
                title: "Space \(index)",
                isSelected: index == 0
            )
        }
        let entries = makeSidebarTabContextMenuEntries(
            role: .regularTab,
            actions: Self.regularActions(
                spaces: spaces
            )
        )
        let snapshot = Self.snapshot(entries)

        XCTAssertFalse(snapshot.contains("Move to Space…"))
        XCTAssertTrue(snapshot.contains("> Move to Space"))
        XCTAssertEqual(snapshot.filter { $0.hasPrefix("  Space ") }.count, 9)
    }

    @MainActor
    func testContextMenuBuilderRendersChoiceIcons() {
        let entries: [SidebarContextMenuEntry] = [
            .submenu(
                title: "Move",
                children: [
                    .action(.init(title: "Emoji", icon: .emoji("✨"), action: Self.noop)),
                    .action(.init(title: "Symbol", icon: .systemImage("briefcase"), action: Self.noop)),
                    .action(
                        .init(
                            title: "Folder",
                            icon: .folderIcon(SumiZenFolderIconCatalog.storageValue(for: "folder")),
                            action: Self.noop
                        )
                    ),
                ]
            ),
        ]

        let menu = SidebarContextMenuBuilder(entries: entries).buildMenu()
        let submenuItems = menu.items.first?.submenu?.items ?? []

        XCTAssertEqual(submenuItems.map(\.title), ["Emoji", "Symbol", "Folder"])
        XCTAssertTrue(submenuItems.allSatisfy { $0.image != nil })
        XCTAssertTrue(submenuItems.allSatisfy { $0.image?.size == NSSize(width: 16, height: 16) })

        let secondMenu = SidebarContextMenuBuilder(entries: entries).buildMenu()
        let secondSubmenuItems = secondMenu.items.first?.submenu?.items ?? []
        for (firstItem, secondItem) in zip(submenuItems, secondSubmenuItems) {
            guard let firstImage = firstItem.image, let secondImage = secondItem.image else {
                XCTFail("Expected menu images to be rendered")
                continue
            }
            XCTAssertIdentical(firstImage, secondImage)
        }
    }

    func testFolderHeaderSpaceAndSidebarBackgroundSnapshots() {
        let folderHeader = makeFolderHeaderContextMenuEntries(
            actions: .init(
                edit: Self.noop,
                alphabetize: Self.noop,
                unloadActiveTabs: Self.noop,
                ungroup: Self.noop,
                delete: Self.noop
            )
        )
        XCTAssertEqual(
            Self.snapshot(folderHeader),
            [
                "Edit",
                "---",
                "Sort by Name",
                "Unload Active Tabs in Folder",
                "---",
                "Ungroup Folder",
                "Delete Folder [destructive]",
            ]
        )

        let spaceMenu = makeSpaceContextMenuEntries(
            actions: .init(
                edit: Self.noop,
                changeTheme: Self.noop,
                deleteSpace: Self.noop
            )
        )
        XCTAssertEqual(
            Self.snapshot(spaceMenu),
            [
                "Edit",
                "Change Theme",
                "---",
                "Delete Space [destructive]",
            ]
        )

        let background = makeSidebarShellContextMenuEntries(
            isCompactModeEnabled: true,
            actions: .init(
                newTab: Self.noop,
                newFolder: Self.noop,
                changeTheme: Self.noop,
                toggleCompactMode: Self.noop,
                openSettings: Self.noop
            )
        )
        XCTAssertEqual(
            Self.snapshot(background),
            [
                "New Tab",
                "New Folder",
                "---",
                "Change Theme",
                "Toggle Compact Mode [on]",
                "Sidebar Settings…",
            ]
        )
        XCTAssertFalse(Self.snapshot(background).contains("Create Folder"))
        XCTAssertFalse(Self.snapshot(background).contains("New Split"))
        XCTAssertFalse(Self.snapshot(background).contains { $0.contains("Selected Tab") })

        let backgroundWithoutFolder = makeSidebarShellContextMenuEntries(
            isCompactModeEnabled: false,
            actions: .init(
                newTab: Self.noop,
                newFolder: nil,
                changeTheme: Self.noop,
                toggleCompactMode: Self.noop,
                openSettings: Self.noop
            )
        )
        XCTAssertFalse(Self.snapshot(backgroundWithoutFolder).contains("New Folder"))
    }

    func testSavedTabRuntimeActionsAreSeparatedFromDeleteActions() {
        var didUnload = false
        var didDelete = false
        let entries = makeSidebarTabContextMenuEntries(
            role: .pinnedTab,
            actions: Self.savedTabActions(
                unload: { didUnload = true },
                deleteSavedTab: { didDelete = true }
            )
        )

        Self.action(named: "Unload Pinned Tab", in: entries)?.action()
        XCTAssertTrue(didUnload)
        XCTAssertFalse(didDelete)

        Self.action(named: "Delete Pinned Tab", in: entries)?.action()
        XCTAssertTrue(didDelete)
    }

    func testMenuDialogAndAccessibilityStringLiteralsDoNotUseLauncher() throws {
        let files = [
            "App/SumiHistoryCommands.swift",
            "Sumi/Components/Sidebar/SidebarMenuFactories.swift",
            "Sumi/Components/Sidebar/SidebarSavedItemDeletionConfirmationPresenter.swift",
            "Sumi/Components/Sidebar/SpaceSection/ShortcutLinkEditorSheet.swift",
        ]
        let regex = try NSRegularExpression(pattern: #""(?:[^"\\\n]|\\.)*Launcher(?:[^"\\\n]|\\.)*""#)

        for file in files {
            let source = try Self.source(named: file)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            XCTAssertNil(
                regex.firstMatch(in: source, range: range),
                "Unexpected user-facing Launcher string literal in \(file)"
            )
        }
    }

    private static func source(named path: String) throws -> String {
        let url = repoRoot.appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func snapshot(_ entries: [SidebarContextMenuEntry], level: Int = 0) -> [String] {
        entries.flatMap { entry -> [String] in
            let prefix = String(repeating: "  ", count: level)
            switch entry {
            case .action(let action):
                var suffix = ""
                if action.isEnabled == false {
                    suffix += " [disabled]"
                }
                if action.state == .on {
                    suffix += " [on]"
                }
                if case .destructive = action.role {
                    suffix += " [destructive]"
                }
                return ["\(prefix)\(action.title)\(suffix)"]
            case .submenu(let title, _, let children):
                return ["\(prefix)> \(title)"] + snapshot(children, level: level + 1)
            case .separator:
                return ["\(prefix)---"]
            }
        }
    }

    private static func action(
        named title: String,
        in entries: [SidebarContextMenuEntry]
    ) -> SidebarContextMenuAction? {
        for entry in entries {
            switch entry {
            case .action(let action) where action.title == title:
                return action
            case .submenu(_, _, let children):
                if let found = action(named: title, in: children) {
                    return found
                }
            case .action, .separator:
                continue
            }
        }
        return nil
    }

    private static func choiceAction(_ choices: [SidebarContextMenuChoice]) -> SidebarChoiceMenuAction {
        .init(
            choices: choices,
            onSelect: { _ in /* no-op */ }
        )
    }

    private static func spaceDestinationAction(
        _ choices: [SidebarContextMenuChoice]
    ) -> SidebarSpaceDestinationAction {
        .init(
            choices: choices,
            onSelect: { _ in /* no-op */ }
        )
    }

    private static func regularActions(
        folders: [SidebarContextMenuChoice] = [],
        spaces: [SidebarContextMenuChoice] = [],
        profiles: [SidebarContextMenuChoice] = [],
        moveUp: (() -> Void)? = { /* no-op */ },
        moveDown: (() -> Void)? = { /* no-op */ },
        pinToSpace: (() -> Void)? = { /* no-op */ },
        addToEssentials: (() -> Void)? = { /* no-op */ },
        closeTabsBelow: (() -> Void)? = { /* no-op */ }
    ) -> SidebarTabContextMenuActions {
        SidebarTabContextMenuActions(
            duplicate: noop,
            copyLink: noop,
            share: noop,
            rename: noop,
            folderTarget: choiceAction(folders),
            moveToSpace: spaceDestinationAction(spaces),
            profileTarget: choiceAction(profiles),
            moveUp: moveUp,
            moveDown: moveDown,
            pinToSpace: pinToSpace,
            addToEssentials: addToEssentials,
            closeTabsBelow: closeTabsBelow,
            close: noop
        )
    }

    private static func savedTabActions(
        folders: [SidebarContextMenuChoice] = [],
        spaces: [SidebarContextMenuChoice] = [],
        profiles: [SidebarContextMenuChoice] = [],
        addToEssentials: (() -> Void)? = nil,
        onBackToSavedURL: (() -> Void)? = nil,
        onUseCurrentPageAsSavedURL: (() -> Void)? = nil,
        unload: (() -> Void)? = nil,
        deleteSavedTab: @escaping () -> Void = { /* no-op */ }
    ) -> SidebarTabContextMenuActions {
        let driftActions: SidebarSavedURLDriftActions?
        if let onBackToSavedURL, let onUseCurrentPageAsSavedURL {
            driftActions = SidebarSavedURLDriftActions(
                onBackToSavedURL: onBackToSavedURL,
                onUseCurrentPageAsSavedURL: onUseCurrentPageAsSavedURL
            )
        } else {
            driftActions = nil
        }

        return SidebarTabContextMenuActions(
            duplicate: noop,
            copyLink: noop,
            share: noop,
            rename: noop,
            folderTarget: choiceAction(folders),
            moveToSpace: spaceDestinationAction(spaces),
            profileTarget: choiceAction(profiles),
            addToEssentials: addToEssentials,
            savedURLDrift: driftActions,
            changeIcon: noop,
            editURL: noop,
            unload: unload,
            deleteSavedTab: deleteSavedTab
        )
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
