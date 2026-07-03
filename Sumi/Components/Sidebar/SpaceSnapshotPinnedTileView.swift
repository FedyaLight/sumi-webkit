import SwiftUI

struct SpaceSnapshotPinnedTileView: View {
    let item: SpaceShortcutSnapshot
    let tileSize: CGSize
    let configuration: PinnedTabsConfiguration
    let tokens: ChromeThemeTokens

    @Environment(\.sumiSettings) private var sumiSettings

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundColor)
                .overlay {
                    if item.presentationState.isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(selectionAccentColor.opacity(0.35))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .frame(width: tileSize.width, height: tileSize.height)

            SpaceSnapshotIconView(
                icon: item.icon,
                size: configuration.faviconHeight,
                foregroundColor: tokens.primaryText
            )
            .saturation(item.presentationState.shouldDesaturateIcon ? 0.0 : 1.0)
            .opacity(item.presentationState.shouldDesaturateIcon ? 0.8 : 1.0)
            .frame(width: tileSize.width, height: tileSize.height, alignment: .center)

            if item.showsSplitOutline {
                PinnedTileSplitGroupOutlineMask(
                    corner: cornerRadius,
                    thickness: max(1.25, configuration.strokeWidth * 0.7),
                    strokeColor: selectionAccentColor
                )
                .frame(width: tileSize.width, height: tileSize.height)
                .allowsHitTesting(false)
            } else if item.presentationState.isSelected {
                accentSelectionRingOverlay(
                    corner: cornerRadius,
                    thickness: configuration.strokeWidth,
                    color: selectionAccentColor
                )
                .frame(width: tileSize.width, height: tileSize.height)
                .allowsHitTesting(false)
            }
        }
        .frame(width: tileSize.width, height: tileSize.height, alignment: .center)
        .overlay(alignment: .topLeading) {
            if item.showsAudioButton {
                audioIndicator
                    .padding(6)
            }
        }
        .shadow(
            color: item.presentationState.isSelected ? tokens.sidebarSelectionShadow : .clear,
            radius: item.presentationState.isSelected ? 2 : 0,
            y: item.presentationState.isSelected ? 1 : 0
        )
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .accessibilityIdentifier("essential-shortcut-snapshot-\(item.id.uuidString)")
    }

    private var cornerRadius: CGFloat {
        sumiSettings.resolvedCornerRadius(configuration.cornerRadius)
    }

    private var backgroundColor: Color {
        if item.presentationState.isSelected {
            return tokens.pinnedActiveBackground
        }
        return tokens.pinnedIdleBackground
    }

    private var selectionAccentColor: Color {
        switch item.icon {
        case .image:
            return tokens.accent
        case .system:
            return tokens.primaryText
        case .emoji:
            return tokens.accent
        }
    }

    private var audioIndicator: some View {
        Image(systemName: item.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(item.isMuted ? tokens.secondaryText : tokens.primaryText)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tokens.fieldBackground.opacity(0.88))
            )
            .accessibilityHidden(true)
    }

    private func accentSelectionRingOverlay(
        corner: CGFloat,
        thickness: CGFloat,
        color: Color
    ) -> some View {
        let strokeInset = thickness / 2
        return RoundedRectangle(
            cornerRadius: max(0, corner - strokeInset),
            style: .continuous
        )
        .inset(by: strokeInset)
        .stroke(color, lineWidth: thickness)
    }
}
