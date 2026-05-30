import AppKit
import SwiftUI

private enum SidebarDropGuidePalette {
    static var guide: Color {
        Color(nsColor: .systemBlue)
    }

    static func background(colorScheme: ColorScheme) -> Color {
        guide.opacity(colorScheme == .dark ? 0.16 : 0.12)
    }
}

enum SidebarInsertionGuide {
    static let visualCenterY: CGFloat = 3
}

// MARK: - Empty drop zone outlines (dash until hover shows real preview)

/// Dashed tile outline for an empty Essentials row during drag — not a content preview.
struct SidebarEssentialsEmptyDropDashPlaceholder: View {
    let size: CGSize

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let corner = sumiSettings.resolvedCornerRadius(10)
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(SidebarDropGuidePalette.background(colorScheme: colorScheme).opacity(0.55))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    SidebarDropGuidePalette.guide.opacity(0.92),
                    style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [5, 4])
                )
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// Dashed strip for an empty space-pinned area during drag — not a row preview.
struct SidebarPinnedEmptyDropDashPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let corner: CGFloat = 6
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(SidebarDropGuidePalette.background(colorScheme: colorScheme).opacity(0.45))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    SidebarDropGuidePalette.guide.opacity(0.92),
                    style: StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [7, 5])
                )
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(SidebarRowLayout.rowHeight - 10, 20))
        .padding(.vertical, 5)
        .accessibilityHidden(true)
    }
}
