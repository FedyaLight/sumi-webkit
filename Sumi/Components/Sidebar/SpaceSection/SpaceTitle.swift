import SwiftUI

struct SpaceTitleActions {
    let canDeleteSpace: Bool
    let renameSpace: (String) -> Void
    let updateSpaceIcon: (String) -> Void
    let persistCommittedEmoji: (String) -> Void
    let editSpace: () -> Void
    let changeTheme: () -> Void
    let deleteSpace: () -> Void
    let clearSpace: () -> Void
}

enum SpaceTitleRowLayout {
    static let iconFontScale: CGFloat = 0.78
    static let titleFontSize: CGFloat = 14
    static let titleFontWeight: Font.Weight = .semibold
    static let trailingControlSize: CGFloat = 28
    static let verticalPadding: CGFloat = 4
    static let defaultCornerRadius: CGFloat = 12

    static var iconFontSize: CGFloat {
        SidebarRowLayout.faviconSize * iconFontScale
    }

    static var minimumHeight: CGFloat {
        trailingControlSize + verticalPadding * 2
    }
}

enum SpaceTitleLeadingPresentation: Equatable {
    case icon
    case chevron(isExpanded: Bool)

    static func resolve(
        hasPinnedContent: Bool,
        isCollapsed: Bool,
        isHovered: Bool
    ) -> Self {
        guard hasPinnedContent, isCollapsed || isHovered else { return .icon }
        return .chevron(isExpanded: !isCollapsed)
    }
}

enum SpaceTitleCollapseMotion {
    static let presentationDuration: TimeInterval = 0.1
    static let rotationOvershootDuration: TimeInterval = 0.11
    static let rotationSettleDelay: TimeInterval = 0.055
    static let rotationSettleDuration: TimeInterval = 0.1

    static func animation(
        reduceMotion: Bool,
        shouldReduceChromeMotion: Bool
    ) -> Animation? {
        guard !reduceMotion, !shouldReduceChromeMotion else { return nil }
        return .easeInOut(duration: presentationDuration)
    }

    static var rotationOvershootAnimation: Animation {
        .timingCurve(
            0.2,
            0.0,
            0.0,
            1.0,
            duration: rotationOvershootDuration
        )
    }

    static var rotationSettleAnimation: Animation {
        .easeInOut(duration: rotationSettleDuration)
            .delay(rotationSettleDelay)
    }
}

struct SpaceTitleChevronRotationPlan: Equatable {
    let overshootDegrees: Double
    let destinationDegrees: Double

    static func resolve(isExpanded: Bool) -> Self {
        let destinationDegrees = isExpanded ? 90.0 : 0.0
        return Self(
            overshootDegrees: destinationDegrees + (isExpanded ? 20.0 : -20.0),
            destinationDegrees: destinationDegrees
        )
    }
}

private struct SpaceTitleLeadingGlyphView: View {
    let iconValue: String
    let isExpanded: Bool
    let showsChevron: Bool
    let textColor: Color
    let presentationAnimation: Animation?

    @State private var displayedDegrees: Double
    @State private var isRotationActive = false
    @State private var rotationGeneration = 0

    init(
        iconValue: String,
        isExpanded: Bool,
        showsChevron: Bool,
        textColor: Color,
        presentationAnimation: Animation?
    ) {
        self.iconValue = iconValue
        self.isExpanded = isExpanded
        self.showsChevron = showsChevron
        self.textColor = textColor
        self.presentationAnimation = presentationAnimation
        _displayedDegrees = State(
            initialValue: SpaceTitleChevronRotationPlan
                .resolve(isExpanded: isExpanded)
                .destinationDegrees
        )
    }

    var body: some View {
        ZStack {
            SpaceTitleIconView(
                iconValue: iconValue,
                textColor: textColor
            )
            .opacity(displaysChevron ? 0 : 1)
            .animation(visibilityAnimation, value: displaysChevron)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(textColor)
                .rotationEffect(.degrees(displayedDegrees))
                .opacity(displaysChevron ? 1 : 0)
                .animation(visibilityAnimation, value: displaysChevron)
                .accessibilityHidden(true)
        }
        .onChange(of: isExpanded) { _, isExpanded in
            animateRotation(isExpanded: isExpanded)
        }
        .onChange(of: animatesRotation) { _, animatesRotation in
            guard !animatesRotation else { return }
            settleImmediately(isExpanded: isExpanded)
        }
    }

    private var animatesRotation: Bool {
        presentationAnimation != nil
    }

    private var displaysChevron: Bool {
        showsChevron || isRotationActive
    }

    private var visibilityAnimation: Animation? {
        isRotationActive ? nil : presentationAnimation
    }

    private func animateRotation(isExpanded: Bool) {
        let plan = SpaceTitleChevronRotationPlan.resolve(isExpanded: isExpanded)
        guard animatesRotation else {
            settleImmediately(isExpanded: isExpanded)
            return
        }

        rotationGeneration += 1
        let generation = rotationGeneration
        isRotationActive = true
        withAnimation(
            SpaceTitleCollapseMotion.rotationOvershootAnimation,
            completionCriteria: .logicallyComplete
        ) {
            displayedDegrees = plan.overshootDegrees
        } completion: {
            guard rotationGeneration == generation else { return }
            withAnimation(
                SpaceTitleCollapseMotion.rotationSettleAnimation,
                completionCriteria: .logicallyComplete
            ) {
                displayedDegrees = plan.destinationDegrees
            } completion: {
                guard rotationGeneration == generation else { return }
                isRotationActive = false
            }
        }
    }

    private func settleImmediately(isExpanded: Bool) {
        rotationGeneration += 1
        isRotationActive = false
        let destinationDegrees = SpaceTitleChevronRotationPlan
            .resolve(isExpanded: isExpanded)
            .destinationDegrees
        withTransaction(Transaction(animation: nil)) {
            displayedDegrees = destinationDegrees
        }
    }
}

struct SpaceIconGlyphView: View {
    let iconValue: String
    let textColor: Color
    let defaultDotSize: CGFloat
    let emojiFont: Font
    let systemFont: Font
    var desaturatesEmoji = false
    var hidesAccessibility = false

    var body: some View {
        Group {
            switch SumiPersistentGlyph.resolvedSpaceIconPresentation(iconValue) {
            case .defaultDot:
                Circle()
                    .fill(textColor)
                    .frame(width: defaultDotSize, height: defaultDotSize)
            case .emoji(let glyph):
                Text(glyph)
                    .font(emojiFont)
                    .conditionally(if: desaturatesEmoji) { view in
                        view.colorMultiply(.gray).blendMode(.luminosity)
                    }
            case .systemImage(let systemName):
                Image(systemName: systemName)
                    .font(systemFont)
                    .foregroundStyle(textColor)
            }
        }
        .accessibilityHidden(hidesAccessibility)
    }
}

struct SpaceTitleIconView: View {
    let iconValue: String
    let textColor: Color
    var hidesAccessibility = false

    var body: some View {
        SpaceIconGlyphView(
            iconValue: iconValue,
            textColor: textColor,
            defaultDotSize: SumiPersistentGlyph.spaceDefaultDotDiameter,
            emojiFont: .system(size: SpaceTitleRowLayout.iconFontSize),
            systemFont: .system(size: SpaceTitleRowLayout.iconFontSize, weight: .medium),
            hidesAccessibility: hidesAccessibility
        )
    }
}

struct SpaceTitleTextLabel: View {
    let title: String
    let textColor: Color

    var body: some View {
        SidebarRowTitleLabel(
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
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    let space: Space
    let actions: SpaceTitleActions
    let hasPinnedContent: Bool
    let isPinnedContentCollapsed: Bool
    let onTogglePinnedContent: () -> Void
    var isAppKitInteractionEnabled: Bool = true

    @State private var isRenaming: Bool = false
    @State private var draftName: String = ""
    @State private var isRowHovered = false
    @FocusState private var nameFieldFocused: Bool

    @StateObject private var emojiManager = EmojiPickerManager()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .conditionally(if: hasPinnedContent) { view in
            view
                .accessibilityValue(
                    isPinnedContentCollapsed ? "collapsed" : "expanded"
                )
                .accessibilityAction {
                    onTogglePinnedContent()
                }
        }
        .sidebarHover($isRowHovered, isEnabled: isAppKitInteractionEnabled)
        .onAppear {
            emojiManager.sidebarRecoveryCoordinator =
                windowState.sidebarContextMenuController.sidebarRecoveryCoordinator
        }
        .onChange(of: nameFieldFocused) { _, focused in
            // When losing focus during rename, commit
            if isRenaming && !focused {
                commitRename()
            }
        }
        .sidebarAppKitContextMenu(
            isInteractionEnabled: isAppKitInteractionEnabled,
            primaryActionExclusionZones: [.trailingStrip(40)],
            releaseAction: hasPinnedContent ? onTogglePinnedContent : nil,
            sourceID: hasPinnedContent ? "space-title-toggle-\(space.id.uuidString)" : nil,
            entries: {
                spaceContextMenuEntries()
            }
        )
    }

    @ViewBuilder
    private var iconView: some View {
        SpaceTitleLeadingGlyphView(
            iconValue: space.icon,
            isExpanded: chevronIsExpanded,
            showsChevron: showsCollapseChevron,
            textColor: textColor,
            presentationAnimation: collapseChevronAnimation
        )
        .background(EmojiPickerAnchor(manager: emojiManager))
        .onTapGesture(count: 2) {
            if !hasPinnedContent {
                toggleSpaceIconPicker()
            }
        }
        .modifier(
            SpaceTitleEmojiPickModifier(
                emojiManager: emojiManager,
                space: space,
                persistCommittedEmoji: actions.persistCommittedEmoji
            )
        )
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
                    if !hasPinnedContent {
                        startRenaming()
                    }
                }
        }
    }

    private var menuButton: some View {
        Button(action: {}) {
            Label("Configure Space", systemImage: "ellipsis")
                .font(.body.weight(.semibold))
                .labelStyle(.iconOnly)
        }
        .buttonStyle(NavButtonStyle(size: .small, hoverTracking: .sidebarSession))
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
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    private var titleCornerRadius: CGFloat {
        sumiSettings.resolvedCornerRadius(SpaceTitleRowLayout.defaultCornerRadius)
    }

    private var displayIsHovering: Bool {
        isRowHovered
    }

    private var leadingPresentation: SpaceTitleLeadingPresentation {
        SpaceTitleLeadingPresentation.resolve(
            hasPinnedContent: hasPinnedContent,
            isCollapsed: isPinnedContentCollapsed,
            isHovered: displayIsHovering
        )
    }

    private var showsCollapseChevron: Bool {
        if case .chevron = leadingPresentation { return true }
        return false
    }

    private var chevronIsExpanded: Bool {
        if case .chevron(let isExpanded) = leadingPresentation {
            return isExpanded
        }
        return !isPinnedContentCollapsed
    }

    private var collapseChevronAnimation: Animation? {
        SpaceTitleCollapseMotion.animation(
            reduceMotion: reduceMotion,
            shouldReduceChromeMotion: sumiSettings.shouldReduceChromeMotion
        )
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
        let clearSpaceAction: (() -> Void)?
        if canDeleteSpace {
            deleteSpaceAction = { showDeleteConfirmation() }
            clearSpaceAction = nil
        } else {
            deleteSpaceAction = nil
            clearSpaceAction = { showClearConfirmation() }
        }

        return makeSpaceContextMenuEntries(
            actions: .init(
                edit: {
                    actions.editSpace()
                },
                changeTheme: {
                    actions.changeTheme()
                },
                deleteSpace: deleteSpaceAction,
                clearSpace: clearSpaceAction
            )
        )
    }

    private func showDeleteConfirmation() {
        actions.deleteSpace()
    }

    private func showClearConfirmation() {
        actions.clearSpace()
    }

    private func toggleSpaceIconPicker() {
        emojiManager.selectedEmoji = SumiPersistentGlyph.presentsAsEmoji(space.icon) ? space.icon : ""
        emojiManager.toggle(
            source: windowState.resolveSidebarPresentationSource(in: windowRegistry),
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
