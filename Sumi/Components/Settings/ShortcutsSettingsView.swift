import SwiftUI

struct ShortcutsSettingsView: View {
    let shortcutManager: KeyboardShortcutManager

    @State private var searchText = ""

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "Filters",
                subtitle: "Find commands before editing their key combinations."
            ) {
                SettingsRow(title: "Search") {
                    searchField
                }
            }

            SettingsSection(
                title: "Shortcuts",
                subtitle: "Customizable shortcuts can be disabled or recorded again."
            ) {
                if filteredShortcuts.isEmpty {
                    SettingsEmptyState(
                        systemImage: "keyboard",
                        title: "No Shortcuts",
                        detail: "No keyboard shortcuts match the current filters."
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(ShortcutCategory.allCases, id: \.self) { category in
                            if let categoryShortcuts = shortcutsByCategory[category], !categoryShortcuts.isEmpty {
                                ShortcutCategorySection(
                                    category: category,
                                    shortcuts: categoryShortcuts,
                                    shortcutManager: shortcutManager
                                )
                            }
                        }
                    }
                }

                SettingsDivider()

                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        shortcutManager.resetToDefaults()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var searchField: some View {
        TextField("Search shortcuts...", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(width: 220)
    }
}

private struct ShortcutCategorySection: View {
    let category: ShortcutCategory
    let shortcuts: [KeyboardShortcut]
    let shortcutManager: KeyboardShortcutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(category.displayName, systemImage: category.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(shortcuts.enumerated()), id: \.element.action) { index, shortcut in
                    ShortcutRowView(shortcut: shortcut, shortcutManager: shortcutManager)

                    if index < shortcuts.count - 1 {
                        SettingsDivider()
                    }
                }
            }
        }
    }
}

private struct ShortcutRowView: View {
    let shortcut: KeyboardShortcut
    let shortcutManager: KeyboardShortcutManager

    var body: some View {
        HStack(spacing: 12) {
            Text(shortcut.action.displayName)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            ShortcutRecorderView(
                keyCombination: shortcut.keyCombination,
                onValidate: validate,
                onCommit: commit,
                onClear: clear
            )
        }
        .padding(.vertical, 8)
    }

    private func validate(_ combination: KeyCombination) -> ShortcutValidationResult {
        shortcutManager.validate(combination, excludingAction: shortcut.action)
    }

    private func commit(_ combination: KeyCombination) -> ShortcutValidationResult {
        shortcutManager.setShortcut(action: shortcut.action, keyCombination: combination)
    }

    private func clear() -> Bool {
        shortcutManager.clearShortcut(action: shortcut.action)
    }
}
