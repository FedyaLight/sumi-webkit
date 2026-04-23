import SwiftUI

struct DownloadsPopoverView: View {
    @ObservedObject var downloadManager: DownloadManager
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        VStack(spacing: 0) {
            if downloadManager.items.isEmpty {
                DownloadsEmptyView()
                    .frame(height: 70)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(downloadManager.items) { item in
                            DownloadRowView(
                                item: item,
                                downloadManager: downloadManager
                            )
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 330)
            }

            Divider()
                .padding(.horizontal, 26)
                .overlay(tokens.separator.opacity(0.65))

            HStack(spacing: 8) {
                DownloadsFooterActionButton(
                    title: "Open Downloads Folder",
                    imageName: "OpenDownloadsFolderIcon",
                    tokens: tokens,
                    action: downloadManager.openDownloadsFolder
                )

                Spacer(minLength: 8)

                DownloadsFooterIconButton(
                    imageName: "ClearDownloadsIcon",
                    help: "Clear Downloads",
                    isEnabled: downloadManager.hasInactiveDownloads,
                    tokens: tokens,
                    action: downloadManager.clearInactiveDownloads
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 360)
    }
}

private struct DownloadsFooterActionButton: View {
    let title: String
    let imageName: String
    let tokens: ChromeThemeTokens
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(imageName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)

                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(DownloadsFooterButtonStyle(isHovering: isHovering, tokens: tokens))
        .foregroundStyle(tokens.primaryText)
        .onHover { isHovering = $0 }
    }
}

private struct DownloadsFooterIconButton: View {
    let imageName: String
    let help: String
    let isEnabled: Bool
    let tokens: ChromeThemeTokens
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Image(imageName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(DownloadsFooterButtonStyle(isHovering: isHovering && isEnabled, tokens: tokens))
        .foregroundStyle(isEnabled ? tokens.secondaryText : tokens.tertiaryText)
        .opacity(isEnabled ? 1 : 0.55)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(Text(help))
        .onHover { isHovering = $0 }
    }
}

private struct DownloadsFooterButtonStyle: ButtonStyle {
    let isHovering: Bool
    let tokens: ChromeThemeTokens

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return tokens.fieldBackground.opacity(0.9)
        }
        if isHovering {
            return tokens.commandPaletteRowHover
        }
        return .clear
    }
}
