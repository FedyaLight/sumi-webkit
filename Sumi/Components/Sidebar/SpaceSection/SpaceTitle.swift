import SwiftUI

struct SpaceTitleActions {
    let canDeleteSpace: Bool
    let renameSpace: (String) -> Void
    let updateSpaceIcon: (String) -> Void
    let persistCommittedEmoji: (String) -> Void
    let editSpace: () -> Void
    let changeTheme: () -> Void
    let deleteSpace: () -> Void
}

enum SpaceTitleRowLayout {
    static let iconFontScale: CGFloat = 0.78
    static let titleFontSize: CGFloat = 14
    static let titleFontWeight: Font.Weight = .semibold
    static let trailingControlSize: CGFloat = 28
    static let verticalPadding: CGFloat = 5
    static let defaultCornerRadius: CGFloat = 12

    static var iconFontSize: CGFloat {
        SidebarRowLayout.faviconSize * iconFontScale
    }

    static var minimumHeight: CGFloat {
        trailingControlSize + verticalPadding * 2
    }
}

struct SpaceTitleIconView: View {
    let iconValue: String
    let textColor: Color
    var hidesAccessibility = false

    var body: some View {
        Group {
            if SumiPersistentGlyph.presentsAsEmoji(iconValue) {
                Text(iconValue)
                    .font(.system(size: SpaceTitleRowLayout.iconFontSize))
            } else {
                Image(systemName: SumiPersistentGlyph.resolvedSpaceSystemImageName(iconValue))
                    .font(.system(size: SpaceTitleRowLayout.iconFontSize, weight: .medium))
                    .foregroundStyle(textColor)
            }
        }
        .accessibilityHidden(hidesAccessibility)
    }
}

struct SpaceTitleTextLabel: View {
    let title: String
    let textColor: Color

    var body: some View {
        SidebarFadingRowTitleLabel(
            title: title,
            font: .system(size: SpaceTitleRowLayout.titleFontSize, weight: SpaceTitleRowLayout.titleFontWeight),
            color: textColor
        )
    }
}

struct SpaceTitleRowChrome<Icon: View, TitleContent: View, TrailingContent: View>: View {
    let backgroundColor: Color
    let cornerRadius: CGFloat
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let title: () -> TitleContent
    @ViewBuilder let trailing: () -> TrailingContent

    var body: some View {
        HStack(spacing: SidebarRowLayout.iconTrailingSpacing) {
            icon()
                .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)

            title()

            Spacer(minLength: 0)

            trailing()
                .frame(
                    width: SpaceTitleRowLayout.trailingControlSize,
                    height: SpaceTitleRowLayout.trailingControlSize
                )
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .padding(.vertical, SpaceTitleRowLayout.verticalPadding)
        .frame(maxWidth: .infinity)
        .frame(minHeight: SpaceTitleRowLayout.minimumHeight)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct SpaceTitle: View {
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    let space: Space
    let actions: SpaceTitleActions
    var isAppKitInteractionEnabled: Bool = true

    @State private var isRenaming: Bool = false
    @State private var draftName: String = ""
    @State private var isRowHovered = false
    @FocusState private var nameFieldFocused: Bool

    @StateObject private var emojiManager = EmojiPickerManager()

    var body: some View {
        SpaceTitleRowChrome(
            backgroundColor: hoverColor,
            cornerRadius: titleCornerRadius
        ) {
            iconView
        } title: {
            titleView
        } trailing: {
            menuButton
        }
        .accessibilityIdentifier("space-title-\(space.id.uuidString)")
        .sidebarDDGHover($isRowHovered, isEnabled: isAppKitInteractionEnabled)
        .onChange(of: nameFieldFocused) { _, focused in
            // When losing focus during rename, commit
            if isRenaming && !focused {
                commitRename()
            }
        }
        .sidebarAppKitContextMenu(
            isInteractionEnabled: isAppKitInteractionEnabled,
            entries: {
                spaceContextMenuEntries()
            }
        )
    }

    @ViewBuilder
    private var iconView: some View {
        ZStack {
            SpaceTitleIconView(
                iconValue: space.icon,
                textColor: textColor
            )
            .background(EmojiPickerAnchor(manager: emojiManager))
            .onTapGesture(count: 2) {
                toggleSpaceIconPicker()
            }
            .modifier(
                SpaceTitleEmojiPickModifier(
                    emojiManager: emojiManager,
                    space: space,
                    persistCommittedEmoji: actions.persistCommittedEmoji
                )
            )
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if isRenaming {
            TextField("", text: $draftName)
                .font(.system(size: SpaceTitleRowLayout.titleFontSize, weight: SpaceTitleRowLayout.titleFontWeight))
                .foregroundStyle(textColor)
                .textFieldStyle(PlainTextFieldStyle())
                .autocorrectionDisabled()
                .focused($nameFieldFocused)
                .onAppear {
                    draftName = space.name
                    DispatchQueue.main.async {
                        nameFieldFocused = true
                    }
                }
                .onSubmit {
                    commitRename()
                }
                .onExitCommand {
                    cancelRename()
                }
        } else {
            SpaceTitleTextLabel(
                title: space.name,
                textColor: textColor
            )
                .onTapGesture(count: 2) {
                    startRenaming()
                }
        }
    }

    private var menuButton: some View {
        Button(action: {}) {
            Label("Configure Space", systemImage: "ellipsis")
                .font(.body.weight(.semibold))
                .labelStyle(.iconOnly)
        }
        .buttonStyle(NavButtonStyle(size: .small))
        .opacity(displayIsHovering ? 1.0 : 0.0)
        .accessibilityIdentifier("space-title-menu-button-\(space.id.uuidString)")
        .sidebarAppKitContextMenu(
            isInteractionEnabled: isAppKitInteractionEnabled,
            surfaceKind: .button,
            triggers: [.leftClick],
            entries: { spaceContextMenuEntries() }
        )
    }

    // MARK: - Colors

    private var hoverColor: Color {
        if displayIsHovering {
            return tokens.sidebarRowHover
        } else {
            return .clear
        }
    }
    private var textColor: Color {
        tokens.primaryText
    }

    private var canDeleteSpace: Bool {
        actions.canDeleteSpace
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var titleCornerRadius: CGFloat {
        sumiSettings.resolvedCornerRadius(SpaceTitleRowLayout.defaultCornerRadius)
    }

    private var freezesHoverState: Bool {
        windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var displayIsHovering: Bool {
        SidebarHoverChrome.displayHover(isRowHovered, freezesHoverState: freezesHoverState)
    }

    // MARK: - Actions

    private func startRenaming() {
        draftName = space.name
        isRenaming = true
    }

    private func cancelRename() {
        isRenaming = false
        draftName = space.name
        nameFieldFocused = false
    }

    private func commitRename() {
        let newName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty, newName != space.name {
            actions.renameSpace(newName)
        }
        isRenaming = false
        nameFieldFocused = false
    }

    private func spaceContextMenuEntries() -> [SidebarContextMenuEntry] {
        let deleteSpaceAction: (() -> Void)?
        if canDeleteSpace {
            deleteSpaceAction = { showDeleteConfirmation() }
        } else {
            deleteSpaceAction = nil
        }

        return makeSpaceContextMenuEntries(
            actions: .init(
                edit: {
                    actions.editSpace()
                },
                changeTheme: {
                    actions.changeTheme()
                },
                deleteSpace: deleteSpaceAction
            )
        )
    }

    private func showDeleteConfirmation() {
        actions.deleteSpace()
    }

    private func toggleSpaceIconPicker() {
        emojiManager.selectedEmoji = SumiPersistentGlyph.presentsAsEmoji(space.icon) ? space.icon : ""
        emojiManager.toggle(
            source: windowState.resolveSidebarPresentationSource(),
            settings: sumiSettings,
            themeContext: themeContext,
            onCommit: commitSpaceIcon
        )
    }

    private func commitSpaceIcon(_ picked: String) {
        let normalized = SumiPersistentGlyph.normalizedSpaceIconValue(picked)
        actions.updateSpaceIcon(normalized)
    }
}

// MARK: - Emoji picker

private struct SpaceTitleEmojiPickModifier: ViewModifier {
    @ObservedObject var emojiManager: EmojiPickerManager
    let space: Space
    let persistCommittedEmoji: (String) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: emojiManager.committedEmoji) { _, newValue in
                RuntimeDiagnostics.emit(newValue)
                guard !newValue.isEmpty else { return }
                let picked = newValue
                DispatchQueue.main.async {
                    space.icon = SumiPersistentGlyph.normalizedSpaceIconValue(picked)
                    persistCommittedEmoji(picked)
                }
            }
    }
}
