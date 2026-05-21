//
//  SpaceDeleteConfirmationDialog.swift
//  Sumi
//
//  Destructive confirmation for deleting a Space.
//

import SwiftUI

struct SpaceDeleteConfirmationDialog: DialogPresentable {
    let spaceName: String
    let spaceIcon: String
    let tabsCount: Int
    let isLastSpace: Bool
    let onDelete: () -> Void
    let onCancel: () -> Void

    func dialogHeader() -> DialogHeader {
        DialogHeader(
            icon: "trash",
            title: "Delete Space",
            subtitle: "This action cannot be undone"
        )
    }

    @ViewBuilder
    func dialogContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if SumiPersistentGlyph.presentsAsEmoji(spaceIcon) {
                    Text(spaceIcon)
                        .font(.system(size: 20))
                } else {
                    Image(systemName: SumiPersistentGlyph.resolvedSpaceSystemImageName(spaceIcon))
                        .font(.system(size: 20, weight: .semibold))
                }
                Text(spaceName)
                    .font(.system(size: 16, weight: .semibold))
            }
            .padding(.bottom, 4)

            HStack(spacing: 8) {
                Label("\(tabsCount) tabs", systemImage: "rectangle.stack")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 6) {
                Label("All tabs in this space will be permanently deleted.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                if isLastSpace {
                    Label("You cannot delete the last remaining space.", systemImage: "hand.raised.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
    }

    func dialogFooter() -> DialogFooter {
        DialogFooter(
            rightButtons: [
                DialogButton(
                    text: "Cancel",
                    variant: .secondary,
                    action: onCancel
                ),
                DialogButton(
                    text: "Delete Space",
                    iconName: "trash",
                    variant: isLastSpace ? .secondary : .primary,
                    isEnabled: !isLastSpace,
                    action: onDelete
                )
            ]
        )
    }

}

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
                    keyboardShortcut: .return,
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
