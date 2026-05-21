//
//  SidebarSpaceDestinationPickerDialog.swift
//  Sumi
//

import AppKit
import SwiftUI

@MainActor
func presentSidebarSpaceDestinationPicker(
    choices: [SidebarContextMenuChoice],
    browserManager: BrowserManager,
    settings: SumiSettingsService,
    themeContext: ResolvedThemeContext,
    source: SidebarTransientPresentationSource?,
    onSelect: @escaping (UUID) -> Void
) {
    let selectableChoices = choices.filter { $0.isSelected == false }
    guard selectableChoices.isEmpty == false else { return }

    let dialog = SidebarSpaceDestinationPickerDialog(
        choices: selectableChoices,
        onSelect: { choiceId in
            browserManager.closeDialog()
            onSelect(choiceId)
        },
        onCancel: {
            browserManager.closeDialog()
        }
    )
    .environment(\.sumiSettings, settings)
    .environment(\.resolvedThemeContext, themeContext)

    if let source {
        browserManager.showDialog(dialog, source: source)
        return
    }

    browserManager.showDialog(dialog)
}

struct SidebarSpaceDestinationPickerDialog: DialogPresentable {
    let choices: [SidebarContextMenuChoice]
    let onSelect: (UUID) -> Void
    let onCancel: () -> Void

    @State private var searchText = ""

    func dialogHeader() -> DialogHeader {
        DialogHeader(
            icon: "arrow.right",
            title: "Move to Space",
            subtitle: "\(choices.count) available spaces"
        )
    }

    @ViewBuilder
    func dialogContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search spaces", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredChoices, id: \.id) { choice in
                        Button {
                            onSelect(choice.id)
                        } label: {
                            HStack(spacing: 10) {
                                SidebarSpaceDestinationChoiceIcon(icon: choice.icon)
                                Text(choice.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 8)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }

                    if filteredChoices.isEmpty {
                        Text("No spaces found")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }
                }
            }
            .frame(width: 360)
            .frame(maxHeight: 280)
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
            ]
        )
    }

    private var filteredChoices: [SidebarContextMenuChoice] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return choices }

        return choices.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct SidebarSpaceDestinationChoiceIcon: View {
    let icon: SidebarContextMenuIcon?

    var body: some View {
        Group {
            switch icon {
            case .emoji(let glyph):
                Text(glyph)
                    .font(.system(size: 13))
            case .systemImage(let name):
                Image(systemName: name)
                    .font(.system(size: 13, weight: .medium))
            case .folderIcon(let value):
                if let image = folderImage(value) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 13, weight: .medium))
                }
            case nil:
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: 16, height: 16)
    }

    private func folderImage(_ value: String) -> NSImage? {
        guard case .bundled(let name) = SumiZenFolderIconCatalog.resolveFolderIcon(value) else {
            return nil
        }
        return SumiZenFolderIconCatalog.bundledFolderImage(named: name)
    }
}
