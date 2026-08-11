//
//  FolderGlyphPicker.swift
//  Sumi
//

import AppKit
import SwiftUI

struct FolderGlyphPicker: View {
    let currentIcon: String
    let tokens: ChromeThemeTokens
    let onIconSelected: (String) -> Void

    @StateObject private var model = FolderGlyphPickerViewModel()

    var body: some View {
        FolderGlyphPickerPanel(
            model: model,
            tokens: tokens,
            onIconSelected: onIconSelected
        )
        .onAppear {
            model.resetForOpen(currentIcon: currentIcon)
        }
    }
}

@MainActor
private final class FolderGlyphPickerViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var debouncedSearch = ""
    @Published var currentIcon: String = ""

    private var debounceTask: Task<Void, Never>?

    func resetForOpen(currentIcon: String) {
        debounceTask?.cancel()
        debounceTask = nil
        searchText = ""
        debouncedSearch = ""
        self.currentIcon = SumiZenFolderIconCatalog.normalizedFolderIconValue(currentIcon)
    }

    func setSearchText(_ value: String) {
        searchText = value
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == debouncedSearch {
            debounceTask?.cancel()
            debounceTask = nil
            return
        }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: SumiEmojiPickerMetrics.searchDebounce)
            guard !Task.isCancelled else { return }
            debouncedSearch = normalized
        }
    }
}

private struct FolderGlyphPickerPanel: View {
    @ObservedObject var model: FolderGlyphPickerViewModel
    let tokens: ChromeThemeTokens
    let onIconSelected: (String) -> Void

    @State private var displayedEntries: [FolderGlyphPickerEntry] = FolderGlyphPickerCatalog.allEntries

    private let columns = [GridItem(.adaptive(minimum: 36), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FolderGlyphSearchField(
                text: Binding(
                    get: { model.searchText },
                    set: { model.setSearchText($0) }
                ),
                placeholder: "Search icons...",
                tokens: tokens
            )
            .accessibilityIdentifier("folder-glyph-picker-search")

            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    FolderGlyphResetGridCell(
                        isSelected: model.currentIcon.isEmpty,
                        tokens: tokens,
                        onTap: {
                            model.currentIcon = ""
                            onIconSelected("")
                        }
                    )

                    ForEach(displayedEntries) { entry in
                        FolderGlyphGridCell(
                            entry: entry,
                            isSelected: entry.storageValue == model.currentIcon,
                            tokens: tokens,
                            onTap: {
                                model.currentIcon = entry.storageValue
                                onIconSelected(entry.storageValue)
                            }
                        )
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(width: SumiEmojiPickerMetrics.popoverWidth, height: SumiEmojiPickerMetrics.popoverHeight)
        .background(tokens.floatingSurfaceBackground)
        .modifier(FolderGlyphPickerAppearModifier())
        .accessibilityIdentifier("folder-glyph-picker-panel")
        .onAppear {
            displayedEntries = FolderGlyphPickerCatalog.entries(
                matching: model.debouncedSearch,
                in: FolderGlyphPickerCatalog.allEntries
            )
        }
        .onChange(of: model.debouncedSearch) { _, newValue in
            displayedEntries = FolderGlyphPickerCatalog.entries(
                matching: newValue,
                in: FolderGlyphPickerCatalog.allEntries
            )
        }
    }
}

private struct FolderGlyphSearchField: View {
    @Binding var text: String
    let placeholder: String
    let tokens: ChromeThemeTokens
    @FocusState private var isFocused: Bool

    private var fieldFont: Font {
        .system(size: 13)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.secondaryText)
                .frame(width: 14, height: 14)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(fieldFont)
                        .foregroundStyle(tokens.secondaryText)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }

                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(fieldFont)
                    .foregroundStyle(tokens.primaryText)
                    .tint(tokens.accent)
                    .focused($isFocused)
                    .accessibilityLabel(placeholder)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(tokens.floatingSurfaceSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isFocused ? tokens.accent.opacity(0.82) : tokens.separator.opacity(0.72),
                    lineWidth: isFocused ? 1.5 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.easeInOut(duration: 0.14), value: isFocused)
    }
}

private struct FolderGlyphPickerAppearModifier: ViewModifier {
    @State private var presented = false

    func body(content: Content) -> some View {
        content
            .opacity(presented ? 1 : 0)
            .scaleEffect(presented ? 1 : SumiEmojiPickerMetrics.appearScale, anchor: .top)
            .offset(y: presented ? 0 : SumiEmojiPickerMetrics.appearOffsetY)
            .onAppear {
                presented = false
                DispatchQueue.main.async {
                    withAnimation(
                        .spring(
                            response: SumiEmojiPickerMetrics.appearSpringResponse,
                            dampingFraction: SumiEmojiPickerMetrics.appearSpringDamping
                        )
                    ) {
                        presented = true
                    }
                }
            }
            .onDisappear {
                withAnimation(.easeOut(duration: SumiEmojiPickerMetrics.disappearEaseDuration)) {
                    presented = false
                }
            }
    }
}

private struct FolderGlyphGridCell: View {
    let entry: FolderGlyphPickerEntry
    let isSelected: Bool
    let tokens: ChromeThemeTokens
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let image = SumiZenFolderIconCatalog.bundledFolderImage(named: entry.iconName) {
                    SumiZenBundledIconView(
                        image: image,
                        size: 21,
                        tint: tokens.primaryText
                    )
                } else {
                    Image(systemName: "folder")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(tokens.primaryText)
                }
            }
            .frame(width: 34, height: 34)
            .background(cellBackground)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .sidebarHover($hovering)
        .help(entry.displayName)
        .accessibilityLabel(entry.displayName)
    }

    private var cellBackground: Color {
        if isSelected {
            Color(nsColor: .selectedContentBackgroundColor).opacity(0.55)
        } else if hovering {
            Color(nsColor: .quaternaryLabelColor).opacity(0.45)
        } else {
            Color.clear
        }
    }
}

private struct FolderGlyphResetGridCell: View {
    let isSelected: Bool
    let tokens: ChromeThemeTokens
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "folder")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tokens.secondaryText)
                .frame(width: 34, height: 34)
                .background(cellBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .sidebarHover($hovering)
        .help("Default Folder Icon")
        .accessibilityLabel("Default Folder Icon")
    }

    private var cellBackground: Color {
        if isSelected {
            Color(nsColor: .selectedContentBackgroundColor).opacity(0.55)
        } else if hovering {
            Color(nsColor: .quaternaryLabelColor).opacity(0.45)
        } else {
            Color.clear
        }
    }
}

private struct FolderGlyphPickerEntry: Identifiable, Hashable {
    let iconName: String
    let storageValue: String
    let displayName: String
    let searchHaystack: String

    var id: String { iconName }
}

private enum FolderGlyphPickerCatalog {
    static let allEntries: [FolderGlyphPickerEntry] = SumiZenFolderIconCatalog
        .bundledFolderIconNames()
        .map { iconName in
            let displayName = Self.displayName(for: iconName)
            return FolderGlyphPickerEntry(
                iconName: iconName,
                storageValue: SumiZenFolderIconCatalog.storageValue(for: iconName),
                displayName: displayName,
                searchHaystack: "\(iconName) \(displayName)".lowercased()
            )
        }

    static func entries(
        matching query: String,
        in entries: [FolderGlyphPickerEntry]
    ) -> [FolderGlyphPickerEntry] {
        let queryTokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split { $0.isWhitespace }
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !queryTokens.isEmpty else { return entries }

        return entries.filter { entry in
            queryTokens.allSatisfy { entry.searchHaystack.contains($0) }
        }
    }

    private static func displayName(for iconName: String) -> String {
        iconName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: " 1", with: "")
            .capitalized
    }
}
