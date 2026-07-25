import SumiDomain
import SwiftUI

struct EssentialSplitGroupTile: View {
    let group: SplitGroup
    let pinsByID: [UUID: ShortcutPin]
    let selection: SidebarWindowSelectionQuery
    let selectionSnapshot: SidebarWindowSelectionSnapshot
    let faviconImageReader: any BrowserFaviconImageReading
    let essentialBackdropReader: any BrowserEssentialBackdropReading
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
    @State private var backdropLoader = SidebarEssentialBackdropLoader()

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
        .task(id: backdropLoadKey) {
            await loadBackdrops()
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
        .onReceive(
            NotificationCenter.default.publisher(for: .essentialBackdropUpdated)
        ) { notification in
            for pin in memberPins where pin.iconAsset == nil {
                backdropLoader.invalidateIfNeeded(
                    for: notification,
                    launchURL: pin.launchURL,
                    partition: faviconPartition(for: pin)
                )
            }
        }
    }

    private var memberCompositionTile: some View {
        EssentialSplitCompactVisual(
            members: splitTileMembers,
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
                let rects = SplitTileGeometry.resolve(
                    in: geometry.size,
                    count: memberVisuals.count,
                    thickness: PinnedTileMetrics.strokeWidth
                ).contentRects
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
                ),
                backdrop: backdropImage(for: pin)
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

    private var backdropLoadKey: String {
        memberPins.map { pin in
            backdropLoader.loadKey(
                launchURL: pin.launchURL,
                partition: faviconPartition(for: pin),
                isEnabled: isGroupActive
                    && pin.iconAsset == nil
                    && pin.glyphText == nil
                    && pin.chromeTemplateSystemImageName == nil
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

    @MainActor
    private func loadBackdrops() async {
        guard isGroupActive else { return }
        for pin in memberPins where pin.iconAsset == nil
            && pin.glyphText == nil
            && pin.chromeTemplateSystemImageName == nil {
            await backdropLoader.load(
                launchURL: pin.launchURL,
                partition: faviconPartition(for: pin),
                reader: essentialBackdropReader,
                isCurrentLaunchURL: { pin.launchURL == $0 }
            )
            guard !Task.isCancelled else { return }
        }
    }

    private func backdropImage(for pin: ShortcutPin) -> Image? {
        guard pin.iconAsset == nil,
              pin.glyphText == nil,
              pin.chromeTemplateSystemImageName == nil
        else { return nil }
        let partition = faviconPartition(for: pin)
        if let loaded = backdropLoader.image(
            for: pin.launchURL,
            partition: partition
        ) {
            return loaded
        }
        return essentialBackdropReader.cachedBackdrop(
            for: pin.launchURL,
            partition: partition
        ).map(Image.init(nsImage:))
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
        SidebarSplitDragPresentation(members: splitTileMembers)
    }

    private var splitTileMembers: [EssentialSplitTileMemberPresentation] {
        memberVisuals.map { member in
            EssentialSplitTileMemberPresentation(
                icon: member.icon,
                glyphText: member.glyphText,
                systemImageName: member.systemImageName,
                accentColor: member.accentColor,
                title: member.title,
                backdrop: member.backdrop
            )
        }
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
    let backdrop: Image?
}

struct EssentialSplitCompactVisual: View {
    let members: [EssentialSplitTileMemberPresentation]
    var isGroupActive: Bool
    var cornerRadius: CGFloat = PinnedTileMetrics.cornerRadius
    var idleBackground: Color = Color(nsColor: .controlBackgroundColor)
    var activeBackground: Color = Color.accentColor.opacity(0.12)
    var desaturatesIcons = false

    var body: some View {
        GeometryReader { geometry in
            let splitGeometry = SplitTileGeometry.resolve(
                in: geometry.size,
                count: min(members.count, SplitGroup.maximumMembers),
                thickness: PinnedTileMetrics.strokeWidth
            )
            let rects = splitGeometry.contentRects
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
                    ZStack {
                        ForEach(Array(splitGeometry.materialRects.enumerated()), id: \.offset) {
                            index, rect in
                            splitChromeSource(at: index, rect: rect)
                        }
                    }
                    .mask {
                        EssentialSplitChromeMask(
                            memberCount: rects.count,
                            cornerRadius: cornerRadius,
                            thickness: PinnedTileMetrics.strokeWidth
                        )
                    }
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
        if members.indices.contains(index),
           let glyph = members[index].glyphText {
            Text(glyph)
                .font(.system(size: 16))
                .frame(width: 16, height: 16)
        } else if members.indices.contains(index),
                  let systemName = members[index].systemImageName {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .frame(width: 16, height: 16)
        } else {
            members[index].icon
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .clipShape(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
        }
    }

    private func resolvedAccentColor(at index: Int) -> Color {
        members.indices.contains(index)
            ? members[index].accentColor : .accentColor
    }

    @ViewBuilder
    private func splitChromeSource(at index: Int, rect: CGRect) -> some View {
        if members.indices.contains(index), let backdrop = members[index].backdrop {
            backdrop
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .scaleEffect(1.12)
                .frame(width: rect.width, height: rect.height)
                .clipped()
                .position(x: rect.midX, y: rect.midY)
        } else {
            Rectangle()
                .fill(resolvedAccentColor(at: index))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }
}

private struct EssentialSplitChromeMask: View {
    let memberCount: Int
    let cornerRadius: CGFloat
    let thickness: CGFloat

    var body: some View {
        GeometryReader { geometryProxy in
            let geometry = SplitTileGeometry.resolve(
                in: geometryProxy.size,
                count: memberCount,
                thickness: thickness
            )
            ZStack {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    SidebarThemeTokens.Colors.opaqueMask,
                    lineWidth: thickness
                )

                ForEach(
                    Array(geometry.dividerRects.enumerated()),
                    id: \.offset
                ) { _, rect in
                    Rectangle()
                        .fill(SidebarThemeTokens.Colors.opaqueMask)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
    }
}
