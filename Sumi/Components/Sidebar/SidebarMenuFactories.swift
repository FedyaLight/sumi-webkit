//
//  SidebarMenuFactories.swift
//  Sumi
//

import AppKit

struct SidebarFolderHeaderMenuActions {
    let edit: () -> Void
    let alphabetize: () -> Void
    let unloadActiveTabs: (() -> Void)?
    let ungroup: () -> Void
    let delete: () -> Void
}

struct SidebarSpaceMenuActions {
    let edit: () -> Void
    let changeTheme: () -> Void
    let deleteSpace: (() -> Void)?
}

struct SidebarShellMenuActions {
    let newTab: () -> Void
    let newFolder: (() -> Void)?
    var newRSSLiveFolder: (() -> Void)?
    var newGitHubPullRequestsLiveFolder: (() -> Void)?
    var newGitHubIssuesLiveFolder: (() -> Void)?
    let changeTheme: (() -> Void)?
    let toggleCompactMode: () -> Void
    let openSettings: () -> Void
}

enum SidebarTabContextMenuRole {
    case regularTab
    case essential
    case pinnedTab
    case folderPinnedTab

    var displayName: String {
        switch self {
        case .regularTab:
            return "Tab"
        case .essential:
            return "Essential"
        case .pinnedTab, .folderPinnedTab:
            return "Pinned Tab"
        }
    }

    var isSavedTab: Bool {
        self != .regularTab
    }
}

struct SidebarChoiceMenuAction {
    let choices: [SidebarContextMenuChoice]
    let onSelect: (UUID) -> Void
}

struct SidebarSpaceDestinationAction {
    let choices: [SidebarContextMenuChoice]
    let onSelect: (UUID) -> Void
}

struct SidebarSavedURLDriftActions {
    let onBackToSavedURL: () -> Void
    let onUseCurrentPageAsSavedURL: () -> Void
}

struct SidebarTabContextMenuActions {
    var duplicate: (() -> Void)?
    var copyLink: (() -> Void)?
    var share: (() -> Void)?
    var edit: (() -> Void)?
    var rename: (() -> Void)?
    var folderTarget: SidebarChoiceMenuAction?
    var moveToSpace: SidebarSpaceDestinationAction?
    var profileTarget: SidebarChoiceMenuAction?
    var moveUp: (() -> Void)?
    var moveDown: (() -> Void)?
    var pinToSpace: (() -> Void)?
    var addToEssentials: (() -> Void)?
    var savedURLDrift: SidebarSavedURLDriftActions?
    var changeIcon: (() -> Void)?
    var editURL: (() -> Void)?
    var unload: (() -> Void)?
    var closeTabsBelow: (() -> Void)?
    var close: (() -> Void)?
    var deleteSavedTab: (() -> Void)?
}

private enum SidebarChoiceSubmenuAvailability {
    case anySelectableChoice
    case multipleChoicesWithSelectableTarget

    func permits(_ choices: [SidebarContextMenuChoice]) -> Bool {
        let hasSelectableChoice = choices.contains { $0.isSelected == false }
        switch self {
        case .anySelectableChoice:
            return hasSelectableChoice
        case .multipleChoicesWithSelectableTarget:
            return choices.count > 1 && hasSelectableChoice
        }
    }
}

func joinSidebarMenuSections(_ sections: [[SidebarContextMenuEntry]]) -> [SidebarContextMenuEntry] {
    sections
        .filter { !$0.isEmpty }
        .enumerated()
        .flatMap { index, section in
            index == 0 ? section : [.separator] + section
        }
}

@MainActor
func makeSidebarContextMenuFolderChoices(
    folders: [TabFolder],
    selectedFolderId: UUID? = nil
) -> [SidebarContextMenuChoice] {
    let foldersById = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })

    func displayTitle(for folder: TabFolder) -> String {
        var names: [String] = [folder.name]
        var parentId = folder.parentFolderId
        var visited: Set<UUID> = [folder.id]

        while let id = parentId,
              !visited.contains(id),
              let parent = foldersById[id] {
            visited.insert(id)
            names.insert(parent.name, at: 0)
            parentId = parent.parentFolderId
        }

        return names.joined(separator: " / ")
    }

    return folders.map { folder in
        SidebarContextMenuChoice(
            id: folder.id,
            title: displayTitle(for: folder),
            icon: .folderIcon(folder.icon),
            isSelected: folder.id == selectedFolderId
        )
    }
}

@MainActor
func makeSidebarContextMenuSpaceChoices(
    spaces: [Space],
    selectedSpaceId: UUID? = nil
) -> [SidebarContextMenuChoice] {
    guard spaces.count > 1 else { return [] }

    return spaces.map { space in
        SidebarContextMenuChoice(
            id: space.id,
            title: space.name,
            icon: sidebarContextMenuPersistentGlyphIcon(
                space.icon,
                fallbackSystemImage: SumiPersistentGlyph.spaceSystemImageFallback
            ),
            isSelected: space.id == selectedSpaceId
        )
    }
}

@MainActor
func makeSidebarContextMenuProfileChoices(
    profiles: [Profile],
    selectedProfileId: UUID? = nil
) -> [SidebarContextMenuChoice] {
    guard profiles.count > 1 else { return [] }

    return profiles.map { profile in
        SidebarContextMenuChoice(
            id: profile.id,
            title: profile.name,
            icon: .emoji(SumiProfileIcon.storedValue(profile.icon)),
            isSelected: profile.id == selectedProfileId
        )
    }
}

private func sidebarContextMenuPersistentGlyphIcon(
    _ value: String,
    fallbackSystemImage: String
) -> SidebarContextMenuIcon {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if SumiPersistentGlyph.isValidSystemSymbolName(trimmed) {
        return .systemImage(trimmed)
    }
    if SumiPersistentGlyph.presentsAsEmoji(trimmed) {
        return .emoji(trimmed)
    }
    return .systemImage(fallbackSystemImage)
}

private func sidebarDestinationSubmenu(
    title: String,
    systemImage: String?,
    choiceSystemImage: String? = nil,
    action: SidebarChoiceMenuAction?,
    classification: SidebarContextMenuActionClassification = .structuralMutation
) -> SidebarContextMenuEntry? {
    guard let action else {
        return nil
    }

    let selectableChoices = action.choices.filter { $0.isSelected == false }
    guard selectableChoices.isEmpty == false else { return nil }

    return .submenu(
        title: title,
        systemImage: systemImage,
        children: selectableChoices.map { choice in
            let fallbackIcon = choiceSystemImage.map { SidebarContextMenuIcon.systemImage($0) }
            return .action(
                .init(
                    title: choice.title,
                    systemImage: nil,
                    classification: classification,
                    onAction: { action.onSelect(choice.id) }
                )
            )
            .withIcon(choice.icon ?? fallbackIcon)
        }
    )
}

private func sidebarSpaceDestinationEntry(action: SidebarSpaceDestinationAction?) -> SidebarContextMenuEntry? {
    guard let action else { return nil }

    let selectableChoices = action.choices.filter { $0.isSelected == false }
    guard selectableChoices.isEmpty == false else { return nil }

    return .submenu(
        title: "Move to Space",
        systemImage: "arrow.right",
        children: selectableChoices.map { choice in
            .action(
                .init(
                    title: choice.title,
                    classification: .structuralMutation,
                    onAction: { action.onSelect(choice.id) }
                )
            )
            .withIcon(choice.icon)
        }
    )
}

private func sidebarStateSubmenu(
    title: String,
    systemImage: String?,
    action: SidebarChoiceMenuAction?,
    classification: SidebarContextMenuActionClassification = .stateMutationNonStructural
) -> SidebarContextMenuEntry? {
    guard let action,
          SidebarChoiceSubmenuAvailability.multipleChoicesWithSelectableTarget.permits(action.choices) else {
        return nil
    }

    return .submenu(
        title: title,
        systemImage: systemImage,
        children: action.choices.map { choice in
            .action(
                .init(
                    title: choice.title,
                    isEnabled: choice.isSelected == false,
                    state: choice.isSelected ? .on : .off,
                    classification: classification,
                    onAction: { action.onSelect(choice.id) }
                )
            )
            .withIcon(choice.icon)
        }
    )
}

func makeSidebarTabContextMenuEntries(
    role: SidebarTabContextMenuRole,
    actions: SidebarTabContextMenuActions
) -> [SidebarContextMenuEntry] {
    if role.isSavedTab {
        return makeSavedSidebarTabEntries(
            role: role,
            actions: actions
        )
    }

    return makeRegularSidebarTabEntries(
        actions: actions
    )
}

private func makeRegularSidebarTabEntries(
    actions: SidebarTabContextMenuActions
) -> [SidebarContextMenuEntry] {
    let duplicateSection: [SidebarContextMenuEntry] = actions.duplicate.map {
        [.action(.init(title: "Duplicate Tab", systemImage: "plus.square.on.square", classification: .structuralMutation, onAction: $0))]
    } ?? []

    let editSection: [SidebarContextMenuEntry] = [
        actions.copyLink.map {
            .action(.init(title: "Copy Link", systemImage: "link", classification: .presentationOnly, onAction: $0))
        },
        actions.share.map {
            .action(.init(title: "Share…", systemImage: "square.and.arrow.up", classification: .presentationOnly, onAction: $0))
        },
        actions.rename.map {
            .action(.init(title: "Rename Tab", systemImage: "character.cursor.ibeam", onAction: $0))
        },
    ].compactMap { $0 }

    var organizationSection: [SidebarContextMenuEntry] = []
    if let folderSubmenu = sidebarDestinationSubmenu(
        title: "Add to Folder",
        systemImage: "folder.badge.plus",
        choiceSystemImage: "folder.fill",
        action: actions.folderTarget
    ) {
        organizationSection.append(folderSubmenu)
    }
    if let spaceSubmenu = sidebarSpaceDestinationEntry(action: actions.moveToSpace) {
        organizationSection.append(spaceSubmenu)
    }
    if let profileSubmenu = sidebarStateSubmenu(
        title: "Use Profile",
        systemImage: "person.2",
        action: actions.profileTarget
    ) {
        organizationSection.append(profileSubmenu)
    }
    if let onMoveUp = actions.moveUp {
        organizationSection.append(
            .action(.init(title: "Move Up", systemImage: "arrow.up", classification: .structuralMutation, onAction: onMoveUp))
        )
    }
    if let onMoveDown = actions.moveDown {
        organizationSection.append(
            .action(.init(title: "Move Down", systemImage: "arrow.down", classification: .structuralMutation, onAction: onMoveDown))
        )
    }

    var saveSection: [SidebarContextMenuEntry] = []
    if let onPinToSpace = actions.pinToSpace {
        saveSection.append(.action(.init(title: "Pin to This Space", systemImage: "pin", classification: .structuralMutation, onAction: onPinToSpace)))
    }
    if let onAddToEssentials = actions.addToEssentials {
        saveSection.append(.action(.init(title: "Add to Essentials", systemImage: "star.fill", classification: .structuralMutation, onAction: onAddToEssentials)))
    }

    var closeSection: [SidebarContextMenuEntry] = []
    if let onCloseTabsBelow = actions.closeTabsBelow {
        closeSection.append(.action(.init(title: "Close Tabs Below", systemImage: "arrow.down.to.line", classification: .structuralMutation, onAction: onCloseTabsBelow)))
    }
    if let onClose = actions.close {
        closeSection.append(
            .action(
                .init(
                    title: "Close Tab",
                    systemImage: "xmark",
                    role: .destructive,
                    classification: .structuralMutation,
                    onAction: onClose
                )
            )
        )
    }

    return joinSidebarMenuSections(
        [
            duplicateSection,
            editSection,
            organizationSection,
            saveSection,
            closeSection,
        ]
    )
}

private func makeSavedSidebarTabEntries(
    role: SidebarTabContextMenuRole,
    actions: SidebarTabContextMenuActions
) -> [SidebarContextMenuEntry] {
    let label = role.displayName
    var openSection: [SidebarContextMenuEntry] = []
    if let onDuplicate = actions.duplicate {
        openSection.append(.action(.init(title: "Duplicate as Tab", systemImage: "doc.on.doc", classification: .structuralMutation, onAction: onDuplicate)))
    }

    let shareSection: [SidebarContextMenuEntry] = [
        actions.copyLink.map {
            .action(.init(title: "Copy Link", systemImage: "link", classification: .presentationOnly, onAction: $0))
        },
        actions.share.map {
            .action(.init(title: "Share…", systemImage: "square.and.arrow.up", classification: .presentationOnly, onAction: $0))
        },
    ].compactMap { $0 }

    let editAction = actions.edit ?? actions.rename ?? actions.editURL
    let editSection: [SidebarContextMenuEntry] = editAction.map {
        [.action(.init(title: "Edit", systemImage: "pencil", classification: .presentationOnly, onAction: $0))]
    } ?? []

    let driftSection: [SidebarContextMenuEntry] = actions.savedURLDrift.map {
        [
            .action(.init(title: "Back to \(label) URL", systemImage: "arrow.counterclockwise", onAction: $0.onBackToSavedURL)),
            .action(.init(title: "Use Current Page as \(label) URL", systemImage: "arrow.triangle.2.circlepath", onAction: $0.onUseCurrentPageAsSavedURL)),
        ]
    } ?? []

    var runtimeSection: [SidebarContextMenuEntry] = []
    if let onUnload = actions.unload {
        runtimeSection.append(.action(.init(title: "Unload \(label)", systemImage: "xmark.circle", onAction: onUnload)))
    }

    var organizationSection: [SidebarContextMenuEntry] = []
    if let onAddToEssentials = actions.addToEssentials {
        organizationSection.append(.action(.init(title: "Add to Essentials", systemImage: "star.fill", classification: .structuralMutation, onAction: onAddToEssentials)))
    }
    if let folderSubmenu = sidebarDestinationSubmenu(
        title: role == .folderPinnedTab ? "Move to Folder" : "Add to Folder",
        systemImage: role == .folderPinnedTab ? "folder" : "folder.badge.plus",
        choiceSystemImage: "folder.fill",
        action: actions.folderTarget
    ) {
        organizationSection.append(folderSubmenu)
    }
    if let spaceSubmenu = sidebarSpaceDestinationEntry(action: actions.moveToSpace) {
        organizationSection.append(spaceSubmenu)
    }
    if let profileSubmenu = sidebarStateSubmenu(
        title: "Use Profile",
        systemImage: "person.2",
        action: actions.profileTarget
    ) {
        organizationSection.append(profileSubmenu)
    }

    let deleteSection: [SidebarContextMenuEntry] = actions.deleteSavedTab.map {
        [
            .action(
                .init(
                    title: "Delete \(label)",
                    systemImage: "trash",
                    role: .destructive,
                    classification: .structuralMutation,
                    onAction: $0
                )
            ),
        ]
    } ?? []

    return joinSidebarMenuSections(
        [
            openSection,
            shareSection,
            editSection,
            driftSection,
            organizationSection,
            runtimeSection,
            deleteSection,
        ]
    )
}

func makeFolderHeaderContextMenuEntries(actions: SidebarFolderHeaderMenuActions) -> [SidebarContextMenuEntry] {
    let iconSection: [SidebarContextMenuEntry] = [
        .action(.init(title: "Edit", systemImage: "pencil", classification: .presentationOnly, onAction: actions.edit)),
    ]

    let contentsSection: [SidebarContextMenuEntry] = [
        .action(.init(title: "Sort by Name", classification: .structuralMutation, onAction: actions.alphabetize)),
    ] + (actions.unloadActiveTabs.map {
        [.action(.init(title: "Unload Active Tabs in Folder", systemImage: "xmark.circle", onAction: $0))]
    } ?? [])

    return joinSidebarMenuSections(
        [
            iconSection,
            contentsSection,
            [
                .action(
                    .init(
                        title: "Ungroup Folder",
                        systemImage: "folder.badge.minus",
                        classification: .structuralMutation,
                        onAction: actions.ungroup
                    )
                ),
                .action(
                    .init(
                        title: "Delete Folder",
                        role: .destructive,
                        classification: .structuralMutation,
                        onAction: actions.delete
                    )
                ),
            ],
        ]
    )
}

func makeSpaceContextMenuEntries(actions: SidebarSpaceMenuActions) -> [SidebarContextMenuEntry] {
    joinSidebarMenuSections(
        [
            [
                .action(.init(title: "Edit", systemImage: "pencil", classification: .presentationOnly, onAction: actions.edit)),
                .action(.init(title: "Change Theme", systemImage: "paintpalette", classification: .presentationOnly, onAction: actions.changeTheme)),
            ],
            actions.deleteSpace.map {
                [
                    .action(.init(title: "Delete Space", systemImage: "trash", role: .destructive, classification: .structuralMutation, onAction: $0)),
                ]
            } ?? [],
        ]
    )
}

func makeSidebarShellContextMenuEntries(
    isCompactModeEnabled: Bool,
    actions: SidebarShellMenuActions
) -> [SidebarContextMenuEntry] {
    let liveFolderChildren: [SidebarContextMenuEntry] = [
        actions.newRSSLiveFolder.map {
            .action(.init(title: "RSS Feed", systemImage: "dot.radiowaves.left.and.right", classification: .structuralMutation, onAction: $0))
        },
        actions.newGitHubPullRequestsLiveFolder.map {
            .action(.init(title: "GitHub Pull Requests", systemImage: "chevron.left.forwardslash.chevron.right", classification: .structuralMutation, onAction: $0))
        },
        actions.newGitHubIssuesLiveFolder.map {
            .action(.init(title: "GitHub Issues", systemImage: "exclamationmark.circle", classification: .structuralMutation, onAction: $0))
        },
    ].compactMap { $0 }

    let createSection: [SidebarContextMenuEntry] = [
        .action(.init(title: "New Tab", systemImage: "plus", classification: .presentationOnly, onAction: actions.newTab)),
        actions.newFolder.map {
            .action(.init(title: "New Folder", systemImage: "folder.badge.plus", classification: .structuralMutation, onAction: $0))
        },
        liveFolderChildren.isEmpty
            ? nil
            : .submenu(title: "New Live Folder", systemImage: "sparkles", children: liveFolderChildren),
    ].compactMap { $0 }

    let appearanceSection: [SidebarContextMenuEntry] = [
        actions.changeTheme.map {
            .action(.init(title: "Change Theme", systemImage: "paintpalette", classification: .presentationOnly, onAction: $0))
        },
        .action(
            .init(
                title: "Toggle Compact Mode",
                systemImage: "circle.grid.2x2",
                state: isCompactModeEnabled ? .on : .off,
                onAction: actions.toggleCompactMode
            )
        ),
        .action(.init(title: "Sidebar Settings…", systemImage: "slider.horizontal.3", classification: .presentationOnly, onAction: actions.openSettings)),
    ].compactMap { $0 }

    return joinSidebarMenuSections([createSection, appearanceSection])
}

extension SidebarContextMenuAction {
    init(
        title: String,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        state: NSControl.StateValue = .off,
        role: SidebarContextMenuRole = .normal,
        classification: SidebarContextMenuActionClassification = .stateMutationNonStructural,
        onAction: @escaping () -> Void
    ) {
        self.init(
            title: title,
            systemImage: systemImage,
            isEnabled: isEnabled,
            state: state,
            role: role,
            classification: classification,
            action: onAction
        )
    }
}
