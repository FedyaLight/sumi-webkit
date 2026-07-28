import SumiDomain
import SwiftUI

struct ShortcutHostedSplitGroupRow: View {
    let group: SplitGroup
    let items: [SplitGroupSidebarItem]
    let spaceId: UUID
    let splitLayout: SplitLayoutService
    let emptySplitCreation: EmptySplitCreationWorkflow
    let groupEditor: SidebarSplitGroupEditorPresentationService
    let groupContextMenuActions: SplitGroupContextMenuActions
    let isAppKitInteractionEnabled: Bool
    let faviconImageReader: any BrowserFaviconImageReading
    let accessibilityID: String
    let onActivateMember: (SplitMemberID) -> Void
    let onUnloadGroup: () -> Void
    let onCloseGroup: () -> Void

    init(
        group: SplitGroup,
        items: [SplitGroupSidebarItem],
        spaceId: UUID,
        splitLayout: SplitLayoutService,
        emptySplitCreation: EmptySplitCreationWorkflow,
        groupEditor: SidebarSplitGroupEditorPresentationService,
        groupContextMenuActions: SplitGroupContextMenuActions,
        isAppKitInteractionEnabled: Bool,
        faviconImageReader: any BrowserFaviconImageReading,
        accessibilityID: String,
        onActivateMember: @escaping (SplitMemberID) -> Void,
        onUnloadGroup: @escaping () -> Void,
        onCloseGroup: @escaping () -> Void
    ) {
        self.group = group
        self.items = items
        self.spaceId = spaceId
        self.splitLayout = splitLayout
        self.emptySplitCreation = emptySplitCreation
        self.groupEditor = groupEditor
        self.groupContextMenuActions = groupContextMenuActions
        self.isAppKitInteractionEnabled = isAppKitInteractionEnabled
        self.faviconImageReader = faviconImageReader
        self.accessibilityID = accessibilityID
        self.onActivateMember = onActivateMember
        self.onUnloadGroup = onUnloadGroup
        self.onCloseGroup = onCloseGroup
    }

    var body: some View {
        SplitGroupSidebarRow(
            group: group,
            items: items,
            spaceId: spaceId,
            isAppKitInteractionEnabled: isAppKitInteractionEnabled,
            faviconImageReader: faviconImageReader,
            splitLayout: splitLayout,
            emptySplitCreation: emptySplitCreation,
            groupEditor: groupEditor,
            groupContextMenuActions: groupContextMenuActions,
            groupAction: SplitGroupSidebarModel.rowAction(
                for: group,
                items: items
            ),
            dragSource: shortcutHostedSplitSegmentDragSource,
            contextMenuEntries: { _ in [] },
            onActivateMember: onActivateMember,
            onGroupAction: performGroupAction
        )
        .accessibilityIdentifier(accessibilityID)
    }

    private func performGroupAction(_ action: SplitGroupSidebarAction) {
        switch action {
        case .unload:
            onUnloadGroup()
        case .close:
            onCloseGroup()
        }
    }

    private func shortcutHostedSplitSegmentDragSource(
        for item: SplitGroupSidebarItem
    ) -> SidebarDragSourceConfiguration? {
        let memberIcon = iconPresentation(for: item)
        if let pin = item.pin {
            return SidebarDragSourceConfiguration(
                item: SumiDragItem.splitGroup(
                    group.id,
                    title: item.title,
                    urlString: item.tab?.url.absoluteString
                        ?? pin.launchURL.absoluteString
                ),
                sourceZone: sourceZone,
                previewKind: .row,
                previewIcon: groupPreviewIcon ?? memberIcon.image,
                previewGlyphText: groupPreviewGlyph,
                splitPresentation: group.iconAsset == nil
                    ? splitDragPresentation : nil,
                chromeTemplateSystemImageName: groupPreviewSystemImage,
                previewPresentationState: groupPresentationState,
                exclusionZones: [.trailingStrip(32)],
                isEnabled: isAppKitInteractionEnabled
            )
        }

        guard let tab = item.tab else { return nil }
        return SidebarDragSourceConfiguration(
            item: SumiDragItem.splitGroup(
                group.id,
                title: tab.name,
                urlString: tab.url.absoluteString
            ),
            sourceZone: sourceZone,
            previewKind: .row,
            previewIcon: groupPreviewIcon ?? memberIcon.image,
            previewGlyphText: groupPreviewGlyph,
            splitPresentation: group.iconAsset == nil
                ? splitDragPresentation : nil,
            chromeTemplateSystemImageName: groupPreviewSystemImage,
            previewPresentationState: groupPresentationState,
            exclusionZones: [.trailingStrip(32)],
            isEnabled: isAppKitInteractionEnabled
        )
    }

    private var splitDragPresentation: SidebarSplitDragPresentation {
        SidebarSplitDragPresentation(
            members: zip(items, iconPresentations).map { item, icon in
                SidebarSplitDragPresentation.Member(
                    icon: icon.image,
                    glyphText: icon.glyphText,
                    systemImageName: icon.systemImageName,
                    accentColor: accentColor(for: item),
                    title: item.title
                )
            }
        )
    }

    private var iconPresentations: [SplitGroupMemberIconPresentation] {
        items.map(iconPresentation)
    }

    private func iconPresentation(
        for item: SplitGroupSidebarItem
    ) -> SplitGroupMemberIconPresentation {
        SplitGroupMemberIconResolver.resolve(
            item: item,
            loadedStoredFavicon: nil,
            imageReader: faviconImageReader
        )
    }

    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    private func accentColor(for item: SplitGroupSidebarItem) -> Color {
        let pin = item.pin
        return PinnedTileAccentResolver.resolve(
            launchURL: item.tab?.url ?? pin?.launchURL,
            partition: pin.map {
                .regular($0.executionProfileId ?? $0.profileId)
            },
            glyphText: pin?.glyphText,
            chromeTemplateSystemImageName:
                pin?.chromeTemplateSystemImageName,
            tokens: tokens
        )
    }

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    private var groupPresentationState: ShortcutPresentationState {
        if sidebarSelection.splitSelection?.groupID == group.id {
            return .visuallySelected
        }
        return !items.isEmpty && items.allSatisfy { $0.tab != nil }
            ? .liveBackgrounded : .launcherOnly
    }

    private var groupPreviewGlyph: String? {
        group.iconAsset.flatMap {
            SumiPersistentGlyph.presentsAsEmoji($0) ? $0 : nil
        }
    }

    private var groupPreviewSystemImage: String? {
        group.iconAsset.flatMap {
            SumiPersistentGlyph.presentsAsEmoji($0)
                ? nil : SumiPersistentGlyph.resolvedLauncherSystemImageName($0)
        }
    }

    private var groupPreviewIcon: Image? {
        groupPreviewSystemImage.map(Image.init(systemName:))
    }

    private var sourceZone: DropZoneID {
        switch group.container {
        case .regularTabs(let groupSpaceID):
            return .spaceRegular(groupSpaceID ?? spaceId)
        case .essentialSidebar:
            return .essentials
        case .shortcutSidebar(let groupSpaceID, _, let folderID, _):
            return folderID.map(DropZoneID.folder)
                ?? .spacePinned(groupSpaceID)
        }
    }
}
