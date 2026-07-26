import SwiftUI

/// Zen parity: the dragged row stays in place, dimmed, while the drop
/// indicator line shows the insertion point.
enum SidebarDragSourceDim {
    static let opacity: Double = 0.5
}

enum SidebarDragSourceExclusionZone: Equatable {
    case leadingStrip(CGFloat)
    case trailingStrip(CGFloat)
    case fixedRect(CGRect)
    case topLeadingSquare(size: CGFloat, inset: CGFloat = 0)
    case topTrailingSquare(size: CGFloat, inset: CGFloat = 0)

    func contains(_ point: CGPoint, in bounds: CGRect) -> Bool {
        switch self {
        case .leadingStrip(let width):
            return CGRect(x: 0, y: 0, width: width, height: bounds.height).contains(point)
        case .trailingStrip(let width):
            return CGRect(
                x: max(bounds.width - width, 0),
                y: 0,
                width: min(width, bounds.width),
                height: bounds.height
            ).contains(point)
        case .fixedRect(let rect):
            return rect.contains(point)
        case .topLeadingSquare(let size, let inset):
            return CGRect(
                x: inset,
                y: max(bounds.height - size - inset, 0),
                width: size,
                height: size
            ).contains(point)
        case .topTrailingSquare(let size, let inset):
            return CGRect(
                x: max(bounds.width - size - inset, 0),
                y: max(bounds.height - size - inset, 0),
                width: size,
                height: size
            ).contains(point)
        }
    }
}

/// Maps a drag handle that occupies only part of a visual item back into the
/// coordinate space of the whole preview.
struct SidebarDragPreviewSourceGeometry: Equatable {
    let size: CGSize
    let localOrigin: CGPoint

    func anchor(forLocalPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: localOrigin.x + point.x,
            y: localOrigin.y + point.y
        )
    }
}

struct SidebarDragSourceConfiguration {
    let item: SumiDragItem
    let sourceZone: DropZoneID
    let previewKind: SidebarDragPreviewKind
    let previewIcon: Image?
    let previewBackdrop: Image?
    let previewGlyphText: String?
    let splitPresentation: SidebarSplitDragPresentation?
    let chromeTemplateSystemImageName: String?
    let previewPresentationState: ShortcutPresentationState?
    let folderGlyphPresentation: SumiFolderGlyphPresentationState?
    let folderGlyphPalette: SumiFolderGlyphPalette?
    let previewSourceGeometry: SidebarDragPreviewSourceGeometry?
    let exclusionZones: [SidebarDragSourceExclusionZone]
    let isEnabled: Bool

    init(
        item: SumiDragItem,
        sourceZone: DropZoneID,
        previewKind: SidebarDragPreviewKind,
        previewIcon: Image? = nil,
        previewBackdrop: Image? = nil,
        previewGlyphText: String? = nil,
        splitPresentation: SidebarSplitDragPresentation? = nil,
        chromeTemplateSystemImageName: String? = nil,
        previewPresentationState: ShortcutPresentationState? = nil,
        folderGlyphPresentation: SumiFolderGlyphPresentationState? = nil,
        folderGlyphPalette: SumiFolderGlyphPalette? = nil,
        previewSourceGeometry: SidebarDragPreviewSourceGeometry? = nil,
        exclusionZones: [SidebarDragSourceExclusionZone] = [],
        isEnabled: Bool = true
    ) {
        self.item = item
        self.sourceZone = sourceZone
        self.previewKind = previewKind
        self.previewIcon = previewIcon
        self.previewBackdrop = previewBackdrop
        self.previewGlyphText = previewGlyphText
        self.splitPresentation = splitPresentation
        self.chromeTemplateSystemImageName = chromeTemplateSystemImageName
        self.previewPresentationState = previewPresentationState
        self.folderGlyphPresentation = folderGlyphPresentation
        self.folderGlyphPalette = folderGlyphPalette
        self.previewSourceGeometry = previewSourceGeometry
        self.exclusionZones = exclusionZones
        self.isEnabled = isEnabled
    }

    func replacingExclusionZones(
        _ exclusionZones: [SidebarDragSourceExclusionZone]
    ) -> SidebarDragSourceConfiguration {
        SidebarDragSourceConfiguration(
            item: item,
            sourceZone: sourceZone,
            previewKind: previewKind,
            previewIcon: previewIcon,
            previewBackdrop: previewBackdrop,
            previewGlyphText: previewGlyphText,
            splitPresentation: splitPresentation,
            chromeTemplateSystemImageName: chromeTemplateSystemImageName,
            previewPresentationState: previewPresentationState,
            folderGlyphPresentation: folderGlyphPresentation,
            folderGlyphPalette: folderGlyphPalette,
            previewSourceGeometry: previewSourceGeometry,
            exclusionZones: exclusionZones,
            isEnabled: isEnabled
        )
    }

    func replacingPreviewSourceGeometry(
        _ previewSourceGeometry: SidebarDragPreviewSourceGeometry?
    ) -> SidebarDragSourceConfiguration {
        SidebarDragSourceConfiguration(
            item: item,
            sourceZone: sourceZone,
            previewKind: previewKind,
            previewIcon: previewIcon,
            previewBackdrop: previewBackdrop,
            previewGlyphText: previewGlyphText,
            splitPresentation: splitPresentation,
            chromeTemplateSystemImageName: chromeTemplateSystemImageName,
            previewPresentationState: previewPresentationState,
            folderGlyphPresentation: folderGlyphPresentation,
            folderGlyphPalette: folderGlyphPalette,
            previewSourceGeometry: previewSourceGeometry,
            exclusionZones: exclusionZones,
            isEnabled: isEnabled
        )
    }
}

struct SidebarDragPreviewSession {
    let previewAssets: [SidebarDragPreviewKind: SidebarDragPreviewAsset]
    let previewModel: SidebarDragPreviewModel
    let primaryAsset: SidebarDragPreviewAsset
}

@MainActor
enum SidebarDragPreviewSessionFactory {
    static func make(
        configuration: SidebarDragSourceConfiguration,
        sourceSize: CGSize,
        sourceOffsetFromBottomLeading point: CGPoint
    ) -> SidebarDragPreviewSession? {
        let sourceAnchor = resolvedSourceAnchor(
            for: configuration,
            sourceSize: sourceSize,
            pointerAnchor: point
        )
        let descriptor = SumiNativeDragPreviewDescriptor(
            item: configuration.item,
            previewIcon: configuration.previewIcon,
            sourceZone: configuration.sourceZone,
            sourceSize: sourceSize,
            sourceOffsetFromBottomLeading: sourceAnchor,
            folderGlyphPresentation: configuration.folderGlyphPresentation,
            folderGlyphPalette: configuration.folderGlyphPalette
        )
        let previewAssets = buildPreviewAssets(
            descriptor: descriptor,
            previewKind: configuration.previewKind
        )
        guard let primaryAsset = previewAssets[configuration.previewKind] else { return nil }

        let model = SidebarDragPreviewModel(
            item: configuration.item,
            sourceZone: configuration.sourceZone,
            baseKind: configuration.previewKind,
            previewIcon: configuration.previewIcon,
            previewBackdrop: configuration.previewBackdrop,
            previewGlyphText: configuration.previewGlyphText,
            splitPresentation: configuration.splitPresentation,
            chromeTemplateSystemImageName: configuration.chromeTemplateSystemImageName,
            sourceSize: sourceSize,
            normalizedTopLeadingAnchor: SidebarDragPreviewModel.normalizedTopLeadingAnchor(
                fromBottomLeading: sourceAnchor,
                in: sourceSize
            ),
            shortcutPresentationState: configuration.previewPresentationState,
            folderGlyphPresentation: configuration.folderGlyphPresentation,
            folderGlyphPalette: configuration.folderGlyphPalette
        )

        return SidebarDragPreviewSession(
            previewAssets: previewAssets,
            previewModel: model,
            primaryAsset: primaryAsset
        )
    }

    private static func resolvedSourceAnchor(
        for configuration: SidebarDragSourceConfiguration,
        sourceSize: CGSize,
        pointerAnchor: CGPoint
    ) -> CGPoint {
        guard case .essentials = configuration.sourceZone else {
            return pointerAnchor
        }
        return CGPoint(
            x: sourceSize.width / 2,
            y: sourceSize.height / 2
        )
    }

    private static func buildPreviewAssets(
        descriptor: SumiNativeDragPreviewDescriptor,
        previewKind: SidebarDragPreviewKind
    ) -> [SidebarDragPreviewKind: SidebarDragPreviewAsset] {
        let factory = SumiNativeDragImageFactory()
        var assets: [SidebarDragPreviewKind: SidebarDragPreviewAsset] = [:]

        func insert(_ kind: SidebarDragPreviewKind) {
            let style = kind.nativeStyle
            let size = factory.size(for: style, descriptor: descriptor)
            assets[kind] = SidebarDragPreviewAsset(
                image: factory.image(for: style, descriptor: descriptor, sourceView: nil),
                size: size,
                anchorOffset: factory.offset(for: style, descriptor: descriptor)
            )
        }

        insert(previewKind)
        if previewKind != .folderRow {
            insert(.row)
            insert(.essentialsTile)
        }

        return assets
    }
}
