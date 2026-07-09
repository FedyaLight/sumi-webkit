//
//  ShortcutSidebarLauncherAudioButton.swift
//  Sumi
//

import SwiftUI
import SumiDomain

struct LauncherAudioButton: View {
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
                            .font(SidebarThemeTokens.Typography.rowAccessory)
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
