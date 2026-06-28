import SwiftUI

struct SpaceSnapshotPinnedTileView: View {
    let item: SpaceShortcutSnapshot
    let tileSize: CGSize
    let configuration: PinnedTabsConfiguration
    let tokens: ChromeThemeTokens

    var body: some View {
        ZStack {
            PinnedTileVisual(
                tabIcon: pinnedTileTabIcon,
                glyphText: pinnedTileGlyphText,
                chromeTemplateSystemImageName: pinnedTileChromeTemplateSystemImageName,
                presentationState: item.presentationState,
                showsSplitGroupOutline: item.showsSplitOutline,
                configuration: configuration
            )

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

    private var pinnedTileTabIcon: Image {
        if case .image(let image) = item.icon {
            return image
        }

        return Image(systemName: SumiPersistentGlyph.launcherSystemImageFallback)
    }

    private var pinnedTileGlyphText: String? {
        if case .emoji(let emoji) = item.icon {
            return emoji
        }

        return nil
    }

    private var pinnedTileChromeTemplateSystemImageName: String? {
        if case .system(let systemName) = item.icon {
            return systemName
        }

        return nil
    }
}
