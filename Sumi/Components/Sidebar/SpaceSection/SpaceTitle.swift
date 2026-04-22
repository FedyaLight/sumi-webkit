import SwiftUI

struct SpaceTitle: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    let space: Space
    var isAppKitInteractionEnabled: Bool = true

    /// Matches favicon / SF Symbol scale in tab and launcher rows (`SidebarRowLayout.faviconSize`).
    private var spaceIconFontSize: CGFloat {
        SidebarRowLayout.faviconSize * 0.78
    }

    @State private var isHovering: Bool = false
    @State private var isRenaming: Bool = false
    @State private var draftName: String = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var isEllipsisHovering: Bool = false
    
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
                        browserManager: browserManager
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
            .opacity(isHovering ? 1.0 : 0.0)
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
        .onHover { hovering in
            guard !freezesHoverState else { return }
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
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
    
    //MARK: - Colors
    
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
        browserManager.tabManager.spaces.count > 1
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var freezesHoverState: Bool {
        windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var displayIsHovering: Bool {
        isHovering && !freezesHoverState
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
            do {
                try browserManager.tabManager.renameSpace(
                    spaceId: space.id,
                    newName: newName
                )
            } catch {
                RuntimeDiagnostics.emit("⚠️ Failed to rename space \(space.id.uuidString):", error)
            }
        }
        isRenaming = false
        nameFieldFocused = false
    }

    private func deleteSpace() {
        browserManager.tabManager.removeSpace(space.id)
    }

    private func spaceContextMenuEntries() -> [SidebarContextMenuEntry] {
        let profiles = browserManager.profileManager.profiles.map { profile in
            SidebarContextMenuChoice(
                id: profile.id,
                title: profile.name,
                isSelected: profile.id == space.profileId
            )
        }

        return makeSpaceContextMenuEntries(
            profiles: profiles,
            canRename: true,
            canChangeIcon: true,
            canDelete: canDeleteSpace,
            callbacks: .init(
                onSelectProfile: { newProfileId in
                    browserManager.tabManager.assign(spaceId: space.id, toProfile: newProfileId)
                },
                onRename: { startRenaming() },
                onChangeIcon: {
                    toggleSpaceIconPicker()
                },
                onChangeTheme: {
                    browserManager.showGradientEditor(
                        for: space,
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                onOpenSettings: {
                    let source = windowState.resolveSidebarPresentationSource()
                    browserManager.showDialog(
                        SpaceEditDialog(
                            space: space,
                            mode: .icon,
                            onSave: { newName, newIcon, newProfileId in
                                updateSpace(name: newName, icon: newIcon, profileId: newProfileId)
                            },
                            onCancel: {
                                browserManager.closeDialog()
                            }
                        ),
                        source: source
                    )
                },
                onDeleteSpace: {
                    showDeleteConfirmation(source: windowState.resolveSidebarPresentationSource())
                }
            )
        )
    }

    private func showDeleteConfirmation(source: SidebarTransientPresentationSource? = nil) {
        let tabsCount = browserManager.tabManager.userVisibleTabCount(for: space.id)

        if let source {
            browserManager.showDialog(
                SpaceDeleteConfirmationDialog(
                    spaceName: space.name,
                    spaceIcon: space.icon,
                    tabsCount: tabsCount,
                    isLastSpace: browserManager.tabManager.spaces.count <= 1,
                    onDelete: {
                        browserManager.closeDialog()
                        DispatchQueue.main.async {
                            deleteSpace()
                        }
                    },
                    onCancel: {
                        browserManager.closeDialog()
                    }
                ),
                source: source
            )
            return
        }

        browserManager.showDialog(
            SpaceDeleteConfirmationDialog(
                spaceName: space.name,
                spaceIcon: space.icon,
                tabsCount: tabsCount,
                isLastSpace: browserManager.tabManager.spaces.count <= 1,
                onDelete: {
                    browserManager.closeDialog()
                    DispatchQueue.main.async {
                        deleteSpace()
                    }
                },
                onCancel: {
                    browserManager.closeDialog()
                }
            )
        )
    }

    private func createFolder() {
        RuntimeDiagnostics.emit("🎯 SpaceTitle.createFolder() called for space '\(space.name)' (id: \(space.id.uuidString.prefix(8))...)")
        _ = browserManager.tabManager.createFolder(for: space.id)
    }

    private func assignProfile(_ id: UUID) {
        browserManager.tabManager.assign(spaceId: space.id, toProfile: id)
    }

    private func updateSpace(name: String, icon: String, profileId: UUID?) {
        browserManager.closeDialog()
        DispatchQueue.main.async {
            do {
                if icon != space.icon {
                    try browserManager.tabManager.updateSpaceIcon(spaceId: space.id, icon: icon)
                }
                if name != space.name {
                    try browserManager.tabManager.renameSpace(spaceId: space.id, newName: name)
                }
                if profileId != space.profileId, let profileId = profileId {
                    browserManager.tabManager.assign(spaceId: space.id, toProfile: profileId)
                }
            } catch {
                RuntimeDiagnostics.emit("⚠️ Failed to update space \(space.id.uuidString):", error)
            }
        }
    }

    private func toggleSpaceIconPicker() {
        emojiManager.selectedEmoji = SumiPersistentGlyph.presentsAsEmoji(space.icon) ? space.icon : ""
        emojiManager.toggle(
            source: windowState.resolveSidebarPresentationSource(),
            onCommit: commitSpaceIcon
        )
    }

    private func commitSpaceIcon(_ picked: String) {
        let normalized = SumiPersistentGlyph.normalizedSpaceIconValue(picked)
        do {
            try browserManager.tabManager.updateSpaceIcon(spaceId: space.id, icon: normalized)
        } catch {
            RuntimeDiagnostics.emit("⚠️ Failed to update space icon \(space.id.uuidString):", error)
        }
    }

    private func resolvedProfileName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return browserManager.profileManager.profiles.first(where: { $0.id == id })?.name
    }
}

// MARK: - Emoji picker

private struct SpaceTitleEmojiPickModifier: ViewModifier {
    @ObservedObject var emojiManager: EmojiPickerManager
    let space: Space
    let browserManager: BrowserManager

    func body(content: Content) -> some View {
        content
            .onChange(of: emojiManager.committedEmoji) { _, newValue in
                RuntimeDiagnostics.emit(newValue)
                guard !newValue.isEmpty else { return }
                let picked = newValue
                DispatchQueue.main.async {
                    space.icon = SumiPersistentGlyph.normalizedSpaceIconValue(picked)
                    browserManager.tabManager.markAllSpacesStructurallyDirty()
                    browserManager.tabManager.scheduleStructuralPersistence()
                }
            }
    }
}
