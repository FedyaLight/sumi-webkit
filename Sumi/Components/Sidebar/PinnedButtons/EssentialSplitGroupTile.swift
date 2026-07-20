import SumiDomain
import SwiftUI

struct EssentialSplitGroupTile: View {
    let group: SplitGroup
    let pinsByID: [UUID: ShortcutPin]
    let selection: SidebarWindowSelectionQuery
    let selectionSnapshot: SidebarWindowSelectionSnapshot
    let faviconImageReader: any BrowserFaviconImageReading
    let splitLayout: SplitLayoutService
    let emptySplitCreation: EmptySplitCreationWorkflow
    let groupEditor: SidebarSplitGroupEditorPresentationService
    let groupContextMenuActions: SplitGroupContextMenuActions
    let isAppKitInteractionEnabled: Bool
    let onActivateMember: (SplitMemberID) -> Void
    let onUnloadGroup: () -> Void

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
    @State private var loadedAccentColors: [UUID: Color] = [:]
    @State private var accentRefreshID = UUID()
    @StateObject private var storedFaviconLoader = SidebarStoredFaviconLoader()

    var body: some View {
        Group {
            if let iconAsset = group.iconAsset,
               let activationMember = preferredActivationMember {
                groupIconTile(
                    iconAsset,
                    activationMember: activationMember
                )
            } else {
                memberCompositionTile
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("essential-split-group-\(group.id.uuidString)")
        .task(id: accentLoadKey) {
            await loadAccentColorsIfNeeded()
        }
        .task(id: storedFaviconLoadKey) {
            await loadStoredFavicons()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .faviconCacheUpdated)
        ) { notification in
            for pin in memberPins where pin.iconAsset == nil {
                storedFaviconLoader.invalidateIfNeeded(
                    for: notification,
                    launchURL: pin.launchURL,
                    partition: faviconPartition(for: pin)
                )
            }
            let affected = memberVisuals.filter {
                PinnedTileAccentResolver.faviconUpdate(
                    notification,
                    matches: $0.url
                )
            }
            guard !affected.isEmpty else { return }
            for member in affected {
                loadedAccentColors[member.persistentID] = nil
                PinnedTileAccentResolver.invalidateAccent(for: member.url)
            }
            accentRefreshID = UUID()
        }
    }

    private var memberCompositionTile: some View {
        EssentialSplitCompactVisual(
            icons: memberVisuals.map(\.icon),
            glyphTexts: memberVisuals.map(\.glyphText),
            systemImageNames: memberVisuals.map(\.systemImageName),
            accentColors: memberVisuals.map(\.accentColor),
            isGroupActive: isGroupActive,
            cornerRadius: sumiSettings.resolvedCornerRadius(
                PinnedTileMetrics.cornerRadius
            ),
            idleBackground: tokens.pinnedIdleBackground,
            activeBackground: tokens.pinnedActiveBackground,
            desaturatesIcons: !isGroupLoaded
        )
        .overlay {
            GeometryReader { geometry in
                let rects = EssentialSplitCompactLayout.rects(
                    in: geometry.size,
                    count: memberVisuals.count,
                    gap: PinnedTileMetrics.strokeWidth
                )
                ForEach(Array(memberVisuals.enumerated()), id: \.element.id) {
                    index, member in
                    if rects.indices.contains(index) {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(
                                width: rects[index].width,
                                height: rects[index].height
                            )
                            .position(
                                x: rects[index].midX,
                                y: rects[index].midY
                            )
                            .onTapGesture {
                                onActivateMember(member.id)
                            }
                            .sidebarAppKitContextMenu(
                                isInteractionEnabled: isAppKitInteractionEnabled,
                                surfaceKind: .button,
                                dragSource: dragSource(
                                    memberID: member.id,
                                    title: member.title,
                                    url: member.url,
                                    previewIcon: member.icon,
                                    previewSourceGeometry:
                                        SidebarDragPreviewSourceGeometry(
                                            size: geometry.size,
                                            localOrigin: CGPoint(
                                                x: rects[index].minX,
                                                y: geometry.size.height
                                                    - rects[index].maxY
                                            )
                                        )
                                ),
                                primaryAction: {
                                    onActivateMember(member.id)
                                },
                                onMiddleClick: supportsUnload
                                    ? onUnloadGroup : nil,
                                sourceID: "essential-split-member-\(member.persistentID.uuidString)",
                                entries: contextMenuEntries
                            )
                            .accessibilityIdentifier(
                                "essential-split-member-\(member.persistentID.uuidString)"
                            )
                    }
                }
            }
        }
    }

    private func groupIconTile(
        _ iconAsset: String,
        activationMember: EssentialSplitMemberVisual
    ) -> some View {
        PinnedTileVisual(
            tabIcon: Image(systemName:
                SumiPersistentGlyph.resolvedLauncherSystemImageName(iconAsset)
            ),
            glyphText: SumiPersistentGlyph.presentsAsEmoji(iconAsset)
                ? iconAsset : nil,
            presentationState: groupPresentationState,
            isHovered: false
        )
        .contentShape(Rectangle())
        .onTapGesture { onActivateMember(activationMember.id) }
        .sidebarAppKitContextMenu(
            isInteractionEnabled: isAppKitInteractionEnabled,
            surfaceKind: .button,
            dragSource: dragSource(
                memberID: activationMember.id,
                title: groupDisplayTitle,
                url: activationMember.url,
                previewIcon: nil
            ),
            primaryAction: { onActivateMember(activationMember.id) },
            onMiddleClick: supportsUnload ? onUnloadGroup : nil,
            sourceID: "essential-split-group-icon-\(group.id.uuidString)",
            entries: contextMenuEntries
        )
    }

    private var preferredActivationMember: EssentialSplitMemberVisual? {
        if let activeIndex = activeMemberIndex,
           memberVisuals.indices.contains(activeIndex) {
            return memberVisuals[activeIndex]
        }
        return memberVisuals.first
    }

    private var groupDisplayTitle: String {
        SplitGroupSidebarModel.displayTitle(for: group)
    }

    private var liveTabsByPinID: [UUID: Tab] {
        pinsByID.reduce(into: [:]) { result, entry in
            if let tab = selection.liveTab(for: entry.key, in: windowState) {
                result[entry.key] = tab
            }
        }
    }

    private var isGroupActive: Bool {
        selectionSnapshot.splitSelection?.groupID == group.id
    }

    private var isGroupLoaded: Bool {
        let shortcutMemberIDs = group.memberIDs.compactMap { memberID -> UUID? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return pinID
        }
        return !shortcutMemberIDs.isEmpty
            && shortcutMemberIDs.allSatisfy { liveTabsByPinID[$0] != nil }
    }

    private var groupPresentationState: ShortcutPresentationState {
        if isGroupActive { return .visuallySelected }
        return isGroupLoaded ? .liveBackgrounded : .launcherOnly
    }

    private var activeMemberIndex: Int? {
        guard isGroupActive,
              let memberID = selectionSnapshot.splitSelection?.activeMemberID
        else { return nil }
        return memberVisuals.firstIndex { $0.id == memberID }
    }

    private var memberVisuals: [EssentialSplitMemberVisual] {
        group.members.compactMap { member in
            guard case .shortcutPin(let pinID) = member.memberID,
                  let pin = pinsByID[pinID],
                  let item = SplitGroupSidebarItem.shortcut(
                    member,
                    pin: pin,
                    liveTab: liveTabsByPinID[pinID]
                  ) else { return nil }
            let liveTab = liveTabsByPinID[pinID]
            let presentation = SplitGroupMemberIconResolver.resolve(
                item: item,
                loadedStoredFavicon: storedFaviconLoader.image(
                    for: pin.launchURL,
                    partition: faviconPartition(for: pin)
                ),
                imageReader: faviconImageReader
            )
            return EssentialSplitMemberVisual(
                id: member.memberID,
                persistentID: pinID,
                title: liveTab?.name ?? pin.preferredDisplayTitle,
                url: liveTab?.url ?? pin.launchURL,
                icon: presentation.image,
                glyphText: presentation.glyphText,
                systemImageName: presentation.systemImageName,
                accentColor: loadedAccentColors[pinID]
                    ?? PinnedTileAccentResolver.resolve(
                    launchURL: liveTab?.url ?? pin.launchURL,
                    partition: .regular(
                        pin.executionProfileId ?? pin.profileId
                    ),
                    glyphText: pin.glyphText,
                    chromeTemplateSystemImageName:
                        pin.chromeTemplateSystemImageName,
                    tokens: tokens
                ),
                partition: .regular(
                    pin.executionProfileId ?? pin.profileId
                )
            )
        }
    }

    private var accentLoadKey: String {
        [
            isGroupActive ? "active" : "inactive",
            memberVisuals.map { $0.url.absoluteString }.joined(separator: "|"),
            accentRefreshID.uuidString,
        ].joined(separator: "|")
    }

    private var memberPins: [ShortcutPin] {
        group.memberIDs.compactMap { memberID in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return pinsByID[pinID]
        }
    }

    private var storedFaviconLoadKey: String {
        memberPins.map { pin in
            storedFaviconLoader.loadKey(
                launchURL: pin.launchURL,
                partition: faviconPartition(for: pin),
                isEnabled: pin.iconAsset == nil,
                disabledID: pin.id.uuidString
            )
        }.joined(separator: "|")
    }

    @MainActor
    private func loadStoredFavicons() async {
        for pin in memberPins where pin.iconAsset == nil {
            await storedFaviconLoader.load(
                launchURL: pin.launchURL,
                partition: faviconPartition(for: pin),
                imageReader: faviconImageReader,
                isCurrentLaunchURL: { pin.launchURL == $0 }
            )
            guard !Task.isCancelled else { return }
        }
    }

    private func faviconPartition(
        for pin: ShortcutPin
    ) -> SumiFaviconPartition {
        .regular(pin.executionProfileId ?? pin.profileId)
    }

    @MainActor
    private func loadAccentColorsIfNeeded() async {
        guard isGroupActive else { return }
        for member in memberVisuals where member.glyphText == nil
            && member.systemImageName == nil {
            if let cached = PinnedTileAccentResolver.cachedAccent(
                for: member.url,
                partition: member.partition
            ) {
                loadedAccentColors[member.persistentID] = cached
                continue
            }
            let cachedImage = TabFaviconStore.getCachedImage(
                forDocumentURL: member.url,
                partition: member.partition,
                context: .pinnedLauncher,
                imageReader: faviconImageReader
            )
            let image: NSImage?
            if let cachedImage {
                image = cachedImage
            } else {
                image = await TabFaviconStore.loadCachedLauncherImage(
                    forDocumentURL: member.url,
                    partition: member.partition,
                    imageReader: faviconImageReader
                )
            }
            guard !Task.isCancelled else { return }
            guard let image,
                  let accent = SumiFaviconAccentColor.extract(from: image)
            else { continue }
            PinnedTileAccentResolver.storeAccent(
                accent,
                for: member.url,
                partition: member.partition
            )
            loadedAccentColors[member.persistentID] = accent
        }
    }

    private func dragSource(
        memberID: SplitMemberID,
        title: String,
        url: URL,
        previewIcon: Image?,
        previewSourceGeometry: SidebarDragPreviewSourceGeometry? = nil
    ) -> SidebarDragSourceConfiguration {
        SidebarDragSourceConfiguration(
            item: .splitGroup(
                group.id,
                title: title,
                urlString: url.absoluteString
            ),
            sourceZone: .essentials,
            previewKind: .essentialsTile,
            previewIcon: group.iconAsset == nil ? previewIcon : nil,
            previewGlyphText: group.iconAsset.flatMap {
                SumiPersistentGlyph.presentsAsEmoji($0) ? $0 : nil
            },
            splitPresentation: group.iconAsset == nil
                ? splitDragPresentation : nil,
            chromeTemplateSystemImageName: group.iconAsset.flatMap {
                SumiPersistentGlyph.presentsAsEmoji($0)
                    ? nil
                    : SumiPersistentGlyph.resolvedLauncherSystemImageName($0)
            },
            previewPresentationState: groupPresentationState,
            previewSourceGeometry: previewSourceGeometry,
            exclusionZones: [],
            onActivate: { onActivateMember(memberID) },
            isEnabled: isAppKitInteractionEnabled
        )
    }

    private var splitDragPresentation: SidebarSplitDragPresentation {
        SidebarSplitDragPresentation(
            members: memberVisuals.map { member in
                SidebarSplitDragPresentation.Member(
                    icon: member.icon,
                    glyphText: member.glyphText,
                    systemImageName: member.systemImageName,
                    accentColor: member.accentColor,
                    title: member.title
                )
            }
        )
    }

    private var supportsUnload: Bool {
        liveTabsByPinID.isEmpty == false
    }

    private func contextMenuEntries() -> [SidebarContextMenuEntry] {
        SplitGroupContextMenuFactory.entries(
            for: group,
            members: group.memberIDs.compactMap { memberID in
                guard case .shortcutPin(let pinID) = memberID,
                      let pin = pinsByID[pinID] else { return nil }
                let liveTab = liveTabsByPinID[pinID]
                return SplitGroupContextMenuMember(
                    id: memberID,
                    title: liveTab?.name ?? pin.preferredDisplayTitle,
                    url: liveTab?.url ?? pin.launchURL
                )
            },
            splitLayout: splitLayout,
            emptySplitCreation: emptySplitCreation,
            windowState: windowState,
            actions: resolvedGroupContextMenuActions
        )
    }

    private var resolvedGroupContextMenuActions: SplitGroupContextMenuActions {
        var actions = groupContextMenuActions
        actions.edit = {
            groupEditor.show(
                group,
                in: windowState,
                themeContext: themeContext
            )
        }
        actions.duplicate = {
            groupEditor.duplicate(group, in: windowState)
        }
        actions.moveTo = groupEditor.moveMenuEntries(
            for: group,
            in: windowState
        )
        if group.memberIDs.count < SplitGroup.maximumMembers,
           let activationMember = preferredActivationMember {
            actions.addTab = {
                onActivateMember(activationMember.id)
                _ = emptySplitCreation.create(
                    side: .right,
                    in: windowState,
                    reason: .splitTabPicker
                )
            }
        }
        if let delete = actions.delete {
            actions.delete = {
                groupEditor.confirmDelete(
                    group,
                    in: windowState,
                    themeContext: themeContext,
                    onDelete: delete
                )
            }
        }
        return actions
    }

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }
}

private struct EssentialSplitMemberVisual: Identifiable {
    let id: SplitMemberID
    let persistentID: UUID
    let title: String
    let url: URL
    let icon: Image
    let glyphText: String?
    let systemImageName: String?
    let accentColor: Color
    let partition: SumiFaviconPartition
}

enum EssentialSplitCompactLayout {
    static func rects(
        in size: CGSize,
        count: Int,
        gap: CGFloat
    ) -> [CGRect] {
        let width = max(0, size.width)
        let height = max(0, size.height)
        let halfWidth = max(0, (width - gap) / 2)
        let halfHeight = max(0, (height - gap) / 2)
        switch count {
        case 2:
            return [
                CGRect(x: 0, y: 0, width: halfWidth, height: height),
                CGRect(
                    x: halfWidth + gap,
                    y: 0,
                    width: halfWidth,
                    height: height
                ),
            ]
        case 3:
            return [
                CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight),
                CGRect(
                    x: 0,
                    y: halfHeight + gap,
                    width: halfWidth,
                    height: halfHeight
                ),
                CGRect(
                    x: halfWidth + gap,
                    y: 0,
                    width: halfWidth,
                    height: height
                ),
            ]
        case 4:
            return [
                CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight),
                CGRect(
                    x: halfWidth + gap,
                    y: 0,
                    width: halfWidth,
                    height: halfHeight
                ),
                CGRect(
                    x: 0,
                    y: halfHeight + gap,
                    width: halfWidth,
                    height: halfHeight
                ),
                CGRect(
                    x: halfWidth + gap,
                    y: halfHeight + gap,
                    width: halfWidth,
                    height: halfHeight
                ),
            ]
        default:
            return count == 1
                ? [CGRect(origin: .zero, size: size)] : []
        }
    }
}

struct EssentialSplitCompactChromeGeometry {
    let outerRect: CGRect
    let dividerRects: [CGRect]

    static func resolve(
        in size: CGSize,
        count: Int,
        thickness: CGFloat
    ) -> EssentialSplitCompactChromeGeometry {
        let width = max(0, size.width)
        let height = max(0, size.height)
        let lineWidth = max(0, min(thickness, min(width, height)))
        let vertical = CGRect(
            x: (width - lineWidth) / 2,
            y: 0,
            width: lineWidth,
            height: height
        )
        let fullHorizontal = CGRect(
            x: 0,
            y: (height - lineWidth) / 2,
            width: width,
            height: lineWidth
        )
        let leftHorizontal = CGRect(
            x: 0,
            y: (height - lineWidth) / 2,
            width: (width + lineWidth) / 2,
            height: lineWidth
        )
        let dividers: [CGRect] = switch count {
        case 2: [vertical]
        case 3: [vertical, leftHorizontal]
        case 4: [vertical, fullHorizontal]
        default: []
        }
        return EssentialSplitCompactChromeGeometry(
            outerRect: CGRect(x: 0, y: 0, width: width, height: height),
            dividerRects: dividers
        )
    }
}

struct EssentialSplitCompactVisual: View {
    let icons: [Image]
    var glyphTexts: [String?] = []
    var systemImageNames: [String?] = []
    var accentColors: [Color] = []
    var isGroupActive: Bool
    var cornerRadius: CGFloat = PinnedTileMetrics.cornerRadius
    var idleBackground: Color = Color(nsColor: .controlBackgroundColor)
    var activeBackground: Color = Color.accentColor.opacity(0.12)
    var desaturatesIcons = false

    var body: some View {
        GeometryReader { geometry in
            let rects = EssentialSplitCompactLayout.rects(
                in: geometry.size,
                count: min(icons.count, SplitGroup.maximumMembers),
                gap: PinnedTileMetrics.strokeWidth
            )
            ZStack {
                ForEach(Array(rects.enumerated()), id: \.offset) { index, rect in
                    Rectangle()
                        .fill(isGroupActive ? activeBackground : idleBackground)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    compactIcon(at: index)
                        .saturation(desaturatesIcons ? 0 : 1)
                        .opacity(desaturatesIcons ? 0.8 : 1)
                        .position(x: rect.midX, y: rect.midY)
                }

                if isGroupActive {
                    let accentMesh = EssentialSplitAccentMesh.resolve(
                        in: geometry.size,
                        memberRects: rects
                    )
                    EssentialSplitChromeMask(
                        memberCount: rects.count,
                        cornerRadius: cornerRadius,
                        thickness: PinnedTileMetrics.strokeWidth
                    )
                    .fill(MeshGradient(
                        width: accentMesh.width,
                        height: accentMesh.height,
                        points: accentMesh.points,
                        colors: accentMesh.colorIndices.map { index in
                            resolvedAccentColor(at: index)
                        }
                    ))
                    .allowsHitTesting(false)
                }
            }
        }
        .clipShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    @ViewBuilder
    private func compactIcon(at index: Int) -> some View {
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
            icons[index]
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .clipShape(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
        }
    }

    private func resolvedAccentColor(at index: Int) -> Color {
        accentColors.indices.contains(index)
            ? accentColors[index] : .accentColor
    }
}

struct EssentialSplitAccentMesh {
    let width: Int
    let height: Int
    let points: [SIMD2<Float>]
    let colorIndices: [Int]

    static func resolve(
        in size: CGSize,
        memberRects: [CGRect]
    ) -> EssentialSplitAccentMesh {
        guard size.width > 0, size.height > 0, !memberRects.isEmpty else {
            return EssentialSplitAccentMesh(
                width: 2,
                height: 2,
                points: [
                    SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
                    SIMD2<Float>(0, 1), SIMD2<Float>(1, 1),
                ],
                colorIndices: [0, 0, 0, 0]
            )
        }

        let centers = memberRects.map { rect in
            CGPoint(
                x: rect.midX / size.width,
                y: rect.midY / size.height
            )
        }
        let xPositions = meshAxisPositions(centers.map(\.x))
        let yPositions = meshAxisPositions(centers.map(\.y))
        let points = yPositions.flatMap { y in
            xPositions.map { x in SIMD2<Float>(Float(x), Float(y)) }
        }
        let colorIndices = points.map { point in
            nearestCenterIndex(
                to: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)),
                centers: centers
            )
        }
        return EssentialSplitAccentMesh(
            width: xPositions.count,
            height: yPositions.count,
            points: points,
            colorIndices: colorIndices
        )
    }

    private static func meshAxisPositions(
        _ memberPositions: [CGFloat]
    ) -> [CGFloat] {
        Array(Set([0, 0.5, 1] + memberPositions)).sorted()
    }

    private static func nearestCenterIndex(
        to point: CGPoint,
        centers: [CGPoint]
    ) -> Int {
        centers.indices.min { lhs, rhs in
            squaredDistance(from: point, to: centers[lhs])
                < squaredDistance(from: point, to: centers[rhs])
        } ?? 0
    }

    private static func squaredDistance(
        from first: CGPoint,
        to second: CGPoint
    ) -> CGFloat {
        let deltaX = first.x - second.x
        let deltaY = first.y - second.y
        return deltaX * deltaX + deltaY * deltaY
    }
}

private struct EssentialSplitChromeMask: Shape {
    let memberCount: Int
    let cornerRadius: CGFloat
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        let geometry = EssentialSplitCompactChromeGeometry.resolve(
            in: rect.size,
            count: memberCount,
            thickness: thickness
        )
        var result = Path()
        let outerRect = geometry.outerRect
            .offsetBy(dx: rect.minX, dy: rect.minY)
            .insetBy(dx: thickness / 2, dy: thickness / 2)
        let resolvedCornerRadius = min(
            cornerRadius,
            min(outerRect.width, outerRect.height) / 2
        )
        let outerStroke = Path(
            roundedRect: outerRect,
            cornerRadius: resolvedCornerRadius
        ).strokedPath(StrokeStyle(lineWidth: thickness))
        result.addPath(outerStroke)
        for dividerRect in geometry.dividerRects {
            result.addRect(
                dividerRect.offsetBy(dx: rect.minX, dy: rect.minY)
            )
        }
        return result
    }
}
