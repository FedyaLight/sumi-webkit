//
//  SidebarMenuFactories.swift
//  Sumi
//

import AppKit

struct SidebarFolderHeaderMenuCallbacks {
    let onRename: () -> Void
    let onChangeIcon: () -> Void
    let onResetIcon: () -> Void
    let onAddTab: () -> Void
    let onAlphabetize: () -> Void
    let onUnloadActiveTabs: (() -> Void)?
    let onDelete: () -> Void
}

struct SidebarSpaceMenuCallbacks {
    let onSelectProfile: (UUID) -> Void
    let onRename: (() -> Void)?
    let onChangeIcon: (() -> Void)?
    let onChangeTheme: () -> Void
    let onOpenSettings: () -> Void
    let onDeleteSpace: (() -> Void)?
}

struct SidebarSpaceListMenuCallbacks {
    let onOpenSettings: () -> Void
    let onDeleteSpace: (() -> Void)?
}

struct SidebarShellMenuCallbacks {
    let onNewTab: () -> Void
    let onNewSplit: () -> Void
    let onToggleCompactMode: () -> Void
    let onOpenSettings: () -> Void
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

struct SidebarTabContextMenuCapabilities {
    var folders: [SidebarContextMenuChoice] = []
    var spaces: [SidebarContextMenuChoice] = []
    var profiles: [SidebarContextMenuChoice] = []
    var showsAddToEssentials = false
    var canMoveUp = false
    var canMoveDown = false
    var showsCloseTabsBelow = false
    var hasSavedURLDrift = false
    var hasLiveInstance = false
}

struct SidebarTabContextMenuCallbacks {
    var onDuplicate: (() -> Void)?
    var onCopyLink: (() -> Void)?
    var onShare: (() -> Void)?
    var onRename: (() -> Void)?
    var onMoveToFolder: ((UUID) -> Void)?
    var onMoveToSpace: ((UUID) -> Void)?
    var onConvertSpaceToProfile: ((UUID) -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onPinToSpace: (() -> Void)?
    var onAddToEssentials: (() -> Void)?
    var onBackToSavedURL: (() -> Void)?
    var onUseCurrentPageAsSavedURL: (() -> Void)?
    var onChangeIcon: (() -> Void)?
    var onEditURL: (() -> Void)?
    var onUnload: (() -> Void)?
    var onCloseTabsBelow: (() -> Void)?
    var onClose: (() -> Void)?
    var onDeleteSavedTab: (() -> Void)?
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

private func joinSidebarMenuSections(_ sections: [[SidebarContextMenuEntry]]) -> [SidebarContextMenuEntry] {
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
    folders.map { folder in
        SidebarContextMenuChoice(
            id: folder.id,
            title: folder.name,
            isSelected: folder.id == selectedFolderId
        )
    }
}

@MainActor
func makeSidebarContextMenuSpaceChoices(
    spaces: [Space],
    profiles: [Profile],
    selectedSpaceId: UUID? = nil
) -> [SidebarContextMenuChoice] {
    guard spaces.count > 1 else { return [] }

    let fallbackProfileName = profiles.first?.name ?? "Default"
    return spaces.map { space in
        let profileName = space.profileId.flatMap { profileId in
            profiles.first(where: { $0.id == profileId })?.name
        } ?? fallbackProfileName

        return SidebarContextMenuChoice(
            id: space.id,
            title: "\(profileName): \(space.name)",
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
            isSelected: profile.id == selectedProfileId
        )
    }
}

private func sidebarChoiceSubmenu(
    title: String,
    systemImage: String?,
    choiceSystemImage: String? = nil,
    choices: [SidebarContextMenuChoice],
    classification: SidebarContextMenuActionClassification = .structuralMutation,
    availability: SidebarChoiceSubmenuAvailability = .anySelectableChoice,
    onSelect: ((UUID) -> Void)?
) -> SidebarContextMenuEntry? {
    guard availability.permits(choices),
          let onSelect else {
        return nil
    }

    return .submenu(
        title: title,
        systemImage: systemImage,
        children: choices.map { choice in
            .action(
                .init(
                    title: choice.title,
                    systemImage: choiceSystemImage,
                    isEnabled: choice.isSelected == false,
                    state: choice.isSelected ? .on : .off,
                    classification: classification,
                    onAction: { onSelect(choice.id) }
                )
            )
        }
    )
}

func makeSidebarTabContextMenuEntries(
    role: SidebarTabContextMenuRole,
    capabilities: SidebarTabContextMenuCapabilities,
    callbacks: SidebarTabContextMenuCallbacks
) -> [SidebarContextMenuEntry] {
    if role.isSavedTab {
        return makeSavedSidebarTabEntries(
            role: role,
            capabilities: capabilities,
            callbacks: callbacks
        )
    }

    return makeRegularSidebarTabEntries(
        capabilities: capabilities,
        callbacks: callbacks
    )
}

private func makeRegularSidebarTabEntries(
    capabilities: SidebarTabContextMenuCapabilities,
    callbacks: SidebarTabContextMenuCallbacks
) -> [SidebarContextMenuEntry] {
    let duplicateSection: [SidebarContextMenuEntry] = callbacks.onDuplicate.map {
        [.action(.init(title: "Duplicate Tab", systemImage: "plus.square.on.square", classification: .structuralMutation, onAction: $0))]
    } ?? []

    let editSection: [SidebarContextMenuEntry] = [
        callbacks.onCopyLink.map {
            .action(.init(title: "Copy Link", systemImage: "link", classification: .presentationOnly, onAction: $0))
        },
        callbacks.onShare.map {
            .action(.init(title: "Share…", systemImage: "square.and.arrow.up", classification: .presentationOnly, onAction: $0))
        },
        callbacks.onRename.map {
            .action(.init(title: "Rename Tab", systemImage: "character.cursor.ibeam", onAction: $0))
        },
    ].compactMap { $0 }

    var organizationSection: [SidebarContextMenuEntry] = []
    if let folderSubmenu = sidebarChoiceSubmenu(
        title: "Add to Folder",
        systemImage: "folder.badge.plus",
        choiceSystemImage: "folder.fill",
        choices: capabilities.folders,
        onSelect: callbacks.onMoveToFolder
    ) {
        organizationSection.append(folderSubmenu)
    }
    if let spaceSubmenu = sidebarChoiceSubmenu(
        title: "Move to…",
        systemImage: "arrow.right",
        choices: capabilities.spaces,
        availability: .multipleChoicesWithSelectableTarget,
        onSelect: callbacks.onMoveToSpace
    ) {
        organizationSection.append(spaceSubmenu)
    }
    if let profileSubmenu = sidebarChoiceSubmenu(
        title: "Convert Space to Profile",
        systemImage: "person.crop.circle",
        choices: capabilities.profiles,
        availability: .multipleChoicesWithSelectableTarget,
        onSelect: callbacks.onConvertSpaceToProfile
    ) {
        organizationSection.append(profileSubmenu)
    }
    if capabilities.canMoveUp, let onMoveUp = callbacks.onMoveUp {
        organizationSection.append(
            .action(.init(title: "Move Up", systemImage: "arrow.up", classification: .structuralMutation, onAction: onMoveUp))
        )
    }
    if capabilities.canMoveDown, let onMoveDown = callbacks.onMoveDown {
        organizationSection.append(
            .action(.init(title: "Move Down", systemImage: "arrow.down", classification: .structuralMutation, onAction: onMoveDown))
        )
    }

    var saveSection: [SidebarContextMenuEntry] = []
    if let onPinToSpace = callbacks.onPinToSpace {
        saveSection.append(.action(.init(title: "Pin to This Space", systemImage: "pin", classification: .structuralMutation, onAction: onPinToSpace)))
    }
    if capabilities.showsAddToEssentials, let onAddToEssentials = callbacks.onAddToEssentials {
        saveSection.append(.action(.init(title: "Add to Essentials", systemImage: "star.fill", classification: .structuralMutation, onAction: onAddToEssentials)))
    }

    var closeSection: [SidebarContextMenuEntry] = []
    if capabilities.showsCloseTabsBelow, let onCloseTabsBelow = callbacks.onCloseTabsBelow {
        closeSection.append(.action(.init(title: "Close Tabs Below", systemImage: "arrow.down.to.line", classification: .structuralMutation, onAction: onCloseTabsBelow)))
    }
    if let onClose = callbacks.onClose {
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
    capabilities: SidebarTabContextMenuCapabilities,
    callbacks: SidebarTabContextMenuCallbacks
) -> [SidebarContextMenuEntry] {
    let label = role.displayName
    var openSection: [SidebarContextMenuEntry] = []
    if let onDuplicate = callbacks.onDuplicate {
        openSection.append(.action(.init(title: "Duplicate as Tab", systemImage: "doc.on.doc", classification: .structuralMutation, onAction: onDuplicate)))
    }

    let shareSection: [SidebarContextMenuEntry] = [
        callbacks.onCopyLink.map {
            .action(.init(title: "Copy Link", systemImage: "link", classification: .presentationOnly, onAction: $0))
        },
        callbacks.onShare.map {
            .action(.init(title: "Share…", systemImage: "square.and.arrow.up", classification: .presentationOnly, onAction: $0))
        },
    ].compactMap { $0 }

    let editSection: [SidebarContextMenuEntry] = [
        callbacks.onRename.map {
            .action(.init(title: "Rename \(label)", systemImage: "character.cursor.ibeam", onAction: $0))
        },
        callbacks.onChangeIcon.map {
            .action(.init(title: "Change Icon…", systemImage: "photo", classification: .presentationOnly, onAction: $0))
        },
        callbacks.onEditURL.map {
            .action(.init(title: "Edit URL…", systemImage: "link.badge.plus", classification: .presentationOnly, onAction: $0))
        },
    ].compactMap { $0 }

    var driftSection: [SidebarContextMenuEntry] = []
    if capabilities.hasSavedURLDrift,
       let onBackToSavedURL = callbacks.onBackToSavedURL,
       let onUseCurrentPageAsSavedURL = callbacks.onUseCurrentPageAsSavedURL {
        driftSection = [
            .action(.init(title: "Back to \(label) URL", systemImage: "arrow.counterclockwise", onAction: onBackToSavedURL)),
            .action(.init(title: "Use Current Page as \(label) URL", systemImage: "arrow.triangle.2.circlepath", onAction: onUseCurrentPageAsSavedURL)),
        ]
    }

    var runtimeSection: [SidebarContextMenuEntry] = []
    if capabilities.hasLiveInstance, let onUnload = callbacks.onUnload {
        runtimeSection.append(.action(.init(title: "Unload \(label)", systemImage: "xmark.circle", onAction: onUnload)))
    }

    var organizationSection: [SidebarContextMenuEntry] = []
    if capabilities.showsAddToEssentials, let onAddToEssentials = callbacks.onAddToEssentials {
        organizationSection.append(.action(.init(title: "Add to Essentials", systemImage: "star.fill", classification: .structuralMutation, onAction: onAddToEssentials)))
    }
    if let folderSubmenu = sidebarChoiceSubmenu(
        title: role == .folderPinnedTab ? "Move to Folder" : "Add to Folder",
        systemImage: role == .folderPinnedTab ? "folder" : "folder.badge.plus",
        choiceSystemImage: "folder.fill",
        choices: capabilities.folders,
        onSelect: callbacks.onMoveToFolder
    ) {
        organizationSection.append(folderSubmenu)
    }
    if let spaceSubmenu = sidebarChoiceSubmenu(
        title: "Move to…",
        systemImage: "arrow.right",
        choices: capabilities.spaces,
        availability: .multipleChoicesWithSelectableTarget,
        onSelect: callbacks.onMoveToSpace
    ) {
        organizationSection.append(spaceSubmenu)
    }
    if let profileSubmenu = sidebarChoiceSubmenu(
        title: "Convert Space to Profile",
        systemImage: "person.crop.circle",
        choices: capabilities.profiles,
        availability: .multipleChoicesWithSelectableTarget,
        onSelect: callbacks.onConvertSpaceToProfile
    ) {
        organizationSection.append(profileSubmenu)
    }

    let deleteSection: [SidebarContextMenuEntry] = callbacks.onDeleteSavedTab.map {
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

func makeFolderHeaderContextMenuEntries(
    hasCustomIcon: Bool,
    showsUnloadActiveTabs: Bool = false,
    callbacks: SidebarFolderHeaderMenuCallbacks
) -> [SidebarContextMenuEntry] {
    let iconSection: [SidebarContextMenuEntry] = [
        .action(.init(title: "Rename Folder", onAction: callbacks.onRename)),
        .action(.init(title: "Change Folder Icon…", classification: .presentationOnly, onAction: callbacks.onChangeIcon)),
    ] + (hasCustomIcon
        ? [.action(.init(title: "Reset Folder Icon", onAction: callbacks.onResetIcon))]
        : [])

    let contentsSection: [SidebarContextMenuEntry] = [
        .action(.init(title: "New Tab in Folder", classification: .structuralMutation, onAction: callbacks.onAddTab)),
        .action(.init(title: "Sort by Name", classification: .structuralMutation, onAction: callbacks.onAlphabetize)),
    ] + (showsUnloadActiveTabs && callbacks.onUnloadActiveTabs != nil
        ? [.action(.init(title: "Unload Active Tabs in Folder", systemImage: "xmark.circle", onAction: callbacks.onUnloadActiveTabs ?? {}))]
        : [])

    return joinSidebarMenuSections(
        [
            iconSection,
            contentsSection,
            [
                .action(
                    .init(
                        title: "Delete Folder",
                        role: .destructive,
                        classification: .structuralMutation,
                        onAction: callbacks.onDelete
                    )
                ),
            ],
        ]
    )
}

func makeSpaceContextMenuEntries(
    profiles: [SidebarContextMenuChoice],
    canRename: Bool,
    canChangeIcon: Bool,
    canDelete: Bool,
    callbacks: SidebarSpaceMenuCallbacks
) -> [SidebarContextMenuEntry] {
    let profileEntries = profiles.map { profile in
        SidebarContextMenuEntry.action(
            .init(
                title: profile.title,
                state: profile.isSelected ? .on : .off,
                onAction: { callbacks.onSelectProfile(profile.id) }
            )
        )
    }

    var editSection: [SidebarContextMenuEntry] = []
    if canRename, let onRename = callbacks.onRename {
        editSection.append(.action(.init(title: "Rename", systemImage: "textformat", onAction: onRename)))
    }
    if canChangeIcon, let onChangeIcon = callbacks.onChangeIcon {
        editSection.append(.action(.init(title: "Change Icon", systemImage: "face.smiling", classification: .presentationOnly, onAction: onChangeIcon)))
    }
    editSection.append(.action(.init(title: "Change Theme", systemImage: "paintpalette", classification: .presentationOnly, onAction: callbacks.onChangeTheme)))

    var settingsSection: [SidebarContextMenuEntry] = [
        .action(.init(title: "Space Settings", systemImage: "gear", classification: .presentationOnly, onAction: callbacks.onOpenSettings)),
    ]
    if canDelete, let onDeleteSpace = callbacks.onDeleteSpace {
        settingsSection.append(
            .action(.init(title: "Delete Space", systemImage: "trash", role: .destructive, classification: .structuralMutation, onAction: onDeleteSpace))
        )
    }

    return joinSidebarMenuSections(
        [
            [
                .submenu(title: "Profile", systemImage: "person.crop.circle", children: profileEntries),
            ],
            editSection,
            settingsSection,
        ]
    )
}

func makeSpaceListContextMenuEntries(
    canDelete: Bool,
    callbacks: SidebarSpaceListMenuCallbacks
) -> [SidebarContextMenuEntry] {
    joinSidebarMenuSections(
        [
        [
            .action(.init(title: "Space Settings", systemImage: "gear", classification: .presentationOnly, onAction: callbacks.onOpenSettings)),
        ],
        canDelete && callbacks.onDeleteSpace != nil
            ? [
                .action(
                    .init(
                        title: "Delete Space",
                        systemImage: "trash",
                        role: .destructive,
                        classification: .structuralMutation,
                        onAction: callbacks.onDeleteSpace ?? {}
                    )
                ),
            ]
                : [],
        ]
    )
}

func makeSidebarShellContextMenuEntries(
    isCompactModeEnabled: Bool,
    callbacks: SidebarShellMenuCallbacks
) -> [SidebarContextMenuEntry] {
    joinSidebarMenuSections(
        [
            [
                .action(.init(title: "New Tab", systemImage: "plus", classification: .structuralMutation, onAction: callbacks.onNewTab)),
                .action(.init(title: "New Split", systemImage: "rectangle.split.2x1", onAction: callbacks.onNewSplit)),
            ],
            [
                .action(
                    .init(
                        title: "Toggle Compact Mode",
                        systemImage: "circle.grid.2x2",
                        state: isCompactModeEnabled ? .on : .off,
                        onAction: callbacks.onToggleCompactMode
                    )
                ),
                .action(.init(title: "Sidebar Settings…", systemImage: "slider.horizontal.3", classification: .presentationOnly, onAction: callbacks.onOpenSettings)),
            ],
        ]
    )
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
