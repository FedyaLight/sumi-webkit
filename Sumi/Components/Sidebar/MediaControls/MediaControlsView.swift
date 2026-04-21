//
//  MediaControlsView.swift
//  Sumi
//

import AppKit
import Foundation
import SwiftUI

struct MediaControlsView: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var mediaStore = SumiBackgroundMediaCardStore()

    var body: some View {
        Group {
            if windowState.isSidebarVisible, let cardState = mediaStore.cardState {
                SumiBackgroundMediaCardView(
                    cardState: cardState,
                    onFocus: mediaStore.activateSource,
                    onPlayPause: { Task { await mediaStore.togglePlayPause() } },
                    onToggleMute: { Task { await mediaStore.toggleMute() } }
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .offset(y: 10))
                            .animation(.easeOut(duration: 0.22)),
                        removal: .opacity
                            .combined(with: .offset(y: 4))
                            .animation(.easeInOut(duration: 0.16))
                    )
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mediaStore.cardState != nil)
        .onAppear {
            mediaStore.configure(browserManager: browserManager, windowState: windowState)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                mediaStore.handleSceneActive()
            }
        }
        .onChange(of: windowState.currentTabId) { _, _ in
            mediaStore.handleSelectionChange()
        }
        .onChange(of: windowState.currentSpaceId) { _, _ in
            mediaStore.handleSelectionChange()
        }
    }
}

private struct SumiBackgroundMediaCardView: View {
    let cardState: SumiBackgroundMediaCardState
    let onFocus: () -> Void
    let onPlayPause: () -> Void
    let onToggleMute: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    @State private var isHovered = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var isExpanded: Bool {
        isHovered
    }

    private var cardBackground: Color {
        tokens.toastBackground.opacity(0.985)
    }

    private var cardBorder: Color {
        tokens.toastBorder.opacity(0.92)
    }

    private var controlBackground: Color {
        tokens.buttonSecondaryBackground.opacity(0.98)
    }

    var body: some View {
        cardBody()
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func cardBody() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpanded {
                revealSection
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .offset(y: 6))
                                .animation(.easeInOut(duration: 0.18)),
                            removal: .opacity
                                .combined(with: .offset(y: 10))
                                .animation(.easeInOut(duration: 0.12))
                        )
                    )
            }

            controlsRow
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .frame(height: isExpanded ? nil : 40, alignment: .center)
        .background {
            RoundedRectangle(
                cornerRadius: sumiSettings.resolvedCornerRadius(10),
                style: .continuous
            )
            .fill(cardBackground)
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: sumiSettings.resolvedCornerRadius(10),
                style: .continuous
            )
            .stroke(cardBorder, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.05), radius: 8, y: 1)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
    }

    private var revealSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            infoRow
        }
        .padding(.top, 5)
        .padding(.bottom, 2)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var infoRow: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                OverflowAwareMarqueeText(
                    text: cardState.title,
                    font: .system(size: 11, weight: .semibold),
                    color: tokens.primaryText
                )

                HStack(spacing: 6) {
                    Text(cardState.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(tokens.secondaryText.opacity(0.9))
                        .lineLimit(1)

                    if let sourceHost = cardState.sourceHost, !sourceHost.isEmpty {
                        Text(sourceHost)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tokens.secondaryText.opacity(0.8))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                controlBackground,
                                in: Capsule(style: .continuous)
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controlsRow: some View {
        HStack(spacing: 0) {
            focusButton

            Spacer(minLength: 12)

            compactIconButton(
                systemName: cardState.isPlaying ? "pause.fill" : "play.fill",
                help: cardState.isPlaying ? "Pause" : "Play",
                isEnabled: cardState.canPlayPause,
                isPrimary: true,
                action: onPlayPause
            )

            Spacer(minLength: 12)

            compactIconButton(
                systemName: cardState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                help: cardState.isMuted ? "Unmute Audio" : "Mute Audio",
                isEnabled: cardState.canMute,
                action: onToggleMute
            )
        }
        .frame(height: 26)
    }

    private var focusButton: some View {
        Button(action: onFocus) {
            SumiMediaSourceIconView(cardState: cardState)
                .frame(width: 26, height: 26)
                .background(
                    controlBackground,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(cardBorder.opacity(0.9), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .help("Focus source tab")
    }

    private func compactIconButton(
        systemName: String,
        help: String,
        isEnabled: Bool = true,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isPrimary ? tokens.primaryText : tokens.secondaryText)
                .frame(width: 26, height: 26)
                .background(
                    controlBackground,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .help(help)
    }
}

private struct SumiMediaSourceIconView: View {
    let cardState: SumiBackgroundMediaCardState

    var body: some View {
        Group {
            if let faviconKey = cardState.favicon,
               let icon = TabFaviconStore.getCachedImage(for: faviconKey)
            {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else if cardState.sourceHost != nil {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct OverflowAwareMarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 14, alignment: .center)
    }
}
