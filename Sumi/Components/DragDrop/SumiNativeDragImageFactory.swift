import SwiftUI
import AppKit

enum SumiNativeDragPreviewStyle {
    case essentialsTile
    case sourceSnapshot
    case row
    case folderRow
}

extension SidebarDragPreviewKind {
    var nativeStyle: SumiNativeDragPreviewStyle {
        switch self {
        case .row:
            .row
        case .essentialsTile:
            .essentialsTile
        case .folderRow:
            .folderRow
        }
    }
}

struct SumiNativeDragPreviewDescriptor {
    let item: SumiDragItem
    let previewIcon: Image?
    let sourceZone: DropZoneID
    let sourceSize: CGSize
    let sourceOffsetFromBottomLeading: CGPoint
    let pinnedConfig: PinnedTabsConfiguration
    let folderGlyphPresentation: SumiFolderGlyphPresentationState?
    let folderGlyphPalette: SumiFolderGlyphPalette?

    init(
        item: SumiDragItem,
        previewIcon: Image?,
        sourceZone: DropZoneID,
        sourceSize: CGSize,
        sourceOffsetFromBottomLeading: CGPoint,
        pinnedConfig: PinnedTabsConfiguration,
        folderGlyphPresentation: SumiFolderGlyphPresentationState? = nil,
        folderGlyphPalette: SumiFolderGlyphPalette? = nil
    ) {
        self.item = item
        self.previewIcon = previewIcon
        self.sourceZone = sourceZone
        self.sourceSize = sourceSize
        self.sourceOffsetFromBottomLeading = sourceOffsetFromBottomLeading
        self.pinnedConfig = pinnedConfig
        self.folderGlyphPresentation = folderGlyphPresentation
        self.folderGlyphPalette = folderGlyphPalette
    }
}

@MainActor
final class SumiNativeDragImageFactory {
    static let shared = SumiNativeDragImageFactory()

    private init() {}

    func image(
        for style: SumiNativeDragPreviewStyle,
        descriptor: SumiNativeDragPreviewDescriptor,
        sourceView: NSView?
    ) -> NSImage {
        let size = self.size(for: style, descriptor: descriptor)

        if style == .sourceSnapshot,
           let sourceView,
           let snapshot = snapshotImage(from: sourceView, size: size) {
            return snapshot
        }

        let view = SumiNativeDragPreviewRenderable(
            descriptor: descriptor,
            style: style,
            size: size
        )
        return render(view, size: size)
    }

    func size(for style: SumiNativeDragPreviewStyle, descriptor: SumiNativeDragPreviewDescriptor) -> CGSize {
        switch style {
        case .essentialsTile:
            if descriptor.sourceZone == .essentials,
               descriptor.sourceSize.width > 0,
               descriptor.sourceSize.height > 0 {
                return descriptor.sourceSize
            }
            return CGSize(
                width: descriptor.pinnedConfig.minWidth,
                height: descriptor.pinnedConfig.height
            )
        case .sourceSnapshot:
            if descriptor.sourceZone == .essentials {
                return CGSize(
                    width: descriptor.pinnedConfig.minWidth,
                    height: descriptor.pinnedConfig.height
                )
            }
            fallthrough
        case .row, .folderRow:
            let width = descriptor.sourceSize.width > 0 ? descriptor.sourceSize.width : 200
            let height = descriptor.sourceSize.height > 0 ? descriptor.sourceSize.height : 36
            return CGSize(width: width, height: height)
        }
    }

    func offset(for style: SumiNativeDragPreviewStyle, descriptor: SumiNativeDragPreviewDescriptor) -> CGPoint {
        let size = self.size(for: style, descriptor: descriptor)
        switch style {
        case .essentialsTile:
            if descriptor.sourceZone == .essentials {
                return clampedOffset(descriptor.sourceOffsetFromBottomLeading, in: size)
            }
            return CGPoint(x: size.width / 2, y: size.height / 2)
        case .sourceSnapshot, .row, .folderRow:
            return clampedOffset(descriptor.sourceOffsetFromBottomLeading, in: size)
        }
    }

    private func clampedOffset(_ offset: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: max(0, min(offset.x, size.width)),
            y: max(0, min(offset.y, size.height))
        )
    }

    private func snapshotImage(from view: NSView, size: CGSize) -> NSImage? {
        guard size.width > 0, size.height > 0,
              let superview = view.superview else {
            return nil
        }

        let rect = view.convert(view.bounds, to: superview)
        guard rect.width > 0, rect.height > 0,
              let rep = superview.bitmapImageRepForCachingDisplay(in: rect) else {
            return nil
        }

        superview.cacheDisplay(in: rect, to: rep)
        guard bitmapHasVisiblePixels(rep) else {
            return nil
        }
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
    }

    private func bitmapHasVisiblePixels(_ rep: NSBitmapImageRep) -> Bool {
        let width = max(rep.pixelsWide, 1)
        let height = max(rep.pixelsHigh, 1)
        let samplePoints = [
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.25, y: 0.5),
            CGPoint(x: 0.75, y: 0.5),
            CGPoint(x: 0.5, y: 0.25),
            CGPoint(x: 0.5, y: 0.75),
        ]

        for point in samplePoints {
            let x = max(0, min(Int(CGFloat(width - 1) * point.x), width - 1))
            let y = max(0, min(Int(CGFloat(height - 1) * point.y), height - 1))
            if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                return true
            }
        }
        return false
    }

    private func render<V: View>(_ view: V, size: CGSize) -> NSImage {
        let hostingView = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return NSImage(size: size)
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}

private struct SumiNativeDragPreviewRenderable: View {
    let descriptor: SumiNativeDragPreviewDescriptor
    let style: SumiNativeDragPreviewStyle
    let size: CGSize

    var body: some View {
        switch style {
        case .essentialsTile:
            essentialsTile
        case .sourceSnapshot:
            descriptor.sourceZone == .essentials ? AnyView(essentialsTile) : AnyView(rowPreview)
        case .row:
            rowPreview
        case .folderRow:
            AnyView(folderRowPreview)
        }
    }

    private var essentialsTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: descriptor.pinnedConfig.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.95))

            iconView
                .frame(
                    width: descriptor.pinnedConfig.faviconHeight,
                    height: descriptor.pinnedConfig.faviconHeight
                )
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: descriptor.pinnedConfig.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }

    private var rowPreview: some View {
        HStack(spacing: 8) {
            iconView
                .frame(width: 16, height: 16)

            SumiTabTitleLabel(
                title: descriptor.item.title,
                font: .systemFont(ofSize: 13, weight: .medium),
                textColor: .primary,
                animated: false
            )
        }
        .padding(.horizontal, 12)
        .frame(width: size.width, height: size.height, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }

    @ViewBuilder
    private var folderRowPreview: some View {
        if let presentation = descriptor.folderGlyphPresentation,
           let palette = descriptor.folderGlyphPalette {
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Color.clear
                        .frame(width: SidebarRowLayout.folderTitleLeading, height: SidebarRowLayout.rowHeight)
                    SumiFolderGlyphView(
                        presentation: presentation,
                        palette: palette
                    )
                    .frame(
                        width: SidebarRowLayout.folderGlyphSize,
                        height: SidebarRowLayout.folderGlyphSize,
                        alignment: .center
                    )
                    .offset(x: SidebarRowLayout.folderHeaderGlyphCenteringOffset)
                }
                .frame(width: SidebarRowLayout.folderTitleLeading, alignment: .leading)

                Text(descriptor.item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, SidebarRowLayout.leadingInset)
            .padding(.trailing, SidebarRowLayout.trailingInset)
            .frame(width: size.width, height: size.height, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        } else {
            rowPreview
        }
    }

    @ViewBuilder
    private var iconView: some View {
        if let previewIcon = descriptor.previewIcon {
            previewIcon
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
        } else {
            Image(systemName: "globe")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }
}
