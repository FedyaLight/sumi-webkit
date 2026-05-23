//
//  SidebarDeleteConfirmationDialogs.swift
//  Sumi
//
//  Destructive confirmations for saved sidebar items.
//

import SwiftUI

enum SavedTabDeleteKind {
    case essential
    case pinnedTab

    var title: String {
        switch self {
        case .essential:
            return "Delete Essential"
        case .pinnedTab:
            return "Delete Pinned Tab"
        }
    }

    var subtitle: String {
        switch self {
        case .essential:
            return "The Essential will be removed"
        case .pinnedTab:
            return "The Pinned Tab will be removed"
        }
    }

    var warning: String {
        switch self {
        case .essential:
            return "This removes the saved Essential. It does not delete browsing history or website data."
        case .pinnedTab:
            return "This removes the saved Pinned Tab. It does not delete browsing history or website data."
        }
    }
}

struct SavedTabDeleteConfirmationDialog: DialogPresentable {
    let kind: SavedTabDeleteKind
    let displayName: String
    let url: URL
    let onDelete: () -> Void
    let onCancel: () -> Void

    func dialogHeader() -> DialogHeader {
        DialogHeader(
            icon: "trash",
            title: kind.title,
            subtitle: kind.subtitle
        )
    }

    @ViewBuilder
    func dialogContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider().opacity(0.4)

            Label(kind.warning, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func dialogFooter() -> DialogFooter {
        DialogFooter(
            rightButtons: [
                DialogButton(
                    text: "Cancel",
                    variant: .secondary,
                    keyboardShortcut: .escape,
                    action: onCancel
                ),
                DialogButton(
                    text: kind.title,
                    iconName: "trash",
                    variant: .primary,
                    action: onDelete
                )
            ]
        )
    }
}

struct FolderDeleteConfirmationDialog: DialogPresentable {
    let folderName: String
    let childCount: Int
    let onDelete: () -> Void
    let onCancel: () -> Void

    func dialogHeader() -> DialogHeader {
        DialogHeader(
            icon: "trash",
            title: "Delete Folder",
            subtitle: "Pinned tabs in the folder will move out"
        )
    }

    @ViewBuilder
    func dialogContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(folderName)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)

            Label("\(childCount) pinned tabs", systemImage: "pin")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().opacity(0.4)

            Label("The folder will be deleted. Its pinned tabs will stay saved outside the folder.", systemImage: "info.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func dialogFooter() -> DialogFooter {
        DialogFooter(
            rightButtons: [
                DialogButton(
                    text: "Cancel",
                    variant: .secondary,
                    keyboardShortcut: .escape,
                    action: onCancel
                ),
                DialogButton(
                    text: "Delete Folder",
                    iconName: "trash",
                    variant: .primary,
                    keyboardShortcut: .return,
                    action: onDelete
                )
            ]
        )
    }
}
