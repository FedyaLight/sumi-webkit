//
//  SpaceTab.swift
//  Sumi
//
//

import AppKit
import SwiftUI

struct SpaceTab: View {
    @ObservedObject var tab: Tab
    var dragSourceConfiguration: SidebarDragSourceConfiguration?
    var isAppKitInteractionEnabled: Bool = true
    var action: () -> Void
    var onClose: () -> Void
    var onMute: () -> Void
    var contextMenuEntries: () -> [SidebarContextMenuEntry] = { [] }
    var fetchesVisiblePresentation: Bool = true
    @FocusState private var isTextFieldFocused: Bool
    @State private var isRowHovered = false
    @State private var isCloseHovered = false
    @State private var isGlanceCloseHovered = false
    @State private var isSpeakerHovered = false
    @State private var suppressRegularCloseUntilHoverExit = false
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject private var glanceManager: GlanceManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var settings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                favicon
                if tab.audioState.showsTabAudioButton {
                    Button(action: {
                        onMute()
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    displayIsSpeakerHovering
                                        ? (isCurrentTab ? tokens.fieldBackgroundHover : tokens.fieldBackground)
                                        : Color.clear
                                )
                                .frame(width: 22, height: 22)
                            ZStack {
                                Image(systemName: tab.audioState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(tab.audioState.isMuted ? tokens.secondaryText : textTab)
                                    .id(tab.audioState.isMuted)
                                    .transition(
                                        .asymmetric(
                                            insertion: .scale(scale: 0.82).combined(with: .opacity),
                                            removal: .scale(scale: 1.08).combined(with: .opacity)
                                        )
                                    )
                            }
                            .animation(.easeInOut(duration: 0.1), value: tab.audioState.isMuted)
                        }
                        .frame(width: 22, height: 22)
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(
                        SidebarZenActionButtonStyle(
                            isEnabled: isAppKitInteractionEnabled && !freezesHoverState
                        )
                    )
                    .frame(width: 22, height: 22)
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .sidebarDDGHover($isSpeakerHovered, isEnabled: isAppKitInteractionEnabled)
                    .accessibilityIdentifier("space-regular-tab-audio-\(tab.id.uuidString)")
                    .sidebarAppKitPrimaryAction(
                        isEnabled: !freezesHoverState,
                        isInteractionEnabled: isAppKitInteractionEnabled,
                        action: onMute
                    )
                    .help(tab.audioState.isMuted ? "Unmute Audio" : "Mute Audio")
                }

                if tab.isRenaming {
                    TextField("", text: $tab.editingName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tab.showsWebViewUnloadedIndicator ? tokens.secondaryText : textTab)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onSubmit {
                            tab.saveRename()
                        }
                        .onExitCommand {
                            tab.cancelRename()
                        }
                        .onAppear {
                            DispatchQueue.main.async {
                                isTextFieldFocused = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                if let textField = NSApp.keyWindow?.firstResponder as? NSTextView {
                                    textField.selectAll(nil)
                                }
                            }
                        }
                        .focused($isTextFieldFocused)
                } else {
                    SumiTabTitleLabel(
                        title: tab.name,
                        font: .systemFont(ofSize: 13, weight: .medium),
                        textColor: textTab,
                        trailingPadding: titleTrailingPadding
                    )
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .textSelection(.disabled) // Make text non-selectable
                }
            }
            .padding(.leading, SidebarRowLayout.leadingInset)
            .padding(.trailing, SidebarRowLayout.trailingInset)
            .frame(height: SidebarRowLayout.rowHeight)
            .frame(minWidth: 0, maxWidth: .infinity)
            .contentShape(Rectangle())
            .overlay(alignment: .leading) {
                rowActivationOverlay
            }
            .overlay(alignment: .trailing) {
                trailingAccessory
                    .padding(.trailing, SidebarRowLayout.trailingInset)
            }
            .sidebarRowSurface(
                background: backgroundColor,
                cornerRadius: rowCornerRadius,
                tokens: tokens,
                isVisible: drawsRowSurface,
                drawsSelectionShadow: isCurrentTab
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("tab-row-\(tab.id.uuidString)")
        .accessibilityValue(isCurrentTab ? "selected" : "not selected")
        .sidebarDDGHover($isRowHovered, isEnabled: isAppKitInteractionEnabled)
        .onChange(of: isRowHovered) { _, hovering in
            if !hovering {
                suppressRegularCloseUntilHoverExit = false
            }
        }
        .onChange(of: activeGlanceSessionForRow?.id) { oldValue, newValue in
            if oldValue != nil, newValue == nil, isRowHovered {
                suppressRegularCloseUntilHoverExit = true
            } else if newValue != nil {
                suppressRegularCloseUntilHoverExit = false
            }
        }
        .sidebarZenPressEffect(
            sourceID: rowSourceID,
            isEnabled: isAppKitInteractionEnabled && !tab.isRenaming
        )
        .background(
            Group {
                if tab.isRenaming {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            tab.saveRename()
                        }
                }
            }
        )
        .sidebarAppKitContextMenu(
            isInteractionEnabled: isAppKitInteractionEnabled,
            dragSource: effectiveDragSourceConfiguration,
            primaryAction: {
                if tab.isRenaming {
                    tab.saveRename()
                }
                action()
            },
            sourceID: rowSourceID,
            entries: contextMenuEntries
        )
        .task(id: tab.url) {
            guard fetchesVisiblePresentation else { return }
            await tab.fetchFaviconForVisiblePresentation()
        }
    }

    private var rowSourceID: String {
        "tab-row-\(tab.id.uuidString)"
    }

    private var isCurrentTab: Bool {
        browserManager.currentTab(for: windowState)?.id == tab.id
    }

    private var rowCornerRadius: CGFloat {
        settings.resolvedCornerRadius(12)
    }

    private var backgroundColor: Color {
        if isCurrentTab {
            return tokens.sidebarRowActive
        } else if displayIsHovering {
            return tokens.sidebarRowHover
        } else {
            return Color.clear
        }
    }

    private var drawsRowSurface: Bool {
        isCurrentTab || displayIsHovering
    }

    private var textTab: Color {
        tokens.primaryText
    }

    @ViewBuilder
    private var favicon: some View {
        if tab.showsWebViewUnloadedIndicator {
            SidebarUnloadedRegularTabFaviconIndicator(
                size: SidebarRowLayout.faviconSize
            ) {
                SidebarTabFaviconView(tab: tab, size: SidebarRowLayout.faviconSize)
            }
        } else {
            SidebarTabFaviconView(tab: tab, size: SidebarRowLayout.faviconSize)
        }
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: settings)
    }

    private var freezesHoverState: Bool {
        windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var displayIsHovering: Bool {
        SidebarHoverChrome.displayHover(isRowHovered, freezesHoverState: freezesHoverState)
    }

    private var displayIsCloseHovering: Bool {
        SidebarHoverChrome.displayHover(isCloseHovered, freezesHoverState: freezesHoverState)
    }

    private var displayIsSpeakerHovering: Bool {
        SidebarHoverChrome.displayHover(isSpeakerHovered, freezesHoverState: freezesHoverState)
    }

    private var showsCloseButton: Bool {
        guard activeGlanceSessionForRow == nil else { return false }
        guard !suppressRegularCloseUntilHoverExit else { return false }
        return SidebarHoverChrome.showsTrailingAction(
            isHovered: displayIsHovering,
            isSelected: isCurrentTab
        )
    }

    private var activeGlanceSessionForRow: GlanceSession? {
        guard let session = glanceManager.sidebarSession(for: windowState),
              session.sourceTab?.id == tab.id
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
        return SidebarHoverChrome.trailingPadding(showsTrailingAction: showsCloseButton)
    }

    private var trailingActivationExclusionWidth: CGFloat {
        if activeGlanceSessionForRow != nil {
            return SidebarRowLayout.trailingActionSize
                + SidebarRowLayout.trailingInset
                + (showsGlanceCloseButton ? SidebarRowLayout.trailingActionSize + SidebarRowLayout.trailingActionGap : 0)
        }
        return 40
    }

    private var effectiveDragSourceConfiguration: SidebarDragSourceConfiguration? {
        guard let dragSourceConfiguration else { return nil }
        guard activeGlanceSessionForRow != nil else { return dragSourceConfiguration }

        return dragSourceConfiguration.replacingExclusionZones(
            dragSourceConfiguration.exclusionZones + [
                .trailingStrip(trailingActivationExclusionWidth),
            ]
        )
    }

    static var audioButtonHitFrame: CGRect {
        CGRect(
            x: SidebarRowLayout.leadingInset
                + SidebarRowLayout.faviconSize
                + 8,
            y: (SidebarRowLayout.rowHeight - 22) / 2,
            width: 22,
            height: 22
        )
    }

    private var activeAudioButtonHitFrame: CGRect {
        guard tab.audioState.showsTabAudioButton else { return .null }

        return Self.audioButtonHitFrame
    }

    @ViewBuilder
    private var rowActivationOverlay: some View {
        if !tab.isRenaming {
            GeometryReader { proxy in
                let trailingLimit = max(proxy.size.width - trailingActivationExclusionWidth, 0)

                ZStack(alignment: .leading) {
                    if tab.audioState.showsTabAudioButton {
                        activationHitRegion(width: activeAudioButtonHitFrame.minX)

                        activationHitRegion(
                            width: max(trailingLimit - activeAudioButtonHitFrame.maxX, 0)
                        )
                        .offset(x: activeAudioButtonHitFrame.maxX)
                    } else {
                        activationHitRegion(width: trailingLimit)
                    }
                }
            }
            .frame(height: SidebarRowLayout.rowHeight)
        }
    }

    private func activationHitRegion(width: CGFloat) -> some View {
        Color.clear
            .frame(width: max(width, 0), height: SidebarRowLayout.rowHeight)
            .contentShape(Rectangle())
            .onTapGesture(perform: activateRow)
    }

    private func activateRow() {
        action()
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if let glanceSession = activeGlanceSessionForRow {
            SidebarGlanceTrailingAccessory(
                session: glanceSession,
                sourceID: tab.id.uuidString,
                accessibilityPrefix: "space-regular-tab-glance",
                showsCloseButton: showsGlanceCloseButton,
                isCloseHovered: $isGlanceCloseHovered,
                textColor: textTab,
                closeBackground: isCurrentTab ? tokens.fieldBackgroundHover : tokens.fieldBackground,
                isEnabled: !freezesHoverState,
                isInteractionEnabled: isAppKitInteractionEnabled
            )
        } else {
            closeButton
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(textTab)
                .frame(
                    width: SidebarRowLayout.trailingActionSize,
                    height: SidebarRowLayout.trailingActionSize
                )
                .background(
                    displayIsCloseHovering
                        ? (isCurrentTab ? tokens.fieldBackgroundHover : tokens.fieldBackground)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(
            SidebarZenActionButtonStyle(
                isEnabled: showsCloseButton && !freezesHoverState
            )
        )
        .opacity(showsCloseButton ? 1 : 0)
        .sidebarZenActionOpacity(showsCloseButton)
        .allowsHitTesting(showsCloseButton && !freezesHoverState)
        .accessibilityHidden(!showsCloseButton)
        .sidebarDDGHover($isCloseHovered, isEnabled: showsCloseButton && isAppKitInteractionEnabled)
        .accessibilityIdentifier("space-regular-tab-close-\(tab.id.uuidString)")
        .sidebarAppKitPrimaryAction(
            isEnabled: showsCloseButton && !freezesHoverState,
            isInteractionEnabled: isAppKitInteractionEnabled,
            action: onClose
        )
    }
}

struct SidebarGlanceTrailingAccessory: View {
    @ObservedObject var session: GlanceSession
    let sourceID: String
    let accessibilityPrefix: String
    let showsCloseButton: Bool
    @Binding var isCloseHovered: Bool
    let textColor: Color
    let closeBackground: Color
    let isEnabled: Bool
    let isInteractionEnabled: Bool

    @EnvironmentObject private var glanceManager: GlanceManager
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        HStack(spacing: SidebarRowLayout.trailingActionGap) {
            closeButton
            SidebarTabFaviconView(
                tab: session.previewTab,
                size: SidebarRowLayout.faviconSize
            )
            .frame(
                width: SidebarRowLayout.trailingActionSize,
                height: SidebarRowLayout.trailingActionSize
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .help(session.title)
            .accessibilityIdentifier("\(accessibilityPrefix)-favicon-\(sourceID)")
        }
    }

    private var closeButton: some View {
        Button(action: closeCurrentSession) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(textColor)
                .frame(
                    width: SidebarRowLayout.trailingActionSize,
                    height: SidebarRowLayout.trailingActionSize
                )
                .background(displayIsCloseHovering ? closeBackground : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(
            SidebarZenActionButtonStyle(
                isEnabled: showsCloseButton && isEnabled
            )
        )
        .opacity(showsCloseButton ? 1 : 0)
        .sidebarZenActionOpacity(showsCloseButton)
        .allowsHitTesting(showsCloseButton && isEnabled)
        .accessibilityHidden(!showsCloseButton)
        .sidebarDDGHover($isCloseHovered, isEnabled: showsCloseButton && isInteractionEnabled)
        .accessibilityIdentifier("\(accessibilityPrefix)-close-\(sourceID)")
        .sidebarAppKitPrimaryAction(
            isEnabled: showsCloseButton && isEnabled,
            isInteractionEnabled: isInteractionEnabled,
            action: closeCurrentSession
        )
        .help("Close Glance")
    }

    private var displayIsCloseHovering: Bool {
        SidebarHoverChrome.displayHover(
            isCloseHovered,
            freezesHoverState: windowState.sidebarInteractionState.freezesSidebarHoverState
        )
    }

    private func closeCurrentSession() {
        guard glanceManager.currentSession?.id == session.id else { return }
        glanceManager.dismissGlance()
    }
}
