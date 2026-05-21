import XCTest
import AppKit
@testable import Sumi

final class SidebarContextMenuLifecycleTests: XCTestCase {
    private static let spaceA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let spaceB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private static let folderA = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private static let folderB = UUID(uuidString: "00000000-0000-0000-0000-000000000006")!
    private static let profileA = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    private static let profileB = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    private static func noop() {}

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
        let entries = makeSidebarTabContextMenuEntries(
            role: .regularTab,
            capabilities: .init(
                folders: [.init(id: Self.folderA, title: "Project")],
                spaces: [
                    .init(id: Self.spaceA, title: "Current", isSelected: true),
                    .init(id: Self.spaceB, title: "Work"),
                ],
                profiles: [
                    .init(id: Self.profileA, title: "Personal", isSelected: true),
                    .init(id: Self.profileB, title: "Work Profile"),
                ],
                showsAddToEssentials: true,
                canMoveUp: false,
                canMoveDown: true,
                showsCloseTabsBelow: true
            ),
            callbacks: Self.regularCallbacks()
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
                "> Move to…",
                "  Current [disabled] [on]",
                "  Work",
                "> Convert Space to Profile",
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
                profiles: [personalProfile],
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
            profiles: [personalProfile, workProfile],
            selectedSpaceId: currentSpace.id
        )
        XCTAssertEqual(spaceChoices.map(\.title), ["Personal: Current", "Work: Work"])
        XCTAssertTrue(spaceChoices.first?.isSelected == true)

        let profileChoices = makeSidebarContextMenuProfileChoices(
            profiles: [personalProfile, workProfile],
            selectedProfileId: personalProfile.id
        )
        XCTAssertEqual(profileChoices.map(\.title), ["Personal", "Work"])
        XCTAssertTrue(profileChoices.first?.isSelected == true)
    }

    func testContextMenusHideOrganizationActionsWithoutUsefulTargets() {
        let regular = makeSidebarTabContextMenuEntries(
            role: .regularTab,
            capabilities: .init(
                folders: [.init(id: Self.folderA, title: "Project")],
                spaces: [.init(id: Self.spaceA, title: "Only Space", isSelected: true)],
                profiles: [.init(id: Self.profileA, title: "Only Profile", isSelected: true)],
                showsAddToEssentials: false,
                canMoveUp: false,
                canMoveDown: false
            ),
            callbacks: Self.regularCallbacks()
        )
        let regularSnapshot = Self.snapshot(regular)
        XCTAssertTrue(regularSnapshot.contains("> Add to Folder"))
        XCTAssertFalse(regularSnapshot.contains("> Move to…"))
        XCTAssertFalse(regularSnapshot.contains("> Convert Space to Profile"))
        XCTAssertFalse(regularSnapshot.contains("Move Up"))
        XCTAssertFalse(regularSnapshot.contains("Move Down"))
        XCTAssertFalse(regularSnapshot.contains("Add to Essentials"))

        let saved = makeSidebarTabContextMenuEntries(
            role: .essential,
            capabilities: .init(
                folders: [.init(id: Self.folderA, title: "Project")],
                spaces: [.init(id: Self.spaceA, title: "Only Space")],
                profiles: [.init(id: Self.profileA, title: "Only Profile")]
            ),
            callbacks: Self.savedTabCallbacks()
        )
        let savedSnapshot = Self.snapshot(saved)
        XCTAssertTrue(savedSnapshot.contains("> Add to Folder"))
        XCTAssertFalse(savedSnapshot.contains("> Move to…"))
        XCTAssertFalse(savedSnapshot.contains("> Convert Space to Profile"))

        let folderPinnedOnlyCurrentFolder = makeSidebarTabContextMenuEntries(
            role: .folderPinnedTab,
            capabilities: .init(
                folders: [.init(id: Self.folderA, title: "Project", isSelected: true)]
            ),
            callbacks: Self.savedTabCallbacks()
        )
        XCTAssertFalse(Self.snapshot(folderPinnedOnlyCurrentFolder).contains("> Move to Folder"))
    }

    func testEssentialContextMenuSnapshots() {
        let stored = makeSidebarTabContextMenuEntries(
            role: .essential,
            capabilities: .init(),
            callbacks: Self.savedTabCallbacks()
        )
        XCTAssertEqual(
            Self.snapshot(stored),
            [
                "Duplicate as Tab",
                "---",
                "Copy Link",
                "Share…",
                "---",
                "Rename Essential",
                "Change Icon…",
                "Edit URL…",
                "---",
                "Delete Essential [destructive]",
            ]
        )
        XCTAssertFalse(Self.snapshot(stored).contains("Add to Essentials"))
        XCTAssertFalse(Self.snapshot(stored).contains("Unload Essential"))
        XCTAssertFalse(Self.snapshot(stored).contains("> Open in Split"))

        let live = makeSidebarTabContextMenuEntries(
            role: .essential,
            capabilities: .init(hasLiveInstance: true),
            callbacks: Self.savedTabCallbacks(onUnload: Self.noop)
        )
        XCTAssertTrue(Self.snapshot(live).contains("Unload Essential"))

        let drifted = makeSidebarTabContextMenuEntries(
            role: .essential,
            capabilities: .init(
                hasSavedURLDrift: true,
                hasLiveInstance: true
            ),
            callbacks: Self.savedTabCallbacks(
                onBackToSavedURL: Self.noop,
                onUseCurrentPageAsSavedURL: Self.noop,
                onUnload: Self.noop
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
        let stored = makeSidebarTabContextMenuEntries(
            role: .pinnedTab,
            capabilities: .init(
                folders: [.init(id: Self.folderA, title: "Project")],
                spaces: [
                    .init(id: Self.spaceA, title: "Personal: Current", isSelected: true),
                    .init(id: Self.spaceB, title: "Work Profile: Work"),
                ],
                profiles: [
                    .init(id: Self.profileA, title: "Personal", isSelected: true),
                    .init(id: Self.profileB, title: "Work Profile"),
                ],
                showsAddToEssentials: true
            ),
            callbacks: Self.savedTabCallbacks()
        )
        XCTAssertEqual(
            Self.snapshot(stored),
            [
                "Duplicate as Tab",
                "---",
                "Copy Link",
                "Share…",
                "---",
                "Rename Pinned Tab",
                "Change Icon…",
                "Edit URL…",
                "---",
                "Add to Essentials",
                "> Add to Folder",
                "  Project",
                "> Move to…",
                "  Personal: Current [disabled] [on]",
                "  Work Profile: Work",
                "> Convert Space to Profile",
                "  Personal [disabled] [on]",
                "  Work Profile",
                "---",
                "Delete Pinned Tab [destructive]",
            ]
        )

        let live = makeSidebarTabContextMenuEntries(
            role: .pinnedTab,
            capabilities: .init(hasLiveInstance: true),
            callbacks: Self.savedTabCallbacks(onUnload: Self.noop)
        )
        XCTAssertTrue(Self.snapshot(live).contains("Unload Pinned Tab"))
        XCTAssertFalse(Self.snapshot(live).contains("Add to Essentials"))

        let driftedFolderPinned = makeSidebarTabContextMenuEntries(
            role: .folderPinnedTab,
            capabilities: .init(
                folders: [
                    .init(id: Self.folderA, title: "Project", isSelected: true),
                    .init(id: Self.folderB, title: "Archive"),
                ],
                hasSavedURLDrift: true,
                hasLiveInstance: true
            ),
            callbacks: Self.savedTabCallbacks(
                onBackToSavedURL: Self.noop,
                onUseCurrentPageAsSavedURL: Self.noop,
                onUnload: Self.noop
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
        XCTAssertTrue(folderPinnedSnapshot.contains("  Project [disabled] [on]"))
        XCTAssertFalse(folderPinnedSnapshot.contains("> Add to Folder"))
        XCTAssertTrue(folderPinnedSnapshot.contains("Delete Pinned Tab [destructive]"))
    }

    func testFolderHeaderAndSidebarBackgroundSnapshots() {
        let folderHeader = makeFolderHeaderContextMenuEntries(
            hasCustomIcon: true,
            showsUnloadActiveTabs: true,
            callbacks: .init(
                onRename: Self.noop,
                onChangeIcon: Self.noop,
                onResetIcon: Self.noop,
                onAddTab: Self.noop,
                onAlphabetize: Self.noop,
                onUnloadActiveTabs: Self.noop,
                onDelete: Self.noop
            )
        )
        XCTAssertEqual(
            Self.snapshot(folderHeader),
            [
                "Rename Folder",
                "Change Folder Icon…",
                "Reset Folder Icon",
                "---",
                "New Tab in Folder",
                "Sort by Name",
                "Unload Active Tabs in Folder",
                "---",
                "Delete Folder [destructive]",
            ]
        )

        let background = makeSidebarShellContextMenuEntries(
            isCompactModeEnabled: true,
            callbacks: .init(
                onNewTab: Self.noop,
                onNewSplit: Self.noop,
                onToggleCompactMode: Self.noop,
                onOpenSettings: Self.noop
            )
        )
        XCTAssertEqual(
            Self.snapshot(background),
            [
                "New Tab",
                "New Split",
                "---",
                "Toggle Compact Mode [on]",
                "Sidebar Settings…",
            ]
        )
        XCTAssertFalse(Self.snapshot(background).contains("Create Folder"))
        XCTAssertFalse(Self.snapshot(background).contains { $0.contains("Selected Tab") })
    }

    func testSavedTabRuntimeActionsAreSeparatedFromDeleteActions() {
        var didUnload = false
        var didDelete = false
        let entries = makeSidebarTabContextMenuEntries(
            role: .pinnedTab,
            capabilities: .init(hasLiveInstance: true),
            callbacks: Self.savedTabCallbacks(
                onUnload: { didUnload = true },
                onDeleteSavedTab: { didDelete = true }
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
            "Sumi/Components/Sidebar/SpaceSection/ShortcutLinkEditorSheet.swift",
            "Sumi/Managers/DialogManager/Dialogs/SpaceDeleteConfirmationDialog.swift",
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

    private static func regularCallbacks() -> SidebarTabContextMenuCallbacks {
        .init(
            onDuplicate: noop,
            onCopyLink: noop,
            onShare: noop,
            onRename: noop,
            onMoveToFolder: { _ in },
            onMoveToSpace: { _ in },
            onConvertSpaceToProfile: { _ in },
            onMoveUp: noop,
            onMoveDown: noop,
            onPinToSpace: noop,
            onAddToEssentials: noop,
            onCloseTabsBelow: noop,
            onClose: noop
        )
    }

    private static func savedTabCallbacks(
        onBackToSavedURL: (() -> Void)? = nil,
        onUseCurrentPageAsSavedURL: (() -> Void)? = nil,
        onUnload: (() -> Void)? = nil,
        onDeleteSavedTab: @escaping () -> Void = {}
    ) -> SidebarTabContextMenuCallbacks {
        .init(
            onDuplicate: noop,
            onCopyLink: noop,
            onShare: noop,
            onRename: noop,
            onMoveToFolder: { _ in },
            onMoveToSpace: { _ in },
            onConvertSpaceToProfile: { _ in },
            onAddToEssentials: noop,
            onBackToSavedURL: onBackToSavedURL,
            onUseCurrentPageAsSavedURL: onUseCurrentPageAsSavedURL,
            onChangeIcon: noop,
            onEditURL: noop,
            onUnload: onUnload,
            onDeleteSavedTab: onDeleteSavedTab
        )
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
