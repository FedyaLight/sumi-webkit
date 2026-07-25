import SwiftUI
import SumiDomain

enum SidebarSpaceCreationFocusedField: Hashable {
    case name
    case newProfileName
}

enum SidebarSpaceCreationMetrics {
    static let horizontalPadding: CGFloat = 8
    static let groupSpacing: CGFloat = 12
    static let formRowHeight: CGFloat = 42
    static let iconWellSize: CGFloat = 28
    static let actionHorizontalPadding: CGFloat = 16
    static let primaryButtonHeight: CGFloat = 40
    static let primaryButtonCornerRadius: CGFloat = 10
}

@MainActor
struct SpaceCreationProfileContext {
    let profiles: [Profile]
    let currentProfileID: UUID?

    var fallbackProfile: Profile? {
        profiles.first
    }

    func resolvedProfile(for session: SpaceCreationSession) -> Profile? {
        guard let profileID = session.profileID ?? currentProfileID ?? profiles.first?.id else {
            return nil
        }
        return profiles.first { $0.id == profileID }
    }

    func isNewProfileNameAvailable(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        return !profiles.contains {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }
}

struct SidebarSpaceCreationView: View {
    @ObservedObject var session: SpaceCreationSession
    let profileContext: SpaceCreationProfileContext
    let onThemePreview: @MainActor (WorkspaceTheme) -> Void
    let onCreate: () -> Void
    let onCancel: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var focusedField: SidebarSpaceCreationFocusedField?
    @StateObject private var emojiManager = EmojiPickerManager()
    @State private var showsProfileInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: SidebarSpaceCreationMetrics.groupSpacing) {
            headerSection

            nameCard

            profileCard

            if session.createsNewProfile {
                newProfileCard
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            themeCard

            Spacer(minLength: 0)

            actionButtons
        }
        .animation(profileExpansionAnimation, value: session.createsNewProfile)
        .padding(.horizontal, SidebarSpaceCreationMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: focusNameField)
        .onChange(of: session.workspaceTheme) { _, theme in
            onThemePreview(theme)
        }
        .onExitCommand(perform: cancel)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar-space-creation")
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            SidebarSpaceCreationHeaderIllustration(tokens: tokens)
                .padding(.top, 12)

            Text("Create a Space")
                .font(SidebarSpaceCreationThemeTokens.Typography.headerTitle)
                .foregroundStyle(tokens.primaryText)

            Text("Separate your tabs for life, work, projects, and more.")
                .font(SidebarSpaceCreationThemeTokens.Typography.headerSubtitle)
                .foregroundStyle(tokens.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private var nameCard: some View {
        nameRow
            .modifier(cardBackground)
    }

    private var profileCard: some View {
        profileRow
            .modifier(cardBackground)
    }

    private var newProfileCard: some View {
        SidebarSpaceCreationNewProfileEditor(
            session: session,
            validationMessage: newProfileValidationMessage,
            focusedField: $focusedField,
            tokens: tokens,
            onSubmit: createIfPossible
        )
        .modifier(cardBackground)
    }

    private var themeCard: some View {
        SidebarSpaceCreationThemeRow(
            session: session,
            tokens: tokens,
            rowCornerRadius: rowCornerRadius
        )
        .modifier(cardBackground)
    }

    private var nameRow: some View {
        HStack(spacing: 10) {
            Button(action: openEmojiPicker) {
                spaceIconView
                    .frame(
                        width: SidebarSpaceCreationMetrics.iconWellSize,
                        height: SidebarSpaceCreationMetrics.iconWellSize
                    )
            }
            .buttonStyle(.plain)
            .background(EmojiPickerAnchor(manager: emojiManager))
            .help("Choose icon")
            .accessibilityLabel("Choose Space Icon")

            TextField("Space name...", text: $session.name)
                .textFieldStyle(.plain)
                .font(SidebarSpaceCreationThemeTokens.Typography.field)
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
            Image(systemName: "person.crop.circle")
                .font(SidebarSpaceCreationThemeTokens.Typography.rowGlyph)
                .foregroundStyle(tokens.secondaryText)
                .frame(
                    width: SidebarSpaceCreationMetrics.iconWellSize,
                    height: SidebarSpaceCreationMetrics.iconWellSize
                )
                .accessibilityHidden(true)

            Text("Profile")
                .font(SidebarSpaceCreationThemeTokens.Typography.rowLabel)
                .foregroundStyle(tokens.primaryText)

            Spacer(minLength: 0)

            Menu {
                ForEach(profileContext.profiles, id: \.id) { profile in
                    Button {
                        selectExistingProfile(profile.id)
                    } label: {
                        Text(verbatim: isSelectedProfile(profile) ? "✓ \(profile.name)" : profile.name)
                    }
                }

                Divider()

                Button {
                    selectNewProfile()
                } label: {
                    Label("New Profile…", systemImage: "person.badge.plus")
                }
            } label: {
                profileMenuLabel
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(tokens.chromeControlHoverBackground.opacity(0.56))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 170, alignment: .trailing)
            .accessibilityIdentifier("sidebar-space-creation-profile-menu")

            Button {
                showsProfileInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(SidebarSpaceCreationThemeTokens.Typography.rowGlyph)
                    .foregroundStyle(tokens.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About profiles")
            .popover(isPresented: $showsProfileInfo, arrowEdge: .bottom) {
                Text("Profiles keep cookies, logins, and history separate between spaces.")
                    .font(SidebarSpaceCreationThemeTokens.Typography.rowLabel)
                    .frame(width: 220)
                    .padding(12)
            }
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarSpaceCreationMetrics.formRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileMenuLabel: some View {
        HStack(spacing: 6) {
            Text(currentProfileName)
                .font(SidebarSpaceCreationThemeTokens.Typography.profileMenuText)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(SidebarSpaceCreationThemeTokens.Typography.profileMenuChevron)
                .foregroundStyle(tokens.secondaryText)
        }
        .foregroundStyle(tokens.primaryText)
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            Button(action: createIfPossible) {
                Text("Create Space")
                    .font(SidebarSpaceCreationThemeTokens.Typography.primaryButton)
                    .frame(maxWidth: .infinity)
                    .frame(height: SidebarSpaceCreationMetrics.primaryButtonHeight)
            }
            .buttonStyle(SidebarSpaceCreationPrimaryButtonStyle(tokens: tokens))
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!canCreate)

            Button(action: cancel) {
                Text("Cancel")
                    .font(SidebarSpaceCreationThemeTokens.Typography.secondaryButton)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
            .keyboardShortcut(.escape, modifiers: [])
            .foregroundStyle(tokens.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, SidebarSpaceCreationMetrics.actionHorizontalPadding)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var spaceIconView: some View {
        if hasCustomIcon {
            SpaceIconGlyphView(
                iconValue: session.resolvedIcon,
                textColor: tokens.primaryText,
                defaultDotSize: SumiPersistentGlyph.spaceDefaultDotDiameter,
                emojiFont: SidebarSpaceCreationThemeTokens.Typography.spaceEmoji,
                systemFont: SidebarSpaceCreationThemeTokens.Typography.spaceSymbol,
                hidesAccessibility: true
            )
            .frame(
                width: SidebarSpaceCreationMetrics.iconWellSize,
                height: SidebarSpaceCreationMetrics.iconWellSize
            )
            .background(tokens.chromeControlHoverBackground.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous)
                .strokeBorder(
                    tokens.separator,
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
                .frame(
                    width: SidebarSpaceCreationMetrics.iconWellSize,
                    height: SidebarSpaceCreationMetrics.iconWellSize
                )
                .overlay {
                    Image(systemName: "plus")
                        .font(SidebarSpaceCreationThemeTokens.Typography.rowGlyph)
                        .foregroundStyle(tokens.secondaryText)
                }
        }
    }

    private var hasCustomIcon: Bool {
        session.icon.isEmpty == false
            && session.icon != SpaceCreationSession.defaultIcon
    }

    private var currentProfileName: String {
        if session.createsNewProfile {
            return "New profile"
        }
        guard let profile = currentProfile else {
            return profileContext.fallbackProfile?.name ?? "Default"
        }
        return profile.name
    }

    private func isSelectedProfile(_ profile: Profile) -> Bool {
        session.createsNewProfile == false && currentProfile?.id == profile.id
    }

    private var currentProfile: Profile? {
        profileContext.resolvedProfile(for: session)
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
        return profileContext.isNewProfileNameAvailable(trimmed)
    }

    private var profileExpansionAnimation: Animation? {
        reduceMotion || sumiSettings.shouldReduceChromeMotion ? nil : .easeInOut(duration: 0.18)
    }

    private var cardBackground: SidebarSpaceCreationCardBackground {
        SidebarSpaceCreationCardBackground(
            cornerRadius: formCornerRadius,
            tokens: tokens
        )
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

private struct SidebarSpaceCreationPrimaryButtonStyle: ButtonStyle {
    let tokens: ChromeThemeTokens

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(nsColor: .alternateSelectedControlTextColor))
            .background {
                RoundedRectangle(
                    cornerRadius: SidebarSpaceCreationMetrics.primaryButtonCornerRadius,
                    style: .continuous
                )
                .fill(Color(nsColor: .controlAccentColor))
            }
            .contentShape(
                RoundedRectangle(
                    cornerRadius: SidebarSpaceCreationMetrics.primaryButtonCornerRadius,
                    style: .continuous
                )
            )
            .opacity(opacity(isPressed: configuration.isPressed))
    }

    private func opacity(isPressed: Bool) -> CGFloat {
        guard isEnabled else { return tokens.popoverActionDisabledAlpha }
        return isPressed ? 0.82 : 1
    }
}

private struct SidebarSpaceCreationCardBackground: ViewModifier {
    let cornerRadius: CGFloat
    let tokens: ChromeThemeTokens

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tokens.fieldBackground.opacity(0.78))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(tokens.separator.opacity(0.74), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
