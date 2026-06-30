import AppKit
import SwiftUI

struct SumiBoostActionButton: View {
    let title: String
    var trailingSystemImage: String?
    var trailingText: String?
    var valueText: String?
    var isActive = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Group {
                if valueText == nil && trailingSystemImage == nil && trailingText == nil {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let valueText {
                            Text(valueText)
                                .font(.system(size: 13, weight: .semibold))
                        } else if let trailingSystemImage {
                            Image(systemName: trailingSystemImage)
                                .font(.system(size: 16, weight: .medium))
                        } else if let trailingText {
                            Text(trailingText)
                                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        }
                    }
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        isActive
            ? SumiBoostEditorStyle.primaryText(for: colorScheme)
            : SumiBoostEditorStyle.buttonBackground(for: colorScheme)
    }

    private var foreground: Color {
        isActive
            ? SumiBoostEditorStyle.primaryBackground(for: colorScheme)
            : SumiBoostEditorStyle.primaryText(for: colorScheme)
    }
}
