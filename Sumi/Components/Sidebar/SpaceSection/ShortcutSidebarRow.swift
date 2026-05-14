//
//  ShortcutSidebarRow.swift
//  Sumi
//

import SwiftUI

struct ShortcutSidebarRow: View {
    @ObservedObject var pin: ShortcutPin
    var liveTab: Tab? = nil
    var accessibilityID: String? = nil
    var contextMenuEntries: (@escaping () -> Void) -> [SidebarContextMenuEntry] = { _ in [] }
    let action: () -> Void
    var dragSourceZone: DropZoneID? = nil
    var dragHasTrailingActionExclusion: Bool = true
    var dragIsEnabled: Bool = true
    var debugRenderMode: String = "unspecified"
    var onLauncherIconSelected: ((String) -> Void)? = nil
    let onResetToLaunchURL: (() -> Void)?
    let onUnload: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Group {
            if let liveTab {
                ShortcutSidebarLiveRowContent(
                    pin: pin,
                    liveTab: liveTab,
                    accessibilityID: accessibilityID,
                    contextMenuEntries: contextMenuEntries,
                    action: action,
                    dragSourceZone: dragSourceZone,
                    dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
                    dragIsEnabled: dragIsEnabled,
                    debugRenderMode: debugRenderMode,
                    onLauncherIconSelected: onLauncherIconSelected,
                    onResetToLaunchURL: onResetToLaunchURL,
                    onUnload: onUnload,
                    onRemove: onRemove
                )
            } else {
                ShortcutSidebarStoredRowContent(
                    pin: pin,
                    accessibilityID: accessibilityID,
                    contextMenuEntries: contextMenuEntries,
                    action: action,
                    dragSourceZone: dragSourceZone,
                    dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
                    dragIsEnabled: dragIsEnabled,
                    debugRenderMode: debugRenderMode,
                    onLauncherIconSelected: onLauncherIconSelected,
                    onResetToLaunchURL: onResetToLaunchURL,
                    onUnload: onUnload,
                    onRemove: onRemove
                )
            }
        }
    }
}

private struct ShortcutSidebarLiveRowContent: View {
    @ObservedObject var pin: ShortcutPin
    @ObservedObject var liveTab: Tab
    var accessibilityID: String?
    var contextMenuEntries: (@escaping () -> Void) -> [SidebarContextMenuEntry]
    let action: () -> Void
    var dragSourceZone: DropZoneID?
    var dragHasTrailingActionExclusion: Bool
    var dragIsEnabled: Bool
    var debugRenderMode: String
    var onLauncherIconSelected: ((String) -> Void)?
    let onResetToLaunchURL: (() -> Void)?
    let onUnload: () -> Void
    let onRemove: () -> Void

    @EnvironmentObject private var browserManager: BrowserManager
    @EnvironmentObject private var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        let splitSide = splitManager.side(for: liveTab.id, in: windowState.id)

        ShortcutSidebarRowChrome(
            pin: pin,
            liveTab: liveTab,
            resolvedTitle: pin.resolvedDisplayTitle(liveTab: liveTab),
            runtimeAffordance: browserManager.tabManager.shortcutRuntimeAffordanceState(
                for: pin,
                in: windowState
            ),
            showsSplitBadge: splitSide != nil,
            splitBadgeIsSelected: splitManager.activeSide(for: windowState.id) == splitSide,
            accessibilityID: accessibilityID,
            contextMenuEntries: contextMenuEntries,
            action: action,
            dragSourceZone: dragSourceZone,
            dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
            dragIsEnabled: dragIsEnabled,
            debugRenderMode: debugRenderMode,
            onLauncherIconSelected: onLauncherIconSelected,
            onResetToLaunchURL: onResetToLaunchURL,
            onUnload: onUnload,
            onRemove: onRemove
        )
    }
}

private struct ShortcutSidebarStoredRowContent: View {
    @ObservedObject var pin: ShortcutPin
    var accessibilityID: String?
    var contextMenuEntries: (@escaping () -> Void) -> [SidebarContextMenuEntry]
    let action: () -> Void
    var dragSourceZone: DropZoneID?
    var dragHasTrailingActionExclusion: Bool
    var dragIsEnabled: Bool
    var debugRenderMode: String
    var onLauncherIconSelected: ((String) -> Void)?
    let onResetToLaunchURL: (() -> Void)?
    let onUnload: () -> Void
    let onRemove: () -> Void

    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        ShortcutSidebarRowChrome(
            pin: pin,
            liveTab: nil,
            resolvedTitle: pin.preferredDisplayTitle,
            runtimeAffordance: browserManager.tabManager.shortcutRuntimeAffordanceState(
                for: pin,
                in: windowState
            ),
            showsSplitBadge: false,
            splitBadgeIsSelected: false,
            accessibilityID: accessibilityID,
            contextMenuEntries: contextMenuEntries,
            action: action,
            dragSourceZone: dragSourceZone,
            dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
            dragIsEnabled: dragIsEnabled,
            debugRenderMode: debugRenderMode,
            onLauncherIconSelected: onLauncherIconSelected,
            onResetToLaunchURL: onResetToLaunchURL,
            onUnload: onUnload,
            onRemove: onRemove
        )
    }
}

private struct ShortcutSidebarRowChrome: View {
    let pin: ShortcutPin
    let liveTab: Tab?
    let resolvedTitle: String
    let runtimeAffordance: SumiLauncherRuntimeAffordanceState
    let showsSplitBadge: Bool
    let splitBadgeIsSelected: Bool
    var accessibilityID: String? = nil
    var contextMenuEntries: (@escaping () -> Void) -> [SidebarContextMenuEntry] = { _ in [] }
    let action: () -> Void
    var dragSourceZone: DropZoneID? = nil
    var dragHasTrailingActionExclusion: Bool = true
    var dragIsEnabled: Bool = true
    var debugRenderMode: String = "unspecified"
    var onLauncherIconSelected: ((String) -> Void)? = nil
    let onResetToLaunchURL: (() -> Void)?
    let onUnload: () -> Void
    let onRemove: () -> Void

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var markerInstanceID = UUID()
    @State private var isRowHovered = false
    @State private var isActionHovered = false
    @State private var isResetHovered = false
    @State private var faviconCacheRefreshID = UUID()
    @StateObject private var emojiManager = EmojiPickerManager()

    var body: some View {
        let _ = faviconCacheRefreshID
        let cornerRadius = sumiSettings.resolvedCornerRadius(12)
        HStack(spacing: 0) {
            if runtimeAffordance.usesResetLeadingAction, let onResetToLaunchURL {
                Button(action: onResetToLaunchURL) {
                    resetLeadingButtonContent
                }
                .buttonStyle(
                    SidebarZenActionButtonStyle(
                        isEnabled: dragIsEnabled && !freezesHoverState
                    )
                )
                .sidebarDDGHover($isResetHovered, isEnabled: dragIsEnabled)
                .accessibilityIdentifier(resetActionAccessibilityID ?? "shortcut-sidebar-reset")
                .accessibilityLabel("Back to pinned URL")
                .help("Back to pinned URL")
                .sidebarAppKitPrimaryAction(
                    isInteractionEnabled: dragIsEnabled,
                    action: onResetToLaunchURL
                )
            }

            ZStack {
                HStack(spacing: 0) {
                    if !runtimeAffordance.usesResetLeadingAction {
                        rowIcon
                            .padding(.leading, SidebarRowLayout.leadingInset)
                            .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)
                    }

                    if let liveTab {
                        LauncherAudioButton(
                            tab: liveTab,
                            foregroundColor: textColor,
                            mutedForegroundColor: tokens.secondaryText,
                            hoverBackground: actionBackground,
                            accessibilityID: launcherAudioAccessibilityID,
                            isAppKitInteractionEnabled: dragIsEnabled
                        )
                        .padding(.trailing, SidebarRowLayout.iconTrailingSpacing)
                    }

                    titleStack
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, runtimeAffordance.usesResetLeadingAction ? SidebarRowLayout.changedLauncherTitleLeading : 0)
                .padding(.trailing, SidebarRowLayout.trailingInset)
                .frame(height: SidebarRowLayout.rowHeight)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .background(EmojiPickerAnchor(manager: emojiManager))
        .overlay(alignment: .leading) {
            rowActivationOverlay
        }
        .overlay(alignment: .trailing) {
            trailingActionButton
                .padding(.trailing, SidebarRowLayout.trailingInset)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if showsSplitBadge {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(splitBadgeIsSelected ? Color.accentColor : tokens.secondaryText)
                    .padding(4)
                    .background(tokens.fieldBackground, in: Circle())
                    .padding(.trailing, 8)
                    .padding(.bottom, 6)
            }
        }
        // Expose the row container itself so the launcher keeps the same source identity
        // when runtime drift replaces the leading favicon with the reset control.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityID ?? "shortcut-sidebar-row")
        .accessibilityValue(runtimeAffordance.isSelected ? "selected" : "not selected")
        .sidebarDDGHover($isRowHovered, isEnabled: dragIsEnabled)
        .sidebarZenPressEffect(sourceID: rowSourceID, isEnabled: dragIsEnabled)
        .onAppear {
            recordShortcutSidebarMarker("shortcutRowAppear")
        }
        .onDisappear {
            recordShortcutSidebarMarker("shortcutRowDisappear")
        }
        .onChange(of: liveTab?.id) { _, _ in
            recordShortcutSidebarMarker("shortcutRowLiveTabChange")
        }
        .onChange(of: runtimeAffordance.usesResetLeadingAction) { _, _ in
            recordShortcutSidebarMarker("shortcutRowResetAffordanceChange")
        }
        .onChange(of: runtimeAffordance.isSelected) { _, _ in
            recordShortcutSidebarMarker("shortcutRowSelectionChange")
        }
        .onReceive(NotificationCenter.default.publisher(for: .faviconCacheUpdated)) { _ in
            faviconCacheRefreshID = UUID()
        }
        .sidebarAppKitContextMenu(
            isInteractionEnabled: dragIsEnabled,
            dragSource: dragSourceConfiguration,
            primaryAction: action,
            sourceID: rowSourceID,
            entries: { contextMenuEntries(toggleLauncherIconPicker) }
        )
        .onChange(of: emojiManager.committedEmoji) { _, newValue in
            guard !newValue.isEmpty else { return }
            let normalized = SumiPersistentGlyph.normalizedLauncherIconValue(newValue)
            guard let onLauncherIconSelected else { return }
            DispatchQueue.main.async {
                onLauncherIconSelected(normalized)
            }
        }
        .shadow(
            color: runtimeAffordance.isSelected ? tokens.sidebarSelectionShadow : .clear,
            radius: runtimeAffordance.isSelected ? 2 : 0,
            y: runtimeAffordance.isSelected ? 1 : 0
        )
    }

    private func recordShortcutSidebarMarker(_ name: String) {
        let sourceID = accessibilityID ?? "shortcut-sidebar-row"
        let mode = liveTab == nil ? "stored" : "live"
        SidebarUITestDragMarker.recordEvent(
            name,
            dragItemID: pin.id,
            ownerDescription: "ShortcutSidebarRowChrome{instance=\(markerInstanceID.uuidString)}",
            sourceID: sourceID,
            viewDescription: "swiftui:\(markerInstanceID.uuidString)",
            details: "source=\(sourceID) pin=\(pin.id.uuidString) liveTab=\(liveTab?.id.uuidString ?? "nil") mode=\(mode) renderMode=\(debugRenderMode) dragIsEnabled=\(dragIsEnabled) resetLeading=\(runtimeAffordance.usesResetLeadingAction) selected=\(runtimeAffordance.isSelected) window=\(windowState.id.uuidString)"
        )
    }

    private var rowIcon: some View {
        Group {
            if let launcherIconAsset = pin.iconAsset {
                launcherGlyph(for: launcherIconAsset)
            } else if let systemName = chromeTemplateSystemImageName {
                Image(systemName: systemName)
                    .font(.system(size: SidebarRowLayout.faviconSize * 0.78, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(textColor)
            } else {
                displayFavicon
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .saturation(runtimeAffordance.shouldDesaturateIcon ? 0.0 : 1.0)
        .opacity(runtimeAffordance.shouldDesaturateIcon ? 0.8 : 1.0)
    }

    private var displayFavicon: Image {
        liveTab?.favicon ?? pin.storedFavicon
    }

    private var chromeTemplateSystemImageName: String? {
        if let liveTab {
            if SumiSurface.isSettingsSurfaceURL(liveTab.url) {
                return SumiSurface.settingsTabFaviconSystemImageName
            }
            if liveTab.faviconIsTemplateGlobePlaceholder {
                return SumiPersistentGlyph.launcherSystemImageFallback
            }
            return nil
        }
        return pin.storedChromeTemplateSystemImageName
    }

    @ViewBuilder
    private func launcherGlyph(for iconAsset: String) -> some View {
        if SumiPersistentGlyph.presentsAsEmoji(iconAsset) {
            Text(iconAsset)
                .font(.system(size: SidebarRowLayout.faviconSize * 0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .multilineTextAlignment(.center)
                .frame(
                    width: SidebarRowLayout.faviconSize,
                    height: SidebarRowLayout.faviconSize,
                    alignment: .center
                )
        } else {
            Image(systemName: SumiPersistentGlyph.resolvedLauncherSystemImageName(iconAsset))
                .font(.system(size: SidebarRowLayout.faviconSize * 0.78, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(textColor)
        }
    }

    private func toggleLauncherIconPicker() {
        guard onLauncherIconSelected != nil else { return }
        emojiManager.selectedEmoji = pin.iconAsset.flatMap { iconAsset in
            SumiPersistentGlyph.presentsAsEmoji(iconAsset) ? iconAsset : nil
        } ?? ""
        emojiManager.toggle(
            source: windowState.resolveSidebarPresentationSource(),
            settings: sumiSettings,
            themeContext: themeContext
        ) { picked in
            let normalized = SumiPersistentGlyph.normalizedLauncherIconValue(picked)
            onLauncherIconSelected?(normalized)
        }
    }

    private var resetLeadingButtonContent: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                rowIcon
                    .padding(.leading, SidebarRowLayout.changedLauncherResetIconLeading)
                Spacer(minLength: 0)
            }
            .frame(
                width: SidebarRowLayout.changedLauncherResetWidth,
                height: SidebarRowLayout.changedLauncherResetHeight,
                alignment: .leading
            )
            .background(displayIsResetHovering ? actionBackground : Color.clear)
            .clipShape(resetHighlightShape)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tokens.secondaryText.opacity(displayIsResetHovering ? 0 : 0.3))
                .frame(
                    width: SidebarRowLayout.changedLauncherSeparatorWidth,
                    height: SidebarRowLayout.changedLauncherSeparatorHeight
                )
                .rotationEffect(.degrees(15))
        }
        .frame(
            width: SidebarRowLayout.changedLauncherResetWidth,
            height: SidebarRowLayout.changedLauncherResetHeight,
            alignment: .leading
        )
        .padding(.trailing, SidebarRowLayout.changedLauncherResetTrailingGap)
    }

    private var resetHighlightShape: some Shape {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 8,
                bottomLeading: 8,
                bottomTrailing: 0,
                topTrailing: 0
            ),
            style: .continuous
        )
    }

    @ViewBuilder
    private var titleStack: some View {
        titleLabel
            .frame(height: SidebarRowLayout.titleHeight, alignment: .center)
    }

    @ViewBuilder
    private var titleLabel: some View {
        SumiTabTitleLabel(
            title: resolvedTitle,
            font: .systemFont(ofSize: 13, weight: .medium),
            textColor: textColor,
            trailingFadePadding: SidebarHoverChrome.trailingFadePadding(
                showsTrailingAction: showsActionButton
            ),
            animated: liveTab != nil,
            isLoading: liveTab?.isLoading ?? false
        )
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var trailingActionButton: some View {
        Button(action: performActionButton) {
            Image(systemName: actionIconName)
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(textColor)
                .frame(
                    width: SidebarRowLayout.trailingActionSize,
                    height: SidebarRowLayout.trailingActionSize
                )
                .background(displayIsActionHovering ? actionBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(
            SidebarZenActionButtonStyle(
                isEnabled: showsActionButton && !freezesHoverState
            )
        )
        .opacity(showsActionButton ? 1 : 0)
        .sidebarZenActionOpacity(showsActionButton)
        .allowsHitTesting(showsActionButton && !freezesHoverState)
        .accessibilityHidden(!showsActionButton)
        .sidebarDDGHover($isActionHovered, isEnabled: showsActionButton && dragIsEnabled)
        .accessibilityIdentifier(trailingActionAccessibilityID ?? "shortcut-sidebar-action")
        .sidebarAppKitPrimaryAction(
            isEnabled: showsActionButton && !freezesHoverState,
            isInteractionEnabled: dragIsEnabled,
            action: performActionButton
        )
    }

    private var backgroundColor: Color {
        if runtimeAffordance.isSelected {
            return tokens.sidebarRowActive
        } else if displayIsHovering {
            return tokens.sidebarRowHover
        }
        return .clear
    }

    private var rowSourceID: String {
        accessibilityID ?? "shortcut-sidebar-row"
    }

    private var actionBackground: Color {
        runtimeAffordance.isSelected
            ? tokens.fieldBackgroundHover
            : tokens.fieldBackground
    }

    private var actionIconName: String {
        runtimeAffordance.isOpenLive ? "minus" : "xmark"
    }

    private var trailingActionAccessibilityID: String? {
        actionAccessibilityID(suffix: "action")
    }

    private var resetActionAccessibilityID: String? {
        actionAccessibilityID(suffix: "reset")
    }

    private var launcherAudioAccessibilityID: String? {
        actionAccessibilityID(suffix: "audio")
    }

    private var showsActionButton: Bool {
        SidebarHoverChrome.showsTrailingAction(
            isHovered: displayIsHovering,
            isSelected: runtimeAffordance.isSelected
        )
    }

    private var freezesHoverState: Bool {
        windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var displayIsHovering: Bool {
        SidebarHoverChrome.displayHover(isRowHovered, freezesHoverState: freezesHoverState)
    }

    private var displayIsActionHovering: Bool {
        SidebarHoverChrome.displayHover(isActionHovered, freezesHoverState: freezesHoverState)
    }

    private var displayIsResetHovering: Bool {
        SidebarHoverChrome.displayHover(isResetHovered, freezesHoverState: freezesHoverState)
    }

    private var dragSourceConfiguration: SidebarDragSourceConfiguration? {
        makeShortcutSidebarDragSourceConfiguration(
            pin: pin,
            resolvedTitle: resolvedTitle,
            runtimeAffordance: runtimeAffordance,
            dragSourceZone: dragSourceZone,
            dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
            hasLiveAudioExclusion: liveTab?.audioState.showsTabAudioButton == true,
            previewIcon: displayFavicon,
            action: action,
            dragIsEnabled: dragIsEnabled
        )
    }

    private var textColor: Color {
        tokens.primaryText
    }

    private var audioButtonHitFrame: CGRect? {
        guard liveTab?.audioState.showsTabAudioButton == true else { return nil }

        return ShortcutSidebarAudioHitArea.frameInRow(
            usesResetLeadingAction: runtimeAffordance.usesResetLeadingAction
        )
    }

    @ViewBuilder
    private var rowActivationOverlay: some View {
        GeometryReader { proxy in
            let resetExclusionWidth = runtimeAffordance.usesResetLeadingAction
                ? ShortcutSidebarAudioHitArea.contentStartX(usesResetLeadingAction: true)
                : 0
            let trailingExclusionWidth: CGFloat = dragHasTrailingActionExclusion ? 40 : 0
            let trailingLimit = max(proxy.size.width - trailingExclusionWidth, resetExclusionWidth)

            ZStack(alignment: .leading) {
                if let audioButtonHitFrame {
                    activationHitRegion(
                        x: resetExclusionWidth,
                        width: max(audioButtonHitFrame.minX - resetExclusionWidth, 0)
                    )

                    activationHitRegion(
                        x: audioButtonHitFrame.maxX,
                        width: max(trailingLimit - audioButtonHitFrame.maxX, 0)
                    )
                } else {
                    activationHitRegion(
                        x: resetExclusionWidth,
                        width: max(trailingLimit - resetExclusionWidth, 0)
                    )
                }
            }
        }
        .frame(height: SidebarRowLayout.rowHeight)
    }

    private func activationHitRegion(x: CGFloat, width: CGFloat) -> some View {
        Color.clear
            .frame(width: max(width, 0), height: SidebarRowLayout.rowHeight)
            .contentShape(Rectangle())
            .offset(x: x)
            .onTapGesture(perform: action)
    }

    private func performActionButton() {
        if runtimeAffordance.isOpenLive {
            onUnload()
            return
        }
        onRemove()
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private func actionAccessibilityID(suffix: String) -> String? {
        guard let accessibilityID else { return nil }
        if let id = accessibilityID.replacingPrefix("space-pinned-shortcut-", with: "space-pinned-shortcut-\(suffix)-") {
            return id
        }
        if let id = accessibilityID.replacingPrefix("folder-shortcut-", with: "folder-shortcut-\(suffix)-") {
            return id
        }
        return "\(accessibilityID)-\(suffix)"
    }
}

@MainActor
func makeShortcutSidebarDragSourceConfiguration(
    pin: ShortcutPin,
    resolvedTitle: String,
    runtimeAffordance: SumiLauncherRuntimeAffordanceState,
    dragSourceZone: DropZoneID?,
    dragHasTrailingActionExclusion: Bool,
    hasLiveAudioExclusion: Bool = false,
    previewIcon: Image,
    action: (() -> Void)? = nil,
    dragIsEnabled: Bool = true
) -> SidebarDragSourceConfiguration? {
    guard let dragSourceZone else { return nil }

    return SidebarDragSourceConfiguration(
        item: SumiDragItem(
            tabId: pin.id,
            title: resolvedTitle,
            urlString: pin.launchURL.absoluteString
        ),
        sourceZone: dragSourceZone,
        previewKind: .row,
        previewIcon: previewIcon,
        exclusionZones: makeShortcutSidebarDragExclusionZones(
            runtimeAffordance: runtimeAffordance,
            dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
            hasLiveAudioExclusion: hasLiveAudioExclusion
        ),
        onActivate: action,
        isEnabled: dragIsEnabled
    )
}

@MainActor
func makeShortcutSidebarDragExclusionZones(
    runtimeAffordance: SumiLauncherRuntimeAffordanceState,
    dragHasTrailingActionExclusion: Bool,
    hasLiveAudioExclusion: Bool = false
) -> [SidebarDragSourceExclusionZone] {
    var exclusions: [SidebarDragSourceExclusionZone] = []
    if runtimeAffordance.usesResetLeadingAction {
        exclusions.append(.leadingStrip(SidebarRowLayout.changedLauncherResetWidth + 12))
    }
    if hasLiveAudioExclusion {
        exclusions.append(
            .fixedRect(
                ShortcutSidebarAudioHitArea.frameInRow(
                    usesResetLeadingAction: runtimeAffordance.usesResetLeadingAction
                )
            )
        )
    }
    if dragHasTrailingActionExclusion {
        exclusions.append(.trailingStrip(40))
    }
    return exclusions
}

private enum ShortcutSidebarAudioHitArea {
    static let size: CGFloat = 22

    static func contentStartX(usesResetLeadingAction: Bool) -> CGFloat {
        guard usesResetLeadingAction else { return 0 }

        return SidebarRowLayout.changedLauncherResetWidth
            + SidebarRowLayout.changedLauncherResetTrailingGap
    }

    static func frameInRow(usesResetLeadingAction: Bool) -> CGRect {
        let x: CGFloat
        if usesResetLeadingAction {
            x = contentStartX(usesResetLeadingAction: true)
                + SidebarRowLayout.changedLauncherTitleLeading
        } else {
            x = SidebarRowLayout.leadingInset
                + SidebarRowLayout.faviconSize
                + SidebarRowLayout.iconTrailingSpacing
        }

        return CGRect(
            x: x,
            y: (SidebarRowLayout.rowHeight - size) / 2,
            width: size,
            height: size
        )
    }
}

private struct LauncherAudioButton: View {
    @ObservedObject var tab: Tab
    let foregroundColor: Color
    let mutedForegroundColor: Color
    let hoverBackground: Color
    let accessibilityID: String?
    let isAppKitInteractionEnabled: Bool
    @Environment(BrowserWindowState.self) private var windowState
    @State private var isHovering = false

    var body: some View {
        Group {
            if tab.audioState.showsTabAudioButton {
                Button {
                    tab.toggleMute()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(displayIsHovering ? hoverBackground : Color.clear)
                            .frame(width: 22, height: 22)

                        Image(systemName: tab.audioState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(tab.audioState.isMuted ? mutedForegroundColor : foregroundColor)
                            .id(tab.audioState.isMuted)
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.82).combined(with: .opacity),
                                    removal: .scale(scale: 1.08).combined(with: .opacity)
                                )
                            )
                    }
                    .frame(width: 22, height: 22)
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(
                    SidebarZenActionButtonStyle(
                        isEnabled: isAppKitInteractionEnabled
                            && !windowState.sidebarInteractionState.freezesSidebarHoverState
                    )
                )
                .frame(width: 22, height: 22)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .sidebarDDGHover($isHovering, isEnabled: isAppKitInteractionEnabled)
                .accessibilityIdentifier(accessibilityID ?? "shortcut-sidebar-audio")
                .sidebarAppKitPrimaryAction(
                    isEnabled: !windowState.sidebarInteractionState.freezesSidebarHoverState,
                    isInteractionEnabled: isAppKitInteractionEnabled,
                    action: tab.toggleMute
                )
                .help(tab.audioState.isMuted ? "Unmute Audio" : "Mute Audio")
                .animation(.easeInOut(duration: 0.1), value: tab.audioState.isMuted)
            }
        }
    }

    private var displayIsHovering: Bool {
        SidebarHoverChrome.displayHover(
            isHovering,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }
}

private extension String {
    func replacingPrefix(_ prefix: String, with replacement: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return replacement + String(dropFirst(prefix.count))
    }
}
