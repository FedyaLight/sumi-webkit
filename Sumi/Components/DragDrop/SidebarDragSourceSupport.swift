import SwiftUI

enum SidebarDragSourceExclusionZone {
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

struct SidebarDragSourceConfiguration {
    let item: SumiDragItem
    let sourceZone: DropZoneID
    let previewKind: SidebarDragPreviewKind
    let previewIcon: Image?
    let chromeTemplateSystemImageName: String?
    let pinnedConfig: PinnedTabsConfiguration
    let previewPresentationState: ShortcutPresentationState?
    let folderGlyphPresentation: SumiFolderGlyphPresentationState?
    let folderGlyphPalette: SumiFolderGlyphPalette?
    let exclusionZones: [SidebarDragSourceExclusionZone]
    let onActivate: (() -> Void)?
    let isEnabled: Bool

    init(
        item: SumiDragItem,
        sourceZone: DropZoneID,
        previewKind: SidebarDragPreviewKind,
        previewIcon: Image? = nil,
        chromeTemplateSystemImageName: String? = nil,
        pinnedConfig: PinnedTabsConfiguration = .large,
        previewPresentationState: ShortcutPresentationState? = nil,
        folderGlyphPresentation: SumiFolderGlyphPresentationState? = nil,
        folderGlyphPalette: SumiFolderGlyphPalette? = nil,
        exclusionZones: [SidebarDragSourceExclusionZone] = [],
        onActivate: (() -> Void)? = nil,
        isEnabled: Bool = true
    ) {
        self.item = item
        self.sourceZone = sourceZone
        self.previewKind = previewKind
        self.previewIcon = previewIcon
        self.chromeTemplateSystemImageName = chromeTemplateSystemImageName
        self.pinnedConfig = pinnedConfig
        self.previewPresentationState = previewPresentationState
        self.folderGlyphPresentation = folderGlyphPresentation
        self.folderGlyphPalette = folderGlyphPalette
        self.exclusionZones = exclusionZones
        self.onActivate = onActivate
        self.isEnabled = isEnabled
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
        let descriptor = SumiNativeDragPreviewDescriptor(
            item: configuration.item,
            previewIcon: configuration.previewIcon,
            sourceZone: configuration.sourceZone,
            sourceSize: sourceSize,
            sourceOffsetFromBottomLeading: point,
            pinnedConfig: configuration.pinnedConfig,
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
            chromeTemplateSystemImageName: configuration.chromeTemplateSystemImageName,
            sourceSize: sourceSize,
            normalizedTopLeadingAnchor: SidebarDragPreviewModel.normalizedTopLeadingAnchor(
                fromBottomLeading: point,
                in: sourceSize
            ),
            pinnedConfig: configuration.pinnedConfig,
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

    private static func buildPreviewAssets(
        descriptor: SumiNativeDragPreviewDescriptor,
        previewKind: SidebarDragPreviewKind
    ) -> [SidebarDragPreviewKind: SidebarDragPreviewAsset] {
        let factory = SumiNativeDragImageFactory.shared
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

        return assets
    }
}
