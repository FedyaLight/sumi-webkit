import AppKit
import SwiftUI

struct DownloadRowView: View {
    @ObservedObject var item: DownloadItem
    @ObservedObject var downloadManager: DownloadManager
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovering = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(item.statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            actionButtons
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isHovering ? tokens.commandPaletteRowHover : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            if item.state == .completed {
                downloadManager.open(item)
            }
        }
        .onDrag {
            guard item.state == .completed,
                  let url = item.localURL,
                  FileManager.default.fileExists(atPath: url.path)
            else {
                return NSItemProvider()
            }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if item.isActive {
            ZStack {
                Image("DownloadsActiveIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .foregroundStyle(tokens.primaryText)
                DownloadProgressRing(progress: item.progressFraction, size: 30)
            }
        } else {
            Image(nsImage: item.icon(size: NSSize(width: 28, height: 28)))
                .resizable()
                .scaledToFit()
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if item.isActive {
            rowButton(systemImage: "xmark", help: "Cancel") {
                downloadManager.cancel(item)
            }
        } else if item.canRetry {
            rowButton(systemImage: "arrow.clockwise", help: "Retry") {
                downloadManager.retry(item)
            }
        } else if item.state == .completed {
            rowButton(systemImage: "magnifyingglass", help: "Show in Finder") {
                downloadManager.reveal(item)
            }
        }
    }

    private func rowButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tokens.secondaryText)
        .background(isHovering ? tokens.fieldBackground : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help(help)
    }

    private var statusColor: Color {
        switch item.state {
        case .failed:
            return .red.opacity(0.82)
        case .cancelled:
            return tokens.tertiaryText
        default:
            return tokens.secondaryText
        }
    }
}
