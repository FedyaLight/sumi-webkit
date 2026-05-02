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
                .padding(.bottom, 4)
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
    /// Single spring for layout + clip: avoids opacity fighting height (feels glued to the card edge).
    private static let hoverExpandAnimation = Animation.spring(response: 0.3, dampingFraction: 0.86)

    private static let collapsedCardHeight: CGFloat = 40
    private static let cardVerticalPadding: CGFloat = 4
    private static let controlsRowHeight: CGFloat = 26
    /// When collapsed, reveal height is 0; band fills the card under vertical padding so Spacers can center the row.
    private static let controlsBandCollapsedHeight =
        collapsedCardHeight - cardVerticalPadding * 2

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

    private var cardCornerRadius: CGFloat {
        sumiSettings.resolvedCornerRadius(10)
    }

    var body: some View {
        cardBody()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cardBody() -> some View {
        let shape = RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)

        return VStack(alignment: .leading, spacing: 0) {
            revealSection
                .frame(maxHeight: isExpanded ? nil : 0, alignment: .top)
                .clipped()
                .allowsHitTesting(isExpanded)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                controlsRow
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: isExpanded ? Self.controlsRowHeight : Self.controlsBandCollapsedHeight)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, Self.cardVerticalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: isExpanded ? nil : Self.collapsedCardHeight, alignment: .top)
        .background {
            shape.fill(cardBackground)
        }
        .clipShape(shape)
        .overlay {
            shape.stroke(cardBorder, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.05), radius: 8, y: 1)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Self.hoverExpandAnimation) {
                isHovered = hovering
            }
        }
    }

    private var revealSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            infoRow
        }
        .padding(.top, 5)
        .padding(.bottom, 5)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var infoRow: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                OverflowAwareMarqueeText(
                    text: cardState.title,
                    font: .system(size: 11, weight: .semibold),
                    color: tokens.primaryText
                )

                if !cardState.subtitle.isEmpty {
                    Text(cardState.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(tokens.secondaryText.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controlsRow: some View {
        ZStack {
            HStack(spacing: 0) {
                focusButton
                Spacer(minLength: 0)
                compactIconButton(
                    systemName: cardState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    help: cardState.isMuted ? "Unmute Audio" : "Mute Audio",
                    isEnabled: cardState.canMute,
                    action: onToggleMute
                )
            }

            compactIconButton(
                systemName: cardState.isPlaying ? "pause.fill" : "play.fill",
                help: cardState.isPlaying ? "Pause" : "Play",
                isEnabled: cardState.canPlayPause,
                isPrimary: true,
                action: onPlayPause
            )
        }
        .frame(maxWidth: .infinity)
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
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(cardBorder.opacity(0.9), lineWidth: 0.5)
                }
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
