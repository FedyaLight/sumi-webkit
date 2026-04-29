import AppKit
import SwiftUI

enum SidebarDragPreviewKind: Hashable {
    case row
    case essentialsTile
    case folderRow
}

struct SidebarDragPreviewAsset {
    let image: NSImage
    let size: CGSize
    let anchorOffset: CGPoint
}

struct SidebarDragPreviewModel {
    let item: SumiDragItem
    let sourceZone: DropZoneID
    let baseKind: SidebarDragPreviewKind
    let previewIcon: Image?
    let chromeTemplateSystemImageName: String?
    let sourceSize: CGSize
    let normalizedTopLeadingAnchor: CGPoint
    let pinnedConfig: PinnedTabsConfiguration
    let shortcutPresentationState: ShortcutPresentationState?
    let folderGlyphPresentation: SumiFolderGlyphPresentationState?
    let folderGlyphPalette: SumiFolderGlyphPalette?

    func anchorOffset(in size: CGSize) -> CGPoint {
        CGPoint(
            x: max(0, min(normalizedTopLeadingAnchor.x, 1)) * size.width,
            y: max(0, min(normalizedTopLeadingAnchor.y, 1)) * size.height
        )
    }

    static func normalizedTopLeadingAnchor(
        fromBottomLeading point: CGPoint,
        in sourceSize: CGSize
    ) -> CGPoint {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        return CGPoint(
            x: max(0, min(point.x / sourceSize.width, 1)),
            y: max(0, min((sourceSize.height - point.y) / sourceSize.height, 1))
        )
    }
}
