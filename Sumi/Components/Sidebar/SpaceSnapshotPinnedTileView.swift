import SwiftUI

struct SpaceSnapshotPinnedTileView: View {
    let item: SpaceShortcutSnapshot
    let tileSize: CGSize
    let configuration: PinnedTabsConfiguration
    let tokens: ChromeThemeTokens

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: configuration.cornerRadius, style: .continuous)
                .fill(item.presentationState.isSelected ? tokens.pinnedActiveBackground : tokens.pinnedIdleBackground)
                .overlay {
                    if item.presentationState.isSelected && !item.showsSplitOutline {
                        RoundedRectangle(cornerRadius: configuration.cornerRadius, style: .continuous)
                            .inset(by: configuration.strokeWidth / 2)
                            .stroke(tokens.sidebarSelectionShadow.opacity(0.35), lineWidth: configuration.strokeWidth)
                    }
                }

            SpaceSnapshotIconView(
                icon: item.icon,
                size: configuration.faviconHeight,
                cornerRadius: PinnedTileFaviconLayout.cornerRadius,
                foregroundColor: tokens.primaryText
            )
            .saturation(item.presentationState.shouldDesaturateIcon ? 0.0 : 1.0)
            .opacity(item.presentationState.shouldDesaturateIcon ? 0.8 : 1.0)

            if item.showsSplitOutline {
                PinnedTileSplitGroupOutlineMask(
                    corner: configuration.cornerRadius,
                    thickness: max(1.25, configuration.strokeWidth * 0.7),
                    strokeColor: tokens.accent
                )
                .allowsHitTesting(false)
            }

            if item.showsAudioButton {
                VStack {
                    HStack {
                        Image(systemName: item.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(item.isMuted ? tokens.secondaryText : tokens.primaryText)
                            .frame(width: 22, height: 22)
                            .background(tokens.fieldBackground.opacity(0.88), in: RoundedRectangle(cornerRadius: 7))
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
            }

        }
        .frame(width: tileSize.width, height: tileSize.height, alignment: .center)
        .shadow(
            color: item.presentationState.isSelected ? tokens.sidebarSelectionShadow : .clear,
            radius: item.presentationState.isSelected ? 2 : 0,
            y: item.presentationState.isSelected ? 1 : 0
        )
        .accessibilityIdentifier("essential-shortcut-snapshot-\(item.id.uuidString)")
    }
}
