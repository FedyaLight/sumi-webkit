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

struct SpaceTitle: View {
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    let space: Space
    let actions: SpaceTitleActions
    var isAppKitInteractionEnabled: Bool = true

    /// Matches favicon / SF Symbol scale in tab and launcher rows (`SidebarRowLayout.faviconSize`).
    private var spaceIconFontSize: CGFloat {
        SidebarRowLayout.faviconSize * 0.78
    }

    @State private var isRenaming: Bool = false
    @State private var draftName: String = ""
    @State private var isRowHovered = false
    @FocusState private var nameFieldFocused: Bool

    @StateObject private var emojiManager = EmojiPickerManager()

    var body: some View {
        HStack(spacing: SidebarRowLayout.iconTrailingSpacing) {
            // Show emoji or SF Symbol icon
            ZStack {
                Group {
                    if SumiPersistentGlyph.presentsAsEmoji(space.icon) {
                        Text(space.icon)
                            .font(.system(size: spaceIconFontSize))
                    } else {
                        Image(systemName: SumiPersistentGlyph.resolvedSpaceSystemImageName(space.icon))
                            .font(.system(size: spaceIconFontSize, weight: .medium))
                            .foregroundStyle(textColor)
                    }
                }
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
            .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)

            if isRenaming {
                TextField("", text: $draftName)
                    .font(.system(size: 14, weight: .semibold))
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
                HStack(spacing: 0) {
                    Text(space.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .onTapGesture(count: 2) {
                            startRenaming()
                        }
                }
            }

            Spacer()

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
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(hoverColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
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
