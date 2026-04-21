//
//  FolderIconPickerSheet.swift
//  Sumi
//

import SwiftUI

struct FolderIconPickerSheet: View {
    let currentIconValue: String
    let onSelect: (String) -> Void
    let onReset: () -> Void
    /// Dismiss SwiftUI sheet or close `DialogManager` overlay — must not run synchronously from `NSMenu` action.
    let onRequestClose: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    @State private var searchQuery = ""

    private let columns = Array(
        repeating: GridItem(.fixed(44), spacing: 10, alignment: .leading),
        count: 6
    )

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var filteredIcons: [String] {
        let allIcons = SumiZenFolderIconCatalog.bundledFolderIconNames()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return allIcons
        }

        return allIcons.filter { iconName in
            iconName.localizedCaseInsensitiveContains(query)
                || iconName.replacingOccurrences(of: "-", with: " ")
                    .localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedBundledName: String? {
        guard case .bundled(let name) = SumiZenFolderIconCatalog.resolveFolderIcon(currentIconValue) else {
            return nil
        }
        return name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Folder Icon")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tokens.primaryText)

                Spacer(minLength: 0)

                Button("Done") {
                    onRequestClose()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tokens.secondaryText)
            }

            TextField("Search icons", text: $searchQuery)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    FolderIconPickerTile(
                        isSelected: selectedBundledName == nil
                    ) {
                        Image(systemName: "nosign")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(tokens.secondaryText)
                            .frame(width: 20, height: 20)
                    } action: {
                        onRequestClose()
                        onReset()
                    }
                    .help("No icon")

                    ForEach(filteredIcons, id: \.self) { iconName in
                        FolderIconPickerTile(
                            isSelected: selectedBundledName == iconName
                        ) {
                            SumiZenBundledIconView(
                                image: SumiZenFolderIconCatalog.bundledFolderImage(named: iconName),
                                size: 18,
                                tint: tokens.primaryText
                            )
                        } action: {
                            onRequestClose()
                            onSelect(SumiZenFolderIconCatalog.storageValue(for: iconName))
                        }
                        .help(iconName.replacingOccurrences(of: "-", with: " "))
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .frame(width: 360, height: 320)
        .background(tokens.commandPaletteBackground)
        .accessibilityIdentifier("folder-icon-picker-sheet")
    }
}

private struct FolderIconPickerTile<Content: View>: View {
    let isSelected: Bool
    @ViewBuilder let content: () -> Content
    let action: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovered = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: 44, height: 40)
                .background(backgroundFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(borderColor, lineWidth: isSelected ? 1 : 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundFill: Color {
        if isSelected {
            return tokens.fieldBackgroundHover
        }
        return isHovered ? tokens.fieldBackgroundHover : tokens.fieldBackground
    }

    private var borderColor: Color {
        isSelected ? tokens.accent.opacity(0.85) : tokens.separator.opacity(0.7)
    }
}
