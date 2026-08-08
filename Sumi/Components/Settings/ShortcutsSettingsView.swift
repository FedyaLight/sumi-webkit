import AppKit
import SumiDomain
import SwiftUI

struct ShortcutsSettingsView: View {
    let shortcutManager: KeyboardShortcutManager
    let activeProfileID: UUID?
    let extensionsModule: SumiExtensionsModule
    @ObservedObject private var extensionSurfaceStore:
        BrowserExtensionSurfaceStore

    @State private var searchText = ""

    init(
        shortcutManager: KeyboardShortcutManager,
        activeProfileID: UUID?,
        extensionsModule: SumiExtensionsModule,
        extensionSurfaceStore: BrowserExtensionSurfaceStore
    ) {
        self.shortcutManager = shortcutManager
        self.activeProfileID = activeProfileID
        self.extensionsModule = extensionsModule
        _extensionSurfaceStore = ObservedObject(
            wrappedValue: extensionSurfaceStore
        )
    }

    private var filteredShortcuts: [KeyboardShortcut] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return shortcutManager.shortcuts
            .filter { shortcut in
                query.isEmpty || shortcut.action.displayName.localizedCaseInsensitiveContains(query)
            }
    }

    private var shortcutsByCategory: [ShortcutCategory: [KeyboardShortcut]] {
        Dictionary(grouping: filteredShortcuts, by: \.action.category)
    }

    private var filteredExtensionCommands:
        [ExtensionCommandBindingAssignment] {
        _ = shortcutManager.bindingRevision
        _ = extensionSurfaceStore.installedExtensions
        guard let activeProfileID else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return shortcutManager.extensionCommandAssignments(
            profileID: activeProfileID
        ).filter { command in
            query.isEmpty
                || command.title.localizedCaseInsensitiveContains(query)
                || command.extensionName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                searchField

                Spacer(minLength: 16)

                Button("Restore Defaults") {
                    shortcutManager.resetToDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if filteredShortcuts.isEmpty && filteredExtensionCommands.isEmpty {
                SettingsSection {
                    SettingsEmptyState(
                        systemImage: "keyboard",
                        title: "No Shortcuts",
                        detail: "No shortcuts match your search."
                    )
                }
            } else {
                SettingsSection {
                    let visibleCategories = ShortcutCategory.allCases.filter {
                        shortcutsByCategory[$0]?.isEmpty == false
                    }

                    ForEach(Array(visibleCategories.enumerated()), id: \.element) { index, category in
                        if index > 0 {
                            SettingsDivider()
                                .padding(.vertical, 8)
                        }

                        if let categoryShortcuts = shortcutsByCategory[category] {
                            ShortcutCategorySection(
                                category: category,
                                shortcuts: categoryShortcuts,
                                shortcutManager: shortcutManager,
                                activeProfileID: activeProfileID
                            )
                        }
                    }

                    if filteredExtensionCommands.isEmpty == false {
                        if visibleCategories.isEmpty == false {
                            SettingsDivider()
                                .padding(.vertical, 8)
                        }
                        ExtensionShortcutSection(
                            assignments: filteredExtensionCommands,
                            shortcutManager: shortcutManager
                        )
                    }
                }
            }
        }
        .onAppear {
            extensionsModule.prepareForExtensionActivation()
        }
    }

    private var searchField: some View {
        ShortcutSearchField(
            text: $searchText,
            placeholder: String(localized: "Search Shortcuts")
        )
            .frame(width: 220)
    }
}

private struct ExtensionShortcutSection: View {
    let assignments: [ExtensionCommandBindingAssignment]
    let shortcutManager: KeyboardShortcutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Extensions")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

            ForEach(Array(assignments.enumerated()), id: \.element.id) { index, assignment in
                ExtensionShortcutRow(
                    assignment: assignment,
                    shortcutManager: shortcutManager
                )
                if index < assignments.count - 1 {
                    SettingsDivider()
                }
            }
        }
    }
}

private struct ExtensionShortcutRow: View {
    let assignment: ExtensionCommandBindingAssignment
    let shortcutManager: KeyboardShortcutManager

    var body: some View {
        SettingsRow(
            title: assignment.title,
            subtitle: subtitle,
            verticalPadding: 6
        ) {
            if isUnsupported {
                Text("Not available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ShortcutRecorderView(
                    keyCombination: assignment.assignedCombination,
                    onValidate: validate,
                    onCommit: commit,
                    onClear: clear
                )
            }
        }
    }

    private var subtitle: String {
        if let reason = assignment.inactiveReason {
            return "\(assignment.extensionName) · \(reason.userMessage)"
        }
        return assignment.extensionName
    }

    private var isUnsupported: Bool {
        switch assignment.inactiveReason {
        case .unsupportedMedia, .unsupportedGlobal:
            return true
        default:
            return false
        }
    }

    private func validate(
        _ combination: KeyCombination
    ) -> ShortcutValidationResult {
        shortcutManager.validateExtensionCommand(
            combination,
            identity: assignment.identity
        )
    }

    private func commit(
        _ combination: KeyCombination
    ) -> ShortcutValidationResult {
        shortcutManager.setExtensionCommand(
            combination,
            identity: assignment.identity
        )
    }

    private func clear() -> Bool {
        shortcutManager.clearExtensionCommand(identity: assignment.identity)
    }
}

private struct ShortcutSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = placeholder
        searchField.controlSize = .small
        searchField.delegate = context.coordinator
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.text = $text
        searchField.placeholderString = placeholder
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            text.wrappedValue = searchField.stringValue
        }
    }
}

private struct ShortcutCategorySection: View {
    let category: ShortcutCategory
    let shortcuts: [KeyboardShortcut]
    let shortcutManager: KeyboardShortcutManager
    let activeProfileID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

            ForEach(Array(shortcuts.enumerated()), id: \.element.action) { index, shortcut in
                ShortcutRowView(
                    shortcut: shortcut,
                    shortcutManager: shortcutManager,
                    activeProfileID: activeProfileID
                )

                if index < shortcuts.count - 1 {
                    SettingsDivider()
                }
            }
        }
    }
}

private struct ShortcutRowView: View {
    let shortcut: KeyboardShortcut
    let shortcutManager: KeyboardShortcutManager
    let activeProfileID: UUID?

    var body: some View {
        SettingsRow(
            title: shortcut.action.displayName,
            subtitle: assignment.inactiveReason?.userMessage,
            verticalPadding: 6
        ) {
            ShortcutRecorderView(
                keyCombination: assignment.assignedCombination,
                onValidate: validate,
                onCommit: commit,
                onClear: clear
            )
        }
    }

    private var assignment: BrowserActionBindingAssignment {
        shortcutManager.bindingAssignment(for: shortcut.action)
    }

    private func validate(_ combination: KeyCombination) -> ShortcutValidationResult {
        shortcutManager.validate(
            combination,
            excludingAction: shortcut.action,
            profileID: activeProfileID
        )
    }

    private func commit(_ combination: KeyCombination) -> ShortcutValidationResult {
        shortcutManager.setShortcut(
            action: shortcut.action,
            keyCombination: combination,
            profileID: activeProfileID
        )
    }

    private func clear() -> Bool {
        shortcutManager.clearShortcut(action: shortcut.action)
    }
}
