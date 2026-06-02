import SwiftUI

enum SidebarSpaceCreationFocusedField: Hashable {
    case name
    case newProfileName
}

enum SidebarSpaceCreationMetrics {
    static let horizontalPadding: CGFloat = 8
    static let groupSpacing: CGFloat = 12
    static let formRowHeight: CGFloat = 42
    static let iconWellSize: CGFloat = 28
}

struct SidebarSpaceCreationView: View {
    @ObservedObject var session: SpaceCreationSession
    let onCreate: () -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var focusedField: SidebarSpaceCreationFocusedField?
    @StateObject private var emojiManager = EmojiPickerManager()

    var body: some View {
        VStack(alignment: .leading, spacing: SidebarSpaceCreationMetrics.groupSpacing) {
            titleRow

            formGroup

            actionButtons
        }
        .padding(.horizontal, SidebarSpaceCreationMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: focusNameField)
        .onExitCommand(perform: cancel)
        .accessibilityIdentifier("sidebar-space-creation")
    }

    private var titleRow: some View {
        HStack(spacing: SidebarRowLayout.iconTrailingSpacing) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: SidebarRowLayout.faviconSize * 0.78, weight: .semibold))
                .foregroundStyle(tokens.secondaryText)
                .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)

            Text("New space")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tokens.primaryText)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .padding(.vertical, 5)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
    }

    private var formGroup: some View {
        VStack(spacing: 0) {
            nameRow

            Divider()
                .overlay(tokens.separator.opacity(0.58))
                .padding(.leading, SidebarRowLayout.leadingInset + SidebarSpaceCreationMetrics.iconWellSize + 10)

            profileRow

            if session.createsNewProfile {
                Divider()
                    .overlay(tokens.separator.opacity(0.58))
                    .padding(.leading, SidebarRowLayout.leadingInset + SidebarSpaceCreationMetrics.iconWellSize + 10)

                SidebarSpaceCreationNewProfileEditor(
                    session: session,
                    validationMessage: newProfileValidationMessage,
                    focusedField: $focusedField,
                    tokens: tokens,
                    iconCornerRadius: iconCornerRadius,
                    onSubmit: createIfPossible
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: formCornerRadius, style: .continuous)
                .fill(tokens.fieldBackground.opacity(0.78))
        }
        .overlay {
            RoundedRectangle(cornerRadius: formCornerRadius, style: .continuous)
                .stroke(tokens.separator.opacity(0.74), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: formCornerRadius, style: .continuous))
        .animation(profileExpansionAnimation, value: session.createsNewProfile)
    }

    private var nameRow: some View {
        HStack(spacing: 10) {
            Button(action: openEmojiPicker) {
                spaceIconView
                    .frame(
                        width: SidebarSpaceCreationMetrics.iconWellSize,
                        height: SidebarSpaceCreationMetrics.iconWellSize
                    )
                    .background(tokens.chromeControlHoverBackground.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .background(EmojiPickerAnchor(manager: emojiManager))
            .help("Choose icon")
            .accessibilityLabel("Choose Space Icon")

            TextField("Name", text: $session.name)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tokens.primaryText)
                .focused($focusedField, equals: .name)
                .onSubmit(createIfPossible)
                .accessibilityIdentifier("sidebar-space-creation-name")
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarSpaceCreationMetrics.formRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileRow: some View {
        HStack(spacing: 10) {
            Color.clear
                .frame(
                    width: SidebarSpaceCreationMetrics.iconWellSize,
                    height: SidebarSpaceCreationMetrics.iconWellSize
                )
                .accessibilityHidden(true)

            Text("Profile")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tokens.secondaryText)

            Spacer(minLength: 0)

            Menu {
                ForEach(browserManager.profileManager.profiles, id: \.id) { profile in
                    Button {
                        selectExistingProfile(profile.id)
                    } label: {
                        Text(profileMenuItemTitle(for: profile))
                    }
                }

                Divider()

                Button {
                    selectNewProfile()
                } label: {
                    Label("New profile", systemImage: "person.badge.plus")
                }
            } label: {
                profileMenuLabel
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(tokens.chromeControlHoverBackground.opacity(0.56))
                    .clipShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 190, alignment: .trailing)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarSpaceCreationMetrics.formRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileMenuLabel: some View {
        HStack(spacing: 6) {
            if session.createsNewProfile {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 13, weight: .medium))
            } else {
                SumiProfileIconView(
                    icon: currentProfileIcon,
                    font: .system(size: 13, weight: .medium)
                )
            }

            Text(currentProfileName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tokens.secondaryText)
        }
        .foregroundStyle(tokens.primaryText)
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button(action: createIfPossible) {
                Label("Create", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!canCreate)

            Button(action: cancel) {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
            .keyboardShortcut(.escape, modifiers: [])
            .foregroundStyle(tokens.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var spaceIconView: some View {
        let icon = session.resolvedIcon
        if SumiPersistentGlyph.presentsAsEmoji(icon) {
            Text(icon)
                .font(.system(size: 18))
        } else {
            Image(systemName: SumiPersistentGlyph.resolvedSpaceSystemImageName(icon))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tokens.primaryText)
        }
    }

    private var currentProfileName: String {
        if session.createsNewProfile {
            return "New profile"
        }
        guard let profile = currentProfile else {
            return browserManager.profileManager.profiles.first?.name ?? "Default"
        }
        return profile.name
    }

    private var currentProfileIcon: String {
        guard let profile = currentProfile else {
            return browserManager.profileManager.profiles.first?.icon
                ?? SumiProfileIcon.defaultIcon
        }
        return profile.icon
    }

    private func profileMenuItemTitle(for profile: Profile) -> String {
        "\(SumiProfileIcon.storedValue(profile.icon))  \(profile.name)"
    }

    private var currentProfile: Profile? {
        guard let profileID = session.profileID
                ?? browserManager.currentProfile?.id
                ?? browserManager.profileManager.profiles.first?.id
        else { return nil }
        return browserManager.profileManager.profiles.first { $0.id == profileID }
    }

    private var tokens: ChromeThemeTokens {
        themeContext.nativeSurfaceThemeContext.tokens(settings: sumiSettings)
    }

    private var canCreate: Bool {
        session.canCommit && newProfileValidationMessage == nil
    }

    private var newProfileValidationMessage: String? {
        guard session.createsNewProfile,
              session.trimmedNewProfileName.isEmpty == false,
              isNewProfileNameAvailable == false
        else { return nil }
        return "Profile name already exists"
    }

    private var isNewProfileNameAvailable: Bool {
        let trimmed = session.trimmedNewProfileName
        guard trimmed.isEmpty == false else { return false }
        return !browserManager.profileManager.profiles.contains {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private var profileExpansionAnimation: Animation? {
        reduceMotion || sumiSettings.shouldReduceChromeMotion ? nil : .easeInOut(duration: 0.18)
    }

    private var rowCornerRadius: CGFloat {
        sumiSettings.resolvedCornerRadius(12)
    }

    private var formCornerRadius: CGFloat {
        sumiSettings.resolvedCornerRadius(14)
    }

    private var iconCornerRadius: CGFloat {
        min(10, max(8, formCornerRadius - 4))
    }

    private func focusNameField() {
        emojiManager.selectedEmoji = session.resolvedIcon
        guard !reduceMotion, !sumiSettings.shouldReduceChromeMotion else {
            focusedField = .name
            return
        }
        DispatchQueue.main.async {
            focusedField = .name
        }
    }

    private func openEmojiPicker() {
        emojiManager.selectedEmoji = session.resolvedIcon
        emojiManager.toggle(
            source: session.source,
            settings: sumiSettings,
            themeContext: themeContext,
            onCommit: { emoji in
                session.icon = SumiPersistentGlyph.normalizedSpaceIconValue(emoji)
            }
        )
    }

    private func selectExistingProfile(_ profileID: UUID) {
        withAnimation(profileExpansionAnimation) {
            session.profileID = profileID
            session.createsNewProfile = false
        }
    }

    private func selectNewProfile() {
        withAnimation(profileExpansionAnimation) {
            session.profileID = nil
            session.createsNewProfile = true
        }
        DispatchQueue.main.async {
            focusedField = .newProfileName
        }
    }

    private func createIfPossible() {
        guard canCreate else { return }
        syncPendingEmojiSelection()
        emojiManager.popover?.close()
        onCreate()
    }

    private func cancel() {
        session.cancelsOnDismiss = true
        emojiManager.popover?.close()
        onCancel()
    }

    private func syncPendingEmojiSelection() {
        guard emojiManager.selectedEmoji.isEmpty == false else { return }
        session.icon = SumiPersistentGlyph.normalizedSpaceIconValue(emojiManager.selectedEmoji)
    }
}
