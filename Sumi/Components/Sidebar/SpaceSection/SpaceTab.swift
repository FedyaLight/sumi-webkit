//
//  SpaceTab.swift
//  Sumi
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import AppKit
import SwiftUI

struct SpaceTab: View {
    @ObservedObject var tab: Tab
    var dragSourceConfiguration: SidebarDragSourceConfiguration? = nil
    var isAppKitInteractionEnabled: Bool = true
    var action: () -> Void
    var onClose: () -> Void
    var onMute: () -> Void
    var contextMenuEntries: [SidebarContextMenuEntry] = []
    @FocusState private var isTextFieldFocused: Bool
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var settings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                ZStack {
                    SidebarTabFaviconView(tab: tab, size: SidebarRowLayout.faviconSize, cornerRadius: 6)
                        .opacity(tab.showsWebViewUnloadedIndicator ? 0.5 : 1.0)
                    
                    if tab.showsWebViewUnloadedIndicator {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .background(Color.gray)
                            .clipShape(Circle())
                            .offset(x: 6, y: -6)
                    }
                }
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
                                .animation(.easeInOut(duration: 0.05), value: displayIsSpeakerHovering)
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
                    }
                    .buttonStyle(PlainButtonStyle())
                    .sidebarHoverTarget(
                        speakerHoverTarget,
                        isEnabled: isAppKitInteractionEnabled,
                        animation: .easeInOut(duration: 0.05)
                    )
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
                        trailingFadePadding: showsCloseButton ? SidebarRowLayout.trailingActionFadePadding : 0
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
            .background(
                backgroundColor
            )
            .overlay(alignment: .trailing) {
                closeButton
                    .padding(.trailing, SidebarRowLayout.trailingInset)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .onTapGesture {
            if tab.isRenaming {
                tab.saveRename()
            }
            action()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("tab-row-\(tab.id.uuidString)")
        .accessibilityValue(isCurrentTab ? "selected" : "not selected")
        .sidebarHoverTarget(
            rowHoverTarget,
            isEnabled: isAppKitInteractionEnabled,
            animation: .easeInOut(duration: 0.05)
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
            dragSource: dragSourceConfiguration,
            primaryAction: {
                if tab.isRenaming {
                    tab.saveRename()
                }
                action()
            },
            sourceID: "tab-row-\(tab.id.uuidString)",
            entries: { contextMenuEntries }
        )
        .task(id: tab.url) {
            await tab.fetchFaviconForVisiblePresentation()
        }
        .shadow(color: isActive ? shadowColor : Color.clear, radius: isActive ? 2 : 0, y: 1.5)
    }

    private var isActive: Bool {
        return browserManager.currentTab(for: windowState)?.id == tab.id
    }
    
    private var isCurrentTab: Bool {
        return browserManager.currentTab(for: windowState)?.id == tab.id
    }

    private var shadowColor: Color {
        tokens.sidebarSelectionShadow
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
    private var textTab: Color {
        return tokens.primaryText
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: settings)
    }

    private var freezesHoverState: Bool {
        windowState.sidebarInteractionState.freezesSidebarHoverState
    }

    private var displayIsHovering: Bool {
        windowState.sidebarInteractionState.isSidebarHoverActive(rowHoverTarget)
            && !freezesHoverState
    }

    private var displayIsCloseHovering: Bool {
        windowState.sidebarInteractionState.isSidebarHoverActive(closeHoverTarget)
            && !freezesHoverState
    }

    private var displayIsSpeakerHovering: Bool {
        windowState.sidebarInteractionState.isSidebarHoverActive(speakerHoverTarget)
            && !freezesHoverState
    }

    private var showsCloseButton: Bool {
        displayIsHovering || isCurrentTab
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
        .buttonStyle(PlainButtonStyle())
        .opacity(showsCloseButton ? 1 : 0)
        .allowsHitTesting(showsCloseButton && !freezesHoverState)
        .accessibilityHidden(!showsCloseButton)
        .sidebarHoverTarget(
            closeHoverTarget,
            isEnabled: showsCloseButton && isAppKitInteractionEnabled,
            animation: .easeInOut(duration: 0.05)
        )
        .accessibilityIdentifier("space-regular-tab-close-\(tab.id.uuidString)")
        .sidebarAppKitPrimaryAction(
            isEnabled: showsCloseButton && !freezesHoverState,
            isInteractionEnabled: isAppKitInteractionEnabled,
            action: onClose
        )
    }

    private var rowHoverTarget: SidebarHoverTarget {
        .row("regular-tab-\(tab.id.uuidString)")
    }

    private var closeHoverTarget: SidebarHoverTarget {
        .action("regular-tab-close-\(tab.id.uuidString)")
    }

    private var speakerHoverTarget: SidebarHoverTarget {
        .action("regular-tab-audio-\(tab.id.uuidString)")
    }
}
