import SwiftUI

struct ShortcutsSettingsView: View {
    let shortcutManager: KeyboardShortcutManager

    @State private var searchText = ""
    @State private var selectedCategory: ShortcutCategory?

    private var filteredShortcuts: [KeyboardShortcut] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return shortcutManager.shortcuts
            .filter { shortcut in
                selectedCategory.map { shortcut.action.category == $0 } ?? true
            }
            .filter { shortcut in
                return query.isEmpty || shortcut.action.displayName.localizedCaseInsensitiveContains(query)
            }
    }

    private var shortcutsByCategory: [ShortcutCategory: [KeyboardShortcut]] {
        Dictionary(grouping: filteredShortcuts, by: \.action.category)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(
                title: "Shortcut Filters",
                subtitle: "Search and narrow commands before editing their key combinations."
            ) {
                filters
            }

            SettingsSection(
                title: "Shortcuts",
                subtitle: "Customizable shortcuts can be disabled or recorded again."
            ) {
                LazyVStack(spacing: 12) {
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
        }
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                searchField
                categoryScroller
                Spacer(minLength: 0)
                resetButton
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    searchField
                    resetButton
                }
                categoryScroller
            }
        }
    }

    private var searchField: some View {
        TextField("Search shortcuts...", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 180, idealWidth: 240, maxWidth: 280)
    }

    private var categoryScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ShortcutCategoryFilterChip(
                    title: "All",
                    icon: nil,
                    isSelected: selectedCategory == nil,
                    onTap: { selectedCategory = nil }
                )
                ForEach(ShortcutCategory.allCases, id: \.self) { category in
                    ShortcutCategoryFilterChip(
                        title: category.displayName,
                        icon: category.icon,
                        isSelected: selectedCategory == category,
                        onTap: { selectedCategory = category }
                    )
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var resetButton: some View {
        Button("Reset to Defaults") {
            shortcutManager.resetToDefaults()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private struct ShortcutCategorySection: View {
    let category: ShortcutCategory
    let shortcuts: [KeyboardShortcut]
    let shortcutManager: KeyboardShortcutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(category.displayName, systemImage: category.icon)
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(shortcuts, id: \.action) { shortcut in
                    ShortcutRowView(shortcut: shortcut, shortcutManager: shortcutManager)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct ShortcutRowView: View {
    let shortcut: KeyboardShortcut
    let shortcutManager: KeyboardShortcutManager

    var body: some View {
        HStack(spacing: 12) {
            Text(shortcut.action.displayName)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer(minLength: 12)

            ShortcutRecorderView(
                keyCombination: shortcut.keyCombination,
                onValidate: validate,
                onCommit: commit,
                onClear: clear
            )
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

private struct ShortcutCategoryFilterChip: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
