//
//  ShortcutSidebarRow.swift
//  Sumi
//

import SwiftUI

struct ShortcutSidebarRow: View {
    @ObservedObject var pin: ShortcutPin
    var liveTab: Tab?
    var accessibilityID: String?
    var contextMenuEntries: () -> [SidebarContextMenuEntry] = { [] }
    let action: () -> Void
    var dragSourceZone: DropZoneID?
    var dragHasTrailingActionExclusion: Bool = true
    var dragIsEnabled: Bool = true
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
    var contextMenuEntries: () -> [SidebarContextMenuEntry]
    let action: () -> Void
    var dragSourceZone: DropZoneID?
    var dragHasTrailingActionExclusion: Bool
    var dragIsEnabled: Bool
    let onResetToLaunchURL: (() -> Void)?
    let onUnload: () -> Void
    let onRemove: () -> Void

    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        ShortcutSidebarRowChrome(
            pin: pin,
            liveTab: liveTab,
            faviconPartition: browserManager.tabManager.resolvedFaviconPartition(
                for: pin,
                currentSpaceId: windowState.currentSpaceId
            ),
            resolvedTitle: pin.resolvedDisplayTitle(liveTab: liveTab),
            runtimeAffordance: browserManager.tabManager.shortcutRuntimeAffordanceState(
                for: pin,
                in: windowState
            ),
            accessibilityID: accessibilityID,
            contextMenuEntries: contextMenuEntries,
            action: action,
            dragSourceZone: dragSourceZone,
            dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
            dragIsEnabled: dragIsEnabled,
            onResetToLaunchURL: onResetToLaunchURL,
            onUnload: onUnload,
            onRemove: onRemove
        )
    }
}

private struct ShortcutSidebarStoredRowContent: View {
    @ObservedObject var pin: ShortcutPin
    var accessibilityID: String?
    var contextMenuEntries: () -> [SidebarContextMenuEntry]
    let action: () -> Void
    var dragSourceZone: DropZoneID?
    var dragHasTrailingActionExclusion: Bool
    var dragIsEnabled: Bool
    let onResetToLaunchURL: (() -> Void)?
    let onUnload: () -> Void
    let onRemove: () -> Void

    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        ShortcutSidebarRowChrome(
            pin: pin,
            liveTab: nil,
            faviconPartition: browserManager.tabManager.resolvedFaviconPartition(
                for: pin,
                currentSpaceId: windowState.currentSpaceId
            ),
            resolvedTitle: pin.preferredDisplayTitle,
            runtimeAffordance: browserManager.tabManager.shortcutRuntimeAffordanceState(
                for: pin,
                in: windowState
            ),
            accessibilityID: accessibilityID,
            contextMenuEntries: contextMenuEntries,
            action: action,
            dragSourceZone: dragSourceZone,
            dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
            dragIsEnabled: dragIsEnabled,
            onResetToLaunchURL: onResetToLaunchURL,
            onUnload: onUnload,
            onRemove: onRemove
        )
    }
}

private struct ShortcutSidebarRowChrome: View {
    let pin: ShortcutPin
    let liveTab: Tab?
    let faviconPartition: SumiFaviconPartition
    let resolvedTitle: String
    let runtimeAffordance: SumiLauncherRuntimeAffordanceState
    var accessibilityID: String?
    var contextMenuEntries: () -> [SidebarContextMenuEntry] = { [] }
    let action: () -> Void
    var dragSourceZone: DropZoneID?
    var dragHasTrailingActionExclusion: Bool = true
    var dragIsEnabled: Bool = true
    let onResetToLaunchURL: (() -> Void)?
    let onUnload: () -> Void
    let onRemove: () -> Void

    @Environment(BrowserWindowState.self) private var windowState
    @EnvironmentObject private var glanceManager: GlanceManager
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isRowHovered = false
    @State private var isActionHovered = false
    @State private var isGlanceCloseHovered = false
    @State private var isResetHovered = false
    @State private var suppressRegularActionUntilHoverExit = false
    @State private var faviconCacheRefreshID = UUID()
    @State private var loadedStoredFaviconURL: URL?
    @State private var loadedStoredFavicon: Image?

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
        .overlay(alignment: .leading) {
            rowActivationOverlay
        }
        .overlay(alignment: .trailing) {
            trailingActionButton
                .padding(.trailing, SidebarRowLayout.trailingInset)
        }
        .sidebarRowSurface(
            background: backgroundColor,
            cornerRadius: cornerRadius,
            tokens: tokens,
            isVisible: drawsRowSurface,
            drawsSelectionShadow: runtimeAffordance.isSelected
        )
        // Expose the row container itself so the launcher keeps the same source identity
        // when runtime drift replaces the leading favicon with the reset control.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityID ?? "shortcut-sidebar-row")
        .accessibilityValue(runtimeAffordance.isSelected ? "selected" : "not selected")
        .sidebarDDGHover($isRowHovered, isEnabled: dragIsEnabled)
        .onChange(of: isRowHovered) { _, hovering in
            if !hovering {
                suppressRegularActionUntilHoverExit = false
            }
        }
        .onChange(of: activeGlanceSessionForRow?.id) { oldValue, newValue in
            if oldValue != nil, newValue == nil, isRowHovered {
                suppressRegularActionUntilHoverExit = true
            } else if newValue != nil {
                suppressRegularActionUntilHoverExit = false
            }
        }
        .sidebarZenPressEffect(sourceID: rowSourceID, isEnabled: dragIsEnabled)
        .task(id: storedFaviconLoadKey) {
            await loadStoredFavicon()
        }
        .onReceive(NotificationCenter.default.publisher(for: .faviconCacheUpdated)) { notification in
            guard pin.iconAsset == nil else { return }
            guard PinnedTileAccentResolver.faviconUpdate(notification, matches: pin.launchURL) else { return }
            loadedStoredFaviconURL = nil
            loadedStoredFavicon = nil
            faviconCacheRefreshID = UUID()
        }
        .sidebarAppKitContextMenu(
            isInteractionEnabled: dragIsEnabled,
            dragSource: dragSourceConfiguration,
            primaryAction: action,
            sourceID: rowSourceID,
            entries: contextMenuEntries
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
            }
        }
        .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)
        .saturation(runtimeAffordance.shouldDesaturateIcon ? 0.0 : 1.0)
        .opacity(runtimeAffordance.shouldDesaturateIcon ? 0.8 : 1.0)
    }

    private var displayFavicon: Image {
        if let launcherFavicon = currentCachedStoredFavicon {
            return launcherFavicon
        }
        if let liveTab, !liveTab.faviconIsTemplateGlobePlaceholder {
            return liveTab.favicon
        }
        return pin.storedFaviconImage(partition: faviconPartition)
    }

    private var chromeTemplateSystemImageName: String? {
        if let liveTab {
            if SumiSurface.isSettingsSurfaceURL(liveTab.url) {
                return SumiSurface.settingsTabFaviconSystemImageName
            }
            if currentCachedStoredFavicon != nil {
                return nil
            }
            if liveTab.faviconIsTemplateGlobePlaceholder {
                return SumiPersistentGlyph.launcherSystemImageFallback
            }
            return nil
        }
        if currentLoadedStoredFavicon != nil {
            return nil
        }
        return pin.storedChromeTemplateSystemImageName(for: faviconPartition)
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
            trailingPadding: titleTrailingPadding,
            animated: liveTab != nil
        )
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var trailingActionButton: some View {
        if let glanceSession = activeGlanceSessionForRow {
            SidebarGlanceTrailingAccessory(
                session: glanceSession,
                sourceID: pin.id.uuidString,
                accessibilityPrefix: "shortcut-sidebar-glance",
                showsCloseButton: showsGlanceCloseButton,
                isCloseHovered: $isGlanceCloseHovered,
                textColor: textColor,
                closeBackground: actionBackground,
                isEnabled: !freezesHoverState,
                isInteractionEnabled: dragIsEnabled
            )
        } else {
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
    }

    private var backgroundColor: Color {
        if runtimeAffordance.isSelected {
            return tokens.sidebarRowActive
        } else if displayIsHovering {
            return tokens.sidebarRowHover
        }
        return .clear
    }

    private var drawsRowSurface: Bool {
        runtimeAffordance.isSelected || displayIsHovering
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
        activeGlanceSessionForRow == nil
            && !suppressRegularActionUntilHoverExit
            && displayIsHovering
    }

    private var activeGlanceSessionForRow: GlanceSession? {
        guard let liveTab,
              let session = glanceManager.sidebarSession(for: windowState),
              session.sourceTab?.id == liveTab.id
        else { return nil }
        return session
    }

    private var showsGlanceCloseButton: Bool {
        activeGlanceSessionForRow != nil && displayIsHovering
    }

    private var titleTrailingPadding: CGFloat {
        if activeGlanceSessionForRow != nil {
            return SidebarRowLayout.trailingActionSize
                + (showsGlanceCloseButton ? SidebarRowLayout.trailingActionSize + SidebarRowLayout.trailingActionGap : 0)
        }
        return SidebarHoverChrome.trailingPadding(showsTrailingAction: showsActionButton)
    }

    private var trailingActivationExclusionWidth: CGFloat {
        if activeGlanceSessionForRow != nil {
            return SidebarRowLayout.trailingActionSize
                + SidebarRowLayout.trailingInset
                + (showsGlanceCloseButton ? SidebarRowLayout.trailingActionSize + SidebarRowLayout.trailingActionGap : 0)
        }
        return dragHasTrailingActionExclusion ? 40 : 0
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

    private var currentLoadedStoredFavicon: Image? {
        loadedStoredFaviconURL == pin.launchURL ? loadedStoredFavicon : nil
    }

    private var currentCachedStoredFavicon: Image? {
        currentLoadedStoredFavicon ?? ShortcutPin.cachedLaunchFavicon(
            for: pin.launchURL,
            partition: faviconPartition
        )
    }

    private var storedFaviconLoadKey: String {
        guard pin.iconAsset == nil else {
            return "disabled|\(pin.id.uuidString)|\(faviconCacheRefreshID.uuidString)"
        }
        return [
            pin.launchURL.absoluteString,
            faviconPartition.storageComponent,
            faviconCacheRefreshID.uuidString,
        ].joined(separator: "|")
    }

    @MainActor
    private func loadStoredFavicon() async {
        guard pin.iconAsset == nil else { return }

        let launchURL = pin.launchURL
        guard let image = await TabFaviconStore.loadCachedLauncherImage(
            forDocumentURL: launchURL,
            partition: faviconPartition
        ),
              !Task.isCancelled,
              launchURL == pin.launchURL
        else { return }

        loadedStoredFaviconURL = launchURL
        loadedStoredFavicon = Image(nsImage: image)
    }

    private var dragSourceConfiguration: SidebarDragSourceConfiguration? {
        makeShortcutSidebarDragSourceConfiguration(
            pin: pin,
            resolvedTitle: resolvedTitle,
            runtimeAffordance: runtimeAffordance,
            dragSourceZone: dragSourceZone,
            dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
            hasLiveAudioExclusion: liveTab?.audioState.showsTabAudioButton == true,
            trailingActionExclusionWidth: trailingActivationExclusionWidth,
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
            let trailingLimit = max(proxy.size.width - trailingActivationExclusionWidth, resetExclusionWidth)

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
    trailingActionExclusionWidth: CGFloat = 40,
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
            hasLiveAudioExclusion: hasLiveAudioExclusion,
            trailingActionExclusionWidth: trailingActionExclusionWidth
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
    makeShortcutSidebarDragExclusionZones(
        runtimeAffordance: runtimeAffordance,
        dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
        hasLiveAudioExclusion: hasLiveAudioExclusion,
        trailingActionExclusionWidth: 40
    )
}

@MainActor
func makeShortcutSidebarDragExclusionZones(
    runtimeAffordance: SumiLauncherRuntimeAffordanceState,
    dragHasTrailingActionExclusion: Bool,
    hasLiveAudioExclusion: Bool = false,
    trailingActionExclusionWidth: CGFloat = 40
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
        exclusions.append(.trailingStrip(trailingActionExclusionWidth))
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
