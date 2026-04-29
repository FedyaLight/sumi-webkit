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
    let onDelete: () -> Void
}

struct SidebarRegularTabMenuCallbacks {
    let onAddToFolder: (UUID) -> Void
    let onAddToFavorites: () -> Void
    let onCopyLink: () -> Void
    let onShare: () -> Void
    let onRename: () -> Void
    let onSplitRight: () -> Void
    let onSplitLeft: () -> Void
    let onDuplicate: () -> Void
    let onMoveToSpace: (UUID) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onPinToSpace: () -> Void
    let onPinGlobally: () -> Void
    let onCloseAllBelow: () -> Void
    let onClose: () -> Void
}

struct SidebarLauncherMenuCallbacks {
    let onOpen: () -> Void
    let onSplitRight: () -> Void
    let onSplitLeft: () -> Void
    let onDuplicate: () -> Void
    let onResetToLaunchURL: (() -> Void)?
    let onReplaceLauncherURLWithCurrent: (() -> Void)?
    let onEditIcon: () -> Void
    let onEditLink: () -> Void
    let onUnpin: () -> Void
    let onMoveToRegularTabs: () -> Void
    let onPinGlobally: (() -> Void)?
    let onCloseCurrentPage: (() -> Void)?
}

struct SidebarEssentialsMenuCallbacks {
    let onOpen: () -> Void
    let onSplitRight: () -> Void
    let onSplitLeft: () -> Void
    let onCloseCurrentPage: (() -> Void)?
    let onRemoveFromEssentials: () -> Void
    let onMoveToRegularTabs: () -> Void
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
    let onCreateSpace: () -> Void
    let onCreateFolder: () -> Void
    let onNewSplit: () -> Void
    let onNewTab: () -> Void
    let onReloadSelectedTab: () -> Void
    let onBookmarkSelectedTab: () -> Void
    let onReopenClosedTab: () -> Void
    let onToggleCompactMode: () -> Void
    let onEditTheme: () -> Void
    let onOpenLayout: () -> Void
}

private func joinSidebarMenuSections(_ sections: [[SidebarContextMenuEntry]]) -> [SidebarContextMenuEntry] {
    sections
        .filter { !$0.isEmpty }
        .enumerated()
        .flatMap { index, section in
            index == 0 ? section : [.separator] + section
        }
}

func makeFolderHeaderContextMenuEntries(
    hasCustomIcon: Bool,
    callbacks: SidebarFolderHeaderMenuCallbacks
) -> [SidebarContextMenuEntry] {
    joinSidebarMenuSections(
        [
            [
                .action(.init(title: "Rename Folder", onAction: callbacks.onRename)),
                .action(.init(title: "Change Folder Icon…", classification: .presentationOnly, onAction: callbacks.onChangeIcon)),
            ] + (hasCustomIcon
                ? [.action(.init(title: "Reset Folder Icon", onAction: callbacks.onResetIcon))]
                : []) + [
                    .action(.init(title: "Add Tab to Folder", classification: .structuralMutation, onAction: callbacks.onAddTab)),
                ],
            [
                .action(.init(title: "Alphabetize Tabs", classification: .structuralMutation, onAction: callbacks.onAlphabetize)),
            ],
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

func makeRegularTabContextMenuEntries(
    folders: [SidebarContextMenuChoice],
    spaces: [SidebarContextMenuChoice],
    showsAddToFavorites: Bool,
    canMoveUp: Bool,
    canMoveDown: Bool,
    showsCloseAllBelow: Bool,
    callbacks: SidebarRegularTabMenuCallbacks
) -> [SidebarContextMenuEntry] {
    let addSection: [SidebarContextMenuEntry] =
        (folders.isEmpty
            ? []
            : [
                .submenu(
                    title: "Add to Folder",
                    systemImage: "folder.badge.plus",
                    children: folders.map { folder in
                .action(
                            .init(
                                title: folder.title,
                                systemImage: "folder.fill",
                                classification: .structuralMutation,
                                onAction: { callbacks.onAddToFolder(folder.id) }
                            )
                        )
                    }
                ),
            ]) +
        (showsAddToFavorites
            ? [.action(.init(title: "Add to Favorites", systemImage: "star.fill", classification: .structuralMutation, onAction: callbacks.onAddToFavorites))]
            : [])

    let editSection: [SidebarContextMenuEntry] = [
        .action(.init(title: "Copy Link", systemImage: "link", classification: .presentationOnly, onAction: callbacks.onCopyLink)),
        .action(.init(title: "Share", systemImage: "square.and.arrow.up", classification: .presentationOnly, onAction: callbacks.onShare)),
        .action(.init(title: "Rename", systemImage: "character.cursor.ibeam", onAction: callbacks.onRename)),
    ]

    let moveToSpaceEntries = spaces.map { space in
        SidebarContextMenuEntry.action(
            .init(
                title: space.title,
                isEnabled: space.isSelected == false,
                classification: .structuralMutation,
                onAction: { callbacks.onMoveToSpace(space.id) }
            )
        )
    }

    let actionSection: [SidebarContextMenuEntry] = [
        .submenu(
            title: "Open in Split",
            systemImage: "rectangle.split.2x1",
            children: [
                .action(.init(title: "Right", systemImage: "rectangle.righthalf.filled", onAction: callbacks.onSplitRight)),
                .action(.init(title: "Left", systemImage: "rectangle.lefthalf.filled", onAction: callbacks.onSplitLeft)),
            ]
        ),
        .action(.init(title: "Duplicate", systemImage: "plus.square.on.square", classification: .structuralMutation, onAction: callbacks.onDuplicate)),
        .submenu(title: "Move to Space", systemImage: "square.grid.2x2", children: moveToSpaceEntries),
        .action(.init(title: "Move Up", systemImage: "arrow.up", isEnabled: canMoveUp, classification: .structuralMutation, onAction: callbacks.onMoveUp)),
        .action(.init(title: "Move Down", systemImage: "arrow.down", isEnabled: canMoveDown, classification: .structuralMutation, onAction: callbacks.onMoveDown)),
        .action(.init(title: "Pin to Space", systemImage: "pin", classification: .structuralMutation, onAction: callbacks.onPinToSpace)),
        .action(.init(title: "Pin Globally", systemImage: "pin.circle", classification: .structuralMutation, onAction: callbacks.onPinGlobally)),
    ]

    let closeSection: [SidebarContextMenuEntry] =
        (showsCloseAllBelow
            ? [.action(.init(title: "Close All Below", systemImage: "arrow.down.to.line", classification: .structuralMutation, onAction: callbacks.onCloseAllBelow))]
            : []) + [
                .action(
                    .init(
                        title: "Close",
                        systemImage: "xmark",
                        role: .destructive,
                        classification: .structuralMutation,
                        onAction: callbacks.onClose
                    )
                ),
            ]

    return joinSidebarMenuSections([addSection, editSection, actionSection, closeSection])
}

func makeSpacePinnedLauncherContextMenuEntries(
    hasRuntimeResetActions: Bool,
    showsCloseCurrentPage: Bool,
    callbacks: SidebarLauncherMenuCallbacks
) -> [SidebarContextMenuEntry] {
    var sections: [[SidebarContextMenuEntry]] = [
        [
            .action(.init(title: "Open", systemImage: "arrow.up.forward.app", onAction: callbacks.onOpen)),
            .action(.init(title: "Open in Split (Right)", systemImage: "rectangle.split.2x1", onAction: callbacks.onSplitRight)),
            .action(.init(title: "Open in Split (Left)", systemImage: "rectangle.split.2x1", onAction: callbacks.onSplitLeft)),
        ],
    ]

    if hasRuntimeResetActions, let onResetToLaunchURL = callbacks.onResetToLaunchURL, let onReplace = callbacks.onReplaceLauncherURLWithCurrent {
        sections.append(
            [
                .action(.init(title: "Reset to Launcher URL", systemImage: "arrow.counterclockwise", onAction: onResetToLaunchURL)),
                .action(.init(title: "Replace Launcher URL with Current", systemImage: "arrow.triangle.2.circlepath", onAction: onReplace)),
            ]
        )
    }

    var managementSection: [SidebarContextMenuEntry] = [
        .action(.init(title: "Edit Icon", systemImage: "photo", classification: .presentationOnly, onAction: callbacks.onEditIcon)),
        .action(.init(title: "Edit Link…", systemImage: "link.badge.plus", classification: .presentationOnly, onAction: callbacks.onEditLink)),
        .action(.init(title: "Unpin from Space", systemImage: "pin.slash", classification: .structuralMutation, onAction: callbacks.onUnpin)),
        .action(.init(title: "Move to Regular Tabs", systemImage: "pin.slash.fill", classification: .structuralMutation, onAction: callbacks.onMoveToRegularTabs)),
    ]
    if let onPinGlobally = callbacks.onPinGlobally {
        managementSection.append(.action(.init(title: "Pin Globally", systemImage: "pin.circle", classification: .structuralMutation, onAction: onPinGlobally)))
    }
    sections.append(managementSection)

    if showsCloseCurrentPage, let onCloseCurrentPage = callbacks.onCloseCurrentPage {
        sections.append(
            [
                .action(.init(title: "Close current page", systemImage: "xmark.circle", onAction: onCloseCurrentPage)),
            ]
        )
    }

    return joinSidebarMenuSections(sections)
}

func makeFolderLauncherContextMenuEntries(
    hasRuntimeResetActions: Bool,
    showsCloseCurrentPage: Bool,
    callbacks: SidebarLauncherMenuCallbacks
) -> [SidebarContextMenuEntry] {
    var sections: [[SidebarContextMenuEntry]] = [
        [
            .action(.init(title: "Open", systemImage: "arrow.up.forward.app", onAction: callbacks.onOpen)),
            .action(.init(title: "Open in Split (Right)", systemImage: "rectangle.split.2x1", onAction: callbacks.onSplitRight)),
            .action(.init(title: "Open in Split (Left)", systemImage: "rectangle.split.2x1", onAction: callbacks.onSplitLeft)),
            .action(.init(title: "Duplicate Tab", systemImage: "doc.on.doc", classification: .structuralMutation, onAction: callbacks.onDuplicate)),
        ],
    ]

    if hasRuntimeResetActions, let onResetToLaunchURL = callbacks.onResetToLaunchURL, let onReplace = callbacks.onReplaceLauncherURLWithCurrent {
        sections.append(
            [
                .action(.init(title: "Reset to Launcher URL", systemImage: "arrow.counterclockwise", onAction: onResetToLaunchURL)),
                .action(.init(title: "Replace Launcher URL with Current", systemImage: "arrow.triangle.2.circlepath", onAction: onReplace)),
            ]
        )
    }

    sections.append(
        [
            .action(.init(title: "Edit Icon", systemImage: "photo", classification: .presentationOnly, onAction: callbacks.onEditIcon)),
            .action(.init(title: "Edit Link…", systemImage: "link.badge.plus", classification: .presentationOnly, onAction: callbacks.onEditLink)),
            .action(.init(title: "Unpin from Folder", systemImage: "pin.slash", classification: .structuralMutation, onAction: callbacks.onUnpin)),
            .action(.init(title: "Move to Regular Tabs", systemImage: "pin.slash.fill", classification: .structuralMutation, onAction: callbacks.onMoveToRegularTabs)),
        ]
    )

    if showsCloseCurrentPage, let onCloseCurrentPage = callbacks.onCloseCurrentPage {
        sections.append(
            [
                .action(.init(title: "Close current page", systemImage: "xmark.circle", onAction: onCloseCurrentPage)),
            ]
        )
    }

    return joinSidebarMenuSections(sections)
}

func makeEssentialsContextMenuEntries(
    showsCloseCurrentPage: Bool,
    callbacks: SidebarEssentialsMenuCallbacks
) -> [SidebarContextMenuEntry] {
    var sections: [[SidebarContextMenuEntry]] = [
        [
            .action(.init(title: "Open", systemImage: "arrow.up.forward.app", onAction: callbacks.onOpen)),
            .action(.init(title: "Open in Split (Right)", systemImage: "rectangle.split.2x1", onAction: callbacks.onSplitRight)),
            .action(.init(title: "Open in Split (Left)", systemImage: "rectangle.split.2x1", onAction: callbacks.onSplitLeft)),
        ],
    ]

    if showsCloseCurrentPage, let onCloseCurrentPage = callbacks.onCloseCurrentPage {
        sections.append(
            [
                .action(.init(title: "Close current page", systemImage: "xmark", role: .destructive, onAction: onCloseCurrentPage)),
            ]
        )
    }

    sections.append(
        [
            .action(.init(title: "Remove from Essentials", systemImage: "pin.slash", classification: .structuralMutation, onAction: callbacks.onRemoveFromEssentials)),
            .action(.init(title: "Move to Regular Tabs", systemImage: "pin.slash.fill", classification: .structuralMutation, onAction: callbacks.onMoveToRegularTabs)),
        ]
    )

    return joinSidebarMenuSections(sections)
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
    hasSelectedTab: Bool,
    isCompactModeEnabled: Bool,
    callbacks: SidebarShellMenuCallbacks
) -> [SidebarContextMenuEntry] {
    joinSidebarMenuSections(
        [
            [
                .action(.init(title: "Create Space", systemImage: "square.grid.2x2", classification: .structuralMutation, onAction: callbacks.onCreateSpace)),
                .action(.init(title: "Create Folder", systemImage: "folder.badge.plus", classification: .structuralMutation, onAction: callbacks.onCreateFolder)),
                .action(.init(title: "New Split", systemImage: "rectangle.split.2x1", onAction: callbacks.onNewSplit)),
                .action(.init(title: "New Tab", systemImage: "plus", classification: .structuralMutation, onAction: callbacks.onNewTab)),
            ],
            [
                .action(
                    .init(
                        title: "Reload Selected Tab",
                        systemImage: "arrow.clockwise",
                        isEnabled: hasSelectedTab,
                        onAction: callbacks.onReloadSelectedTab
                    )
                ),
                .action(
                    .init(
                        title: "Bookmark Selected Tab…",
                        systemImage: "bookmark",
                        isEnabled: hasSelectedTab,
                        classification: .presentationOnly,
                        onAction: callbacks.onBookmarkSelectedTab
                    )
                ),
                .action(
                    .init(
                        title: "Reopen Closed Tab",
                        systemImage: "arrow.uturn.backward",
                        classification: .structuralMutation,
                        onAction: callbacks.onReopenClosedTab
                    )
                ),
            ],
            [
                .action(
                    .init(
                        title: "Enable compact mode",
                        systemImage: "circle.grid.2x2",
                        state: isCompactModeEnabled ? .on : .off,
                        onAction: callbacks.onToggleCompactMode
                    )
                ),
            ],
            [
                .action(.init(title: "Edit Theme", systemImage: "paintpalette", classification: .presentationOnly, onAction: callbacks.onEditTheme)),
                .action(.init(title: "Sumi Layout…", systemImage: "slider.horizontal.3", classification: .presentationOnly, onAction: callbacks.onOpenLayout)),
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
