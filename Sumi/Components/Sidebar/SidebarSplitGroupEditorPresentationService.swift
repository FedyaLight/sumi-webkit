import AppKit
import SumiDomain

/// Native, URL-free editor for split-group metadata. Participant launcher
/// editing remains in each participant submenu; this surface owns only the
/// optional group name and group icon.
@MainActor
final class SidebarSplitGroupEditorPresentationService {
    private let groups: SplitGroupStore
    private let mutations: SplitGroupMutationService
    private let windows: SidebarWindowIdentityQuery
    private let duplication: SidebarSplitGroupDuplicationService
    private let moves: SidebarSplitGroupMoveService

    init(
        groups: SplitGroupStore,
        mutations: SplitGroupMutationService,
        windows: SidebarWindowIdentityQuery,
        duplication: SidebarSplitGroupDuplicationService,
        moves: SidebarSplitGroupMoveService
    ) {
        self.groups = groups
        self.mutations = mutations
        self.windows = windows
        self.duplication = duplication
        self.moves = moves
    }

    func show(
        _ group: SplitGroup,
        in windowState: BrowserWindowState,
        themeContext: ResolvedThemeContext
    ) {
        guard groups.group(id: group.id) == group else { return }

        let nameField = NSTextField(string: group.title ?? "")
        nameField.placeholderString = "Name (optional)"
        nameField.setAccessibilityIdentifier("split-group-editor-name-field")

        let iconField = NSTextField(string: group.iconAsset ?? "")
        iconField.placeholderString = "Emoji or SF Symbol (optional)"
        iconField.setAccessibilityIdentifier("split-group-editor-icon-field")

        let stack = NSStackView(views: [
            labeledField("Name", field: nameField),
            labeledField("Icon", field: iconField),
        ])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 82)

        let alert = NSAlert()
        alert.messageText = "Edit Split View"
        alert.informativeText = "A group icon replaces the participant composition in the sidebar."
        alert.accessoryView = stack
        alert.addButton(withTitle: "Done")
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        alert.sumiApplyNativeSurfaceAppearance(themeContext: themeContext)

        let commit: @MainActor () -> Void = { [weak self] in
            self?.commit(group, name: nameField.stringValue, icon: iconField.stringValue)
        }
        if let window = windows.shellWindow(for: windowState) {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                Task { @MainActor in commit() }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            commit()
        }
    }

    func confirmDelete(
        _ group: SplitGroup,
        in windowState: BrowserWindowState,
        themeContext: ResolvedThemeContext,
        onDelete: @escaping @MainActor () -> Void
    ) {
        SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteSplitGroup(
            title: SplitGroupSidebarModel.displayTitle(for: group),
            memberCount: group.memberIDs.count,
            window: windows.shellWindow(for: windowState),
            themeContext: themeContext,
            onDelete: onDelete
        )
    }

    func duplicate(_ group: SplitGroup, in windowState: BrowserWindowState) {
        duplication.duplicate(group, in: windowState)
    }

    func moveMenuEntries(
        for group: SplitGroup,
        in windowState: BrowserWindowState
    ) -> [SidebarContextMenuEntry] {
        moves.destinations(for: group, in: windowState).map { destination in
            .action(.init(
                title: moveTitle(destination),
                systemImage: moveSystemImage(destination),
                classification: .structuralMutation,
                action: { [moves] in
                    _ = moves.move(group, to: destination, in: windowState)
                }
            ))
        }
    }

    private func moveTitle(
        _ destination: SidebarSplitGroupMoveService.Destination
    ) -> String {
        switch destination {
        case .regular: return "Regular Tabs"
        case .pinned: return "Pinned Tabs"
        case .favorite: return "Favorite"
        case .folder(_, let name, _): return name
        }
    }

    private func moveSystemImage(
        _ destination: SidebarSplitGroupMoveService.Destination
    ) -> String {
        switch destination {
        case .regular: return "rectangle.stack"
        case .pinned: return "pin"
        case .favorite: return "square.grid.2x2"
        case .folder: return "folder"
        }
    }

    private func commit(_ expected: SplitGroup, name: String, icon: String) {
        guard groups.group(id: expected.id) == expected else { return }
        let title = optionalTrimmed(name)
        let iconAsset = optionalTrimmed(icon).map(
            SumiPersistentGlyph.normalizedLauncherIconValue
        )
        guard let replacement = expected.editingMetadata(
            title: title,
            iconAsset: iconAsset
        ), replacement != expected else { return }
        _ = mutations.replace(expected, with: replacement)
    }

    private func optionalTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func labeledField(_ title: String, field: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [label, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        label.widthAnchor.constraint(equalToConstant: 42).isActive = true
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true
        return row
    }
}
