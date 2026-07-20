import AppKit
import SumiDomain
import SwiftUI

enum SidebarDragPresentationProjection {
    static let transformAnimation = Animation.easeInOut(duration: 0.15)

    static func resolvedPreviewKind(
        baseKind: SidebarDragPreviewKind?,
        hoveredSlot: DropZoneSlot,
        previewAssets: [SidebarDragPreviewKind: SidebarDragPreviewAsset]
    ) -> SidebarDragPreviewKind? {
        if baseKind == .folderRow {
            return .folderRow
        }

        if case .essentials = hoveredSlot,
           previewAssets[.essentialsTile] != nil {
            return .essentialsTile
        }

        if case .spacePinned = hoveredSlot,
           previewAssets[.row] != nil {
            return .row
        }

        if case .spaceRegular = hoveredSlot,
           previewAssets[.row] != nil {
            return .row
        }

        if case .folder = hoveredSlot,
           previewAssets[.row] != nil {
            return .row
        }

        return baseKind
    }

    static func resolvedPreviewKind(
        model: SidebarDragPreviewModel,
        hoveredSlot: DropZoneSlot
    ) -> SidebarDragPreviewKind {
        if model.baseKind == .folderRow || model.item.kind == .folder {
            return .folderRow
        }

        switch hoveredSlot {
        case .essentials:
            return .essentialsTile
        case .spacePinned, .spaceRegular, .folder:
            return .row
        case .empty:
            return model.baseKind
        }
    }

    static func anchorOffset(
        for model: SidebarDragPreviewModel,
        previewKind: SidebarDragPreviewKind,
        in size: CGSize
    ) -> CGPoint {
        if model.item.kind == .splitGroup,
           model.sourceZone == .essentials,
           previewKind == .row {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        return model.anchorOffset(in: size)
    }
}

struct SidebarFloatingDragPreviewContext {
    let currentProfileID: () -> UUID?
    let essentialPins: (UUID) -> [ShortcutPin]
}

struct SidebarFloatingDragPreview: View {
    @ObservedObject private var dragState: SidebarDragState
    @ObservedObject private var locationTracker: SidebarDragLocationTracker
    private let browserContext: SidebarFloatingDragPreviewContext
    @Environment(BrowserWindowState.self) private var windowState

    init(
        sidebarDragState: SidebarDragState,
        browserContext: SidebarFloatingDragPreviewContext
    ) {
        self._dragState = ObservedObject(wrappedValue: sidebarDragState)
        self._locationTracker = ObservedObject(wrappedValue: sidebarDragState.locationTracker)
        self.browserContext = browserContext
    }

    var body: some View {
        Group {
            if shouldRenderPreview {
                GeometryReader { geo in
                    if let previewModel = dragState.previewModel,
                       let dragLocation = currentDragLocation {
                        let previewKind = SidebarDragPresentationProjection.resolvedPreviewKind(
                            model: previewModel,
                            hoveredSlot: dragState.hoveredSlot
                        )
                        let size = resolvedSize(for: previewKind, model: previewModel)
                        let anchor = SidebarDragPresentationProjection.anchorOffset(
                            for: previewModel,
                            previewKind: previewKind,
                            in: size
                        )

                        previewContent(kind: previewKind, model: previewModel, size: size)
                            .frame(width: size.width, height: size.height)
                            .position(
                                x: (dragLocation.x - geo.frame(in: .global).minX) - anchor.x + (size.width / 2),
                                y: (dragLocation.y - geo.frame(in: .global).minY) - anchor.y + (size.height / 2)
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            .animation(SidebarDragPresentationProjection.transformAnimation, value: previewKind)
                            .animation(SidebarDragPresentationProjection.transformAnimation, value: size)
                            .animation(SidebarDragPresentationProjection.transformAnimation, value: dragState.hoveredSlot)
                    } else if let asset = currentAsset,
                              let dragLocation = currentDragLocation {
                        fallbackImagePreview(asset: asset)
                            .position(
                                x: (dragLocation.x - geo.frame(in: .global).minX) - asset.anchorOffset.x + (asset.size.width / 2),
                                y: (dragLocation.y - geo.frame(in: .global).minY) - asset.anchorOffset.y + (asset.size.height / 2)
                            )
                            .animation(SidebarDragPresentationProjection.transformAnimation, value: currentPreviewKind)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func fallbackImagePreview(asset: SidebarDragPreviewAsset) -> some View {
        Image(nsImage: asset.image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .frame(width: asset.size.width, height: asset.size.height)
    }

    @ViewBuilder
    private func previewContent(
        kind: SidebarDragPreviewKind,
        model: SidebarDragPreviewModel,
        size: CGSize
    ) -> some View {
        ZStack {
            essentialsPreview(model: model)
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            .opacity(kind == .essentialsTile ? 1 : 0)
            .scaleEffect(kind == .essentialsTile ? 1 : 0.97)

            rowPreview(model: model)
            .frame(width: size.width, height: size.height)
            .opacity(kind == .row ? 1 : 0)
            .scaleEffect(kind == .row ? 1 : 0.97)

            SidebarFolderRowPreviewVisual(
                title: model.item.title,
                folderGlyphPresentation: model.folderGlyphPresentation,
                folderGlyphPalette: model.folderGlyphPalette
            )
            .frame(width: size.width, height: size.height)
            .opacity(kind == .folderRow ? 1 : 0)
            .scaleEffect(kind == .folderRow ? 1 : 0.97)
        }
        .geometryGroup()
        .animation(SidebarDragPresentationProjection.transformAnimation, value: kind)
    }

    @ViewBuilder
    private func essentialsPreview(model: SidebarDragPreviewModel) -> some View {
        if let split = model.splitPresentation {
            EssentialSplitCompactVisual(
                icons: split.icons,
                glyphTexts: split.glyphTexts,
                systemImageNames: split.systemImageNames,
                accentColors: split.accentColors,
                isGroupActive: model.shortcutPresentationState?.isSelected == true,
                desaturatesIcons:
                    model.shortcutPresentationState?.shouldDesaturateIcon == true
            )
        } else {
            PinnedTileVisual(
                tabIcon: model.previewIcon ?? Image(systemName: "globe"),
                glyphText: model.previewGlyphText,
                chromeTemplateSystemImageName: model.chromeTemplateSystemImageName,
                presentationState: model.shortcutPresentationState ?? .launcherOnly,
                isHovered: false
            )
        }
    }

    @ViewBuilder
    private func rowPreview(model: SidebarDragPreviewModel) -> some View {
        if let split = model.splitPresentation {
            SidebarSplitRowPreviewVisual(
                icons: split.icons,
                glyphTexts: split.glyphTexts,
                systemImageNames: split.systemImageNames,
                titles: split.titles,
                desaturatesIcons:
                    model.shortcutPresentationState?.shouldDesaturateIcon == true
            )
        } else {
            SidebarTabRowPreviewVisual(
                title: model.item.title,
                icon: model.previewIcon ?? Image(systemName: "globe")
            )
        }
    }

    private func resolvedSize(
        for kind: SidebarDragPreviewKind,
        model: SidebarDragPreviewModel
    ) -> CGSize {
        switch kind {
        case .essentialsTile:
            return resolvedEssentialsTileSize(model: model)
        case .row, .folderRow:
            return CGSize(
                width: resolvedRowWidth(model: model),
                height: SidebarRowLayout.rowHeight
            )
        }
    }

    private func resolvedEssentialsTileSize(model: SidebarDragPreviewModel) -> CGSize {
        guard case .essentials(let slot) = dragState.hoveredSlot,
              let location = locationTracker.location,
              let hoveredPage = dragState.hoveredInteractivePage(at: location),
              let metrics = dragState.essentialsLayoutMetricsBySpace[hoveredPage.spaceId]
        else {
            if model.sourceZone == .essentials, model.sourceSize.width > 0, model.sourceSize.height > 0 {
                return model.sourceSize
            }
            return CGSize(width: PinnedTileMetrics.minWidth, height: PinnedTileMetrics.height)
        }

        let profileId = hoveredPage.profileId
            ?? metrics.profileId
            ?? windowState.currentProfileId
            ?? browserContext.currentProfileID()
        if let slotFrame = metrics.dropSlotFrames.first(where: { $0.slot == slot }),
           slotFrame.frame.width > 0,
           slotFrame.frame.height > 0 {
            return slotFrame.frame.size
        }

        let pins = profileId.map { browserContext.essentialPins($0) } ?? []
        let projection = SidebarEssentialsProjectionPolicy.make(
            items: pins.map(SidebarEssentialVisualItem.pin),
            width: metrics.frame.width,
            dragState: dragState
        )

        if let row = projection.rows.first(where: { row in
            let rowCount = max(row.items.count, 1)
            return slot >= row.startSlot && slot < row.startSlot + rowCount
        }) {
            return row.tileSize
        }

        return projection.rows.last?.tileSize
            ?? projection.tileSize
    }

    private func resolvedRowWidth(model: SidebarDragPreviewModel) -> CGFloat {
        if let targetWidth = activeRowTargetWidth(), targetWidth > 0 {
            return targetWidth
        }

        if model.baseKind == .row || model.baseKind == .folderRow,
           model.sourceSize.width > 0 {
            return model.sourceSize.width
        }

        return max(windowState.sidebarContentWidth, BrowserWindowState.sidebarContentWidth(for: windowState.sidebarWidth))
    }

    private func activeRowTargetWidth() -> CGFloat? {
        switch dragState.hoveredSlot {
        case .spacePinned(let spaceId, _):
            return dragState.sectionFrame(for: .spacePinned, in: spaceId)?.width
        case .spaceRegular(let spaceId, _):
            return dragState.regularListHitTargets[spaceId]?.frame.width
                ?? dragState.sectionFrame(for: .spaceRegular, in: spaceId)?.width
        case .folder(let folderId, _):
            guard let target = dragState.folderDropTargets[folderId] else { return nil }
            return target.headerFrame?.width
                ?? target.bodyFrame?.width
                ?? target.afterFrame?.width
        case .essentials, .empty:
            return nil
        }
    }

    private var currentAsset: SidebarDragPreviewAsset? {
        guard let currentPreviewKind else { return nil }
        return dragState.previewAssets[currentPreviewKind]
    }

    private var currentDragLocation: CGPoint? {
        locationTracker.previewLocation ?? locationTracker.location
    }

    private var shouldRenderPreview: Bool {
        currentDragLocation != nil && (dragState.previewModel != nil || currentAsset != nil)
    }

    private var currentPreviewKind: SidebarDragPreviewKind? {
        SidebarDragPresentationProjection.resolvedPreviewKind(
            baseKind: dragState.previewKind,
            hoveredSlot: dragState.hoveredSlot,
            previewAssets: dragState.previewAssets
        )
    }
}

private struct SidebarSplitRowPreviewVisual: View {
    let icons: [Image]
    let glyphTexts: [String?]
    let systemImageNames: [String?]
    let titles: [String]
    let desaturatesIcons: Bool

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    var body: some View {
        GeometryReader { geometry in
            let count = max(min(icons.count, SplitGroup.maximumMembers), 1)
            let segmentWidth = max(
                0,
                (geometry.size.width - CGFloat(count - 1)) / CGFloat(count)
            )
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    SplitGroupSegmentLabel(
                        title: titles.indices.contains(index)
                            ? titles[index] : String(localized: "Tab"),
                        trailingPadding: 7,
                        textColor: tokens.primaryText
                    ) {
                        previewIcon(at: index)
                            .saturation(desaturatesIcons ? 0 : 1)
                            .opacity(desaturatesIcons ? 0.8 : 1)
                    }
                    .frame(width: segmentWidth)

                    if index < count - 1 {
                        Rectangle()
                            .fill(tokens.separator.opacity(0.7))
                            .frame(width: 1, height: 22)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.sidebarRowHover)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
    }

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    @ViewBuilder
    private func previewIcon(at index: Int) -> some View {
        if glyphTexts.indices.contains(index),
           let glyph = glyphTexts[index] {
            Text(glyph)
                .font(.system(size: 16))
                .frame(width: 16, height: 16)
        } else if systemImageNames.indices.contains(index),
                  let systemName = systemImageNames[index] {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .frame(width: 16, height: 16)
        } else {
            (icons.indices.contains(index)
                ? icons[index] : Image(systemName: "globe"))
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .clipShape(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
        }
    }
}

struct SidebarTabRowPreviewVisual: View {
    let title: String
    let icon: Image

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    var body: some View {
        HStack(spacing: SidebarRowLayout.iconTrailingSpacing) {
            icon
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: SidebarRowLayout.faviconSize, height: SidebarRowLayout.faviconSize)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            SumiTabTitleLabel(
                title: title,
                font: .systemFont(ofSize: 13, weight: .medium),
                textColor: tokens.primaryText,
                animated: false
            )
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.sidebarRowHover)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
    }

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }
}

private struct SidebarFolderRowPreviewVisual: View {
    let title: String
    let folderGlyphPresentation: SumiFolderGlyphPresentationState?
    let folderGlyphPalette: SumiFolderGlyphPalette?

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                Color.clear
                    .frame(width: SidebarRowLayout.folderTitleLeading, height: SidebarRowLayout.rowHeight)
                folderIcon
                    .frame(
                        width: SidebarRowLayout.folderGlyphSize,
                        height: SidebarRowLayout.folderGlyphSize,
                        alignment: .center
                    )
                    .offset(x: SidebarRowLayout.folderHeaderGlyphCenteringOffset)
            }
            .frame(width: SidebarRowLayout.folderTitleLeading, alignment: .leading)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tokens.primaryText)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.sidebarRowHover)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
    }

    @ViewBuilder
    private var folderIcon: some View {
        if let folderGlyphPresentation,
           let folderGlyphPalette {
            SumiFolderGlyphView(
                presentation: folderGlyphPresentation,
                palette: folderGlyphPalette
            )
        } else {
            Image(systemName: "folder.fill")
                .font(.system(size: SidebarRowLayout.faviconSize, weight: .medium))
                .foregroundStyle(tokens.primaryText)
        }
    }

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }
}
